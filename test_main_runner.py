#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test Runner for google_cloud_runner/main.py
-------------------------------------------
Bu betik sunucuda veya yerelde main.py'nin tüm temel yeteneklerini test eder:
1. API Anahtarları ve Model yapılandırması
2. Gemini 1 & 2 ve Groq bağlantı kontrolü
3. Maskeli sporcu eşleştirme algoritması (Özdemir, Kalaycı vb.)
4. Canlı PDF indirme ve ayrıştırma (StartList / ResultList)
"""

import os
import sys
from pathlib import Path

# UTF-8 stdout
if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Path setup
BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR))
sys.path.insert(0, str(BASE_DIR / "google_cloud_runner"))

import main
from google import genai
from google.genai import types

print("=" * 70)
print("  GOOGLE CLOUD RUNNER / MAIN.PY TEST BAŞLATILIYOR")
print("=" * 70)

# 1. Ortam Kontrolü
print("\n[1] ORTAM & YAPILANDIRMA KONTROLÜ:")
print(f"  - Kullanılan Model : {main.DEFAULT_MODEL}")
print(f"  - 1. Gemini Key    : {'[MEVCUT]' if os.getenv('GEMINI_API_KEY') else '[EKSİK!]'}")
print(f"  - 2. Gemini Key    : {'[MEVCUT]' if os.getenv('GEMINI_API_KEY_2') else '[TANIMLANMAMIŞ]'}")
print(f"  - Groq Key         : {'[MEVCUT]' if os.getenv('GROQ_API_KEY') else '[EKSİK!]'}")

# 2. Gemini & Fallback Testi
print("\n[2] LLM API ÇAĞRISI TESTİ:")
gemini_key = os.getenv("GEMINI_API_KEY")
if gemini_key:
    try:
        client = genai.Client(api_key=gemini_key)
        res = main.generate_content_with_fallback(
            primary_client=client,
            model=main.DEFAULT_MODEL,
            contents=["1 kelimelik yanıt ver: 'HAZIR'"],
            config=None,
        )
        print(f"  [+] API Yanıtı Başarılı: {res.text.strip()}")
    except Exception as e:
        print(f"  [-] API Çağrı Hatası: {e}")
else:
    print("  [-] GEMINI_API_KEY bulunamadığı için API testi atlandı.")

# 3. Maskeli Sporcu Çözümleme Testi (Yerel Algoritma)
print("\n[3] MASKELİ SPORCU EŞLEŞTİRME TESTİ:")
sample_candidates = [
    {"id": 100, "sporcu": "Beren ÖZDEM", "dogum_yili": 2014, "kulup": "Dört Mevsim Spor Kulübü"},
    {"id": 101, "sporcu": "Beren ÇALIK", "dogum_yili": 2014, "kulup": "Heybeliada Su Sporları"},
    {"id": 102, "sporcu": "Beren DUTAR", "dogum_yili": 2014, "kulup": "FMV Işık"},
]
match_res = main.resolve_masked_athlete(
    masked_name="Beren Ö**em*r",
    candidates=sample_candidates,
    birth_year=2014,
    club="Dört Mevsim Spor Kulübü",
)
best_cand = match_res.get("adaylar", [{}])[0] if match_res.get("adaylar") else {}
print(f"  - Hedef: 'Beren Ö**em*r' (2014, Dört Mevsim)")
print(f"  [+] Eşleşen ID: {best_cand.get('id')} | İsim: {best_cand.get('sporcu')} | Skor: {best_cand.get('skor')} | Durum: {match_res.get('durum')}")

# 4. PDF İndirme & Ayrıştırma Testi
print("\n[4] PDF AYRIŞTIRMA TESTİ:")
sample_pdf_url = "https://canli.tyf.gov.tr/istanbul/cs-1005380/canli/StartList_1.pdf"
print(f"  - Test PDF: {sample_pdf_url}")
try:
    pdf_bytes = main.download_bytes(sample_pdf_url)
    print(f"  [+] PDF başarıyla indirildi ({len(pdf_bytes)} bayt).")
    
    if gemini_key:
        print(f"  - Sayfa ayrıştırılıyor ({main.DEFAULT_MODEL})...")
        parsed = main.parse_meet_pdf(
            pdf_bytes=pdf_bytes,
            client=client,
            pdf_url=sample_pdf_url,
            model=main.DEFAULT_MODEL,
        )
        kayitlar = parsed.get("kayitlar", [])
        print(f"  [+] Başarılı! Toplam {len(kayitlar)} sporcu kaydı çıkarıldı.")
        if kayitlar:
            k1 = kayitlar[0]
            print(f"      Örnek 1. Kayıt: Seri {k1.get('seri')} Kulvar {k1.get('kulvar')} - {k1.get('sporcu')} ({k1.get('kulup')})")
except Exception as e:
    print(f"  [-] PDF Test Hatası: {e}")

print("\n" + "=" * 70)
print("  TEST TAMAMLANDI!")
print("=" * 70)
