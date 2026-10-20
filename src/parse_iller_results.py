#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
src/parse_iller_results.py
==========================
output/txt/iller/*.txt altındaki il temsilcilikleri sonuç metinlerini
bireysel yüzücü sonuçları ve diskalifiyeler olarak ayrıştırıp
CSV formatına aktarır. Müsabaka adları ve şehirler manifest verileriyle
zenginleştirilir.
"""

import os
import sys
import re
import csv
import json
import time
from pathlib import Path
from typing import List, Dict, Any, Tuple
from concurrent.futures import ProcessPoolExecutor
from urllib.parse import urlparse, unquote

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.parse_tyf_archive import parse_single_file

TXT_DIR = Path("output/txt/iller")
MANIFEST_PATH = Path("output/iller_pdf_manifest.json")
OUT_SWIMMERS_CSV = Path("output/iller_bireysel_yuzucu_sonuclari.csv")
OUT_DQS_CSV = Path("output/iller_diskalifiyeler.csv")

GENERIC_TITLES = {
    "TIKLAYINIZ", "TIKLA", "INDIR", "İNDİR", "DOSYA", "SONUCLAR", "SONUÇLAR",
    "TOPLU SONUC", "TOPLU SONUÇ", "TOPLU SONUCLAR", "TOPLU SONUÇLAR",
    "TUM SONUCLAR", "TÜM SONUÇLAR", "SONUCLARI", "SONUÇLARI", "PDF", "DOKUMAN"
}


def sanitize_filename(name: str) -> str:
    name = unquote(name)
    name = re.sub(r'[\\/*?:"<>|]', "_", name)
    return name.strip()


def slugify_tr(text: str) -> str:
    tr_map = str.maketrans("çğıöşüÇĞİÖŞÜ", "cgiosuCGIOSU")
    clean = text.translate(tr_map).lower()
    clean = re.sub(r"[^a-z0-9]+", "_", clean).strip("_")
    return clean or "diger"


def build_manifest_lookup() -> Dict[str, Dict[str, str]]:
    """Manifest dosyasından metin dosyası adına göre il ve başlık eşleme tablosu üretir."""
    lookup = {}
    if not MANIFEST_PATH.exists():
        return lookup

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        items = json.load(f)

    for item in items:
        url = item.get("pdf_url", "")
        prov = item.get("province", "")
        title = item.get("title", "").strip()

        parts = [p for p in urlparse(url).path.split("/") if p]
        if len(parts) >= 2:
            date_folder = sanitize_filename(parts[-2])
            raw_fname = sanitize_filename(parts[-1])
            pdf_fname = f"{date_folder}_{raw_fname}"
        elif len(parts) == 1:
            pdf_fname = sanitize_filename(parts[0])
        else:
            pdf_fname = "dosya.pdf"

        if not pdf_fname.lower().endswith(".pdf"):
            pdf_fname += ".pdf"

        prov_slug = slugify_tr(prov)
        stem = Path(pdf_fname).stem
        txt_name = f"{prov_slug}_{stem}.txt"

        lookup[txt_name] = {
            "province": prov,
            "title": title
        }

    return lookup


def parse_all_iller_files(workers: int = 8):
    t0 = time.time()
    print("=" * 70, flush=True)
    print("      İL TEMSİLCİLİKLERİ YÜZME SONUÇLARI AYRIŞTIRILIYOR       ", flush=True)
    print("=" * 70, flush=True)

    if not TXT_DIR.exists():
        print(f"[-] Dizin bulunamadı: {TXT_DIR}", flush=True)
        sys.exit(1)

    txt_files = sorted(list(TXT_DIR.glob("*.txt")))
    print(f"[+] Toplam ayrıştırılacak il metin dosyası: {len(txt_files):,}", flush=True)

    manifest_lookup = build_manifest_lookup()
    print(f"[+] Manifest eşleme tablosu hazırlandı ({len(manifest_lookup):,} dosya).", flush=True)

    all_swimmers: List[Dict[str, Any]] = []
    all_dqs: List[Dict[str, Any]] = []

    with ProcessPoolExecutor(max_workers=workers) as executor:
        results = executor.map(parse_single_file, txt_files)
        for i, (sws, dqs) in enumerate(results, 1):
            txt_path = txt_files[i - 1]
            txt_name = txt_path.name
            meta = manifest_lookup.get(txt_name, {})

            prov_name = meta.get("province", "")
            raw_title = meta.get("title", "").strip()
            title_clean = re.sub(r"\s+", " ", raw_title).strip()
            is_generic = title_clean.upper() in GENERIC_TITLES or len(title_clean) < 4

            # Sonuçları zenginleştir
            for r in sws:
                r["Kaynak Türü"] = "IL_TEMSILCILIGI"
                if prov_name and (not r.get("Şehir") or r.get("Şehir") == "None"):
                    r["Şehir"] = prov_name
                # Müsabaka adı zenginleştirme
                m_adi = r.get("Müsabaka Adı", "").strip()
                if not is_generic and (not m_adi or m_adi.startswith("Yarış ") or m_adi.startswith("Event ") or "1.  " in m_adi):
                    r["Müsabaka Adı"] = title_clean
                elif not m_adi or "1.  " in m_adi or m_adi.startswith("Yarış "):
                    # Dosya adından temizle
                    base = txt_path.stem.replace("_", " ").replace("-", " ")
                    r["Müsabaka Adı"] = f"{prov_name} Yüzme Yarışları ({base})".strip()

            for r in dqs:
                r["Kaynak Türü"] = "IL_TEMSILCILIGI"
                if prov_name and (not r.get("Şehir") or r.get("Şehir") == "None"):
                    r["Şehir"] = prov_name
                m_adi = r.get("Müsabaka Adı", "").strip()
                if not is_generic and (not m_adi or m_adi.startswith("Yarış ") or m_adi.startswith("Event ") or "1.  " in m_adi):
                    r["Müsabaka Adı"] = title_clean

            all_swimmers.extend(sws)
            all_dqs.extend(dqs)

            if i % 50 == 0 or i == len(txt_files):
                elapsed = time.time() - t0
                print(f"[{i}/{len(txt_files)}] ({i*100/len(txt_files):.1f}%) | Yüzücü Sonucu: {len(all_swimmers):,} | DQ: {len(all_dqs):,} ({elapsed:.1f}s)", flush=True)

    # CSV Kaydet
    if all_swimmers:
        with open(OUT_SWIMMERS_CSV, "w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(all_swimmers[0].keys()))
            writer.writeheader()
            writer.writerows(all_swimmers)
        print(f"[+] {len(all_swimmers):,} yüzücü sonucu kaydedildi -> {OUT_SWIMMERS_CSV}", flush=True)

    if all_dqs:
        with open(OUT_DQS_CSV, "w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(all_dqs[0].keys()))
            writer.writeheader()
            writer.writerows(all_dqs)
        print(f"[+] {len(all_dqs):,} diskalifiye kaydı kaydedildi -> {OUT_DQS_CSV}", flush=True)

    print("=" * 70, flush=True)
    print(f"[+] İl Sonuçları Parse İşlemi Tamamlandı ({time.time() - t0:.2f} saniye).", flush=True)
    print("=" * 70, flush=True)


if __name__ == "__main__":
    parse_all_iller_files(workers=8)

