# -*- coding: utf-8 -*-
"""
migrate_create_events_table.py
==============================
1. 'events' (Müsabaka) tablosunu oluşturur.
2. Mevcut 'yaris_sonuclari' tablosundaki 745 tekil müsabakayı 'events' tablosuna aktarır.
3. 'yaris_sonuclari' tablosuna 'event_id' foreign key kolonunu ekler ve indeksler.
4. Her bir yarış sonucunu ilgili event_id ile bağlar.
5. Her event için toplam_yaris_sayisi ve toplam_sporcu_sayisi alanlarını günceller.
"""

import sqlite3
import time
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

def migrate():
    db_path = "output/yuzme_veritabani.db"
    print(f"[*] Veritabanı açılıyor: {db_path}")
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    try:
        t0 = time.time()

        # 1. EVENTS TABLOSUNU OLUŞTUR
        print("\n--- 1. 'events' Tablosu Oluşturuluyor ---")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                musabaka_adi VARCHAR(500) NOT NULL,
                sehir VARCHAR(100),
                yaris_tarihi_ham VARCHAR(100),
                yaris_tarihi_baslangic VARCHAR(20),
                yaris_tarihi_bitis VARCHAR(20),
                kaynak_turu VARCHAR(50),
                toplam_yaris_sayisi INTEGER DEFAULT 0,
                toplam_sporcu_sayisi INTEGER DEFAULT 0,
                olusturulma_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP,
                guncellenme_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP
            );
        """)
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_events_baslangic ON events(yaris_tarihi_baslangic);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_events_musabaka_adi ON events(musabaka_adi);")
        print("[OK] 'events' tablosu ve indeksleri hazırlandı.")

        # 2. TEKİL MÜSABAKALARI BUL VE 'events' TABLOSUNA EKLE
        print("\n--- 2. Tekil Müsabakalar 'events' Tablosuna Aktarılıyor ---")
        cursor.execute("SELECT COUNT(*) FROM events")
        existing_event_count = cursor.fetchone()[0]

        if existing_event_count == 0:
            cursor.execute("""
                INSERT INTO events (
                    musabaka_adi, sehir, yaris_tarihi_ham, 
                    yaris_tarihi_baslangic, yaris_tarihi_bitis, kaynak_turu
                )
                SELECT 
                    musabaka_adi,
                    MAX(sehir),
                    MAX(yaris_tarihi_ham),
                    yaris_tarihi_baslangic,
                    MAX(yaris_tarihi_bitis),
                    MAX(kaynak_turu)
                FROM yaris_sonuclari
                WHERE musabaka_adi IS NOT NULL AND musabaka_adi != ''
                GROUP BY musabaka_adi, yaris_tarihi_baslangic
                ORDER BY yaris_tarihi_baslangic DESC
            """)
            conn.commit()
            cursor.execute("SELECT COUNT(*) FROM events")
            print(f"[OK] {cursor.fetchone()[0]} tekil müsabaka 'events' tablosuna eklendi.")
        else:
            print(f"[*] 'events' tablosunda zaten {existing_event_count} kayıt var.")

        # 3. 'yaris_sonuclari' TABLOSUNA 'event_id' KOLONUNU EKLE
        print("\n--- 3. 'yaris_sonuclari' Tablosuna 'event_id' Kolonu Ekleniyor ---")
        cursor.execute("PRAGMA table_info(yaris_sonuclari)")
        columns = [row[1] for row in cursor.fetchall()]
        if "event_id" not in columns:
            cursor.execute("ALTER TABLE yaris_sonuclari ADD COLUMN event_id INTEGER REFERENCES events(id);")
            print("[OK] 'event_id' kolonu eklendi.")
        else:
            print("[*] 'event_id' kolonu zaten mevcut.")

        cursor.execute("CREATE INDEX IF NOT EXISTS idx_yaris_sonuclari_event_id ON yaris_sonuclari(event_id);")

        # 4. YARIS_SONUCLARI TABLOSUNDAKİ HER KAYDI İLGİLİ EVENT_ID İLE EŞLEŞTİR
        print("\n--- 4. Yarış Kayıtları Event Tablosu ile Bağlanıyor (Toplu Eşleştirme) ---")
        cursor.execute("SELECT COUNT(*) FROM yaris_sonuclari WHERE event_id IS NULL")
        unlinked_count = cursor.fetchone()[0]
        print(f"Bağlanacak yarış sayısı: {unlinked_count}")

        if unlinked_count > 0:
            cursor.execute("""
                UPDATE yaris_sonuclari
                SET event_id = (
                    SELECT e.id 
                    FROM events e 
                    WHERE e.musabaka_adi = yaris_sonuclari.musabaka_adi 
                      AND (e.yaris_tarihi_baslangic = yaris_sonuclari.yaris_tarihi_baslangic 
                           OR (yaris_sonuclari.yaris_tarihi_baslangic IS NULL AND e.yaris_tarihi_baslangic IS NULL))
                    LIMIT 1
                )
                WHERE event_id IS NULL;
            """)
            conn.commit()
            print("[OK] Eşleştirme tamamlandı.")

        # Doğrulama: Bağlanamayan var mı?
        cursor.execute("SELECT COUNT(*) FROM yaris_sonuclari WHERE event_id IS NULL")
        rem_unlinked = cursor.fetchone()[0]
        cursor.execute("SELECT COUNT(*) FROM yaris_sonuclari WHERE event_id IS NOT NULL")
        linked_count = cursor.fetchone()[0]
        print(f"[OK] Başarıyla bağlanan yarış sayısı: {linked_count}")
        if rem_unlinked > 0:
            print(f"[!] DİKKAT: {rem_unlinked} yarış bir event ile eşleştirilemedi!")
        else:
            print("[OK] Tüm yarışlar (%100) eksiksiz olarak Event tablosuna bağlandı.")

        # 5. EVENT SAYAÇLARINI GÜNCELLE (toplam_yaris_sayisi, toplam_sporcu_sayisi)
        print("\n--- 5. Event Sayaçları Güncelleniyor ---")
        cursor.execute("""
            UPDATE events
            SET toplam_yaris_sayisi = (
                SELECT COUNT(*) FROM yaris_sonuclari WHERE yaris_sonuclari.event_id = events.id
            ),
            toplam_sporcu_sayisi = (
                SELECT COUNT(DISTINCT sporcu_id) FROM yaris_sonuclari WHERE yaris_sonuclari.event_id = events.id
            )
        """)
        conn.commit()
        print("[OK] Event yarış ve sporcu sayaçları güncellendi.")

        # 6. 'canli_yarislar' TABLOSUNA 'event_id' EKLE
        print("\n--- 6. 'canli_yarislar' Tablosuna 'event_id' Ekleniyor ---")
        cursor.execute("PRAGMA table_info(canli_yarislar)")
        c_cols = [row[1] for row in cursor.fetchall()]
        if "event_id" not in c_cols:
            cursor.execute("ALTER TABLE canli_yarislar ADD COLUMN event_id INTEGER REFERENCES events(id);")
            print("[OK] 'canli_yarislar.event_id' kolonu eklendi.")
        conn.commit()

        print(f"\n[+] MİGRASYON BAŞARIYLA TAMAMLANDI! (Toplam Süre: {time.time()-t0:.2f} sn)")

    except Exception as e:
        conn.rollback()
        print(f"[!] HATA OLUŞTU (ROLLBACK): {e}", file=sys.stderr)
        raise
    finally:
        conn.close()

if __name__ == "__main__":
    migrate()
