"""
src/parse_meet_metadata.py
Sorumluluk: Belgenin başındaki (ilk sayfa başından 'Yarış 1...' satırına kadar olan)
temel yarış bilgilerini (Yarış Adı, Yarış Yeri, Yarış Tarihi) deterministik olarak
ayrıştırarak CompetitionMetadata Pydantic modeline dönüştürmek.
"""

from __future__ import annotations

import glob
import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.models import CompetitionMetadata

PAGE_RE = re.compile(r"^===\s*SAYFA\s*(\d+)\s*/\s*(\d+)\s*===", re.I)
SESSION_RE = re.compile(
    r"^\s*(\d+\s*-\s*[\d\.]+\s*GÜN\s+[A-ZÇĞİÖŞÜ\s]+SEANSI)(?:\s{2,}|\t+)?([0-9\.\s:\-]+)?$",
    re.I,
)
EVENT_START_RE = re.compile(r"^\s*Yar[ıiIİ][şsSŞ]\s+\d+", re.I)

KNOWN_CITIES = {
    "ANKARA", "İSTANBUL", "İZMİR", "BURSA", "ANTALYA", "TRABZON", "EDİRNE",
    "GAZİANTEP", "KONYA", "MERSİN", "SAMSUN", "KOCAELİ", "ADANA", "KAYSERİ", "ESKİŞEHİR"
}


def parse_meet_metadata_from_file(file_path: str | Path) -> CompetitionMetadata:
    """Tek bir sonuç dosyasından temel yarış bilgilerini (Ad, Yer, Tarih) ayrıştırır."""
    file_path = Path(file_path)
    fn = file_path.name
    lines = [l.strip() for l in open(file_path, encoding="utf-8") if l.strip()]

    # 1. İlk sayfa ayracını atla (=== SAYFA 1 / N ===)
    idx = 0
    while idx < len(lines) and PAGE_RE.match(lines[idx]):
        idx += 1

    # 2. İlk yarış başlığına (Yarış 1 ...) kadar olan satırları topla
    header_block: List[str] = []
    while idx < len(lines):
        l = lines[idx]
        if EVENT_START_RE.match(l) or PAGE_RE.match(l):
            break
        header_block.append(l)
        idx += 1

    # 1. Satır: Müsabaka / Yarış Adı
    meet_name = header_block[0] if header_block else ""
    location = ""
    date_range = ""

    # Kalan satırlardan Şehir ve Tarih bilgilerini çıkar
    for l in header_block[1:]:
        u = l.upper()
        # Bilinen bir şehirle mi başlıyor veya virgüllü tarih satırı mı?
        is_city = any(u.startswith(c) for c in KNOWN_CITIES) or (
            "," in l and re.search(r"\d{1,2}[\.-]", l)
        )
        if is_city:
            if "," in l:
                parts = l.split(",", 1)
                location = parts[0].strip()
                date_range = parts[1].strip()
            else:
                location = l.strip()
            break

        # Seans satırında tarih varsa (Örn: 1. GÜN SABAH SEANSI 11.06.2024 - 10:00)
        m_sess = SESSION_RE.match(l)
        if m_sess and m_sess.group(2) and not date_range:
            m_dt = re.search(r"\d{1,2}\.\d{1,2}\.\d{4}", m_sess.group(2))
            if m_dt:
                date_range = m_dt.group(0)

    # Varsayılanlar ve ek aramalar:
    if not location:
        location = "ANKARA"

    if not date_range:
        # Belgenin ilk sayfasında yer alan ilk geçerli yarış tarihini bul
        for l in lines[:25]:
            m_dt = re.search(r"(\d{1,2}\.\d{1,2}\.\d{4})", l)
            if m_dt and not l.startswith("===") and "Splash" not in l:
                date_range = m_dt.group(1)
                break

    return CompetitionMetadata(
        dosya_adi=fn,
        yaris_adi=meet_name,
        yaris_yeri=location.upper(),
        yaris_tarihi=date_range,
    )


import csv

def parse_all_metadata(
    txt_dir: str | Path = "output/txt/ankara",
    output_json_path: Optional[str | Path] = "output/competition_metadata.json",
    output_csv_path: Optional[str | Path] = "output/yaris_temel_bilgileri.csv",
) -> List[CompetitionMetadata]:
    """Klasördeki tüm belgeler için sadece 3 temel bilgiyi ayrıştırır."""
    txt_files = sorted(Path(txt_dir).glob("*.txt"))
    results = [parse_meet_metadata_from_file(f) for f in txt_files]

    if output_json_path:
        out_p = Path(output_json_path)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        data = [m.model_dump() for m in results]
        out_p.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[+] {len(results)} dosya için meta veri kaydedildi (JSON): {out_p}")

    if output_csv_path:
        out_csv = Path(output_csv_path)
        out_csv.parent.mkdir(parents=True, exist_ok=True)
        fieldnames = ["Dosya Adı", "Yarış Adı", "Yarış Yeri", "Yarış Tarihi"]
        with open(out_csv, "w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for m in results:
                writer.writerow({
                    "Dosya Adı": m.dosya_adi,
                    "Yarış Adı": m.yaris_adi,
                    "Yarış Yeri": m.yaris_yeri,
                    "Yarış Tarihi": m.yaris_tarihi,
                })
        print(f"[+] {len(results)} dosya için meta veri kaydedildi (CSV): {out_csv}")

    return results


if __name__ == "__main__":
    results = parse_all_metadata()
    print("\n" + "=" * 90)
    print(f"{'Dosya Adı':40s} | {'Yarış Yeri':10s} | {'Yarış Tarihi':18s} | Yarış Adı")
    print("=" * 90)
    for m in results:
        print(f"{m.dosya_adi[:40]:40s} | {m.yaris_yeri:10s} | {m.yaris_tarihi:18s} | {m.yaris_adi}")

