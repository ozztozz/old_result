# -*- coding: utf-8 -*-
"""
clean_database_duplicates.py
============================
Veritabanındaki mükerrer kayıtları güvenle temizler ve istatistikleri günceller:
1. yaris_sonuclari: Birebir aynı (sporcu, müsabaka, tarih, yarış no, mesafe, stil, derece) kayıtlar
   arasında en kaliteli olanı (puan/sıra/baraj bilgisi dolu olan, METIN_PDF kaynaklı olan) korur,
   54.992 fazlalık kaydı siler.
2. kulupler: Aynı isimli mükerrer kulüpleri ana kulübe bağlar ve fazlalıkları siler.
3. sporcular: İ/I ve büyük harf farklılığından mükerrer açılmış sporcuları birleştirir.
4. İstatistikleri yeniden hesaplar (sporcu toplam yarış sayısı, kulüp yarış ve sporcu sayısı).
5. VACUUM ile veritabanını optimize eder.
"""

import sqlite3
import time
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

def run_cleanup():
    db_path = "output/yuzme_veritabani.db"
    print(f"[*] Veritabanı açılıyor: {db_path}")
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    try:
        t_start = time.time()

        # =========================================================================
        # ADIM 1: YARIS_SONUCLARI MÜKERRER KAYITLARINI TEMİZLE
        # =========================================================================
        print("\n--- ADIM 1: Yaris Sonuclari Mükerrer Temizliği ---")
        cursor.execute("SELECT COUNT(*) FROM yaris_sonuclari")
        initial_race_count = cursor.fetchone()[0]
        print(f"Başlangıç yarış sayısı: {initial_race_count}")

        # Geçici tablo ile silinecek ID'leri topla (hızlı ve güvenli)
        cursor.execute("DROP TABLE IF EXISTS temp_delete_race_ids")
        cursor.execute('''
            CREATE TEMP TABLE temp_delete_race_ids AS
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
            ) WHERE rn > 1
        ''')
        cursor.execute("SELECT COUNT(*) FROM temp_delete_race_ids")
        del_race_count = cursor.fetchone()[0]
        print(f"Tespit edilen mükerrer yarış kaydı sayısı: {del_race_count}")

        if del_race_count > 0:
            cursor.execute('''
                DELETE FROM yaris_sonuclari 
                WHERE id IN (SELECT id FROM temp_delete_race_ids)
            ''')
            print(f"[OK] {del_race_count} mükerrer yarış kaydı başarıyla silindi.")
        cursor.execute("DROP TABLE IF EXISTS temp_delete_race_ids")

        cursor.execute("SELECT COUNT(*) FROM yaris_sonuclari")
        after_race_count = cursor.fetchone()[0]
        print(f"Kalan yarış sayısı: {after_race_count}")

        # =========================================================================
        # ADIM 2: MÜKERRER KULÜPLERİ BİRLEŞTİR
        # =========================================================================
        print("\n--- ADIM 2: Mükerrer Kulüplerin Birleştirilmesi ---")
        cursor.execute('''
            SELECT LOWER(TRIM(kulup_adi)), COUNT(*), GROUP_CONCAT(id)
            FROM kulupler
            GROUP BY LOWER(TRIM(kulup_adi))
            HAVING COUNT(*) > 1
        ''')
        dup_clubs = cursor.fetchall()
        merged_clubs_count = 0
        for norm_name, count, id_str in dup_clubs:
            ids = [int(x) for x in id_str.split(",")]
            keep_id = ids[0]
            remove_ids = ids[1:]
            for rem_id in remove_ids:
                cursor.execute("UPDATE yaris_sonuclari SET kulup_id = ? WHERE kulup_id = ?", (keep_id, rem_id))
                cursor.execute("UPDATE sporcular SET birincil_kulup_id = ? WHERE birincil_kulup_id = ?", (keep_id, rem_id))
                cursor.execute("UPDATE OR IGNORE sporcu_kulup_tarihce SET kulup_id = ? WHERE kulup_id = ?", (keep_id, rem_id))
                cursor.execute("DELETE FROM sporcu_kulup_tarihce WHERE kulup_id = ?", (rem_id,))
                cursor.execute("DELETE FROM kulupler WHERE id = ?", (rem_id,))
                merged_clubs_count += 1

        print(f"[OK] {merged_clubs_count} mükerrer kulüp kaydı ana kulübe birleştirildi.")

        # =========================================================================
        # ADIM 3: MÜKERRER SPORCULARI BİRLEŞTİR
        # =========================================================================
        print("\n--- ADIM 3: Mükerrer Sporcuların Birleştirilmesi ---")
        def norm_name(s):
            if not s: return ''
            s = s.replace('İ', 'I').replace('ı', 'i').replace('Ş', 'S').replace('ş', 's').replace('Ğ', 'G').replace('ğ', 'g').replace('Ü', 'U').replace('ü', 'u').replace('Ö', 'O').replace('ö', 'o').replace('Ç', 'C').replace('ç', 'c')
            return ' '.join(s.upper().split())

        cursor.execute('SELECT id, sporcu_adi, dogum_yili FROM sporcular')
        athletes = cursor.fetchall()
        groups = {}
        for aid, name, byear in athletes:
            key = (norm_name(name), str(byear or ''))
            groups.setdefault(key, []).append(aid)

        merged_athletes_count = 0
        for key, ids in groups.items():
            if len(ids) > 1:
                keep_id = min(ids)
                remove_ids = [i for i in ids if i != keep_id]
                for rem_id in remove_ids:
                    cursor.execute("UPDATE yaris_sonuclari SET sporcu_id = ? WHERE sporcu_id = ?", (keep_id, rem_id))
                    cursor.execute("UPDATE OR IGNORE sporcu_kulup_tarihce SET sporcu_id = ? WHERE sporcu_id = ?", (keep_id, rem_id))
                    cursor.execute("DELETE FROM sporcu_kulup_tarihce WHERE sporcu_id = ?", (rem_id,))
                    cursor.execute("DELETE FROM sporcular WHERE id = ?", (rem_id,))
                    merged_athletes_count += 1

        print(f"[OK] {merged_athletes_count} mükerrer sporcu ana sporcu kaydıyla birleştirildi.")

        # =========================================================================
        # ADIM 4: SPORCU VE KULÜP YARIŞ SAYAÇLARINI GÜNCELLE
        # =========================================================================
        print("\n--- ADIM 4: Sayaçların ve İstatistiklerin Güncellenmesi ---")
        cursor.execute('''
            UPDATE sporcular
            SET toplam_yaris_sayisi = (
                SELECT COUNT(*) FROM yaris_sonuclari WHERE yaris_sonuclari.sporcu_id = sporcular.id
            )
        ''')
        print("[OK] Sporcu yarış sayaçları güncellendi.")

        cursor.execute('''
            UPDATE kulupler
            SET toplam_yaris_sayisi = (
                SELECT COUNT(*) FROM yaris_sonuclari WHERE yaris_sonuclari.kulup_id = kulupler.id
            ),
            toplam_sporcu_sayisi = (
                SELECT COUNT(DISTINCT sporcu_id) FROM sporcu_kulup_tarihce WHERE sporcu_kulup_tarihce.kulup_id = kulupler.id
            )
        ''')
        print("[OK] Kulüp yarış ve sporcu sayaçları güncellendi.")

        # Değişiklikleri kaydet
        conn.commit()
        print("\n[OK] Tüm değişiklikler veritabanına başarıyla kaydedildi (COMMIT).")

        # =========================================================================
        # ADIM 5: VERİTABANI OPTİMİZASYONU (VACUUM)
        # =========================================================================
        print("\n--- ADIM 5: Veritabanı Sıkıştırma (VACUUM) ---")
        cursor.execute("VACUUM")
        print("[OK] VACUUM tamamlandı, veritabanı dosyası sıkıştırıldı ve indeksler yenilendi.")

        print(f"\n[+] İŞLEM BAŞARIYLA TAMAMLANDI (Süre: {time.time()-t_start:.2f} sn)")

    except Exception as e:
        conn.rollback()
        print(f"[!] HATA OLUŞTU, TÜM DEĞİŞİKLİKLER GERİ ALINDI (ROLLBACK): {e}", file=sys.stderr)
        raise
    finally:
        conn.close()

if __name__ == "__main__":
    run_cleanup()
