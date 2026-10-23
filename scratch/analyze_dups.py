import sqlite3

conn = sqlite3.connect('output/yuzme_veritabani.db')
cursor = conn.cursor()

cursor.execute('''
    SELECT y1.kaynak_turu, COUNT(*)
    FROM yaris_sonuclari y1
    WHERE y1.id IN (
        SELECT id FROM yaris_sonuclari
        WHERE id NOT IN (
            SELECT MIN(id)
            FROM yaris_sonuclari
            WHERE musabaka_adi IS NOT NULL
            GROUP BY sporcu_id, musabaka_adi, yaris_tarihi_baslangic, yaris_no, mesafe, stil, derece
        )
    )
    GROUP BY y1.kaynak_turu
''')
print("Kaynak Türüne Göre Silinebilecek Fazlalıklar:")
for r in cursor.fetchall():
    print(r)

