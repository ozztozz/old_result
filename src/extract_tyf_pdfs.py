"""
src/extract_tyf_pdfs.py
Sorumluluk: src/tyf_pdf_arsivi_all klasöründeki 297 adet metin tabanlı PDF dosyasını
PyMuPDF span koordinatlarına göre sütun ve satır yapısını koruyarak
output/txt/tyf_arsiv/*.txt formatına dönüştürmek.
"""

from __future__ import annotations

import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Tuple

import fitz

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.pdf_reader import extract_native_page_text


def convert_single_pdf(args: Tuple[Path, Path, bool]) -> Tuple[str, int, float, str]:
    """Tek bir PDF'i metne dönüştürür."""
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


def batch_convert_tyf_pdfs(
    input_dir: str | Path = "src/tyf_pdf_arsivi_all",
    output_dir: str | Path = "output/txt/tyf_arsiv",
    workers: int = 8,
    overwrite: bool = False
):
    input_dir = Path(input_dir)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    pdf_files = sorted([p for p in input_dir.glob("*.pdf") if p.is_file()])
    print(f"Toplam dönüştürülecek metin tabanlı PDF sayısı: {len(pdf_files)}")

    tasks = [(p, output_dir / f"{p.stem}.txt", overwrite) for p in pdf_files]

    start_time = time.perf_counter()
    completed = 0
    total_pages = 0
    errors = []

    with ProcessPoolExecutor(max_workers=workers) as executor:
        futures = {executor.submit(convert_single_pdf, t): t[0] for t in tasks}
        for future in as_completed(futures):
            name, pages, el, status = future.result()
            completed += 1
            if status == "SUCCESS":
                total_pages += pages
                if completed % 25 == 0 or completed == len(tasks):
                    print(f"[{completed}/{len(tasks)}] {name} -> {pages} sayfa ({el:.2f}s)")
            elif status == "SKIPPED":
                if completed % 50 == 0:
                    print(f"[{completed}/{len(tasks)}] (Atlandı - zaten mevcut)")
            else:
                errors.append((name, status))
                print(f"[HATA] {name}: {status}")

    total_time = time.perf_counter() - start_time
    print("\n" + "=" * 60)
    print(f"DÖNÜŞTÜRME TAMAMLANDI")
    print(f"Toplam Süre        : {total_time:.2f} saniye")
    print(f"Dönüştürülen PDF  : {completed}")
    print(f"Toplam Sayfa       : {total_pages}")
    print(f"Hatalı Dosya       : {len(errors)}")
    print("=" * 60)


if __name__ == "__main__":
    batch_convert_tyf_pdfs()

