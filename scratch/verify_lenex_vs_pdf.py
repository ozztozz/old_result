#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import zipfile
import sqlite3
import xml.etree.ElementTree as ET
import re

# 1. Parse Lenex
z = zipfile.ZipFile('scratch/test_tyf/results.lxf')
root = ET.fromstring(z.read('results.lef').decode('utf-8'))

events_map = {}
for ev in root.findall('.//EVENT'):
    eid = ev.get('eventid')
    num = ev.get('number')
    events_map[eid] = num

lenex_records = []
for club in root.findall('.//CLUB'):
    club_name = club.get('name')
    for athlete in club.findall('.//ATHLETE'):
        fn = athlete.get('firstname') or ''
        ln = athlete.get('lastname') or ''
        full_name = f"{fn} {ln}".strip()
        bd = athlete.get('birthdate') or ''
        gender = athlete.get('gender') or ''

        for res in athlete.findall('.//RESULT'):
            eid = res.get('eventid')
            yaris_no = events_map.get(eid)
            swimtime = res.get('swimtime') # e.g. 00:01:08.85 or 00:00:29.45
            points = res.get('points')
            place = res.get('place')
            heat = res.get('heat')
            lane = res.get('lane')
            reactiontime = res.get('reactiontime')

            # format swimtime into M:SS.xx or SS.xx
            formatted_time = None
            if swimtime and swimtime != '00:00:00.00':
                parts = swimtime.split(':')
                if len(parts) == 3:
                    h, m, s = int(parts[0]), int(parts[1]), float(parts[2])
                    if h == 0 and m == 0:
                        formatted_time = f"{s:05.2f}"
                    elif h == 0:
                        formatted_time = f"{m}:{s:05.2f}"
                    else:
                        formatted_time = f"{h}:{m:02d}:{s:05.2f}"

            lenex_records.append({
                'yaris_no': str(yaris_no),
                'sporcu': full_name,
                'kulup': club_name,
                'birthdate': bd,
                'gender': gender,
                'raw_time': swimtime,
                'time': formatted_time,
                'place': place,
                'points': points,
                'heat': heat,
                'lane': lane
            })

print(f"Lenex toplam yarış kaydı: {len(lenex_records)}")
valid_lenex = [r for r in lenex_records if r['time'] is not None]
print(f"Lenex geçerli derecesi olan (yüzen) sporcu sayısı: {len(valid_lenex)}")

# 2. Query DB records from PDF parsing
conn = sqlite3.connect('output/yuzme_veritabani.db')
cur = conn.cursor()

# Get DB records for this meet
db_rows = cur.execute("""
    SELECT y.yaris_no, s.sporcu_adi, k.kulup_adi, y.derece, y.sira, y.kulvar, y.seri, y.giris_derecesi
    FROM yaris_sonuclari y
    JOIN sporcular s ON y.sporcu_id = s.id
    JOIN kulupler k ON y.kulup_id = k.id
    WHERE y.musabaka_adi LIKE '%11-12%Sem%Baraj%'
""").fetchall()

print(f"Veritabanındaki PDF kaynaklı canlı kayıt sayısı: {len(db_rows)}")

# Let's index DB by (yaris_no, normalized_sporcu_name)
def norm(name):
    s = name.upper().replace('İ', 'I').replace('Ş', 'S').replace('Ğ', 'G').replace('Ü', 'U').replace('Ö', 'O').replace('Ç', 'C')
    return re.sub(r'\s+', ' ', s).strip()

db_map = {}
for r in db_rows:
    y_no, sp_name, kl_name, derece, sira, kulvar, seri, giris = r
    key = (str(y_no), norm(sp_name))
    db_map[key] = {
        'sp_name': sp_name,
        'kl_name': kl_name,
        'derece': derece,
        'sira': sira,
        'kulvar': kulvar,
        'seri': seri,
        'giris': giris
    }

# 3. Compare valid Lenex with DB
matched = 0
time_matched = 0
unmatched_in_db = []

for lr in valid_lenex:
    key = (str(lr['yaris_no']), norm(lr['sporcu']))
    if key in db_map:
        matched += 1
        db_rec = db_map[key]
        # Compare time
        # Lenex time e.g. 1:08.85 vs DB e.g. 1:08.85
        # Lenex time e.g. 29.45 vs DB e.g. 29.45
        lt = lr['time'].lstrip('0') if lr['time'].startswith('0') else lr['time']
        dt = (db_rec['derece'] or '').lstrip('0') if (db_rec['derece'] or '').startswith('0') else (db_rec['derece'] or '')
        if lt == dt or float(lr['raw_time'].split(':')[-1]) == (float(dt.split(':')[-1]) if ':' in dt else 0):
            time_matched += 1
        else:
            # print mismatch sample
            if len(unmatched_in_db) < 5:
                print(f"Zaman farkı: {lr['sporcu']} | Lenex: {lr['time']} ({lr['raw_time']}) vs DB: {db_rec['derece']}")
    else:
        unmatched_in_db.append(lr)

print(f"\n--- KARŞILAŞTIRMA SONUCU ---")
print(f"Lenex'te derecesi olan sporcu sayısı : {len(valid_lenex)}")
print(f"PDF'ten veritabanına eşleşen sporcu   : {matched} (%{matched/len(valid_lenex)*100:.2f})")
print(f"Birebir derece uyuşması             : {time_matched}")
print(f"Veritabanında bulunamayan sporcu     : {len(unmatched_in_db)}")

if unmatched_in_db:
    print(f"\nBulunamayan ilk 5 sporcu örneği:")
    for u in unmatched_in_db[:5]:
        print(f"  Yarış #{u['yaris_no']} - {u['sporcu']} ({u['kulup']}) - Derece: {u['time']}")
