import sqlite3
import re

db_path = r'c:\Users\OZDEN\Desktop\old_result\database\yuzme_veritabani.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("""
    SELECT id, dosya_adi, yaris_no, sira, derece, derece_saniye, ham_satir, uyari_notu 
    FROM yaris_sonuclari 
    WHERE zaman_kontrolu = 'ZAMAN_HATASI'
""")
rows = cur.fetchall()

no_time_rows = []
for r in rows:
    rid, dosya, yno, sira, derece, d_sec, ham, uyari = r
    times = re.findall(r'\b(?:\d+:)?\d{1,2}\.\d{2}\b', ham or '')
    if not times:
        no_time_rows.append(r)

print(f"Total rows where no standard time regex matched in ham_satir: {len(no_time_rows)}")
for r in no_time_rows[:20]:
    print(f"ID: {r[0]} | Derece: '{r[4]}' | Uyari: '{r[7]}'")
    print(f"   Ham: '{r[6]}'")

