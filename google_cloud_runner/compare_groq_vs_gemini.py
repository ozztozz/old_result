"""
Benchmark and Comparison: Groq API vs Gemini & Heuristic Matching
------------------------------------------------------------------
1. Maskeli Sporcu Cozumleme Karsilastirmasi (Algoritmik Matcher vs Groq LLM)
2. PDF Ayristirma Karsilastirmasi (Gemini Flash Lite Multimodal vs PyMuPDF + Groq LLM)
"""

import os
import sys
import time
import json
import urllib.request
from pathlib import Path

# UTF-8 stdout
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Load environment
base_dir = Path(__file__).resolve().parent
dotenv_path = base_dir.parent / ".env"
env_vars = {}
if dotenv_path.exists():
    for line in dotenv_path.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.split("=", 1)
            env_vars[k.strip()] = v.strip().strip("'\"")

GROQ_API_KEY = env_vars.get("GROQ_API_KEY") or os.environ.get("GROQ_API_KEY")
GEMINI_API_KEY = env_vars.get("GEMINI_API_KEY") or os.environ.get("GEMINI_API_KEY")
GROQ_MODEL = env_vars.get("GROQ_MODEL", "openai/gpt-oss-120b")

# Import main.py components
sys.path.insert(0, str(base_dir))
import fitz
from google import genai
from google.genai import types
from main import (
    resolve_masked_athlete,
    DEFAULT_MODEL,
    generate_content_with_fallback,
)


def call_groq_chat(messages, model=GROQ_MODEL, temperature=0.1, response_format=None, timeout=30):
    """Groq API chat completion via urllib (no dependency required)."""
    headers = {
        "Authorization": f"Bearer {GROQ_API_KEY}",
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    }
    payload = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
    }
    if response_format:
        payload["response_format"] = response_format

    req = urllib.request.Request(
        "https://api.groq.com/openai/v1/chat/completions",
        headers=headers,
        data=json.dumps(payload).encode("utf-8"),
    )
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        duration_ms = (time.perf_counter() - t0) * 1000.0
        data = json.loads(resp.read().decode("utf-8"))
        content = data["choices"][0]["message"]["content"]
        usage = data.get("usage", {})
        return {
            "content": content,
            "duration_ms": duration_ms,
            "usage": usage,
        }


def benchmark_athlete_matching():
    print("=" * 80)
    print("  BÖLÜM 1: MASKELİ SPORCU EŞLEŞTİRME KARŞILAŞTIRMASI")
    print(f"  Mevcut Algoritma vs Groq LLM ({GROQ_MODEL})")
    print("=" * 80)

    test_cases = [
        {
            "name": "Vaka 1: Kök Kelime ve Harf Farkı (ÖZDEM vs Ö**EM*R)",
            "masked_name": "Beren Ö**em*r",
            "birth_year": 2014,
            "club": "Dört Mevsim Spor Kulübü",
            "expected_id": 100,
            "candidates": [
                {"id": 100, "sporcu": "Beren ÖZDEM", "dogum_yili": 2014, "kulup": "Dört Mevsim Spor Kulübü"},
                {"id": 101, "sporcu": "Beren ÇALIK", "dogum_yili": 2014, "kulup": "Heybeliada Su Sporları Kulübü"},
                {"id": 102, "sporcu": "Beren DUTAR", "dogum_yili": 2014, "kulup": "Fmv Işık Spor Kulübü"},
                {"id": 103, "sporcu": "Beren TOSUN", "dogum_yili": 2014, "kulup": "İleri Nesil Spor Kulübü"},
                {"id": 104, "sporcu": "Beren KURTULUŞ", "dogum_yili": 2014, "kulup": "Eyüpsultan Belediyesi Spor Kulübü"},
            ]
        },
        {
            "name": "Vaka 2: Gömülü Maskeleme ve OCR Harf Düşmesi (*lyc* in KALAYCI)",
            "masked_name": "Ala Beren *lyc*",
            "birth_year": 2015,
            "club": "Galatasaray Spor Kulübü",
            "expected_id": 200,
            "candidates": [
                {"id": 200, "sporcu": "Alya Beren KALAYCI", "dogum_yili": 2015, "kulup": "Galatasaray Spor Kulübü"},
                {"id": 201, "sporcu": "Ada Beren AĞAL", "dogum_yili": 2015, "kulup": "FERDİ"},
                {"id": 202, "sporcu": "Ayşe Beren OKAN", "dogum_yili": 2014, "kulup": "Heybeliada Su Sporları"},
                {"id": 203, "sporcu": "Beren Su YILDIRIM", "dogum_yili": 2015, "kulup": "Boğaziçi Yüzme Ve Cimnastik"},
            ]
        },
        {
            "name": "Vaka 3: Ön Ek Joker ve Tek Harf Düşmesi (Eif Beren ***irel)",
            "masked_name": "Eif Beren ***irel",
            "birth_year": 2014,
            "club": "Anabilim Spor Kulübü",
            "expected_id": 300,
            "candidates": [
                {"id": 300, "sporcu": "Elif Beren DEMİREL", "dogum_yili": 2014, "kulup": "Anabilim Spor Kulübü"},
                {"id": 301, "sporcu": "Elif Beren KOBYAOĞLU", "dogum_yili": 2014, "kulup": "Bahçelievler Belediye Spor"},
                {"id": 302, "sporcu": "Beren DİLBAZ", "dogum_yili": 2016, "kulup": "İtü Geliştirme Vakfı"},
                {"id": 303, "sporcu": "İlke Beren TUNA", "dogum_yili": 2015, "kulup": "Galaksi Spor Kulübü"},
            ]
        },
        {
            "name": "Vaka 4: OCR 'l' Harfi Düşmesi ve Kısmi Soyad (Ası Beren K**)",
            "masked_name": "Ası Beren K**",
            "birth_year": 2015,
            "club": "Okyanus Koleji Spor Kulübü",
            "expected_id": 400,
            "candidates": [
                {"id": 400, "sporcu": "Aslı Beren KOLCU", "dogum_yili": 2015, "kulup": "Okyanus Koleji Spor Kulübü"},
                {"id": 401, "sporcu": "Ada Beren AĞAL", "dogum_yili": 2015, "kulup": "FERDİ"},
                {"id": 402, "sporcu": "Alya Beren GÜNAY", "dogum_yili": 2016, "kulup": "Okyanus Koleji Spor Kulübü"},
                {"id": 403, "sporcu": "Beren Hatice ÖZKAN", "dogum_yili": 2013, "kulup": "Anabilim Spor Kulübü"},
            ]
        }
    ]

    for tc in test_cases:
        print(f"\n--- {tc['name']} ---")
        print(f"Maskeli Ad : '{tc['masked_name']}' | Doğum Yılı: {tc['birth_year']} | Kulüp: {tc['club']}")

        # 1. Algoritmik Çözücü
        t_algo_start = time.perf_counter()
        algo_res = resolve_masked_athlete(
            masked_name=tc["masked_name"],
            candidates=tc["candidates"],
            birth_year=tc["birth_year"],
            club=tc["club"],
        )
        t_algo_ms = (time.perf_counter() - t_algo_start) * 1000.0

        algo_durum = algo_res.get("durum")
        algo_secilen = algo_res.get("adaylar", [{}])[0] if algo_res.get("adaylar") else {}
        algo_id = algo_secilen.get("id")
        algo_score = algo_secilen.get("skor", 0.0)
        algo_correct = (algo_id == tc["expected_id"])

        # 2. Groq LLM Çözücü
        system_prompt = (
            "Sen Türk yüzme yarışlarındaki maskeli sporcu adlarını (KVKK maskeleri, OCR yazım hataları) "
            "verilen aday listesindeki en uygun sporcu ile eşleştiren bir uzmansın. "
            "OCR tarama kaynaklı harf düşmelerini (örn: 'Elif' -> 'Eif', 'Aslı' -> 'Ası') ve soyadı maskelerini dikkate al. "
            "Yanıtını SADECE şu JSON formatında ver:\n"
            "{\"secilen_id\": <int veya null>, \"guven_skoru\": <0-100 arasi>, \"neden\": \"<kisa aciklama>\"}"
        )
        user_prompt = (
            f"Hedef Maskeli Sporcu: {tc['masked_name']}\n"
            f"Doğum Yılı: {tc['birth_year']}\n"
            f"Kulüp: {tc['club']}\n\n"
            f"Aday Sporcular:\n{json.dumps(tc['candidates'], ensure_ascii=False, indent=2)}\n\n"
            "En uygun adayın 'id' değerini belirle."
        )

        groq_resp = call_groq_chat(
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            response_format={"type": "json_object"},
            temperature=0.0,
        )
        t_groq_ms = groq_resp["duration_ms"]
        groq_correct = False
        groq_id = None
        groq_score = 0
        groq_why = ""
        try:
            parsed = json.loads(groq_resp["content"])
            groq_id = parsed.get("secilen_id")
            groq_score = parsed.get("guven_skoru")
            groq_why = parsed.get("neden")
            groq_correct = (groq_id == tc["expected_id"])
        except Exception as e:
            groq_why = f"JSON parse error: {e}"

        # Sonuç Yazdır
        print(f"  [Algoritma] Süre: {t_algo_ms:6.2f} ms | Seçilen ID: {algo_id} | Skor: {algo_score:5.1f} | Durum: {algo_durum} | Doğru mu: {'✓' if algo_correct else '✗'}")
        score_str = f"{groq_score:5.1f}" if isinstance(groq_score, (int, float)) else str(groq_score)
        print(f"  [Groq LLM ] Süre: {t_groq_ms:6.2f} ms | Seçilen ID: {groq_id} | Skor: {score_str} | Neden : {groq_why} | Doğru mu: {'✓' if groq_correct else '✗'}")


def benchmark_pdf_parsing():
    print("\n" + "=" * 80)
    print("  BÖLÜM 2: PDF AYRIŞTIRMA KARŞILAŞTIRMASI")
    print(f"  Gemini Flash Lite (Multimodal PDF) vs Groq LLM (PyMuPDF Text + {GROQ_MODEL})")
    print("=" * 80)

    pdf_path = base_dir.parent / "scratch" / "StartList_1.pdf"
    if not pdf_path.exists():
        print(f"Hata: {pdf_path} bulunamadı!")
        return

    pdf_bytes = pdf_path.read_bytes()
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    print(f"PDF Dosyası: {pdf_path.name} | Toplam Sayfa: {len(doc)} | Test Sayfası: Sayfa 1")

    # Sayfa 1 baytları (Gemini için tek sayfa PDF)
    single_doc = fitz.open()
    single_doc.insert_pdf(doc, from_page=0, to_page=0)
    page1_pdf_bytes = single_doc.tobytes()
    single_doc.close()

    # Sayfa 1 metni (Groq için)
    page1_text = doc[0].get_text("text")
    doc.close()

    prompt_schema = """Format:
{
  "musabaka_adi": string veya null,
  "sehir": string veya null,
  "tarih": string veya null,
  "yaris_no": integer veya null,
  "cinsiyet": string veya null,
  "mesafe": integer veya null,
  "stil": string veya null,
  "yas_grubu": string veya null,
  "kayitlar": [
    {
      "seri": string,
      "kulvar": integer,
      "sporcu": string,
      "dogum_yili": string,
      "kulup": string,
      "giris_derecesi": string
    }
  ]
}
SADECE JSON döndür."""

    # 1. Gemini Testi
    print("\n1. Gemini Flash Lite (Multimodal PDF) Çalıştırılıyor...")
    gemini_client = genai.Client(api_key=GEMINI_API_KEY)
    gemini_part = types.Part.from_bytes(data=page1_pdf_bytes, mime_type="application/pdf")
    gemini_prompt = (
        "Bu bir TYF Splash Meet Manager START LİSTESİ PDF sayfasıdır. Sayfa 1/1.\n"
        "1. Başlıktan müsabaka_adı, şehir, tarih (YYYY-MM-DD), yarış_no, cinsiyet, mesafe, stil ve yaş_grubu çıkar.\n"
        "2. Sayfadaki her seriyi ve her kulvardaki sporcuları eksiksiz çıkar.\n"
        + prompt_schema
    )

    t_gemini_start = time.perf_counter()
    try:
        gemini_res = generate_content_with_fallback(
            primary_client=gemini_client,
            model=DEFAULT_MODEL,
            contents=[gemini_part, gemini_prompt],
            config=types.GenerateContentConfig(response_mime_type="application/json", temperature=0.1),
        )
        t_gemini_ms = (time.perf_counter() - t_gemini_start) * 1000.0
        gemini_raw = (gemini_res.text or "").strip()
        gemini_json = json.loads(gemini_raw)
        gemini_kayitlar = gemini_json.get("kayitlar", [])
        gemini_success = True
        print(f"  ✓ Gemini Başarılı: {len(gemini_kayitlar)} sporcu kaydı çıkarıldı.")
        print(f"  Süre: {t_gemini_ms:6.2f} ms ({t_gemini_ms/1000.0:.2f} saniye)")
    except Exception as e:
        gemini_success = False
        t_gemini_ms = (time.perf_counter() - t_gemini_start) * 1000.0
        print(f"  ✗ Gemini Hatası: {e}")
        gemini_kayitlar = []

    # 2. Groq Testi
    print("\n2. Groq LLM (PyMuPDF Text + JSON Parsing) Çalıştırılıyor...")
    groq_messages = [
        {
            "role": "system",
            "content": (
                "Sen TYF yüzme yarış listelerini ayrıştıran uzman bir veri çıkarıcısısın. "
                "Verilen metinden başlık ve tüm seri/kulvar sporcu kayıtlarını eksiksiz çıkar.\n"
                + prompt_schema
            ),
        },
        {
            "role": "user",
            "content": f"Aşağıdaki TYF Start Listesi metnini JSON olarak yapılandır:\n\n{page1_text}",
        },
    ]

    t_groq_start = time.perf_counter()
    try:
        groq_res = call_groq_chat(
            messages=groq_messages,
            model=GROQ_MODEL,
            response_format={"type": "json_object"},
            temperature=0.1,
            timeout=40,
        )
        t_groq_ms = groq_res["duration_ms"]
        groq_json = json.loads(groq_res["content"])
        groq_kayitlar = groq_json.get("kayitlar", [])
        groq_success = True
        print(f"  ✓ Groq Başarılı: {len(groq_kayitlar)} sporcu kaydı çıkarıldı.")
        print(f"  Süre: {t_groq_ms:6.2f} ms ({t_groq_ms/1000.0:.2f} saniye)")
        print(f"  Token Kullanımı: {groq_res['usage'].get('total_tokens', 'N/A')} token (Giriş: {groq_res['usage'].get('prompt_tokens')}, Çıkış: {groq_res['usage'].get('completion_tokens')})")
    except Exception as e:
        groq_success = False
        t_groq_ms = (time.perf_counter() - t_groq_start) * 1000.0
        print(f"  ✗ Groq Hatası: {e}")
        groq_kayitlar = []

    # Karşılaştırma Özeti
    print("\n" + "-" * 80)
    print("  ÖZET KARŞILAŞTIRMA:")
    print(f"  Gemini Flash Lite : {len(gemini_kayitlar):2d} kayıt | Süre: {t_gemini_ms/1000.0:5.2f} sn | Yöntem: Native PDF Vision")
    print(f"  Groq ({GROQ_MODEL}) : {len(groq_kayitlar):2d} kayıt | Süre: {t_groq_ms/1000.0:5.2f} sn | Yöntem: PyMuPDF Metin + LLM")
    if t_gemini_ms > 0 and t_groq_ms > 0:
        ratio = t_gemini_ms / t_groq_ms
        if ratio > 1:
            print(f"  => Groq, Gemini'den {ratio:.1f} kat daha HIZLI tamamladı!")
        else:
            print(f"  => Gemini, Groq'tan {1/ratio:.1f} kat daha HIZLI tamamladı!")

    # Örnek ilk 3 sporcu kaydı karşılaştırması
    print("\n  İlk 3 Kayıt Karşılaştırması:")
    for idx in range(min(3, max(len(gemini_kayitlar), len(groq_kayitlar)))):
        g_row = gemini_kayitlar[idx] if idx < len(gemini_kayitlar) else {}
        q_row = groq_kayitlar[idx] if idx < len(groq_kayitlar) else {}
        print(f"  [{idx+1}] Gemini: {g_row.get('seri')} - {g_row.get('kulvar')} | {g_row.get('sporcu')} | {g_row.get('kulup')} | {g_row.get('giris_derecesi')}")
        print(f"      Groq  : {q_row.get('seri')} - {q_row.get('kulvar')} | {q_row.get('sporcu')} | {q_row.get('kulup')} | {q_row.get('giris_derecesi')}")


if __name__ == "__main__":
    benchmark_athlete_matching()
    benchmark_pdf_parsing()
