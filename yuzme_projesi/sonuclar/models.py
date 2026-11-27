# -*- coding: utf-8 -*-
import re
from django.db import models
from django.db.models import Min


def is_school_team(club_name: str) -> bool:
    """
    Bir kulüp adının resmi yüzme spor kulübü mü yoksa okul müsabakası (MEB)
    temsili mi olduğunu belirler.
    Örn:
      - 'Mehmet Aker İlkokulu' -> True (Okul)
      - '12 HAZİRAN ANADOLU LİSESİ' -> True (Okul)
      - 'Ted Ankara Koleji Vakfı Özel Ortaokulu' -> True (Okul)
      - 'İTÜ Geliştirme Vakfı Okulları Spor Kulübü' -> False (Resmi Spor Kulübü)
      - 'Ted Ankara Kolejliler Spor Kulübü' -> False (Resmi Spor Kulübü)
      - 'Enka Spor Kulübü' -> False (Resmi Spor Kulübü)
    """
    if not club_name:
        return False
    name = club_name.strip()
    name_lower = name.replace("\u0307", "").replace("İ", "i").replace("I", "ı").lower()

    if name_lower in ("ferdi", "bireysel"):
        return False

    # Resmi tescilli kulüp belirteçleri (bu ekler varsa okulla ilişkili olsa dahi resmi kulüptür)
    has_club_suffix = bool(re.search(
        r'(?:spor\s*kul[uü]b[uü]|(?:\b|[_\s])sk\b|(?:\b|[_\s])gsk\b|(?:\b|[_\s])skd\b|y[uü]zme\s*kul[uü]b[uü]|ihtisas|derne[gğ]i|belediye\s*spor|belediyespor|kolejliler|su\s*sporlar[ıi]|gen[çc]lik\s*ve\s*spor)',
        name_lower
    ))
    if has_club_suffix:
        return False

    # Okul / MEB anahtar kelimeleri
    has_school_word = bool(re.search(
        r'(?:[iı]lkokul|ortaokul|l[iı]se|imam\s*hatip|i\.?[oö]\.?okulu|a\.?i\.?h\.?l\.?|i\.?h\.?[ol]\.?|kolej|okull?ar[ıi]|anaokul|bilfen|bilsen|bilsem|kamp[uü]s|bilimler\s*akademisi)',
        name_lower
    ))
    if has_school_word:
        return True

    if re.search(r'(?:okulu|l[iı]ses[iı]|koleji|\bok|\bo\.?o\.?|\ba\.?l\.?|\bf\.?l\.?)$', name_lower):
        return True

    return False


class Kulup(models.Model):
    kulup_adi = models.CharField(max_length=255, unique=True, verbose_name="Kulüp Adı")
    il = models.CharField(max_length=100, blank=True, null=True, verbose_name="İl")
    toplam_sporcu_sayisi = models.IntegerField(default=0, verbose_name="Toplam Sporcu Sayısı")
    toplam_yaris_sayisi = models.IntegerField(default=0, verbose_name="Toplam Yarış Sayısı")
    ilk_yaris_tarihi = models.CharField(max_length=20, blank=True, null=True, verbose_name="İlk Yarış Tarihi")
    son_yaris_tarihi = models.CharField(max_length=20, blank=True, null=True, verbose_name="Son Yarış Tarihi")
    okul_mu = models.IntegerField(default=0, verbose_name="Okul mu?")
    adres = models.TextField(blank=True, null=True, verbose_name="Adres")
    telefon = models.CharField(max_length=100, blank=True, null=True, verbose_name="Telefon")
    web_sitesi = models.CharField(max_length=500, blank=True, null=True, verbose_name="Web Sitesi")
    google_maps_url = models.CharField(max_length=500, blank=True, null=True, verbose_name="Google Maps URL")
    instagram = models.CharField(max_length=500, blank=True, null=True, verbose_name="Instagram")
    facebook = models.CharField(max_length=500, blank=True, null=True, verbose_name="Facebook")
    enlem = models.FloatField(blank=True, null=True, verbose_name="Enlem (Latitude)")
    boylam = models.FloatField(blank=True, null=True, verbose_name="Boylam (Longitude)")
    iletisim_guncellenme_tarihi = models.CharField(max_length=30, blank=True, null=True, verbose_name="İletişim Güncellenme Tarihi")

    class Meta:
        managed = False
        db_table = 'kulupler'
        verbose_name = "Kulüp"
        verbose_name_plural = "Kulüpler"
        ordering = ['-toplam_yaris_sayisi']

    def __str__(self):
        return self.kulup_adi

    def build_summary(self) -> dict:
        """Sporcu adları olmadan kulübün performans ve son 1 yılda aktif sporcu yaş/cinsiyet özetini döner."""
        from datetime import date, timedelta
        from django.db.models import Avg, Count, Max
        from .sqlite_tr import normalize_il_adi

        today = date.today()
        cutoff_str = (today - timedelta(days=365)).strftime('%Y-%m-%d')

        th_qs = self.sporcu_tarihcesi.select_related('sporcu')
        aktif_qs = th_qs.filter(aktif_kulup_mu=1, son_yaris_tarihi__gte=cutoff_str)
        aktif_sporcu = aktif_qs.count()
        toplam_th = th_qs.count()
        gecmis_sporcu = max(0, toplam_th - aktif_sporcu)

        erkek_sayisi = aktif_qs.filter(sporcu__cinsiyet__iexact='Erkek').count()
        kadin_sayisi = aktif_qs.filter(sporcu__cinsiyet__iregex=r'^(kad[ıi]n|k|bayan)$').count()

        ys_qs = self.yaris_sonuclari
        agg = ys_qs.aggregate(
            max_puan=Max('puan'),
            avg_puan=Avg('puan'),
            musabaka_sayisi=Count('event_id', distinct=True),
        )

        sira_counts = dict(
            ys_qs.filter(sira__in=['1', '1.', '2', '2.', '3', '3.'])
            .values_list('sira')
            .annotate(c=Count('id'))
        )
        altin = sira_counts.get('1', 0) + sira_counts.get('1.', 0)
        gumus = sira_counts.get('2', 0) + sira_counts.get('2.', 0)
        bronz = sira_counts.get('3', 0) + sira_counts.get('3.', 0)

        sehir_set = set()
        for (raw_sehir,) in (
            ys_qs.filter(event__sehir__isnull=False)
            .exclude(event__sehir='')
            .values_list('event__sehir')
            .distinct()
        ):
            norm = normalize_il_adi(raw_sehir)
            if norm:
                sehir_set.add(norm)

        current_year = today.year
        age_buckets = [
            ('10 Yaş ve Altı', 0, 10),
            ('11-12 Yaş', 11, 12),
            ('13-14 Yaş', 13, 14),
            ('15-17 Yaş', 15, 17),
            ('18+ Yaş', 18, 120),
        ]
        bucket_stats = [{'total': 0, 'erkek': 0, 'kadin': 0} for _ in age_buckets]
        for dy, cins, cnt in (
            aktif_qs.filter(sporcu__dogum_yili__isnull=False)
            .values_list('sporcu__dogum_yili', 'sporcu__cinsiyet')
            .annotate(c=Count('id'))
        ):
            age = current_year - dy
            cins_u = (cins or '').strip().upper()
            for idx, (_, low, high) in enumerate(age_buckets):
                if low <= age <= high:
                    bucket_stats[idx]['total'] += cnt
                    if cins_u in ('ERKEK', 'E'):
                        bucket_stats[idx]['erkek'] += cnt
                    elif cins_u in ('KADIN', 'KADİN', 'K', 'BAYAN'):
                        bucket_stats[idx]['kadin'] += cnt
                    break

        yas_toplam = sum(b['total'] for b in bucket_stats) or 1
        yas_dagilimi = [
            {
                'grup': label,
                'sayi': bucket_stats[idx]['total'],
                'erkek': bucket_stats[idx]['erkek'],
                'kadin': bucket_stats[idx]['kadin'],
                'oran': round((bucket_stats[idx]['total'] / yas_toplam) * 100),
            }
            for idx, (label, _, _) in enumerate(age_buckets)
            if bucket_stats[idx]['total'] > 0
        ]

        return {
            'aktif_sporcu_sayisi': aktif_sporcu,
            'gecmis_sporcu_sayisi': gecmis_sporcu,
            'erkek_sayisi': erkek_sayisi,
            'kadin_sayisi': kadin_sayisi,
            'musabaka_sayisi': agg['musabaka_sayisi'] or 0,
            'farkli_il_sayisi': len(sehir_set),
            'max_puan': agg['max_puan'],
            'avg_puan': round(agg['avg_puan']) if agg['avg_puan'] else None,
            'altin': altin,
            'gumus': gumus,
            'bronz': bronz,
            'toplam_madalya': altin + gumus + bronz,
            'yas_dagilimi': yas_dagilimi,
        }


class Sporcu(models.Model):
    sporcu_adi = models.CharField(max_length=255, verbose_name="Sporcu Adı")
    dogum_yili = models.IntegerField(blank=True, null=True, verbose_name="Hesaplanan Doğum Yılı")
    yas_dogum_yili = models.CharField(max_length=20, blank=True, null=True, verbose_name="Yaş / Doğum Yılı Metni")
    cinsiyet = models.CharField(max_length=20, blank=True, null=True, verbose_name="Cinsiyet")
    birincil_kulup = models.ForeignKey(
        Kulup,
        models.SET_NULL,
        blank=True,
        null=True,
        db_column='birincil_kulup_id',
        related_name='birincil_sporcular',
        verbose_name="Birincil Kulüp"
    )
    toplam_yaris_sayisi = models.IntegerField(default=0, verbose_name="Toplam Yarış Sayısı")
    ilk_yaris_tarihi = models.CharField(max_length=20, blank=True, null=True, verbose_name="İlk Yarış Tarihi")
    son_yaris_tarihi = models.CharField(max_length=20, blank=True, null=True, verbose_name="Son Yarış Tarihi")

    class Meta:
        managed = False
        db_table = 'sporcular'
        verbose_name = "Sporcu"
        verbose_name_plural = "Sporcular"
        ordering = ['sporcu_adi']

    def __str__(self):
        if self.dogum_yili:
            return f"{self.sporcu_adi} (D.Yılı: {self.dogum_yili})"
        if self.yas_dogum_yili:
            return f"{self.sporcu_adi} ({self.yas_dogum_yili})"
        return self.sporcu_adi

    def aktif_kulup(self):
        """
        Sporcunun en güncel/aktif resmi spor kulübünü döner.
        Okul Sporları takımları yerine tescilli spor kulüplerine öncelik verir.
        """
        # 1. Okul olmayan (okul_mu=0) tarihçeler arasından aktif olanı veya en son yarışılanı bul
        tarihce = self.kulup_tarihcesi.select_related('kulup').filter(kulup__okul_mu=0, aktif_kulup_mu=1).first()
        if not tarihce:
            tarihce = self.kulup_tarihcesi.select_related('kulup').filter(kulup__okul_mu=0).order_by('-son_yaris_tarihi', '-id').first()

        if tarihce:
            return tarihce.kulup

        # 2. Sporcunun sadece okul/ferdi kaydı varsa
        t_any = self.kulup_tarihcesi.select_related('kulup').order_by('-son_yaris_tarihi', '-id').first()
        return t_any.kulup if t_any else self.birincil_kulup

    def okul(self):
        """Sporcunun Okul Sporları müsabakalarında temsil ettiği en güncel okulu döner (varsa)."""
        tarihce = self.kulup_tarihcesi.select_related('kulup').filter(kulup__okul_mu=1).order_by('-son_yaris_tarihi', '-id').first()
        return tarihce.kulup.kulup_adi if tarihce else None

    def en_iyi_dereceler(self):
        """Sporcunun branş ve mesafelere göre kişisel en iyi derecelerini (PB) döner."""
        # Geçerli derece saniyesi olan yarışları al
        sonuclar = self.yaris_sonuclari.select_related('kulup', 'event').filter(
            derece_saniye__isnull=False,
            derece_saniye__gt=0
        ).order_by('derece_saniye')

        seen_events = set()
        best_list = []
        for s in sonuclar:
            key = (s.mesafe, s.stil)
            if key not in seen_events and s.mesafe and s.stil:
                seen_events.add(key)
                best_list.append(s)

        # Standart stil sıralaması: Serbest, Sırtüstü, Kurbağalama, Kelebek, Karışık
        stil_oncelik = {
            'SERBEST': 1,
            'SIRTUSTU': 2,
            'SIRTÜSTÜ': 2,
            'KURBAGALAMA': 3,
            'KURBAĞALAMA': 3,
            'KELEBEK': 4,
            'KARISIK': 5,
            'KARIŞIK': 5
        }

        def event_sort_key(item):
            s_norm = (item.stil or '').strip().upper()
            st_rank = stil_oncelik.get(s_norm, 99)
            return (st_rank, item.mesafe or 0)

        best_list.sort(key=event_sort_key)
        return best_list


class SporcuKulupTarihce(models.Model):
    sporcu = models.ForeignKey(
        Sporcu,
        models.CASCADE,
        db_column='sporcu_id',
        related_name='kulup_tarihcesi',
        verbose_name="Sporcu"
    )
    kulup = models.ForeignKey(
        Kulup,
        models.CASCADE,
        db_column='kulup_id',
        related_name='sporcu_tarihcesi',
        verbose_name="Kulüp"
    )
    ilk_yaris_tarihi = models.CharField(max_length=20, blank=True, null=True, verbose_name="İlk Yarış Tarihi")
    son_yaris_tarihi = models.CharField(max_length=20, blank=True, null=True, verbose_name="Son Yarış Tarihi")
    toplam_yaris_sayisi = models.IntegerField(default=0, verbose_name="Toplam Yarış Sayısı")
    donem_sirasi = models.IntegerField(default=1, verbose_name="Dönem Sırası")
    aktif_kulup_mu = models.IntegerField(default=0, verbose_name="Aktif Kulüp mü?")

    class Meta:
        managed = False
        db_table = 'sporcu_kulup_tarihce'
        verbose_name = "Sporcu Kulüp Tarihçesi"
        verbose_name_plural = "Sporcu Kulüp Tarihçeleri"
        ordering = ['donem_sirasi']

    def __str__(self):
        return f"{self.sporcu.sporcu_adi} -> {self.kulup.kulup_adi} ({self.donem_sirasi}. Dönem)"


class Event(models.Model):
    musabaka_adi = models.CharField(max_length=500, verbose_name="Müsabaka Adı")
    sehir = models.CharField(max_length=100, blank=True, null=True, verbose_name="Şehir")
    yaris_tarihi_ham = models.CharField(max_length=100, blank=True, null=True, verbose_name="Yarış Tarihi (Ham)")
    yaris_tarihi_baslangic = models.CharField(max_length=20, blank=True, null=True, db_index=True, verbose_name="Yarış Tarihi (Başlangıç)")
    yaris_tarihi_bitis = models.CharField(max_length=20, blank=True, null=True, verbose_name="Yarış Tarihi (Bitiş)")
    kaynak_turu = models.CharField(max_length=50, blank=True, null=True, verbose_name="Varsayılan Kaynak Türü")
    yas_grubu = models.CharField(max_length=255, blank=True, null=True, verbose_name="Yaş Grubu / Kategori")
    min_yas = models.IntegerField(blank=True, null=True, verbose_name="Min Yaş")
    max_yas = models.IntegerField(blank=True, null=True, verbose_name="Max Yaş")
    havuz = models.CharField(max_length=30, blank=True, null=True, verbose_name="Havuz (25m/50m)")
    toplam_yaris_sayisi = models.IntegerField(default=0, verbose_name="Toplam Yarış Sayısı")
    toplam_sporcu_sayisi = models.IntegerField(default=0, verbose_name="Toplam Sporcu Sayısı")
    olusturulma_tarihi = models.DateTimeField(auto_now_add=True, verbose_name="Oluşturulma Tarihi")
    guncellenme_tarihi = models.DateTimeField(auto_now=True, verbose_name="Güncellenme Tarihi")

    class Meta:
        managed = False
        db_table = 'events'
        verbose_name = "Müsabaka (Event)"
        verbose_name_plural = "Müsabakalar (Events)"
        ordering = ['-yaris_tarihi_baslangic', 'musabaka_adi']

    def __str__(self):
        return f"{self.musabaka_adi} ({self.sehir or '-'} / {self.yaris_tarihi_baslangic or '-'})"


class YarisSonucu(models.Model):
    event = models.ForeignKey(
        Event,
        models.CASCADE,
        blank=True,
        null=True,
        db_column='event_id',
        related_name='yaris_sonuclari',
        verbose_name="Müsabaka (Event)"
    )
    sporcu = models.ForeignKey(
        Sporcu,
        models.CASCADE,
        db_column='sporcu_id',
        related_name='yaris_sonuclari',
        verbose_name="Sporcu"
    )
    kulup = models.ForeignKey(
        Kulup,
        models.SET_NULL,
        blank=True,
        null=True,
        db_column='kulup_id',
        related_name='yaris_sonuclari',
        verbose_name="Kulüp"
    )
    sporcu_kulup_tarihce = models.ForeignKey(
        SporcuKulupTarihce,
        models.SET_NULL,
        blank=True,
        null=True,
        db_column='sporcu_kulup_tarihce_id',
        related_name='yaris_sonuclari',
        verbose_name="Kulüp Tarihçesi"
    )
    canli_dosya = models.ForeignKey(
        'CanliYarisDosya',
        models.SET_NULL,
        blank=True,
        null=True,
        db_column='canli_dosya_id',
        related_name='yaris_sonuclari',
        verbose_name="Canlı Dosya"
    )
    kaynak_turu = models.CharField(max_length=50, blank=True, null=True, verbose_name="Kaynak Türü")
    dosya_adi = models.CharField(max_length=255, blank=True, null=True, verbose_name="Dosya Adı")
    sayfa_no = models.IntegerField(blank=True, null=True, verbose_name="Sayfa No")
    satir_no = models.IntegerField(blank=True, null=True, verbose_name="Satır No")
    yaris_no = models.CharField(max_length=50, blank=True, null=True, verbose_name="Yarış No")
    gun = models.IntegerField(blank=True, null=True, verbose_name="Gün")
    tahmini_saat = models.CharField(max_length=10, blank=True, null=True, verbose_name="Tahmini Başlangıç Saati")
    cinsiyet = models.CharField(max_length=20, blank=True, null=True, verbose_name="Cinsiyet")
    mesafe = models.IntegerField(blank=True, null=True, verbose_name="Mesafe (m)")
    stil = models.CharField(max_length=50, blank=True, null=True, verbose_name="Stil")
    yas_grubu = models.CharField(max_length=50, blank=True, null=True, verbose_name="Yaş Grubu")
    sporcu_yas = models.CharField(max_length=20, blank=True, null=True, verbose_name="Sporcu Yaşı (Ham)")
    hesaplanan_yas = models.IntegerField(blank=True, null=True, verbose_name="Hesaplanan Yarış Yaşı")
    sira = models.CharField(max_length=20, blank=True, null=True, verbose_name="Sıra")
    seri = models.CharField(max_length=50, blank=True, null=True, verbose_name="Seri / Yarış Sırası")
    kulvar = models.IntegerField(blank=True, null=True, verbose_name="Kulvar")
    giris_derecesi = models.CharField(max_length=50, blank=True, null=True, verbose_name="Yarış Başlangıç Derecesi")
    derece = models.CharField(max_length=50, blank=True, null=True, verbose_name="Derece")
    derece_saniye = models.FloatField(blank=True, null=True, verbose_name="Derece (Saniye)")
    puan = models.IntegerField(blank=True, null=True, verbose_name="Puan")
    baraj = models.CharField(max_length=50, blank=True, null=True, verbose_name="Baraj")
    beraberlik_mi = models.CharField(max_length=10, blank=True, null=True, verbose_name="Beraberlik")
    zaman_kontrolu = models.CharField(max_length=50, blank=True, null=True, verbose_name="Zaman Kontrolü")
    uyari_notu = models.TextField(blank=True, null=True, verbose_name="Uyarı Notu")
    ham_satir = models.TextField(blank=True, null=True, verbose_name="Ham Satır")
    sporcu_maskeli = models.CharField(
        max_length=255,
        blank=True,
        null=True,
        verbose_name="PDF Maskeli Sporcu Adı",
    )
    ara_dereceler = models.JSONField(
        blank=True,
        null=True,
        verbose_name="Ara Dereceler",
    )

    class Meta:
        managed = False
        db_table = 'yaris_sonuclari'
        verbose_name = "Yarış Sonucu"
        verbose_name_plural = "Yarış Sonuçları"
        ordering = ['-event__yaris_tarihi_baslangic', 'id']

    def __str__(self):
        return f"{self.sporcu.sporcu_adi} - {self.mesafe}m {self.stil} ({self.derece})"

    @property
    def musabaka_adi(self):
        return self.event.musabaka_adi if self.event else None

    @property
    def sehir(self):
        return self.event.sehir if self.event else None

    @property
    def yaris_tarihi_ham(self):
        return self.event.yaris_tarihi_ham if self.event else None

    @property
    def yaris_tarihi_baslangic(self):
        return self.event.yaris_tarihi_baslangic if self.event else None

    @property
    def yaris_tarihi_bitis(self):
        return self.event.yaris_tarihi_bitis if self.event else None


class CanliYaris(models.Model):
    DURUM_CHOICES = [
        ('BEKLIYOR', 'Bekliyor'),
        ('ISLENIYOR', 'İşleniyor'),
        ('TAMAMLANDI', 'Tamamlandı'),
        ('HATA', 'Hata'),
    ]

    event = models.ForeignKey(
        Event,
        models.SET_NULL,
        blank=True,
        null=True,
        db_column='event_id',
        related_name='canli_yarislar',
        verbose_name="Müsabaka (Event)"
    )
    musabaka_adi = models.CharField(max_length=255, blank=True, null=True, verbose_name="Müsabaka Adı")
    sehir = models.CharField(max_length=100, blank=True, null=True, verbose_name="Şehir")
    tarih = models.CharField(max_length=50, blank=True, null=True, verbose_name="Tarih")
    canli_url = models.URLField(max_length=500, verbose_name="TYF Canlı Yarış Linki")
    reglaman_linki = models.URLField(max_length=500, blank=True, null=True, verbose_name="Reglaman Linki")
    barajlar = models.JSONField(default=dict, blank=True, null=True, verbose_name="Barajlar (JSON)")
    durum = models.CharField(max_length=20, choices=DURUM_CHOICES, default='BEKLIYOR', verbose_name="Durum")
    toplam_start_listesi = models.IntegerField(default=0, verbose_name="Toplam Start Listesi")
    islenen_start_listesi = models.IntegerField(default=0, verbose_name="İşlenen Start Listesi")
    toplam_sonuc_listesi = models.IntegerField(default=0, verbose_name="Toplam Sonuç Listesi")
    islenen_sonuc_listesi = models.IntegerField(default=0, verbose_name="İşlenen Sonuç Listesi")
    eklenen_kayit_sayisi = models.IntegerField(default=0, verbose_name="Eklenen Kayıt Sayısı")
    hata_mesaji = models.TextField(blank=True, null=True, verbose_name="Hata / Uyarı Notu")
    son_islem_tarihi = models.DateTimeField(blank=True, null=True, verbose_name="Son İşlem Tarihi")
    olusturulma_tarihi = models.DateTimeField(auto_now_add=True, verbose_name="Oluşturulma Tarihi")
    guncellenme_tarihi = models.DateTimeField(auto_now=True, verbose_name="Güncellenme Tarihi")

    class Meta:
        managed = False
        db_table = 'canli_yarislar'
        verbose_name = "Canlı Yarış Takibi"
        verbose_name_plural = "Canlı Yarış Takipleri"
        ordering = ['-olusturulma_tarihi']

    def __str__(self):
        return self.musabaka_adi or self.canli_url

    @property
    def gosterilen_sehir(self):
        if self.sehir:
            return self.sehir
        if self.event_id and self.event:
            return self.event.sehir or "-"
        return "-"

    @property
    def gosterilen_tarih(self):
        if self.tarih:
            return self.tarih
        if self.event_id and self.event:
            return self.event.yaris_tarihi_baslangic or self.event.yaris_tarihi_ham or ""
        return ""


class CanliYarisDosya(models.Model):
    DURUM_CHOICES = [
        ('BEKLIYOR', 'Bekliyor'),
        ('ISLENDI', 'İşlendi'),
        ('DEGISTI', 'Değişti'),
        ('HATA', 'Hata'),
    ]
    TUR_CHOICES = [
        ('START_LISTESI', 'Start Listesi'),
        ('SONUC_LISTESI', 'Sonuç Listesi'),
    ]

    event = models.ForeignKey(
        Event,
        models.CASCADE,
        db_column='event_id',
        related_name='canli_dosyalar',
        verbose_name="Müsabaka (Event)"
    )
    canli_yaris = models.ForeignKey(
        CanliYaris,
        models.SET_NULL,
        blank=True,
        null=True,
        db_column='canli_yaris_id',
        related_name='dosyalar',
        verbose_name="Canlı Yarış Oturumu"
    )
    dosya_adi = models.CharField(max_length=255, verbose_name="Dosya Adı")
    dosya_url = models.URLField(max_length=500, blank=True, null=True, verbose_name="Dosya Linki")
    dosya_turu = models.CharField(max_length=20, choices=TUR_CHOICES, default='START_LISTESI', verbose_name="Dosya Türü")
    yaris_no = models.CharField(max_length=50, blank=True, null=True, verbose_name="Yarış No")
    gun = models.IntegerField(blank=True, null=True, verbose_name="Gün")
    tahmini_saat = models.CharField(max_length=10, blank=True, null=True, verbose_name="Tahmini Başlangıç Saati")
    mesafe = models.IntegerField(blank=True, null=True, verbose_name="Mesafe")
    stil = models.CharField(max_length=50, blank=True, null=True, verbose_name="Stil")
    cinsiyet = models.CharField(max_length=20, blank=True, null=True, verbose_name="Cinsiyet")
    yas_grubu = models.CharField(max_length=50, blank=True, null=True, verbose_name="Yaş Grubu")

    # HTTP & Hash Takip Alanları
    etag = models.CharField(max_length=150, blank=True, null=True, verbose_name="ETag")
    last_modified = models.CharField(max_length=100, blank=True, null=True, verbose_name="Last-Modified")
    content_hash = models.CharField(max_length=64, blank=True, null=True, verbose_name="SHA-256 Hash")
    dosya_boyutu = models.IntegerField(blank=True, null=True, verbose_name="Dosya Boyutu (Byte)")

    durum = models.CharField(max_length=20, choices=DURUM_CHOICES, default='BEKLIYOR', verbose_name="Durum")
    kayit_sayisi = models.IntegerField(default=0, verbose_name="Aktarılan Kayıt Sayısı")
    hata_mesaji = models.TextField(blank=True, null=True, verbose_name="Hata Mesajı")
    son_kontrol_tarihi = models.DateTimeField(blank=True, null=True, verbose_name="Son Kontrol Tarihi")
    son_islem_tarihi = models.DateTimeField(blank=True, null=True, verbose_name="Son İşlem Tarihi")
    olusturulma_tarihi = models.DateTimeField(auto_now_add=True, verbose_name="Oluşturulma Tarihi")
    guncellenme_tarihi = models.DateTimeField(auto_now=True, verbose_name="Güncellenme Tarihi")

    class Meta:
        managed = False
        db_table = 'canli_yaris_dosyalari'
        verbose_name = "Canlı Yarış Dosyası"
        verbose_name_plural = "Canlı Yarış Dosyaları"
        ordering = ['yaris_no', 'dosya_turu']

    def __str__(self):
        return f"{self.dosya_adi} ({self.get_dosya_turu_display()} - {self.durum})"


class MobilUygulamaSurumu(models.Model):
    surum_adi = models.CharField(max_length=50, verbose_name="Sürüm Adı (örn: 1.0.0)")
    surum_kodu = models.PositiveIntegerField(default=1, verbose_name="Sürüm Kodu (Build)")
    dosya = models.FileField(upload_to="apk/", verbose_name="APK Dosyası")
    dosya_boyutu_mb = models.DecimalField(max_digits=6, decimal_places=2, default=0.00, verbose_name="Dosya Boyutu (MB)")
    degisiklik_notlari = models.TextField(blank=True, verbose_name="Yenilikler / Değişiklik Notları")
    zorunlu_guncelleme = models.BooleanField(default=False, verbose_name="Zorunlu Güncelleme")
    aktif = models.BooleanField(default=True, verbose_name="İndirmeye Açık")
    indirme_sayisi = models.PositiveIntegerField(default=0, verbose_name="Toplam İndirme Sayısı")
    olusturulma_tarihi = models.DateTimeField(auto_now_add=True, verbose_name="Yüklenme Tarihi")
    guncellenme_tarihi = models.DateTimeField(auto_now=True, verbose_name="Son Güncelleme")

    class Meta:
        db_table = 'mobil_uygulama_surumleri'
        verbose_name = "Mobil Uygulama Sürümü"
        verbose_name_plural = "Mobil Uygulama Sürümleri"
        ordering = ['-surum_kodu', '-olusturulma_tarihi']

    def __str__(self):
        return f"Yüzme Sonuçları v{self.surum_adi} (Build {self.surum_kodu})"

    def save(self, *args, **kwargs):
        if self.dosya:
            try:
                size_mb = self.dosya.size / (1024 * 1024)
                self.dosya_boyutu_mb = round(size_mb, 2)
            except Exception:
                pass
        super().save(*args, **kwargs)


class TyfBelge(models.Model):
    TUR_CHOICES = [
        ('TAKVIM', 'Faaliyet Takvimi'),
        ('REGLAMAN', 'Müsabaka Reglamanı'),
        ('MILLI_TAKIM', 'Milli Takım Kriterleri'),
        ('DUYURU', 'Duyuru / Genelge'),
    ]

    belge_turu = models.CharField(max_length=20, choices=TUR_CHOICES, default='DUYURU', db_index=True, verbose_name="Belge Türü")
    baslik = models.CharField(max_length=500, verbose_name="Belge Başlığı")
    revizyon_etiketi = models.CharField(max_length=100, blank=True, null=True, verbose_name="Revizyon Etiketi")
    kaynak_sayfa = models.URLField(max_length=500, blank=True, null=True, verbose_name="Kaynak Sayfa")
    kaynak_url = models.URLField(max_length=700, unique=True, verbose_name="TYF Dosya URL")
    yerel_dosya = models.FileField(upload_to="tyf_belgeler/%Y-%m/", blank=True, null=True, verbose_name="Yerel PDF Dosyası")

    tarih_metni = models.CharField(max_length=150, blank=True, null=True, verbose_name="Tarih Metni")
    baslangic_tarihi = models.CharField(max_length=20, blank=True, null=True, db_index=True, verbose_name="Başlangıç Tarihi")
    bitis_tarihi = models.CharField(max_length=20, blank=True, null=True, verbose_name="Bitiş Tarihi")
    sehir_yer = models.CharField(max_length=200, blank=True, null=True, verbose_name="Şehir / Yer")
    havuz = models.CharField(max_length=30, blank=True, null=True, verbose_name="Havuz")
    yas_grubu = models.CharField(max_length=255, blank=True, null=True, verbose_name="Yaş Grubu")
    min_yas = models.IntegerField(blank=True, null=True, verbose_name="Min Yaş")
    max_yas = models.IntegerField(blank=True, null=True, verbose_name="Max Yaş")

    ozet = models.TextField(blank=True, null=True, verbose_name="Haber Bandı Özeti")
    onemli_notlar = models.JSONField(default=list, blank=True, verbose_name="Önemli Notlar")
    baraj_gecerlilik_metni = models.CharField(max_length=150, blank=True, null=True, verbose_name="Baraj Geçerlilik Tarihi (Metin)")
    baraj_gecerlilik_baslangic = models.CharField(max_length=20, blank=True, null=True, verbose_name="Baraj Geçerlilik Başlangıç")
    baraj_gecerlilik_bitis = models.CharField(max_length=20, blank=True, null=True, verbose_name="Baraj Geçerlilik Bitiş")
    gemini_json = models.JSONField(default=dict, blank=True, verbose_name="Gemini Analiz Çıktısı")

    event = models.ForeignKey(
        Event,
        models.SET_NULL,
        blank=True,
        null=True,
        related_name='tyf_belgeler',
        verbose_name="İlişkili Müsabaka (Event)",
    )

    etag = models.CharField(max_length=150, blank=True, null=True, verbose_name="ETag")
    last_modified = models.CharField(max_length=100, blank=True, null=True, verbose_name="Last-Modified")
    content_hash = models.CharField(max_length=64, blank=True, null=True, db_index=True, verbose_name="SHA-256 Hash")
    aktif = models.BooleanField(default=True, db_index=True, verbose_name="Haber Bandında Göster")
    son_kontrol_tarihi = models.DateTimeField(blank=True, null=True, verbose_name="Son Kontrol Tarihi")
    olusturulma_tarihi = models.DateTimeField(auto_now_add=True, verbose_name="Oluşturulma Tarihi")
    guncellenme_tarihi = models.DateTimeField(auto_now=True, verbose_name="Güncellenme Tarihi")

    class Meta:
        db_table = 'tyf_belgeler'
        verbose_name = "TYF Belgesi"
        verbose_name_plural = "TYF Belgeleri"
        ordering = ['-guncellenme_tarihi', '-olusturulma_tarihi']

    def __str__(self):
        return f"[{self.belge_turu}] {self.baslik}"


class BarajKurali(models.Model):
    belge = models.ForeignKey(
        TyfBelge,
        models.CASCADE,
        blank=True,
        null=True,
        related_name='baraj_kurallari',
        verbose_name="Kaynak Belge",
    )
    event = models.ForeignKey(
        Event,
        models.SET_NULL,
        blank=True,
        null=True,
        related_name='baraj_kurallari',
        verbose_name="İlişkili Müsabaka (Event)",
    )
    baraj_adi = models.CharField(max_length=300, verbose_name="Baraj Adı")
    baraj_turu = models.CharField(max_length=60, default='Katılım Barajı', db_index=True, verbose_name="Baraj Türü")
    havuz = models.CharField(max_length=20, blank=True, null=True, db_index=True, verbose_name="Havuz")
    cinsiyet = models.CharField(max_length=20, db_index=True, verbose_name="Cinsiyet")
    yas_etiketi = models.CharField(max_length=100, blank=True, null=True, verbose_name="Yaş Etiketi")
    dogum_yillari = models.JSONField(default=list, blank=True, verbose_name="Doğum Yılları")
    max_dogum_yili = models.IntegerField(blank=True, null=True, verbose_name="Max Doğum Yılı (Açık Uçlu)")
    min_yas = models.IntegerField(blank=True, null=True, verbose_name="Min Yaş")
    max_yas = models.IntegerField(blank=True, null=True, verbose_name="Max Yaş")
    mesafe = models.IntegerField(db_index=True, verbose_name="Mesafe")
    stil = models.CharField(max_length=50, db_index=True, verbose_name="Stil")
    sure = models.CharField(max_length=30, verbose_name="Baraj Süresi")
    sure_saniye = models.FloatField(verbose_name="Süre (Saniye)")
    sure_cs = models.IntegerField(verbose_name="Süre (Salise/CS)")
    olusturulma_tarihi = models.DateTimeField(auto_now_add=True, verbose_name="Oluşturulma Tarihi")

    class Meta:
        db_table = 'baraj_kurallari'
        verbose_name = "Baraj Kuralı"
        verbose_name_plural = "Baraj Kuralları"
        ordering = ['baraj_adi', 'havuz', 'cinsiyet', 'mesafe', 'stil']

    def __str__(self):
        return f"{self.baraj_adi} | {self.cinsiyet} {self.yas_etiketi} {self.mesafe}m {self.stil}: {self.sure}"
