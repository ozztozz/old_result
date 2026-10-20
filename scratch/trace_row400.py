import sys
from pathlib import Path
sys.path.insert(0, r'c:\Users\OZDEN\Desktop\old_result')

import csv
from src.canonicalize_scanned_results import clean_raw_ocr_swimmer_name, clean_raw_ocr_club, canonicalize_club, load_text_reference_database, norm

ref_athletes, ref_clubs = load_text_reference_database()

with open('output/tyf_scanned_bireysel_yuzucu_sonuclari.csv', encoding='utf-8-sig') as f:
    rows = list(csv.DictReader(f))

r = rows[400]
print("Row 400:", r)
sp, yb = clean_raw_ocr_swimmer_name(r['Sporcu'], r['Yaş'], r.get('Ham Satır', ''))
print("After clean_sp:", sp, "yb:", yb)
kl, yb = clean_raw_ocr_club(r['Kulüp'], yb)
print("After clean_kl:", kl, "yb:", yb)
canon_kl = canonicalize_club(kl, sp, ref_clubs, ref_athletes)
print("After canonicalize_club:", canon_kl)

