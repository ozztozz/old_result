# -*- coding: utf-8 -*-
"""
Google Cloud Function / Cloud Run - TYF Canlı Start Listesi İşleyicisi
=====================================================================
Bu fonksiyon Google Cloud altyapısında (Cloud Function gen2 veya Cloud Run) çalışır.
PythonAnywhere dış bağlantı engeline takılmadan:
1. canli.tyf.gov.tr üzerindeki yarış sayfasını ve StartList PDF'lerini çeker.
2. Gemini Flash Lite ile her bir start listesini paralel olarak ayrıştırır.
3. Ayrıştırılan kayıtları PythonAnywhere'deki Django API'nize (api/canli-aktar/) doğrudan post eder.
"""

import os
import re
import ssl
import json
import time
import urllib.request
from urllib.parse import urljoin
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
    load_dotenv()
except ImportError:
    pass

DEFAULT_MODEL = os.environ.get("GEMINI_MODEL", "gemini-flash-lite-latest")


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


def fetch_meet_pdf_urls(event_url: str, mode: str = "start_list") -> Tuple[str, List[str]]:
    html = download_bytes(event_url).decode("utf-8", errors="ignore")
    soup = BeautifulSoup(html, "html.parser")
    meet_title = soup.title.string.replace("- SPLASH Meet Manager 11", "").strip() if soup.title else ""

    seen = set()
    pdf_urls = []
    for a in soup.find_all("a", href=True):
        href = a["href"].strip()
        h_lower = href.lower()
        
        matches = False
        if mode == "result_list":
            matches = ("resultlist" in h_lower or "result_list" in h_lower)
        elif mode == "all":
            matches = ("startlist" in h_lower or "start_list" in h_lower or "resultlist" in h_lower or "result_list" in h_lower)
        else: # default start_list
            matches = ("startlist" in h_lower or "start_list" in h_lower)

        if matches:
            full = urljoin(event_url, href)
            if full not in seen:
                seen.add(full)
                pdf_urls.append(full)

    def sort_key(u: str) -> int:
        m = re.search(r"(?:StartList|ResultList)_(\d+)\.pdf", u, re.I)
        return int(m.group(1)) if m else 99999

    pdf_urls.sort(key=sort_key)
    return meet_title, pdf_urls


# Geriye dönük uyumluluk
fetch_start_list_urls = fetch_meet_pdf_urls


def detect_pdf_type(pdf_url: str, pdf_bytes: bytes) -> str:
    u = pdf_url.lower()
    if "resultlist" in u or "result_list" in u or "sonuc" in u:
        return "sonuc_listesi"
    if "startlist" in u or "start_list" in u or "start" in u:
        return "start_listesi"
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


def parse_meet_pdf(pdf_bytes: bytes, client: genai.Client, pdf_url: str = "", model: str = DEFAULT_MODEL) -> Dict[str, Any]:
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
        "kayitlar": []
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
            prompt = f"""Bu bir TYF Splash Meet Manager SONUÇ LİSTESİ PDF sayfasıdır.
Sayfa {p_num}/{total_pages}.
{'1. Başlıktan müsabaka_adı, şehir, tarih (YYYY-MM-DD), yarış_no, cinsiyet (Erkek/Kadın), mesafe (m tam sayı), stil ve yaş_grubu çıkar.' if is_first else ''}
2. Sayfadaki tüm sporcu sonuçlarını eksiksiz çıkar.
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
      "sira": integer veya string,
      "sporcu": string,
      "dogum_yili": string,
      "kulup": string,
      "derece": string,
      "puan": integer veya null,
      "baraj": string veya null
    }}
  ]
}}
SADECE JSON döndür."""
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
SADECE JSON döndür."""

        part = types.Part.from_bytes(data=p_bytes, mime_type="application/pdf")
        res = client.models.generate_content(
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
            parsed_json = {"kayitlar": parsed_json}
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

    return header_data


# Geriye dönük uyumluluk için takma ad
parse_start_list_pdf = parse_meet_pdf


def post_to_django(django_url: str, payload: Dict[str, Any], api_key: Optional[str] = None, max_retries: int = 3) -> bool:
    data_json = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if api_key:
        headers["X-Api-Key"] = api_key

    for attempt in range(1, max_retries + 1):
        try:
            req = urllib.request.Request(django_url, data=data_json, headers=headers)
            with urllib.request.urlopen(req, context=get_ssl_context(), timeout=45) as resp:
                if resp.status in (200, 201):
                    return True
        except Exception as e:
            print(f"[!] Django aktarım hatası (Deneme {attempt}/{max_retries}): {e}")
            if attempt < max_retries:
                time.sleep(2)
    return False


def _process_startlists_job(event_id, event_url, meet_title, start_urls, client, django_api_url, callback_url):
    stats = {
        "event_id": event_id,
        "event_url": event_url,
        "durum": "TAMAMLANDI",
        "musabaka_adi": meet_title,
        "toplam_start_listesi": len(start_urls),
        "islenen_start_listesi": 0,
        "basarili": 0,
        "hatali": 0,
        "toplam_sporcu": 0,
        "hatalar": []
    }

    for pdf_url in start_urls:
        try:
            pdf_bytes = download_bytes(pdf_url)
            parsed = parse_meet_pdf(pdf_bytes, client, pdf_url=pdf_url)
            if not parsed.get("musabaka_adi") and meet_title:
                parsed["musabaka_adi"] = meet_title
            
            stats["toplam_sporcu"] += len(parsed.get("kayitlar", []))

            if django_api_url:
                ok = post_to_django(django_api_url, parsed)
                if not ok:
                    raise RuntimeError(f"Django API aktarımı {django_api_url} yanıt vermedi veya hata döndü.")

            stats["basarili"] += 1
            stats["islenen_start_listesi"] = stats["basarili"]
        except Exception as e:
            err_msg = f"{pdf_url}: {str(e)}"
            print(f"[!] Hata: {err_msg}")
            stats["hatali"] += 1
            stats["hatalar"].append(err_msg)

    if stats["basarili"] == 0 and stats["hatali"] > 0:
        stats["durum"] = "HATA"

    if callback_url:
        print(f"[*] Tamamlandı callback'i gönderiliyor: {callback_url}")
        post_to_django(callback_url, stats)

    return stats


# Google Cloud Functions Entry Point (HTTP)
def tyf_startlist_handler(request):
    """
    Google Cloud Functions (gen2) / Cloud Run HTTP Handler.
    """
    if request.method == "OPTIONS":
        headers = {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, X-Api-Key",
            "Access-Control-Max-Age": "3600"
        }
        return ("", 204, headers)

    req_json = request.get_json(silent=True) or {}
    event_url = req_json.get("event_url") or request.args.get("event_url")
    django_api_url = req_json.get("django_api_url") or request.args.get("django_api_url") or os.environ.get("DJANGO_API_URL")
    callback_url = req_json.get("callback_url") or request.args.get("callback_url") or os.environ.get("CALLBACK_URL")
    event_id = req_json.get("event_id") or request.args.get("event_id")
    async_mode = req_json.get("async_mode", False) or request.args.get("async_mode") == "true"
    gemini_key = req_json.get("gemini_api_key") or os.environ.get("GEMINI_API_KEY")
    mode = req_json.get("mode") or request.args.get("mode") or "start_list"
    limit = req_json.get("limit")

    if not event_url:
        return (json.dumps({"durum": "hata", "mesaj": "'event_url' parametresi zorunludur."}), 400, {"Content-Type": "application/json"})

    if not gemini_key:
        return (json.dumps({"durum": "hata", "mesaj": "GEMINI_API_KEY tanımlanmamış."}), 400, {"Content-Type": "application/json"})

    client = genai.Client(api_key=gemini_key.strip().strip("'\""))
    meet_title, start_urls = fetch_meet_pdf_urls(event_url, mode=mode)

    if limit and isinstance(limit, int) and limit > 0:
        start_urls = start_urls[:limit]

    # Asenkron Webhook Modu (PythonAnywhere zaman aşımına uğramadan 200 ms içinde döner)
    if async_mode:
        import threading
        t = threading.Thread(
            target=_process_startlists_job,
            args=(event_id, event_url, meet_title, start_urls, client, django_api_url, callback_url),
            daemon=True
        )
        t.start()
        return (json.dumps({
            "durum": "isleniyor",
            "mesaj": "Start listeleri arka planda taranmaya başlandı.",
            "musabaka_adi": meet_title,
            "toplam_start_listesi": len(start_urls)
        }, ensure_ascii=False), 200, {"Content-Type": "application/json"})

    # Senkron Mod (Doğrudan tüm işlem bitene kadar bekler)
    stats = _process_startlists_job(event_id, event_url, meet_title, start_urls, client, django_api_url, callback_url)
    return (json.dumps(stats, ensure_ascii=False), 200, {"Content-Type": "application/json"})

