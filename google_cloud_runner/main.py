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
        "content_hash": meta.get("content_hash"),
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


def parse_meet_pdf(pdf_bytes: bytes, client: genai.Client, pdf_url: str = "", model: str = DEFAULT_MODEL, startlist_swimmers: Optional[List[Dict[str, Any]]] = None) -> Dict[str, Any]:
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
    """Django API'ye veriyi POST eder."""
    data_json = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if api_key:
        headers["X-Api-Key"] = api_key

    for attempt in range(1, max_retries + 1):
        try:
            req = urllib.request.Request(django_url, data=data_json, headers=headers)
            with urllib.request.urlopen(req, context=get_ssl_context(), timeout=60) as resp:
                if resp.status in (200, 201):
                    return True
        except Exception as e:
            print(f"  [!] Django aktarım hatası ({django_url} - Deneme {attempt}/{max_retries}): {e}")
            if attempt < max_retries:
                time.sleep(4)
    return False


def process_single_meet(meet: Dict[str, Any], base_url: str, client: genai.Client, model: str = DEFAULT_MODEL, limit: Optional[int] = None, api_key: Optional[str] = None) -> Dict[str, Any]:
    """
    Tek bir canlı yarışı baştan sona işler:
    1. Durumu 'ISLENIYOR' yapar.
    2. Start listelerini tarar, değişmeyenleri atlar, yeni olanları Gemini ile ayrıştırıp Django'ya aktarır.
    3. Sonuç listelerini tarar, start listesi ID'leriyle eşleştirip dereceleri günceller.
    4. Durumu 'TAMAMLANDI' yapar ve istatistikleri döner.
    """
    event_id = meet.get("id")
    event_url = meet.get("canli_url") or meet.get("event_url")

    if not event_url:
        return {"durum": "HATA", "mesaj": "Geçersiz yarış URL'si."}

    print(f"\n=======================================================")
    print(f"[*] Canlı Yarış İşleniyor: ID #{event_id} - {event_url}")
    print(f"=======================================================")

    # 1. Django'da durumu ISLENIYOR yap
    update_meet_status(base_url, {
        "event_id": event_id,
        "event_url": event_url,
        "durum": "ISLENIYOR"
    }, api_key=api_key)

    stats = {
        "event_id": event_id,
        "event_url": event_url,
        "durum": "TAMAMLANDI",
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
        "toplam_sporcu": 0,
        "hatalar": []
    }

    try:
        # 2. Sayfayı tara, başlık ve PDF linklerini çek
        meet_title, city, date_str, start_date, end_date, all_pdf_urls = fetch_meet_pdf_urls(event_url, mode="all")
        if meet_title:
            stats["musabaka_adi"] = meet_title
        if city:
            stats["sehir"] = city
        if date_str or start_date:
            stats["tarih"] = date_str or start_date

        start_urls = [u for u in all_pdf_urls if detect_pdf_type(u, b"") == "start_listesi"]
        result_urls = [u for u in all_pdf_urls if detect_pdf_type(u, b"") == "sonuc_listesi"]

        if limit and isinstance(limit, int) and limit > 0:
            start_urls = start_urls[:limit]
            result_urls = result_urls[:limit]

        stats["toplam_start_listesi"] = len(start_urls)
        stats["toplam_sonuc_listesi"] = len(result_urls)

        # Django'ya ilk başlık ve toplam sayıları bildir
        update_meet_status(base_url, {
            "event_id": event_id,
            "event_url": event_url,
            "musabaka_adi": stats["musabaka_adi"],
            "sehir": stats["sehir"],
            "tarih": stats["tarih"],
            "toplam_start_listesi": stats["toplam_start_listesi"],
            "toplam_sonuc_listesi": stats["toplam_sonuc_listesi"]
        }, api_key=api_key)

        print(f"[*] Müsabaka: {stats['musabaka_adi']} | Şehir: {stats['sehir']} | Tarih: {stats['tarih']}")
        print(f"[*] Tespit edilen: {len(start_urls)} Start Listesi, {len(result_urls)} Sonuç Listesi")

        # 3. Önce START LISTELERİNİ işle
        for pdf_url in start_urls:
            filename = os.path.basename(pdf_url)
            try:
                pdf_bytes, meta = download_file_with_meta(pdf_url)

                # Daha önce işlenmiş ve değişmemişse atla
                if check_file_already_processed(base_url, event_id, filename, meta, api_key=api_key):
                    print(f"  [-] {filename} zaten işlenmiş ve değişmemiş; atlanıyor.")
                    stats["atlanilan"] += 1
                    stats["islenen_start_listesi"] += 1
                    continue

                print(f"  [>] {filename} ayrıştırılıyor (Start Listesi - Gemini Flash Lite)...")
                parsed = parse_meet_pdf(pdf_bytes, client, pdf_url=pdf_url, model=model)
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
                parsed["content_hash"] = meta.get("content_hash")
                parsed["dosya_boyutu"] = meta.get("dosya_boyutu")

                aktar_url = get_endpoint_url(base_url, "canli-aktar")
                if not post_to_django(aktar_url, parsed, api_key=api_key):
                    raise RuntimeError(f"Django aktarımı başarısız oldu ({aktar_url})")

                stats["basarili"] += 1
                stats["islenen_start_listesi"] += 1
                record_count = len(parsed.get("kayitlar", [])) + len(parsed.get("yeni_sporcular", []))
                stats["toplam_sporcu"] += record_count
                print(f"  [+] {filename} başarıyla aktarıldı ({record_count} sporcu/kulvar)")

                # PythonAnywhere tek worker'ına nefes aldır (web kullanıcılarının istekleri araya girebilsin)
                time.sleep(1.5)

            except Exception as e:
                err = f"{filename} (StartList): {str(e)}"
                print(f"  [!] Hata: {err}")
                stats["hatali"] += 1
                stats["hatalar"].append(err)

        # 4. Sonra SONUÇ LİSTELERİNİ işle
        for pdf_url in result_urls:
            filename = os.path.basename(pdf_url)
            try:
                pdf_bytes, meta = download_file_with_meta(pdf_url)

                # Daha önce işlenmiş ve değişmemişse atla
                if check_file_already_processed(base_url, event_id, filename, meta, api_key=api_key):
                    print(f"  [-] {filename} zaten işlenmiş ve değişmemiş; atlanıyor.")
                    stats["atlanilan"] += 1
                    stats["islenen_sonuc_listesi"] += 1
                    continue

                # Yarış no tespiti (Örn: ResultList_1.pdf -> 1)
                m_no = re.search(r"(?:ResultList|StartList)_(\d+)\.pdf", filename, re.I)
                if not m_no:
                    m_no = re.search(r"_(\d+)\.pdf", filename, re.I)
                yaris_no = m_no.group(1) if m_no else None

                # Django'dan Start listesindeki aday sporcuları ve DB ID'lerini çek
                startlist_swimmers = None
                if yaris_no:
                    startlist_swimmers = fetch_startlist_swimmers(base_url, event_id, yaris_no, api_key=api_key)
                    if startlist_swimmers:
                        print(f"  [*] Yarış #{yaris_no} için {len(startlist_swimmers)} startlist sporcusu eşleştirme için yüklendi.")

                print(f"  [>] {filename} ayrıştırılıyor (Sonuç Listesi - Gemini Flash Lite)...")
                parsed = parse_meet_pdf(pdf_bytes, client, pdf_url=pdf_url, model=model, startlist_swimmers=startlist_swimmers)
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
                parsed["content_hash"] = meta.get("content_hash")
                parsed["dosya_boyutu"] = meta.get("dosya_boyutu")

                aktar_url = get_endpoint_url(base_url, "canli-aktar")
                if not post_to_django(aktar_url, parsed, api_key=api_key):
                    raise RuntimeError(f"Django aktarımı başarısız oldu ({aktar_url})")

                stats["basarili"] += 1
                stats["islenen_sonuc_listesi"] += 1
                record_count = len(parsed.get("kayitlar", [])) + len(parsed.get("yeni_sporcular", []))
                stats["toplam_sporcu"] += record_count
                print(f"  [+] {filename} sonuçları başarıyla güncellendi ({record_count} derece)")

                # PythonAnywhere tek worker'ına nefes aldır
                time.sleep(1.5)

            except Exception as e:
                err = f"{filename} (ResultList): {str(e)}"
                print(f"  [!] Hata: {err}")
                stats["hatali"] += 1
                stats["hatalar"].append(err)

    except Exception as e:
        err = f"Genel Tarama Hatası ({event_url}): {str(e)}"
        print(f"[!] {err}")
        stats["hatali"] += 1
        stats["hatalar"].append(err)

    # Nihai durum tespiti
    if (stats["basarili"] + stats["atlanilan"]) == 0 and stats["hatali"] > 0:
        stats["durum"] = "HATA"
    else:
        stats["durum"] = "TAMAMLANDI"

    # Django'da son durumu kaydet
    update_meet_status(base_url, stats, api_key=api_key)
    print(f"[*] Müsabaka #{event_id} tamamlandı: Durum={stats['durum']}, Başarılı={stats['basarili']}, Atlanılan={stats['atlanilan']}, Hatalı={stats['hatali']}\n")
    return stats


def tyf_startlist_handler(request):
    """
    Google Cloud Functions (gen2) / Cloud Run HTTP Handler.
    Cloud Scheduler tarafından periyodik (ör: her 5 veya 10 dk) tetiklendiğinde:
    1. Django API'den bekleyen canlı yarışları çeker (GET /api/canli-bekleyen-yarislar/).
    2. Bekleyen yarış yoksa 0.5 saniyede 200 OK dönerek Cloud Run örneğini sonlandırır (maliyet tasarrufu).
    3. Bekleyen yarış varsa sırayla start ve sonuç listelerini indirip, hash kontrolü yaparak
       yalnızca yeni/değişen dosyaları Gemini ile işler ve Django'ya aktarır.
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
        stats = process_single_meet(meet, base_url, client, model=model, limit=limit, api_key=api_key)
        return (json.dumps(stats, ensure_ascii=False), 200, {"Content-Type": "application/json; charset=utf-8"})

    # Rutin Tarama Modu (Cloud Scheduler cron)
    print(f"[*] Rutin Tarama Başlatıldı. Hedef: {base_url}")
    pending_meets = fetch_pending_meets(base_url, api_key=api_key)

    if not pending_meets:
        msg = "Bekleyen veya işlemde olan canlı yarış bulunamadı. Görev sonlandırıldı."
        print(f"[*] {msg}")
        return (json.dumps({
            "durum": "TAMAMLANDI",
            "mesaj": msg,
            "islenen_yaris_sayisi": 0
        }, ensure_ascii=False), 200, {"Content-Type": "application/json; charset=utf-8"})

    print(f"[*] {len(pending_meets)} adet bekleyen canlı yarış bulundu.")
    reports = []
    for meet in pending_meets:
        rep = process_single_meet(meet, base_url, client, model=model, limit=limit, api_key=api_key)
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
        rep = process_single_meet(meet, target_base, client, model=args.model, limit=args.limit)
        print(json.dumps(rep, indent=2, ensure_ascii=False))
    else:
        print(f"[*] Rutin Tarama: {target_base} adresindeki bekleyen yarışlar sorgulanıyor...")
        pending = fetch_pending_meets(target_base)
        if not pending:
            print("[*] Bekleyen veya işlemde olan canlı yarış bulunamadı.")
        else:
            print(f"[*] {len(pending)} adet bekleyen yarış bulundu.")
            for m in pending:
                process_single_meet(m, target_base, client, model=args.model, limit=args.limit)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="TYF Canlı Yarış Tarayıcısı (Cloud Run / CLI Runner)")
    parser.add_argument("--base-url", default=DEFAULT_DJANGO_BASE_URL, help="Django ana web adresi (Varsayılan: https://ozztozz.pythonanywhere.com)")
    parser.add_argument("--url", default=None, help="Doğrudan belirli bir canlı yarış URL'sini tara")
    parser.add_argument("--id", default=None, help="Yarış ID (isteğe bağlı)")
    parser.add_argument("--limit", type=int, default=None, help="Her yarış için taranacak azami PDF sayısı")
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
        rep = process_single_meet(meet, target_base, client, model=args.model, limit=args.limit)
        print(json.dumps(rep, indent=2, ensure_ascii=False))
    else:
        print(f"[*] Rutin Tarama: {target_base} adresindeki bekleyen yarışlar sorgulanıyor...")
        pending = fetch_pending_meets(target_base)
        if not pending:
            print("[*] Bekleyen veya işlemde olan canlı yarış bulunamadı.")
        else:
            print(f"[*] {len(pending)} adet bekleyen yarış bulundu.")
            for m in pending:
                process_single_meet(m, target_base, client, model=args.model, limit=args.limit)

