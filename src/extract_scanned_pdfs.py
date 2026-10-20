"""
src/extract_scanned_pdfs.py
Sorumluluk: src/tyf_pdf_arsivi_all/tarama_veya_resim_pdfler/ altındaki
10 adet taranmış/resim PDF dosyasını (toplam 1.263 sayfa) çok çekirdekli
Tesseract OCR ile metne (.txt) dönüştürmek ve derece/puan sütun ayrıştırmasını uygulamak.
"""

from __future__ import annotations

import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import List, Optional, Tuple

import fitz

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.pdf_reader import find_tesseract_cmd, _prepare_page_image_png, _clean_ocr_artifacts


def clean_ocr_swimming_line(line: str) -> str:
    """Yüzme sonuçlarındaki OCR gürültülerini ve bitişik sütunları temizler."""
    # 1. Slash içeren zamanlar: 32/4 -> 32.40, 32/5 -> 32.50
    line = re.sub(r'\b(\d{2})\/(\d{1,2})\b', r'\1.\2', line)
    # 2. Kulüp adı ile yapışan derece (dakikalı veya dakikasız): Kul1:20.59 -> Kul   1:20.59, Kulül28.53 -> Kulül   28.53
    line = re.sub(r"([A-Za-zçğıöşüÇĞİÖŞÜ])((?:\d{1,2}:)?\d{2}\.\d{1,2})", r"\1   \2", line)
    # 3. Derece ile puan arasındaki OCR karakter lekeleri (ibü, (o, Oo, ü vb.): 30.53ibü466 -> 30.53   466, 28.53 (o 571 -> 28.53   571
    line = re.sub(r"((?:\d{1,2}:)?\d{2}\.\d{1,2})\s*(?:[\(\)\[\]A-Za-zçğıöşüÇĞİÖŞÜoOe<>/_~]+\s*)(\d{2,4}\b)", r"\1   \2", line)
    # 4. İsim ile 2 haneli doğum yılı arasındaki çizgi gürültüsü
    line = re.sub(r"([A-ZÇĞİÖŞÜa-zçğıöşü])\s+[|_—=~]+\s+(\d{2}\b)", r"\1   \2", line)
    # 5. İki noktası olan ama noktası silinen dakikalı zaman: 1:4248 -> 1:42.48, 2:3144 -> 2:31.44
    line = re.sub(r"\b(\d{1,2}):(\d{2})(\d{2})\b", r"\1:\2.\3", line)
    # 6. İki noktası silinmiş 1 dakikalık zamanlar: 1553.11 -> 1:53.11, 1S57.70 -> 1:57.70
    line = re.sub(r"\b1[5sS](\d{2}\.\d{2})\b", r"1:\1", line)
    line = re.sub(r"\b1([1-5]\d\.\d{2})\b", r"1:\1", line)
    # 7. Puan başındaki parantez lekeleri: (92 -> 92, (28 -> 28
    line = re.sub(r"(?<=\d\s)[\(\[\{]+(\d{1,4})\b", r"\1", line)
    return line


def ocr_single_page(args: Tuple[str, bytes, int, int]) -> Tuple[int, str]:
    tess_cmd, png_data, page_num, total_pages = args
    import subprocess
    cmd = [
        tess_cmd,
        "stdin",
        "stdout",
        "-l",
        "tur+eng",
        "--psm",
        "6",
        "-c",
        "preserve_interword_spaces=1",
    ]
    proc = subprocess.run(cmd, input=png_data, capture_output=True, check=False)
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"Sayfa {page_num} OCR hatası: {err}")

    raw_text = proc.stdout.decode("utf-8", errors="replace")
    cleaned = _clean_ocr_artifacts(raw_text)
    final_lines = [clean_ocr_swimming_line(l) for l in cleaned.splitlines()]
    return page_num, "\n".join(final_lines)


def process_scanned_pdf(
    pdf_path: Path,
    out_txt_path: Path,
    tess_cmd: str,
    workers: int = 8,
    upscale_factor: float = 2.0,
    overwrite: bool = False
) -> Tuple[str, int, float, str]:
    if not overwrite and out_txt_path.exists() and out_txt_path.stat().st_size > 100:
        return pdf_path.name, 0, 0.0, "SKIPPED"

    t0 = time.perf_counter()
    try:
        doc = fitz.open(pdf_path)
        total_pages = len(doc)

        # PNG'leri hazırla
        png_items = [
            (tess_cmd, _prepare_page_image_png(doc[pno], upscale_factor=upscale_factor), pno + 1, total_pages)
            for pno in range(total_pages)
        ]
        doc.close()

        # Sayfa bazlı paralel OCR çalıştır
        page_results: List[Optional[str]] = [None] * total_pages
        with ThreadPoolExecutor(max_workers=workers) as pool:
            for pno, txt in pool.map(ocr_single_page, png_items):
                page_results[pno - 1] = txt

        # Metin dosyası olarak biçimlendir
        formatted = []
        for idx, txt in enumerate(page_results):
            formatted.append(f"=== SAYFA {idx + 1} / {total_pages} ===\n{(txt or '').strip()}\n")

        out_txt_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_txt_path, "w", encoding="utf-8") as f:
            f.write("\n".join(formatted))

        elapsed = time.perf_counter() - t0
        return pdf_path.name, total_pages, elapsed, "SUCCESS"
    except Exception as e:
        elapsed = time.perf_counter() - t0
        return pdf_path.name, 0, elapsed, f"ERROR: {str(e)}"


def batch_ocr_scanned_pdfs(
    input_dir: str | Path = "src/tyf_pdf_arsivi_all/tarama_veya_resim_pdfler",
    output_dir: str | Path = "output/txt/tyf_scanned_ocr",
    workers: int = 8,
    overwrite: bool = False
):
    input_dir = Path(input_dir)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    tess_cmd = find_tesseract_cmd()
    if not tess_cmd:
        print("[HATA] Tesseract OCR bulunamadı!")
        sys.exit(1)

    pdf_files = sorted(list(input_dir.glob("*.pdf")))
    print(f"Toplam OCR uygulanacak taranmış PDF sayısı: {len(pdf_files)}")
    print(f"Kullanılan Tesseract Motoru: {tess_cmd}")
    print(f"Paralel OCR İş Parçacığı Sayısı: {workers}\n")

    t_start = time.perf_counter()
    total_processed_pages = 0

    for i, pdf_file in enumerate(pdf_files, 1):
        out_txt = output_dir / f"{pdf_file.stem}.txt"
        print(f"[{i}/{len(pdf_files)}] İşleniyor: {pdf_file.name} ...", end="", flush=True)

        name, pages, el, status = process_scanned_pdf(
            pdf_path=pdf_file,
            out_txt_path=out_txt,
            tess_cmd=tess_cmd,
            workers=workers,
            overwrite=overwrite
        )

        if status == "SUCCESS":
            total_processed_pages += pages
            print(f" TAMAMLANDI! ({pages} sayfa, {el:.1f}s - {el/pages:.2f}s/sayfa)")
        elif status == "SKIPPED":
            print(f" ATLANDI (Zaten mevcut)")
        else:
            print(f" HATA: {status}")

    t_total = time.perf_counter() - t_start
    print("\n" + "=" * 65)
    print("        TARANMIŞ PDF'LER OCR DÖNÜŞTÜRME RAPORU        ")
    print("=" * 65)
    print(f" İşlenen PDF Dosyası Sayısı : {len(pdf_files)}")
    print(f" Toplam Dönüştürülen Sayfa  : {total_processed_pages}")
    print(f" Toplam Harcanan Süre       : {t_total:.1f} saniye ({t_total/60:.2f} dakika)")
    print(f" Çıktı Dizin                : {output_dir}")
    print("=" * 65)


if __name__ == "__main__":
    batch_ocr_scanned_pdfs()

