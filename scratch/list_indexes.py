import sqlite3

conn = sqlite3.connect('output/yuzme_veritabani.db')
cursor = conn.cursor()

cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='yaris_sonuclari'")
print("yaris_sonuclari İndeksleri:")
for r in cursor.fetchall():
    print(r)

