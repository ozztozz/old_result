import sqlite3
import re

db_path = r'c:\Users\OZDEN\Desktop\old_result\database\yuzme_veritabani.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("SELECT id, dosya_adi, mesafe, stil, sira, derece, derece_saniye, puan, ham_satir, uyari_notu, zaman_kontrolu FROM yaris_sonuclari WHERE id = 470590")
r = cur.fetchone()
print("Record 470590:")
print(f"  ID: {r[0]}")
print(f"  Dosya: {r[1]}")
print(f"  Mesafe: {r[2]}m {r[3]}")
print(f"  Sıra: {r[4]}")
print(f"  Derece: {r[5]} ({r[6]}s)")
print(f"  Puan: {r[7]}")
print(f"  Zaman Kontrolü: {r[10]}")
print(f"  Uyarı: {r[9]}")
print(f"  Ham Satır: '{r[8]}'")

# Şimdi ham satırda [dakika:]saniye.salise arayalım:
# '2:21.44n375' içindeki '2:21.44'
matches = re.findall(r'(\d{1,2}:[0-5]\d\.\d{2})', r[8])
print("\nFound mm:ss.xx times in ham_satir:", matches)

