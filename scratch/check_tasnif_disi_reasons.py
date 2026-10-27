import sqlite3

db_path = r'c:\Users\OZDEN\Desktop\old_result\database\yuzme_veritabani.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("""
    SELECT uyari_notu, COUNT(*) 
    FROM yaris_sonuclari 
    WHERE zaman_kontrolu = 'TASNİF_DIŞI'
    GROUP BY uyari_notu
""")
for r in cur.fetchall():
    print(f"Uyarı: '{r[0]}' -> {r[1]} adet")

