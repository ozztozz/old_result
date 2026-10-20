#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tyf_live_worker.py
==================
TYF Canlı yarış sayfasını (canli.tyf.gov.tr/...) periyodik olarak tarar.
1. Yarıştan 1 gün önce yayınlanan Start Listelerini (StartList_*.pdf) algılar,
   seri, kulvar ve giriş derecesi bilgilerini Django API'sine aktarır.
2. Yarış günü yayınlanan Sonuç Listelerini (ResultList_*.pdf) algılar,
   sıra, derece ve puan bilgilerini Django API'sine aktararak günceller.
3. Taranmış (resim) PDF tespit edilirse Tesseract OCR devreye girer.
4. 'processed_files.json' ile zaten aktarılmış dosyaları hatırlar, mükerrer veri göndermez.
"""

import os
import sys
import re
import json
import ssl
import time
import argparse
import difflib
import urllib.request
import urllib.parse
from typing import Dict, List, Any, Optional

try:
    import fitz  # PyMuPDF
except ImportError:
    fitz = None

try:
    import pytesseract
    from PIL import Image
    import io
    if os.name == 'nt' and os.path.exists(r"C:\Program Files\Tesseract-OCR\tesseract.exe"):
        pytesseract.pytesseract.tesseract_cmd = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
except ImportError:
    pytesseract = None

DEFAULT_TYF_URL = "https://canli.tyf.gov.tr/ankara/cs-1005675/"
DEFAULT_API_URL = "http://127.0.0.1:8000/api/canli-aktar/"
STATE_FILE = "processed_files.json"


def normalize_tr(s: str) -> str:
    """Türkçe karakterleri ve boşlukları eşleştirme için normalize eder."""
    if not s:
        return ""
    mapping = {
        'İ': 'I', 'ı': 'i', 'I': 'I', 'i': 'i',
        'Ş': 'S', 'ş': 's',
        'Ğ': 'G', 'ğ': 'g',
        'Ü': 'U', 'ü': 'u',
        'Ö': 'O', 'ö': 'o',
        'Ç': 'C', 'ç': 'c'
    }
    return re.sub(r'\s+', ' ', ''.join(mapping.get(ch, ch) for ch in s.strip().upper()))


def match_swimmer_to_start_list(res_name: str, start_entries: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """
    Sonuç listesindeki sporcuyu (kısaltma veya OCR hatası olsa dahi)
    start listesindeki güvenilir sporcu kayıtlarıyla eşleştirir.
    """
    if not res_name or not start_entries:
        return None

    r_norm = normalize_tr(res_name)

    # 1. Birebir tam eşleşme
    for entry in start_entries:
        sp_name = entry.get('sporcu') or entry.get('name') or ''
        if normalize_tr(sp_name) == r_norm:
            return entry

    # 2. Önek / Kısaltma eşleşmesi (örn: 'Muharrem Kaan S.' -> 'Muharrem Kaan SELAMOĞLU')
    prefix = r_norm.rstrip('.').strip()
    p_matches = [
        entry for entry in start_entries 
        if normalize_tr(entry.get('sporcu') or entry.get('name') or '').startswith(prefix)
    ]
    if len(p_matches) == 1:
        return p_matches[0]

    # 3. Benzerlik / OCR toleransı (Fuzzy Match >= 0.75)
    best_entry = None
    best_score = 0.0
    for entry in start_entries:
        sp_name = entry.get('sporcu') or entry.get('name') or ''
        score = difflib.SequenceMatcher(None, r_norm, normalize_tr(sp_name)).ratio()
        if score > best_score:
            best_score = score
            best_entry = entry

    if best_score >= 0.75:
        return best_entry

    return None


def get_ssl_context():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def fetch_url(url: str, timeout: int = 15) -> bytes:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
    )
    with urllib.request.urlopen(req, context=get_ssl_context(), timeout=timeout) as resp:
        return resp.read()


def load_state() -> Dict[str, Any]:
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"processed": {}}


def save_state(state: Dict[str, Any]):
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)


def extract_header_info(lines: List[str]) -> Dict[str, Any]:
    info = {
        "musabaka_adi": "",
        "sehir": "",
        "tarih": "",
        "yaris_no": "",
        "cinsiyet": "",
        "mesafe": None,
        "stil": "",
        "yas_grubu": ""
    }
    for i, l in enumerate(lines[:20]):
        if "Yarış " in l:
            m = re.search(r"Yarış\s+(\d+)", l)
            if m:
                info["yaris_no"] = m.group(1)
            if i > 0:
                info["sehir"] = lines[i-1].split(",")[0].strip()
            if i > 1:
                info["musabaka_adi"] = lines[i-2].strip()
            if i + 1 < len(lines):
                event_line = lines[i+1]
                if "Erkek" in event_line:
                    info["cinsiyet"] = "Erkek"
                elif any(k in event_line for k in ["Kız", "Bayan", "Kadın"]):
                    info["cinsiyet"] = "Kadın"
                m_dist = re.search(r"(\d+)\s*m", event_line)
                if m_dist:
                    info["mesafe"] = int(m_dist.group(1))
                for s in ["Serbest", "Sırtüstü", "Kurbağalama", "Kelebek", "Karışık"]:
                    if s.lower() in event_line.lower():
                        info["stil"] = s
                        break
            if i + 2 < len(lines):
                info["yas_grubu"] = lines[i+2].strip()
            if i + 3 < len(lines):
                m_date = re.search(r"(\d{1,2}\.\d{1,2}\.\d{4})", lines[i+3])
                if m_date:
                    d_raw = m_date.group(1)
                    parts = d_raw.split(".")
                    if len(parts) == 3:
                        info["tarih"] = f"{parts[2]}-{int(parts[1]):02d}-{int(parts[0]):02d}"
                    else:
                        info["tarih"] = d_raw
            break
    return info


def parse_start_list_pdf(pdf_bytes: bytes) -> Dict[str, Any]:
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    lines_p1 = [l.strip() for l in doc[0].get_text().splitlines() if l.strip()]
    header = extract_header_info(lines_p1)

    current_heat = None
    kayitlar = []

    for page in doc:
        lines = [l.strip() for l in page.get_text().splitlines() if l.strip()]
        i = 0
        while i < len(lines):
            line = lines[i]
            if line.startswith("Seri "):
                current_heat = line
                i += 1
                continue

            m_lane = re.match(r"^([1-8])\s+([A-ZÇĞİÖŞÜa-zçğıöşü\s]+)$", line)
            if m_lane:
                lane = int(m_lane.group(1))
                name = m_lane.group(2).strip()
                if i + 3 < len(lines):
                    yb = lines[i+1]
                    club = lines[i+2]
                    seed_time = lines[i+3]
                    kayitlar.append({
                        "seri": current_heat,
                        "kulvar": lane,
                        "sporcu": name,
                        "dogum_yili": yb,
                        "kulup": club,
                        "giris_derecesi": seed_time
                    })
                    i += 3
            i += 1

    return {
        "tur": "start_listesi",
        **header,
        "kayitlar": kayitlar
    }


def parse_result_list_pdf(pdf_bytes: bytes, start_entries: Optional[List[Dict[str, Any]]] = None) -> Dict[str, Any]:
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    lines_p1 = [l.strip() for l in doc[0].get_text().splitlines() if l.strip()]
    header = extract_header_info(lines_p1)

    # Text kontrolü: Eğer sayfa metin içermiyorsa OCR fallback
    total_text = "".join(p.get_text() for p in doc)
    if len(total_text.strip()) < 100 and pytesseract:
        print("[!] Metin PDF bulunamadı, Tesseract OCR ile taranıyor...")
        return parse_scanned_pdf_ocr(doc, header, start_entries)

    current_age_group = None
    kayitlar = []

    for page in doc:
        lines = [l.strip() for l in page.get_text().splitlines() if l.strip()]
        i = 0
        while i < len(lines):
            line = lines[i]
            if re.match(r"^\d+\s*yaş$", line, re.I):
                current_age_group = line
                i += 1
                continue

            # Sıra + İsim aynı satırda mı, yoksa ayrı satırlarda mı?
            m_combined = re.match(r"^(\d+)\.\s+([A-ZÇĞİÖŞÜa-zçğıöşü\s\.\'\-]+)$", line)
            m_alone = re.match(r"^(\d+)\.$", line)

            rank = None
            name = None
            next_idx = i + 1

            if m_combined:
                rank = m_combined.group(1)
                name = m_combined.group(2).strip()
            elif m_alone and i + 1 < len(lines):
                rank = m_alone.group(1)
                name = lines[i+1].strip()
                next_idx = i + 2

            if rank and name and next_idx < len(lines):
                yb = lines[next_idx]
                club_raw = lines[next_idx + 1] if next_idx + 1 < len(lines) else ""
                
                club = club_raw
                time_val = None
                points_val = None

                # Durum 1: Kulüp satırının sonuna derece ve puan yapışmış olabilir (örn: 'Vamos SK 3:17.40 338' veya '...Kulübü1:35.61')
                m_club_time = re.match(r"^(.*?)(?:\s*|\b)((?:\d+:)?\d{2}\.\d{2})(?:\s+(\d+))?$", club_raw)
                if m_club_time and len(m_club_time.group(1).strip()) >= 3:
                    club = m_club_time.group(1).strip()
                    time_val = m_club_time.group(2).strip()
                    points_val = m_club_time.group(3)
                else:
                    # Durum 2: Derece sonraki satırlarda yer alıyor
                    for j in range(next_idx + 2, min(next_idx + 8, len(lines))):
                        m_tp = re.match(r"^((?:\d+:)?\d{2}\.\d{2})\s+(\d+)$", lines[j])
                        if m_tp:
                            time_val = m_tp.group(1)
                            points_val = m_tp.group(2)
                            break
                        m_t = re.match(r"^(?:\d+:)?\d{2}\.\d{2}$", lines[j])
                        if m_t:
                            time_val = m_t.group(0)
                            if j + 1 < len(lines) and re.match(r"^\d+$", lines[j+1]):
                                points_val = lines[j+1]
                            break

                if time_val:
                    seri = None
                    kulvar = None
                    giris_derecesi = None

                    # Start listesindeki güvenilir sporcularla eşleştir
                    if start_entries:
                        st_match = match_swimmer_to_start_list(name, start_entries)
                        if st_match:
                            name = st_match.get("sporcu") or name
                            club = st_match.get("kulup") or club
                            seri = st_match.get("seri")
                            kulvar = st_match.get("kulvar")
                            giris_derecesi = st_match.get("giris_derecesi")

                    kayitlar.append({
                        "sira": rank,
                        "sporcu": name,
                        "dogum_yili": yb,
                        "kulup": club,
                        "derece": time_val,
                        "puan": points_val,
                        "yas_grubu": current_age_group,
                        "seri": seri,
                        "kulvar": kulvar,
                        "giris_derecesi": giris_derecesi
                    })
                    i = next_idx + 1
            i += 1

    return {
        "tur": "sonuc_listesi",
        **header,
        "kayitlar": kayitlar
    }


def match_ocr_line(line_prefix: str, candidates: List[str]) -> Optional[str]:
    """OCR satır önekini start listesindeki sporcu adlarıyla eşleştirir."""
    p_norm = normalize_tr(line_prefix)
    p_norm = re.sub(r'^\d+[\.\s]+', '', p_norm).strip()

    # 1. Birebir startswith kontrolü
    for c in candidates:
        c_norm = normalize_tr(c)
        if p_norm.startswith(c_norm):
            return c

    # 2. Kelime benzerliği toleransı (Fuzzy Match >= 0.70)
    words = p_norm.split()
    best_c, best_score = None, 0.0
    for c in candidates:
        c_norm = normalize_tr(c)
        c_len = len(c_norm.split())
        line_part = ' '.join(words[:c_len])
        score = difflib.SequenceMatcher(None, line_part, c_norm).ratio()
        if score > best_score:
            best_score = score
            best_c = c

    if best_score >= 0.70:
        return best_c
    return None


def parse_scanned_pdf_ocr(doc, header: Dict[str, Any], start_entries: Optional[List[Dict[str, Any]]] = None) -> Dict[str, Any]:
    kayitlar = []
    candidates_map = {e['sporcu']: e for e in start_entries} if start_entries else {}
    candidates = list(candidates_map.keys())

    for page_num, page in enumerate(doc):
        # 300 DPI yüksek çözünürlük ile render al
        pix = page.get_pixmap(dpi=300)
        img = Image.open(io.BytesIO(pix.tobytes("png")))
        # --psm 6 satır hizalamasını koruyarak tablo satırlarını birleştirir
        ocr_text = pytesseract.image_to_string(img, lang="tur", config="--psm 6")

        for line in ocr_text.splitlines():
            line = line.strip()
            # Satır sonunda geçerli bir derece var mı? (örn: 28.32 veya 1:05.40 580)
            m_time = re.search(r'((?:\d+:)?\d{2}\.\d{2})(?:\s+(\d+))?$', line)
            if not m_time:
                continue

            time_val = m_time.group(1)
            pts_val = m_time.group(2)
            prefix = line[:m_time.start()].strip()

            m_rank = re.match(r'^(\d+)[\.\s]+', prefix)
            rank_val = m_rank.group(1) if m_rank else None

            matched_name = match_ocr_line(prefix, candidates) if candidates else None

            if matched_name:
                st = candidates_map[matched_name]
                kayitlar.append({
                    "sira": rank_val,
                    "sporcu": matched_name,
                    "dogum_yili": st.get("dogum_yili"),
                    "kulup": st.get("kulup"),
                    "derece": time_val,
                    "puan": pts_val,
                    "seri": st.get("seri"),
                    "kulvar": st.get("kulvar"),
                    "giris_derecesi": st.get("giris_derecesi")
                })
            else:
                # Eşleşmeyen durumlarda genel regex fallback
                clean_pref = re.sub(r'^\d+[\.\s]+', '', prefix).strip()
                kayitlar.append({
                    "sira": rank_val,
                    "sporcu": clean_pref,
                    "kulup": "Bilinmiyor",
                    "derece": time_val,
                    "puan": pts_val
                })

    return {
        "tur": "sonuc_listesi",
        **header,
        "kayitlar": kayitlar
    }


def post_to_django(api_url: str, payload: Dict[str, Any], api_key: Optional[str] = None) -> bool:
    data_json = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "TYF-Live-Bot/1.0"
    }
    if api_key:
        headers["X-Api-Key"] = api_key

    req = urllib.request.Request(api_url, data=data_json, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            resp_body = json.loads(resp.read().decode("utf-8"))
            print(f"  [+] Django API Yanıtı: {resp_body}")
            return True
    except Exception as e:
        print(f"  [-] Django API Gönderim Hatası: {e}")
        return False


def run_worker(tyf_url: str, api_url: Optional[str] = None, api_key: Optional[str] = None, save_json: bool = False):
    print(f"[*] TYF Canlı Sayfası taranıyor: {tyf_url}")
    if api_url:
        print(f"[*] Hedef Django API: {api_url}")
    else:
        print(f"[*] API adresi belirtilmedi; sonuçlar JSON dosyası olarak kaydedilecek.")

    state = load_state()
    processed_map = state.get("processed", {})
    start_map = state.get("start_lists", {})

    if save_json or not api_url:
        os.makedirs("live_results", exist_ok=True)

    try:
        html = fetch_url(tyf_url).decode("utf-8", errors="ignore")
    except Exception as e:
        print(f"[-] TYF sayfasına ulaşılamadı: {e}")
        return

    # PDF linklerini bul
    pdf_links = set(re.findall(r'href=[\"\']([^\"\']+\.pdf)[\"\']', html, re.I))
    print(f"[*] Sayfada {len(pdf_links)} PDF linki bulundu.")

    # StartList ve ResultList dosyalarını ayır (Start listeleri her zaman önce işlenir)
    start_lists = [l for l in pdf_links if "startlist" in l.lower()]
    result_lists = [l for l in pdf_links if "resultlist" in l.lower()]

    all_targets = sorted(start_lists) + sorted(result_lists)

    for pdf_rel in all_targets:
        full_pdf_url = urllib.parse.urljoin(tyf_url, pdf_rel) if "urllib" in globals() else tyf_url.rstrip("/") + "/" + pdf_rel.lstrip("/")

        if pdf_rel in processed_map:
            # Daha önce işlenmiş
            continue

        print(f"\n[>] Yeni dosya tespit edildi: {pdf_rel}")
        try:
            pdf_bytes = fetch_url(full_pdf_url)
        except Exception as e:
            print(f"  [-] İndirilemedi ({pdf_rel}): {e}")
            continue

        payload = None
        if "startlist" in pdf_rel.lower():
            payload = parse_start_list_pdf(pdf_bytes)
            if payload and payload.get("yaris_no"):
                start_map[str(payload["yaris_no"])] = payload
                state["start_lists"] = start_map
                save_state(state)
        elif "resultlist" in pdf_rel.lower():
            # Yaris no'yu dosya adından al
            m_no = re.search(r"ResultList_(\d+)", pdf_rel, re.I)
            y_no = m_no.group(1) if m_no else ""
            start_data = start_map.get(str(y_no), {})
            start_candidates = start_data.get("kayitlar", []) if isinstance(start_data, dict) else start_data
            payload = parse_result_list_pdf(pdf_bytes, start_candidates)
            # Taranmış / Resim PDF'lerde başlık eksik kalırsa Start Listesinden devral
            if not payload.get("yaris_no") and y_no:
                payload["yaris_no"] = y_no
            if isinstance(start_data, dict):
                for k in ["musabaka_adi", "sehir", "tarih", "cinsiyet", "mesafe", "stil", "yas_grubu"]:
                    if not payload.get(k) and start_data.get(k):
                        payload[k] = start_data[k]

        if payload and payload.get("kayitlar"):
            payload["dosya_adi"] = pdf_rel
            print(f"  [*] {pdf_rel}: {len(payload['kayitlar'])} kayıt ayrıştırıldı.")
            
            success = False
            # 1. Django'ya POST at (eğer API URL verilmişse)
            if api_url:
                print("  [*] Django API'sine gönderiliyor...")
                success = post_to_django(api_url, payload, api_key)
            else:
                success = True

            # 2. İstenirse veya bağımsız moddaysa yerel JSON olarak kaydet
            if save_json or not api_url:
                clean_name = re.sub(r'[^a-zA-Z0-9_\-]', '_', pdf_rel.replace('.pdf', '')) + '.json'
                json_path = os.path.join("live_results", clean_name)
                with open(json_path, "w", encoding="utf-8") as f:
                    json.dump(payload, f, ensure_ascii=False, indent=2)
                print(f"  [+] JSON dosyası kaydedildi: {json_path}")

            if success:
                processed_map[pdf_rel] = {
                    "time": time.strftime("%Y-%m-%d %H:%M:%S"),
                    "count": len(payload["kayitlar"])
                }
                state["processed"] = processed_map
                save_state(state)
        else:
            print(f"  [?] Kayıt bulunamadı veya ayrıştırılamadı: {pdf_rel}")

    print("\n[*] Tarama tamamlandı.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="TYF Canlı Yarış Takip ve Aktarım Botu")
    parser.add_argument("--url", default=DEFAULT_TYF_URL, help="TYF Canlı Yarış Sayfası URL'si")
    parser.add_argument("--api", default=None, help="Django POST Endpoint URL'si (Opsiyonel)")
    parser.add_argument("--api-key", default=None, help="Opsiyonel X-Api-Key")
    parser.add_argument("--save-json", action="store_true", help="Ayrıştırılan sonuçları live_results/ klasörüne JSON olarak kaydet")
    args = parser.parse_args()

    run_worker(args.url, args.api, args.api_key, args.save_json)
