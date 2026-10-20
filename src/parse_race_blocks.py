"""
src/parse_race_blocks.py
Sorumluluk: Metin belgelerindeki her bir yarış bloğunun başlangıç başlığını
(Yarış No, Cinsiyet, Mesafe, Tür, Yaş) deterministik olarak ayrıştırıp
RaceBlockMetadata Pydantic modeliyle doğrulamak ve CSV/JSON çıktısı üretmek.
"""

from __future__ import annotations

import csv
import glob
import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.models import RaceBlockMetadata

PAGE_RE = re.compile(r"^===\s*SAYFA\s*(\d+)\s*/\s*(\d+)\s*===", re.I)

EVENT_HEADER_RE = re.compile(
    r"^\s*Yar[ıiIİ][şsSŞ]\s+(\d+)\s*(?:,\s*|(?:\s{2,}|\t+))"
    r"([A-ZÇĞİÖŞÜa-zçğıöşü\s,]+?)(?:,\s*|(?:\s{2,}|\t+))"
    r"(\d+\s*x\s*\d+m|\d+m)\s+"
    r"([A-Za-zÇĞİÖŞÜçğıöşü\s]+?)"
    r"(?:(?:,\s*|(?:\s{2,}|\t+))([0-9\s\-+a-zçğıöşüA-ZÇĞİÖŞÜ]+))?$",
    re.I,
)

EVENT_DATE_RESULTS_RE = re.compile(
    r"^\s*(\d{1,2}\.\d{1,2}\.\d{4})(?:\s*-\s*([0-9:]+))?\s+Sonu[çc]lar\s*$",
    re.I,
)


def normalize_stroke(stroke_text: str) -> str:
    """Yüzme stilini / türünü standartlaştırır (örn: 'Sırtüstü Ayak' -> 'Sırtüstü')."""
    s = stroke_text.lower()
    if "sırt" in s:
        return "Sırtüstü"
    if "serbest" in s:
        return "Serbest"
    if "kurbağa" in s:
        return "Kurbağalama"
    if "kelebek" in s:
        return "Kelebek"
    if "karışık" in s:
        return "Karışık"
    return stroke_text.strip()


def normalize_distance(dist_text: str) -> str:
    """Mesafeyi standartlaştırır (örn: '50m' -> '50', '4 x 50m' -> '4 x 50m')."""
    d = dist_text.strip()
    if d.endswith("m") and "x" not in d.lower():
        return d[:-1].strip()
    return d


def normalize_age(age_str: Optional[str]) -> str:
    """Yaş grubunu standartlaştırır (örn: '8 yaş' -> '8', '11 - 12 yaşları arası' -> '11 - 12')."""
    if not age_str:
        return ""
    s = age_str.strip()
    m_single = re.match(r"^(\d{1,2})\s*yaş\s*$", s, re.I)
    if m_single:
        return m_single.group(1)
    m_range = re.match(r"^(\d{1,2}\s*-\s*\d{1,2})\s*yaşları\s*arası$", s, re.I)
    if m_range:
        return m_range.group(1)
    m_plus = re.match(r"^(\d{1,2})\s*yaş\s*(?:ve\s*büyükler|ve\s*üzeri|\+)", s, re.I)
    if m_plus:
        return f"{m_plus.group(1)}+"
    return s


def parse_race_blocks_from_file(file_path: str | Path) -> List[RaceBlockMetadata]:
    """Tek bir sonuç dosyasındaki tüm yeni yarış bloklarını ayrıştırır."""
    file_path = Path(file_path)
    fn = file_path.name
    lines = [l.strip() for l in open(file_path, encoding="utf-8")]

    races: List[RaceBlockMetadata] = []
    curr_page = 1

    for lno, l in enumerate(lines, 1):
        m_page = PAGE_RE.match(l)
        if m_page:
            curr_page = int(m_page.group(1))
            continue

        m_ev = EVENT_HEADER_RE.match(l)
        if m_ev:
            # Yeni yarış bloğu başlangıcı mı (Sonuçlar satırı takip ediyor mu)?
            nxt_line = ""
            for k in range(lno, min(lno + 4, len(lines))):
                if lines[k]:
                    nxt_line = lines[k]
                    break

            if EVENT_DATE_RESULTS_RE.match(nxt_line):
                dist_raw = m_ev.group(3).strip()
                is_relay = "x" in dist_raw.lower()
                race = RaceBlockMetadata(
                    dosya_adi=fn,
                    sayfa_no=curr_page,
                    satir_no=lno,
                    yaris_no=m_ev.group(1).strip(),
                    cinsiyet=m_ev.group(2).strip(),
                    mesafe=normalize_distance(dist_raw),
                    tur=normalize_stroke(m_ev.group(4)),
                    yas=normalize_age(m_ev.group(5)),
                    bayrak_mi=is_relay,
                    ham_baslik=l,
                )
                races.append(race)

    return races


def parse_all_race_blocks(
    txt_dir: str | Path = "output/txt/ankara",
    output_csv_path: Optional[str | Path] = "output/yaris_bloklari.csv",
    output_json_path: Optional[str | Path] = "output/yaris_bloklari.json",
) -> List[RaceBlockMetadata]:
    """Tüm belgelerdeki yarış bloklarını ayrıştırır ve CSV/JSON olarak dışa aktarır."""
    txt_files = sorted(Path(txt_dir).glob("*.txt"))
    all_races: List[RaceBlockMetadata] = []

    for f in txt_files:
        races = parse_race_blocks_from_file(f)
        all_races.extend(races)

    if output_csv_path:
        out_csv = Path(output_csv_path)
        out_csv.parent.mkdir(parents=True, exist_ok=True)
        fieldnames = [
            "Dosya Adı",
            "Sayfa No",
            "Satır No",
            "Yarış No",
            "Bayrak Mı",
            "Cinsiyet",
            "Mesafe",
            "Tür",
            "Yaş",
            "Ham Başlık",
        ]
        with open(out_csv, "w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for r in all_races:
                writer.writerow({
                    "Dosya Adı": r.dosya_adi,
                    "Sayfa No": r.sayfa_no,
                    "Satır No": r.satir_no,
                    "Yarış No": r.yaris_no,
                    "Bayrak Mı": "EVET" if r.bayrak_mi else "HAYIR",
                    "Cinsiyet": r.cinsiyet,
                    "Mesafe": r.mesafe,
                    "Tür": r.tur,
                    "Yaş": r.yas,
                    "Ham Başlık": r.ham_baslik,
                })
        print(f"[+] {len(all_races)} yarış bloğu CSV olarak kaydedildi: {out_csv}")

    if output_json_path:
        out_json = Path(output_json_path)
        out_json.parent.mkdir(parents=True, exist_ok=True)
        data = [r.model_dump() for r in all_races]
        out_json.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[+] {len(all_races)} yarış bloğu JSON olarak kaydedildi: {out_json}")

    return all_races


if __name__ == "__main__":
    results = parse_all_race_blocks()
    print(f"\nToplam Ayrıştırılan Yarış Bloğu: {len(results)}")

