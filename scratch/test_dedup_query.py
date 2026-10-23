import sqlite3

conn = sqlite3.connect('output/yuzme_veritabani.db')
cursor = conn.cursor()

# Hangi kayıtları sileceğiz?
# Birebir aynı (sporcu_id, musabaka_adi, yaris_tarihi_baslangic, yaris_no, mesafe, stil, derece) gruplarında:
# En iyi kaydı seç:
# Öncelik sırası: 
# 1) puan dolu olan
# 2) sira dolu olan
# 3) baraj dolu olan
# 4) kaynak_turu 'METIN_PDF' > 'IL_TEMSILCILIGI' > 'TARANMIS_OCR'
# 5) en küçük id

query_find_keep_ids = '''
    SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY sporcu_id, musabaka_adi, yaris_tarihi_baslangic, yaris_no, mesafe, stil, derece
                   ORDER BY 
                       (CASE WHEN puan IS NOT NULL AND puan != '' THEN 1 ELSE 0 END) DESC,
                       (CASE WHEN sira IS NOT NULL AND sira != '' THEN 1 ELSE 0 END) DESC,
                       (CASE WHEN baraj IS NOT NULL AND baraj != '' THEN 1 ELSE 0 END) DESC,
                       (CASE WHEN kaynak_turu = 'METIN_PDF' THEN 3 WHEN kaynak_turu = 'IL_TEMSILCILIGI' THEN 2 ELSE 1 END) DESC,
                       id ASC
               ) as rn
        FROM yaris_sonuclari
        WHERE musabaka_adi IS NOT NULL
    ) WHERE rn = 1
'''

cursor.execute(f'''
    SELECT COUNT(*) FROM yaris_sonuclari
    WHERE musabaka_adi IS NOT NULL
      AND id NOT IN ({query_find_keep_ids})
''')
to_delete_count = cursor.fetchone()[0]
print(f"Silinecek yarış sonucu kaydı: {to_delete_count}")

