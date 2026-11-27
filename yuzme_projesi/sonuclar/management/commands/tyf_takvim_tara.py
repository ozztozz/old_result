# -*- coding: utf-8 -*-
from django.core.management.base import BaseCommand
from sonuclar.tyf_calendar_sync import DEFAULT_TAKVIM_URL, sync_tyf_calendar


class Command(BaseCommand):
    help = "TYF faaliyet takvimi, reglaman ve milli takım kriter belgelerini günlük tarar."

    def add_arguments(self, parser):
        parser.add_argument("--url", type=str, default=DEFAULT_TAKVIM_URL, help="Taranacak TYF takvim sayfası URL")
        parser.add_argument("--force", action="store_true", help="Hash değişmese bile tüm belgeleri yeniden işle")
        parser.add_argument("--no-milli-takim", action="store_true", help="Milli takım kriterleri alt sayfasını atla")
        parser.add_argument("--no-ankara", action="store_true", help="Ankara İl Temsilciliği sayfalarını atla")
        parser.add_argument("--no-gemini", action="store_true", help="Gemini analizini atla (yalnız yerel parser)")

    def handle(self, *args, **options):
        self.stdout.write(f"[*] TYF Takvim taraması başlatılıyor: {options['url']}")
        stats = sync_tyf_calendar(
            takvim_url=options["url"],
            include_milli_takim=not options["no_milli_takim"],
            include_ankara=not options["no_ankara"],
            force=options["force"],
            skip_gemini=options["no_gemini"],
        )
        self.stdout.write(self.style.SUCCESS(
            f"[+] Tamamlandı | Bulunan: {stats['discovered']} | İşlenen: {stats['processed']} | "
            f"Değişmeyen (Atlanan): {stats['skipped_unchanged']} | Takvim Etkinliği: {stats['takvim_events']} | "
            f"Baraj Kuralı: {stats['baraj_rules']}"
        ))
        if stats["errors"]:
            for err in stats["errors"]:
                self.stderr.write(self.style.ERROR(f"[!] Hata: {err}"))
