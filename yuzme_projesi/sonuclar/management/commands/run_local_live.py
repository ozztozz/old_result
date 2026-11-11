# -*- coding: utf-8 -*-
from django.core.management.base import BaseCommand
from sonuclar.local_live_engine import (
    run_local_live_worker,
    run_cron_orchestrator,
    run_daemon_worker,
    start_daemon_background,
    stop_daemon,
    get_running_daemon_pid,
    DEFAULT_POLL_INTERVAL,
)

class Command(BaseCommand):
    help = "Yerel TYF Canlı Takip Servisi (5 Saniyede Bir Anlık Kontrol + Saatlik Cron Orkestratörü)"

    def add_arguments(self, parser):
        parser.add_argument("--cron", action="store_true", help="1. Servis: Saatlik cron orkestratörünü çalıştır")
        parser.add_argument("--daemon", action="store_true", help="2. Servis: 5 saniyelik anlık takipçi döngüsünü başlat")
        parser.add_argument("--baslat", action="store_true", help="Takipçiyi arka planda başlat (detatch)")
        parser.add_argument("--durdur", action="store_true", help="Çalışan canlı takipçi sürecini durdur")
        parser.add_argument("--durum", action="store_true", help="Canlı takipçi servisinin PID ve çalışma durumunu kontrol et")
        parser.add_argument("--url", type=str, help="Belirli bir yarış URL'sini anında tek seferlik tara")
        parser.add_argument("--interval", type=int, default=DEFAULT_POLL_INTERVAL, help="Kontrol sıklığı (saniye, varsayılan: 5)")
        parser.add_argument("--force", action="store_true", help="İşlenmiş dosyaları tekrar tara")

    def handle(self, *args, **options):
        if options.get("durdur"):
            if stop_daemon():
                self.stdout.write(self.style.SUCCESS("[+] Yerel Canlı Takip Servisi başarıyla durduruldu."))
            else:
                self.stdout.write(self.style.WARNING("[-] Çalışan takipçi bulunamadı."))
        elif options.get("durum"):
            pid = get_running_daemon_pid()
            if pid:
                self.stdout.write(self.style.SUCCESS(f"[+] 5 Saniyelik Canlı Takipçi AKTİF çalışıyor (PID: {pid})."))
            else:
                self.stdout.write(self.style.WARNING("[-] Canlı Takipçi şu anda ÇALIŞMIYOR."))
        elif options.get("baslat"):
            pid = start_daemon_background(poll_interval=options.get("interval", DEFAULT_POLL_INTERVAL))
            if pid:
                self.stdout.write(self.style.SUCCESS(f"[+] Canlı Takipçi arka planda başlatıldı (PID: {pid})."))
        elif options.get("cron"):
            self.stdout.write("[*] Saatlik Cron Orkestratörü çalıştırılıyor...")
            run_cron_orchestrator(poll_interval=options.get("interval", DEFAULT_POLL_INTERVAL))
        elif options.get("daemon"):
            self.stdout.write(f"[*] 5 Saniyelik Canlı Takipçi ön planda başlatılıyor...")
            run_daemon_worker(poll_interval=options.get("interval", DEFAULT_POLL_INTERVAL))
        else:
            url = options.get("url")
            force = options.get("force", False)
            interval = options.get("interval", DEFAULT_POLL_INTERVAL)
            self.stdout.write(self.style.SUCCESS("[*] Yerel Canlı Takip Taraması Başlatılıyor..."))
            run_local_live_worker(url=url, interval=interval, force=force)
