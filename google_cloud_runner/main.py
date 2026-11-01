"""
TYF PDF ve Gemini ayr??t?rma yard?mc?lar?.

Bu mod?l yaln?zca PDF/Gemini ayr??t?rma yard?mc?lar?n? sa?lar. Kal?c? kay?t
ve sonu? e?le?tirmesi Django ORM kullanan ``sonuclar.live_db_runner``
mod?l?ndedir; bu dosyada Django HTTP aktar?m? bulunmaz.
"""

import os
import re
import json
import time
import unicodedata
from urllib.parse import urljoin
from typing import Dict, List, Any, Optional, Tuple
from concurrent.futures import ThreadPoolExecutor

try:
    import requests
    from requests.adapters import HTTPAdapter
except ImportError:
    requests = None
    HTTPAdapter = None

try:
    import pymupdf as fitz
except ImportError:
    try:
        import fitz
    except ImportError:
        fitz = None

try:
    from bs4 import BeautifulSoup
except ImportError:
    BeautifulSoup = None

try:
    from google import genai
    from google.genai import types
except ImportError:
    genai = None
    types = None

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

# Kalıcı TCP/TLS bağlantı havuzu (HTTP Keep-Alive ile tekrarlı el sıkışma yükünü önler)
_HTTP_SESSION: Optional[requests.Session] = None
_FALLBACK_GEMINI_CLIENT: Optional[genai.Client] = None
_USE_FALLBACK_KEY: bool = False
# Aynı tarama çalışmasında start ve sonuç PDF'leri arasında kaynak maskeli adı korur.


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
    ?nce birincil GEMINI_API_KEY ile istek atar; kota/limit hatas? (429) al?n?rsa
    GEMINI_API_KEY_2'ye ge?er. ?kisi de dolmu?sa veya kota a??m? varsa k?sa bir bekleme (backoff) ile yeniden dener.
    """
    global _USE_FALLBACK_KEY
    fallback_client = get_fallback_gemini_client()

    for attempt in range(4):
        use_fallback = (_USE_FALLBACK_KEY and fallback_client is not None)
        client = fallback_client if use_fallback else primary_client
        try:
            return client.models.generate_content(model=model, contents=contents, config=config)
        except Exception as e:
            if _is_quota_error(e):
                if '402' in str(e) or 'prepayment' in str(e).lower() or 'depleted' in str(e).lower():
                    _USE_FALLBACK_KEY = False
                elif not _USE_FALLBACK_KEY and fallback_client is not None:
                    print('  [!] Birincil API kota doldu, GEMINI_API_KEY_2 deneniyor...')
                    try:
                        res = fallback_client.models.generate_content(model=model, contents=contents, config=config)
                        _USE_FALLBACK_KEY = True
                        return res
                    except Exception as fb_err:
                        print(f'  [!] GEMINI_API_KEY_2 de kota/kredi hatas? verdi: {fb_err}')
                        _USE_FALLBACK_KEY = False

                if attempt < 3:
                    wait_sec = 25 + (attempt * 10)
                    print(f'  [*] Gemini 429/RPM limiti a??ld?. {wait_sec} sn beklenip tekrar deneniyor ({attempt + 1}/3)...')
                    time.sleep(wait_sec)
                    continue
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


def parse_tr_date_range(d_str: str) -> Tuple[str, str]:
    """T?rk?e tarih aral???n? ISO format?na d?n??t?r?r (?rn: '30.10. - 1.11.2026' -> '2026-10-30', '2026-11-01')."""
    if not d_str:
        return '', ''
    d_clean = re.sub(r'\s+', ' ', d_str.strip())
    # 1. Farkl? aylar i?eren aral?klar (?rn: 30.10. - 1.11.2026 veya 30.10.2026 - 1.11.2026)
    m_diff = re.search(r'(\d{1,2})\.(\d{1,2})\.?(?:\d{4})?\s*-\s*(\d{1,2})\.(\d{1,2})\.(\d{4})', d_clean)
    if m_diff:
        d1, m1, d2, m2, y = m_diff.groups()
        return f'{y}-{int(m1):02d}-{int(d1):02d}', f'{y}-{int(m2):02d}-{int(d2):02d}'

    # 2. Ayn? ay i?indeki aral?klar (?rn: 24. - 26.4.2026 veya 24-26.04.2026)
    m_same = re.search(r'(\d{1,2})\.?\s*-\s*(\d{1,2})\.(\d{1,2})\.(\d{4})', d_clean)
    if m_same:
        d1, d2, m, y = m_same.groups()
        return f'{y}-{int(m):02d}-{int(d1):02d}', f'{y}-{int(m):02d}-{int(d2):02d}'

    # 3. Tekil tarih (?rn: 24.4.2026)
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


def normalize_masked_name(value: Any) -> str:
    """
    Türkçe isimleri karşılaştırılabilir standart formata getirir.
    Maskeleme varyasyonlarını tek tip '*' yapar.
    'Maskeli sporcu (...)' gibi sarmalayıcıları temizler.
    """
    if not value:
        return ""
    text = unicodedata.normalize("NFKC", str(value)).strip()
    
    # Sarmalayıcı ön ekleri temizle: "Maskeli sporcu (CAN K***)" -> "CAN K***"
    text = re.sub(r'^(?:maskeli\s+sporcu\s*[\(\[]?|\(f\d+\)\s*|[\(\[])', '', text, flags=re.IGNORECASE)
    text = re.sub(r'[\)\]]$', '', text).strip()
    
    # Türkçe küçük i/ı dönüşümü ve büyük harfe çevirme
    text = text.replace("i", "İ").replace("ı", "I").upper()
    mapping = str.maketrans({
        "İ": "I", "Ş": "S", "Ğ": "G", "Ü": "U", "Ö": "O", "Ç": "C",
        "|": "L",
    })
    text = text.translate(mapping)
    
    # OCR düzeltmesi: Kelime sonundaki 'OGU' -> 'OGLU'
    text = re.sub(r'\bOGU\b', 'OGLU', text)
    
    # Maskeleme karakterlerini '*' yap:
    # 1. Unicode yıldızlar, mermi simgeleri ve orta noktalar
    text = re.sub(r'[\u2731-\u2739\u2605\u2606\u2022\u00B7\u2026]+', '*', text)
    # 2. İki veya daha fazla nokta (.. veya ...)
    text = re.sub(r'\.{2,}', '*', text)
    # 3. İki veya daha fazla alt tire (__)
    text = re.sub(r'_+', '*', text)
    # 4. KVKK amaçlı ardışık X'ler (örn: KXXXX -> K****)
    text = re.sub(r'([A-Z0-9])X{2,}', lambda m: m.group(1) + '*' * (len(m.group(0)) - 1), text)
    # 5. Tekil X'lerden oluşan soyadlar (örn: 'A*** X')
    text = re.sub(r'\bX+\b', '*', text)
    
    # Harf, rakam ve '*' dışındakileri boşluğa çevir (tekil noktayı kısaltma olarak tanı)
    text = re.sub(r'[^A-Z0-9*.]+', ' ', text)
    # Noktalı kısaltmaları ayır (örn: 'M.ALI' -> 'M. ALI')
    text = re.sub(r'\.([A-Z0-9*])', r'. \1', text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text

def build_masked_like_pattern(masked_name: str) -> str:
    """
    Maskeli isimden SQL LIKE sorgusu deseni üretir.
    Kelimelerin arasına ve yıldızların yerine '%' yerleştirir.
    Örn: 'MEHMET Y****' -> '%MEHMET%Y%'
    Örn: 'CAN K***' -> '%CAN%K%'
    """
    norm = normalize_masked_name(masked_name)
    tokens = norm.split()
    if not tokens:
        return "%"
    parts = []
    for t in tokens:
        t_clean = t.rstrip('.')
        part = re.sub(r'\*+', '%', t_clean)
        parts.append(part)
    return "%" + "%".join(parts) + "%"


def build_masked_wildcard_regex(masked_name: str) -> Optional[re.Pattern]:
    """
    Maskeli isimden toleranslı wildcard regex deseni üretir.
    İki isimli veya kısaltmalı adları destekler.
    Örn: 'MEHMET Y****' -> r'\bMEHMET.*?\bY.*?'
    Örn: 'M. ALI K***' -> r'\bM[A-Z0-9]*.*?\bALI.*?\bK.*?'
    """
    norm = normalize_masked_name(masked_name)
    tokens = norm.split()
    if not tokens:
        return None

    parts = []
    for t in tokens:
        t_clean = t.rstrip('.')
        if '*' not in t_clean:
            if len(t_clean) == 1:
                parts.append(re.escape(t_clean) + r'[A-Z0-9]*')
            else:
                parts.append(re.escape(t_clean))
        else:
            clean_stars = re.sub(r'\*+', '*', t_clean)
            sub_parts = [re.escape(p) for p in clean_stars.split('*')]
            parts.append(r'.*?'.join(sub_parts))

    regex_str = r'\b' + r'.*?\b'.join(parts)
    return re.compile(regex_str, re.IGNORECASE)



def is_subsequence(sub: str, string: str) -> bool:
    """sub karakterlerinin tamamı string içinde aynı sırada yer alıyor mu?"""
    if not sub:
        return True
    it = iter(string)
    return all(c in it for c in sub)


def _token_matches(masked_tok: str, cand_tok: str) -> Tuple[bool, float]:
    """
    İki tokenı karşılaştırır:
    - Birebir eşitlik: 1.0
    - Baş harf kısaltması ('M.' veya 'M' vs 'MEHMET'): 0.88
    - Maskeli eşleşme ('A***' vs 'AHMET'): 0.80 - 1.0
    - Subsequence: 0.72 - 0.85
    """
    m = masked_tok.strip().rstrip('.')
    c = cand_tok.strip().rstrip('.')
    if not m or not c:
        return False, 0.0
    if m == c:
        return True, 1.0
    
    # Baş harf kısaltması kontrolü: 'M' vs 'MEHMET'
    if len(m) == 1 and '*' not in m:
        if c.startswith(m):
            return True, 0.88
        return False, 0.0
    if len(c) == 1 and '*' not in c:
        if m.startswith(c):
            return True, 0.88
        return False, 0.0

    # Maskeli wildcard kontrolü
    if '*' in m:
        clean_pat = re.sub(r'\*+', '*', m)
        regex = "^" + re.escape(clean_pat).replace(r"\*", ".*") + "$"
        if re.match(regex, c):
            vis_len = len(m.replace('*', ''))
            ratio = vis_len / max(len(c), 1)
            return True, 0.78 + min(ratio * 0.22, 0.22)
            
    # Subsequence kontrolü
    vis_m = re.sub(r'[^A-Z0-9]', '', m)
    if vis_m and len(vis_m) >= 2 and is_subsequence(vis_m, c):
        if vis_m[0] == c[0]:
            ratio = len(vis_m) / max(len(c), 1)
            return True, 0.72 + min(ratio * 0.20, 0.20)

    return False, 0.0


def _match_name_tokens(masked_tokens: List[str], cand_tokens: List[str]) -> Tuple[bool, float]:
    """
    İsim token listelerini esnek olarak eşleştirir.
    Alt küme, bileşik ad ve kısaltma toleranslıdır.
    """
    if not masked_tokens or not cand_tokens:
        return False, 0.0

    # 1. Birebir uzunluk eşleşmesi
    if len(masked_tokens) == len(cand_tokens):
        all_ok = True
        scores = []
        for mt, ct in zip(masked_tokens, cand_tokens):
            ok, sc = _token_matches(mt, ct)
            if not ok:
                all_ok = False
                break
            scores.append(sc)
        if all_ok:
            return True, sum(scores) / len(scores)

    # 2. Bileşik isim kontrolü (örn: 'MEHMETCAN' vs ['MEHMET', 'CAN'])
    m_joined = "".join(t.replace('*', '') for t in masked_tokens)
    c_joined = "".join(cand_tokens)
    if m_joined and c_joined:
        if m_joined == c_joined:
            return True, 0.95
        if is_subsequence(m_joined, c_joined) and m_joined[0] == c_joined[0]:
            return True, 0.85

    # 3. Alt küme kontrolü: Maskeli tokenların adayın tokenları içinde bulunması
    matched_scores = []
    used_cands = set()
    for mt in masked_tokens:
        best_sc = 0.0
        best_idx = -1
        for idx, ct in enumerate(cand_tokens):
            if idx in used_cands:
                continue
            ok, sc = _token_matches(mt, ct)
            if ok and sc > best_sc:
                best_sc = sc
                best_idx = idx
        if best_idx != -1:
            used_cands.add(best_idx)
            matched_scores.append(best_sc)

    if len(matched_scores) == len(masked_tokens) and matched_scores:
        coverage_penalty = len(masked_tokens) / len(cand_tokens)
        base = sum(matched_scores) / len(matched_scores)
        return True, base * (0.88 + 0.12 * coverage_penalty)

    if len(matched_scores) == len(cand_tokens) and matched_scores:
        base = sum(matched_scores) / len(matched_scores)
        return True, base * 0.90

    return False, 0.0


def split_athlete_tokens(tokens: List[str]) -> Tuple[List[str], List[str]]:
    """
    Token listesini ön ad(lar) ve soyad(lar) olarak böler.
    Maske işaretinin başladığı noktayı soyadı başlangıcı kabul eder.
    """
    if not tokens:
        return [], []
    if len(tokens) == 1:
        return tokens, tokens
    
    firsts = []
    surnames = []
    mask_started = False
    for t in tokens:
        if '*' in t:
            mask_started = True
        if not mask_started:
            firsts.append(t)
        else:
            surnames.append(t)
            
    if not firsts:
        firsts = tokens[:-1]
        surnames = [tokens[-1]]
    elif not surnames:
        firsts = tokens[:-1]
        surnames = [tokens[-1]]

    return firsts, surnames


def split_masked_name(masked_name: str) -> Tuple[List[str], str]:
    """
    Maskeli adı ön ad(lar) ve maskeli soyad olarak ikiye ayırır.
    Geriye dönük uyumluluk için korunmuştur.
    """
    norm = normalize_masked_name(masked_name)
    tokens = norm.split()
    firsts, surnames = split_athlete_tokens(tokens)
    return firsts, " ".join(surnames)


def _masked_token_match(masked: str, candidate: str) -> Tuple[bool, float]:
    """Bir isim token'ını yıldızları wildcard kabul ederek eşleştirir (geriye dönük uyumluluk)."""
    return _token_matches(masked, candidate)


def normalize_club_name(club_name: Any) -> str:
    """Kulüp isimlerini normalize eder ve kısaltmaları standartlaştırır."""
    if not club_name:
        return ""
    text = unicodedata.normalize("NFKC", str(club_name)).strip().upper()
    text = text.replace("i", "İ").replace("ı", "I")
    mapping = str.maketrans({"İ": "I", "Ş": "S", "Ğ": "G", "Ü": "U", "Ö": "O", "Ç": "C"})
    text = text.translate(mapping)
    text = re.sub(r'\bB[\.\s]*B[\.\s]*S[\.\s]*K[\.\s]*\b', ' BUYUKSEHIR BELEDIYESI SPOR KULUBU ', text)
    text = re.sub(r'\bB[\.\s]*S[\.\s]*B[\.\s]*\b', ' BUYUKSEHIR BELEDIYESI ', text)
    text = re.sub(r'\bI[\.\s]*B[\.\s]*B[\.\s]*\b', ' ISTANBUL BUYUKSEHIR BELEDIYESI ', text)
    text = re.sub(r'\bG[\.\s]*S[\.\s]*K[\.\s]*\b', ' GENCLIK SPOR KULUBU ', text)
    text = re.sub(r'\bS[\.\s]*K[\.\s]*\b', ' SPOR KULUBU ', text)
    text = re.sub(r'\bY[\.\s]*I[\.\s]*K[\.\s]*\b', ' YUZME IHTISAS KULUBU ', text)
    text = re.sub(r'[^A-Z0-9]+', ' ', text)
    return re.sub(r'\s+', ' ', text).strip()


def clubs_match(c1: Optional[str], c2: Optional[str]) -> bool:
    """İki kulüp adının aynı veya türevi olup olmadığını doğrular."""
    n1 = normalize_club_name(c1)
    n2 = normalize_club_name(c2)
    if not n1 or not n2:
        return False
    if n1 == n2 or n1 in n2 or n2 in n1:
        return True
    ignore_words = {
        'SPOR', 'KULUBU', 'DERNEGI', 'ILKOKULU', 'ORTAOKULU', 'KOLEJI',
        'BELEDIYESI', 'BELEDIYE', 'GENCLIK', 'IL', 'MUDURLUGU', 'YUZME', 'IHTISAS', 'VE'
    }
    w1 = set(n1.split()) - ignore_words
    w2 = set(n2.split()) - ignore_words
    return bool(w1 and w2 and (w1 & w2))


def masked_name_match_score(masked_name: str, candidate_name: str) -> Optional[float]:
    """
    Maskeli adı adayın adıyla puanlar.
    Sonuç 0-100 arasında döner; uyumsuzluk durumunda None döner.
    """
    norm_m = normalize_masked_name(masked_name)
    norm_c = normalize_masked_name(candidate_name)
    if not norm_m or not norm_c:
        return None
    if norm_m == norm_c:
        return 100.0

    if "*" in norm_c and "*" not in norm_m:
        return masked_name_match_score(candidate_name, masked_name)

    m_tokens = norm_m.split()
    c_tokens = norm_c.split()
    if not m_tokens or not c_tokens:
        return None

    # Hızlı ilk harf kontrolü
    if m_tokens[0] and c_tokens[0] and m_tokens[0][0] != '*' and c_tokens[0][0] != '*':
        if not any(ct.startswith(m_tokens[0][0]) for ct in c_tokens):
            return None

    # 1. Bütünsel Token Eşleştirmesi (Aynı token sayısında)
    if len(m_tokens) == len(c_tokens):
        all_matched = True
        token_scores = []
        for mt, ct in zip(m_tokens, c_tokens):
            ok, sc = _token_matches(mt, ct)
            if not ok:
                all_matched = False
                break
            token_scores.append(sc)
        if all_matched:
            return round(sum(token_scores) / len(token_scores) * 100.0, 1)

    # 2. Ön Ad(lar) ve Soyad(lar) Parçalı Eşleştirmesi
    m_firsts, m_surnames = split_athlete_tokens(m_tokens)
    c_firsts, c_surnames = c_tokens[:-1] if len(c_tokens) > 1 else c_tokens, [c_tokens[-1]]

    first_ok, first_score = _match_name_tokens(m_firsts, c_firsts)
    if not first_ok:
        ok, sc = _token_matches(m_firsts[0], c_firsts[0]) if (m_firsts and c_firsts) else (False, 0.0)
        if ok:
            first_ok, first_score = True, sc * 0.85
        else:
            return None

    surname_ok, surname_score = _match_name_tokens(m_surnames, c_surnames)
    if not surname_ok:
        if len(c_tokens) >= 2:
            alt_c_surnames = c_tokens[len(m_firsts):] if len(m_firsts) < len(c_tokens) else [c_tokens[-1]]
            s_ok, s_sc = _match_name_tokens(m_surnames, alt_c_surnames)
            if s_ok:
                surname_ok, surname_score = True, s_sc * 0.90

    if not surname_ok:
        m_sur_str = "".join(m_surnames)
        c_sur_str = "".join(c_surnames)
        vis_sur = re.sub(r'[^A-Z0-9]', '', m_sur_str)
        if not vis_sur:
            surname_ok, surname_score = True, 0.75
        elif is_subsequence(vis_sur, c_sur_str):
            if vis_sur[0] == c_sur_str[0]:
                ratio = len(vis_sur) / max(len(c_sur_str), 1)
                surname_ok, surname_score = True, 0.75 + min(ratio * 0.20, 0.20)

    if not surname_ok:
        return None

    total_score = (first_score * 0.52 + surname_score * 0.48) * 100.0
    return round(total_score, 1)


def resolve_masked_athlete(
    masked_name: str,
    candidates: List[Dict[str, Any]],
    birth_year: Any = None,
    club: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Maskeli start-list adını mevcut aday kayıtlarla yüksek doğruluk ve hızla eşleştirir.
    Puanlama:
    - Temel isim skoru: 0 - 70 arası (name_score * 0.70)
    - Doğum yılı tam eşleşmesi: +15 puan (1 yaş fark toleransı: +5 puan)
    - Kulüp eşleşmesi: +15 puan
    Böylece toplam skor 0-100 arasında dengeli dağılır; adaylar arasındaki kulüp veya doğum yılı
    farkı tavan kırpılmasına takılmadan belirleyici rol oynar.
    """
    if not masked_name or not candidates:
        return {"durum": "bulunamadi", "adaylar": []}

    target_year = None
    try:
        if birth_year:
            target_year = int(str(birth_year).strip())
            if target_year < 100:
                target_year += 2000 if target_year <= 35 else 1900
    except (TypeError, ValueError):
        target_year = None

    norm_masked = normalize_masked_name(masked_name)
    wildcard_rx = build_masked_wildcard_regex(norm_masked)

    scored = []
    for candidate in candidates:
        cand_name = candidate.get("sporcu") or candidate.get("sporcu_adi") or ""
        if not cand_name:
            continue

        cand_norm = normalize_masked_name(cand_name)
        # Hızlı Wildcard Elemesi: Adayın normalize adı wildcard desenine uymuyorsa atla
        if wildcard_rx and not wildcard_rx.search(cand_norm):
            continue

        name_score = masked_name_match_score(norm_masked, cand_name)
        if name_score is None:
            continue

        candidate_year = candidate.get("dogum_yili")
        try:
            if candidate_year:
                candidate_year = int(str(candidate_year).strip())
                if candidate_year < 100:
                    candidate_year += 2000 if candidate_year <= 35 else 1900
        except (TypeError, ValueError):
            candidate_year = None

        # Doğum yılı kontrolü
        year_bonus = 0.0
        if target_year and candidate_year:
            if target_year == candidate_year:
                year_bonus = 15.0
            elif abs(target_year - candidate_year) == 1:
                year_bonus = 5.0
            else:
                # 2 veya daha fazla yaş farkı varsa elenir
                continue
        elif not target_year or not candidate_year:
            year_bonus = 5.0

        # Kulüp kontrolü
        club_bonus = 0.0
        candidate_club = candidate.get("kulup") or candidate.get("kulup_adi")
        if club and candidate_club:
            if clubs_match(club, candidate_club):
                club_bonus = 15.0
        elif not club or not candidate_club:
            club_bonus = 5.0

        final_score = (name_score * 0.70) + year_bonus + club_bonus
        final_score = min(round(final_score, 1), 100.0)

        scored.append((final_score, candidate))

    scored.sort(key=lambda item: item[0], reverse=True)
    if not scored:
        return {"durum": "bulunamadi", "adaylar": []}

    top_score, top_candidate = scored[0]
    second_score = scored[1][0] if len(scored) > 1 else None

    # Eşleşme kararı
    if second_score is None:
        confident = top_score >= 62.0
    else:
        gap = top_score - second_score
        if top_score >= 82.0 and gap >= 5.0:
            confident = True
        elif top_score >= 70.0 and gap >= 8.0:
            confident = True
        else:
            confident = False

    return {
        "durum": "eslesti" if confident else "belirsiz",
        "aday": top_candidate if confident else None,
        "skor": top_score,
        "adaylar": [
            {"skor": s, **cand}
            for s, cand in scored[:5]
        ],
    }


def _lane_key(series: Any, lane: Any) -> Optional[Tuple[str, int]]:
    if series in (None, "") or lane in (None, ""):
        return None
    try:
        lane_int = int(str(lane).strip())
    except (TypeError, ValueError):
        return None
    return normalize_masked_name(series), lane_int


def reconcile_result_ids(
    records: List[Dict[str, Any]],
    startlist_swimmers: Optional[List[Dict[str, Any]]],
) -> List[Dict[str, Any]]:
    """
    Sonuç satırlarını önce seri+kulvar ile deterministik olarak start kaydına bağlar.
    Seri/kulvar yoksa (DQ / diskalifiye satırları gibi) start listesindeki maskeli isimlerle eşleştirir.
    """
    if not startlist_swimmers:
        return records

    by_lane: Dict[Tuple[str, int], List[Dict[str, Any]]] = {}
    by_id = {str(s.get("id")): s for s in startlist_swimmers if s.get("id") is not None}

    for swimmer in startlist_swimmers:
        key = _lane_key(swimmer.get("seri"), swimmer.get("kulvar"))
        if key:
            by_lane.setdefault(key, []).append(swimmer)

    reconciled = []
    matched_start_ids = set()

    for record in records:
        item = dict(record)
        key = _lane_key(item.get("seri"), item.get("kulvar"))
        lane_candidates = by_lane.get(key, []) if key else []

        # 1. Aşama: Seri + Kulvar tam eşleşmesi
        if len(lane_candidates) == 1:
            matched_id = lane_candidates[0].get("id")
            item["id"] = matched_id
            item["eslesme_yontemi"] = "seri_kulvar"
            item["eslesme_durumu"] = "eslesti"
            matched_start_ids.add(matched_id)

        # 2. Aşama: Gemini'nin doğrudan döndürdüğü ID doğrulaması
        elif item.get("id") is not None and str(item["id"]) in by_id:
            candidate = by_id[str(item["id"])]
            name_score = masked_name_match_score(
                item.get("sporcu") or item.get("sporcu_maskeli") or "",
                candidate.get("sporcu_maskeli") or candidate.get("sporcu") or candidate.get("sporcu_adi") or "",
            )
            if name_score is not None and name_score >= 70:
                item["eslesme_yontemi"] = "isim_kontrolu"
                item["eslesme_skoru"] = name_score
                item["eslesme_durumu"] = "eslesti"
                matched_start_ids.add(candidate.get("id"))
            else:
                item["eslesme_aday_id"] = item.pop("id")
                item["eslesme_durumu"] = "inceleme_bekliyor"

        # 3. Aşama: Diskalifiye (DQ), DNF veya kulvarsız satırlarda Start Listesi maskeli isim eşleşmesi
        else:
            raw_result_name = item.get("sporcu") or item.get("sporcu_maskeli") or ""
            best_cand = None
            best_score = 0.0

            for cand in startlist_swimmers:
                c_id = cand.get("id")
                if c_id in matched_start_ids:
                    continue

                target_masked = cand.get("sporcu_maskeli") or cand.get("sporcu") or cand.get("sporcu_adi") or ""
                if target_masked.startswith("Maskeli sporcu (") and target_masked.endswith(")"):
                    target_masked = target_masked[16:-1].strip()
                score = masked_name_match_score(raw_result_name, target_masked)
                if score is not None and score > best_score:
                    best_score = score
                    best_cand = cand

            if best_cand and best_score >= 70.0:
                matched_id = best_cand.get("id")
                item["id"] = matched_id
                item["eslesme_yontemi"] = "startlist_maskeli_eslesme"
                item["eslesme_skoru"] = best_score
                item["eslesme_durumu"] = "eslesti"
                matched_start_ids.add(matched_id)
                # Kulüp veya seri/kulvar start listesinde varsa sonuç kaydına aktar
                if not item.get("kulup") and best_cand.get("kulup_adi"):
                    item["kulup"] = best_cand.get("kulup_adi")
                if not item.get("seri") and best_cand.get("seri"):
                    item["seri"] = best_cand.get("seri")
                if item.get("kulvar") is None and best_cand.get("kulvar") is not None:
                    item["kulvar"] = best_cand.get("kulvar")
            else:
                item["eslesme_durumu"] = "inceleme_bekliyor"

        reconciled.append(item)
    return reconciled


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
            if startlist_swimmers:
                candidates = []
                for s in startlist_swimmers:
                    candidates.append({
                        "id": s.get("id"),
                        "sporcu": s.get("sporcu_maskeli") or s.get("sporcu") or s.get("sporcu_adi"),
                        "sporcu_maskeli": s.get("sporcu_maskeli") or s.get("sporcu") or s.get("sporcu_adi"),
                        "sporcu_adi": s.get("sporcu_adi"),
                        "kulup": s.get("kulup_adi"),
                        "dogum_yili": s.get("dogum_yili"),
                        "seri": s.get("seri"),
                        "kulvar": s.get("kulvar")
                    })
                cands_json = json.dumps(candidates, ensure_ascii=False)
                swimmers_context = f"\nBU YARIŞTA YÜZEN START LİSTESİNDEKİ SPORCULAR:\n{cands_json}\n"

                prompt = f"""Bu bir TYF Splash Meet Manager SONUÇ LİSTESİ PDF sayfasıdır.
Sayfa {p_num}/{total_pages}.
{swimmers_context}
Sayfadaki tüm sporcu sonuçlarını eksiksiz çıkar ve yukarıdaki start listesi ile eşleştir.
Eşleşen sporcular için SADECE satır "id", "sira", "derece", "puan" ve "baraj" değerlerini döndür.
(Eşleşen sporcular için isim, kulüp, doğum yılı ve başlık bilgilerini ÇIKARMA, veritabanı satır id'si yeterlidir).
Eşleştirmeyi öncelikle seri ve kulvar ile yap. Seri/kulvar yazmayan satırlarda (diskalifiye DQ/disk., terk DNF vb.) veya sayfa sonundaki diskalifiye listelerinde sporcu adındaki maskeli harfleri (örn. 'Kaan K**t*') yukarıdaki start listesindeki 'sporcu_maskeli' ile karşılaştırarak doğru 'id'yi eşleştir; id'yi boş bırakma.
Sonuç satırındaki seri, kulvar ve kaynakta görünen maskeli sporcu adını da koru.
Start listesinde yer almayan yeni/yedek bir sporcu yüzmüşse onu "yeni_sporcular" listesine ekle.

ÖNEMLİ KURALLAR:
1. DİSKALİFİYE (disk. / DQ): Diskalifiye olan sporcular için ara zaman veya süre derecesi ASLA VERME (Örn: satırda '28.68 32.46' gibi ara zamanlar yazsa bile dereceye koyma). "sira" değerine "DQ" yaz, "derece" alanına ise altındaki diskalifiye kuralını ve nedenini yaz (Örn: "SW 10.2.1 - Yüzmesi gereken mesafeyi tamamlamadığından (Zaman: 12:23), 100 mt terk"). Diskalifiyelerde "puan" ve "baraj" null olmalıdır.
2. TERK / KATILMADI (DNF / DNS): Yarışı terk edenler için "sira": "DNF", "derece": "DNF"; yarışa başlamayanlar için "sira": "DNS", "derece": "DNS" yaz ("puan" ve "baraj" null).

Format:
{{
  "kayitlar": [
    {{
      "id": integer veya null (yalnızca start listesindeki açık aday id'si),
      "seri": string veya null,
      "kulvar": integer veya null,
      "sporcu": string veya null (kaynakta görünen ad; maskeyi açma),
      "sira": integer veya string (1, 2, "DQ", "DNS" vb.),
      "derece": string ("2:41.39", "Disk." vb.),
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
SADECE JSON nesnesi (object) döndür."""
            else:
                prompt = f"""Bu bir TYF Splash Meet Manager SONUÇ LİSTESİ PDF sayfasıdır.
Sayfa {p_num}/{total_pages}.
{'1. Başlıktan müsabaka_adı, şehir, tarih (YYYY-MM-DD), yarış_no, cinsiyet (Erkek/Kadın), mesafe (m tam sayı), stil ve yaş_grubu çıkar.' if is_first else ''}
2. Sayfadaki tüm sporcu sonuçlarını eksiksiz çıkar.

ÖNEMLİ KURALLAR:
1. DİSKALİFİYE (disk. / DQ): Diskalifiye olan sporcular için ara zaman veya süre derecesi ASLA VERME (Örn: satırda '28.68 32.46' gibi ara zamanlar yazsa bile dereceye koyma). "sira" değerine "DQ" yaz, "derece" alanına ise altındaki diskalifiye kuralını ve nedenini yaz (Örn: "SW 10.2.1 - Yüzmesi gereken mesafeyi tamamlamadığından (Zaman: 12:23), 100 mt terk"). Diskalifiyelerde "puan" ve "baraj" null olmalıdır.
2. TERK / KATILMADI (DNF / DNS): Yarışı terk edenler için "sira": "DNF", "derece": "DNF"; yarışa başlamayanlar için "sira": "DNS", "derece": "DNS" yaz ("puan" ve "baraj" null).
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
SADECE JSON nesnesi (object) döndür."""
        else:
            prompt = f"""Bu bir TYF Splash Meet Manager START LİSTESİ PDF sayfasıdır.
Sayfa {p_num}/{total_pages}.
{'1. Başlıktan müsabaka_adı, şehir, tarih (YYYY-MM-DD), yarış_no, cinsiyet (Erkek/Kadın), mesafe (m tam sayı), stil ve yaş_grubu çıkar.' if is_first else ''}
2. Sayfadaki her seriyi ve her kulvardaki sporcuları eksiksiz çıkar.
3. Sporcu adını PDF'de göründüğü biçimde aynen aktar. '*' ve benzeri maskeleme
   karakterlerini koru; soyadı veya adı tahmin ederek açma.
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
      "sporcu_maskeli": string (PDF'de görünen adın aynısı),
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
                        elif "sporcu" in elem or "derece" in elem or "kulvar" in elem or "id" in elem:
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

    if not header_data.get("yaris_no") and (pdf_url or ""):
        m_yno = re.search(r'(?:StartList|ResultList)_(\d+)', pdf_url, re.I)
        if m_yno:
            header_data["yaris_no"] = m_yno.group(1)

    if doc_type == "sonuc_listesi":
        header_data["kayitlar"] = reconcile_result_ids(
            header_data.get("kayitlar", []),
            startlist_swimmers,
        )

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
