# -*- coding: utf-8 -*-
"""
clean_live_data.py
==================
Veritabanındaki tüm canlı sonuç/start listesi verilerini (canli_yarislar, canli_yaris_dosyalari,
kaynak_turu CANLI_START / CANLI_SONUC olan yaris_sonuclari ve events kayıtlarını) temizler.
"""

import argparse
import os
import sqlite3
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DJANGO_DIR = os.path.join(BASE_DIR, "yuzme_projesi")
if DJANGO_DIR not in sys.path:
    sys.path.insert(0, DJANGO_DIR)

from sonuclar.turkish_names import resolve_default_db_path


def clean_live_results(db_path: str = None):
    target_db = db_path or resolve_default_db_path()
    if not os.path.exists(target_db):
        raise FileNotFoundError(f"Veritabanı bulunamadı: {target_db}")

    conn = sqlite3.connect(target_db)
    cur = conn.cursor()

    cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = {r[0] for r in cur.fetchall()}

    print("=" * 70)
    print(f"  CANLI YARIŞ VERİLERİ TEMİZLEME ARACI ({target_db})")
    print("=" * 70)

    cur.execute("SELECT kaynak_turu, COUNT(*) FROM yaris_sonuclari GROUP BY kaynak_turu")
    print("Önceki yaris_sonuclari kaynak_turu dağılımı :", cur.fetchall())

    if "events" in tables:
        cur.execute("SELECT kaynak_turu, COUNT(*) FROM events GROUP BY kaynak_turu")
        print("Önceki events kaynak_turu dağılımı          :", cur.fetchall())

    if "canli_yarislar" in tables:
        cur.execute("SELECT COUNT(*) FROM canli_yarislar")
        print("Önceki canli_yarislar kayıt sayısı          :", cur.fetchone()[0])

    if "canli_yaris_dosyalari" in tables:
        cur.execute("SELECT COUNT(*) FROM canli_yaris_dosyalari")
        print("Önceki canli_yaris_dosyalari kayıt sayısı   :", cur.fetchone()[0])

    cur.execute("BEGIN TRANSACTION;")

    try:
        live_event_ids = set()
        if "events" in tables:
            cur.execute(
                "SELECT id FROM events WHERE kaynak_turu IN ('CANLI_START', 'CANLI_SONUC') "
                "OR kaynak_turu LIKE '%CANLI%' OR yaris_tarihi_baslangic = '2026-07-17'"
            )
            live_event_ids.update(r[0] for r in cur.fetchall())

        if "canli_yarislar" in tables:
            cur.execute("SELECT event_id FROM canli_yarislar WHERE event_id IS NOT NULL")
            live_event_ids.update(r[0] for r in cur.fetchall())

        if "canli_yaris_dosyalari" in tables:
            cur.execute("SELECT event_id FROM canli_yaris_dosyalari WHERE event_id IS NOT NULL")
            live_event_ids.update(r[0] for r in cur.fetchall())

        cur.execute("PRAGMA table_info(yaris_sonuclari)")
        ys_cols = {r[1] for r in cur.fetchall()}

        where_clauses = [
            "kaynak_turu IN ('CANLI_START', 'CANLI_SONUC')",
            "kaynak_turu LIKE '%CANLI%'",
            "derece = 'Bekleniyor'",
        ]
        if "canli_dosya_id" in ys_cols:
            where_clauses.append("canli_dosya_id IS NOT NULL")
        if live_event_ids and "event_id" in ys_cols:
            where_clauses.append(f"+event_id IN ({','.join(str(eid) for eid in live_event_ids)})")

        where_sql = " OR ".join(where_clauses)

        cur.execute(f"SELECT DISTINCT sporcu_id FROM yaris_sonuclari WHERE ({where_sql}) AND sporcu_id IS NOT NULL")
        affected_athletes = [r[0] for r in cur.fetchall()]

        cur.execute(f"DELETE FROM yaris_sonuclari WHERE {where_sql}")
        deleted_ys = cur.rowcount

        deleted_dosya = 0
        if "canli_yaris_dosyalari" in tables:
            cur.execute("DELETE FROM canli_yaris_dosyalari")
            deleted_dosya = cur.rowcount

        deleted_canli = 0
        if "canli_yarislar" in tables:
            cur.execute("DELETE FROM canli_yarislar")
            deleted_canli = cur.rowcount

        deleted_events = 0
        if "events" in tables:
            if live_event_ids:
                e_ids_sql = ",".join(str(eid) for eid in live_event_ids)
                cur.execute(
                    f"DELETE FROM events WHERE (id IN ({e_ids_sql}) OR kaynak_turu LIKE '%CANLI%') "
                    f"AND NOT EXISTS (SELECT 1 FROM yaris_sonuclari WHERE yaris_sonuclari.event_id = events.id)"
                )
            else:
                cur.execute(
                    "DELETE FROM events WHERE kaynak_turu LIKE '%CANLI%' "
                    "AND NOT EXISTS (SELECT 1 FROM yaris_sonuclari WHERE yaris_sonuclari.event_id = events.id)"
                )
            deleted_events = cur.rowcount

        deleted_athletes = 0
        if affected_athletes:
            a_ids_sql = ",".join(str(aid) for aid in affected_athletes)
            cur.execute(
                f"""
                UPDATE sporcular
                SET toplam_yaris_sayisi = (
                    SELECT COUNT(*) FROM yaris_sonuclari WHERE yaris_sonuclari.sporcu_id = sporcular.id
                )
                WHERE id IN ({a_ids_sql})
                """
            )
            cur.execute(
                f"""
                DELETE FROM sporcu_kulup_tarihce
                WHERE sporcu_id IN ({a_ids_sql})
                  AND NOT EXISTS (
                      SELECT 1 FROM yaris_sonuclari
                      WHERE yaris_sonuclari.sporcu_id = sporcu_kulup_tarihce.sporcu_id
                        AND yaris_sonuclari.kulup_id = sporcu_kulup_tarihce.kulup_id
                  )
                """
            )
            cur.execute(f"DELETE FROM sporcular WHERE id IN ({a_ids_sql}) AND toplam_yaris_sayisi = 0")
            deleted_athletes = cur.rowcount

        conn.commit()

        print("-" * 70)
        print(f"Silinen canlı yarış sonucu (yaris_sonuclari) : {deleted_ys:,}")
        print(f"Silinen canlı dosya (canli_yaris_dosyalari)  : {deleted_dosya:,}")
        print(f"Silinen canlı yarış oturumu (canli_yarislar) : {deleted_canli:,}")
        print(f"Silinen canlı müsabaka (events)              : {deleted_events:,}")
        print(f"Sadece canlıdan gelen ve silinen sporcu      : {deleted_athletes:,}")
        print("=" * 70)
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Veritabanındaki tüm canlı sonuç verilerini temizler.")
    parser.add_argument("--db", type=str, default=None, help="SQLite veritabanı yolu")
    args = parser.parse_args()
    clean_live_results(db_path=args.db)
