# -*- coding: utf-8 -*-
from django.core.management.base import BaseCommand
from django.db.models import Q
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
        parser.add_argument("--force", action="store_true", help="Eski dosya önbelleğini sıfırla ve tüm PDF'leri baştan tara")
        parser.add_argument("--eslestir", nargs="?", const=-1, type=int, help="Maskeli sporcuları ('Maskeli sporcu (...)') veritabanındaki gerçek sporcularla arka planda eşleştir (Event ID veya tümü)")
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
        elif options.get("eslestir") is not None:
            ev_id = options.get("eslestir")
            from sonuclar.athlete_matcher import match_athlete
            from sonuclar.models import YarisSonucu, Sporcu

            qs = YarisSonucu.objects.filter(
                Q(sporcu__sporcu_adi__startswith="Maskeli sporcu") |
                Q(sporcu__sporcu_adi__contains="*") |
                (Q(sporcu_maskeli__isnull=False) & Q(sporcu_maskeli__contains="*"))
            ).distinct()

            if ev_id and ev_id > 0:
                qs = qs.filter(event_id=ev_id)
                self.stdout.write(f"[*] Event #{ev_id} için maskeli sporcular taranıyor...")
            else:
                self.stdout.write("[*] Tüm yarışlardaki maskeli sporcular taranıyor...")

            total = qs.count()
            self.stdout.write(f"[*] Toplam {total} maskeli sonuç kaydı bulundu.")
            matched_count = 0
            for r in qs.select_related("sporcu", "kulup", "event").iterator(chunk_size=200):
                raw_masked_name = r.sporcu_maskeli
                if not raw_masked_name and r.sporcu:
                    raw_masked_name = r.sporcu.sporcu_adi.replace("Maskeli sporcu (", "").rstrip(")")
                
                m_res = match_athlete(
                    raw_masked_name,
                    birth_year_or_date=r.sporcu.dogum_yili if r.sporcu else None,
                    club=r.kulup.kulup_adi if r.kulup else None,
                    gender=r.cinsiyet or (r.sporcu.cinsiyet if r.sporcu else None),
                )
                if m_res.get("bulunan_id"):
                    found_sp = Sporcu.objects.filter(id=m_res["bulunan_id"]).first()
                    if found_sp:
                        old_name = r.sporcu.sporcu_adi if r.sporcu else "Yok"
                        r.sporcu = found_sp
                        r.save(update_fields=["sporcu"])
                        matched_count += 1
                        self.stdout.write(self.style.SUCCESS(f"  [+] Eşleşti: {old_name} -> {found_sp.sporcu_adi} (ID: {found_sp.id})"))

            # Kullanılmayan boşta kalmış "Maskeli sporcu (...)" kayıtlarını temizle
            orphan_qs = Sporcu.objects.filter(sporcu_adi__startswith="Maskeli sporcu").filter(yaris_sonuclari__isnull=True)
            orphan_count = orphan_qs.count()
            if orphan_count > 0:
                orphan_qs.delete()
                self.stdout.write(f"[*] {orphan_count} sahipsiz 'Maskeli sporcu' kaydı temizlendi.")

            self.stdout.write(self.style.SUCCESS(f"[+] Tamamlandı: {matched_count}/{total} kayıt gerçek sporcusuyla eşleştirildi."))
        elif options.get("daemon"):
            run_daemon_worker(poll_interval=options.get("aralik", 10), model=options.get("model", DEFAULT_MODEL))
        elif options.get("id"):
            yaris_id = options["id"]
            y = CanliYaris.objects.filter(id=yaris_id).first()
            if not y:
                self.stdout.write(self.style.ERROR(f"[!] ID {yaris_id} olan canlı yarış bulunamadı."))
                return
            cl = get_gemini_client()
            st = process_single_meet_db(y, cl, model=options.get("model", DEFAULT_MODEL), force=options.get("force", False))
            self.stdout.write(self.style.SUCCESS(f"[+] Sonuç: {st}"))
        elif options.get("kesfet") and not options.get("cron"):
            added = discover_new_meets_db()
            self.stdout.write(self.style.SUCCESS(f"[+] {added} yeni yarış keşfedildi."))
        else:
            # Varsayılan olarak (veya --cron ile) saatlik cron orkestratörünü çalıştır
            run_cron_orchestrator(kesfet=options.get("kesfet", False))
