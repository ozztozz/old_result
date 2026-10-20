import sys
from pathlib import Path
sys.path.insert(0, r'c:\Users\OZDEN\Desktop\old_result')

import csv
from src.canonicalize_scanned_results import (
    load_text_reference_database, clean_raw_ocr_swimmer_name,
    clean_raw_ocr_club, canonicalize_club, norm, sim, standardize_swimmer_name
)

ref_athletes, ref_clubs = load_text_reference_database()

with open('output/tyf_scanned_bireysel_yuzucu_sonuclari.csv', encoding='utf-8-sig') as f:
    rows = list(csv.DictReader(f))

r = rows[400]
print("RAW ROW 400:", r)

raw_sp = r["Sporcu"]
raw_yb = r["Yaş"]
raw_kl = r["Kulüp"]
fn = r["Dosya Adı"]
ham = r.get("Ham Satır", "")

clean_sp, clean_yb = clean_raw_ocr_swimmer_name(raw_sp, raw_yb, ham)
print("1. clean_sp:", repr(clean_sp), "clean_yb:", repr(clean_yb))

clean_kl, clean_yb = clean_raw_ocr_club(raw_kl, clean_yb)
print("2. clean_kl:", repr(clean_kl), "clean_yb:", repr(clean_yb))

norm_sp = norm(clean_sp)
print("3. norm_sp:", repr(norm_sp), "in ref_athletes:", norm_sp in ref_athletes)

canon_kl = canonicalize_club(clean_kl, clean_sp, ref_clubs, ref_athletes)
print("4. canon_kl:", repr(canon_kl))

r["Sporcu"] = clean_sp
r["Yaş"] = clean_yb
r["Kulüp"] = canon_kl
print("FINAL ROW:", r)

