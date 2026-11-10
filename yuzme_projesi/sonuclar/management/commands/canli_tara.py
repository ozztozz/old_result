# -*- coding: utf-8 -*-
from django.core.management.base import BaseCommand
from sonuclar.live_engine import (
    run_cron_orchestrator,
    run_daemon_worker,
    discover_new_meets_db,
    stop_daemon,
    get_running_daemon_pid,
    process_single_meet_db,
    get_gemini_client,
    CanliYaris,
    DEFAULT_MODEL,
)


class Command(BaseCommand):
    help = "TYF Canlı Yarış Takip, Ayrıştırma ve Cron Orkestratörü (live_engine köprüsü)"

    def add_arguments(self, parser):
        parser.add_argument("--cron", action="store_true", help="1. Servis: Saatlik cron orkestratörünü çalıştır")
        parser.add_argument("--daemon", action="store_true", help="2. Servis: 10 saniyelik canlı takipçi döngüsünü başlat")
        parser.add_argument("--kesfet", action="store_true", help="TYF sayfalarından yeni canlı yarışları keşfet")
        parser.add_argument("--durdur", action="store_true", help="Çalışan 2. Servisi (daemon) durdur")
        parser.add_argument("--durum", action="store_true", help="Canlı takipçi servisinin durumunu kontrol et")
        parser.add_argument("--id", type=int, default=None, help="Belirli bir yarış ID'sini anında tek seferlik tara")
        parser.add_argument("--aralik", type=int, default=10, help="Daemon döngü aralığı (saniye)")
        parser.add_argument("--model", type=str, default=DEFAULT_MODEL, help="Gemini model adı")

    def handle(self, *args, **options):
        if options.get("durdur"):
            stop_daemon()
        elif options.get("durum"):
            pid = get_running_daemon_pid()
            if pid:
                self.stdout.write(self.style.SUCCESS(f"[+] 2. Servis (Canlı Takipçi) AKTİF çalışıyor. PID: {pid}"))
            else:
                self.stdout.write(self.style.WARNING("[-] 2. Servis (Canlı Takipçi) şu anda ÇALIŞMIYOR."))
        elif options.get("daemon"):
            run_daemon_worker(poll_interval=options.get("aralik", 10), model=options.get("model", DEFAULT_MODEL))
        elif options.get("id"):
            yaris_id = options["id"]
            y = CanliYaris.objects.filter(id=yaris_id).first()
            if not y:
                self.stdout.write(self.style.ERROR(f"[!] ID {yaris_id} olan canlı yarış bulunamadı."))
                return
            cl = get_gemini_client()
            st = process_single_meet_db(y, cl, model=options.get("model", DEFAULT_MODEL))
            self.stdout.write(self.style.SUCCESS(f"[+] Sonuç: {st}"))
        elif options.get("kesfet") and not options.get("cron"):
            added = discover_new_meets_db()
            self.stdout.write(self.style.SUCCESS(f"[+] {added} yeni yarış keşfedildi."))
        else:
            # Varsayılan olarak (veya --cron ile) saatlik cron orkestratörünü çalıştır
            run_cron_orchestrator(kesfet=options.get("kesfet", False))
