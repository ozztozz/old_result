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
import hashlib
import argparse
import difflib
import urllib.request
import urllib.parse
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

try:
    from rapidfuzz import fuzz
except ImportError:
    fuzz = None

try:
    from src.extract_scanned_pdfs import clean_ocr_swimming_line
except ImportError:
    def clean_ocr_swimming_line(line: str) -> str:
        line = re.sub(r"([A-Za-zçğıöşüÇĞİÖŞÜ])(\d{1,2}:\d{2}\.\d{2})", r"\1   \2", line)
        line = re.sub(r"(\d{1,2}:\d{2}\.\d{2})\s*(?:[oOe<>/_~]+\s*)(\d{2,4}\b)", r"\1   \2", line)
        line = re.sub(r"([A-ZÇĞİÖŞÜa-zçğıöşü])\s+[|_—=~]+\s+(\d{2}\b)", r"\1   \2", line)
        return line

try:
    from src.canonicalize_athletes import standardize_swimmer_name
except ImportError:
    def standardize_swimmer_name(name: str) -> str:
        return name.strip()

try:
    from src.pdf_reader import find_tesseract_cmd
except ImportError:
    def find_tesseract_cmd() -> Optional[str]:
        p = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
        return p if os.path.exists(p) else None

try:
    import fitz  # PyMuPDF
except ImportError:
    fitz = None

try:
    import pytesseract
    from PIL import Image
    import io
    tess_path = find_tesseract_cmd()
    if tess_path:
        pytesseract.pytesseract.tesseract_cmd = tess_path
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


def fetch_url_with_meta(url: str, timeout: int = 15) -> Tuple[bytes, Dict[str, Any]]:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
    )
    with urllib.request.urlopen(req, context=get_ssl_context(), timeout=timeout) as resp:
        meta = {
            "etag": resp.headers.get("ETag", "").strip('"'),
            "last_modified": resp.headers.get("Last-Modified", ""),
            "content_length": resp.headers.get("Content-Length", "")
        }
        data = resp.read()
        meta["sha256"] = hashlib.sha256(data).hexdigest()
        return data, meta


def fetch_url(url: str, timeout: int = 15) -> bytes:
    data, _ = fetch_url_with_meta(url, timeout)
    return data


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
    if not line_prefix or not candidates:
        return None

    p_norm = normalize_tr(line_prefix)
    p_norm = re.sub(r'^\d+[\.\s]+', '', p_norm).strip()
    text_lower = line_prefix.lower()

    # 1. RapidFuzz varsa yüksek doğruluklu token ve partial ratio kontrolü
    if fuzz:
        best_c, best_score = None, 0.0
        for c in candidates:
            c_lower = c.lower()
            score1 = fuzz.partial_ratio(c_lower, text_lower)
            score2 = fuzz.token_set_ratio(c_lower, text_lower)
            score = max(score1, score2)
            if score > best_score:
                best_score = score
                best_c = c
        if best_score >= 70.0:
            return best_c

    # 2. Birebir startswith veya difflib toleransı (Fallback)
    for c in candidates:
        c_norm = normalize_tr(c)
        if p_norm.startswith(c_norm):
            return c

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


def fix_ocr_time(t_str: str, seed_time: Optional[str] = None) -> str:
    """
    OCR okumasında harf karışmalarını ve nokta öncesi eksik veya birleşik çıkan dakikayı düzeltir.
    Örn: '402.52' -> '4:02.52', 'A27.B3' -> '4:27.83', 'M:51.58' -> '4:51.58'
    """
    if not t_str:
        return t_str

    t = t_str.strip()

    # 1. OCR harf-sayı karışması düzeltmesi (A->4, B->8, S->5, O/o->0, I/l->1)
    if any(c.isalpha() for c in t) and "." in t:
        trans = str.maketrans("ABbSOoIl", "48850011")
        t = t.translate(trans)

    # 2. '402.52' veya '538.41' gibi 3 basamak nokta öncesi varsa (dakika:saniye)
    m3 = re.match(r"^(\d)(\d{2})\.(\d{2})$", t)
    if m3:
        return f"{m3.group(1)}:{m3.group(2)}.{m3.group(3)}"

    # 3. Eğer dakika kısmı harf lekesi veya bozulmuşsa (örn: 'M:51.58', 'hd:44.44' veya ':51.58')
    m_corrupt_min = re.match(r"^[^\d:]*:(\d{2}\.\d{2})$", t)
    if m_corrupt_min and seed_time and ":" in seed_time:
        seed_min = seed_time.split(":")[0]
        return f"{seed_min}:{m_corrupt_min.group(1)}"

    # 4. Eğer dakika kısmı OCR'da tamamen kopmuşsa ('02.52') ve giriş derecesi dakikalı ise
    if ":" not in t and seed_time and ":" in seed_time:
        seed_min = seed_time.split(":")[0]
        return f"{seed_min}:{t}"

    return t


def parse_scanned_pdf_ocr(doc, header: Dict[str, Any], start_entries: Optional[List[Dict[str, Any]]] = None) -> Dict[str, Any]:
    kayitlar = []
    candidates_map = {e['sporcu']: e for e in start_entries} if start_entries else {}
    candidates = list(candidates_map.keys())
    seen_swimmers = set()

    for page_num, page in enumerate(doc):
        # 300 DPI yüksek çözünürlük ile render al
        pix = page.get_pixmap(dpi=300)
        img = Image.open(io.BytesIO(pix.tobytes("png")))
        # --psm 6 satır hizalamasını koruyarak tablo satırlarını birleştirir
        ocr_text = pytesseract.image_to_string(img, lang="tur", config="--psm 6 preserve_interword_spaces=1")

        # Sayfa 0'da başlık eksikse OCR satırlarından tamamla
        if page_num == 0 and not header.get("yaris_no"):
            ocr_lines = [l.strip() for l in ocr_text.splitlines() if l.strip()]
            for l in ocr_lines[:10]:
                m_race = re.search(r"Yar[ıiIİ][şsSŞ]\s+(\d+)\s+([A-Za-zÇĞİÖŞÜçğıöşü]+)[,\s]+(\d+)m\s+([A-Za-zÇĞİÖŞÜçğıöşü]+)\s*(.*)", l, re.I)
                if m_race:
                    header["yaris_no"] = m_race.group(1)
                    header["cinsiyet"] = "Erkek" if "Erkek" in m_race.group(2) else "Kadın"
                    header["mesafe"] = int(m_race.group(3))
                    header["stil"] = m_race.group(4)
                    if m_race.group(5):
                        header["yas_grubu"] = m_race.group(5).strip()
                    break
            if not header.get("musabaka_adi") and len(ocr_lines) >= 2:
                header["musabaka_adi"] = ocr_lines[0]
                if "," in ocr_lines[1]:
                    header["sehir"] = ocr_lines[1].split(",")[0].strip()

        for raw_line in ocr_text.splitlines():
            line = raw_line.strip()
            if not line:
                continue

            # 1. Eski yapımızdaki ara derece (split time) ve gürültü kontrolleri
            if re.search(r'\b(?:\d{2,3}m|tüm|idüm|Güm|ilüm|isim|[5S]0m|[5S]om)[:\s]', line, re.I):
                continue
            if "Splash Meet Manager" in line or "Puanlar:" in line or "BAŞHAKEM" in line or "Sonuçlar" in line:
                continue
            if re.match(r"^S[ıi]ra\b", line, re.I) or re.search(r"T[ÜU]RK[İI]YE\s+REKORLAR", line, re.I):
                continue

            # 2. Temizleme katmanı
            line = clean_ocr_swimming_line(line)

            # 3. Yüzücü satırı tespiti: Baştaki sıra numarası (1., 2., 10. vb.)
            m_rank = re.match(r"^(\d{1,3})\.[\s\t]+(.+)$", line)
            if not m_rank:
                continue

            rank_val = m_rank.group(1)
            content = m_rank.group(2).strip()

            # 4. Resmi Derece ve Puan tespiti:
            # Durum A: Standart dereceli (noktalı/iki noktalı) ve puanlı (aradaki leke/Oo temizlenmiş)
            m_time = re.search(r'\b((?:[A-Za-z0-9]{1,2}:)?[A-Za-z0-9]{2,3}\.[A-Za-z0-9]{2,3})\s*(?:[oOe<>/_~]*\s*)(\d{1,4})\b', content)
            time_val = None
            pts_val = None

            if m_time:
                time_val = m_time.group(1)
                pts_val = m_time.group(2)
                prefix = content[:m_time.start()].strip()
            else:
                # Durum B: 50m sprint yarışlarında noktası OCR'da silinmiş 4 basamaklı zaman: '4242 119' -> '42.42 119'
                m_4dig = re.search(r'\b(\d{2})(\d{2})\s*(?:[oOe<>/_~]*\s*)(\d{1,4})\b', content)
                if m_4dig:
                    time_val = f"{m_4dig.group(1)}.{m_4dig.group(2)}"
                    pts_val = m_4dig.group(3)
                    prefix = content[:m_4dig.start()].strip()
                else:
                    # Durum C: Puansız sadece zaman
                    m_only_t = re.search(r'\b((?:\d{1,2}:)?\d{2,3}\.\d{2})\b', content)
                    if m_only_t:
                        time_val = m_only_t.group(1)
                        pts_val = None
                        prefix = content[:m_only_t.start()].strip()
                    else:
                        continue

            # 5. SADECE START LISTESİNDEKİ SPORCULARLA EŞLEŞENLERİ KABUL ET
            matched_name = match_ocr_line(prefix, candidates) if candidates else None

            if matched_name and matched_name not in seen_swimmers:
                seen_swimmers.add(matched_name)
                st = candidates_map[matched_name]
                cleaned_time = fix_ocr_time(time_val, st.get("giris_derecesi"))

                kayitlar.append({
                    "sira": rank_val,
                    "sporcu": matched_name,
                    "dogum_yili": st.get("dogum_yili"),
                    "kulup": st.get("kulup"),
                    "derece": cleaned_time,
                    "puan": pts_val,
                    "seri": st.get("seri"),
                    "kulvar": st.get("kulvar"),
                    "giris_derecesi": st.get("giris_derecesi")
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


def run_worker(tyf_url: str, api_url: Optional[str] = None, api_key: Optional[str] = None, save_json: bool = False, force: bool = False):
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
        prev_info = processed_map.get(pdf_rel)

        try:
            pdf_bytes, meta = fetch_url_with_meta(full_pdf_url)
        except Exception as e:
            print(f"  [-] İndirilemedi ({pdf_rel}): {e}")
            continue

        sha256_val = meta.get("sha256", "")

        # Dosya sunucuda güncellendi mi kontrol et (Hash / SHA-256)
        if prev_info and not force:
            prev_sha = prev_info.get("sha256")
            prev_count = prev_info.get("count", 0)

            if prev_sha and prev_sha == sha256_val:
                # Sunucudaki dosya içeriği birebir aynı, yeniden işlemeye gerek yok
                continue
            else:
                print(f"\n[!] GÜNCELLEME TESPİT EDİLDİ: {pdf_rel} (Önceki kayıt: {prev_count}, sunucu dosyayı güncelledi!)")
        else:
            print(f"\n[>] Yeni dosya tespit edildi: {pdf_rel}")

        payload = None
        start_candidates = []
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
            result_count = len(payload["kayitlar"])
            print(f"  [*] {pdf_rel}: {result_count} kayıt ayrıştırıldı.")
            
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
                    "count": result_count,
                    "sha256": sha256_val,
                    "etag": meta.get("etag", ""),
                    "last_modified": meta.get("last_modified", "")
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
    parser.add_argument("--force", action="store_true", help="Kayıtlı duruma bakılmaksızın tüm dosyaları yeniden tara")
    args = parser.parse_args()

    run_worker(args.url, args.api, args.api_key, args.save_json, args.force)
