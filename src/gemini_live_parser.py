#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gemini_live_parser.py
=====================
Gemini 1.5 Flash-8B (Flash Lite) ve 1.5 Flash modelleri ile TYF canlı
Start List ve Result List PDF'lerini yapılandırılmış JSON / tablo verisine
dönüştüren yüksek doğruluklu parser.

Özellikler:
- Hem dijital (text) hem de taranmış (resim/scanned) PDF'leri destekler.
- Çok sayfalı PDF'lerde token sınırına takılmamak ve hiçbir sporcuyu atlamamak için
  sayfa bazlı (veya chunk) akıllı tarama yapar.
- Start listesi (Seri, Kulvar, Sporcu, YB, Kulüp, Giriş Derecesi)
- Sonuç listesi (Sıra, Sporcu, YB, Kulüp, Derece, Puan, Yaş Grubu, Diskalifiye Durumu)
- google-genai SDK'sı ve standart REST API fallback'i ile tam uyumlu çalışır.
"""

import os
import sys
import re
import json
import ssl
import time
import argparse
import urllib.request
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# .env dosyasını otomatik ve esnek şekilde yükle
def load_env_file():
    """Tüm olası dizinlerdeki .env dosyasını bulup os.environ'a yükler."""
    candidates = [
        Path(__file__).resolve().parent.parent / ".env",
        Path.cwd() / ".env",
        Path(__file__).resolve().parent / ".env",
    ]
    for env_path in candidates:
        if env_path.is_file():
            # 1. python-dotenv dene
            try:
                from dotenv import load_dotenv
                load_dotenv(dotenv_path=env_path, override=False)
            except ImportError:
                pass
            # 2. Manuel satır satır oku (dotenv paketi yoksa bile çalışır)
            try:
                with open(env_path, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if not line or line.startswith("#") or "=" not in line:
                            continue
                        k, v = line.split("=", 1)
                        k = k.strip()
                        v = v.strip().strip("'\"")
                        if k and k not in os.environ:
                            os.environ[k] = v
                break
            except Exception:
                pass

load_env_file()

try:
    import pymupdf as fitz
except ImportError:
    try:
        import fitz
    except ImportError:
        fitz = None

try:
    from google import genai
    from google.genai import types
    HAS_GENAI_SDK = True
except ImportError:
    HAS_GENAI_SDK = False


# Varsayılan Gemini modeli (Gemini Flash Lite)
DEFAULT_MODEL = os.environ.get("GEMINI_MODEL", "gemini-flash-lite-latest")


def get_api_key(api_key: Optional[str] = None) -> str:
    """API anahtarını argümandan veya ortam değişkenlerinden alır."""
    key = api_key or os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not key:
        load_env_file()
        key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    return key.strip().strip("'\"") if key else ""


def strip_markers(text: Optional[str]) -> str:
    """(Fd), (Tk), (Td) gibi yüzme etiketlerini temizler."""
    if not text:
        return ""
    cleaned = re.sub(r"\((?:Fd|Tk|Td)\)\s*", "", str(text), flags=re.IGNORECASE)
    return cleaned.strip()


def normalize_birth_year(yb: Any) -> Optional[str]:
    """Doğum yılını 4 haneli formata dönüştürür (örn: '10' -> '2010')."""
    if yb is None:
        return None
    s = str(yb).strip()
    if re.fullmatch(r"\d{2}", s):
        val = int(s)
        # 50 ve üzeri ise 19XX, altı ise 20XX
        return f"19{s}" if val >= 50 else f"20{s}"
    if re.fullmatch(r"\d{4}", s):
        return s
    return s


def download_pdf_bytes(url: str) -> bytes:
    """URL'den SSL doğrulaması esnek olarak PDF dosyasını indirir."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
    )
    with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
        return resp.read()


class GeminiLiveParser:
    def __init__(self, api_key: Optional[str] = None, model: str = DEFAULT_MODEL):
        self.api_key = get_api_key(api_key)
        self.model = model
        self.client = None
        if HAS_GENAI_SDK and self.api_key:
            try:
                self.client = genai.Client(api_key=self.api_key)
            except Exception as e:
                print(f"[!] google-genai Client başlatılamadı, REST kullanılacak: {e}", file=sys.stderr)

    def _call_gemini_api(self, pdf_bytes: bytes, prompt: str) -> Dict[str, Any]:
        """Gemini API'sine PDF ve istem gönderip JSON yanıt döner."""
        if not self.api_key:
            raise ValueError(
                "Gemini API anahtarı bulunamadı! Lütfen GEMINI_API_KEY veya GOOGLE_API_KEY "
                "ortam değişkenini ayarlayın veya --api-key parametresi ile belirtin."
            )

        # 1. Öncelik: google-genai SDK
        if self.client:
            try:
                part = types.Part.from_bytes(data=pdf_bytes, mime_type="application/pdf")
                response = self.client.models.generate_content(
                    model=self.model,
                    contents=[part, prompt],
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        temperature=0.1,
                    )
                )
                text = response.text or ""
                return self._parse_json_response(text)
            except Exception as e:
                err_msg = str(e)
                # Model bulunamadıysa (404) gemini-1.5-flash denenebilir
                if "404" in err_msg and self.model == "gemini-1.5-flash-8b":
                    print("[!] gemini-1.5-flash-8b bulunamadı, gemini-1.5-flash deneniyor...", file=sys.stderr)
                    self.model = "gemini-1.5-flash"
                    return self._call_gemini_api(pdf_bytes, prompt)
                print(f"[!] SDK hatası: {e}, REST API ile tekrar deneniyor...", file=sys.stderr)

        # 2. Öncelik: Doğrudan REST API fallback
        import base64
        pdf_b64 = base64.b64encode(pdf_bytes).decode("utf-8")
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent?key={self.api_key}"
        
        payload = {
            "contents": [{
                "parts": [
                    {"text": prompt},
                    {
                        "inline_data": {
                            "mime_type": "application/pdf",
                            "data": pdf_b64
                        }
                    }
                ]
            }],
            "generationConfig": {
                "temperature": 0.1,
                "responseMimeType": "application/json"
            }
        }
        
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        
        with urllib.request.urlopen(req, context=ctx, timeout=120) as resp:
            res_json = json.loads(resp.read().decode("utf-8"))
            try:
                text = res_json["candidates"][0]["content"]["parts"][0]["text"]
                return self._parse_json_response(text)
            except (KeyError, IndexError) as err:
                raise RuntimeError(f"Gemini API yanıt yapısı geçersiz: {res_json}") from err

    def _parse_json_response(self, text: str) -> Dict[str, Any]:
        """Model yanıtından temiz JSON ayrıştırır."""
        raw = text.strip()
        # Markdown kod bloklarını temizle
        if raw.startswith("```"):
            raw = re.sub(r"^```(?:json)?\s*", "", raw)
            raw = re.sub(r"\s*```$", "", raw)
        return json.loads(raw)

    def detect_document_type(self, pdf_bytes: bytes, hint: str = "") -> str:
        """PDF'in start listesi mi yoksa sonuç listesi mi olduğunu belirler."""
        h = hint.lower()
        if "startlist" in h or "start_list" in h or "start" in h:
            return "start_listesi"
        if "resultlist" in h or "result_list" in h or "sonuc" in h or "result" in h:
            return "sonuc_listesi"

        # İlk sayfa metnine bak
        if fitz:
            try:
                doc = fitz.open(stream=pdf_bytes, filetype="pdf")
                if len(doc) > 0:
                    first_text = doc[0].get_text().lower()
                    if "start listesi" in first_text or "start list" in first_text:
                        return "start_listesi"
                    if "sonuçlar" in first_text or "sonuclar" in first_text or "results" in first_text:
                        return "sonuc_listesi"
            except Exception:
                pass
        return "sonuc_listesi"

    def _get_start_list_page_prompt(self, page_num: int, total_pages: int, is_first_page: bool) -> str:
        """Start listesi için optimize edilmiş sayfa istemi."""
        header_instruction = ""
        if is_first_page:
            header_instruction = """
1. Belgenin başlığından müsabaka bilgilerini çıkar:
   - musabaka_adi: Müsabaka adı (örn: "13+ YAS UZUN KULVAR BARAJ GECME MUSABAKALARI")
   - sehir: Şehir (örn: "İSTANBUL")
   - tarih: Yarış tarihi YYYY-MM-DD formatında (örn: "2026-04-24")
   - yaris_no: Yarış numarası (örn: 2)
   - cinsiyet: "Erkek" veya "Kadın"
   - mesafe: Metre cinsinden mesafe tam sayı olarak (örn: 50, 100, 200, 400)
   - stil: "Serbest", "Sırtüstü", "Kurbağalama", "Kelebek" veya "Karışık"
   - yas_grubu: "Açık", "13 yaş" vb.
"""
        else:
            header_instruction = "1. Bu devam sayfasıdır, başlık bilgisi boş bırakılabilir."

        return f"""Bu bir Türkiye Yüzme Federasyonu (TYF) Splash Meet Manager START LİSTESİ (Başlangıç Listesi) PDF sayfasıdır.
Sayfa {page_num} / {total_pages}.

GÖREVLER:
{header_instruction}
2. Sayfada yer alan her bir seriyi ("Seri 1 of 31", "Seri 2 of 31" vb.) ve o serideki tüm sporcuları eksiksiz çıkar.
   Her sporcu için:
   - seri: Seri bilgisi (örn: "Seri 1 of 31" veya seri numarası tam sayı: 1)
   - kulvar: Kulvar numarası (1-8 arası tam sayı)
   - sporcu: Sporcunun tam adı ve soyadı (büyük harfleri koruyun, "(Fd)", "(Tk)", "(Td)" etiketlerini temizleyin)
   - dogum_yili: Doğum yılı (örn: "10" veya "2010")
   - kulup: Kulübünün tam adı ("(Fd)", "(Tk)", "(Td)" etiketlerini temizleyin)
   - giris_derecesi: Giriş derecesi (örn: "24.95", "1:02.40", "NT")

ŞU JSON ŞEMASINA KESİNLİKLE UY:
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
      "seri": string veya integer,
      "kulvar": integer,
      "sporcu": string,
      "dogum_yili": string,
      "kulup": string,
      "giris_derecesi": string
    }}
  ]
}}
SADECE JSON döndür. Başka hiçbir açıklama yazma.
"""

    def _get_result_list_page_prompt(self, page_num: int, total_pages: int, is_first_page: bool, startlist_swimmers: Optional[List[Dict[str, Any]]] = None) -> str:
        """Sonuç listesi için optimize edilmiş sayfa istemi."""
        header_instruction = ""
        if is_first_page:
            header_instruction = """
1. Belgenin başlığından müsabaka bilgilerini çıkar:
   - musabaka_adi: Müsabaka adı (örn: "13+ YAS UZUN KULVAR BARAJ GECME MUSABAKALARI")
   - sehir: Şehir (örn: "İSTANBUL")
   - tarih: Yarış tarihi YYYY-MM-DD formatında (örn: "2026-04-24")
   - yaris_no: Yarış numarası (örn: 2)
   - cinsiyet: "Erkek" veya "Kadın"
   - mesafe: Metre cinsinden mesafe (örn: 50)
   - stil: "Serbest", "Sırtüstü", "Kurbağalama", "Kelebek" veya "Karışık"
   - yas_grubu: "Açık", "13 yaş" vb.
"""
        else:
            header_instruction = "1. Bu devam sayfasıdır, başlık bilgisi boş bırakılabilir."

        swimmers_section = ""
        if startlist_swimmers:
            candidates = []
            for s in startlist_swimmers:
                candidates.append({
                    "id": s.get("id"),
                    "sporcu": s.get("sporcu_adi") or s.get("sporcu"),
                    "kulup": s.get("kulup_adi") or s.get("kulup"),
                    "dogum_yili": s.get("dogum_yili"),
                    "seri": s.get("seri"),
                    "kulvar": s.get("kulvar")
                })
            swimmers_section = f"""
BU YARIŞTA YÜZEN START LİSTESİNDEKİ SPORCULAR:
{json.dumps(candidates, ensure_ascii=False)}
Lütfen PDF'teki sonuçları yukarıdaki sporcularla eşleştirip onların "id" değerini "id" alanına yazın.
"""

        return f"""Bu bir Türkiye Yüzme Federasyonu (TYF) Splash Meet Manager SONUÇ LİSTESİ (Result List) PDF sayfasıdır.
Bu sayfa taranmış/resim olabilir. OCR ile dikkatlice oku.
Sayfa {page_num} / {total_pages}.
{swimmers_section}
GÖREVLER:
{header_instruction}
2. Sayfada yer alan tüm yarış sonuçlarını (sporcuları) eksiksiz çıkar.
   Her sporcu için:
   - id: Start listesindeki eşleşen sporcunun id değeri (yoksa null)
   - sira: Sıralama derecesi tam sayı (1, 2, 3...) veya diskalifiye/katılmadıysa null
   - sporcu: Sporcunun tam adı ve soyadı ("(Fd)", "(Tk)", "(Td)" etiketlerini temizleyin)
   - dogum_yili: Doğum yılı (örn: "10" veya "2010")
   - kulup: Kulübünün tam adı ("(Fd)", "(Tk)", "(Td)" etiketlerini temizleyin)
   - derece: Yüzülen derece (örn: "24.95", "1:02.40"). Diskalifiye ise "DSQ", yarışa girmediyse "DNS", terk ettiyse "DNF"
   - puan: FINA/World Aquatics puanı (tam sayı, örn: 586 veya null)
   - yas_grubu: Kategori veya yaş grubu başlığı (örn: "Açık", "13 yaş", "14 yaş")
   - diskalifiye: boolean (diskalifiye ise true, değilse false)
   - diskalifiye_nedeni: Varsa diskalifiye açıklaması (örn: "SW 4.4 - Hatalı çıkış...") veya null

ŞU JSON ŞEMASINA KESİNLİKLE UY:
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
      "sira": integer veya null,
      "sporcu": string,
      "dogum_yili": string,
      "kulup": string,
      "derece": string,
      "puan": integer veya null,
      "yas_grubu": string veya null,
      "diskalifiye": boolean,
      "diskalifiye_nedeni": string veya null
    }}
  ]
}}
SADECE JSON döndür. Başka hiçbir açıklama yazma.
"""

    def parse_pdf_bytes(self, pdf_bytes: bytes, doc_type: Optional[str] = None, hint: str = "", max_workers: int = 5, startlist_swimmers: Optional[List[Dict[str, Any]]] = None) -> Dict[str, Any]:
        """PDF baytlarını Gemini ile parse eder. Çok sayfalı belgeleri paralel thread havuzuyla çok hızlı tarar."""
        if not doc_type:
            doc_type = self.detect_document_type(pdf_bytes, hint)

        if not fitz:
            # PyMuPDF yoksa doğrudan tüm PDF'i gönder
            prompt = (
                self._get_start_list_page_prompt(1, 1, True)
                if doc_type == "start_listesi"
                else self._get_result_list_page_prompt(1, 1, True, startlist_swimmers=startlist_swimmers)
            )
            data = self._call_gemini_api(pdf_bytes, prompt)
            data["tur"] = doc_type
            self._post_process_records(data)
            return data

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

        print(f"[*] Toplam {total_pages} sayfa ayrıştırılıyor (Tür: {doc_type}, Model: {self.model}, Paralel: {min(max_workers, total_pages)} thread)...", flush=True)

        # Her sayfanın bağımsız PDF baytlarını hazırla
        pages_bytes = []
        for page_idx in range(total_pages):
            single_page_doc = fitz.open()
            single_page_doc.insert_pdf(doc, from_page=page_idx, to_page=page_idx)
            pages_bytes.append((page_idx, single_page_doc.tobytes()))
            single_page_doc.close()
        doc.close()

        def _process_page(args: Tuple[int, bytes]) -> Tuple[int, Dict[str, Any]]:
            page_idx, p_bytes = args
            page_num = page_idx + 1
            is_first = (page_idx == 0)
            prompt = (
                self._get_start_list_page_prompt(page_num, total_pages, is_first)
                if doc_type == "start_listesi"
                else self._get_result_list_page_prompt(page_num, total_pages, is_first, startlist_swimmers=startlist_swimmers)
            )
            t_start = time.time()
            try:
                page_data = self._call_gemini_api(p_bytes, prompt)
                rec_cnt = len(page_data.get("kayitlar", []))
                print(f"  [✓] Sayfa {page_num}/{total_pages} tamamlandı ({time.time()-t_start:.2f}s, {rec_cnt} kayıt)", flush=True)
                return page_idx, page_data
            except Exception as e:
                print(f"  [!] Sayfa {page_num} hatası ({time.time()-t_start:.2f}s): {e}", file=sys.stderr, flush=True)
                return page_idx, {}

        # Sayfaları paralel olarak Gemini API'ye gönder
        actual_workers = min(max_workers, total_pages)
        if actual_workers > 1:
            with ThreadPoolExecutor(max_workers=actual_workers) as executor:
                page_results = list(executor.map(_process_page, pages_bytes))
        else:
            page_results = [_process_page(p) for p in pages_bytes]

        # Sayfa sırasını korumak için sırala
        page_results.sort(key=lambda x: x[0])

        for page_idx, page_data in page_results:
            if not page_data:
                continue
            if page_idx == 0:
                for k in ["musabaka_adi", "sehir", "tarih", "yaris_no", "cinsiyet", "mesafe", "stil", "yas_grubu"]:
                    if page_data.get(k):
                        header_data[k] = page_data[k]

            page_records = page_data.get("kayitlar", [])
            header_data["kayitlar"].extend(page_records)

        self._post_process_records(header_data)
        return header_data

    def _post_process_records(self, data: Dict[str, Any]):
        """Kayıtları temizleme ve normalizasyon kuralları."""
        records = data.get("kayitlar", [])
        for r in records:
            if "sporcu" in r:
                r["sporcu"] = strip_markers(r["sporcu"])
            if "kulup" in r:
                r["kulup"] = strip_markers(r["kulup"])
            if "dogum_yili" in r:
                r["dogum_yili"] = normalize_birth_year(r["dogum_yili"])
            if "diskalifiye" in r and r.get("derece") == "DSQ":
                r["diskalifiye"] = True

    def parse_url(self, url: str, doc_type: Optional[str] = None) -> Dict[str, Any]:
        """Verilen canlı sonuç URL'sini indirip parse eder."""
        print(f"[*] URL indiriliyor: {url}")
        pdf_bytes = download_pdf_bytes(url)
        return self.parse_pdf_bytes(pdf_bytes, doc_type=doc_type, hint=url)

    def parse_file(self, file_path: str, doc_type: Optional[str] = None) -> Dict[str, Any]:
        """Yerel PDF dosyasını parse eder."""
        p = Path(file_path)
        with open(p, "rb") as f:
            pdf_bytes = f.read()
        return self.parse_pdf_bytes(pdf_bytes, doc_type=doc_type, hint=p.name)


def print_formatted_summary(data: Dict[str, Any], limit: int = 15):
    """Ayrıştırılan verileri terminalde okunabilir bir tablo olarak özetler."""
    tur = data.get("tur", "bilinmeyen")
    records = data.get("kayitlar", [])

    print("\n" + "=" * 70)
    print(f" MÜSABAKA BİLGİLERİ ({tur.upper()})")
    print("=" * 70)
    print(f" Müsabaka Adı : {data.get('musabaka_adi')}")
    print(f" Şehir / Tarih: {data.get('sehir')} | {data.get('tarih')}")
    print(f" Yarış No     : Yarış {data.get('yaris_no')}")
    print(f" Kategori     : {data.get('cinsiyet')} - {data.get('mesafe')}m {data.get('stil')} ({data.get('yas_grubu')})")
    print(f" Toplam Kayıt : {len(records)} sporcu")
    print("-" * 70)

    if not records:
        print(" (Hiç kayıt bulunamadı)")
        return

    if tur == "start_listesi":
        print(f"{'Seri':<10} {'Kulvar':<8} {'Sporcu Adı':<25} {'YB':<6} {'Kulüp':<25} {'Giriş Derecesi':<12}")
        print("-" * 90)
        for r in records[:limit]:
            seri = str(r.get("seri", ""))
            kulvar = str(r.get("kulvar", ""))
            sporcu = str(r.get("sporcu", ""))[:24]
            yb = str(r.get("dogum_yili", ""))
            kulup = str(r.get("kulup", ""))[:24]
            giris = str(r.get("giris_derecesi", ""))
            print(f"{seri:<10} {kulvar:<8} {sporcu:<25} {yb:<6} {kulup:<25} {giris:<12}")
    else:
        print(f"{'Sıra':<6} {'Sporcu Adı':<25} {'YB':<6} {'Kulüp':<25} {'Derece':<10} {'Puan':<8} {'Not'}")
        print("-" * 95)
        for r in records[:limit]:
            sira = str(r.get("sira") or "-")
            sporcu = str(r.get("sporcu", ""))[:24]
            yb = str(r.get("dogum_yili", ""))
            kulup = str(r.get("kulup", ""))[:24]
            derece = str(r.get("derece", ""))
            puan = str(r.get("puan") or "-")
            not_bilgisi = r.get("diskalifiye_nedeni") or ""
            print(f"{sira:<6} {sporcu:<25} {yb:<6} {kulup:<25} {derece:<10} {puan:<8} {not_bilgisi}")

    if len(records) > limit:
        print(f"... ve {len(records) - limit} kayıt daha (tamamı JSON çıktısında)")
    print("=" * 70 + "\n")


def main():
    parser = argparse.ArgumentParser(description="Gemini Flash Lite 1.5 TYF Canlı Sonuç Parser")
    parser.add_argument("source", nargs="?", help="URL veya yerel PDF dosya yolu")
    parser.add_argument("--api-key", default=None, help="Gemini API Anahtarı")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Model (Varsayılan: {DEFAULT_MODEL})")
    parser.add_argument("--type", choices=["start_listesi", "sonuc_listesi"], default=None, help="Belge türü")
    parser.add_argument("--out", default=None, help="JSON çıktı dosya yolu")
    args = parser.parse_args()

    if not args.source:
        parser.print_help()
        sys.exit(1)

    gemini_parser = GeminiLiveParser(api_key=args.api_key, model=args.model)

    if args.source.startswith("http://") or args.source.startswith("https://"):
        result = gemini_parser.parse_url(args.source, doc_type=args.type)
    else:
        result = gemini_parser.parse_file(args.source, doc_type=args.type)

    print_formatted_summary(result)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print(f"[✓] Sonuç kaydedildi: {args.out}")


if __name__ == "__main__":
    main()

