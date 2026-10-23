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
import hashlib
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


def download_file_with_meta(url: str) -> Tuple[bytes, Dict[str, Any]]:
    """Dosyayı indirir ve ETag, Last-Modified ve SHA-256 hash meta verilerini çıkarır."""
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
    )
    with urllib.request.urlopen(req, context=get_ssl_context(), timeout=30) as resp:
        content = resp.read()
        etag = (resp.headers.get("ETag") or "").strip('"')
        last_modified = resp.headers.get("Last-Modified") or ""
        sha256 = hashlib.sha256(content).hexdigest()
        meta = {
            "etag": etag,
            "last_modified": last_modified,
            "content_hash": sha256,
            "dosya_boyutu": len(content)
        }
        return content, meta


def get_endpoint_url(django_url: str, endpoint: str) -> str:
    """Django API URL'sinden ilgili endpoint adresini türetir."""
    if not django_url:
        return ""
    clean_endpoint = endpoint.strip("/")
    if "/api/" in django_url:
        base = django_url.split("/api/")[0]
        return f"{base}/api/{clean_endpoint}/"
    return urljoin(django_url, f"/api/{clean_endpoint}/")


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
        "content_hash": meta.get("content_hash"),
        "dosya_boyutu": meta.get("dosya_boyutu")
    }
    try:
        data_json = json.dumps(payload).encode("utf-8")
        headers = {"Content-Type": "application/json; charset=utf-8"}
        if api_key:
            headers["X-Api-Key"] = api_key
        req = urllib.request.Request(check_api, data=data_json, headers=headers)
        with urllib.request.urlopen(req, context=get_ssl_context(), timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return bool(data.get("islenmis_mi") is True and data.get("degisti_mi") is False)
    except Exception as e:
        print(f"  [!] Dosya kontrol hatası ({filename}): {e}")
        return False


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
        print(f"[!] Start listesi sporcuları çekilemedi ({full_url}): {e}")
        return []


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


def fetch_meet_pdf_urls(event_url: str, mode: str = "start_listesi") -> Tuple[str, str, str, str, str, List[str]]:
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
    is_all = m_lower in ("all", "hepsi")

    seen = set()
    pdf_urls = []
    for a in soup.find_all("a", href=True):
        href = a["href"].strip()
        h_lower = href.lower()
        
        matches = False
        if is_sonuc:
            matches = ("resultlist" in h_lower or "result_list" in h_lower or "sonuc" in h_lower)
        elif is_all:
            matches = ("startlist" in h_lower or "start_list" in h_lower or "resultlist" in h_lower or "result_list" in h_lower or "sonuc" in h_lower or "start" in h_lower)
        else: # default start_listesi
            matches = ("startlist" in h_lower or "start_list" in h_lower or "start" in h_lower)

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


def parse_meet_pdf(pdf_bytes: bytes, client: genai.Client, pdf_url: str = "", model: str = DEFAULT_MODEL, startlist_swimmers: Optional[List[Dict[str, Any]]] = None) -> Dict[str, Any]:
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
        new_swimmers = p_data.get("yeni_sporcular", [])
        if isinstance(new_swimmers, list):
            header_data.setdefault("yeni_sporcular", []).extend(new_swimmers)

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


def _process_startlists_job(event_id, event_url, meet_title, city, date_str, start_date, end_date, start_urls, client, django_api_url, callback_url, mode="start_listesi"):
    is_sonuc = (mode or "").lower() in ("sonuc_listesi", "result_list", "sonuc", "results")
    doc_label = "Sonuç Listesi" if is_sonuc else "Start Listesi"

    stats = {
        "event_id": event_id,
        "event_url": event_url,
        "durum": "TAMAMLANDI",
        "mod": mode,
        "musabaka_adi": meet_title,
        "sehir": city,
        "tarih": date_str or start_date,
        "toplam_liste": len(start_urls),
        "toplam_start_listesi": 0 if is_sonuc else len(start_urls),
        "islenen_start_listesi": 0,
        "toplam_sonuc_listesi": len(start_urls) if is_sonuc else 0,
        "islenen_sonuc_listesi": 0,
        "basarili": 0,
        "atlanilan": 0,
        "hatali": 0,
        "toplam_sporcu": 0,
        "hatalar": []
    }

    for pdf_url in start_urls:
        try:
            pdf_bytes, meta = download_file_with_meta(pdf_url)
            filename = os.path.basename(pdf_url)

            # Önceden işlenmiş ve değişmemiş mi kontrol et (Idempotency / Deduplication)
            if django_api_url and event_id:
                already_done = check_file_already_processed(django_api_url, event_id, filename, meta)
                if already_done:
                    print(f"  [*] {filename} zaten işlenmiş ve değişmemiş; Gemini çağrısı atlanıyor.")
                    stats["atlanilan"] += 1
                    if is_sonuc:
                        stats["islenen_sonuc_listesi"] += 1
                    else:
                        stats["islenen_start_listesi"] += 1
                    continue

            # Yarış no tespiti (Örn: ResultList_1.pdf -> yaris_no = 1)
            m_no = re.search(r"(?:StartList|ResultList)_(\d+)\.pdf", filename, re.I)
            if not m_no:
                m_no = re.search(r"_(\d+)\.pdf", filename, re.I)
            yaris_no = m_no.group(1) if m_no else None

            # Eğer sonuç listesiyse start listesindeki sporcuları Django'dan çek
            startlist_swimmers = None
            d_type = detect_pdf_type(pdf_url, pdf_bytes)
            if d_type == "sonuc_listesi" and yaris_no and django_api_url:
                startlist_swimmers = fetch_startlist_swimmers(django_api_url, event_id, yaris_no)

            parsed = parse_meet_pdf(pdf_bytes, client, pdf_url=pdf_url, startlist_swimmers=startlist_swimmers)
            if not parsed.get("musabaka_adi") and meet_title:
                parsed["musabaka_adi"] = meet_title
            if not parsed.get("sehir") and city:
                parsed["sehir"] = city
            if not parsed.get("tarih") and (date_str or start_date):
                parsed["tarih"] = date_str or start_date
            if start_date and not parsed.get("yaris_tarihi_baslangic"):
                parsed["yaris_tarihi_baslangic"] = start_date
            if end_date and not parsed.get("yaris_tarihi_bitis"):
                parsed["yaris_tarihi_bitis"] = end_date

            # Meta verileri ekle
            parsed["dosya_adi"] = filename
            parsed["dosya_url"] = pdf_url
            parsed["etag"] = meta.get("etag")
            parsed["last_modified"] = meta.get("last_modified")
            parsed["content_hash"] = meta.get("content_hash")
            parsed["dosya_boyutu"] = meta.get("dosya_boyutu")
            parsed["canli_yaris_id"] = event_id
            
            stats["toplam_sporcu"] += len(parsed.get("kayitlar", [])) + len(parsed.get("yeni_sporcular", []))

            if django_api_url:
                ok = post_to_django(django_api_url, parsed)
                if not ok:
                    raise RuntimeError(f"Django API aktarımı {django_api_url} yanıt vermedi veya hata döndü.")

            stats["basarili"] += 1
            if is_sonuc:
                stats["islenen_sonuc_listesi"] += 1
            else:
                stats["islenen_start_listesi"] += 1

        except Exception as e:
            err_msg = f"{pdf_url}: {str(e)}"
            print(f"[!] Hata: {err_msg}")
            stats["hatali"] += 1
            stats["hatalar"].append(err_msg)

    if (stats["basarili"] + stats["atlanilan"]) == 0 and stats["hatali"] > 0:
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

    # Mod tespiti ('mod' veya 'mode' desteği)
    raw_mode = (req_json.get("mod") or req_json.get("mode") or request.args.get("mod") or request.args.get("mode") or "start_listesi").lower()
    if raw_mode in ["sonuc_listesi", "result_list", "sonuc", "results"]:
        mode = "sonuc_listesi"
    elif raw_mode in ["all", "hepsi"]:
        mode = "hepsi"
    else:
        mode = "start_listesi"

    limit = req_json.get("limit")

    if not event_url:
        return (json.dumps({"durum": "hata", "mesaj": "'event_url' parametresi zorunludur."}), 400, {"Content-Type": "application/json"})

    if not gemini_key:
        return (json.dumps({"durum": "hata", "mesaj": "GEMINI_API_KEY tanımlanmamış."}), 400, {"Content-Type": "application/json"})

    client = genai.Client(api_key=gemini_key.strip().strip("'\""))
    meet_title, city, date_str, start_date, end_date, start_urls = fetch_meet_pdf_urls(event_url, mode=mode)

    if limit and isinstance(limit, int) and limit > 0:
        start_urls = start_urls[:limit]

    doc_label = "Sonuç Listeleri" if mode == "sonuc_listesi" else "Start Listeleri"

    # Asenkron Webhook Modu (PythonAnywhere zaman aşımına uğramadan 200 ms içinde döner)
    if async_mode:
        import threading
        t = threading.Thread(
            target=_process_startlists_job,
            args=(event_id, event_url, meet_title, city, date_str, start_date, end_date, start_urls, client, django_api_url, callback_url, mode),
            daemon=True
        )
        t.start()
        return (json.dumps({
            "durum": "ISLENIYOR",
            "mesaj": f"{doc_label} arka planda taranmaya başlandı ({len(start_urls)} liste).",
            "musabaka_adi": meet_title,
            "mod": mode,
            "toplam_liste": len(start_urls),
            "toplam_start_listesi": 0 if mode == "sonuc_listesi" else len(start_urls),
            "toplam_sonuc_listesi": len(start_urls) if mode == "sonuc_listesi" else 0
        }, ensure_ascii=False), 202, {"Content-Type": "application/json"})

    # Senkron Mod (Doğrudan tüm işlem bitene kadar bekler)
    stats = _process_startlists_job(event_id, event_url, meet_title, city, date_str, start_date, end_date, start_urls, client, django_api_url, callback_url, mode)
    return (json.dumps(stats, ensure_ascii=False), 200, {"Content-Type": "application/json"})

