# -*- coding: utf-8 -*-
"""
Google Cloud Function / Cloud Run - TYF Canlı Start ve Sonuç Listesi İşleyicisi
================================================================================
Bu servis Google Cloud Run veya Cloud Functions (gen2) altyapısında çalışır.

Çalışma Mantığı (Pull Modeli - Rutin Tarama):
1. Web uygulamasından (PythonAnywhere) Cloud Run'a istek atılmaz (timeout ve dış proxy engellerini önler).
2. Cloud Scheduler periyodik olarak (ör: her 5 veya 10 dakikada bir) bu servisi tetikler.
3. Servis Django'ya (varsayılan: https://ozztozz.pythonanywhere.com/) bağlanır:
   - GET /api/canli-bekleyen-yarislar/ ile kuyrukta bekleyen yarışları çeker.
   - Bekleyen yarış yoksa anında (~0.5 sn) 200 OK ile kapanır (Cloud Run CPU/maliyet tasarrufu).
4. Bekleyen yarış varsa:
   - Durumu 'ISLENIYOR' olarak işaretler.
   - canli.tyf.gov.tr sayfasındaki StartList ve ResultList PDF'lerini çeker.
   - Her PDF için SHA-256 hash ve ETag kontrolü yapar (/api/canli-dosya-kontrol/).
   - Değişmeyen dosyaları atlar (Gemini maliyetini %95 oranında düşürür).
   - Yeni/değişen Start listelerini Gemini Flash Lite ile ayrıştırıp Django'ya aktarır (/api/canli-aktar/).
   - Yeni/değişen Sonuç listelerinde Django'daki start listesi sporcu ID'lerini eşleştirme için Gemini'ye aktarır.
   - Tüm işlemler bitince durumu 'TAMAMLANDI' yapar (/api/canli-durum-guncelle/) ve kapanır.
"""

import os
import re
import ssl
import json
import time
import hashlib
import difflib
import urllib.request
from urllib.parse import urljoin, urlencode
from typing import Dict, List, Any, Optional, Tuple
from concurrent.futures import ThreadPoolExecutor

try:
    import pymupdf as fitz
except ImportError:
    import fitz
from bs4 import BeautifulSoup
from google import genai
from google.genai import types

try:
    from dotenv import load_dotenv
    env_paths = [
        os.path.join(os.path.dirname(__file__), ".env"),
        os.path.join(os.path.dirname(__file__), "..", ".env"),
    ]
    for ep in env_paths:
        if os.path.exists(ep):
            load_dotenv(ep)
            break
except ImportError:
    pass

DEFAULT_MODEL = os.environ.get("GEMINI_MODEL", "gemini-flash-lite-latest")
DEFAULT_DJANGO_BASE_URL = os.environ.get("DJANGO_BASE_URL", "https://ozztozz.pythonanywhere.com").rstrip("/")
DEFAULT_BATCH_SIZE = int(os.environ.get("BATCH_SIZE", 5))

_TR_NORM_MAP = str.maketrans({
    "İ": "i", "I": "ı", "i": "i", "ı": "ı",
    "Ğ": "ğ", "Ü": "ü", "Ş": "ş", "Ö": "ö", "Ç": "ç",
    "Â": "a", "Î": "i", "Û": "u", "â": "a", "î": "i", "û": "u",
})


def normalize_tr(s: str) -> str:
    """Türkçe karakter duyarlı küçük harf ve boşluk normalizasyonu."""
    if not s:
        return ""
    s = str(s).translate(_TR_NORM_MAP).lower()
    s = re.sub(r"[^a-z0-9ğüşıöç\s]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def extract_race_no_from_filename(filename_or_url: str) -> Optional[str]:
    """StartList_12.pdf veya ResultList_12.pdf gibi dosya adlarından yarış numarasını çıkarır."""
    if not filename_or_url:
        return None
    fname = os.path.basename(str(filename_or_url))
    m = re.search(r"(?:StartList|ResultList)_(\d+)\.pdf", fname, re.I)
    if not m:
        m = re.search(r"_(\d+)\.pdf", fname, re.I)
    return m.group(1) if m else None


def is_valid_swim_time(val: Any) -> Optional[str]:
    """
    Verilen değer geçerli bir yüzme derecesi ise (örn: '27.45', '1:04.32', '01:04,32')
    noktalı standart formatta ('1:04.32') döner; değilse None döner.
    """
    if val is None:
        return None
    s = re.sub(r"\s+", "", str(val).strip()).replace(",", ".")
    if not re.match(r"^(?:\d{1,2}:)?(?:\d{1,2}:)?\d{1,2}\.\d{2}$", s):
        return None
    return s


def normalize_and_validate_derece(raw_derece: Any, rec: Optional[Dict[str, Any]] = None) -> Optional[str]:
    """
    Sonuç listesindeki bir kaydın 'derece' alanını doğrular.
    - Geçerli yüzme süresi ise ('1:05.32', '28.91') temizlenmiş halini döner.
    - Diskalifiye / Terk / Katılmadı ise 'DSQ', 'DNF' veya 'DNS' döner.
    - Gemini sütun kaydırıp 'derece' içine sporcu adı yazmışsa ve zamanı 'baraj' alanına
      kaydırmışsa zamanı kurtarır, sporcu adını da boşsa 'sporcu' alanına geri yazar.
    - Geçersiz metin/sporcu adı ise asla derece olarak döndürmez (None döner).
    """
    rec = rec if isinstance(rec, dict) else {}
    is_dsq_flag = bool(rec.get("diskalifiye")) or bool(rec.get("diskalifiye_nedeni"))

    s = str(raw_derece or "").strip()
    s_norm = normalize_tr(s)

    dsq_tokens = ("dsq", "dq", "disk", "diskalifiye", "disqualified", "ihrac")
    dns_tokens = ("dns", "katılmadı", "katilmadi", "girmedi", "did not start", "ns", "yuzmedi", "yüzmedi")
    dnf_tokens = ("dnf", "terk", "yarış terk", "yaris terk", "did not finish", "bıraktı", "birakti")

    if s_norm in dsq_tokens or s.lower().startswith("disk"):
        return "DSQ"
    if s_norm in dns_tokens:
        return "DNS"
    if s_norm in dnf_tokens:
        return "DNF"

    clean_t = is_valid_swim_time(s)
    if clean_t:
        return clean_t

    # Metin içinde gömülü zaman var mı? (örn: "1:05.21 A2")
    m_emb = re.search(r"\b((?:\d{1,2}:)?\d{1,2}[\.,]\d{2})\b", s)
    if m_emb:
        clean_emb = is_valid_swim_time(m_emb.group(1))
        if clean_emb:
            return clean_emb

    # Sütun kayması kontrolü:
    # Eğer 'derece' içine sporcu adı gelmişse (harf içeriyor ve rakam içermiyorsa) ve 'sporcu' alanı boşsa:
    if s and not re.search(r"\d", s) and len(s) >= 4 and not rec.get("sporcu"):
        rec["sporcu"] = s

    # 'baraj' alanında geçerli bir yüzme zamanı var mı?
    baraj_raw = str(rec.get("baraj") or "").strip()
    if baraj_raw:
        clean_b = is_valid_swim_time(baraj_raw)
        if clean_b:
            rec["baraj"] = None
            return clean_b

    if is_dsq_flag:
        return "DSQ"

    return None


def get_ssl_context():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def download_bytes(url: str) -> bytes:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
    )
    with urllib.request.urlopen(req, context=get_ssl_context(), timeout=30) as resp:
        return resp.read()


def download_file_with_meta(url: str) -> Tuple[bytes, Dict[str, Any]]:
    """Dosyayı indirir ve ETag, Last-Modified, SHA-256 content_hash meta verilerini çıkarır."""
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
    )
    with urllib.request.urlopen(req, context=get_ssl_context(), timeout=30) as resp:
        content = resp.read()
        etag = (resp.headers.get("ETag") or "").strip('"')
        last_modified = resp.headers.get("Last-Modified") or ""
        content_hash = hashlib.sha256(content).hexdigest()
        meta = {
            "etag": etag,
            "last_modified": last_modified,
            "content_hash": content_hash,
            "dosya_boyutu": len(content)
        }
        return content, meta


def get_remote_file_header(url: str) -> Tuple[str, Dict[str, str]]:
    """HTTP HEAD isteği ile dosyanın ETag ve Last-Modified başlıklarını çeker (0 bayt veri tüketir)."""
    req = urllib.request.Request(
        url,
        method="HEAD",
        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
    )
    try:
        with urllib.request.urlopen(req, context=get_ssl_context(), timeout=10) as resp:
            etag = (resp.headers.get("ETag") or "").strip('"')
            last_modified = resp.headers.get("Last-Modified") or ""
            return url, {"etag": etag, "last_modified": last_modified}
    except Exception:
        return url, {}


def fetch_remote_headers_map(urls: List[str]) -> Dict[str, Dict[str, str]]:
    """Tüm PDF URL'lerinin ETag ve Last-Modified başlıklarını paralel HTTP HEAD ile çeker (~0.3 sn)."""
    if not urls:
        return {}
    headers_map = {}
    with ThreadPoolExecutor(max_workers=8) as executor:
        for u, h in executor.map(get_remote_file_header, urls):
            fname = os.path.basename(u)
            headers_map[fname] = h
    return headers_map


def get_endpoint_url(django_url: str, endpoint: str) -> str:
    """Django API URL'sinden ilgili endpoint adresini türetir."""
    if not django_url:
        return ""
    clean_endpoint = endpoint.strip("/")
    base = django_url.rstrip("/")
    if "/api/" in base:
        base = base.split("/api/")[0]
    return f"{base}/api/{clean_endpoint}/"


def check_file_already_processed(django_url: str, event_id: Any, filename: str, meta: Dict[str, Any], api_key: Optional[str] = None) -> bool:
    """
    Django API'den dosyanın daha önce işlenip işlenmediğini, veritabanında geçerli kaydı olup olmadığını
    ve değişip değişmediğini kontrol eder.
    """
    if not django_url or not event_id:
        return False
    check_api = get_endpoint_url(django_url, "canli-dosya-kontrol")
    payload = {
        "canli_yaris_id": event_id,
        "dosya_adi": filename,
        "etag": meta.get("etag"),
        "content_hash": meta.get("content_hash"),
        "last_modified": meta.get("last_modified"),
        "dosya_boyutu": meta.get("dosya_boyutu")
    }
    try:
        data_json = json.dumps(payload).encode("utf-8")
        headers = {"Content-Type": "application/json; charset=utf-8"}
        if api_key:
            headers["X-Api-Key"] = api_key
        req = urllib.request.Request(check_api, data=data_json, headers=headers)
        with urllib.request.urlopen(req, context=get_ssl_context(), timeout=25) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            is_valid = data.get("veri_gecerli_mi", True) is not False and (data.get("kayit_sayisi") or 0) > 0
            return bool(data.get("islenmis_mi") is True and is_valid and data.get("degisti_mi") is False)
    except Exception as e:
        print(f"  [!] Dosya kontrol hatası ({filename}): {e}")
        return False


def verify_file_saved_in_django(
    django_url: str,
    event_id: Any,
    filename: str,
    meta: Dict[str, Any],
    api_key: Optional[str] = None
) -> Tuple[bool, Dict[str, Any]]:
    """
    POST işleminden sonra Django veritabanında dosyanın gerçekten kaydedildiğini ve
    eşleştirme/kilitlenme nedeniyle veri kaybı yaşanmadığını doğrular.
    """
    if not django_url or not event_id:
        return True, {}
    check_api = get_endpoint_url(django_url, "canli-dosya-kontrol")
    payload = {
        "canli_yaris_id": event_id,
        "dosya_adi": filename,
        "etag": meta.get("etag"),
        "content_hash": meta.get("content_hash"),
        "last_modified": meta.get("last_modified"),
        "dosya_boyutu": meta.get("dosya_boyutu")
    }
    try:
        data_json = json.dumps(payload).encode("utf-8")
        headers = {"Content-Type": "application/json; charset=utf-8"}
        if api_key:
            headers["X-Api-Key"] = api_key
        req = urllib.request.Request(check_api, data=data_json, headers=headers)
        with urllib.request.urlopen(req, context=get_ssl_context(), timeout=25) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            is_done = bool(data.get("islenmis_mi") is True)
            is_valid = bool(data.get("veri_gecerli_mi", True) is not False)
            saved_count = int(data.get("db_kayit_sayisi") or data.get("kayit_sayisi") or 0)
            return (is_done and is_valid and saved_count > 0), data
    except Exception as e:
        print(f"  [!] POST sonrası doğrulama sorgusu hatası ({filename}): {e}")
        return False, {}


def fetch_known_files_map(django_url: str, event_id: Any, api_key: Optional[str] = None) -> Dict[str, Dict[str, Any]]:
    """
    Django API'den o yarışa ait daha önce işlenmiş tüm dosyaları tek bir HTTP isteğinde çeker.
    Bu sayede her dosya için ayrı ayrı HTTP isteği atılması ve 80 round-trip önlenir.
    Dönen sözlük örneği:
      {"StartList_1.pdf": {"durum": "ISLENDI", "etag": "...", "content_hash": "..."}, ...}
    """
    if not django_url or not event_id:
        return {}
    endpoint = get_endpoint_url(django_url, "canli-dosya-kontrol")
    query = urlencode({"event_id": event_id})
    full_url = f"{endpoint}?{query}"
    try:
        req = urllib.request.Request(full_url, headers={"User-Agent": "TYF-CloudRunner/1.0"})
        if api_key:
            req.add_header("X-Api-Key", api_key)
        with urllib.request.urlopen(req, context=get_ssl_context(), timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("durum") == "basarili":
                return data.get("dosyalar", {})
    except Exception as e:
        print(f"  [!] Toplu dosya kontrolü hatası ({full_url}): {e}")
    return {}


def fetch_startlist_swimmers(django_url: str, event_id: Any, yaris_no: str, api_key: Optional[str] = None) -> List[Dict[str, Any]]:
    """Django API'den o yarışın start listesindeki sporcularını ve sonuc ID'lerini çeker."""
    if not django_url:
        return []
    base_api = get_endpoint_url(django_url, "canli-startlist-sporculari")
    query = urlencode({"event_id": event_id, "yaris_no": yaris_no})
    full_url = f"{base_api}?{query}"
    try:
        req = urllib.request.Request(full_url, headers={"User-Agent": "TYF-LiveRunner"})
        if api_key:
            req.add_header("X-Api-Key", api_key)
        with urllib.request.urlopen(req, context=get_ssl_context(), timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("sporcular", [])
    except Exception as e:
        print(f"  [!] Start listesi sporcuları çekilemedi ({full_url}): {e}")
        return []


def fetch_pending_meets(base_url: str, api_key: Optional[str] = None) -> List[Dict[str, Any]]:
    """Django API'den BEKLIYOR veya ISLENIYOR durumundaki canlı yarışları çeker."""
    endpoint = get_endpoint_url(base_url, "canli-bekleyen-yarislar")
    headers = {"User-Agent": "TYF-CloudRunner/1.0"}
    if api_key:
        headers["X-Api-Key"] = api_key
    try:
        req = urllib.request.Request(endpoint, headers=headers)
        with urllib.request.urlopen(req, context=get_ssl_context(), timeout=20) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("yarislar", [])
    except Exception as e:
        print(f"[!] Bekleyen yarışlar çekilemedi ({endpoint}): {e}")
        return []


def update_meet_status(base_url: str, payload: Dict[str, Any], api_key: Optional[str] = None) -> bool:
    """Django API'deki yarış durumunu ve sayaçları günceller."""
    endpoint = get_endpoint_url(base_url, "canli-durum-guncelle")
    return post_to_django(endpoint, payload, api_key=api_key)


def parse_tr_date_range(d_str: str) -> Tuple[str, str]:
    """Türkçe tarih aralığını ISO formatına dönüştürür (örn: '24. - 26.4.2026' -> '2026-04-24', '2026-04-26')."""
    if not d_str:
        return '', ''
    d_clean = re.sub(r'\s+', ' ', d_str.strip())
    m = re.search(r'(\d{1,2})\.?\s*(?:-\s*(\d{1,2})\.?)?\s*(\d{1,2})\.(\d{4})', d_clean)
    if m:
        d1, d2, month, year = m.group(1), m.group(2), m.group(3), m.group(4)
        m_str = f'{int(month):02d}'
        start_date = f'{year}-{m_str}-{int(d1):02d}'
        end_date = f'{year}-{m_str}-{int(d2):02d}' if d2 else start_date
        return start_date, end_date
    return '', ''


def fetch_meet_pdf_urls(event_url: str, mode: str = "all") -> Tuple[str, str, str, str, str, List[str]]:
    """TYF Canlı sonuç web sayfasından başlık, şehir, tarih ve PDF URL'lerini çeker."""
    html = download_bytes(event_url).decode("utf-8", errors="ignore")
    soup = BeautifulSoup(html, "html.parser")
    meet_title = soup.title.string.replace("- SPLASH Meet Manager 11", "").strip() if soup.title else ""

    plain_text = soup.get_text()
    city = ""
    date_str = ""
    start_date = ""
    end_date = ""

    m_city = re.search(r'([A-ZÇĞİÖŞÜa-zçğıöşü\s]{3,30})\s*\((?:TUR|TR)\)', plain_text)
    if m_city:
        city = re.sub(r'\s+', ' ', m_city.group(1)).strip()

    m_date = re.search(r'(\d{1,2}\.?\s*(?:-\s*\d{1,2}\.)?\s*\d{1,2}\.\d{4})', plain_text)
    if m_date:
        date_str = re.sub(r'\s+', ' ', m_date.group(1)).strip()
        start_date, end_date = parse_tr_date_range(date_str)

    if not city:
        m_u = re.search(r'canli\.tyf\.gov\.tr/([a-zA-ZçğıöşüÇĞİÖŞÜ]+)/', event_url)
        if m_u:
            c_raw = m_u.group(1).lower()
            city = c_raw.replace('i', 'İ').replace('ı', 'I').upper()

    m_lower = (mode or "").lower()
    is_sonuc = m_lower in ("sonuc_listesi", "result_list", "sonuc", "results")
    is_start = m_lower in ("start_listesi", "start_list", "start")
    is_all = not (is_sonuc or is_start) or m_lower in ("all", "hepsi")

    seen = set()
    pdf_urls = []
    for a in soup.find_all("a", href=True):
        href = a["href"].strip()
        h_lower = href.lower()

        matches = False
        if is_sonuc:
            matches = ("resultlist" in h_lower or "result_list" in h_lower or "sonuc" in h_lower)
        elif is_start:
            matches = ("startlist" in h_lower or "start_list" in h_lower or "start" in h_lower)
        else:  # all / hepsi
            matches = ("startlist" in h_lower or "start_list" in h_lower or "resultlist" in h_lower or "result_list" in h_lower or "sonuc" in h_lower or "start" in h_lower)

        if matches:
            full = urljoin(event_url, href)
            if full not in seen:
                seen.add(full)
                pdf_urls.append(full)

    def sort_key(u: str) -> int:
        m = re.search(r"(?:StartList|ResultList)_(\d+)\.pdf", u, re.I)
        return int(m.group(1)) if m else 99999

    pdf_urls.sort(key=sort_key)
    return meet_title, city, date_str, start_date, end_date, pdf_urls


# Geriye dönük uyumluluk
fetch_start_list_urls = fetch_meet_pdf_urls


def detect_pdf_type(pdf_url: str, pdf_bytes: bytes = b"") -> str:
    """PDF URL'sine ve içeriğine göre Start Listesi mi Sonuç Listesi mi olduğunu saptar."""
    u = pdf_url.lower()
    if "resultlist" in u or "result_list" in u or "sonuc" in u:
        return "sonuc_listesi"
    if "startlist" in u or "start_list" in u or "start" in u:
        return "start_listesi"
    if pdf_bytes:
        try:
            doc = fitz.open(stream=pdf_bytes, filetype="pdf")
            if len(doc) > 0:
                txt = doc[0].get_text().lower()
                if "start list" in txt or "start listesi" in txt:
                    return "start_listesi"
                if "sonuç" in txt or "results" in txt:
                    return "sonuc_listesi"
            doc.close()
        except Exception:
            pass
    return "start_listesi"


def sanitize_and_match_records(
    raw_records: List[Dict[str, Any]],
    doc_type: str,
    startlist_swimmers: Optional[List[Dict[str, Any]]] = None
) -> List[Dict[str, Any]]:
    """
    Gemini'den dönen kayıtları doğrular, sütun kaymalarını (sporcu adının dereceye gelmesi vb.)
    temizler ve sonuç listesinde StartList sporcularıyla deterministik Python eşleştirmesi yapar.
    """
    if not raw_records:
        return []

    if doc_type != "sonuc_listesi":
        cleaned_starts = []
        for r in raw_records:
            if not isinstance(r, dict):
                continue
            sporcu = str(r.get("sporcu") or r.get("sporcu_adi") or r.get("name") or "").strip()
            if not sporcu:
                continue
            r["sporcu"] = sporcu
            cleaned_starts.append(r)
        return cleaned_starts

    # StartList sporcuları için hızlı arama tabloları hazırla
    swimmers_by_id: Dict[int, Dict[str, Any]] = {}
    swimmers_by_norm_name: Dict[str, List[Dict[str, Any]]] = {}
    all_swimmers: List[Tuple[str, Dict[str, Any]]] = []

    if startlist_swimmers:
        for s in startlist_swimmers:
            sid = s.get("id")
            if sid is not None:
                try:
                    swimmers_by_id[int(sid)] = s
                except (ValueError, TypeError):
                    pass
            sname = str(s.get("sporcu_adi") or s.get("sporcu") or "").strip()
            norm_s = normalize_tr(sname)
            if norm_s:
                swimmers_by_norm_name.setdefault(norm_s, []).append(s)
                all_swimmers.append((norm_s, s))

    def _extract_birth_year(val: Any) -> Optional[int]:
        if not val:
            return None
        m = re.search(r"(\d{2,4})", str(val).strip())
        if not m:
            return None
        y = int(m.group(1))
        if y < 100:
            return 2000 + y if y <= 35 else 1900 + y
        return y

    def _match_swimmer_in_startlist(name_str: str, yb_val: Any) -> Optional[Dict[str, Any]]:
        norm_q = normalize_tr(name_str)
        if not norm_q or not all_swimmers:
            return None
        target_yb = _extract_birth_year(yb_val)

        # 1. Tam normalize isim eşleşmesi
        exact_cands = swimmers_by_norm_name.get(norm_q)
        if exact_cands:
            if len(exact_cands) == 1:
                return exact_cands[0]
            if target_yb:
                for c in exact_cands:
                    if _extract_birth_year(c.get("dogum_yili")) == target_yb:
                        return c
            return exact_cands[0]

        # 2. Uzun isim kırpılması (Splash Meet Manager PDF sütun darlığı) veya bulanık eşleşme
        best_score = 0.0
        best_cand = None
        for cand_norm, cand_obj in all_swimmers:
            if len(norm_q) >= 8 and len(cand_norm) >= 8 and (cand_norm.startswith(norm_q) or norm_q.startswith(cand_norm)):
                sim = 0.93
            else:
                sim = difflib.SequenceMatcher(None, norm_q, cand_norm).ratio()

            cand_yb = _extract_birth_year(cand_obj.get("dogum_yili"))
            if target_yb and cand_yb:
                if target_yb == cand_yb:
                    sim += 0.05
                else:
                    sim -= 0.15

            if sim > best_score:
                best_score = sim
                best_cand = cand_obj

        if best_cand and best_score >= 0.82:
            return best_cand
        return None

    cleaned_results = []
    for r in raw_records:
        if not isinstance(r, dict):
            continue

        rec = dict(r)
        sporcu = str(rec.get("sporcu") or rec.get("sporcu_adi") or rec.get("name") or "").strip()
        if sporcu:
            rec["sporcu"] = sporcu

        # Dereceyi doğrula ve sütun kayması varsa düzelt
        valid_derece = normalize_and_validate_derece(rec.get("derece") or rec.get("time"), rec)
        if not valid_derece:
            continue
        rec["derece"] = valid_derece

        # normalize_and_validate_derece 'sporcu' alanını kurtarmış olabilir
        sporcu = str(rec.get("sporcu") or "").strip()

        # Sıra ve puan temizliği
        sira_raw = str(rec.get("sira") or rec.get("rank") or "").strip()
        if sira_raw.endswith("."):
            sira_raw = sira_raw[:-1].strip()
        if valid_derece in ("DSQ", "DNS", "DNF"):
            rec["sira"] = ""
            rec["puan"] = None
        else:
            rec["sira"] = sira_raw

        # StartList ID doğrulaması ve deterministik eşleştirme
        raw_id = rec.get("id")
        matched_swimmer = None
        if raw_id is not None:
            try:
                rid = int(raw_id)
                cand_sw = swimmers_by_id.get(rid)
                if cand_sw:
                    cand_name_norm = normalize_tr(cand_sw.get("sporcu_adi") or "")
                    if not sporcu:
                        # Gemini sadece ID döndürmüş -> sporcu adını, kulübünü ve doğum yılını StartList'ten tamamla!
                        matched_swimmer = cand_sw
                    else:
                        rec_name_norm = normalize_tr(sporcu)
                        sim = difflib.SequenceMatcher(None, rec_name_norm, cand_name_norm).ratio()
                        if rec_name_norm == cand_name_norm or sim >= 0.72 or cand_name_norm.startswith(rec_name_norm) or rec_name_norm.startswith(cand_name_norm):
                            matched_swimmer = cand_sw
                        else:
                            # Gemini yanlış sporcunun ID'sini yazmış! ID'yi sıfırla ve isimden bul.
                            rec["id"] = None
                else:
                    rec["id"] = None
            except (ValueError, TypeError):
                rec["id"] = None

        if not matched_swimmer and sporcu and all_swimmers:
            matched_swimmer = _match_swimmer_in_startlist(sporcu, rec.get("dogum_yili"))

        if matched_swimmer:
            rec["id"] = matched_swimmer.get("id")
            if not rec.get("sporcu"):
                rec["sporcu"] = matched_swimmer.get("sporcu_adi") or ""
            if not rec.get("kulup"):
                rec["kulup"] = matched_swimmer.get("kulup_adi") or ""
            if not rec.get("dogum_yili") and matched_swimmer.get("dogum_yili"):
                rec["dogum_yili"] = str(matched_swimmer.get("dogum_yili"))

        # Hem sporcu adı hem de geçerli ID yoksa bu kayıt işlenemez, atla
        if not rec.get("sporcu") and not rec.get("id"):
            continue

        cleaned_results.append(rec)

    return cleaned_results


def parse_meet_pdf(pdf_bytes: bytes, client: genai.Client, pdf_url: str = "", model: str = DEFAULT_MODEL, startlist_swimmers: Optional[List[Dict[str, Any]]] = None) -> Dict[str, Any]:
    """PDF sayfalarını Gemini Flash Lite ile paralel olarak yapılandırılmış JSON verisine dönüştürür."""
    doc_type = detect_pdf_type(pdf_url, pdf_bytes)
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    total_pages = len(doc)

    fallback_race_no = extract_race_no_from_filename(pdf_url)

    header_data = {
        "tur": doc_type,
        "musabaka_adi": "",
        "sehir": "",
        "tarih": "",
        "yaris_no": int(fallback_race_no) if (fallback_race_no and fallback_race_no.isdigit()) else fallback_race_no,
        "cinsiyet": "",
        "mesafe": None,
        "stil": "",
        "yas_grubu": "",
        "toplam_sayfa": total_pages,
        "kayitlar": [],
        "yeni_sporcular": []
    }

    pages_bytes = []
    for page_idx in range(total_pages):
        page_text = ""
        try:
            page_text = (doc[page_idx].get_text("text") or "").strip()
        except Exception:
            page_text = ""
        single_page_doc = fitz.open()
        single_page_doc.insert_pdf(doc, from_page=page_idx, to_page=page_idx)
        pages_bytes.append((page_idx, single_page_doc.tobytes(), page_text))
        single_page_doc.close()
    doc.close()

    def process_page(args):
        p_idx, p_bytes, p_text = args
        p_num = p_idx + 1
        is_first = (p_idx == 0)

        text_hint = ""
        if p_text and len(p_text) > 20:
            text_hint = f"\nSAYFADAKİ HAM METİN (Sütunları ve dereceleri doğrulamak için referans al):\n---\n{p_text[:12000]}\n---\n"

        if doc_type == "sonuc_listesi":
            swimmers_context = ""
            if startlist_swimmers:
                candidates = []
                for s in startlist_swimmers:
                    candidates.append({
                        "id": s.get("id"),
                        "sporcu": s.get("sporcu_adi"),
                        "kulup": s.get("kulup_adi"),
                        "dogum_yili": s.get("dogum_yili"),
                        "seri": s.get("seri"),
                        "kulvar": s.get("kulvar")
                    })
                swimmers_context = f"\nBU YARIŞTA YÜZEN START LİSTESİNDEKİ SPORCULAR (İsim eşleşiyorsa buradaki id değerini ata):\n{json.dumps(candidates, ensure_ascii=False)}\n"

            prompt = f"""Bu bir TYF Splash Meet Manager SONUÇ LİSTESİ (ResultList) PDF sayfasıdır.
Sayfa {p_num}/{total_pages}.
{'1. Başlıktan musabaka_adi, sehir, tarih (YYYY-MM-DD), yaris_no (sadece sayı), cinsiyet (Erkek/Kadın), mesafe (m tam sayı), stil ve yas_grubu çıkar.' if is_first else ''}
{swimmers_context}
{text_hint}
2. Sayfadaki TÜM yaş grubu bölümlerindeki (örn. 11 yaş, 12 yaş, 13 yaş, Açık Yaş vb.) normal dereceli sporcuları VE sayfa sonundaki diskalifiye (DSQ / disk.) veya terk/katılmadı sporcuların TAMAMINI eksiksiz çıkar.
ÇOK ÖNEMLİ KURALLAR:
- Her bir sporcu kaydında "sporcu" (Ad Soyad), "dogum_yili" (2 veya 4 haneli yıl), "kulup" ve "derece" alanlarını MUTLAKA doldur.
- "derece" alanına ASLA sporcu adı veya kulüp adı YAZMA! "derece" alanı SADECE yüzme süresi (örn: "32.45", "1:08.12", "2:24.80") veya "DSQ", "DNS", "DNF" olabilir.
- TYF sonuç listelerinde sütun sırası genellikle: [Sıra] [Sporcu Adı Soyadı] [Doğum Yılı (YB)] [Kulübü] [Derece (Zaman)] [Puan / Baraj] şeklindedir. Sütunları kesinlikle kaydırma!
- Ara geçiş derecelerini (50m:, 100m:, 150m: vb. split zamanları) ayrı satır veya sonuç olarak EKLEME, sadece sporcunun nihai bitiş derecesini al.
- Sayfada birden fazla yaş kategorisi başlığı varsa sadece sonuncuyu veya sadece diskalifiyeleri değil, sayfanın başından sonuna kadar TÜM sıralanmış sporcuları çıkar.

Format:
{{
  "musabaka_adi": string veya null,
  "sehir": string veya null,
  "tarih": string veya null,
  "yaris_no": integer veya null,
  "cinsiyet": string veya null,
  "mesafe": integer veya null,
  "stil": string veya null,
  "yas_grubu": string veya null,
  "kayitlar": [
    {{
      "id": integer veya null,
      "sira": integer veya string,
      "sporcu": string,
      "dogum_yili": string,
      "kulup": string,
      "derece": string,
      "puan": integer veya null,
      "yas_grubu": string veya null,
      "baraj": string veya null,
      "diskalifiye": boolean
    }}
  ]
}}
SADECE geçerli JSON döndür."""
        else:
            prompt = f"""Bu bir TYF Splash Meet Manager START LİSTESİ PDF sayfasıdır.
Sayfa {p_num}/{total_pages}.
{'1. Başlıktan musabaka_adi, sehir, tarih (YYYY-MM-DD), yaris_no (sadece sayı), cinsiyet (Erkek/Kadın), mesafe (m tam sayı), stil ve yas_grubu çıkar.' if is_first else ''}
{text_hint}
2. Sayfadaki her seriyi ve her kulvardaki sporcuları eksiksiz çıkar.
Format:
{{
  "musabaka_adi": string veya null,
  "sehir": string veya null,
  "tarih": string veya null,
  "yaris_no": integer veya null,
  "cinsiyet": string veya null,
  "mesafe": integer veya null,
  "stil": string veya null,
  "yas_grubu": string veya null,
  "kayitlar": [
    {{
      "seri": string,
      "kulvar": integer,
      "sporcu": string,
      "dogum_yili": string,
      "kulup": string,
      "giris_derecesi": string
    }}
  ]
}}
SADECE geçerli JSON döndür."""

        part = types.Part.from_bytes(data=p_bytes, mime_type="application/pdf")
        last_err = None
        for attempt in range(1, 4):
            try:
                res = client.models.generate_content(
                    model=model,
                    contents=[part, prompt],
                    config=types.GenerateContentConfig(response_mime_type="application/json", temperature=0.0)
                )
                raw = (res.text or "").strip()
                if raw.startswith("```"):
                    raw = re.sub(r"^```(?:json)?\s*", "", raw)
                    raw = re.sub(r"\s*```$", "", raw)
                parsed_json = json.loads(raw)
                if isinstance(parsed_json, list):
                    parsed_json = {"kayitlar": parsed_json}
                elif not isinstance(parsed_json, dict):
                    parsed_json = {"kayitlar": []}
                return p_idx, parsed_json
            except Exception as e:
                last_err = e
                print(f"  [!] Sayfa {p_num}/{total_pages} Gemini ayrıştırma hatası (Deneme {attempt}/3): {e}")
                if attempt < 3:
                    time.sleep(2 * attempt)
        raise RuntimeError(f"Sayfa {p_num}/{total_pages} ayrıştırılamadı: {last_err}")

    with ThreadPoolExecutor(max_workers=min(total_pages, 4)) as ex:
        results = list(ex.map(process_page, pages_bytes))

    results.sort(key=lambda x: x[0])
    raw_all_records = []
    for p_idx, p_data in results:
        if not isinstance(p_data, dict):
            continue
        if p_idx == 0:
            for k in ["musabaka_adi", "sehir", "tarih", "yaris_no", "cinsiyet", "mesafe", "stil", "yas_grubu"]:
                if p_data.get(k):
                    header_data[k] = p_data[k]
        records = p_data.get("kayitlar", [])
        if isinstance(records, list):
            raw_all_records.extend(records)
        new_swimmers = p_data.get("yeni_sporcular", [])
        if isinstance(new_swimmers, list):
            raw_all_records.extend(new_swimmers)

    # Yaris numarası dosya adından geliyorsa ve Gemini boş/farklı döndürdüyse dosya adını baz al
    if fallback_race_no:
        header_data["yaris_no"] = int(fallback_race_no) if fallback_race_no.isdigit() else fallback_race_no

    header_data["kayitlar"] = sanitize_and_match_records(
        raw_all_records,
        doc_type=doc_type,
        startlist_swimmers=startlist_swimmers
    )
    header_data["yeni_sporcular"] = []

    return header_data


# Geriye dönük uyumluluk için takma ad
parse_start_list_pdf = parse_meet_pdf


def post_to_django(
    django_url: str,
    payload: Dict[str, Any],
    api_key: Optional[str] = None,
    max_retries: int = 3,
    verify_records: bool = False
) -> bool:
    """
    Django API'ye veriyi POST eder.
    verify_records=True ise (/api/canli-aktar/ için) dönen JSON içindeki
    eklenen/güncellenen/mükerrer kayıt sayısının > 0 olduğunu da doğrular.
    """
    data_json = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if api_key:
        headers["X-Api-Key"] = api_key

    for attempt in range(1, max_retries + 1):
        try:
            req = urllib.request.Request(django_url, data=data_json, headers=headers)
            with urllib.request.urlopen(req, context=get_ssl_context(), timeout=90) as resp:
                resp_body = resp.read().decode("utf-8", errors="ignore")
                if resp.status in (200, 201):
                    if not verify_records:
                        return True
                    try:
                        resp_json = json.loads(resp_body)
                    except Exception:
                        resp_json = {}
                    if resp_json.get("durum") == "basarili":
                        ist = resp_json.get("istatistikler") or {}
                        processed_total = (
                            int(ist.get("eklenen_sonuc_sayisi") or 0) +
                            int(ist.get("guncellenen_sonuc_sayisi") or 0) +
                            int(ist.get("mukerrer_atlanilan_sayisi") or 0)
                        )
                        if processed_total > 0:
                            return True
                        print(f"  [!] Uyarı: Django 200 döndü ancak 0 kayıt işlendi ({django_url} - Deneme {attempt}/{max_retries}). Yanıt: {resp_body[:200]}")
                    else:
                        print(f"  [!] Uyarı: Django başarısız durum döndü ({django_url} - Deneme {attempt}/{max_retries}): {resp_body[:200]}")
        except Exception as e:
            print(f"  [!] Django aktarım hatası ({django_url} - Deneme {attempt}/{max_retries}): {e}")
        if attempt < max_retries:
            time.sleep(3 * attempt)
    return False


def deliver_and_verify_race_payload(
    base_url: str,
    event_id: Any,
    filename: str,
    meta: Dict[str, Any],
    parsed_payload: Dict[str, Any],
    api_key: Optional[str] = None,
    max_attempts: int = 3
) -> bool:
    """
    Ayrıştırılan PDF verisini Django'ya POST eder ve ardından /api/canli-dosya-kontrol/
    üzerinden verinin veritabanına gerçekten yazıldığını (eşleştirme/lock yüzünden düşmediğini)
    doğrular. Doğrulama başarısızsa yeniden gönderir.
    """
    aktar_url = get_endpoint_url(base_url, "canli-aktar")
    for attempt in range(1, max_attempts + 1):
        posted = post_to_django(aktar_url, parsed_payload, api_key=api_key, max_retries=2, verify_records=True)
        if posted:
            # Eşleştirme ve transaction commit sonrası veritabanından teyit al
            ok, check_data = verify_file_saved_in_django(base_url, event_id, filename, meta, api_key=api_key)
            if ok:
                return True
            print(f"  [!] POST sonrası DB doğrulaması başarısız ({filename} - Deneme {attempt}/{max_attempts}): {check_data}")
        if attempt < max_attempts:
            time.sleep(3 * attempt)
    return False


def process_single_meet(
    meet: Dict[str, Any],
    base_url: str,
    client: genai.Client,
    model: str = DEFAULT_MODEL,
    limit: Optional[int] = None,
    batch_size: Optional[int] = None,
    api_key: Optional[str] = None
) -> Dict[str, Any]:
    """
    Tek bir canlı yarışın web sayfasını inceler:
    1. Django'dan bilinen tüm işlenmiş dosyaları tek sorguda çeker (/api/canli-dosya-kontrol/).
    2. Daha önce işlenmiş (ISLENDI) ve veritabanında geçerli kaydı bulunan dosyaları SIFIR indirme ile atlar.
    3. Henüz işlenmemiş veya verisi eksik/bozuk dosyaları BATCH_SIZE (varsayılan 5) gruplar halinde işler.
    4. Sırada bekleyen dosya varsa durumu 'ISLENIYOR' olarak korur (sonraki Scheduler tetiklemesi devam ettirir).
    5. Tüm dosyalar bittiğinde durumu 'TAMAMLANDI' yapar.
    """
    event_id = meet.get("id")
    event_url = meet.get("canli_url") or meet.get("event_url")

    if not event_url:
        return {"durum": "HATA", "mesaj": "Geçersiz yarış URL'si."}

    print(f"\n=======================================================")
    print(f"[*] Canlı Yarış İnceleniyor: ID #{event_id} - {event_url}")
    print(f"=======================================================")

    stats = {
        "event_id": event_id,
        "event_url": event_url,
        "durum": "ISLENIYOR",
        "musabaka_adi": meet.get("musabaka_adi", ""),
        "sehir": meet.get("sehir", ""),
        "tarih": meet.get("tarih", ""),
        "toplam_start_listesi": 0,
        "islenen_start_listesi": 0,
        "toplam_sonuc_listesi": 0,
        "islenen_sonuc_listesi": 0,
        "basarili": 0,
        "atlanilan": 0,
        "hatali": 0,
        "kalan_dosya": 0,
        "toplam_sporcu": 0,
        "hatalar": []
    }

    try:
        # 1. Sayfayı tara, başlık ve PDF linklerini çek
        meet_title, city, date_str, start_date, end_date, all_pdf_urls = fetch_meet_pdf_urls(event_url, mode="all")
        if meet_title:
            stats["musabaka_adi"] = meet_title
        if city:
            stats["sehir"] = city
        if date_str or start_date:
            stats["tarih"] = date_str or start_date

        start_urls = [u for u in all_pdf_urls if detect_pdf_type(u, b"") == "start_listesi"]
        result_urls = [u for u in all_pdf_urls if detect_pdf_type(u, b"") == "sonuc_listesi"]

        stats["toplam_start_listesi"] = len(start_urls)
        stats["toplam_sonuc_listesi"] = len(result_urls)

        # 2. Django'dan daha önce işlenmiş dosyaları TEK HTTP çağrısında çek (Bulk check)
        known_files = fetch_known_files_map(base_url, event_id, api_key=api_key)
        print(f"[*] Django'dan {len(known_files)} adet kayıtlı dosya bilgisi alındı.")

        # 3. TYF sunucusundan ETag ve Last-Modified başlıklarını paralel HTTP HEAD ile çek (0 bayt indirme, ~0.3 sn)
        remote_headers = fetch_remote_headers_map(all_pdf_urls)

        def is_file_unchanged(fname: str) -> bool:
            kf = known_files.get(fname)
            if not kf or kf.get("durum") != "ISLENDI":
                return False
            # Django veritabanında bu dosyanın kayıtları eksik veya bozuksa yeniden işle
            if kf.get("veri_gecerli_mi") is False:
                return False
            if int(kf.get("kayit_sayisi") or 0) <= 0:
                return False
            if "db_kayit_sayisi" in kf and int(kf.get("db_kayit_sayisi") or 0) <= 0:
                return False

            rh = remote_headers.get(fname) or {}
            known_etag = (kf.get("etag") or "").strip('"')
            remote_etag = (rh.get("etag") or "").strip('"')
            known_lm = (kf.get("last_modified") or "").strip()
            remote_lm = (rh.get("last_modified") or "").strip()

            # ETag veya Last-Modified ile kontrol et
            if remote_etag and known_etag:
                return remote_etag == known_etag
            if remote_lm and known_lm:
                return remote_lm == known_lm
            return True  # Her ikisi de yoksa önceden işlenmiş ve verisi doğrulanmış ISLENDI durumunu kabul et

        # İndirmeden filtreleme (ETag / Last-Modified eşleşenler 0 bayt ile atlanır)
        pending_start_urls = []
        already_done_starts = 0
        for u in start_urls:
            fname = os.path.basename(u)
            if is_file_unchanged(fname):
                already_done_starts += 1
            else:
                pending_start_urls.append(u)

        pending_result_urls = []
        already_done_results = 0
        for u in result_urls:
            fname = os.path.basename(u)
            if is_file_unchanged(fname):
                already_done_results += 1
            else:
                pending_result_urls.append(u)

        stats["islenen_start_listesi"] = already_done_starts
        stats["islenen_sonuc_listesi"] = already_done_results
        stats["atlanilan"] = already_done_starts + already_done_results

        # Django'ya mevcut ilerleme durumunu anında bildir
        update_meet_status(base_url, {
            "event_id": event_id,
            "event_url": event_url,
            "durum": "ISLENIYOR",
            "musabaka_adi": stats["musabaka_adi"],
            "sehir": stats["sehir"],
            "tarih": stats["tarih"],
            "toplam_start_listesi": stats["toplam_start_listesi"],
            "islenen_start_listesi": stats["islenen_start_listesi"],
            "toplam_sonuc_listesi": stats["toplam_sonuc_listesi"],
            "islenen_sonuc_listesi": stats["islenen_sonuc_listesi"]
        }, api_key=api_key)

        print(f"[*] Durum: {len(start_urls)} Start ({already_done_starts} işlenmiş, {len(pending_start_urls)} bekliyor), "
              f"{len(result_urls)} Sonuç ({already_done_results} işlenmiş, {len(pending_result_urls)} bekliyor)")

        # 4. İşlenecek dosyaları sırala (Start listeleri sonuçlardan önce işlenmeli)
        pending_queue = [("start_listesi", u) for u in pending_start_urls] + [("sonuc_listesi", u) for u in pending_result_urls]

        # Eğer hiç bekleyen dosya kalmamışsa doğrudan tamamla!
        if not pending_queue:
            print(f"[*] Tüm dosyalar ({stats['atlanilan']}/{len(all_pdf_urls)}) zaten önceden işlenmiş. İndirme yapılmadan tamamlandı.")
            stats["durum"] = "TAMAMLANDI"
            stats["kalan_dosya"] = 0
            update_meet_status(base_url, stats, api_key=api_key)
            return stats

        # 5. Batch dilimleme (Cloud Run ve PythonAnywhere aşırı yükünü önler)
        effective_batch_size = int(batch_size or DEFAULT_BATCH_SIZE)
        if limit and isinstance(limit, int) and limit > 0:
            effective_batch_size = min(effective_batch_size, limit)

        current_batch = pending_queue[:effective_batch_size]
        remaining_after_batch = len(pending_queue) - len(current_batch)
        print(f"[*] Batch planı: {len(pending_queue)} bekleyen dosya içinden ilk {len(current_batch)} dosya işlenecek (BATCH_SIZE={effective_batch_size}). Kalan dosya: {remaining_after_batch}")

        # 6. Sadece bu batch içindeki dosyaları indir ve işle
        for doc_type, pdf_url in current_batch:
            filename = os.path.basename(pdf_url)
            yaris_no = extract_race_no_from_filename(filename)
            try:
                pdf_bytes, meta = download_file_with_meta(pdf_url)

                if doc_type == "start_listesi":
                    print(f"  [>] {filename} ayrıştırılıyor (Start Listesi - Gemini Flash Lite)...")
                    parsed = parse_meet_pdf(pdf_bytes, client, pdf_url=pdf_url, model=model)
                    parsed["tur"] = "start_listesi"
                    if yaris_no:
                        parsed["yaris_no"] = yaris_no
                    if not parsed.get("musabaka_adi") and stats["musabaka_adi"]:
                        parsed["musabaka_adi"] = stats["musabaka_adi"]
                    if not parsed.get("sehir") and stats["sehir"]:
                        parsed["sehir"] = stats["sehir"]
                    if not parsed.get("tarih") and stats["tarih"]:
                        parsed["tarih"] = stats["tarih"]
                    if start_date and not parsed.get("yaris_tarihi_baslangic"):
                        parsed["yaris_tarihi_baslangic"] = start_date
                    if end_date and not parsed.get("yaris_tarihi_bitis"):
                        parsed["yaris_tarihi_bitis"] = end_date

                    parsed["canli_yaris_id"] = event_id
                    parsed["dosya_adi"] = filename
                    parsed["dosya_url"] = pdf_url
                    parsed["etag"] = meta.get("etag")
                    parsed["content_hash"] = meta.get("content_hash")
                    parsed["last_modified"] = meta.get("last_modified")
                    parsed["dosya_boyutu"] = meta.get("dosya_boyutu")

                    record_count = len(parsed.get("kayitlar", [])) + len(parsed.get("yeni_sporcular", []))
                    if record_count <= 0:
                        raise RuntimeError(f"{filename} içinden hiç geçerli sporcu kaydı çıkarılamadı.")

                    if not deliver_and_verify_race_payload(base_url, event_id, filename, meta, parsed, api_key=api_key):
                        raise RuntimeError(f"Django aktarımı veya DB doğrulaması başarısız oldu ({filename})")

                    stats["basarili"] += 1
                    stats["islenen_start_listesi"] += 1
                    stats["toplam_sporcu"] += record_count
                    print(f"  [+] {filename} başarıyla aktarıldı ve doğrulandı ({record_count} sporcu/kulvar)")

                else:  # sonuc_listesi
                    startlist_swimmers = None
                    if yaris_no:
                        startlist_swimmers = fetch_startlist_swimmers(base_url, event_id, yaris_no, api_key=api_key)
                        if startlist_swimmers:
                            print(f"  [*] Yarış #{yaris_no} için {len(startlist_swimmers)} startlist sporcusu eşleştirme için yüklendi.")

                    print(f"  [>] {filename} ayrıştırılıyor (Sonuç Listesi - Gemini Flash Lite)...")
                    parsed = parse_meet_pdf(pdf_bytes, client, pdf_url=pdf_url, model=model, startlist_swimmers=startlist_swimmers)
                    parsed["tur"] = "sonuc_listesi"
                    if yaris_no:
                        parsed["yaris_no"] = yaris_no
                    if not parsed.get("musabaka_adi") and stats["musabaka_adi"]:
                        parsed["musabaka_adi"] = stats["musabaka_adi"]
                    if not parsed.get("sehir") and stats["sehir"]:
                        parsed["sehir"] = stats["sehir"]
                    if not parsed.get("tarih") and stats["tarih"]:
                        parsed["tarih"] = stats["tarih"]
                    if start_date and not parsed.get("yaris_tarihi_baslangic"):
                        parsed["yaris_tarihi_baslangic"] = start_date
                    if end_date and not parsed.get("yaris_tarihi_bitis"):
                        parsed["yaris_tarihi_bitis"] = end_date

                    parsed["canli_yaris_id"] = event_id
                    parsed["dosya_adi"] = filename
                    parsed["dosya_url"] = pdf_url
                    parsed["etag"] = meta.get("etag")
                    parsed["content_hash"] = meta.get("content_hash")
                    parsed["last_modified"] = meta.get("last_modified")
                    parsed["dosya_boyutu"] = meta.get("dosya_boyutu")

                    record_count = len(parsed.get("kayitlar", [])) + len(parsed.get("yeni_sporcular", []))
                    if record_count <= 0:
                        raise RuntimeError(f"{filename} içinden hiç geçerli sonuç/derece çıkarılamadı.")

                    if not deliver_and_verify_race_payload(base_url, event_id, filename, meta, parsed, api_key=api_key):
                        raise RuntimeError(f"Django aktarımı veya DB doğrulaması başarısız oldu ({filename})")

                    stats["basarili"] += 1
                    stats["islenen_sonuc_listesi"] += 1
                    stats["toplam_sporcu"] += record_count
                    print(f"  [+] {filename} sonuçları başarıyla aktarıldı ve doğrulandı ({record_count} derece)")

                # PythonAnywhere tek iş parçacığına nefes aldır (web ziyaretçileri için)
                time.sleep(1.5)

            except Exception as e:
                err = f"{filename} ({doc_type}): {str(e)}"
                print(f"  [!] Hata: {err}")
                stats["hatali"] += 1
                stats["hatalar"].append(err)

        stats["kalan_dosya"] = remaining_after_batch

    except Exception as e:
        err = f"Genel Tarama Hatası ({event_url}): {str(e)}"
        print(f"[!] {err}")
        stats["hatali"] += 1
        stats["hatalar"].append(err)

    # 7. Nihai durum tespiti: Sırada bekleyen dosya var mı?
    if stats.get("kalan_dosya", 0) > 0:
        stats["durum"] = "ISLENIYOR"
        print(f"[*] Batch tamamlandı ({len(current_batch)} dosya). Sırada {stats['kalan_dosya']} dosya var. Durum ISLENIYOR olarak bırakıldı.")
    else:
        if (stats["basarili"] + stats["atlanilan"]) == 0 and stats["hatali"] > 0:
            stats["durum"] = "HATA"
        else:
            stats["durum"] = "TAMAMLANDI"
        print(f"[*] Müsabaka #{event_id} tamamen bitti: Durum={stats['durum']}")

    # Django'da son durumu kaydet
    update_meet_status(base_url, stats, api_key=api_key)
    print(f"[*] Özet: Durum={stats['durum']}, Başarılı={stats['basarili']}, Atlanılan={stats['atlanilan']}, Hatalı={stats['hatali']}, Kalan={stats.get('kalan_dosya', 0)}\n")
    return stats


def tyf_startlist_handler(request):
    """
    Google Cloud Functions (gen2) / Cloud Run HTTP Handler.
    Cloud Scheduler tarafından periyodik (ör: her 5 veya 10 dk) tetiklendiğinde:
    1. Django API'den bekleyen canlı yarışları çeker (GET /api/canli-bekleyen-yarislar/).
    2. Bekleyen yarış yoksa 0.5 saniyede 200 OK dönerek Cloud Run örneğini sonlandırır (maliyet tasarrufu).
    3. Bekleyen yarış varsa sırayla start ve sonuç listelerini inceleyip,
       BATCH_SIZE kadar yeni/değişen dosyayı Gemini ile işler ve Django'ya aktarır.
    4. İsteğe bağlı olarak tekil bir 'event_url' parametresiyle manuel olarak da çağrılabilir.
    """
    if request.method == "OPTIONS":
        headers = {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, X-Api-Key",
            "Access-Control-Max-Age": "3600"
        }
        return ("", 204, headers)

    req_json = request.get_json(silent=True) or {}

    # Base URL: İstekten veya ortam değişkeninden, varsayılan https://ozztozz.pythonanywhere.com
    base_url = (
        req_json.get("base_url") or
        req_json.get("django_api_url") or
        request.args.get("base_url") or
        request.args.get("django_api_url") or
        os.environ.get("DJANGO_BASE_URL") or
        DEFAULT_DJANGO_BASE_URL
    ).rstrip("/")

    api_key = req_json.get("api_key") or request.args.get("api_key") or os.environ.get("DJANGO_API_KEY")
    gemini_key = req_json.get("gemini_api_key") or os.environ.get("GEMINI_API_KEY")
    model = req_json.get("model") or request.args.get("model") or os.environ.get("GEMINI_MODEL", DEFAULT_MODEL)
    limit = req_json.get("limit") or request.args.get("limit")
    if limit:
        try:
            limit = int(limit)
        except ValueError:
            limit = None

    batch_size = req_json.get("batch_size") or request.args.get("batch_size") or os.environ.get("BATCH_SIZE")
    if batch_size:
        try:
            batch_size = int(batch_size)
        except ValueError:
            batch_size = DEFAULT_BATCH_SIZE
    else:
        batch_size = DEFAULT_BATCH_SIZE

    if not gemini_key:
        return (json.dumps({"durum": "hata", "mesaj": "GEMINI_API_KEY tanımlanmamış."}), 400, {"Content-Type": "application/json"})

    client = genai.Client(api_key=gemini_key.strip().strip("'\""))

    # Tekil URL mi gönderildi yoksa rutin tarama mı?
    event_url = req_json.get("event_url") or request.args.get("event_url")
    event_id = req_json.get("event_id") or request.args.get("event_id")

    if event_url:
        # Tekil test/manuel çalıştırma modu
        meet = {
            "id": event_id,
            "canli_url": event_url,
            "musabaka_adi": req_json.get("musabaka_adi", "")
        }
        stats = process_single_meet(meet, base_url, client, model=model, limit=limit, batch_size=batch_size, api_key=api_key)
        return (json.dumps(stats, ensure_ascii=False), 200, {"Content-Type": "application/json; charset=utf-8"})

    # Rutin Tarama Modu (Cloud Scheduler cron)
    print(f"[*] Rutin Tarama Başlatıldı. Hedef: {base_url} (BATCH_SIZE={batch_size})")
    pending_meets = fetch_pending_meets(base_url, api_key=api_key)

    if not pending_meets:
        msg = "Bekleyen veya işlemde olan canlı yarış bulunamadı. Görev sonlandırıldı."
        print(f"[*] {msg}")
        return (json.dumps({
            "durum": "TAMAMLANDI",
            "mesaj": msg,
            "islenen_yaris_sayisi": 0
        }, ensure_ascii=False), 200, {"Content-Type": "application/json; charset=utf-8"})

    print(f"[*] {len(pending_meets)} adet bekleyen/işlemde canlı yarış bulundu.")
    reports = []
    for meet in pending_meets:
        rep = process_single_meet(meet, base_url, client, model=model, limit=limit, batch_size=batch_size, api_key=api_key)
        reports.append(rep)

    return (json.dumps({
        "durum": "TAMAMLANDI",
        "toplam_yaris": len(pending_meets),
        "raporlar": reports
    }, ensure_ascii=False), 200, {"Content-Type": "application/json; charset=utf-8"})


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="TYF Canlı Yarış Tarayıcısı (Cloud Run / CLI Runner)")
    parser.add_argument("--base-url", default=DEFAULT_DJANGO_BASE_URL, help="Django ana web adresi (Varsayılan: https://ozztozz.pythonanywhere.com)")
    parser.add_argument("--url", default=None, help="Doğrudan belirli bir canlı yarış URL'sini tara")
    parser.add_argument("--id", default=None, help="Yarış ID (isteğe bağlı)")
    parser.add_argument("--limit", type=int, default=None, help="Her yarış için taranacak azami PDF sayısı")
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE, help="Tek seferde işlenecek azami PDF sayısı (Varsayılan: 5)")
    parser.add_argument("--model", default=DEFAULT_MODEL, help="Gemini Model Adı")
    args = parser.parse_args()

    gemini_key = os.environ.get("GEMINI_API_KEY")
    if not gemini_key:
        print("[!] Hata: GEMINI_API_KEY bulunamadı. Lütfen .env dosyasında veya ortam değişkenlerinde tanımlayın.")
        exit(1)

    client = genai.Client(api_key=gemini_key.strip().strip("'\""))
    target_base = args.base_url.rstrip("/")

    if args.url:
        meet = {"id": args.id, "canli_url": args.url}
        rep = process_single_meet(meet, target_base, client, model=args.model, limit=args.limit, batch_size=args.batch_size)
        print(json.dumps(rep, indent=2, ensure_ascii=False))
    else:
        print(f"[*] Rutin Tarama: {target_base} adresindeki bekleyen yarışlar sorgulanıyor (BATCH_SIZE={args.batch_size})...")
        pending = fetch_pending_meets(target_base)
        if not pending:
            print("[*] Bekleyen veya işlemde olan canlı yarış bulunamadı.")
        else:
            print(f"[*] {len(pending)} adet bekleyen yarış bulundu.")
            for m in pending:
                process_single_meet(m, target_base, client, model=args.model, limit=args.limit, batch_size=args.batch_size)


