# -*- coding: utf-8 -*-
from django.core.management.base import BaseCommand
from sonuclar.local_live_engine import (
    run_local_live_worker,
    run_cron_orchestrator,
    run_daemon_worker,
    start_daemon_background,
    stop_daemon,
    get_running_daemon_pid,
    discover_new_live_meets,
    compute_auto_scan_range,
    DEFAULT_POLL_INTERVAL,
    DEFAULT_SCAN_WINDOW,
)

class Command(BaseCommand):
    help = "Yerel TYF Canlı Takip Servisi (5 Saniyede Bir Anlık Kontrol + Saatlik Cron Orkestratörü)"

    def add_arguments(self, parser):
        parser.add_argument("--cron", action="store_true", help="1. Servis: Cron orkestratörünü çalıştır (yeni yarış keşfi + daemon başlatma)")
        parser.add_argument("--tara", action="store_true", help="TYF canlı sayfasında yeni yarış var mı diye otomatik aralıkta tara ve DB'ye ekle")
        parser.add_argument("--scan-start", type=int, default=None, help="Tarama başlangıç ID (boşsa DB'den otomatik hesaplanır)")
        parser.add_argument("--scan-end", type=int, default=None, help="Tarama bitiş ID (boşsa DB'den otomatik hesaplanır)")
        parser.add_argument("--scan-window", type=int, default=DEFAULT_SCAN_WINDOW, help=f"Otomatik ileri tarama penceresi (varsayılan: {DEFAULT_SCAN_WINDOW})")
        parser.add_argument("--no-discover", action="store_true", help="--cron çalışırken otomatik yarış keşfini atla")
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
        elif options.get("tara"):
            year, auto_s, auto_e, _ = compute_auto_scan_range(window=options.get("scan_window", DEFAULT_SCAN_WINDOW))
            s_id = options.get("scan_start") if options.get("scan_start") is not None else auto_s
            e_id = options.get("scan_end") if options.get("scan_end") is not None else auto_e
            self.stdout.write(f"[*] Yeni canlı yarış keşfi ({year}): {s_id} -> {e_id}")
            added = discover_new_live_meets(
                start_id=s_id,
                end_id=e_id,
                window=options.get("scan_window", DEFAULT_SCAN_WINDOW),
            )
            self.stdout.write(self.style.SUCCESS(f"[+] Tamamlandı: {len(added)} yeni yarış eklendi."))
        elif options.get("baslat"):
            pid = start_daemon_background(poll_interval=options.get("interval", DEFAULT_POLL_INTERVAL))
            if pid:
                self.stdout.write(self.style.SUCCESS(f"[+] Canlı Takipçi arka planda başlatıldı (PID: {pid})."))
        elif options.get("cron"):
            self.stdout.write("[*] Cron Orkestratörü çalıştırılıyor...")
            run_cron_orchestrator(
                poll_interval=options.get("interval", DEFAULT_POLL_INTERVAL),
                discover=not options.get("no_discover", False),
            )
        elif options.get("daemon"):
            self.stdout.write(f"[*] 5 Saniyelik Canlı Takipçi ön planda başlatılıyor...")
            run_daemon_worker(poll_interval=options.get("interval", DEFAULT_POLL_INTERVAL))
        else:
            url = options.get("url")
            force = options.get("force", False)
            interval = options.get("interval", DEFAULT_POLL_INTERVAL)
            self.stdout.write(self.style.SUCCESS("[*] Yerel Canlı Takip Taraması Başlatılıyor..."))
            run_local_live_worker(url=url, interval=interval, force=force)
