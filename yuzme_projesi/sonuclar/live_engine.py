# -*- coding: utf-8 -*-
"""
live_engine.py
==============
TYF Canlı Yarış Takip, Ayrıştırma, Cron Orkestrasyonu ve Sürekli Dinleme Motoru.
(TAMAMEN BAĞIMSIZ - TEK DOSYA MİMARİSİ)

Bu modül başka hiçbir harici klasöre (örn: google_cloud_runner) bağımlı değildir.
Tüm TYF web tarayıcıları, PDF indirme, Gemini/Groq ayrıştırma, sporcu-kulüp eşleme,
FINA puanı hesaplama ve Django ORM veritabanı kayıt mantığı bu dosyada yer alır.

Görevleri:
1. SERVİS 1 (Saatlik Cron Orkestratörü - `run_cron_orchestrator`):
   - Her saat başında çalışır.
   - 08:00 - 19:00 çalışma saatlerini kontrol eder (19:00 - 07:59 arasında çalışmaz).
   - Veritabanında canlı takibi aktif ('ISLENIYOR') veya bekleyen yarış olup olmadığını denetler.
   - Eğer aktif yarış varsa ve 2. Servis çalışmıyorsa arka planda başlatır.
   - 2. Servis zaten çalışıyorsa hiçbir şey yapmaz.

2. SERVİS 2 (10 Saniyelik Canlı Takipçi / Worker - `run_daemon_worker`):
   - 1. Servisin aktivasyonuyla veya arayüzden tetiklenerek ayağa kalkar.
   - PID dosya kilidi ile tekil kopya garantisi sağlar (çift çalışma ve DB kilitlenmelerini önler).
   - Her 10 saniyede bir aktif yarışların TYF sayfalarını hafif HTTP HEAD istekleriyle yoklar.
   - Yeni sonuç/start listesi PDF'i düştüğünde Gemini/Groq ile ayrıştırıp veritabanına atomik olarak yazar.
   - Saat 19:00'a ulaştığında veya takipte yarış kalmadığında kendini güvenle kapatır.
"""

import os
import sys
import re
import time
import json
import signal
import tempfile
import logging
import subprocess
from datetime import datetime, timezone as dt_timezone, timedelta, date
from typing import Dict, List, Any, Optional, Tuple
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urljoin

# Proje dizinini sys.path'e ekle
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(CURRENT_DIR)
if PROJECT_DIR not in sys.path:
    sys.path.insert(0, PROJECT_DIR)

# Django ortamı başlatılmamışsa başlat
if "django" not in sys.modules:
    import django
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "yuzme_projesi.settings")
    django.setup()

import requests
from requests.adapters import HTTPAdapter
from bs4 import BeautifulSoup

try:
    import fitz  # PyMuPDF
except ImportError:
    fitz = None

try:
    from google import genai
    from google.genai import types
except ImportError:
    genai = None
    types = None

from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from sonuclar.models import (
    CanliYaris,
    CanliYarisDosya,
    Event,
    YarisSonucu,
    Kulup,
    Sporcu,
    is_school_team,
)
from sonuclar.athlete_matcher import match_athlete, clean_athlete_name_tags
from sonuclar.turkish_names import standardize_turkish_athlete_name, tr_fold
from sonuclar.fina_calculator import calculate_fina_points, detect_course

# Türkiye Zaman Dilimi (UTC+3)
TR_TIMEZONE = dt_timezone(timedelta(hours=3))

DEFAULT_MODEL = os.environ.get("GEMINI_MODEL", "gemini-flash-lite-latest")
GROQ_API_KEY = (os.environ.get("GROQ_API_KEY") or "").strip().strip("'\"")
GROQ_MODEL = os.environ.get("GROQ_MODEL", "openai/gpt-oss-120b")
TYF_CANLI_SONUC_URL = "https://www.tyf.gov.tr/canli-sonuc/"

LOG_FILE_PATH = os.path.join(tempfile.gettempdir(), "yuzme_live_engine.log")
PID_FILE_PATH = os.path.join(tempfile.gettempdir(), "yuzme_live_engine.pid")

logger = logging.getLogger("LiveEngine")
if not logger.handlers:
    c_handler = logging.StreamHandler()
    c_handler.setFormatter(logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S"))
    logger.addHandler(c_handler)
    try:
        f_handler = logging.FileHandler(LOG_FILE_PATH, encoding="utf-8")
        f_handler.setFormatter(logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S"))
        logger.addHandler(f_handler)
    except Exception:
        pass
    logger.setLevel(logging.INFO)

SHUTDOWN_SIGNAL_RECEIVED = False

_HTTP_SESSION: Optional[requests.Session] = None
_FALLBACK_GEMINI_CLIENT: Optional[genai.Client] = None
_USE_FALLBACK_KEY: bool = False


# ==============================================================================
# 1. HTTP BAĞLANTI HAVUZU VE YARDIMCILAR
# ==============================================================================

def get_http_session() -> requests.Session:
    global _HTTP_SESSION
    if _HTTP_SESSION is None:
        session = requests.Session()
        session.verify = False
        session.headers.update({
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
            ),
            "Connection": "keep-alive"
        })
        adapter = HTTPAdapter(pool_connections=20, pool_maxsize=20, max_retries=1)
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
        "dosya_boyutu": len(content),
    }
    return content, meta


def get_remote_file_header(url: str) -> Tuple[str, Dict[str, str]]:
    """Tek bir URL için HTTP HEAD isteği atarak ETag ve Last-Modified bilgisini döner."""
    try:
        resp = get_http_session().head(url, timeout=8, allow_redirects=True)
        if resp.status_code == 200:
            return url, {
                "etag": (resp.headers.get("ETag") or "").strip('"'),
                "last_modified": resp.headers.get("Last-Modified") or "",
                "dosya_boyutu": int(resp.headers.get("Content-Length") or 0)
            }
    except Exception:
        pass
    return url, {"etag": "", "last_modified": "", "dosya_boyutu": 0}


def fetch_remote_headers_map(urls: List[str]) -> Dict[str, Dict[str, Any]]:
    """Tüm PDF URL'lerinin ETag ve Last-Modified başlıklarını paralel HTTP HEAD ile çeker (~0.2 sn)."""
    if not urls:
        return {}
    headers_map = {}
    with ThreadPoolExecutor(max_workers=10) as executor:
        for u, h in executor.map(get_remote_file_header, urls):
            fname = os.path.basename(u)
            headers_map[fname] = h
    return headers_map


def parse_tr_date_range(d_str: str) -> Tuple[str, str]:
    """Türkçe tarih aralığını ISO formatına dönüştürür (Örn: '30.10. - 1.11.2026' -> '2026-10-30', '2026-11-01')."""
    if not d_str:
        return '', ''
    d_clean = re.sub(r'\s+', ' ', d_str.strip())
    m_diff = re.search(r'(\d{1,2})\.(\d{1,2})\.?(?:\d{4})?\s*-\s*(\d{1,2})\.(\d{1,2})\.(\d{4})', d_clean)
    if m_diff:
        d1, m1, d2, m2, y = m_diff.groups()
        return f'{y}-{int(m1):02d}-{int(d1):02d}', f'{y}-{int(m2):02d}-{int(d2):02d}'

    m_same = re.search(r'(\d{1,2})\.?\s*-\s*(\d{1,2})\.(\d{1,2})\.(\d{4})', d_clean)
    if m_same:
        d1, d2, m, y = m_same.groups()
        return f'{y}-{int(m):02d}-{int(d1):02d}', f'{y}-{int(m):02d}-{int(d2):02d}'

    m_single = re.search(r'(\d{1,2})\.(\d{1,2})\.(\d{4})', d_clean)
    if m_single:
        d, m, y = m_single.groups()
        iso = f'{y}-{int(m):02d}-{int(d):02d}'
        return iso, iso
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

        if matches and h_lower.endswith(".pdf"):
            full_url = urljoin(event_url, href)
            if full_url not in seen:
                seen.add(full_url)
                pdf_urls.append(full_url)

    return meet_title, city, date_str, start_date, end_date, pdf_urls


def detect_pdf_type(pdf_url: str, pdf_bytes: bytes = b"") -> str:
    """PDF URL'sine ve içeriğine göre Start Listesi mi Sonuç Listesi mi olduğunu saptar."""
    u = pdf_url.lower()
    if "resultlist" in u or "result_list" in u or "sonuc" in u:
        return "sonuc_listesi"
    if "startlist" in u or "start_list" in u or "start" in u:
        return "start_listesi"
    if pdf_bytes and fitz is not None:
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


# ==============================================================================
# 2. AI MODEL VE YEDEKLEME (GEMINI + GROQ FALLBACK)
# ==============================================================================

class GroqFallbackResponse:
    """Gemini response nesnesiyle uyumlu (.text özniteliği sağlayan) Groq yanıt sarmalayıcısı."""
    def __init__(self, text: str):
        self.text = text


def call_groq_fallback(contents: List[Any], model: str = GROQ_MODEL) -> GroqFallbackResponse:
    """Gemini anahtarlarının ikisi de kota sınırına ulaştığında Groq API devreye girer."""
    api_key = (os.environ.get("GROQ_API_KEY") or GROQ_API_KEY or "").strip().strip("'\"")
    if not api_key:
        raise RuntimeError("GROQ_API_KEY ortam değişkeni tanımlı değil.")

    pdf_bytes = None
    prompt_parts = []
    for item in contents:
        if isinstance(item, str):
            prompt_parts.append(item)
        elif hasattr(item, "inline_data") and getattr(item.inline_data, "data", None):
            pdf_bytes = item.inline_data.data
        elif isinstance(item, bytes):
            pdf_bytes = item

    doc_text = ""
    if pdf_bytes and fitz is not None:
        try:
            doc = fitz.open(stream=pdf_bytes, filetype="pdf")
            doc_text = "\n".join(page.get_text("text") for page in doc).strip()
            doc.close()
        except Exception:
            doc_text = ""

    full_prompt = "\n\n".join(prompt_parts)
    user_content = f"{full_prompt}\n\n[BELGE METNİ]:\n{doc_text}" if doc_text else full_prompt

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    }
    payload = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": "Sen TYF yüzme yarış listelerini ve sonuçlarını yapılandıran uzman bir veri çıkarıcısısın. SADECE istenen geçerli JSON nesnesini döndür.",
            },
            {"role": "user", "content": user_content},
        ],
        "response_format": {"type": "json_object"},
        "temperature": 0.1,
    }

    res = get_http_session().post(
        "https://api.groq.com/openai/v1/chat/completions",
        headers=headers,
        json=payload,
        timeout=35,
    )
    res.raise_for_status()
    data = res.json()
    res_text = data["choices"][0]["message"]["content"]
    return GroqFallbackResponse(text=res_text)


def _is_quota_error(exc: Exception) -> bool:
    msg = str(exc).lower()
    return any(tok in msg for tok in ("429", "402", "resource_exhausted", "quota", "rate limit", "ratelimit", "too many requests", "exhausted", "depleted"))


def get_fallback_gemini_client() -> Optional[genai.Client]:
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
    3 Kademeli Hiyerarşik Yedekleme:
    1. Birincil GEMINI_API_KEY
    2. GEMINI_API_KEY_2
    3. Groq API (openai/gpt-oss-120b)
    """
    global _USE_FALLBACK_KEY
    fallback_client = get_fallback_gemini_client()
    groq_key = (os.environ.get("GROQ_API_KEY") or GROQ_API_KEY or "").strip().strip("'\"")

    for attempt in range(3):
        use_fallback = (_USE_FALLBACK_KEY and fallback_client is not None)
        client = fallback_client if use_fallback else primary_client
        try:
            return client.models.generate_content(model=model, contents=contents, config=config)
        except Exception as e:
            if _is_quota_error(e):
                if not _USE_FALLBACK_KEY and fallback_client is not None:
                    logger.warning("[!] Birincil Gemini API kotası doldu, GEMINI_API_KEY_2 devreye giriyor...")
                    try:
                        res = fallback_client.models.generate_content(model=model, contents=contents, config=config)
                        _USE_FALLBACK_KEY = True
                        return res
                    except Exception as fb_err:
                        logger.warning(f"[!] GEMINI_API_KEY_2 de kota hatası verdi: {fb_err}")
                        _USE_FALLBACK_KEY = False

                if groq_key:
                    logger.warning("[!] İki Gemini anahtarı da sınırda. 3. aşama olarak Groq API devreye giriyor...")
                    try:
                        return call_groq_fallback(contents)
                    except Exception as groq_err:
                        logger.error(f"[!] Groq API yedek çağrısı da hata verdi: {groq_err}")

                if attempt < 2:
                    wait_sec = 20 + (attempt * 10)
                    logger.info(f"[*] API limiti nedeniyle {wait_sec} sn bekleniyor ({attempt + 1}/2)...")
                    time.sleep(wait_sec)
                    continue
            raise


def safe_json_loads(raw: str) -> Any:
    """Markdown kod bloklarını temizleyerek JSON ayrıştırır."""
    if not raw:
        return {}
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned)
        cleaned = re.sub(r"\s*```$", "", cleaned)
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        m = re.search(r"(\{.*\}|\[.*\])", cleaned, re.DOTALL)
        if m:
            return json.loads(m.group(1))
        raise


def parse_meet_pdf(
    pdf_bytes: bytes,
    client: genai.Client,
    pdf_url: str = "",
    model: str = DEFAULT_MODEL,
) -> Dict[str, Any]:
    """PDF sayfalarını Gemini Flash Lite ile yapılandırılmış JSON verisine dönüştürür."""
    doc_type = detect_pdf_type(pdf_url, pdf_bytes)
    total_pages = 1
    pages_bytes = [(0, pdf_bytes)]
    if fitz is not None:
        try:
            doc = fitz.open(stream=pdf_bytes, filetype="pdf")
            total_pages = len(doc)
            pages_bytes = []
            for page_idx in range(total_pages):
                single_page_doc = fitz.open()
                single_page_doc.insert_pdf(doc, from_page=page_idx, to_page=page_idx)
                pages_bytes.append((page_idx, single_page_doc.tobytes()))
                single_page_doc.close()
            doc.close()
        except Exception:
            pass

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
        "sonuclar": [],
    }

    def process_page(args):
        p_idx, p_bytes = args
        p_num = p_idx + 1
        is_first = (p_idx == 0)

        prompt = f"""Bu bir TYF Splash Meet Manager {'SONUÇ' if doc_type == 'sonuc_listesi' else 'START'} LİSTESİ PDF sayfasıdır.
Sayfa {p_num}/{total_pages}.
{'1. Başlıktan müsabaka_adı, şehir, tarih (YYYY-MM-DD), yarış_no, cinsiyet (Erkek/Kadın), mesafe (m tam sayı), stil ve yaş_grubu çıkar.' if is_first else ''}
2. Sayfadaki tüm sporcu {'sonuçlarını' if doc_type == 'sonuc_listesi' else 'seri ve kulvarlarını'} eksiksiz çıkar.
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
  "sonuclar": [
    {{
      "seri": string veya null,
      "kulvar": integer veya null,
      "sira": integer veya string veya null,
      "ad_soyad": string,
      "dogum_yili": string veya integer veya null,
      "kulup": string veya null,
      "derece": string veya null,
      "puan": integer veya null,
      "durum": string veya null
    }}
  ]
}}
SADECE geçerli JSON nesnesi döndür."""

        part = types.Part.from_bytes(data=p_bytes, mime_type="application/pdf")
        res = generate_content_with_fallback(
            primary_client=client,
            model=model,
            contents=[part, prompt],
            config=types.GenerateContentConfig(response_mime_type="application/json", temperature=0.1)
        )
        return safe_json_loads(res.text or "")

    with ThreadPoolExecutor(max_workers=min(4, total_pages)) as executor:
        for p_data in executor.map(process_page, pages_bytes):
            if isinstance(p_data, dict):
                for k in ("musabaka_adi", "sehir", "tarih", "yaris_no", "cinsiyet", "mesafe", "stil", "yas_grubu"):
                    if p_data.get(k) and not header_data[k]:
                        header_data[k] = p_data[k]
                records = p_data.get("sonuclar") or p_data.get("kayitlar") or []
                for r in records:
                    if not r.get("ad_soyad") and r.get("sporcu"):
                        r["ad_soyad"] = r["sporcu"]
                    header_data["sonuclar"].append(r)

    return header_data


# ==============================================================================
# 3. PROCESS & KİLİT YÖNETİMİ (SINGLETON DAEMON)
# ==============================================================================

def is_pid_running(pid: int) -> bool:
    """Belirtilen PID'ye sahip bir sürecin aktif olup olmadığını denetler."""
    if pid <= 0:
        return False
    try:
        import psutil
        return psutil.pid_exists(pid)
    except Exception:
        try:
            if os.name == 'nt':
                import ctypes
                kernel32 = ctypes.windll.kernel32
                SYNCHRONIZE = 0x00100000
                process = kernel32.OpenProcess(SYNCHRONIZE, False, pid)
                if process:
                    kernel32.CloseHandle(process)
                    return True
                return False
            else:
                os.kill(pid, 0)
                return True
        except (OSError, SystemError):
            return False


def get_running_daemon_pid() -> Optional[int]:
    """Çalışan canlı takip daemon'ının PID'sini döner. Çalışmıyorsa None döner."""
    if not os.path.exists(PID_FILE_PATH):
        return None
    try:
        with open(PID_FILE_PATH, "r", encoding="utf-8") as f:
            content = f.read().strip()
        if not content:
            return None
        pid = int(content)
        if is_pid_running(pid):
            return pid
        else:
            try:
                os.remove(PID_FILE_PATH)
            except OSError:
                pass
            return None
    except Exception:
        return None


def acquire_daemon_lock() -> bool:
    """Bu process için PID kilit dosyasını alır. Başka process varsa False döner."""
    existing_pid = get_running_daemon_pid()
    current_pid = os.getpid()
    if existing_pid is not None and existing_pid != current_pid:
        return False
    try:
        with open(PID_FILE_PATH, "w", encoding="utf-8") as f:
            f.write(str(current_pid))
        return True
    except Exception as e:
        logger.error(f"Kilit dosyası oluşturulamadı: {e}")
        return False


def release_daemon_lock() -> None:
    """PID kilit dosyasını güvenle siler."""
    try:
        if os.path.exists(PID_FILE_PATH):
            os.remove(PID_FILE_PATH)
    except OSError:
        pass


def stop_daemon() -> bool:
    """Çalışan daemon sürecini tespit edip durdurur."""
    pid = get_running_daemon_pid()
    if not pid:
        logger.info("[*] Durdurulacak çalışan daemon bulunamadı.")
        return False
    try:
        logger.info(f"[*] PID {pid} sürecine durdurma sinyali gönderiliyor...")
        if os.name == 'nt':
            subprocess.run(["taskkill", "/PID", str(pid), "/F"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            os.kill(pid, signal.SIGTERM)
        time.sleep(1)
        release_daemon_lock()
        logger.info(f"[+] Daemon (PID: {pid}) başarıyla durduruldu.")
        return True
    except Exception as e:
        logger.error(f"[!] Daemon durdurulamadı: {e}")
        return False


def get_python_executable() -> str:
    """Ubuntu venv veya yerel Python yorumlayıcısını bulur."""
    candidates = [
        "/home/ubuntu/app/venv/bin/python",
        os.path.join(PROJECT_DIR, "..", "venv", "bin", "python"),
        os.path.join(PROJECT_DIR, "venv", "bin", "python"),
        os.path.join(PROJECT_DIR, "my_env", "bin", "python"),
        sys.executable
    ]
    for c in candidates:
        if os.path.isfile(c):
            return c
    return sys.executable


def start_daemon_background() -> Optional[int]:
    """2. Servisi (Canlı Takipçi) arka planda başlatır."""
    running_pid = get_running_daemon_pid()
    if running_pid:
        logger.info(f"[*] Daemon zaten çalışıyor (PID: {running_pid}).")
        return running_pid

    py_exe = get_python_executable()
    engine_script = os.path.abspath(__file__)
    cmd = [py_exe, engine_script, "--daemon"]

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{PROJECT_DIR}:{env.get('PYTHONPATH', '')}"

    try:
        log_file = open(LOG_FILE_PATH, "a", encoding="utf-8")
        if os.name == 'nt':
            DETACHED_PROCESS = 0x00000008
            CREATE_NEW_PROCESS_GROUP = 0x00000200
            proc = subprocess.Popen(
                cmd,
                cwd=PROJECT_DIR,
                env=env,
                creationflags=DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP,
                stdout=log_file,
                stderr=log_file,
                close_fds=True,
            )
        else:
            proc = subprocess.Popen(
                cmd,
                cwd=PROJECT_DIR,
                env=env,
                start_new_session=True,
                stdout=log_file,
                stderr=log_file,
                close_fds=True,
            )
        time.sleep(0.5)
        if proc.poll() is not None:
            logger.error(f"[!] Daemon hemen sonlandı (kod: {proc.returncode}). Detay: {LOG_FILE_PATH}")
            return None

        logger.info(f"[+] 2. Servis (Canlı Takipçi) arka planda başlatıldı (PID: {proc.pid}, Log: {LOG_FILE_PATH}).")
        return proc.pid
    except Exception as e:
        logger.error(f"[!] Daemon başlatılırken hata: {e}")
        return None


# ==============================================================================
# 4. ZAMAN & ÇALIŞMA SAATLERİ VE KARAR MOTORU
# ==============================================================================

def get_current_tr_time() -> datetime:
    """Türkiye Zaman Dilimindeki (UTC+3) güncel zamanı döner."""
    return datetime.now(TR_TIMEZONE)


def is_within_working_hours(start_hour: int = 8, end_hour: int = 19) -> bool:
    """08:00 - 18:59 arası True, 19:00 ve sonrası False döner."""
    now = get_current_tr_time()
    return start_hour <= now.hour < end_hour


def evaluate_single_meet(meet: Dict[str, Any], today: Optional[date] = None) -> Tuple[bool, str]:
    """
    Tek bir yarış için parser'ın çalışması gerekip gerekmediğini kararlaştırır.
    Dönüş: (should_run: bool, reason: str)
    """
    if today is None:
        today = datetime.now(TR_TIMEZONE).date()

    meet_id = meet.get("id")
    title = meet.get("musabaka_adi") or meet.get("canli_url") or f"Yarış #{meet_id}"
    durum = (meet.get("durum") or "BEKLIYOR").upper()
    toplam_start = int(meet.get("toplam_start_listesi") or 0)
    islenen_start = int(meet.get("islenen_start_listesi") or 0)
    toplam_sonuc = int(meet.get("toplam_sonuc_listesi") or 0)
    islenen_sonuc = int(meet.get("islenen_sonuc_listesi") or 0)

    gercekten_tamam = (
        durum == "TAMAMLANDI"
        and toplam_sonuc > 0
        and islenen_sonuc >= toplam_sonuc
        and (toplam_start == 0 or islenen_sonuc >= toplam_start)
    )
    if gercekten_tamam:
        return False, f"[{title}] Müsabaka tüm sonuç listeleri ({islenen_sonuc}/{toplam_sonuc}) ile tamamlandı."

    startlist_tamam = (toplam_start > 0 and islenen_start >= toplam_start)
    if not startlist_tamam:
        kalan = max(0, toplam_start - islenen_start) if toplam_start > 0 else 'Bilinmiyor'
        return True, f'[{title}] Start listeleri eksik ({islenen_start}/{toplam_start}, Kalan: {kalan}). Parser çalışmalı.'

    if toplam_sonuc > 0 and islenen_sonuc < toplam_sonuc:
        return True, f'[{title}] Yeni yayınlanan sonuç listeleri mevcut ({islenen_sonuc}/{toplam_sonuc}).'

    start_iso = meet.get('baslangic_tarihi')
    end_iso = meet.get('bitis_tarihi') or start_iso

    if start_iso and end_iso:
        today_str = today.isoformat()
        if today_str < str(start_iso):
            return False, f"[{title}] Start listeleri hazır. Yarış {start_iso} tarihinde başlayacak."
        elif str(start_iso) <= today_str <= str(end_iso):
            return True, f"[{title}] BUGÜN YARIŞ GÜNÜ ({start_iso} - {end_iso})! Canlı sonuç takibi aktif."
        else:
            if durum != "TAMAMLANDI" or (toplam_sonuc > 0 and islenen_sonuc < toplam_sonuc):
                return True, f"[{title}] Yarış tarihi bitti fakat eksik sonuç listeleri var."
            return False, f"[{title}] Yarış geçmiş tarihte bitti ({end_iso})."

    return True, f"[{title}] Tarih bilgisi henüz yok, güvenli modda start/sonuç kontrolü yapılıyor."


def get_gemini_client() -> genai.Client:
    """Ortam değişkenlerinden (.env) Gemini istemcisini oluşturur."""
    gemini_key = (
        os.environ.get("GEMINI_API_KEY")
        or os.environ.get("GEMINI_API_KEY_2")
        or ""
    ).strip().strip("'\"")
    if not gemini_key:
        raise RuntimeError("GEMINI_API_KEY veya GEMINI_API_KEY_2 tanımlı değil.")
    return genai.Client(api_key=gemini_key)


def is_meet_truly_completed(
    yaris: CanliYaris,
    kalan_dosya: int = 0,
    hatalar: Optional[List[str]] = None,
) -> bool:
    """Erken TAMAMLANDI işaretlenmesini engeller."""
    if kalan_dosya > 0 or hatalar:
        return False

    t_start = int(yaris.toplam_start_listesi or 0)
    i_start = int(yaris.islenen_start_listesi or 0)
    t_sonuc = int(yaris.toplam_sonuc_listesi or 0)
    i_sonuc = int(yaris.islenen_sonuc_listesi or 0)

    if t_start == 0 and t_sonuc == 0:
        return False
    if t_start > 0 and i_start < t_start:
        return False
    if t_sonuc == 0 or i_sonuc < t_sonuc:
        return False
    if t_start > 0 and i_sonuc < t_start:
        return False

    return True


def canli_yaris_to_eval_dict(yaris: CanliYaris) -> Dict[str, Any]:
    ev = yaris.event
    return {
        "id": yaris.id,
        "musabaka_adi": yaris.musabaka_adi or yaris.canli_url,
        "canli_url": yaris.canli_url,
        "durum": yaris.durum,
        "toplam_start_listesi": yaris.toplam_start_listesi or 0,
        "islenen_start_listesi": yaris.islenen_start_listesi or 0,
        "toplam_sonuc_listesi": yaris.toplam_sonuc_listesi or 0,
        "islenen_sonuc_listesi": yaris.islenen_sonuc_listesi or 0,
        "baslangic_tarihi": ev.yaris_tarihi_baslangic if ev else None,
        "bitis_tarihi": ev.yaris_tarihi_bitis if ev else None,
    }


def should_scan_meet_db(yaris: CanliYaris, today: Optional[date] = None) -> Tuple[bool, str]:
    meet_dict = canli_yaris_to_eval_dict(yaris)
    return evaluate_single_meet(meet_dict, today=today)


def fetch_known_files_db(yaris: CanliYaris) -> Dict[str, Dict[str, Any]]:
    known = {}
    for d in CanliYarisDosya.objects.filter(canli_yaris=yaris):
        known[d.dosya_adi] = {
            "durum": d.durum,
            "etag": d.etag,
            "last_modified": d.last_modified,
            "boyut": d.dosya_boyutu,
        }
    return known


def update_meet_status_db(yaris: CanliYaris, data: Dict[str, Any]) -> None:
    fields = []
    for k in (
        "musabaka_adi", "sehir", "tarih", "durum", "toplam_start_listesi",
        "islenen_start_listesi", "toplam_sonuc_listesi", "islenen_sonuc_listesi",
        "hata_mesaji", "reglaman_linki", "barajlar",
    ):
        if k in data and getattr(yaris, k) != data[k]:
            setattr(yaris, k, data[k])
            fields.append(k)

    if data.get("durum") == "TAMAMLANDI":
        kalan = int(data.get("kalan_dosya") or 0)
        hatalar = data.get("hatalar") or []
        if not is_meet_truly_completed(yaris, kalan_dosya=kalan, hatalar=hatalar):
            yaris.durum = "ISLENIYOR"
            if "durum" not in fields:
                fields.append("durum")

    yaris.son_islem_tarihi = timezone.now()
    fields.append("son_islem_tarihi")

    if fields:
        yaris.save(update_fields=fields)


# ==============================================================================
# 5. DOĞRUDAN VERİTABANI İŞLEYİCİSİ (DJANGO ORM)
# ==============================================================================

def is_school_meet(meet_name: str) -> bool:
    if not meet_name:
        return False
    nm = tr_fold(meet_name)
    tokens = ["okul", "okullar", "meb", "okul spor", "kucukler il", "yildizlar il", "gencler il"]
    return any(t in nm for t in tokens)


def _time_to_seconds(time_str: Optional[str]) -> Optional[float]:
    if not time_str:
        return None
    s = str(time_str).strip()
    try:
        if ":" in s:
            p = s.split(":")
            return round(int(p[0]) * 60 + float(p[1]), 2)
        return round(float(s), 2)
    except Exception:
        return None


def clean_and_expand_club_name(name: str) -> str:
    if not name:
        return ""
    name = re.sub(r"\s+", " ", name.strip())
    expansions = [
        (r"\bB\.B\.?\s*S\.?K\.?\b", "BÜYÜKŞEHİR BELEDİYESİ SPOR KULÜBÜ"),
        (r"\bB\.B\.?\b", "BÜYÜKŞEHİR BELEDİYESİ"),
        (r"\bBŞB\b", "BÜYÜKŞEHİR BELEDİYESİ"),
        (r"\bGSK\b", "GENÇLİK VE SPOR KULÜBÜ"),
        (r"\bG\.S\.K\.?\b", "GENÇLİK VE SPOR KULÜBÜ"),
        (r"\bSK\b", "SPOR KULÜBÜ"),
        (r"\bS\.K\.?\b", "SPOR KULÜBÜ"),
        (r"\bK\.?\b", "KULÜBÜ"),
    ]
    for pat, rep in expansions:
        name = re.sub(pat, rep, name, flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", name.strip())


def get_or_resolve_canonical_club(raw_club_name: str, is_school: bool = False) -> Tuple[Kulup, bool]:
    c_name = raw_club_name.strip() if raw_club_name else "FERDİ"
    c_name = re.sub(r"\s+", " ", c_name)
    is_school_flag = is_school or is_school_team(c_name)

    club = Kulup.objects.filter(ad__iexact=c_name).first()
    if club:
        return club, False

    clean_name = clean_and_expand_club_name(c_name)
    club = Kulup.objects.filter(ad__iexact=clean_name).first()
    if club:
        return club, False

    club = Kulup.objects.create(
        ad=c_name,
        kisa_ad=c_name[:50] if len(c_name) > 50 else c_name,
        is_school=is_school_flag,
    )
    return club, True


def _process_single_race_payload(payload: dict) -> dict:
    """Tek bir yarış PDF'inin Gemini çıktısını atomik olarak SQLite veritabanına kaydeder."""
    stats = {"eklenen_sonuc": 0, "guncellenen_sonuc": 0, "mukerrer_atlanilan": 0}
    doc_type = payload.get("tur") or "sonuc_listesi"
    yaris_adi = payload.get("musabaka_adi") or ""
    sehir = payload.get("sehir") or ""
    canli_yaris_id = payload.get("canli_yaris_id")
    event_id = payload.get("event_id")

    canli_yaris = None
    if canli_yaris_id:
        canli_yaris = CanliYaris.objects.filter(id=canli_yaris_id).first()

    if canli_yaris and canli_yaris.event:
        event = canli_yaris.event
    elif event_id:
        event = Event.objects.get(id=event_id)
    else:
        # Canlı yarışın benzersiz linkine özel yeni Event oluştur
        event = Event.objects.create(
            musabaka_adi=yaris_adi or "TYF Canlı Yarış",
            sehir=sehir,
            kaynak_turu="CANLI_TAKIP",
        )
        if canli_yaris:
            canli_yaris.event = event
            canli_yaris.save(update_fields=["event"])

    is_school = is_school_meet(event.musabaka_adi)
    dosya_adi = payload.get("dosya_adi") or "dosya.pdf"
    dosya_turu = "START_LISTESI" if doc_type == "start_listesi" else "SONUC_LISTESI"

    lookup_dosya = {"dosya_adi": dosya_adi}
    if canli_yaris:
        lookup_dosya["canli_yaris"] = canli_yaris
    else:
        lookup_dosya["event"] = event

    dosya_kaydi, _ = CanliYarisDosya.objects.update_or_create(
        **lookup_dosya,
        defaults={
            "event": event,
            "canli_yaris": canli_yaris,
            "dosya_url": payload.get("dosya_url"),
            "dosya_turu": dosya_turu,
            "yaris_no": str(payload.get("yaris_no") or ""),
            "mesafe": payload.get("mesafe"),
            "stil": payload.get("stil"),
            "cinsiyet": payload.get("cinsiyet"),
            "yas_grubu": payload.get("yas_grubu"),
            "etag": payload.get("etag"),
            "last_modified": payload.get("last_modified"),
            "dosya_boyutu": payload.get("dosya_boyutu"),
            "durum": "ISLENDI",
        },
    )

    races = payload.get("yarismalar") or []
    if not races and (payload.get("mesafe") or payload.get("stil") or payload.get("sonuclar")):
        races = [{
            "yaris_no": payload.get("yaris_no"),
            "mesafe": payload.get("mesafe"),
            "stil": payload.get("stil"),
            "cinsiyet": payload.get("cinsiyet"),
            "yas_grubu": payload.get("yas_grubu"),
            "sonuclar": payload.get("sonuclar", []),
        }]

    course = detect_course(event.musabaka_adi or "")
    for race in races:
        mesafe = race.get("mesafe")
        stil = race.get("stil")
        cinsiyet = race.get("cinsiyet")
        yas_grubu = race.get("yas_grubu")

        for s in race.get("sonuclar", []):
            raw_name = (s.get("ad_soyad") or s.get("sporcu") or "").strip()
            if not raw_name:
                continue

            # 1. (FD), (TK), (TD), ferdi vb. etiketleri temizle
            clean_name = clean_athlete_name_tags(raw_name)
            birth_year = s.get("dogum_yili")
            gender = cinsiyet or s.get("cinsiyet")
            raw_club = s.get("kulup") or ""
            club, _ = get_or_resolve_canonical_club(raw_club, is_school=is_school)

            # 2. Sporcuyu bul veya 1-e-1 maskeli eşleştir
            match_res = match_athlete(clean_name, birth_year_or_date=birth_year, club=raw_club, gender=gender)
            athlete = None
            if match_res.get("bulunan_id"):
                athlete = Sporcu.objects.filter(id=match_res["bulunan_id"]).first()

            if not athlete:
                if '*' in clean_name:
                    athlete, _ = Sporcu.objects.get_or_create(
                        sporcu_adi=f"Maskeli sporcu ({clean_name})",
                        dogum_yili=birth_year,
                        cinsiyet=gender,
                        defaults={"birincil_kulup": club}
                    )
                else:
                    std_name = standardize_turkish_athlete_name(clean_name)
                    athlete, _ = Sporcu.objects.get_or_create(
                        sporcu_adi=std_name or clean_name,
                        dogum_yili=birth_year,
                        cinsiyet=gender,
                        defaults={"birincil_kulup": club}
                    )

            if athlete and club and not athlete.birincil_kulup:
                athlete.birincil_kulup = club
                athlete.save(update_fields=["birincil_kulup"])

            seri = s.get("seri")
            kulvar = s.get("kulvar")
            derece = s.get("derece")
            sira = s.get("sira")
            puan = s.get("puan")
            durum_str = s.get("durum") or "NORMAL"

            fina = puan
            if derece and not fina:
                fina = calculate_fina_points(cinsiyet, mesafe, stil, derece, course)

            derece_sn = _time_to_seconds(derece)

            defaults = {
                "kulup": club,
                "derece": derece,
                "derece_saniye": derece_sn,
                "sira": sira,
                "puan": fina,
                "seri": seri,
                "kulvar": kulvar,
                "canli_dosya": dosya_kaydi,
                "kaynak_turu": "CANLI_START_LISTESI" if doc_type == "start_listesi" else "CANLI_SONUC",
            }
            if '*' in clean_name or '*' in raw_name:
                defaults["sporcu_maskeli"] = clean_name
            if durum_str and durum_str != "NORMAL":
                defaults["uyari_notu"] = durum_str

            lookup = {
                "event": event,
                "sporcu": athlete,
                "mesafe": mesafe,
                "stil": stil,
                "cinsiyet": cinsiyet,
            }
            if yas_grubu:
                lookup["yas_grubu"] = yas_grubu

            sonuc_obj = YarisSonucu.objects.filter(**lookup).first()
            if sonuc_obj:
                if doc_type == "sonuc_listesi" or sonuc_obj.kaynak_turu == "CANLI_START_LISTESI":
                    for k, v in defaults.items():
                        setattr(sonuc_obj, k, v)
                    sonuc_obj.save()
                    stats["guncellenen_sonuc"] += 1
                else:
                    stats["mukerrer_atlanilan"] += 1
            else:
                lookup.update(defaults)
                YarisSonucu.objects.create(**lookup)
                stats["eklenen_sonuc"] += 1

    dosya_kaydi.kayit_sayisi = stats["eklenen_sonuc"] + stats["guncellenen_sonuc"]
    dosya_kaydi.save(update_fields=["kayit_sayisi"])
    return stats


def process_single_meet_db(
    yaris: CanliYaris,
    client: genai.Client,
    model: str = DEFAULT_MODEL,
    limit: Optional[int] = None,
    force: bool = False,
) -> Dict[str, Any]:
    """Bir canlı yarışın tüm bekleyen PDF'lerini Gemini ile ayrıştırıp veritabanına yazar."""
    event_id = yaris.id
    event_url = yaris.canli_url
    stats = {
        "event_id": event_id,
        "musabaka_adi": yaris.musabaka_adi or "",
        "sehir": yaris.sehir or "",
        "tarih": yaris.tarih or "",
        "durum": "ISLENIYOR",
        "toplam_start_listesi": 0,
        "islenen_start_listesi": 0,
        "toplam_sonuc_listesi": 0,
        "islenen_sonuc_listesi": 0,
        "basarili": 0,
        "atlanilan": 0,
        "hatali": 0,
        "kalan_dosya": 0,
        "hatalar": [],
    }

    try:
        meet_title, city, date_str, start_date, end_date, all_pdf_urls = fetch_meet_pdf_urls(event_url, mode="all")
        if meet_title:
            stats["musabaka_adi"] = meet_title
        if city:
            stats["sehir"] = city
        if date_str or start_date:
            stats["tarih"] = date_str or start_date

        if not yaris.event_id and stats["musabaka_adi"]:
            # Canlı yarışın tekil linkine (URL) özel bağımsız Event kaydı oluştur
            event_obj = Event.objects.create(
                musabaka_adi=stats["musabaka_adi"],
                sehir=stats.get("sehir") or "",
                yaris_tarihi_baslangic=start_date or "",
                yaris_tarihi_bitis=end_date or "",
                yaris_tarihi_ham=date_str or "",
                kaynak_turu="CANLI_TAKIP",
            )
            yaris.event = event_obj
            yaris.save(update_fields=["event"])
        elif yaris.event_id and yaris.event:
            ev = yaris.event
            ev_dirty = []
            if stats["musabaka_adi"] and ev.musabaka_adi != stats["musabaka_adi"]:
                ev.musabaka_adi = stats["musabaka_adi"]
                ev_dirty.append("musabaka_adi")
            if stats.get("sehir") and not ev.sehir:
                ev.sehir = stats["sehir"]
                ev_dirty.append("sehir")
            if start_date and not ev.yaris_tarihi_baslangic:
                ev.yaris_tarihi_baslangic = start_date
                ev_dirty.append("yaris_tarihi_baslangic")
            if end_date and not ev.yaris_tarihi_bitis:
                ev.yaris_tarihi_bitis = end_date
                ev_dirty.append("yaris_tarihi_bitis")
            if ev_dirty:
                ev.save(update_fields=ev_dirty)

        start_urls = [u for u in all_pdf_urls if detect_pdf_type(u, b"") == "start_listesi"]
        result_urls = [u for u in all_pdf_urls if detect_pdf_type(u, b"") == "sonuc_listesi"]

        stats["toplam_start_listesi"] = len(start_urls)
        stats["toplam_sonuc_listesi"] = len(result_urls)

        # Otomatik Sıfırlama: Eğer force=True VEYA event'e bağlı yarış sonucu yoksa
        # ama eski CanliYarisDosya kayıtları varsa, dosya önbelleğini sıfırla ki tüm PDF'ler baştan işlensin!
        event_has_results = bool(yaris.event and YarisSonucu.objects.filter(event=yaris.event).exists())
        if force or not event_has_results:
            if CanliYarisDosya.objects.filter(canli_yaris=yaris).exists():
                logger.info(f"[*] #{yaris.id} ({yaris.musabaka_adi or yaris.canli_url}): Sonuçlar boş/silinmiş veya force devrede. Tüm dosyalar baştan işlenmek üzere sıfırlanıyor...")
                CanliYarisDosya.objects.filter(canli_yaris=yaris).delete()
                yaris.islenen_start_listesi = 0
                yaris.islenen_sonuc_listesi = 0
                yaris.durum = "ISLENIYOR"
                yaris.save(update_fields=["islenen_start_listesi", "islenen_sonuc_listesi", "durum"])

        known_files = fetch_known_files_db(yaris)
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

            if remote_etag and known_etag:
                return remote_etag == known_etag
            if remote_lm and known_lm:
                return remote_lm == known_lm
            return True

        pending_start_urls = [u for u in start_urls if not is_file_unchanged(os.path.basename(u))]
        pending_result_urls = [u for u in result_urls if not is_file_unchanged(os.path.basename(u))]

        stats["islenen_start_listesi"] = len(start_urls) - len(pending_start_urls)
        stats["islenen_sonuc_listesi"] = len(result_urls) - len(pending_result_urls)
        stats["atlanilan"] = stats["islenen_start_listesi"] + stats["islenen_sonuc_listesi"]

        pending_queue = (
            [("start_listesi", u) for u in pending_start_urls]
            + [("sonuc_listesi", u) for u in pending_result_urls]
        )

        logger.info(
            f"[*] #{yaris.id} ({stats['musabaka_adi'] or yaris.canli_url}): "
            f"Toplam PDF: {len(all_pdf_urls)} (Start: {len(start_urls)}, Sonuç: {len(result_urls)}) | "
            f"İşlenecek: {len(pending_queue)} (Atlanılan: {stats['atlanilan']})"
        )

        if not pending_queue:
            stats["kalan_dosya"] = 0
            if is_meet_truly_completed(yaris, kalan_dosya=0, hatalar=[]):
                stats["durum"] = "TAMAMLANDI"
            else:
                stats["durum"] = "ISLENIYOR"
            update_meet_status_db(yaris, stats)
            return stats

        current_batch = pending_queue[:limit] if limit else pending_queue
        for doc_type, pdf_url in current_batch:
            filename = os.path.basename(pdf_url)
            try:
                pdf_bytes, meta = download_file_with_meta(pdf_url)
                logger.info(f"  [>] {filename} ayrıştırılıyor ({doc_type})...")
                parsed = parse_meet_pdf(
                    pdf_bytes,
                    client,
                    pdf_url=pdf_url,
                    model=model,
                )
                parsed["tur"] = doc_type
                parsed["musabaka_adi"] = stats["musabaka_adi"]
                parsed["sehir"] = stats["sehir"]
                parsed["tarih"] = stats["tarih"]
                parsed["canli_yaris_id"] = event_id
                parsed["dosya_adi"] = filename
                parsed["dosya_url"] = pdf_url
                parsed["etag"] = meta.get("etag")
                parsed["last_modified"] = meta.get("last_modified")
                parsed["dosya_boyutu"] = meta.get("dosya_boyutu")

                with transaction.atomic():
                    db_stats = _process_single_race_payload(parsed)

                stats["basarili"] += 1
                if doc_type == "start_listesi":
                    stats["islenen_start_listesi"] += 1
                else:
                    stats["islenen_sonuc_listesi"] += 1

                update_meet_status_db(yaris, {
                    "durum": "ISLENIYOR",
                    "toplam_start_listesi": stats["toplam_start_listesi"],
                    "islenen_start_listesi": stats["islenen_start_listesi"],
                    "toplam_sonuc_listesi": stats["toplam_sonuc_listesi"],
                    "islenen_sonuc_listesi": stats["islenen_sonuc_listesi"],
                    "eklenen_kayit_sayisi": (yaris.eklenen_kayit_sayisi or 0) + db_stats.get("eklenen_sonuc", 0),
                })
                logger.info(f"  [+] {filename} kaydedildi ({db_stats.get('eklenen_sonuc', 0)} sporcu eklendi).")
                time.sleep(3)

            except Exception as e:
                err = f"{filename} ({doc_type}): {str(e)}"
                logger.error(f"  [!] Hata: {err}")
                stats["hatali"] += 1
                stats["hatalar"].append(err)

        stats["kalan_dosya"] = len(pending_queue) - len(current_batch)

    except Exception as e:
        err = f"Genel Tarama Hatası ({event_url}): {str(e)}"
        logger.error(f"[!] {err}")
        stats["hatali"] += 1
        stats["hatalar"].append(err)

    if stats.get("kalan_dosya", 0) > 0:
        stats["durum"] = "ISLENIYOR"
    elif stats["hatali"] > 0:
        stats["durum"] = "ISLENIYOR" if (stats["basarili"] + stats["atlanilan"]) > 0 else "HATA"
    else:
        if is_meet_truly_completed(yaris, kalan_dosya=0, hatalar=stats.get("hatalar")):
            stats["durum"] = "TAMAMLANDI"
        else:
            stats["durum"] = "ISLENIYOR"

    update_meet_status_db(yaris, stats)
    return stats


def discover_new_meets_db() -> int:
    """TYF merkezi canlı sonuç sayfasını tarayıp yeni yarışları veritabanına ekler."""
    logger.info(f"TYF merkezi canlı sonuç sayfası taranıyor: {TYF_CANLI_SONUC_URL}")
    added_count = 0
    try:
        res = get_http_session().get(TYF_CANLI_SONUC_URL, timeout=12)
        if res.status_code != 200:
            return 0
        soup = BeautifulSoup(res.text, "html.parser")
        for a in soup.find_all("a", href=True):
            href = a["href"].strip()
            if "canli.tyf.gov.tr" in href or "/cs-" in href:
                if href.startswith("/"):
                    href = urljoin("https://canli.tyf.gov.tr", href)
                elif not href.startswith("http"):
                    href = "https://" + href

                title = a.get_text(strip=True)
                title = re.sub(r"\s*-\s*SPLASH\s+Meet\s+Manager\s*\d*", "", title, flags=re.IGNORECASE).strip()

                _, created = CanliYaris.objects.get_or_create(
                    canli_url=href,
                    defaults={
                        "musabaka_adi": title or "TYF Canlı Yarış",
                        "durum": "BEKLIYOR",
                    },
                )
                if created:
                    added_count += 1
                    logger.info(f"[+] Yeni canlı yarış keşfedildi: {title or href}")
    except Exception as e:
        logger.warning(f"Keşif hatası: {e}")
    return added_count


# ==============================================================================
# 6. SERVİS 1: SAATLİK CRON ORKESTRATÖRÜ
# ==============================================================================

def run_cron_orchestrator(kesfet: bool = False) -> None:
    now = get_current_tr_time()
    logger.info(f"=== [Servis 1: Saatlik Cron Kontrolü Başladı] (Saat: {now.strftime('%H:%M:%S')}) ===")

    if not is_within_working_hours(start_hour=8, end_hour=19):
        logger.info(f"[*] Şu an saat {now.strftime('%H:%M')}. Çalışma saatleri dışındayız (08:00 - 19:00). İşlem yapılmadı.")
        return

    if kesfet:
        logger.info("[*] TYF sayfalarından yeni yarış keşfi yapılıyor...")
        added = discover_new_meets_db()
        logger.info(f"[*] Keşif tamamlandı ({added} yeni yarış eklendi).")

    qs = CanliYaris.objects.filter(
        Q(durum="ISLENIYOR") | Q(durum="BEKLIYOR")
    ).order_by("-olusturulma_tarihi")

    active_meets = []
    for y in qs:
        should_run, reason = should_scan_meet_db(y)
        logger.info(f"[*] Karar Motoru (#{y.id} {y.musabaka_adi or y.canli_url}): {reason}")
        if should_run:
            active_meets.append(y)

    if not active_meets:
        logger.info("[*] Takipte olan veya taranması gereken aktif canlı yarış bulunmadı. Çıkılıyor.")
        return

    running_pid = get_running_daemon_pid()
    if running_pid:
        logger.info(f"[+] 2. Servis (Canlı Takipçi) zaten aktif çalışıyor (PID: {running_pid}). Müdahale edilmedi.")
        return

    logger.info(f"[*] {len(active_meets)} aktif yarış için 2. Servis (Canlı Takipçi) uyandırılıyor...")
    proc_pid = start_daemon_background()
    if proc_pid:
        logger.info(f"[+] 2. Servis başarıyla başlatıldı (PID: {proc_pid}).")
    else:
        logger.error("[!] 2. Servis başlatılamadı!")


# ==============================================================================
# 7. SERVİS 2: 10 SANİYELİK CANLI TAKİP DÖNGÜSÜ (DAEMON)
# ==============================================================================

def _signal_handler(signum, _frame):
    global SHUTDOWN_SIGNAL_RECEIVED
    logger.info(f"[*] Kapanma sinyali alındı ({signum}). Servis nazikçe durduruluyor...")
    SHUTDOWN_SIGNAL_RECEIVED = True


def run_daemon_worker(poll_interval: int = 10, model: str = DEFAULT_MODEL) -> None:
    global SHUTDOWN_SIGNAL_RECEIVED
    if not acquire_daemon_lock():
        existing_pid = get_running_daemon_pid()
        logger.warning(f"[!] 2. Servis zaten çalışıyor (PID: {existing_pid}). İkinci bir kopya açılamaz.")
        return

    signal.signal(signal.SIGINT, _signal_handler)
    signal.signal(signal.SIGTERM, _signal_handler)
    if hasattr(signal, "SIGBREAK"):
        signal.signal(signal.SIGBREAK, _signal_handler)

    logger.info(f"=== [Servis 2: Canlı Takipçi Başlatıldı] (PID: {os.getpid()}, Aralık: {poll_interval} sn) ===")
    try:
        client = get_gemini_client()
    except Exception as e:
        logger.error(f"[!] Gemini istemcisi başlatılamadı: {e}")
        release_daemon_lock()
        return

    try:
        while not SHUTDOWN_SIGNAL_RECEIVED:
            now = get_current_tr_time()

            if now.hour >= 19 or now.hour < 8:
                logger.info(f"[*] Saat {now.strftime('%H:%M:%S')} - Saat 19:00 sınırı aşıldı. Günlük canlı takip oturumu güvenle sonlandırılıyor.")
                break

            # Hem ISLENIYOR olanları hem de BEKLIYOR durumunda olup bugün yarış günü olanları topla
            active_meets_dict = {m.id: m for m in CanliYaris.objects.filter(durum="ISLENIYOR").order_by("id")}
            pending_meets = list(CanliYaris.objects.filter(durum="BEKLIYOR").order_by("id"))
            for p in pending_meets:
                should_run, _ = should_scan_meet_db(p, today=now.date())
                if should_run:
                    p.durum = "ISLENIYOR"
                    p.save(update_fields=["durum"])
                    active_meets_dict[p.id] = p

            active_meets = list(active_meets_dict.values())
            if not active_meets:
                logger.info("[*] Takip edilecek aktif canlı yarış kalmadı. Servis kendini kapatıyor.")
                break

            for yaris in active_meets:
                if SHUTDOWN_SIGNAL_RECEIVED:
                    break
                try:
                    stats = process_single_meet_db(
                        yaris=yaris,
                        client=client,
                        model=model,
                    )
                    if stats.get("basarili", 0) > 0:
                        logger.info(
                            f"[+] #{yaris.id} ({yaris.musabaka_adi or yaris.canli_url}): "
                            f"{stats['basarili']} yeni dosya işlendi, durum={stats['durum']}"
                        )
                except Exception as e:
                    logger.error(f"[!] Yarış #{yaris.id} taranırken hata: {e}")

            for _ in range(poll_interval):
                if SHUTDOWN_SIGNAL_RECEIVED:
                    break
                time.sleep(1)

    except Exception as e:
        logger.error(f"[!] Daemon döngüsünde beklenmeyen hata: {e}", exc_info=True)
    finally:
        release_daemon_lock()
        logger.info("=== [Servis 2: Canlı Takipçi Güvenle Kapandı] ===")


# ==============================================================================
# 8. CLI VE YARDIMCI GİRİŞ NOKTALARI
# ==============================================================================

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="TYF Canlı Yarış Takip ve Ayrıştırma Motoru (live_engine)")
    parser.add_argument("--cron", action="store_true", help="1. Servis: Saatlik cron orkestratörünü çalıştır")
    parser.add_argument("--daemon", action="store_true", help="2. Servis: 10 saniyelik canlı takipçi döngüsünü başlat")
    parser.add_argument("--kesfet", action="store_true", help="TYF sayfalarından yeni yarışları keşfet")
    parser.add_argument("--durdur", action="store_true", help="Çalışan 2. Servisi (daemon) durdur")
    parser.add_argument("--durum", action="store_true", help="Canlı takipçi servisinin durumunu kontrol et")
    parser.add_argument("--id", type=int, default=None, help="Belirli bir yarış ID'sini anında tek seferlik tara")
    parser.add_argument("--force", action="store_true", help="Eski dosya önbelleğini sıfırla ve tüm PDF'leri baştan tara")
    parser.add_argument("--aralik", type=int, default=10, help="Daemon döngü aralığı (saniye, varsayılan: 10)")
    parser.add_argument("--model", type=str, default=DEFAULT_MODEL, help="Gemini model adı")

    args = parser.parse_args()

    if args.durdur:
        stop_daemon()
    elif args.durum:
        pid = get_running_daemon_pid()
        if pid:
            print(f"[+] 2. Servis (Canlı Takipçi) AKTİF çalışıyor. PID: {pid}")
        else:
            print("[-] 2. Servis (Canlı Takipçi) şu anda ÇALIŞMIYOR.")
    elif args.cron:
        run_cron_orchestrator(kesfet=args.kesfet)
    elif args.daemon:
        run_daemon_worker(poll_interval=args.aralik, model=args.model)
    elif args.id:
        y = CanliYaris.objects.filter(id=args.id).first()
        if not y:
            print(f"[!] ID {args.id} olan canlı yarış bulunamadı.")
            sys.exit(1)
        cl = get_gemini_client()
        st = process_single_meet_db(y, cl, model=args.model, force=args.force)
        print(f"[+] Sonuç: {st}")
    else:
        run_cron_orchestrator(kesfet=args.kesfet)
