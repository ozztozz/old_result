# -*- coding: utf-8 -*-
"""
fix_turkish_athlete_names.py
============================
Veritabanındaki sporcu isimlerinde Türkçe karakterlerden (İ/I, ı/i, Ş/S, Ğ/G, Ü/U, Ö/O, Ç/C),
Python'un .capitalize()/.upper()/.lower() hatalarından (örn: Çinar -> Çınar, DEMIR -> DEMİR, i\\u0307 -> i)
ve imla farklarından kaynaklanan bozulmaları düzeltir; Türkçe karakter farkıyla oluşmuş mükerrer
sporcu kayıtlarını tek kayıtta birleştirir.

Kullanım:
  python scratch/fix_turkish_athlete_names.py
  python scratch/fix_turkish_athlete_names.py --dry-run
  python scratch/fix_turkish_athlete_names.py --db /path/to/yuzme_veritabani.db
"""

import argparse
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# Proje dizinini import yoluna ekle
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DJANGO_DIR = os.path.join(BASE_DIR, "yuzme_projesi")
if DJANGO_DIR not in sys.path:
    sys.path.insert(0, DJANGO_DIR)

from sonuclar.turkish_names import repair_database_turkish_names


def main():
    parser = argparse.ArgumentParser(
        description="Veritabanındaki sporcu isimlerinde Türkçe karakter kaynaklı hataları düzeltir ve mükerrerleri birleştirir."
    )
    parser.add_argument(
        "--db",
        type=str,
        default=None,
        help="SQLite veritabanı yolu (varsayılan: otomatik bulur)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Veritabanında değişiklik yapmadan düzeltilecek kayıtları ve birleştirmeleri raporlar",
    )
    args = parser.parse_args()

    print("=" * 72)
    print("  SPORCU İSİMLERİ TÜRKÇE KARAKTER DÜZELTME VE TEKİLLEŞTİRME ARACI")
    print("=" * 72)
    if args.dry_run:
        print("[MOD] DRY-RUN (Sadece analiz, veritabanına yazılmayacak)")

    stats = repair_database_turkish_names(db_path=args.db, dry_run=args.dry_run)

    print(f"\nVeritabanı               : {stats['db_path']}")
    print(f"Taranan toplam sporcu    : {stats['total_athletes']:,}")
    print(f"İsmi düzeltilen sporcu   : {stats['renamed_count']:,}")
    print(f"Birleştirilen mükerrer   : {stats['merged_duplicate_athletes']:,}")
    print(f"Taşınan yarış sonucu     : {stats['reassigned_races']:,}")
    print(f"Silinen mükerrer yarış   : {stats['deleted_duplicate_races']:,}")
    print(f"İşlem süresi             : {stats['elapsed_sec']} sn")

    if stats["sample_renames"]:
        print("\nÖrnek İsim Düzeltmeleri (İlk 30):")
        print("-" * 72)
        for sp_id, old_name, new_name in stats["sample_renames"][:30]:
            print(f"  [ID {sp_id:<6}] {old_name:<30} -> {new_name}")

    if stats["sample_merges"]:
        print("\nÖrnek Birleştirilen Mükerrer Sporcular (İlk 20):")
        print("-" * 72)
        for dup_id, dup_name, keep_id, keep_name, by in stats["sample_merges"][:20]:
            print(f"  [Silinen ID {dup_id}: {dup_name} ({by})] ==> [Korunan ID {keep_id}: {keep_name}]")

    print("=" * 72)


if __name__ == "__main__":
    main()

