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
      - 'Ted Ankara Koleji Vakfı Özel Ortaokulu' -> True (Okul)
      - 'Beytepe Ortaokulu' -> True (Okul)
      - 'Özel Bademli Sınav Koleji' -> True (Okul)
      - 'İTÜ Geliştirme Vakfı Okulları Spor Kulübü' -> False (Resmi Spor Kulübü)
      - 'Ted Ankara Kolejliler Spor Kulübü' -> False (Resmi Spor Kulübü)
      - 'Bursa Kolejliler' -> False (Resmi Spor Kulübü)
      - 'Enka Spor Kulübü' -> False (Resmi Spor Kulübü)
    """
    if not club_name:
        return False
    name = club_name.strip()
    name_lower = name.lower()

    if name_lower == 'ferdi':
        return False

    # Resmi tescilli kulüp belirteçleri (bu ekler varsa okulla ilişkili olsa dahi resmi kulüptür)
    has_club_suffix = bool(re.search(
        r'(?:spor\s*kul[uü]b[uü]|(?:\b|[_\s])sk\b|(?:\b|[_\s])gsk\b|(?:\b|[_\s])skd\b|y[uü]zme\s*kul[uü]b[uü]|ihtisas|derne[gğ]i|belediye\s*spor|belediyespor|kolejliler)',
        name_lower
    ))
    if has_club_suffix:
        return False

    # Okul / MEB anahtar kelimeleri
    has_school_word = bool(re.search(
        r'(?:ilkokul|ortaokul|lise|imam\s*hatip|i\.?[oö]\.?okulu|kolej|okullar[ıi]|anaokul|bilsen|bilsem|kamp[uü]s)',
        name_lower
    ))
    if has_school_word:
        return True

    if re.search(r'(?:okulu|lisesi|koleji)$', name_lower):
        return True

    return False


class Kulup(models.Model):
    kulup_adi = models.CharField(max_length=255, unique=True, verbose_name="Kulüp Adı")
    toplam_sporcu_sayisi = models.IntegerField(default=0, verbose_name="Toplam Sporcu Sayısı")
    toplam_yaris_sayisi = models.IntegerField(default=0, verbose_name="Toplam Yarış Sayısı")
    ilk_yaris_tarihi = models.CharField(max_length=20, blank=True, null=True, verbose_name="İlk Yarış Tarihi")
    son_yaris_tarihi = models.CharField(max_length=20, blank=True, null=True, verbose_name="Son Yarış Tarihi")
    okul_mu = models.IntegerField(default=0, verbose_name="Okul mu?")

    class Meta:
        managed = False
        db_table = 'kulupler'
        verbose_name = "Kulüp"
        verbose_name_plural = "Kulüpler"
        ordering = ['-toplam_yaris_sayisi']

    def __str__(self):
        return self.kulup_adi


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
