"""
src/run_full_parse.py
Sorumluluk: Tüm metin tabanlı (src/ankara + src/tyf_pdf_arsivi_all) ve taranmış OCR
PDF'lerini yarış bilgileri (Müsabaka Adı, Şehir, Tarih, Yarış No, Cinsiyet, Mesafe,
Stil, Yaş Grubu) ile birlikte uçtan uca ayrıştırmak, kanonik doğrulamadan geçirmek
ve tek bir ana veri seti (Master CSV) üretmek.
"""

from __future__ import annotations

import csv
import os
import sys
import time
from pathlib import Path
from typing import List, Dict, Any

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.parse_tyf_archive import parse_all_archive_files
from src.build_canonical_reference import build_canonical_reference
from src.canonicalize_scanned_results import canonicalize_scanned_dataset


def run_full_pipeline():
    t_start = time.perf_counter()
    print("=" * 75)
    print("        TÜM VERİ SETİ UÇTAN UCA PARSE VE KANONİKLEŞTİRME SÜRECİ       ")
    print("=" * 75)

    # -------------------------------------------------------------
    # 1. Metin Tabanlı Dosyaların Ayrıştırılması
    # -------------------------------------------------------------
    print("\n>>> ADIM 1: Metin Tabanlı PDF Metinlerinin Ayrıştırılması...")
    
    # Ankara Metin Tabanlı (42 dosya)
    ankara_txt_dir = Path("output/txt/ankara")
    if ankara_txt_dir.exists():
        parse_all_archive_files(
            txt_dirs=ankara_txt_dir,
            out_swimmers_csv="output/ankara_bireysel_yuzucu_sonuclari.csv",
            out_dqs_csv="output/ankara_diskalifiyeler.csv",
            workers=6
        )

    # TYF Arşiv Metin Tabanlı (297 dosya)
    tyf_txt_dir = Path("output/txt/tyf_arsiv")
    if tyf_txt_dir.exists():
        parse_all_archive_files(
            txt_dirs=tyf_txt_dir,
            out_swimmers_csv="output/tyf_arsiv_bireysel_yuzucu_sonuclari.csv",
            out_dqs_csv="output/tyf_arsiv_diskalifiyeler.csv",
            workers=6
        )

    # Birleştirilmiş Metin Tabanlı (Ankara + TYF Arşiv: 339 dosya)
    print("\n>>> ADIM 2: Birleştirilmiş Metin Tabanlı Master CSV Üretiliyor...")
    metin_csv = "output/metin_tabanli_bireysel_yuzucu_sonuclari.csv"
    parse_all_archive_files(
        txt_dirs=[ankara_txt_dir, tyf_txt_dir],
        out_swimmers_csv=metin_csv,
        out_dqs_csv="output/metin_tabanli_diskalifiyeler.csv",
        workers=6
    )

    # -------------------------------------------------------------
    # 2. Kanonik Referans Tablolarının Oluşturulması (YALNIZCA METİN TABANLI)
    # -------------------------------------------------------------
    print("\n>>> ADIM 3: Kanonik Kulüp ve Sporcu Referans Tabloları Üretiliyor (Yalnızca Metin PDF)...")
    build_canonical_reference(
        text_results_csv=metin_csv,
        output_dir="output/reference"
    )

    # -------------------------------------------------------------
    # 3. Taranmış OCR Metin Dosyalarının Ayrıştırılması
    # -------------------------------------------------------------
    print("\n>>> ADIM 4: Taranmış OCR Metinlerinin Ham Ayrıştırılması...")
    
    ocr_dirs = []
    tyf_ocr_dir = Path("output/txt/tyf_scanned_ocr")
    ankara_ocr_dir = Path("output/txt/ankara_scanned_ocr")
    
    if tyf_ocr_dir.exists() and list(tyf_ocr_dir.glob("*.txt")):
        ocr_dirs.append(tyf_ocr_dir)
    if ankara_ocr_dir.exists() and list(ankara_ocr_dir.glob("*.txt")):
        ocr_dirs.append(ankara_ocr_dir)

    raw_ocr_swimmers = "output/taranmis_bireysel_yuzucu_sonuclari_raw.csv"
    raw_ocr_dqs = "output/taranmis_diskalifiyeler.csv"

    if ocr_dirs:
        parse_all_archive_files(
            txt_dirs=ocr_dirs,
            out_swimmers_csv=raw_ocr_swimmers,
            out_dqs_csv=raw_ocr_dqs,
            workers=6
        )

        # -------------------------------------------------------------
        # 4. Taranmış OCR Sonuçlarının Kanonikleştirilmesi ve Doğrulanması
        # -------------------------------------------------------------
        print("\n>>> ADIM 5: Taranmış Sonuçların Kanonik Eşleştirilmesi ve Temizlenmesi...")
        canonicalize_scanned_dataset(
            scanned_csv=raw_ocr_swimmers,
            out_cleaned_csv="output/taranmis_bireysel_yuzucu_sonuclari.csv",
            out_report_csv="output/reference/scanned_sporcu_duzeltme_raporu.csv"
        )

    # -------------------------------------------------------------
    # 5. Master CSV: Metin Tabanlı + Kanonik Taranmış Tüm Sonuçlar
    # -------------------------------------------------------------
    print("\n>>> ADIM 6: Nihai Master CSV Dosyasının Birleştirilmesi...")
    master_rows = []
    
    # Metin tabanlı sonuçları ekle
    if os.path.exists("output/metin_tabanli_bireysel_yuzucu_sonuclari.csv"):
        with open("output/metin_tabanli_bireysel_yuzucu_sonuclari.csv", encoding="utf-8-sig") as f:
            for r in csv.DictReader(f):
                r["Kaynak Türü"] = "METIN_PDF"
                master_rows.append(r)

    # Taranmış sonuçları ekle
    if os.path.exists("output/taranmis_bireysel_yuzucu_sonuclari.csv"):
        with open("output/taranmis_bireysel_yuzucu_sonuclari.csv", encoding="utf-8-sig") as f:
            for r in csv.DictReader(f):
                r["Kaynak Türü"] = "TARANMIS_OCR"
                master_rows.append(r)

    out_master_csv = "output/tum_bireysel_yuzucu_sonuclari_master.csv"
    if master_rows:
        fieldnames = ["Kaynak Türü"] + [k for k in master_rows[0].keys() if k != "Kaynak Türü"]
        with open(out_master_csv, "w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(master_rows)

    # Master Diskalifiyeler
    master_dq_rows = []
    if os.path.exists("output/metin_tabanli_diskalifiyeler.csv"):
        with open("output/metin_tabanli_diskalifiyeler.csv", encoding="utf-8-sig") as f:
            for r in csv.DictReader(f):
                r["Kaynak Türü"] = "METIN_PDF"
                master_dq_rows.append(r)
    if os.path.exists("output/taranmis_diskalifiyeler.csv"):
        with open("output/taranmis_diskalifiyeler.csv", encoding="utf-8-sig") as f:
            for r in csv.DictReader(f):
                r["Kaynak Türü"] = "TARANMIS_OCR"
                master_dq_rows.append(r)

    out_master_dq_csv = "output/tum_diskalifiyeler_master.csv"
    if master_dq_rows:
        dq_fieldnames = ["Kaynak Türü"] + [k for k in master_dq_rows[0].keys() if k != "Kaynak Türü"]
        with open(out_master_dq_csv, "w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=dq_fieldnames)
            writer.writeheader()
            writer.writerows(master_dq_rows)

    total_el = time.perf_counter() - t_start

    print("\n" + "=" * 75)
    print("                    FULL PARSE VE ENTEGRASYON RAPORU                 ")
    print("=" * 75)
    text_cnt = len([r for r in master_rows if r.get("Kaynak Türü") == "METIN_PDF"])
    ocr_cnt = len([r for r in master_rows if r.get("Kaynak Türü") == "TARANMIS_OCR"])
    print(f" Metin Tabanlı Yüzücü Sonucu   : {text_cnt:7d}")
    print(f" Taranmış/OCR Yüzücü Sonucu    : {ocr_cnt:7d}")
    print(f" TOPLAM MASTER YÜZÜCÜ SONUCU   : {len(master_rows):7d}")
    print(f" TOPLAM DİSKALİFİYE SONUCU     : {len(master_dq_rows):7d}")
    print(f" Toplam İşlem Süresi           : {total_el:.2f} saniye")
    print(f" Master Yüzücü Sonuçları CSV   : {out_master_csv}")
    print(f" Master Diskalifiyeler CSV     : {out_master_dq_csv}")
    print("=" * 75)


if __name__ == "__main__":
    run_full_pipeline()

