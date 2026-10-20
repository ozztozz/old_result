#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
src/merge_all_results.py
========================
Tüm veri kaynaklarını (Ulusal Metin Arşivi, Ankara, Taranmış OCR ve İl Temsilcilikleri)
tek bir ana Master CSV (output/tum_bireysel_yuzucu_sonuclari_master.csv) altında birleştirir.
"""

import os
import sys
import csv
import time
from pathlib import Path

METIN_CSV = Path("output/metin_tabanli_bireysel_yuzucu_sonuclari.csv")
OCR_CSV = Path("output/taranmis_bireysel_yuzucu_sonuclari.csv")
ILLER_CSV = Path("output/iller_bireysel_yuzucu_sonuclari.csv")
MASTER_CSV = Path("output/tum_bireysel_yuzucu_sonuclari_master.csv")


def merge_datasets():
    t0 = time.time()
    print("=" * 70, flush=True)
    print("      TÜM YÜZME SONUÇLARI MASTER CSV BİRLEŞTİRİLİYOR", flush=True)
    print("=" * 70, flush=True)

    sources = [
        ("Ulusal Metin Arşivi & Ankara", METIN_CSV),
        ("Taranmış OCR Arşivi (Kanonik)", OCR_CSV),
        ("İl Temsilcilikleri (80 İl)", ILLER_CSV),
    ]

    fieldnames = None
    total_written = 0

    with open(MASTER_CSV, "w", encoding="utf-8-sig", newline="") as out_f:
        writer = None

        for label, path in sources:
            if not path.exists():
                print(f"[!] Uyarı: {label} dosyası bulunamadı ({path}), atlanıyor.", flush=True)
                continue

            cnt = 0
            with open(path, "r", encoding="utf-8-sig") as in_f:
                reader = csv.DictReader(in_f)
                if fieldnames is None:
                    fieldnames = reader.fieldnames
                    writer = csv.DictWriter(out_f, fieldnames=fieldnames)
                    writer.writeheader()

                for row in reader:
                    # Sadece fieldnames'teki sütunları yaz
                    clean_row = {k: row.get(k, "") for k in fieldnames}
                    writer.writerow(clean_row)
                    cnt += 1

            total_written += cnt
            print(f"[+] {label:32s}: {cnt:>9,} satır eklendi.", flush=True)

    elapsed = time.time() - t0
    print("=" * 70, flush=True)
    print(f"[+] Master CSV Başarıyla Oluşturuldu : {MASTER_CSV}", flush=True)
    print(f"[+] Toplam Bireysel Yarış Kaydı      : {total_written:,}", flush=True)
    print(f"[+] Dosya Boyutu                    : {MASTER_CSV.stat().st_size / (1024*1024):.2f} MB", flush=True)
    print(f"[+] İşlem Süresi                    : {elapsed:.2f} saniye", flush=True)
    print("=" * 70, flush=True)


if __name__ == "__main__":
    merge_datasets()
