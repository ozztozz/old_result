import sqlite3

conn = sqlite3.connect('output/yuzme_veritabani.db')
cursor = conn.cursor()

# Start listesi kaydı ('Bekleniyor') olup aynı yarışta gerçek sonuç da girilmiş olanlar:
cursor.execute('''
    SELECT s.id, r.id, s.sporcu_id, s.musabaka_adi, s.mesafe, s.stil, r.derece
    FROM yaris_sonuclari s
    JOIN yaris_sonuclari r ON s.sporcu_id = r.sporcu_id 
        AND s.musabaka_adi = r.musabaka_adi 
        AND s.mesafe = r.mesafe 
        AND s.stil = r.stil
        AND (s.yaris_no = r.yaris_no OR s.yaris_no IS NULL OR r.yaris_no IS NULL)
        AND s.id != r.id
    WHERE s.derece = 'Bekleniyor' AND r.derece != 'Bekleniyor'
''')
start_vs_result = cursor.fetchall()
print(f"'Bekleniyor' olup gerçek derecesi de mevcut olan çiftler: {len(start_vs_result)}")

