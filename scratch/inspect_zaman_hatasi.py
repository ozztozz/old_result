import sqlite3

db_path = r'c:\Users\OZDEN\Desktop\old_result\database\yuzme_veritabani.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("SELECT COUNT(*) FROM yaris_sonuclari WHERE zaman_kontrolu = 'ZAMAN_HATASI'")
count = cur.fetchone()[0]
print(f"Count of ZAMAN_HATASI in yaris_sonuclari: {count}")

cur.execute("SELECT DISTINCT zaman_kontrolu, COUNT(*) FROM yaris_sonuclari GROUP BY zaman_kontrolu")
print("\nDistribution of zaman_kontrolu:")
for r in cur.fetchall():
    print(f"  {r[0]}: {r[1]}")

cur.execute("""
    SELECT id, dosya_adi, yaris_no, sira, derece, derece_saniye, ham_satir, uyari_notu 
    FROM yaris_sonuclari 
    WHERE zaman_kontrolu = 'ZAMAN_HATASI' 
    LIMIT 30
""")
rows = cur.fetchall()
print(f"\nSample ZAMAN_HATASI rows (first {len(rows)}):")
for r in rows:
    print(f"ID: {r[0]} | Dosya: {r[1]} | YarisNo: {r[2]} | Sira: {r[3]} | Derece: '{r[4]}' ({r[5]}s) | Uyari: '{r[7]}'")
    print(f"  Ham Satir: '{r[6]}'")

