"""
YarisSonuclari tablosunda silinmiş/geçersiz sporcu_kulup_tarihce_id referanslarını
otomatik olarak doğru tarihçe kaydıyla eşleştiren veya NULL yapan onarım betiği.
Django migrate esnasında oluşan IntegrityError hatasını giderir.
"""

import os
import sqlite3
import sys

def fix_database_foreign_keys(db_path: str):
    if not os.path.exists(db_path):
        print(f"[-] Veritabanı bulunamadı: {db_path}")
        return

    print(f"[*] Veritabanı inceleniyor: {db_path}")
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # Geçersiz referansları bul
    cur.execute("""
        SELECT y.id, y.sporcu_id, y.kulup_id, y.sporcu_kulup_tarihce_id
        FROM yaris_sonuclari y
        LEFT JOIN sporcu_kulup_tarihce t ON y.sporcu_kulup_tarihce_id = t.id
        WHERE y.sporcu_kulup_tarihce_id IS NOT NULL AND t.id IS NULL
    """)
    bad_rows = cur.fetchall()

    if not bad_rows:
        print(f"[+] {db_path} içinde geçersiz yabancı anahtar (FK) bulunamadı. Veritabanı temiz.")
        conn.close()
        return

    print(f"[!] {len(bad_rows)} adet geçersiz sporcu_kulup_tarihce referansı tespit edildi. Onarılıyor...")

    # 1. Aşama: sporcu_id ve kulup_id eşleşen gerçek tarihçe kaydını bulup ata
    cur.execute("""
        UPDATE yaris_sonuclari
        SET sporcu_kulup_tarihce_id = (
            SELECT t.id
            FROM sporcu_kulup_tarihce t
            WHERE t.sporcu_id = yaris_sonuclari.sporcu_id
              AND t.kulup_id = yaris_sonuclari.kulup_id
            LIMIT 1
        )
        WHERE id IN (
            SELECT y.id
            FROM yaris_sonuclari y
            LEFT JOIN sporcu_kulup_tarihce t ON y.sporcu_kulup_tarihce_id = t.id
            WHERE y.sporcu_kulup_tarihce_id IS NOT NULL AND t.id IS NULL
        )
    """)

    # 2. Aşama: Eşleşmeyen kalırsa NULL yap (foreign key kısıtını sağlaması için)
    cur.execute("""
        UPDATE yaris_sonuclari
        SET sporcu_kulup_tarihce_id = NULL
        WHERE id IN (
            SELECT y.id
            FROM yaris_sonuclari y
            LEFT JOIN sporcu_kulup_tarihce t ON y.sporcu_kulup_tarihce_id = t.id
            WHERE y.sporcu_kulup_tarihce_id IS NOT NULL AND t.id IS NULL
        )
    """)

    conn.commit()

    cur.execute("PRAGMA foreign_key_check;")
    remaining = cur.fetchall()
    print(f"[+] Onarım tamamlandı! Kalan FK hatası: {len(remaining)}")
    conn.close()


if __name__ == "__main__":
    db_candidates = [
        os.path.join(os.path.dirname(__file__), "database", "yuzme_veritabani.db"),
        os.path.join(os.path.dirname(__file__), "output", "yuzme_veritabani.db"),
        "yuzme_veritabani.db",
        "/home/ozztozz/yuzme_projesi/database/yuzme_veritabani.db"
    ]
    for db in db_candidates:
        if os.path.exists(db):
            fix_database_foreign_keys(db)

