# -*- coding: utf-8 -*-
"""
populate_kulup_il.py
====================
Canlı veya yerel SQLite veritabanındaki `kulupler` tablosuna `il` sütununu
ekler (yoksa) ve her kulübün `il` bilgisini `yaris_sonuclari` + `events`
tablolarından en çok yarışılan il olarak hesaplayıp günceller.

Kullanım:
    python scripts/populate_kulup_il.py
    python scripts/populate_kulup_il.py --db /home/ubuntu/database/yuzme_veritabani.db
    python scripts/populate_kulup_il.py --dry-run
"""

import argparse
from collections import defaultdict
import os
import sqlite3
import sys

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
YUZME_APP_DIR = os.path.join(ROOT_DIR, "yuzme_projesi")
if YUZME_APP_DIR not in sys.path:
    sys.path.insert(0, YUZME_APP_DIR)

from sonuclar.sqlite_tr import is_ferdi_club, normalize_il_adi


def resolve_default_db_path() -> str:
    candidates = [
        os.path.join(ROOT_DIR, "database", "yuzme_veritabani.db"),
        os.path.join(YUZME_APP_DIR, "yuzme_veritabani.db"),
        "/home/ubuntu/database/yuzme_veritabani.db",
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return candidates[0]


def ensure_il_column(cur: sqlite3.Cursor, dry_run: bool = False) -> bool:
    """`kulupler` tablosunda `il` sütunu yoksa ekler. Eklendiyse True döner."""
    cols = {row[1] for row in cur.execute("PRAGMA table_info(kulupler)").fetchall()}
    if "il" in cols:
        return False
    if not dry_run:
        cur.execute("ALTER TABLE kulupler ADD COLUMN il TEXT")
    return True


def compute_club_provinces(cur: sqlite3.Cursor) -> tuple:
    """
    Her kulüp için en çok yarışılan ili hesaplar.
    - Ferdi kayıtlar (FERDİ, Ferdi Lisans vb.) hariç tutulur (il = None).
    - Okul kayıtlarında (okul_mu=1) birden fazla ilde yarışılmışsa belirsiz
      olduğu için hariç tutulur (il = None); tek ilde yarışmışsa o il atanır.
    Dönüş: ({kulup_id: (en_cok_il, toplam_yaris_sayisi)}, excluded_stats_dict)
    """
    rows = cur.execute(
        """
        SELECT
            ys.kulup_id,
            k.kulup_adi,
            COALESCE(k.okul_mu, 0) AS okul_mu,
            e.sehir,
            COUNT(*) AS yaris_sayisi,
            MAX(COALESCE(e.yaris_tarihi_baslangic, '')) AS son_tarih
        FROM yaris_sonuclari ys
        JOIN kulupler k ON ys.kulup_id = k.id
        JOIN events e ON ys.event_id = e.id
        WHERE ys.kulup_id IS NOT NULL
          AND e.sehir IS NOT NULL
          AND TRIM(e.sehir) != ''
        GROUP BY ys.kulup_id, e.sehir
        """
    ).fetchall()

    # kulup_id -> norm_il -> [toplam_yaris, max_son_tarih]
    club_city_stats = defaultdict(dict)
    club_meta = {}
    for kulup_id, kulup_adi, okul_mu, raw_sehir, cnt, son_tarih in rows:
        club_meta[kulup_id] = (kulup_adi, okul_mu)
        norm_il = normalize_il_adi(raw_sehir)
        if not norm_il:
            continue
        bucket = club_city_stats[kulup_id].get(norm_il)
        if bucket is None:
            club_city_stats[kulup_id][norm_il] = [cnt, son_tarih or ""]
        else:
            bucket[0] += cnt
            if (son_tarih or "") > bucket[1]:
                bucket[1] = son_tarih or ""

    result = {}
    excluded = {"ferdi": 0, "multi_city_school": 0}
    for kulup_id, city_map in club_city_stats.items():
        kulup_adi, okul_mu = club_meta[kulup_id]
        if is_ferdi_club(kulup_adi):
            excluded["ferdi"] += 1
            continue
        if okul_mu == 1 and len(city_map) > 1:
            excluded["multi_city_school"] += 1
            continue

        # En çok yarışılan il; eşitlikte en güncel yarış tarihi, sonra alfabetik
        best_il, (best_cnt, _) = max(
            city_map.items(),
            key=lambda kv: (kv[1][0], kv[1][1], kv[0]),
        )
        result[kulup_id] = (best_il, best_cnt)
    return result, excluded


def populate_kulup_il(db_path: str, dry_run: bool = False) -> dict:
    if not os.path.exists(db_path):
        raise FileNotFoundError(f"Veritabanı bulunamadı: {db_path}")

    conn = sqlite3.connect(db_path, timeout=60)
    try:
        cur = conn.cursor()
        col_added = ensure_il_column(cur, dry_run=dry_run)
        club_provinces, excluded = compute_club_provinces(cur)

        all_club_ids = [r[0] for r in cur.execute("SELECT id FROM kulupler").fetchall()]
        updates = [
            (club_provinces[kid][0] if kid in club_provinces else None, kid)
            for kid in all_club_ids
        ]

        if not dry_run:
            cur.executemany("UPDATE kulupler SET il = ? WHERE id = ?", updates)
            conn.commit()

        il_dist = defaultdict(int)
        for il, _ in club_provinces.values():
            il_dist[il] += 1

        return {
            "db_path": db_path,
            "column_added": col_added,
            "total_clubs": len(all_club_ids),
            "updated_clubs": len(club_provinces),
            "without_city": len(all_club_ids) - len(club_provinces),
            "excluded_ferdi": excluded["ferdi"],
            "excluded_multi_city_school": excluded["multi_city_school"],
            "top_provinces": sorted(il_dist.items(), key=lambda x: (-x[1], x[0]))[:15],
            "dry_run": dry_run,
        }
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser(description="Kulüp il bilgisini en çok yarışılan ilden doldurur.")
    parser.add_argument("--db", default=resolve_default_db_path(), help="SQLite veritabanı yolu")
    parser.add_argument("--dry-run", action="store_true", help="Veritabanını değiştirmeden önizleme yapar")
    args = parser.parse_args()

    stats = populate_kulup_il(args.db, dry_run=args.dry_run)
    mode = "DRY-RUN" if stats["dry_run"] else "UYGULANDI"
    print(f"[{mode}] Veritabanı: {stats['db_path']}")
    print(f"  - 'il' sütunu eklendi mi          : {'Evet' if stats['column_added'] else 'Hayır (zaten vardı)'}")
    print(f"  - Toplam kulüp                    : {stats['total_clubs']}")
    print(f"  - İl atanan kulüp                 : {stats['updated_clubs']}")
    print(f"  - İl bilgisi boş bırakılan        : {stats['without_city']}")
    print(f"    * Ferdi (hariç tutulan)         : {stats['excluded_ferdi']}")
    print(f"    * Çok illi okul (hariç tutulan) : {stats['excluded_multi_city_school']}")
    print("  - En fazla kulübe sahip ilk 15 il:")
    for il, cnt in stats["top_provinces"]:
        print(f"      {il}: {cnt}")


if __name__ == "__main__":
    main()
