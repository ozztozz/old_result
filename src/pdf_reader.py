"""
src/pdf_reader.py
Sorumluluk: Yüzme sonuç PDF dosyalarını (metin tabanlı veya imaj/tarama tabanlı)
satır ve sütun yapısını koruyarak düz metin (.txt) dosyalarına dönüştürmek.

Mimari:
1. Sayfa bazlı hibrit kontrol yapılır:
   - Sayfada gömülü (native) metin varsa OCR kesinlikle çalıştırılmaz.
   - PyMuPDF (fitz) 'dict' çıktısındaki span koordinatları (x0, y0) kullanılarak
     aynı satırdaki hücreler soldan sağa birleştirilir. Bu yöntem, uzun kulüp
     isimlerinin derece sütunuyla iç içe geçmesini ("Spor 1:54.35Kulübü" hatasını)
     ve altbilgilerin sayfa başına kaymasını engeller.
2. Sayfada metin yoksa (imaj/tarama PDF'leri):
   - Sayfadaki ham görüntü çıkarılır, gri tonlamaya çevrilir ve düşük çözünürlüklü
     (örn. 827x1170 ~100 DPI) taramalardaki karakter kırılmalarını önlemek için
     bellek içinde 2x Bikübik (order=3) büyütme uygulanır.
   - Geçici dosya oluşturmadan (stdin/stdout üzerinden) Tesseract OCR
     ('-l tur+eng --psm 6 -c preserve_interword_spaces=1') ile tablo düzeni
     korunarak metne çevrilir.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

import fitz  # PyMuPDF
import numpy as np
from scipy.ndimage import zoom

DEFAULT_TESSERACT_PATHS = [
    r"C:\Program Files\Tesseract-OCR\tesseract.exe",
    r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
    os.path.expanduser(r"~\AppData\Local\Programs\Tesseract-OCR\tesseract.exe"),
    os.path.expanduser(r"~\AppData\Local\Tesseract-OCR\tesseract.exe"),
]


@dataclass
class ConversionResult:
    """Tek bir PDF dosyasının metne dönüştürülme özeti."""
    pdf_path: Path
    txt_path: Path
    total_pages: int
    native_pages: int
    ocr_pages: int
    elapsed_sec: float
    skipped: bool = False
    error: Optional[str] = None

    @property
    def mode(self) -> str:
        if self.skipped:
            return "SKIPPED"
        if self.ocr_pages == 0:
            return "NATIVE_TEXT"
        if self.native_pages == 0:
            return "OCR_IMAGE"
        return "HYBRID"


def find_tesseract_cmd(custom_path: Optional[str] = None) -> Optional[str]:
    """Sistemdeki Tesseract çalıştırılabilir dosyasını bulur."""
    if custom_path and os.path.exists(custom_path):
        return custom_path
    in_path = shutil.which("tesseract")
    if in_path:
        return in_path
    for candidate in DEFAULT_TESSERACT_PATHS:
        if os.path.exists(candidate):
            return candidate
    return None


def extract_native_page_text(page: fitz.Page, y_tolerance: float = 3.0) -> str:
    """
    Sayfadaki gömülü PDF metinlerini span koordinatlarına göre satır bazında çıkarır.

    Neden standart page.get_text("text") veya sort=True kullanılmıyor?
    - Standart get_text("text"): Tablo sütunlarını alt alta yazar ve sayfa altındaki
      hakem/Splash Meet Manager bilgilerini sayfanın en üstüne koyar.
    - get_text("text", sort=True): Karakter bazlı X sıralaması yaptığı için uzun
      kulüp adlarıyla derece sütunu çakıştığında metni böler
      (örn: 'Fatih Karakurt Alpha Academy Spor 1:54.35Kulübü').
    - Span bazlı (y0, x0) gruplama: Her bir metin bloğunu bütün olarak korur,
      aynı satırdaki sütunları soldan sağa sırayla yan yana birleştirir.
    """
    page_dict = page.get_text("dict")
    spans: List[Tuple[float, float, float, str]] = []

    for block in page_dict.get("blocks", []):
        if "lines" not in block:
            continue
        for line in block["lines"]:
            for span in line.get("spans", []):
                text = span.get("text", "").strip()
                if not text:
                    continue
                x0, y0, x1, y1 = span["bbox"]
                spans.append((y0, x0, x1, text))

    if not spans:
        return ""

    # Önce dikey (y0), sonra yatay (x0) koordinata göre sırala
    spans.sort(key=lambda item: (item[0], item[1]))

    # Y koordinatı birbirine yakın (y_tolerance içinde) olan span'ları aynı satıra grupla
    grouped_lines: List[Tuple[float, List[Tuple[float, float, str]]]] = []
    for y0, x0, x1, text in spans:
        if not grouped_lines or abs(y0 - grouped_lines[-1][0]) > y_tolerance:
            grouped_lines.append((y0, [(x0, x1, text)]))
        else:
            grouped_lines[-1][1].append((x0, x1, text))

    output_lines: List[str] = []
    for _, row_items in grouped_lines:
        row_items.sort(key=lambda item: item[0])
        line_parts: List[str] = []
        prev_x1: Optional[float] = None
        for x0, x1, text in row_items:
            if prev_x1 is not None:
                gap = x0 - prev_x1
                # Sütunlar arası boşluğu koru (en az 2 boşluk bırak)
                spaces = max(2, min(12, int(round(gap / 6.0)))) if gap > 4.0 else 2
                line_parts.append(" " * spaces)
            line_parts.append(text)
            prev_x1 = max(prev_x1 or x1, x1)
        output_lines.append("".join(line_parts))

    return "\n".join(output_lines)


def _clean_ocr_artifacts(text: str) -> str:
    """
    Düşük çözünürlüklü JPEG taramalarında doğum yılı (2 haneli DT/YB) ile sporcu/kulüp adı
    arasındaki geniş boşlukta oluşan tek karakterlik JPEG gürültülerini ('12 o Kulüp',
    '12 = Ted', '12 (Nesibe', '12. Emba', 'ŞENEL | 12' vb.) temizler.
    """
    cleaned_lines: List[str] = []
    for line in text.splitlines():
        line = line.rstrip()
        if not line:
            cleaned_lines.append("")
            continue
        # İsim ile 2 haneli doğum yılı arasındaki tekil çizgi/dik çizgi gürültüsü
        line = re.sub(r"([A-ZÇĞİÖŞÜa-zçğıöşü])\s+[|_—=~]+\s+(\d{2}\b)", r"\1   \2", line)
        # Doğum yılından hemen sonra gelen nokta/parantez veya tek harfli JPEG lekesi
        line = re.sub(
            r"(\b\d{2})\.?\s+(?:[oO=—~«»\"“”(|]|oO+|Oo+)?\s*([A-ZÇĞİÖŞÜ])",
            r"\1   \2",
            line,
        )
        cleaned_lines.append(line)
    return "\n".join(cleaned_lines)


def _prepare_page_image_png(page: fitz.Page, upscale_factor: float = 2.0) -> bytes:
    """
    Sayfadaki görüntüyü gri tonlamalı olarak alır ve bikübik (order=3)
    enterpolasyonla büyütüp PNG baytlarına çevirir.
    """
    doc = page.parent
    images = page.get_images(full=True)

    # Sayfa tek bir tam sayfa tarama imajından oluşuyorsa ve döndürülmemişse
    # doğrudan ham imajı çekmek yeniden örnekleme (resampling) kaybını önler.
    if len(images) == 1 and page.rotation == 0:
        xref = images[0][0]
        raw_pix = fitz.Pixmap(doc, xref)
        gray_pix = fitz.Pixmap(fitz.csGRAY, raw_pix) if raw_pix.n > 1 else raw_pix
    else:
        gray_pix = page.get_pixmap(dpi=150, colorspace=fitz.csGRAY)

    # Eğer görüntü zaten yüksek çözünürlüklüyse (>1600px genişlik) tekrar büyütmeye gerek yok
    if gray_pix.width >= 1600 or upscale_factor <= 1.0:
        return gray_pix.tobytes("png")

    arr = np.frombuffer(gray_pix.samples, dtype=np.uint8).reshape(
        gray_pix.height, gray_pix.width
    )
    upscaled = np.clip(
        zoom(arr.astype(np.float32), upscale_factor, order=3), 0, 255
    ).astype(np.uint8)
    up_pix = fitz.Pixmap(
        fitz.csGRAY, upscaled.shape[1], upscaled.shape[0], upscaled.tobytes(), False
    )
    return up_pix.tobytes("png")


def extract_ocr_page_text(
    page: fitz.Page,
    tesseract_cmd: Optional[str],
    lang: str = "tur+eng",
    upscale_factor: float = 2.0,
) -> str:
    """
    Gömülü metni olmayan (imaj tabanlı) bir PDF sayfasını OCR ile metne çevirir.
    """
    if not tesseract_cmd:
        raise RuntimeError(
            "Tesseract OCR bulunamadı! İmaj tabanlı PDF'leri okumak için "
            "Tesseract-OCR kurulu olmalıdır."
        )

    png_bytes = _prepare_page_image_png(page, upscale_factor=upscale_factor)

    cmd = [
        tesseract_cmd,
        "stdin",
        "stdout",
        "-l",
        lang,
        "--psm",
        "6",
        "-c",
        "preserve_interword_spaces=1",
    ]
    proc = subprocess.run(cmd, input=png_bytes, capture_output=True, check=False)
    if proc.returncode != 0:
        err_msg = proc.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"Tesseract OCR hatası (kod {proc.returncode}): {err_msg}")

    raw_text = proc.stdout.decode("utf-8", errors="replace")
    return _clean_ocr_artifacts(raw_text)


def convert_pdf_to_text(
    pdf_path: str | Path,
    output_txt_path: Optional[str | Path] = None,
    min_native_chars: int = 30,
    tesseract_cmd: Optional[str] = None,
    ocr_workers: int = 4,
    overwrite: bool = False,
) -> ConversionResult:
    """
    Tek bir PDF dosyasını sayfa sayfa analiz ederek metin (.txt) dosyasına çevirir.
    - Sayfada yeterli düz metin (>= min_native_chars) varsa OCR kullanmaz.
    - Sayfada metin yoksa OCR ile okur (çok sayfalı imaj PDF'lerinde sayfa bazlı
      paralel OCR çalıştırır).
    """
    t0 = time.perf_counter()
    pdf_path = Path(pdf_path)
    if output_txt_path is None:
        output_txt_path = pdf_path.with_suffix(".txt")
    else:
        output_txt_path = Path(output_txt_path)

    if output_txt_path.exists() and not overwrite:
        doc = fitz.open(pdf_path)
        total_pages = len(doc)
        doc.close()
        return ConversionResult(
            pdf_path=pdf_path,
            txt_path=output_txt_path,
            total_pages=total_pages,
            native_pages=0,
            ocr_pages=0,
            elapsed_sec=time.perf_counter() - t0,
            skipped=True,
        )

    resolved_tesseract = find_tesseract_cmd(tesseract_cmd)
    doc = fitz.open(pdf_path)
    total_pages = len(doc)

    page_texts: List[Optional[str]] = [None] * total_pages
    ocr_page_indices: List[int] = []
    native_count = 0

    # 1. Aşama: Tüm sayfalarda önce hızlıca gömülü metin (native text) kontrolü yap
    for idx in range(total_pages):
        page = doc[idx]
        native_text = extract_native_page_text(page)
        if len(native_text.strip()) >= min_native_chars:
            page_texts[idx] = native_text
            native_count += 1
        else:
            ocr_page_indices.append(idx)

    # 2. Aşama: Sadece gömülü metni olmayan sayfalar için OCR çalıştır
    if ocr_page_indices:
        if not resolved_tesseract:
            doc.close()
            raise RuntimeError(
                f"'{pdf_path.name}' içinde {len(ocr_page_indices)} imaj sayfası var "
                "ancak Tesseract OCR bulunamadı."
            )

        # PNG hazırlığını ana iş parçacığında yapıp Tesseract alt süreçlerini paralel koştur
        png_payloads = [
            (idx, _prepare_page_image_png(doc[idx], upscale_factor=2.0))
            for idx in ocr_page_indices
        ]

        def _ocr_worker(item: Tuple[int, bytes]) -> Tuple[int, str]:
            p_idx, png_data = item
            cmd = [
                resolved_tesseract,
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
                raise RuntimeError(f"Sayfa {p_idx + 1} OCR hatası: {err}")
            txt = proc.stdout.decode("utf-8", errors="replace")
            return p_idx, _clean_ocr_artifacts(txt)

        workers = max(1, min(ocr_workers, len(png_payloads)))
        if workers == 1:
            for item in png_payloads:
                p_idx, txt = _ocr_worker(item)
                page_texts[p_idx] = txt
        else:
            with ThreadPoolExecutor(max_workers=workers) as pool:
                for p_idx, txt in pool.map(_ocr_worker, png_payloads):
                    page_texts[p_idx] = txt

    doc.close()

    # 3. Aşama: Sayfaları birleştir ve UTF-8 olarak kaydet
    formatted_pages: List[str] = []
    for idx, txt in enumerate(page_texts):
        header = f"=== SAYFA {idx + 1} / {total_pages} ==="
        formatted_pages.append(f"{header}\n{(txt or '').strip()}\n")

    output_txt_path.parent.mkdir(parents=True, exist_ok=True)
    output_txt_path.write_text("\n".join(formatted_pages), encoding="utf-8")

    return ConversionResult(
        pdf_path=pdf_path,
        txt_path=output_txt_path,
        total_pages=total_pages,
        native_pages=native_count,
        ocr_pages=len(ocr_page_indices),
        elapsed_sec=time.perf_counter() - t0,
    )


def convert_directory(
    input_dir: str | Path = "src/ankara",
    output_dir: str | Path = "output/txt/ankara",
    mode: str = "all",  # 'all', 'native-only', 'ocr-only'
    max_workers: int = 8,
    overwrite: bool = False,
) -> List[ConversionResult]:
    """
    Bir klasördeki tüm PDF dosyalarını tarar ve metin dosyalarına dönüştürür.
    """
    input_path = Path(input_dir)
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    pdf_files = sorted(input_path.glob("*.pdf"))
    if not pdf_files:
        print(f"[UYARI] '{input_path}' klasöründe PDF dosyası bulunamadı.")
        return []

    # Dosyaları hızlıca ön-sınıflandır (metin mi, imaj mı?)
    selected_files: List[Tuple[Path, bool]] = []
    for pdf_file in pdf_files:
        doc = fitz.open(pdf_file)
        has_native = any(len(p.get_text().strip()) >= 30 for p in doc)
        doc.close()

        if mode == "native-only" and not has_native:
            continue
        if mode == "ocr-only" and has_native:
            continue
        selected_files.append((pdf_file, has_native))

    print(
        f"Toplam {len(selected_files)} PDF işlenecek "
        f"(Metin: {sum(1 for _, h in selected_files if h)}, "
        f"İmaj/OCR: {sum(1 for _, h in selected_files if not h)}) -> '{output_path}'"
    )

    results: List[ConversionResult] = []
    for idx, (pdf_file, has_native) in enumerate(selected_files, start=1):
        out_txt = output_path / f"{pdf_file.stem}.txt"
        try:
            res = convert_pdf_to_text(
                pdf_path=pdf_file,
                output_txt_path=out_txt,
                ocr_workers=max_workers if not has_native else 1,
                overwrite=overwrite,
            )
            results.append(res)
            status_tag = (
                "ATLANDI"
                if res.skipped
                else ("METİN" if res.ocr_pages == 0 else f"OCR ({res.ocr_pages} syf)")
            )
            print(
                f"[{idx:02d}/{len(selected_files):02d}] {status_tag:12s} | "
                f"{res.total_pages:3d} sayfa | {res.elapsed_sec:5.2f}s | {pdf_file.name}"
            )
        except Exception as exc:
            print(f"[{idx:02d}/{len(selected_files):02d}] HATA         | {pdf_file.name}: {exc}")
            results.append(
                ConversionResult(
                    pdf_path=pdf_file,
                    txt_path=out_txt,
                    total_pages=0,
                    native_pages=0,
                    ocr_pages=0,
                    elapsed_sec=0.0,
                    error=str(exc),
                )
            )

    return results


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Yüzme sonuç PDF dosyalarını (metin + OCR hibrit) .txt dosyalarına çevirir."
    )
    parser.add_argument(
        "--input-dir",
        default="src/ankara",
        help="PDF dosyalarının bulunduğu klasör (varsayılan: src/ankara)",
    )
    parser.add_argument(
        "--output-dir",
        default="output/txt/ankara",
        help="Çıktı .txt dosyalarının kaydedileceği klasör (varsayılan: output/txt/ankara)",
    )
    parser.add_argument(
        "--mode",
        choices=["all", "native-only", "ocr-only"],
        default="all",
        help="İşleme modu: 'all' (tümü), 'native-only' (sadece düz metin), 'ocr-only' (sadece imaj)",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=max(1, (os.cpu_count() or 4) - 2),
        help="OCR için paralel iş parçacığı sayısı",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Mevcut .txt dosyalarının üzerine yaz",
    )
    args = parser.parse_args()

    t_start = time.perf_counter()
    results = convert_directory(
        input_dir=args.input_dir,
        output_dir=args.output_dir,
        mode=args.mode,
        max_workers=args.workers,
        overwrite=args.overwrite,
    )
    elapsed = time.perf_counter() - t_start
    ok_count = sum(1 for r in results if not r.error)
    err_count = sum(1 for r in results if r.error)
    print(
        f"\nTamamlandı! Başarılı: {ok_count}, Hatalı: {err_count}, Toplam Süre: {elapsed:.2f}s"
    )


if __name__ == "__main__":
    main()
