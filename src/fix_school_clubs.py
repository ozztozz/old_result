# -*- coding: utf-8 -*-
"""
Okul müsabakalarında (MEB Okul Sporları) kulüp hanesinde yer alan okul takımlarını
(İlkokulu, Ortaokulu, Lisesi, Kolej vb.) tespit ederek;
1. sporcu_kulup_tarihce tablosundaki 'aktif_kulup_mu' bayrağını resmi spor kulüplerine öncelik verecek şekilde düzeltir.
2. sporcular tablosundaki 'birincil_kulup_id' değerini resmi spor kulüplerine öncelik verecek şekilde düzeltir.
"""

import sqlite3
import os
import re
from collections import defaultdict

DB_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "output", "yuzme_veritabani.db")

def is_school_team(club_name: str) -> bool:
    if not club_name:
        return False
    name = club_name.strip()
    name_lower = name.lower()

    if name_lower == 'ferdi':
        return False

    # Resmi tescilli kulüp belirteçleri (bu ekler varsa okulla ilişkili olsa dahi resmi kulüptür)
    has_club_suffix = bool(re.search(
        r'(?:spor\s*kul[uü]b[uü]|(?:\b|[_\s])sk\b|(?:\b|[_\s])gsk\b|(?:\b|[_\s])skd\b|y[uü]zme\s*kul[uü]b[uü]|ihtisas|derne[gğ]i|belediye\s*spor|belediyespor|kolejliler)', 
        name_lower
    ))
    if has_club_suffix:
        return False

    # Okul / MEB anahtar kelimeleri
    has_school_word = bool(re.search(
        r'(?:ilkokul|ortaokul|lise|imam\s*hatip|i\.?[oö]\.?okulu|kolej|okullar[ıi]|anaokul|bilsen|bilsem|kamp[uü]s)',
        name_lower
    ))
    if has_school_word:
        return True

    if re.search(r'(?:okulu|lisesi|koleji)$', name_lower):
        return True

    return False

def main():
    print(f"Veritabanı bağlanıyor: {DB_PATH}")
    if not os.path.exists(DB_PATH):
        print(f"HATA: {DB_PATH} bulunamadı!")
        return

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    cur.execute("SELECT id, kulup_adi FROM kulupler")
    clubs = {r[0]: r[1] for r in cur.fetchall()}
    print(f"Toplam kulüp sayısı: {len(clubs)}")

    # 1. Sporcu - Kulüp Tarihçesi Düzeltmesi (aktif_kulup_mu)
    print("\n>>> 1. Sporcu-Kulüp tarihçesindeki 'aktif_kulup_mu' bayrakları güncelleniyor...")
    cur.execute("SELECT id, sporcu_id, kulup_id, son_yaris_tarihi, toplam_yaris_sayisi, aktif_kulup_mu FROM sporcu_kulup_tarihce")
    all_hist = cur.fetchall()

    athlete_hist = defaultdict(list)
    for r in all_hist:
        athlete_hist[r[1]].append(r)

    active_updates = []
    reset_active_ids = []
    set_active_ids = []

    for s_id, hlist in athlete_hist.items():
        curr_active = [h for h in hlist if h[5] == 1]
        curr_hist_id = curr_active[0][0] if curr_active else None

        # Resmi kulüpler arasından en son tarihli olan
        non_schools = [h for h in hlist if not is_school_team(clubs.get(h[2], ''))]
        if non_schools:
            best = max(non_schools, key=lambda x: (x[3] or '', x[4]))
        else:
            best = max(hlist, key=lambda x: (x[3] or '', x[4]))

        new_hist_id = best[0]
        if curr_hist_id != new_hist_id:
            if curr_hist_id:
                reset_active_ids.append(curr_hist_id)
            set_active_ids.append(new_hist_id)

    print(f"  -> {len(set_active_ids):,} sporcunun aktif kulübü okuldan resmi kulübe geçiriliyor...")

    # Batch update
    cur.execute("BEGIN TRANSACTION;")
    if reset_active_ids:
        cur.executemany("UPDATE sporcu_kulup_tarihce SET aktif_kulup_mu = 0 WHERE id = ?", [(hid,) for hid in reset_active_ids])
    if set_active_ids:
        cur.executemany("UPDATE sporcu_kulup_tarihce SET aktif_kulup_mu = 1 WHERE id = ?", [(hid,) for hid in set_active_ids])
    conn.commit()
    print("  [OK] Aktif kulup guncellemeleri tamamlandi.")

    # 2. Sporcular Tablosu Birincil Kulüp Düzeltmesi
    print("\n>>> 2. Sporcular tablosundaki 'birincil_kulup_id' değerleri güncelleniyor...")
    cur.execute("SELECT id, birincil_kulup_id FROM sporcular")
    swimmers = cur.fetchall()

    cur.execute("SELECT sporcu_id, kulup_id, toplam_yaris_sayisi FROM sporcu_kulup_tarihce")
    all_hist2 = cur.fetchall()
    athlete_hist2 = defaultdict(list)
    for r in all_hist2:
        athlete_hist2[r[0]].append((r[1], r[2]))

    birincil_updates = []
    for s_id, b_id in swimmers:
        curr_name = clubs.get(b_id, '')
        if is_school_team(curr_name):
            hlist = athlete_hist2.get(s_id, [])
            non_schools = [h for h in hlist if not is_school_team(clubs.get(h[0], ''))]
            if non_schools:
                best = max(non_schools, key=lambda x: x[1])
                birincil_updates.append((best[0], s_id))

    print(f"  -> {len(birincil_updates):,} sporcunun birincil kulübü resmi kulüp ile güncelleniyor...")
    cur.execute("BEGIN TRANSACTION;")
    if birincil_updates:
        cur.executemany("UPDATE sporcular SET birincil_kulup_id = ? WHERE id = ?", birincil_updates)
    conn.commit()
    print("  [OK] Birincil kulup guncellemeleri tamamlandi.")

    conn.close()
    print("\n>>> Tüm işlemler başarıyla kaydedildi!")

if __name__ == "__main__":
    main()
