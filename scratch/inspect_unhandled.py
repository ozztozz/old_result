import sqlite3
import re
from scratch.test_rescue_algorithm import extract_swimmer_data_from_ham, time_to_sec, is_realistic

db_path = r'c:\Users\OZDEN\Desktop\old_result\database\yuzme_veritabani.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("""
    SELECT id, mesafe, stil, ham_satir, uyari_notu
    FROM yaris_sonuclari
    WHERE (uyari_notu LIKE '%uyumsuz ara zaman%' OR uyari_notu LIKE '%Diskalifiye/Terk%')
""")
rows = cur.fetchall()

unhandled = []
for r in rows:
    rid, mes, stl, ham, uyari = r
    if 'Diskalifiye/Terk: SW' in uyari or 'Diskalifiye/Terk: DQ' in uyari or 'Diskalifiye/Terk: disk' in uyari:
        continue
    ext = extract_swimmer_data_from_ham(ham, mes)
    if not ext:
        unhandled.append((rid, mes, stl, ham, uyari))

print(f"Total unhandled rows: {len(unhandled)}")
for u in unhandled[:20]:
    print(f"ID {u[0]} ({u[1]}m {u[2]}):")
    print(f"   Ham: '{u[3]}'")

