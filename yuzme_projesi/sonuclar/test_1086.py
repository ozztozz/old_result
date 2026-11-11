# -*- coding: utf-8 -*-
"""
test_1086.py
============
StartList_1086.pdf ve ResultList_1086.pdf (Erkekler 200m Karışık) test betiği.
"""

import os
import sys
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(CURRENT_DIR)
if PROJECT_DIR not in sys.path:
    sys.path.insert(0, PROJECT_DIR)

import django
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "yuzme_projesi.settings")
django.setup()

from sonuclar.local_startlist_parser import LocalStartListParser
from sonuclar.local_resultlist_parser import LocalResultListParser
from sonuclar.athlete_matcher import match_athlete

START_URL = "https://canli.tyf.gov.tr/live/2026/1005845/StartList_1086.pdf?v=1794223206"
RESULT_URL = "https://canli.tyf.gov.tr/live/2026/1005845/ResultList_1086.pdf?v=1794224907"

headers = {"User-Agent": "Mozilla/5.0"}

def main():
    print("=" * 80)
    print("1. START LISTESI AYRIŞTIRMA (StartList_1086.pdf)")
    print("URL:", START_URL)
    print("=" * 80)

    r_start = requests.get(START_URL, headers=headers, verify=False, timeout=15)
    start_parser = LocalStartListParser()
    start_data = start_parser.parse(r_start.content)

    print(f"Müsabaka    : {start_data['musabaka_adi']}")
    print(f"Tarih       : {start_data['tarih']}")
    print(f"Yarış       : {start_data['yaris']}")
    print(f"Toplam Seri : {start_data['toplam_seri']}")
    print(f"Toplam Sporcu: {start_data['toplam_sporcu']}")
    print("-" * 80)

    # Start listesi unmasking
    start_unmasked_map = {}  # key: (seri_no, kulvar) -> athlete info
    matched_count = 0

    for s in start_data["sporcular"]:
        # extract seri no from string 'Seri 1/4' -> 1
        seri_no = int(s["seri"].split()[1].split("/")[0]) if s["seri"] else 1
        kulvar = s["kulvar"]

        m = match_athlete(
            name=s["sporcu"],
            birth_year_or_date=s["dogum_yili"],
            club=s["kulup"],
            gender=start_data["cinsiyet"]
        )
        is_exact = (m.get("sonuc") == "tam_eslesme")
        solved_name = m.get("sporcu", {}).get("sporcu_adi") if is_exact else None
        if is_exact:
            matched_count += 1

        start_unmasked_map[(seri_no, kulvar)] = {
            "maskeli": s["sporcu"],
            "cozulen": solved_name,
            "d_yili": s["dogum_yili"],
            "kulup": s["kulup"],
            "giris": s["giris_derecesi"]
        }

    for seri_name, swimmers in start_data["seriler"].items():
        print(f"\n--- {seri_name} ({len(swimmers)} Sporcu) ---")
        for s in swimmers:
            seri_no = int(s["seri"].split()[1].split("/")[0]) if s["seri"] else 1
            info = start_unmasked_map.get((seri_no, s["kulvar"]), {})
            coz = f"-> {info['cozulen']}" if info.get("cozulen") else ""
            print(f"  Kulvar {s['kulvar']:2d} | {s['sporcu']:30s} | {s['dogum_yili'] or '----'} | {s['giris_derecesi'] or '--:--'} | {coz}")

    print(f"\n[+] Start Listesi Unmasking Başarısı: {matched_count}/{len(start_data['sporcular'])} (%{matched_count/len(start_data['sporcular'])*100:.1f})")

    print("\n" + "=" * 80)
    print("2. SONUÇ LİSTESİ AYRIŞTIRMA (ResultList_1086.pdf)")
    print("URL:", RESULT_URL)
    print("=" * 80)

    r_res = requests.get(RESULT_URL, headers=headers, verify=False, timeout=15)
    result_parser = LocalResultListParser()
    result_data = result_parser.parse(r_res.content, unmask=False)

    print(f"Müsabaka    : {result_data['musabaka_adi']}")
    print(f"Tarih       : {result_data['tarih']}")
    print(f"Yarış       : {result_data['yaris']}")
    print(f"Toplam Sayfa: {result_data['toplam_sayfa']}")
    print(f"Toplam Sonuç: {result_data['toplam_sonuc']} (Derece Alan: {result_data['derece_alanlar']}, DSQ/DNS: {result_data['dsq_dns_sayisi']})")
    print("-" * 80)

    print(f"{'SIRA':<5} {'K/S':<8} {'D.YILI':<7} {'DERECE':<9} {'MASKELİ SPORCU':<28} {'ÇÖZÜLEN SPORCU (StartList Çapraz)':<30}")
    print("-" * 80)

    for item in result_data["sonuclar"]:
        sira_str = f"{item['sira']:2d}." if item['sira'] is not None else f"[{item['durum']}]"
        ks_str = f"K{item['kulvar']}/S{item['seri']}" if item['kulvar'] and item['seri'] else "   -   "
        dy = item['dogum_yili'] or "----"
        derece = item['derece'] or "--:--"
        sporcu = item['sporcu']

        # Çapraz eşleme: Start listesindeki (seri, kulvar) üzerinden gerçek sporcuyu çek
        cross_match = start_unmasked_map.get((item['seri'], item['kulvar'])) if item['kulvar'] and item['seri'] else None
        cozulen = cross_match['cozulen'] if cross_match and cross_match.get('cozulen') else ""
        if not cozulen and cross_match:
            cozulen = f"(Maske: {cross_match['maskeli']})"

        print(f"{sira_str:<5} {ks_str:<8} {dy:<7} {derece:<9} {sporcu:<28} {cozulen:<30}")

    if result_data["dsq_dns_sayisi"] > 0:
        print("\n--- Diskalifiye / Özel Durumlar ---")
        for item in [s for s in result_data["sonuclar"] if s["durum"] != "OK"]:
            print(f"[{item['durum']}] {item['sporcu']} (Not: {item['notlar']})")

if __name__ == "__main__":
    main()
