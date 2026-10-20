#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
src/extract_iller_pdfs.py
=========================
src/iller_pdf altındaki tüm il bazlı PDF sonuç dosyalarını
PyMuPDF ile sütun/satır yapısını koruyarak metin dosyalarına (.txt)
dönüştürür ve output/txt/iller/ klasörüne kaydeder.
"""

import os
import sys
import time
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor, as_completed
from typing import Tuple, List

import fitz

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.pdf_reader import extract_native_page_text

INPUT_DIR = Path("src/iller_pdf")
OUTPUT_DIR = Path("output/txt/iller")


def convert_single_pdf(args: Tuple[Path, Path, bool]) -> Tuple[str, int, float, str]:
    """Tek bir PDF dosyasını metne dönüştürür."""
    pdf_path, out_txt_path, overwrite = args
    if not overwrite and out_txt_path.exists() and out_txt_path.stat().st_size > 50:
        return pdf_path.name, 0, 0.0, "SKIPPED"

    t0 = time.perf_counter()
    try:
        doc = fitz.open(pdf_path)
        total_pages = len(doc)
        pages_text = []

        for pno in range(total_pages):
            page = doc[pno]
            txt = extract_native_page_text(page)
            pages_text.append(f"=== SAYFA {pno + 1} / {total_pages} ===\n{txt}")

        doc.close()
        full_content = "\n\n".join(pages_text)
        out_txt_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_txt_path, "w", encoding="utf-8") as f:
            f.write(full_content)

        elapsed = time.perf_counter() - t0
        return pdf_path.name, total_pages, elapsed, "SUCCESS"
    except Exception as e:
        elapsed = time.perf_counter() - t0
        return pdf_path.name, 0, elapsed, f"ERROR: {str(e)}"


def batch_convert_iller_pdfs(workers: int = 8, overwrite: bool = False):
    t0 = time.time()
    print("=" * 70, flush=True)
    print("      İL SONUÇ PDF'LERİ METNE DÖNÜŞTÜRÜLÜYOR (PyMuPDF)", flush=True)
    print("=" * 70, flush=True)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    pdf_files = sorted([p for p in INPUT_DIR.glob("**/*.pdf") if p.is_file()])
    print(f"[+] Toplam dönüştürülecek il PDF sayısı: {len(pdf_files)}", flush=True)

    tasks = []
    for p in pdf_files:
        prov_slug = p.parent.name
        out_name = f"{prov_slug}_{p.stem}.txt"
        tasks.append((p, OUTPUT_DIR / out_name, overwrite))

    completed = 0
    total_pages = 0
    errors = []
    skipped = 0

    with ProcessPoolExecutor(max_workers=workers) as executor:
        futures = {executor.submit(convert_single_pdf, t): t[0] for t in tasks}
        total = len(futures)

        for future in as_completed(futures):
            name, pages, el, status = future.result()
            completed += 1

            if status == "SUCCESS":
                total_pages += pages
                if completed % 50 == 0 or completed == total:
                    rate = completed / max(time.time() - t0, 0.1)
                    print(f"[{completed}/{total}] ({completed*100/total:.1f}%) | {name} ({pages} sf, {el:.2f}s) | {rate:.1f} dosya/sn", flush=True)
            elif status == "SKIPPED":
                skipped += 1
                if completed % 100 == 0 or completed == total:
                    print(f"[{completed}/{total}] ({completed*100/total:.1f}%) | Atlandı (Mevcut)", flush=True)
            else:
                errors.append((name, status))

    elapsed = time.time() - t0
    print("=" * 70, flush=True)
    print(f"[+] Dönüştürme Tamamlandı: {completed - skipped} metne çevrildi, {skipped} atlandı, {len(errors)} hata.", flush=True)
    print(f"[+] Toplam Sayfa Sayısı : {total_pages:,}", flush=True)
    print(f"[+] Toplam Süre         : {elapsed:.2f} saniye", flush=True)
    print(f"[+] Hedef Klasör        : {OUTPUT_DIR}", flush=True)
    print("=" * 70, flush=True)


if __name__ == "__main__":
    batch_convert_iller_pdfs(workers=8)

