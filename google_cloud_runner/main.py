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
import json
import time
import hashlib
from urllib.parse import urljoin
from typing import Dict, List, Any, Optional, Tuple
from concurrent.futures import ThreadPoolExecutor

import requests
from requests.adapters import HTTPAdapter
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

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
STARTLIST_POST_DELAY_SEC = max(120, int(os.environ.get("STARTLIST_POST_DELAY_SEC", 60)))

# Kalıcı TCP/TLS bağlantı havuzu (HTTP Keep-Alive ile tekrarlı el sıkışma yükünü önler)
_HTTP_SESSION: Optional[requests.Session] = None
_FALLBACK_GEMINI_CLIENT: Optional[genai.Client] = None
_USE_FALLBACK_KEY: bool = False


def _is_quota_error(exc: Exception) -> bool:
    """Hatanın Gemini API kota / rate limit (429 / RESOURCE_EXHAUSTED) kaynaklı olup olmadığını kontrol eder."""
    msg = str(exc).lower()
    return any(tok in msg for tok in ("429", "resource_exhausted", "quota", "rate limit", "ratelimit", "too many requests", "exhausted"))


def get_fallback_gemini_client() -> Optional[genai.Client]:
    """Ortam değişkenlerinde tanımlıysa GEMINI_API_KEY_2 ile yedek istemci döndürür."""
    global _FALLBACK_GEMINI_CLIENT
    if _FALLBACK_GEMINI_CLIENT is None:
        key2 = (os.environ.get("GEMINI_API_KEY_2") or "").strip().strip("'\"")
        if key2:
            _FALLBACK_GEMINI_CLIENT = genai.Client(api_key=key2)
    return _FALLBACK_GEMINI_CLIENT


def generate_content_with_fallback(
    primary_client: genai.Client,
    model: str,
    contents: List[Any],
    config: types.GenerateContentConfig
):
    """
    Önce birincil GEMINI_API_KEY ile istek atar; kota/limit hatası alınırsa
    otomatik olarak GEMINI_API_KEY_2'ye geçer ve kalan isteklerde yedek anahtarı kullanır.
    """
    global _USE_FALLBACK_KEY
    fallback_client = get_fallback_gemini_client()

    if _USE_FALLBACK_KEY and fallback_client is not None:
        return fallback_client.models.generate_content(model=model, contents=contents, config=config)

    try:
        return primary_client.models.generate_content(model=model, contents=contents, config=config)
    except Exception as e:
        if fallback_client is not None and _is_quota_error(e):
            _USE_FALLBACK_KEY = True
            print(f"  [!] GEMINI_API_KEY kota hatası verdi ({e}). GEMINI_API_KEY_2 ile devam ediliyor...")
            return fallback_client.models.generate_content(model=model, contents=contents, config=config)
        raise


def get_http_session() -> requests.Session:
    global _HTTP_SESSION
    if _HTTP_SESSION is None:
        session = requests.Session()
        session.verify = False
        session.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Connection": "keep-alive"
        })
        adapter = HTTPAdapter(pool_connections=16, pool_maxsize=16)
        session.mount("https://", adapter)
        session.mount("http://", adapter)
        _HTTP_SESSION = session
    return _HTTP_SESSION


def download_bytes(url: str) -> bytes:
    resp = get_http_session().get(url, timeout=30)
    resp.raise_for_status()
    return resp.content


def download_file_with_meta(url: str) -> Tuple[bytes, Dict[str, Any]]:
    """Dosyayı indirir ve ETag, Last-Modified meta verilerini çıkarır."""
    resp = get_http_session().get(url, timeout=30)
    resp.raise_for_status()
    content = resp.content
    etag = (resp.headers.get("ETag") or "").strip('"')
    last_modified = resp.headers.get("Last-Modified") or ""
    meta = {
        "etag": etag,
        "last_modified": last_modified,
        "dosya_boyutu": len(content)
    }
    return content, meta


def get_remote_file_header(url: str) -> Tuple[str, Dict[str, str]]:
    """HTTP HEAD isteği ile dosyanın ETag ve Last-Modified başlıklarını çeker (0 bayt veri tüketir)."""
    try:
        resp = get_http_session().head(url, timeout=10, allow_redirects=True)
        if resp.ok:
            etag = (resp.headers.get("ETag") or "").strip('"')
            last_modified = resp.headers.get("Last-Modified") or ""
            return url, {"etag": etag, "last_modified": last_modified}
    except Exception:
        pass
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
    Django API'den dosyanın daha önce işlenip işlenmediğini ve değişip değişmediğini kontrol eder.
    Eğer dosya daha önce işlenmişse ve ETag/Hash aynıysa gereksiz Gemini çağrısını önler.
    """
    if not django_url or not event_id:
        return False
    check_api = get_endpoint_url(django_url, "canli-dosya-kontrol")
    payload = {
        "canli_yaris_id": event_id,
        "dosya_adi": filename,
        "etag": meta.get("etag"),
        "last_modified": meta.get("last_modified"),
        "dosya_boyutu": meta.get("dosya_boyutu")
    }
    try:
        headers = {"Content-Type": "application/json; charset=utf-8"}
        if api_key:
            headers["X-Api-Key"] = api_key
        resp = get_http_session().post(check_api, json=payload, headers=headers, timeout=25)
        resp.raise_for_status()
        data = resp.json()
        return bool(data.get("islenmis_mi") is True and data.get("degisti_mi") is False)
    except Exception as e:
        print(f"  [!] Dosya kontrol hatası ({filename}): {e}")
        return False


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
    headers = {"User-Agent": "TYF-CloudRunner/1.0"}
    if api_key:
        headers["X-Api-Key"] = api_key
    try:
        resp = get_http_session().get(endpoint, params={"event_id": event_id}, headers=headers, timeout=15)
        resp.raise_for_status()
        data = resp.json()
        if data.get("durum") == "basarili":
            return data.get("dosyalar", {})
    except Exception as e:
        print(f"  [!] Toplu dosya kontrolü hatası ({endpoint}): {e}")
    return {}


def fetch_startlist_swimmers(django_url: str, event_id: Any, yaris_no: str, api_key: Optional[str] = None) -> List[Dict[str, Any]]:
    """Django API'den o yarışın start listesindeki sporcularını ve sonuc ID'lerini çeker."""
    if not django_url:
        return []
    base_api = get_endpoint_url(django_url, "canli-startlist-sporculari")
    headers = {"User-Agent": "TYF-LiveRunner"}
    if api_key:
        headers["X-Api-Key"] = api_key
    try:
        resp = get_http_session().get(base_api, params={"event_id": event_id, "yaris_no": yaris_no}, headers=headers, timeout=15)
        resp.raise_for_status()
        data = resp.json()
        return data.get("sporcular", [])
    except Exception as e:
        print(f"  [!] Start listesi sporcuları çekilemedi ({base_api}): {e}")
        return []


def fetch_pending_meets(base_url: str, api_key: Optional[str] = None) -> List[Dict[str, Any]]:
    """Django API'den BEKLIYOR veya ISLENIYOR durumundaki canlı yarışları çeker."""
    endpoint = get_endpoint_url(base_url, "canli-bekleyen-yarislar")
    headers = {"User-Agent": "TYF-CloudRunner/1.0"}
    if api_key:
        headers["X-Api-Key"] = api_key
    try:
        resp = get_http_session().get(endpoint, headers=headers, timeout=20)
        resp.raise_for_status()
        data = resp.json()
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


def parse_reglaman_pdf(reglaman_url: str, client: genai.Client, model: str = DEFAULT_MODEL) -> Dict[str, Any]:
    """
    Müsabaka reglaman PDF dosyasını indirir ve Gemini ile katılım baraj süreleri tablosunu ayrıştırır.
    Her zaman baraj olmayabileceğinden baraj bulunamazsa veya hata olursa boş veriyle döner (opsiyonel).
    """
    if not reglaman_url:
        return {"barajlar_var_mi": False, "barajlar": []}

    print(f"[*] Reglaman PDF ayrıştırılıyor: {reglaman_url}")
    try:
        pdf_bytes = download_bytes(reglaman_url)
    except Exception as e:
        print(f"  [!] Reglaman PDF indirilemedi ({reglaman_url}): {e}")
        return {"barajlar_var_mi": False, "barajlar": []}

    prompt = """Bu bir Türkiye Yüzme Federasyonu (TYF) yarış reglamanı PDF dosyasıdır.
PDF içerisindeki katılım baraj süreleri (baraj dereceleri) tablosunu bul ve ayrıştır.
Her bir baraj satırını şu formatta JSON olarak listele:
{
  "barajlar_var_mi": true veya false,
  "baraj_adi": "11-12 Yaş Bölge/Final Barajları..." gibi başlık veya null,
  "barajlar": [
    {
      "cinsiyet": "KADIN" veya "ERKEK",
      "yas": 11 (veya "11", "11-12", "11 YAŞ (2015)" gibi yaş/yaş grubu),
      "mesafe": 50 (metre, tam sayı: 50, 100, 200, 400, 800, 1500),
      "stil": "SERBEST" veya "SIRTÜSTÜ" veya "KURBAĞALAMA" veya "KELEBEK" veya "KARIŞIK",
      "baraj_derecesi": "00:34.50" (veya "34.50", "01:12.99" - varsa virgülü noktaya çevir),
      "seviye": "KATILIM" veya "A1" veya "A2" veya "B1" veya null
    }
  ]
}

Eğer belgede herhangi bir baraj tablosu veya baraj süresi yoksa "barajlar_var_mi": false ve "barajlar": [] döndür.
SADECE geçerli bir JSON nesnesi döndür."""

    try:
        part = types.Part.from_bytes(data=pdf_bytes, mime_type="application/pdf")
        res = generate_content_with_fallback(
            primary_client=client,
            model=model,
            contents=[part, prompt],
            config=types.GenerateContentConfig(response_mime_type="application/json", temperature=0.1)
        )
        raw = (res.text or "").strip()
        if raw.startswith("```"):
            raw = re.sub(r"^```(?:json)?\s*", "", raw)
            raw = re.sub(r"\s*```$", "", raw)
        parsed = json.loads(raw)
        if isinstance(parsed, dict) and parsed.get("barajlar_var_mi") and parsed.get("barajlar"):
            for b in parsed["barajlar"]:
                if "baraj_derecesi" in b and isinstance(b["baraj_derecesi"], str):
                    b["baraj_derecesi"] = b["baraj_derecesi"].replace(",", ".")
            print(f"  [+] Reglamandan {len(parsed['barajlar'])} adet baraj derecesi başarıyla çıkarıldı.")
            return parsed
    except Exception as e:
        print(f"  [!] Reglaman baraj ayrıştırma hatası: {e}")

    return {"barajlar_var_mi": False, "barajlar": []}


def normalize_swimming_style(stil: str) -> str:
    s = (stil or "").lower().strip()
    if "serbest" in s or "free" in s:
        return "SERBEST"
    if "sırt" in s or "sirt" in s or "back" in s:
        return "SIRTÜSTÜ"
    if "kurbağ" in s or "kurbag" in s or "breast" in s:
        return "KURBAĞALAMA"
    if "kelebek" in s or "fly" in s:
        return "KELEBEK"
    if "karışık" in s or "karisik" in s or "medley" in s:
        return "KARIŞIK"
    return (stil or "").upper().strip()


def normalize_gender(cinsiyet: str) -> str:
    c = (cinsiyet or "").lower().strip()
    if "erkek" in c or c.startswith("e") or "boy" in c or "men" in c or "male" in c:
        return "ERKEK"
    if "kadın" in c or "kadin" in c or "kız" in c or "kiz" in c or c.startswith("k") or "girl" in c or "women" in c or "female" in c:
        return "KADIN"
    return (cinsiyet or "").upper().strip()


def get_athlete_age(dogum_yili: Any, date_str: Optional[str] = None) -> Optional[int]:
    if not dogum_yili:
        return None
    try:
        y_int = int(str(dogum_yili).strip())
        if y_int < 100:
            y_int += 2000 if y_int <= 35 else 1900
        ref_year = None
        if date_str:
            m = re.search(r"\b(20\d\d)\b", str(date_str))
            if m:
                ref_year = int(m.group(1))
        if not ref_year:
            ref_year = datetime.now().year
        return max(0, ref_year - y_int)
    except Exception:
        return None


def find_matching_baraj(barajlar: List[Dict[str, Any]], cinsiyet: str, mesafe: Any, stil: str, yas_grubu: Optional[str] = None) -> Optional[str]:
    """Verilen yarış özelliklerine uyan baraj derecesini bulur."""
    if not barajlar:
        return None
    c_norm = normalize_gender(cinsiyet)
    s_norm = normalize_swimming_style(stil)

    try:
        m_val = int(re.search(r'\d+', str(mesafe)).group(0)) if mesafe else None
    except (ValueError, TypeError, AttributeError):
        m_val = None

    target_age_digits = set(re.findall(r'\b\d+\b', str(yas_grubu or '')))

    # 1. Aşama: Yaş, cinsiyet, mesafe ve stil tam eşleşmesi
    for b in barajlar:
        b_c = normalize_gender(b.get("cinsiyet") or "")
        b_s = normalize_swimming_style(b.get("stil") or "")
        try:
            b_m = int(re.search(r'\d+', str(b.get("mesafe"))).group(0)) if b.get("mesafe") else None
        except Exception:
            b_m = None
        b_y_digits = set(re.findall(r'\b\d+\b', str(b.get("yas") or '')))

        c_match = (not c_norm or not b_c or c_norm == b_c)
        s_match = (not s_norm or not b_s or s_norm == b_s)
        m_match = (m_val is None or b_m is None or m_val == b_m)
        y_match = bool(target_age_digits and b_y_digits and (target_age_digits & b_y_digits))

        if c_match and s_match and m_match and y_match:
            return b.get("baraj_derecesi")

    # 2. Aşama: Cinsiyet, mesafe ve stil eşleşmesi (genel)
    for b in barajlar:
        b_c = normalize_gender(b.get("cinsiyet") or "")
        b_s = normalize_swimming_style(b.get("stil") or "")
        try:
            b_m = int(re.search(r'\d+', str(b.get("mesafe"))).group(0)) if b.get("mesafe") else None
        except Exception:
            b_m = None

        c_match = (not c_norm or not b_c or c_norm == b_c)
        s_match = (not s_norm or not b_s or s_norm == b_s)
        m_match = (m_val is None or b_m is None or m_val == b_m)

        if c_match and s_match and m_match:
            return b.get("baraj_derecesi")

    return None


def parse_meet_pdf(
    pdf_bytes: bytes,
    client: genai.Client,
    pdf_url: str = "",
    model: str = DEFAULT_MODEL,
    startlist_swimmers: Optional[List[Dict[str, Any]]] = None,
    barajlar_data: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """PDF sayfalarını Gemini Flash Lite ile paralel olarak yapılandırılmış JSON verisine dönüştürür."""
    doc_type = detect_pdf_type(pdf_url, pdf_bytes)
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    total_pages = len(doc)

    header_data = {
        "tur": doc_type,
        "musabaka_adi": "",
        "sehir": "",
        "tarih": "",
        "yaris_no": None,
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
        single_page_doc = fitz.open()
        single_page_doc.insert_pdf(doc, from_page=page_idx, to_page=page_idx)
        pages_bytes.append((page_idx, single_page_doc.tobytes()))
        single_page_doc.close()
    doc.close()

    def process_page(args):
        p_idx, p_bytes = args
        p_num = p_idx + 1
        is_first = (p_idx == 0)

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
                swimmers_context = f"\nBU YARIŞTA YÜZEN START LİSTESİNDEKİ SPORCULAR (Eşleştirmede bu id değerlerini kullan):\n{json.dumps(candidates, ensure_ascii=False)}\n"

            prompt = f"""Bu bir TYF Splash Meet Manager SONUÇ LİSTESİ PDF sayfasıdır.
Sayfa {p_num}/{total_pages}.
{'1. Başlıktan müsabaka_adı, şehir, tarih (YYYY-MM-DD), yarış_no, cinsiyet (Erkek/Kadın), mesafe (m tam sayı), stil ve yaş_grubu çıkar.' if is_first else ''}
{swimmers_context}
2. Sayfadaki tüm sporcu sonuçlarını eksiksiz çıkar. Listedeki sporcularla eşleştirip "id" değerini ata.
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
      "id": integer veya null (start listesinde eşleşen sporcunun id değeri),
      "sporcu": string,
      "dogum_yili": string,
      "kulup": string,
      "sira": integer veya string,
      "derece": string,
      "puan": integer veya null,
      "baraj": string veya null
    }}
  ],
  "yeni_sporcular": [
    {{
      "sporcu": string,
      "dogum_yili": string,
      "kulup": string,
      "sira": integer veya string,
      "derece": string,
      "puan": integer veya null,
      "baraj": string veya null
    }}
  ]
}}
* Start listesinde olmayan yedek/yeni bir sporcu yüzmüşse onu "yeni_sporcular" listesine ekle.
SADECE JSON nesnesi (object) döndür."""
        else:
            prompt = f"""Bu bir TYF Splash Meet Manager START LİSTESİ PDF sayfasıdır.
Sayfa {p_num}/{total_pages}.
{'1. Başlıktan müsabaka_adı, şehir, tarih (YYYY-MM-DD), yarış_no, cinsiyet (Erkek/Kadın), mesafe (m tam sayı), stil ve yaş_grubu çıkar.' if is_first else ''}
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
SADECE JSON nesnesi (object) döndür."""

        part = types.Part.from_bytes(data=p_bytes, mime_type="application/pdf")
        res = generate_content_with_fallback(
            primary_client=client,
            model=model,
            contents=[part, prompt],
            config=types.GenerateContentConfig(response_mime_type="application/json", temperature=0.1)
        )
        raw = (res.text or "").strip()
        if raw.startswith("```"):
            raw = re.sub(r"^```(?:json)?\s*", "", raw)
            raw = re.sub(r"\s*```$", "", raw)
        parsed_json = json.loads(raw)
        if isinstance(parsed_json, list):
            if len(parsed_json) == 1 and isinstance(parsed_json[0], dict) and (
                "kayitlar" in parsed_json[0] or "yeni_sporcular" in parsed_json[0]
            ):
                parsed_json = parsed_json[0]
            else:
                merged_records = []
                merged_new = []
                header_obj = {}
                for elem in parsed_json:
                    if isinstance(elem, dict):
                        for hk in ("musabaka_adi", "sehir", "tarih", "yaris_no", "cinsiyet", "mesafe", "stil", "yas_grubu"):
                            if elem.get(hk) and not header_obj.get(hk):
                                header_obj[hk] = elem[hk]
                        if "kayitlar" in elem and isinstance(elem["kayitlar"], list):
                            merged_records.extend(elem["kayitlar"])
                        elif "sporcu" in elem or "derece" in elem or "kulvar" in elem:
                            merged_records.append(elem)
                        if "yeni_sporcular" in elem and isinstance(elem["yeni_sporcular"], list):
                            merged_new.extend(elem["yeni_sporcular"])
                header_obj["kayitlar"] = merged_records
                header_obj["yeni_sporcular"] = merged_new
                parsed_json = header_obj
        elif not isinstance(parsed_json, dict):
            parsed_json = {"kayitlar": []}
        return p_idx, parsed_json

    with ThreadPoolExecutor(max_workers=min(total_pages, 6)) as ex:
        results = list(ex.map(process_page, pages_bytes))

    results.sort(key=lambda x: x[0])
    for p_idx, p_data in results:
        if not isinstance(p_data, dict):
            continue
        if p_idx == 0:
            for k in ["musabaka_adi", "sehir", "tarih", "yaris_no", "cinsiyet", "mesafe", "stil", "yas_grubu"]:
                if p_data.get(k):
                    header_data[k] = p_data[k]
        records = p_data.get("kayitlar", [])
        if isinstance(records, list):
            header_data["kayitlar"].extend(records)
        new_swimmers = p_data.get("yeni_sporcular", [])
        if isinstance(new_swimmers, list):
            header_data.setdefault("yeni_sporcular", []).extend(new_swimmers)

    # Baraj derecelerini eşleştir ve ekle
    if barajlar_data and barajlar_data.get("barajlar"):
        b_list = barajlar_data["barajlar"]
        event_baraj = find_matching_baraj(
            b_list,
            cinsiyet=header_data.get("cinsiyet"),
            mesafe=header_data.get("mesafe"),
            stil=header_data.get("stil"),
            yas_grubu=header_data.get("yas_grubu")
        )
        if event_baraj:
            header_data["baraj_derecesi"] = event_baraj

        all_records = header_data.get("kayitlar", []) + header_data.get("yeni_sporcular", [])
        for rec in all_records:
            if not rec.get("baraj"):
                ath_age = get_athlete_age(rec.get("dogum_yili"), header_data.get("tarih"))
                swimmer_baraj = find_matching_baraj(
                    b_list,
                    cinsiyet=header_data.get("cinsiyet"),
                    mesafe=header_data.get("mesafe"),
                    stil=header_data.get("stil"),
                    yas_grubu=str(ath_age) if ath_age else header_data.get("yas_grubu")
                )
                if swimmer_baraj:
                    rec["baraj"] = swimmer_baraj
                elif event_baraj:
                    rec["baraj"] = event_baraj

    return header_data


# Geriye dönük uyumluluk için takma ad
parse_start_list_pdf = parse_meet_pdf


def post_to_django(django_url: str, payload: Dict[str, Any], api_key: Optional[str] = None, max_retries: int = 3) -> bool:
    """Django API'ye veriyi kalıcı HTTP oturumu (Keep-Alive) üzerinden POST eder."""
    data_json = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if api_key:
        headers["X-Api-Key"] = api_key

    session = get_http_session()
    for attempt in range(1, max_retries + 1):
        try:
            resp = session.post(django_url, data=data_json, headers=headers, timeout=120)
            if resp.status_code in (200, 201):
                return True
            print(f"  [!] Django HTTP {resp.status_code} yanıtı ({django_url} - Deneme {attempt}/{max_retries}): {resp.text[:200]}")
        except Exception as e:
            print(f"  [!] Django aktarım hatası ({django_url} - Deneme {attempt}/{max_retries}): {e}")
        if attempt < max_retries:
            time.sleep(4)
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
    2. Daha önce işlenmiş (ISLENDI) dosyaları SIFIR indirme ile atlar (Ağ ve CPU tasarrufu).
    3. Henüz işlenmemiş dosyaları BATCH_SIZE (varsayılan 5) gruplar halinde işler.
    4. Sırada bekleyen dosya varsa durumu 'ISLENIYOR' olarak korur (sonraki Scheduler tetiklemesi devam ettirir).
    5. Tüm dosyalar bittiğinde durumu 'TAMAMLANDI' yapar.
    """
    event_id = meet.get("id")
    event_url = meet.get("canli_url") or meet.get("yaris_url") or meet.get("event_url")
    reglaman_linki = meet.get("reglaman_linki") or ""
    barajlar_data = meet.get("barajlar") or {}

    if not event_url:
        return {"durum": "HATA", "mesaj": "Geçersiz yarış URL'si."}

    print(f"\n=======================================================")
    print(f"[*] Canlı Yarış İnceleniyor: ID #{event_id} - {event_url}")
    if reglaman_linki:
        print(f"[*] Reglaman Linki: {reglaman_linki}")
    print(f"=======================================================")

    stats = {
        "event_id": event_id,
        "event_url": event_url,
        "reglaman_linki": reglaman_linki,
        "barajlar": barajlar_data,
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
        # Reglaman PDF ve Katılım Barajları Kontrolü (Opsiyonel)
        if reglaman_linki and (not barajlar_data or not barajlar_data.get("barajlar")):
            print(f"[*] Canlı yarış reglaman linki mevcut, baraj süreleri ayrıştırılıyor: {reglaman_linki}")
            barajlar_data = parse_reglaman_pdf(reglaman_linki, client, model=model)
            if barajlar_data and barajlar_data.get("barajlar"):
                stats["barajlar"] = barajlar_data
                if event_id:
                    update_meet_status(base_url, {
                        "event_id": event_id,
                        "reglaman_linki": reglaman_linki,
                        "barajlar": barajlar_data
                    }, api_key=api_key)
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
            return True  # Her ikisi de yoksa önceden işlenmiş ISLENDI durumunu kabul et

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
            try:
                pdf_bytes, meta = download_file_with_meta(pdf_url)

                if doc_type == "start_listesi":
                    print(f"  [>] {filename} ayrıştırılıyor (Start Listesi - Gemini Flash Lite)...")
                    parsed = parse_meet_pdf(pdf_bytes, client, pdf_url=pdf_url, model=model, barajlar_data=barajlar_data)
                    parsed["tur"] = "start_listesi"
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
                    parsed["last_modified"] = meta.get("last_modified")
                    parsed["dosya_boyutu"] = meta.get("dosya_boyutu")

                    aktar_url = get_endpoint_url(base_url, "canli-aktar")
                    if not post_to_django(aktar_url, parsed, api_key=api_key):
                        raise RuntimeError(f"Django aktarımı başarısız oldu ({aktar_url})")

                    stats["basarili"] += 1
                    stats["islenen_start_listesi"] += 1
                    record_count = len(parsed.get("kayitlar", [])) + len(parsed.get("yeni_sporcular", []))
                    stats["toplam_sporcu"] += record_count
                    print(f"  [+] {filename} başarıyla aktarıldı ({record_count} sporcu/kulvar)")
                    print(f"  [*] Start listesi eşleştirme işlemi için {STARTLIST_POST_DELAY_SEC} sn bekleniyor...")
                    time.sleep(STARTLIST_POST_DELAY_SEC)

                else:  # sonuc_listesi
                    m_no = re.search(r"(?:ResultList|StartList)_(\d+)\.pdf", filename, re.I)
                    if not m_no:
                        m_no = re.search(r"_(\d+)\.pdf", filename, re.I)
                    yaris_no = m_no.group(1) if m_no else None

                    startlist_swimmers = None
                    if yaris_no:
                        startlist_swimmers = fetch_startlist_swimmers(base_url, event_id, yaris_no, api_key=api_key)
                        if startlist_swimmers:
                            print(f"  [*] Yarış #{yaris_no} için {len(startlist_swimmers)} startlist sporcusu eşleştirme için yüklendi.")

                    print(f"  [>] {filename} ayrıştırılıyor (Sonuç Listesi - Gemini Flash Lite)...")
                    parsed = parse_meet_pdf(pdf_bytes, client, pdf_url=pdf_url, model=model, startlist_swimmers=startlist_swimmers, barajlar_data=barajlar_data)
                    parsed["tur"] = "sonuc_listesi"
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
                    parsed["last_modified"] = meta.get("last_modified")
                    parsed["dosya_boyutu"] = meta.get("dosya_boyutu")

                    aktar_url = get_endpoint_url(base_url, "canli-aktar")
                    if not post_to_django(aktar_url, parsed, api_key=api_key):
                        raise RuntimeError(f"Django aktarımı başarısız oldu ({aktar_url})")

                    stats["basarili"] += 1
                    stats["islenen_sonuc_listesi"] += 1
                    record_count = len(parsed.get("kayitlar", [])) + len(parsed.get("yeni_sporcular", []))
                    stats["toplam_sporcu"] += record_count
                    print(f"  [+] {filename} sonuçları başarıyla aktarıldı ({record_count} derece)")

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
    gemini_key = req_json.get("gemini_api_key") or os.environ.get("GEMINI_API_KEY") or os.environ.get("GEMINI_API_KEY_2")
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
    reglaman_linki = req_json.get("reglaman_linki") or request.args.get("reglaman_linki") or ""
    barajlar = req_json.get("barajlar") or {}

    if event_url:
        # Tekil test/manuel çalıştırma modu
        meet = {
            "id": event_id,
            "canli_url": event_url,
            "musabaka_adi": req_json.get("musabaka_adi", ""),
            "reglaman_linki": reglaman_linki,
            "barajlar": barajlar
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
    parser.add_argument("--reglaman", default=None, help="Yarış reglaman PDF linki (baraj sürelerini ayrıştırmak için opsiyonel)")
    args = parser.parse_args()

    gemini_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GEMINI_API_KEY_2")
    if not gemini_key:
        print("[!] Hata: GEMINI_API_KEY veya GEMINI_API_KEY_2 bulunamadı. Lütfen .env dosyasında veya ortam değişkenlerinde tanımlayın.")
        exit(1)

    client = genai.Client(api_key=gemini_key.strip().strip("'\""))
    target_base = args.base_url.rstrip("/")

    if args.url:
        meet = {"id": args.id, "canli_url": args.url, "reglaman_linki": args.reglaman}
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


