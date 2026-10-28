# -*- coding: utf-8 -*-
"""
Django Management Command: canli_tara
=====================================
Tam otomatik canlı yarış keşif, karar motoru ve doğrudan veritabanı (Django ORM) işleyicisi.

Çalışma Mantığı:
1. --kesfet parametresi verildiğinde TYF merkezi sayfası ve il temsilciliklerini tarar,
   yeni canlı yarışları doğrudan CanliYaris tablosuna ekler.
2. Bekleyen / işlemde olan yarışlar için karar motorunu (should_scan_meet_db / evaluate_single_meet) çalıştırır:
   - Start listeleri eksikse -> Hemen tarar ve veritabanına yazar.
   - Start listeleri tamamsa ve yarış ileri bir tarihteyse -> Yarış gününe kadar atlar.
   - Bugün yarış günüyse -> Yeni yayınlanan sonuç listelerini tarar ve veritabanına yazar.
"""

from django.core.management.base import BaseCommand
from django.db.models import Q

from sonuclar.models import CanliYaris
from sonuclar.live_db_runner import (
    DEFAULT_MODEL,
    discover_new_meets_db,
    get_gemini_client,
    is_meet_truly_completed,
    process_single_meet_db,
    should_scan_meet_db,
)


class Command(BaseCommand):
    help = "TYF canlı yarışlarını otomatik keşfeder ve doğrudan veritabanına (Django ORM) işler."

    def add_arguments(self, parser):
        parser.add_argument("--id", type=int, default=None, help="Belirli bir CanliYaris ID'sini zorla tara")
        parser.add_argument("--kesfet", action="store_true", help="TYF web sayfalarından yeni canlı yarışları keşfet ve ekle")
        parser.add_argument("--batch-size", type=int, default=None, help="Her turda işlenecek azami PDF sayısı (Varsayılan: Sınırsız / Tüm bekleyen dosyalar)")
        parser.add_argument("--limit", type=int, default=None, help="Test amaçlı işlenecek dosya sınırı")
        parser.add_argument("--model", type=str, default=DEFAULT_MODEL, help="Gemini model adı")

    def handle(self, *args, **options):
        if options.get("kesfet"):
            self.stdout.write("[*] TYF canlı sonuç sayfaları taranıyor...")
            added = discover_new_meets_db()
            self.stdout.write(self.style.SUCCESS(f"[*] Keşif tamamlandı ({added} yeni yarış eklendi)."))

        target_id = options.get("id")
        if target_id:
            meets = list(CanliYaris.objects.select_related("event").filter(id=target_id))
        else:
            # Eskiden sonuçlar bitmeden yanlışlıkla TAMAMLANDI yapılmış yarışları otomatik ISLENIYOR'a geri al
            for premature in CanliYaris.objects.select_related("event").filter(durum="TAMAMLANDI"):
                if not is_meet_truly_completed(premature):
                    premature.durum = "ISLENIYOR"
                    premature.save(update_fields=["durum"])
                    self.stdout.write(self.style.WARNING(
                        f"[!] Erken TAMAMLANDI işaretlenmiş yarış düzeltildi -> ISLENIYOR: {premature.musabaka_adi or premature.canli_url}"
                    ))

            qs = CanliYaris.objects.select_related("event").filter(
                Q(durum="BEKLIYOR") | Q(durum="ISLENIYOR")
            ).order_by("-olusturulma_tarihi")
            meets = []
            for y in qs:
                should_run, reason = should_scan_meet_db(y)
                self.stdout.write(f"[*] Karar Motoru: {reason}")
                if should_run:
                    meets.append(y)

        if not meets:
            self.stdout.write("[*] Şu an taranması gereken aktif canlı yarış bulunmadı.")
            return

        client = get_gemini_client()
        for yaris in meets:
            stats = process_single_meet_db(
                yaris=yaris,
                client=client,
                model=options["model"],
                batch_size=options["batch_size"],
                limit=options["limit"],
            )
            self.stdout.write(
                self.style.SUCCESS(
                    f"[+] Yarış #{yaris.id} ({yaris.musabaka_adi or yaris.canli_url}): "
                    f"Durum={stats['durum']}, Başarılı={stats['basarili']}, "
                    f"Atlanılan={stats['atlanilan']}, Kalan={stats['kalan_dosya']}"
                )
            )
