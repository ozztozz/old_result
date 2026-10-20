"""
src/parse_first_results.py
Sorumluluk: 'Sıra YB Zaman Derece' başlık kalıbını kullanarak, bu kalıba sahip
yarış bloklarındaki ilk sonuç satırını deterministik olarak ayrıştırmak,
SwimmerResultLine modeli ile doğrulamak ve CSV/JSON çıktılarını üretmek.
"""

from __future__ import annotations

import csv
import glob
import json
import os
import re
import sys
from pathlib import Path
from typing import List, Optional

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.models import SwimmerResultLine

PAGE_RE = re.compile(r"^===\s*SAYFA\s*(\d+)\s*/\s*(\d+)\s*===", re.I)

RACE_HEADER_RE = re.compile(
    r"^\s*Yar[ıiIİ][şsSŞ]\s+(\d+)\s*(?:,\s*|(?:\s{2,}|\t+))"
    r"([A-ZÇĞİÖŞÜa-zçğıöşü\s,]+?)(?:,\s*|(?:\s{2,}|\t+))"
    r"(\d+\s*x\s*\d+m|\d+m)\s+"
    r"([A-Za-zÇĞİÖŞÜçğıöşü\s]+?)"
    r"(?:(?:,\s*|(?:\s{2,}|\t+))([0-9\s\-+a-zçğıöşüA-ZÇĞİÖŞÜ]+))?$",
    re.I,
)

# Sıra YB Zaman Derece başlık kalıbı
TABLE_HEADER_RE = re.compile(r"^S[ıi]ra\s+YB\s+Zaman\s+Derece\s*$", re.I)

# Bireysel yüzücü sonuç satırı ayrıştırma regex'i
SWIMMER_ROW_RE = re.compile(
    r"^(?P<sira>\d+\.|td\.|disk\.|ykle\.|ykm\.)\s+"
    r"(?P<ad_soyad>.+?)\s{2,}"
    r"(?P<yb>\d{2})\s{2,}"
    r"(?P<kulup>.+?)\s{2,}"
    r"(?P<zaman>(?:\d{1,2}:)?\d{2}\.\d{2}|disk\.|ykle\.|ykm\.)"
    r"(?:\s+(?P<derece>\d+))?"
    r"(?:\s+(?P<splits>.*))?$"
)


def parse_first_result_lines(directory: str | Path) -> List[SwimmerResultLine]:
    """Tüm metin dosyalarında 'Sıra YB Zaman Derece' başlığından sonraki ilk sonuç satırını çeker."""
    files = sorted(glob.glob(os.path.join(str(directory), "*.txt")))
    results: List[SwimmerResultLine] = []

    for fpath in files:
        fn = Path(fpath).name
        lines = [line.strip() for line in open(fpath, encoding="utf-8")]

        for idx, line in enumerate(lines):
            m_race = RACE_HEADER_RE.match(line)
            if not (m_race and idx + 1 < len(lines) and "sonuçlar" in lines[idx + 1].lower()):
                continue

            race_no = m_race.group(1)

            # Yarış başlığından sonraki satırlarda tablo başlığını ara (en fazla 10 satır)
            hdr_found = False
            hdr_line_idx = -1
            for offset in range(1, 10):
                if idx + offset >= len(lines):
                    break
                candidate = lines[idx + offset]
                if TABLE_HEADER_RE.match(candidate):
                    hdr_found = True
                    hdr_line_idx = idx + offset
                    break

            if not hdr_found:
                continue

            # Tablo başlığından sonra gelen ilk yüzücü sonuç satırını bul
            cur = hdr_line_idx + 1
            while cur < len(lines):
                cand_line = lines[cur]

                # Yeni yarış başlığına denk geldiysek bu yarış boş demektir
                if RACE_HEADER_RE.match(cand_line) and cur + 1 < len(lines) and "sonuçlar" in lines[cur + 1].lower():
                    break

                # Yüzücü satırı başlangıcı mı? (1., 2., td., disk., vb.)
                if re.match(r"^(?:\d+\.|td\.|disk\.|ykle\.|ykm\.)\s+", cand_line):
                    m_row = SWIMMER_ROW_RE.match(cand_line)
                    if m_row:
                        gd = m_row.groupdict()
                        item = SwimmerResultLine(
                            dosya_adi=fn,
                            yaris_no=race_no,
                            satir_no=cur + 1,
                            sira=gd["sira"].rstrip("."),
                            ad_soyad=gd["ad_soyad"].strip(),
                            yb=gd["yb"].strip() if gd["yb"] else None,
                            kulup=gd["kulup"].strip(),
                            zaman=gd["zaman"].strip(),
                            derece=gd["derece"].strip() if gd["derece"] else None,
                            ham_satir=cand_line,
                        )
                        results.append(item)
                    break

                cur += 1

    return results


def save_results(results: List[SwimmerResultLine], out_csv: str, out_json: str) -> None:
    """Sonuçları CSV ve JSON formatında diske kaydeder."""
    os.makedirs(os.path.dirname(out_csv), exist_ok=True)

    # JSON kaydı
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump([r.model_dump() for r in results], f, ensure_ascii=False, indent=2)

    # CSV kaydı (Excel uyumlu UTF-8 BOM ile)
    fieldnames = [
        "Dosya Adı",
        "Yarış No",
        "Satır No",
        "Sıra",
        "Adı Soyadı",
        "YB",
        "Kulüp",
        "Zaman",
        "Derece",
        "Ham Satır",
    ]

    with open(out_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in results:
            writer.writerow({
                "Dosya Adı": r.dosya_adi,
                "Yarış No": r.yaris_no,
                "Satır No": r.satir_no,
                "Sıra": r.sira,
                "Adı Soyadı": r.ad_soyad,
                "YB": r.yb or "",
                "Kulüp": r.kulup,
                "Zaman": r.zaman,
                "Derece": r.derece or "",
                "Ham Satır": r.ham_satir,
            })


if __name__ == "__main__":
    txt_dir = Path("output/txt/ankara")
    parsed_items = parse_first_result_lines(txt_dir)
    print(f"Toplam parse edilen ilk sonuç satırı: {len(parsed_items)}")

    out_csv = "output/ilk_sonuc_satirlari.csv"
    out_json = "output/ilk_sonuc_satirlari.json"
    save_results(parsed_items, out_csv, out_json)
    print(f"CSV kaydedildi: {out_csv}")
    print(f"JSON kaydedildi: {out_json}")

