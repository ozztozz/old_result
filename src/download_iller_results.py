#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
src/download_iller_results.py
=============================
TYF İl Temsilcilikleri sonuç sayfalarından (Ankara hariç 80 il)
tüm PDF sonuç dosyalarını indirir ve il bazlı klasörlere kaydeder.
Çakışmaları önlemek için dosya adına tarih/yükleme klasörü öneklenir.
"""

import os
import sys
import re
import json
import time
import ssl
import urllib.request
from urllib.parse import urlparse, unquote
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, List, Any

MANIFEST_PATH = "output/iller_pdf_manifest.json"
BASE_DOWNLOAD_DIR = Path("src/iller_pdf")

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}


def sanitize_filename(name: str) -> str:
    """Windows dosya adı kısıtlamalarına uygun hale getirir."""
    name = unquote(name)
    name = re.sub(r'[\\/*?:"<>|]', "_", name)
    return name.strip()


def slugify_tr(text: str) -> str:
    """Türkçe il isimlerini klasör slug'ına dönüştürür."""
    tr_map = str.maketrans("çğıöşüÇĞİÖŞÜ", "cgiosuCGIOSU")
    clean = text.translate(tr_map).lower()
    clean = re.sub(r"[^a-z0-9]+", "_", clean).strip("_")
    return clean or "diger"


def build_unique_filename(url: str) -> str:
    """URL yolundaki yükleme klasörünü önekleyerek çakışmasız dosya adı üretir."""
    parts = [p for p in urlparse(url).path.split("/") if p]
    if len(parts) >= 2:
        date_folder = sanitize_filename(parts[-2])
        raw_fname = sanitize_filename(parts[-1])
        fname = f"{date_folder}_{raw_fname}"
    elif len(parts) == 1:
        fname = sanitize_filename(parts[0])
    else:
        fname = "dosya.pdf"

    if not fname.lower().endswith(".pdf"):
        fname += ".pdf"
    return fname


def download_single_file(item: Dict[str, Any]) -> Dict[str, Any]:
    """Tek bir PDF dosyasını indirir."""
    url = item["pdf_url"]
    prov = item["province"]
    prov_slug = slugify_tr(prov)
    fname = build_unique_filename(url)

    prov_dir = BASE_DOWNLOAD_DIR / prov_slug
    prov_dir.mkdir(parents=True, exist_ok=True)
    target_path = prov_dir / fname

    # Eğer dosya zaten inmiş ve geçerli boyuttaysa atla
    if target_path.exists() and target_path.stat().st_size > 512:
        return {
            "url": url,
            "province": prov,
            "title": item.get("title", ""),
            "path": str(target_path),
            "filename": fname,
            "size": target_path.stat().st_size,
            "status": "SKIPPED",
            "error": None
        }

    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, context=ctx, timeout=25) as resp:
                data = resp.read()
                if len(data) < 100:
                    raise ValueError(f"Dosya çok küçük ({len(data)} byte)")

                with open(target_path, "wb") as f:
                    f.write(data)

                return {
                    "url": url,
                    "province": prov,
                    "title": item.get("title", ""),
                    "path": str(target_path),
                    "filename": fname,
                    "size": len(data),
                    "status": "DOWNLOADED",
                    "error": None
                }
        except Exception as e:
            if attempt == 2:
                return {
                    "url": url,
                    "province": prov,
                    "title": item.get("title", ""),
                    "path": str(target_path),
                    "filename": fname,
                    "size": 0,
                    "status": "FAILED",
                    "error": str(e)
                }
            time.sleep(1.0)


def download_all_provincial_pdfs(max_workers: int = 12):
    t0 = time.time()
    print("=" * 70, flush=True)
    print("      TYF İL TEMSİLCİLİKLERİ SONUÇ PDF'LERİ İNDİRİLİYOR", flush=True)
    print("=" * 70, flush=True)

    if not os.path.exists(MANIFEST_PATH):
        print(f"[-] Manifest bulunamadı: {MANIFEST_PATH}", flush=True)
        sys.exit(1)

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        items = json.load(f)

    # URL bazında tekilleştirme
    unique_items = {}
    for item in items:
        unique_items[item["pdf_url"]] = item

    item_list = list(unique_items.values())
    print(f"[+] Toplam {len(item_list):,} adet benzersiz PDF indirilecek.", flush=True)

    results = []
    downloaded = 0
    skipped = 0
    failed = 0
    total_bytes = 0

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(download_single_file, it): it for it in item_list}
        completed = 0
        total = len(futures)

        for future in as_completed(futures):
            res = future.result()
            results.append(res)
            completed += 1

            st = res["status"]
            if st == "DOWNLOADED":
                downloaded += 1
                total_bytes += res["size"]
            elif st == "SKIPPED":
                skipped += 1
                total_bytes += res["size"]
            elif st == "FAILED":
                failed += 1

            if completed % 50 == 0 or completed == total:
                elapsed = time.time() - t0
                rate = completed / max(elapsed, 0.1)
                print(f"[{completed}/{total}] ({completed*100/total:.1f}%) | İndirilen: {downloaded:,} | Zaten Mevcut: {skipped:,} | Hatalı: {failed} | {rate:.1f} dosya/sn", flush=True)

    summary_path = "output/iller_download_summary.json"
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump({
            "total_files": len(results),
            "downloaded": downloaded,
            "skipped": skipped,
            "failed": failed,
            "total_bytes": total_bytes,
            "elapsed_seconds": time.time() - t0,
            "results": results
        }, f, ensure_ascii=False, indent=2)

    print("=" * 70, flush=True)
    print(f"[+] İndirme Tamamlandı: {downloaded} indirildi, {skipped} zaten mevcut, {failed} başarısız.", flush=True)
    print(f"[+] Toplam Boyut: {total_bytes / (1024*1024):.2f} MB ({time.time() - t0:.1f} saniye)", flush=True)
    print(f"[+] Özet Kaydedildi: {summary_path}", flush=True)
    print("=" * 70, flush=True)


if __name__ == "__main__":
    download_all_provincial_pdfs(max_workers=12)

