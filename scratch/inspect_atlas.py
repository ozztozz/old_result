import csv

with open('output/tyf_scanned_bireysel_yuzucu_sonuclari.csv', encoding='utf-8-sig') as f:
    for i, r in enumerate(csv.DictReader(f)):
        if 'ATLAS' in r['Sporcu'].upper() and 'SEYHAN' in r['Sporcu'].upper():
            print(f"Row {i}: File={r['Dosya Adı']} | Sp={r['Sporcu']} | Yaş={r['Yaş']} | Kulüp={r['Kulüp']}")

