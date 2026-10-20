import sqlite3

conn = sqlite3.connect('output/yuzme_veritabani.db')
cur = conn.cursor()

print('=== TABLO SATIR SAYILARI ===')
for table in ['kulupler', 'sporcular', 'sporcu_kulup_tarihce', 'yaris_sonuclari']:
    cur.execute(f'SELECT count(*) FROM {table}')
    print(f'  {table:25s}: {cur.fetchone()[0]:,}')

print('\n=== ÖRNEK SPORCU: Bahar ALTINTOP ===')
cur.execute('''
SELECT s.id, s.sporcu_adi, s.yas_dogum_yili, s.cinsiyet, k.kulup_adi, s.toplam_yaris_sayisi, s.ilk_yaris_tarihi, s.son_yaris_tarihi
FROM sporcular s
JOIN kulupler k ON s.birincil_kulup_id = k.id
WHERE s.sporcu_adi = 'Bahar ALTINTOP'
''')
for r in cur.fetchall():
    print('Sporcu:', r)

print('\n=== Bahar ALTINTOP Kulüp Tarihçesi ===')
cur.execute('''
SELECT h.donem_sirasi, k.kulup_adi, h.ilk_yaris_tarihi, h.son_yaris_tarihi, h.toplam_yaris_sayisi, h.aktif_kulup_mu
FROM sporcu_kulup_tarihce h
JOIN sporcular s ON h.sporcu_id = s.id
JOIN kulupler k ON h.kulup_id = k.id
WHERE s.sporcu_adi = 'Bahar ALTINTOP'
ORDER BY h.donem_sirasi
''')
for r in cur.fetchall():
    status = 'AKTİF' if r[5] else 'GEÇMİŞ'
    print(f'  {r[0]}. Dönem: {r[1]} ({r[2]} -> {r[3]}) | {r[4]} Yarış | [{status}]')

print('\n=== ÖRNEK TRANSFER GEÇMİŞİ OLAN SPORCULAR (3+ KULÜP DEĞİŞTİREN) ===')
cur.execute('''
SELECT s.sporcu_adi, count(h.id) as kulup_sayisi, min(h.ilk_yaris_tarihi), max(h.son_yaris_tarihi), sum(h.toplam_yaris_sayisi)
FROM sporcu_kulup_tarihce h
JOIN sporcular s ON h.sporcu_id = s.id
GROUP BY s.id
HAVING kulup_sayisi >= 3
ORDER BY sum(h.toplam_yaris_sayisi) DESC
LIMIT 3
''')
top_transfers = cur.fetchall()
for ath in top_transfers:
    print(f'\nSporcu: {ath[0]} (Toplam {ath[1]} Farklı Kulüp, {ath[4]} Yarış):')
    cur.execute('''
    SELECT h.donem_sirasi, k.kulup_adi, h.ilk_yaris_tarihi, h.son_yaris_tarihi, h.toplam_yaris_sayisi, h.aktif_kulup_mu
    FROM sporcu_kulup_tarihce h
    JOIN sporcular s ON h.sporcu_id = s.id
    JOIN kulupler k ON h.kulup_id = k.id
    WHERE s.sporcu_adi = ?
    ORDER BY h.donem_sirasi
    ''', (ath[0],))
    for tr in cur.fetchall():
        status = 'AKTİF' if tr[5] else 'GEÇMİŞ'
        print(f'  {tr[0]}. Dönem: {tr[1]} ({tr[2]} -> {tr[3]}) | {tr[4]} Yarış | [{status}]')

print('\n=== EN ÇOK SPORCUSU OLAN İLK 5 KULÜP ===')
cur.execute('''
SELECT id, kulup_adi, toplam_sporcu_sayisi, toplam_yaris_sayisi, ilk_yaris_tarihi, son_yaris_tarihi
FROM kulupler
ORDER BY toplam_sporcu_sayisi DESC
LIMIT 5
''')
for r in cur.fetchall():
    print(f'  [{r[0]}] {r[1]}: {r[2]:,} Sporcu | {r[3]:,} Yarış | {r[4]} -> {r[5]}')

conn.close()

