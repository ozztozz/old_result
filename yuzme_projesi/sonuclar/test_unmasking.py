# -*- coding: utf-8 -*-
"""
test_unmasking.py
=================
Start listesindeki sporcuların yerel veritabanı üzerinden unmasking (maske kaldırma / sporcu eşleme) testi.
"""

import os
import sys

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(CURRENT_DIR)
if PROJECT_DIR not in sys.path:
    sys.path.insert(0, PROJECT_DIR)

import django
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "yuzme_projesi.settings")
django.setup()

from sonuclar.local_startlist_parser import parse_startlist_pdf
from sonuclar.athlete_matcher import match_athlete

def run_test(pdf_path: str = r"C:\Users\OZDEN\Desktop\StartList_1080.pdf"):
    print("=" * 75)
    print("START LISTESI UNMASKING TESTİ BAŞLATILIYOR...")
    print(f"Hedef PDF: {pdf_path}")
    print("=" * 75)

    data = parse_startlist_pdf(pdf_path)
    swimmers = data["sporcular"]
    gender = data.get("cinsiyet")

    print(f"Yarış: {data.get('yaris')}")
    print(f"Toplam Sporcu: {len(swimmers)}")
    print("-" * 75)

    matched = []
    unmatched = []

    for s in swimmers:
        match_res = match_athlete(
            name=s["sporcu"],
            birth_year_or_date=s["dogum_yili"],
            club=s["kulup"],
            gender=gender
        )
        is_exact = (match_res.get("sonuc") == "tam_eslesme")
        solved_name = match_res.get("sporcu", {}).get("sporcu_adi") if is_exact else None
        
        info = {
            "seri": s["seri"],
            "kulvar": s["kulvar"],
            "maskeli": s["sporcu"],
            "d_yili": s["dogum_yili"],
            "kulup": s["kulup"],
            "cozulen": solved_name,
            "sonuc": match_res.get("sonuc"),
            "muhtemel": [m.get("sporcu_adi") for m in match_res.get("muhtemel_eslesmeler", [])[:3]],
            "sporcu_id": match_res.get("bulunan_id")
        }

        if is_exact:
            matched.append(info)
        else:
            unmatched.append(info)

    print(f"\n[+] BAŞARIYLA ÇÖZÜLEN (Tam Eşleşme) : {len(matched)} / {len(swimmers)} (%{len(matched)/len(swimmers)*100:.1f})")
    print(f"[-] ÇÖZÜLEMEYEN VEYA ÇOKLU ADAY      : {len(unmatched)} / {len(swimmers)}\n")

    print("=" * 75)
    print(f"{'SERİ':<10} {'KUL':<4} {'D.YILI':<7} {'MASKELİ İSİM':<30} -> {'ÇÖZÜLEN SPORCU ADI'}")
    print("=" * 75)
    for item in matched:
        print(f"{item['seri']:<10} K{item['kulvar']:<3} {item['d_yili']:<7} {item['maskeli']:<30} -> {item['cozulen']}")

    if unmatched:
        print("\n" + "=" * 75)
        print("ÇÖZÜLEMEYEN VEYA ÇOKLU ADAY KALAN SPORCULAR:")
        print("=" * 75)
        for item in unmatched:
            muht = ", ".join(item["muhtemel"]) if item["muhtemel"] else "Aday yok"
            print(f"{item['seri']:<10} K{item['kulvar']:<3} {item['d_yili']:<7} {item['maskeli']:<30} | Durum: {item['sonuc']} | Adaylar: {muht}")

if __name__ == "__main__":
    pdf_file = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\OZDEN\Desktop\StartList_1080.pdf"
    run_test(pdf_file)
