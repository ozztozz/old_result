# -*- coding: utf-8 -*-
from django.conf import settings
from django.core.management.base import BaseCommand
from sonuclar.turkish_names import repair_database_turkish_names


class Command(BaseCommand):
    help = "Veritabanındaki sporcu isimlerinde Türkçe karakter kaynaklı hataları düzeltir ve mükerrerleri birleştirir."

    def add_arguments(self, parser):
        parser.add_argument(
            "--db",
            type=str,
            default=None,
            help="SQLite veritabanı dosya yolu (varsayılan: settings.DATABASES['default']['NAME'])",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Değişiklikleri kaydetmeden sadece raporla",
        )

    def handle(self, *args, **options):
        db_path = options.get("db")
        if not db_path:
            db_path = str(settings.DATABASES["default"]["NAME"])
        dry_run = bool(options.get("dry_run"))

        self.stdout.write("=" * 70)
        self.stdout.write("  SPORCU İSİMLERİ TÜRKÇE KARAKTER DÜZELTME ARACI")
        self.stdout.write("=" * 70)
        if dry_run:
            self.stdout.write(self.style.WARNING("[DRY-RUN] Veritabanına yazılmadan analiz yapılıyor..."))

        stats = repair_database_turkish_names(db_path=db_path, dry_run=dry_run)

        self.stdout.write(f"Veritabanı             : {stats['db_path']}")
        self.stdout.write(f"Taranan toplam sporcu  : {stats['total_athletes']:,}")
        self.stdout.write(self.style.SUCCESS(f"İsmi düzeltilen sporcu : {stats['renamed_count']:,}"))
        self.stdout.write(self.style.SUCCESS(f"Birleştirilen mükerrer : {stats['merged_duplicate_athletes']:,}"))
        self.stdout.write(f"Taşınan yarış sonucu   : {stats['reassigned_races']:,}")
        self.stdout.write(f"Silinen mükerrer yarış : {stats['deleted_duplicate_races']:,}")
        self.stdout.write(f"İşlem süresi           : {stats['elapsed_sec']} sn")

        if stats["sample_renames"]:
            self.stdout.write("\nÖrnek İsim Düzeltmeleri (İlk 25):")
            for sp_id, old_name, new_name in stats["sample_renames"][:25]:
                self.stdout.write(f"  [ID {sp_id:<6}] {old_name:<28} -> {new_name}")

        if stats["sample_merges"]:
            self.stdout.write("\nÖrnek Birleştirilen Mükerrerler (İlk 15):")
            for dup_id, dup_name, keep_id, keep_name, by in stats["sample_merges"][:15]:
                self.stdout.write(
                    f"  [ID {dup_id}: {dup_name} ({by})] ==> [ID {keep_id}: {keep_name}]"
                )

