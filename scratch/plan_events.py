import sqlite3

conn = sqlite3.connect('output/yuzme_veritabani.db')
cursor = conn.cursor()

cursor.execute("SELECT COUNT(*) FROM yaris_sonuclari WHERE musabaka_adi IS NULL OR musabaka_adi = ''")
print("Boş musabaka_adi sayısı:", cursor.fetchone()[0])

cursor.execute('''
    SELECT 
        musabaka_adi,
        sehir,
        yaris_tarihi_baslangic,
        yaris_tarihi_bitis,
        yaris_tarihi_ham,
        kaynak_turu,
        COUNT(*) as yaris_sayisi,
        COUNT(DISTINCT sporcu_id) as sporcu_sayisi
    FROM yaris_sonuclari
    GROUP BY musabaka_adi, sehir, yaris_tarihi_baslangic, yaris_tarihi_bitis
    ORDER BY yaris_tarihi_baslangic DESC
''')
events = cursor.fetchall()
print(f"Oluşturulacak toplam Event sayısı: {len(events)}")
print("\nÖrnek ilk 5 Event:")
for e in events[:5]:
    print(f"- {e[0]} | {e[1]} | {e[2]} - {e[3]} | Yarış: {e[6]} | Sporcu: {e[7]}")

