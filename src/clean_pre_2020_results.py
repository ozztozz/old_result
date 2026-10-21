# -*- coding: utf-8 -*-
"""
clean_pre_2020_results.py
=========================
Kullanıcı talebi doğrultusunda:
Veritabanını güncel tutmak için 2020 öncesi (< 2020) tüm yarış sonuçlarını temizler.

İşlem Adımları:
1. 2020 öncesi yarış sonuçlarını (yaris_sonuclari) siler.
2. 2020 sonrasında hiç yarışı kalmayan eski sporcuları (sporcular) ve kulüpleri (kulupler) temizler.
3. Kalan sporcu-kulüp tarihçelerini (sporcu_kulup_tarihce) günceller.
4. Kalan sporcuların ve kulüplerin toplam yarış, tarih aralıkları ve aktif kulüp bilgilerini yeniden hesaplar.
5. Veritabanı dosyasını VACUUM ederek disk boyutunu küçültür.
"""

import sqlite3
import os
import re
import time
from collections import defaultdict, Counter

DB_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "output", "yuzme_veritabani.db")

def get_race_year(fname: str, mname: str, dstart: str) -> int | None:
    if dstart and len(dstart) >= 4 and dstart[:4].isdigit():
        return int(dstart[:4])
    text = f"{fname or ''} {mname or ''}"
    matches = re.findall(r'(?:^|[^\d])(20[12]\d)(?:[^\d]|$)', text)
    if matches:
        return int(matches[0])
    return None

def main():
    t0 = time.time()
    print("=" * 70)
    print("          2020 ÖNCESİ YARIŞ SONUÇLARINI TEMİZLEME İŞLEMİ")
    print("=" * 70)

    if not os.path.exists(DB_PATH):
        print(f"[!] HATA: Veritabanı bulunamadı: {DB_PATH}")
        return

    orig_size_mb = os.path.getsize(DB_PATH) / (1024 * 1024)
    print(f"[*] Veritabanı: {DB_PATH} ({orig_size_mb:.2f} MB)")

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    cur.execute("PRAGMA synchronous = OFF;")
    cur.execute("PRAGMA journal_mode = MEMORY;")

    # 1. 2020 öncesi yarışları tespit et
    print("\n>>> ADIM 1: Yarışların tarihleri analiz ediliyor...")
    cur.execute("SELECT id, dosya_adi, musabaka_adi, yaris_tarihi_baslangic FROM yaris_sonuclari")
    all_races = cur.fetchall()

    delete_race_ids = []
    for rid, fname, mname, dstart in all_races:
        yr = get_race_year(fname, mname, dstart)
        if yr is not None and yr < 2020:
            delete_race_ids.append(rid)

    print(f"  -> Toplam yarış: {len(all_races):,}")
    print(f"  -> Silinecek 2020 öncesi yarış sayısı: {len(delete_race_ids):,}")
    print(f"  -> Korunacak 2020+ yarış sayısı: {len(all_races) - len(delete_race_ids):,}")

    # 2. Yarış sonuçlarını sil
    print("\n>>> ADIM 2: 2020 öncesi yarışlar siliniyor...")
    cur.execute("BEGIN TRANSACTION;")
    batch_size = 50000
    for i in range(0, len(delete_race_ids), batch_size):
        batch = [(rid,) for rid in delete_race_ids[i:i + batch_size]]
        cur.executemany("DELETE FROM yaris_sonuclari WHERE id = ?", batch)
        print(f"  -> {min(i + batch_size, len(delete_race_ids)):,} / {len(delete_race_ids):,} silindi...")
    conn.commit()
    print("  [OK] 2020 öncesi yarış sonuçları başarıyla silindi.")

    # 3. 2020 sonrasında hiç yarışı kalmayan sporcuları temizle
    print("\n>>> ADIM 3: 2020+ döneminde hiç yarışı kalmayan sporcular tespit ediliyor...")
    cur.execute("SELECT DISTINCT sporcu_id FROM yaris_sonuclari")
    active_swimmer_ids = set(r[0] for r in cur.fetchall())

    cur.execute("SELECT id FROM sporcular")
    all_swimmer_ids = set(r[0] for r in cur.fetchall())

    obsolete_swimmers = all_swimmer_ids - active_swimmer_ids
    print(f"  -> Silinecek eski sporcu sayısı: {len(obsolete_swimmers):,}")
    print(f"  -> Korunacak güncel sporcu sayısı: {len(active_swimmer_ids):,}")

    cur.execute("BEGIN TRANSACTION;")
    obsolete_swimmer_list = [(sid,) for sid in obsolete_swimmers]
    for i in range(0, len(obsolete_swimmer_list), batch_size):
        cur.executemany("DELETE FROM sporcular WHERE id = ?", obsolete_swimmer_list[i:i + batch_size])
    conn.commit()
    print("  [OK] Eski sporcular temizlendi.")

    # 4. Sporcu - Kulüp Tarihçesini Temizle ve Güncelle
    print("\n>>> ADIM 4: Sporcu - Kulüp Tarihçeleri yeniden hesaplanıyor...")
    cur.execute("DELETE FROM sporcu_kulup_tarihce WHERE sporcu_id NOT IN (SELECT id FROM sporcular)")
    conn.commit()

    # Kalan tarihçelerin yarışlarını topla
    cur.execute("""
    SELECT sporcu_id, kulup_id, 
           COUNT(id) as cnt,
           MIN(yaris_tarihi_baslangic) as min_d,
           MAX(yaris_tarihi_bitis) as max_d
    FROM yaris_sonuclari
    GROUP BY sporcu_id, kulup_id
    """)
    active_histories = cur.fetchall()

    # Mevcut tarihçeyi güncelle veya ekle
    cur.execute("DELETE FROM sporcu_kulup_tarihce")
    conn.commit()

    # Kulüp okul_mu haritası
    cur.execute("SELECT id, okul_mu FROM kulupler")
    club_school_map = {r[0]: r[1] for r in cur.fetchall()}

    athlete_grouped_hist = defaultdict(list)
    for sid, cid, cnt, min_d, max_d in active_histories:
        athlete_grouped_hist[sid].append((cid, cnt, min_d, max_d))

    history_insert_rows = []
    h_counter = 1
    for sid, clist in athlete_grouped_hist.items():
        # Okul olmayanlar arasından en son tarihli olanı aktif seç
        non_schools = [item for item in clist if club_school_map.get(item[0], 0) == 0]
        if non_schools:
            latest_c_id = max(non_schools, key=lambda x: (x[3] or '', x[1]))[0]
        else:
            latest_c_id = max(clist, key=lambda x: (x[3] or '', x[1]))[0]

        for order_idx, (cid, cnt, min_d, max_d) in enumerate(clist, start=1):
            is_active = 1 if cid == latest_c_id else 0
            history_insert_rows.append((
                h_counter,
                sid,
                cid,
                min_d,
                max_d,
                cnt,
                order_idx,
                is_active
            ))
            h_counter += 1

    cur.execute("BEGIN TRANSACTION;")
    cur.executemany("""
    INSERT INTO sporcu_kulup_tarihce (id, sporcu_id, kulup_id, ilk_yaris_tarihi, son_yaris_tarihi, toplam_yaris_sayisi, donem_sirasi, aktif_kulup_mu)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, history_insert_rows)
    conn.commit()
    print(f"  [OK] {len(history_insert_rows):,} sporcu-kulüp tarihçesi güncellendi.")

    # 5. Kalan Sporcuların İstatistiklerini ve Birincil Kulüplerini Güncelle
    print("\n>>> ADIM 5: Sporcuların birincil kulüpleri ve istatistikleri güncelleniyor...")
    cur.execute("""
    SELECT sporcu_id,
           COUNT(id) as total_races,
           MIN(yaris_tarihi_baslangic) as first_d,
           MAX(yaris_tarihi_bitis) as last_d
    FROM yaris_sonuclari
    GROUP BY sporcu_id
    """)
    swimmer_stats = cur.fetchall()

    swimmer_updates = []
    for sid, tot, fd, ld in swimmer_stats:
        clist = athlete_grouped_hist.get(sid, [])
        non_schools = [item for item in clist if club_school_map.get(item[0], 0) == 0]
        if non_schools:
            top_club_id = max(non_schools, key=lambda x: x[1])[0]
        elif clist:
            top_club_id = max(clist, key=lambda x: x[1])[0]
        else:
            top_club_id = None

        swimmer_updates.append((top_club_id, tot, fd, ld, sid))

    cur.execute("BEGIN TRANSACTION;")
    cur.executemany("""
    UPDATE sporcular 
    SET birincil_kulup_id = ?, toplam_yaris_sayisi = ?, ilk_yaris_tarihi = ?, son_yaris_tarihi = ?
    WHERE id = ?
    """, swimmer_updates)
    conn.commit()
    print("  [OK] Sporcu istatistikleri ve birincil kulüpleri güncellendi.")

    # 6. 2020 sonrasında hiç yarışı kalmayan kulüpleri temizle
    print("\n>>> ADIM 6: 2020+ döneminde hiç yarışı kalmayan kulüpler temizleniyor...")
    cur.execute("SELECT DISTINCT kulup_id FROM yaris_sonuclari WHERE kulup_id IS NOT NULL")
    active_club_ids = set(r[0] for r in cur.fetchall())

    cur.execute("SELECT id FROM kulupler")
    all_club_ids = set(r[0] for r in cur.fetchall())

    obsolete_clubs = all_club_ids - active_club_ids
    print(f"  -> Silinecek eski kulüp sayısı: {len(obsolete_clubs):,}")
    print(f"  -> Korunacak güncel kulüp sayısı: {len(active_club_ids):,}")

    cur.execute("BEGIN TRANSACTION;")
    obsolete_club_list = [(cid,) for cid in obsolete_clubs]
    for i in range(0, len(obsolete_club_list), batch_size):
        cur.executemany("DELETE FROM kulupler WHERE id = ?", obsolete_club_list[i:i + batch_size])
    conn.commit()
    print("  [OK] Eski kulüpler temizlendi.")

    # 7. Kalan Kulüplerin İstatistiklerini Güncelle
    print("\n>>> ADIM 7: Kulüplerin toplam yarış ve sporcu sayıları güncelleniyor...")
    cur.execute("""
    SELECT kulup_id,
           COUNT(id) as total_races,
           COUNT(DISTINCT sporcu_id) as total_swimmers,
           MIN(yaris_tarihi_baslangic) as first_d,
           MAX(yaris_tarihi_bitis) as last_d
    FROM yaris_sonuclari
    WHERE kulup_id IS NOT NULL
    GROUP BY kulup_id
    """)
    club_stats_res = cur.fetchall()

    club_updates = []
    for cid, tot_races, tot_swimmers, fd, ld in club_stats_res:
        club_updates.append((tot_swimmers, tot_races, fd, ld, cid))

    cur.execute("BEGIN TRANSACTION;")
    cur.executemany("""
    UPDATE kulupler
    SET toplam_sporcu_sayisi = ?, toplam_yaris_sayisi = ?, ilk_yaris_tarihi = ?, son_yaris_tarihi = ?
    WHERE id = ?
    """, club_updates)
    conn.commit()
    print("  [OK] Kulüp istatistikleri güncellendi.")

    # 8. Veritabanını VACUUM yaparak disk boyutunu küçült
    print("\n>>> ADIM 8: Veritabanı VACUUM ediliyor (Disk alanı geri kazanılıyor)...")
    cur.execute("VACUUM;")
    conn.close()

    new_size_mb = os.path.getsize(DB_PATH) / (1024 * 1024)
    elapsed = time.time() - t0

    print("=" * 70)
    print(f"[+] TEMİZLEME İŞLEMİ TAMAMLANDI ({elapsed:.2f} saniye)")
    print(f"[*] Eski Veritabanı Boyutu : {orig_size_mb:.2f} MB")
    print(f"[*] Yeni Veritabanı Boyutu : {new_size_mb:.2f} MB (Tasarruf: {orig_size_mb - new_size_mb:.2f} MB)")
    print(f"[*] Kalan Güncel Yarış      : {len(all_races) - len(delete_race_ids):,}")
    print(f"[*] Kalan Güncel Sporcu    : {len(active_swimmer_ids):,}")
    print(f"[*] Kalan Güncel Kulüp     : {len(active_club_ids):,}")
    print("=" * 70)

if __name__ == "__main__":
    main()
