import sqlite3

conn = sqlite3.connect('output/yuzme_veritabani.db')
cursor = conn.cursor()

cursor.execute('''
    SELECT sporcu_id, musabaka_adi, yaris_tarihi_baslangic, yaris_no, mesafe, stil, derece
    FROM yaris_sonuclari
    GROUP BY sporcu_id, musabaka_adi, yaris_tarihi_baslangic, yaris_no, mesafe, stil, derece
    HAVING COUNT(*) > 1
    LIMIT 5
''')
groups = cursor.fetchall()

for g in groups:
    print("\n--- GRUP ---", g[0], g[1][:30], g[4], g[5], g[6])
    cursor.execute('''
        SELECT id, sira, seri, kulvar, derece, derece_saniye, puan, baraj, kaynak_turu, dosya_adi
        FROM yaris_sonuclari
        WHERE sporcu_id = ? AND musabaka_adi = ? AND yaris_tarihi_baslangic = ? 
          AND yaris_no = ? AND mesafe = ? AND stil = ? AND derece = ?
    ''', g)
    for row in cursor.fetchall():
        print(" ", row)

