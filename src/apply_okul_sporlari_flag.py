# -*- coding: utf-8 -*-
"""
apply_okul_sporlari_flag.py
===========================
Kullanıcı direktifi:
"yarış isimlerinde Okul Sporları ibaresi yer alan takımların hepsini okul olarak işaretleyebilirsin."

Bu script:
1. 'kulupler' tablosuna 'okul_mu' (INTEGER DEFAULT 0) sütunu ekler.
2. Yarış isimlerinde 'Okul Sporları' geçen tüm müsabakalardaki takımları (ve okul formatındaki isimleri)
   okul_mu = 1 olarak işaretler. (Büyük tescilli federasyon kulüpleri istisna tutulur).
3. 'sporcu_kulup_tarihce' tablosundaki 'aktif_kulup_mu' bayraklarını ve 'sporcular' tablosundaki
   'birincil_kulup_id' değerlerini resmi kulüplere (okul_mu = 0) öncelik verecek şekilde günceller.
"""

import sqlite3
import os
import re
from collections import defaultdict

DB_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "output", "yuzme_veritabani.db")

def is_school_name(name: str) -> bool:
    nl = name.lower()
    return bool(re.search(
        r'(?:ilkokul|ortaokul|lise|imam\s*hatip|i\.?[oö]\.?okulu|kolej|okullar[ıi]|anaokul|bilsen|bilsem|kamp[uü]s|okulu$|lisesi$|koleji$)',
        nl
    ))

def has_real_club_suffix(name: str) -> bool:
    nl = name.lower()
    return bool(re.search(
        r'(?:spor\s*kul[uü]b[uü]|(?:\b|[_\s])sk\b|(?:\b|[_\s])gsk\b|(?:\b|[_\s])skd\b|y[uü]zme\s*kul[uü]b[uü]|ihtisas|derne[gğ]i|belediye\s*spor|belediyespor|kolejliler)',
        nl
    ))

def main():
    print(f"Veritabani baglaniyor: {DB_PATH}")
    if not os.path.exists(DB_PATH):
        print(f"HATA: {DB_PATH} bulunamadi!")
        return

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # 1. Sütun kontrolü ve ekleme
    cur.execute("PRAGMA table_info(kulupler)")
    col_names = [c[1] for c in cur.fetchall()]
    if 'okul_mu' not in col_names:
        print(">>> 1. 'kulupler' tablosuna 'okul_mu' sutunu ekleniyor...")
        cur.execute("ALTER TABLE kulupler ADD COLUMN okul_mu INTEGER DEFAULT 0;")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_kulupler_okul_mu ON kulupler(okul_mu);")
        conn.commit()
        print("  [OK] 'okul_mu' sutunu eklendi.")
    else:
        print(">>> 1. 'okul_mu' sutunu zaten mevcut.")

    # 2. Kulüplerin yarış istatistiklerini hesapla
    print("\n>>> 2. 'Okul Sporları' yarislarinda yer alan takimlar analiz ediliyor...")
    cur.execute("""
    SELECT k.id, k.kulup_adi,
           SUM(CASE WHEN lower(y.musabaka_adi) LIKE '%okul%spor%' 
                      OR lower(y.musabaka_adi) LIKE '%okulspor%' 
                      OR lower(y.musabaka_adi) LIKE '%okullar%' THEN 1 ELSE 0 END) as okul_races,
           SUM(CASE WHEN NOT (lower(y.musabaka_adi) LIKE '%okul%spor%' 
                           OR lower(y.musabaka_adi) LIKE '%okulspor%' 
                           OR lower(y.musabaka_adi) LIKE '%okullar%') THEN 1 ELSE 0 END) as fed_races
    FROM kulupler k
    JOIN yaris_sonuclari y ON k.id = y.kulup_id
    GROUP BY k.id, k.kulup_adi
    """)
    club_stats = cur.fetchall()

    school_ids = []
    club_ids = []

    for cid, cname, okul_races, fed_races in club_stats:
        if cname.lower() == 'ferdi':
            club_ids.append(cid)
            continue
        in_school_meet = (okul_races > 0)
        has_school_kw = is_school_name(cname)
        has_sk = has_real_club_suffix(cname)

        # Okul Sporları yarışlarında yarışanlar:
        if in_school_meet:
            # Büyük tescilli federasyon kulüpleri istisna:
            if has_sk and fed_races > okul_races and fed_races >= 50:
                club_ids.append(cid)
            else:
                school_ids.append(cid)
        elif has_school_kw and not has_sk:
            school_ids.append(cid)
        else:
            club_ids.append(cid)

    # Hiç yarışı olmayan kulüpler (varsa) isimlerinden kontrol et
    cur.execute("SELECT id, kulup_adi FROM kulupler WHERE id NOT IN (SELECT DISTINCT kulup_id FROM yaris_sonuclari WHERE kulup_id IS NOT NULL)")
    empty_clubs = cur.fetchall()
    for cid, cname in empty_clubs:
        if is_school_name(cname) and not has_real_club_suffix(cname):
            school_ids.append(cid)
        else:
            club_ids.append(cid)

    print(f"  -> Toplam {len(school_ids):,} kurum/takim OKUL olarak isaretleniyor...")
    print(f"  -> Toplam {len(club_ids):,} kurum RESMI SPOR KULUBU olarak kaydediliyor...")

    cur.execute("BEGIN TRANSACTION;")
    # Reset all to 0 first
    cur.execute("UPDATE kulupler SET okul_mu = 0;")
    # Set school_ids to 1
    cur.executemany("UPDATE kulupler SET okul_mu = 1 WHERE id = ?", [(sid,) for sid in school_ids])
    conn.commit()
    print("  [OK] 'okul_mu' bayraklari basariyla guncellendi.")

    # 3. Sporcu - Kulüp Tarihçesi Düzeltmesi (aktif_kulup_mu)
    print("\n>>> 3. Sporcu-Kulup tarihcesindeki 'aktif_kulup_mu' bayraklari okul_mu degerine gore guncelleniyor...")
    school_set = set(school_ids)

    cur.execute("SELECT id, sporcu_id, kulup_id, son_yaris_tarihi, toplam_yaris_sayisi, aktif_kulup_mu FROM sporcu_kulup_tarihce")
    all_hist = cur.fetchall()

    athlete_hist = defaultdict(list)
    for r in all_hist:
        athlete_hist[r[1]].append(r)

    reset_active_ids = []
    set_active_ids = []

    for s_id, hlist in athlete_hist.items():
        curr_active = [h for h in hlist if h[5] == 1]
        curr_hist_id = curr_active[0][0] if curr_active else None

        # Resmi kulüpler (okul_mu = 0) arasından en son tarihli olan
        non_schools = [h for h in hlist if h[2] not in school_set]
        if non_schools:
            best = max(non_schools, key=lambda x: (x[3] or '', x[4]))
        else:
            best = max(hlist, key=lambda x: (x[3] or '', x[4]))

        new_hist_id = best[0]
        if curr_hist_id != new_hist_id:
            if curr_hist_id:
                reset_active_ids.append(curr_hist_id)
            set_active_ids.append(new_hist_id)

    print(f"  -> {len(set_active_ids):,} sporcunun aktif kulup bayragi resmi kulube yonlendiriliyor...")
    cur.execute("BEGIN TRANSACTION;")
    if reset_active_ids:
        cur.executemany("UPDATE sporcu_kulup_tarihce SET aktif_kulup_mu = 0 WHERE id = ?", [(hid,) for hid in reset_active_ids])
    if set_active_ids:
        cur.executemany("UPDATE sporcu_kulup_tarihce SET aktif_kulup_mu = 1 WHERE id = ?", [(hid,) for hid in set_active_ids])
    conn.commit()
    print("  [OK] Aktif kulup bayraklari guncellendi.")

    # 4. Sporcular Tablosu Birincil Kulüp Düzeltmesi
    print("\n>>> 4. Sporcular tablosundaki 'birincil_kulup_id' degerleri resmi kulup oncelikli guncelleniyor...")
    cur.execute("SELECT id, birincil_kulup_id FROM sporcular")
    swimmers = cur.fetchall()

    cur.execute("SELECT sporcu_id, kulup_id, toplam_yaris_sayisi FROM sporcu_kulup_tarihce")
    all_hist2 = cur.fetchall()
    athlete_hist2 = defaultdict(list)
    for r in all_hist2:
        athlete_hist2[r[0]].append((r[1], r[2]))

    birincil_updates = []
    for s_id, b_id in swimmers:
        if b_id in school_set:
            hlist = athlete_hist2.get(s_id, [])
            non_schools = [h for h in hlist if h[0] not in school_set]
            if non_schools:
                best = max(non_schools, key=lambda x: x[1])
                birincil_updates.append((best[0], s_id))

    print(f"  -> {len(birincil_updates):,} sporcunun birincil kulubu resmi kulup ile guncelleniyor...")
    cur.execute("BEGIN TRANSACTION;")
    if birincil_updates:
        cur.executemany("UPDATE sporcular SET birincil_kulup_id = ? WHERE id = ?", birincil_updates)
    conn.commit()
    print("  [OK] Birincil kulup degerleri guncellendi.")

    conn.close()
    print("\n>>> ISLEM BASARIYLA TAMAMLANDI!")

if __name__ == "__main__":
    main()

