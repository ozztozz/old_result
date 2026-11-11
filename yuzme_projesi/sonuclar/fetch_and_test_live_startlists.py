# -*- coding: utf-8 -*-
"""
fetch_and_test_live_startlists.py
=================================
TYF Canlı sonuç sayfasındaki (örn: https://canli.tyf.gov.tr/live/2026/1005845/)
tüm Start Listesi PDF'lerini indirir, yerel parser ile parse eder ve
veritabanındaki sporcularla unmasking testini gerçekleştirir.
"""

import os
import sys
import re
import urllib3
from urllib.parse import urljoin
from typing import List, Dict, Any

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(CURRENT_DIR)
if PROJECT_DIR not in sys.path:
    sys.path.insert(0, PROJECT_DIR)

import django
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "yuzme_projesi.settings")
django.setup()

import requests
from bs4 import BeautifulSoup
from sonuclar.local_startlist_parser import LocalStartListParser
from sonuclar.athlete_matcher import match_athlete

LIVE_URL = "https://canli.tyf.gov.tr/live/2026/1005845/"

def get_startlist_links(base_url: str = LIVE_URL) -> List[Dict[str, str]]:
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    resp = requests.get(base_url, headers=headers, verify=False, timeout=15)
    resp.encoding = "utf-8"
    soup = BeautifulSoup(resp.text, "html.parser")

    items = []
    seen = set()

    # tr veya link bazlı tespit
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if "StartList" in href:
            clean_href = href.split("?")[0]
            if clean_href in seen:
                continue
            seen.add(clean_href)

            full_url = urljoin(base_url, href)
            # tr üst düğümünden yarış bilgilerini topla
            tr = a.find_parent("tr")
            event_name = ""
            if tr:
                cols = [td.get_text(strip=True) for td in tr.find_all(["td", "th"])]
                event_name = " | ".join([c for c in cols if c and c not in ["Start List.", "Sonuçlar"]])

            items.append({
                "pdf_name": os.path.basename(clean_href),
                "url": full_url,
                "event_hint": event_name
            })

    return items


def test_live_startlists(max_pdf: int = 5):
    links = get_startlist_links()
    print("=" * 80)
    print(f"TYF CANLI SAYFASI: {LIVE_URL}")
    print(f"Toplam Tespit Edilen Start Listesi Sayısı: {len(links)}")
    print(f"Test Edilecek PDF Sayısı (İlk): {max_pdf if max_pdf > 0 else len(links)}")
    print("=" * 80)

    parser = LocalStartListParser()
    headers = {"User-Agent": "Mozilla/5.0"}

    total_all_swimmers = 0
    total_all_matched = 0

    to_test = links[:max_pdf] if max_pdf > 0 else links

    for idx, item in enumerate(to_test, 1):
        pdf_name = item["pdf_name"]
        url = item["url"]
        hint = item["event_hint"]

        print(f"\n[{idx}/{len(to_test)}] İndiriliyor: {pdf_name} ({hint})")
        try:
            r = requests.get(url, headers=headers, verify=False, timeout=15)
            if r.status_code != 200:
                print(f"  [HATA] HTTP {r.status_code}")
                continue

            parsed = parser.parse(r.content)
            yaris = parsed.get("yaris") or hint
            gender = parsed.get("cinsiyet")
            swimmers = parsed.get("sporcular", [])
            total_seri = parsed.get("toplam_seri", 0)

            print(f"  -> Parse Başarılı: {yaris} | {parsed.get('toplam_sayfa')} Sayfa | {total_seri} Seri | {len(swimmers)} Sporcu")

            # Unmasking Testi
            matched_here = 0
            unmatched_here = 0
            sample_matches = []
            sample_unmatched = []

            for s in swimmers:
                m = match_athlete(
                    name=s["sporcu"],
                    birth_year_or_date=s["dogum_yili"],
                    club=s["kulup"],
                    gender=gender
                )
                is_exact = (m.get("sonuc") == "tam_eslesme")
                if is_exact:
                    matched_here += 1
                    if len(sample_matches) < 3:
                        sample_matches.append((s["kulvar"], s["seri"], s["sporcu"], s["dogum_yili"], m["sporcu"]["sporcu_adi"]))
                else:
                    unmatched_here += 1
                    if len(sample_unmatched) < 2:
                        sample_unmatched.append((s["kulvar"], s["seri"], s["sporcu"], s["dogum_yili"], m.get("sonuc")))

            total_all_swimmers += len(swimmers)
            total_all_matched += matched_here

            ratio = (matched_here / len(swimmers) * 100) if swimmers else 0
            print(f"  -> Unmasking: {matched_here}/{len(swimmers)} Başarılı (%{ratio:.1f})")

            if sample_matches:
                print("     Örnek Çözülenler:")
                for kul, ser, mask, yr, real in sample_matches:
                    print(f"       * {ser} K{kul} ({yr}): {mask} -> {real}")

            if sample_unmatched:
                print("     Örnek Çözülemeyen:")
                for kul, ser, mask, yr, st in sample_unmatched:
                    print(f"       * {ser} K{kul} ({yr}): {mask} [{st}]")

        except Exception as e:
            print(f"  [!] HATA: {e}")

    print("\n" + "=" * 80)
    print("GENEL TEST ÖZETİ:")
    print(f"İncelenen PDF Sayısı     : {len(to_test)}")
    print(f"Toplam Ayrıştırılan Sporcu: {total_all_swimmers}")
    print(f"Toplam Başarıyla Çözülen : {total_all_matched} (%{(total_all_matched/total_all_swimmers*100) if total_all_swimmers else 0:.1f})")
    print("=" * 80)


if __name__ == "__main__":
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    test_live_startlists(count)
