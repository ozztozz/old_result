# -*- coding: utf-8 -*-
"""
drop_event_columns_from_yaris_sonuclari.py
=========================================
'yaris_sonuclari' tablosundan 'events' tablosuna aktarılan 5 kolonu kaldırır:
- musabaka_adi
- sehir
- yaris_tarihi_ham
- yaris_tarihi_baslangic
- yaris_tarihi_bitis
"""

import sqlite3
import time
import sys

def drop_columns():
    db_path = "output/yuzme_veritabani.db"
    print(f"[*] Veritabanı açılıyor: {db_path}")
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    try:
        t0 = time.time()

        # Doğrulama: Tüm kayıtların event_id'si var mı?
        cursor.execute("SELECT COUNT(*) FROM yaris_sonuclari WHERE event_id IS NULL")
        missing_event = cursor.fetchone()[0]
        if missing_event > 0:
            raise RuntimeError(f"HATA: {missing_event} kaydın event_id'si boş! Kolonlar silinemez.")

        cursor.execute("PRAGMA table_info(yaris_sonuclari)")
        cols = [r[1] for r in cursor.fetchall()]
        print(f"Mevcut kolon sayısı: {len(cols)}")

        # Önce bu kolonlar üzerindeki indeksleri kaldır
        print("[*] Eski indeksler kaldırılıyor...")
        cursor.execute("DROP INDEX IF EXISTS idx_sonuclar_tarih;")
        print("[OK] 'idx_sonuclar_tarih' indeksi kaldırıldı.")

        cols_to_drop = [
            'musabaka_adi',
            'sehir',
            'yaris_tarihi_ham',
            'yaris_tarihi_baslangic',
            'yaris_tarihi_bitis'
        ]

        for col in cols_to_drop:
            if col in cols:
                print(f"[*] '{col}' kolonu yaris_sonuclari tablosundan siliniyor...")
                cursor.execute(f"ALTER TABLE yaris_sonuclari DROP COLUMN {col};")
                print(f"[OK] '{col}' başarıyla kaldırıldı.")
            else:
                print(f"[*] '{col}' zaten tabloda yok.")

        conn.commit()

        cursor.execute("PRAGMA table_info(yaris_sonuclari)")
        new_cols = [r[1] for r in cursor.fetchall()]
        print(f"\n[OK] Kalan kolon sayısı: {len(new_cols)}")
        print("Kalan kolonlar:", new_cols)

        print("\n[*] Veritabanı sıkıştırılıyor (VACUUM)...")
        cursor.execute("VACUUM")
        print(f"[+] İŞLEM BAŞARIYLA TAMAMLANDI! (Süre: {time.time()-t0:.2f} sn)")

    except Exception as e:
        conn.rollback()
        print(f"[!] HATA: {e}", file=sys.stderr)
        raise
    finally:
        conn.close()

if __name__ == "__main__":
    drop_columns()
