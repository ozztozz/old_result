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
        sonuclar = self.yaris_sonuclari.filter(derece_saniye__isnull=False, derece_saniye__gt=0).order_by('derece_saniye')
        seen_events = set()
        best_list = []
        for s in sonuclar:
            key = (s.mesafe, s.stil)
            if key not in seen_events and s.mesafe and s.stil:
                seen_events.add(key)
                best_list.append(s)
        # Mesafeye ve stile göre sırala
        best_list.sort(key=lambda x: (x.mesafe or 0, x.stil or ""))
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


class YarisSonucu(models.Model):
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
    kaynak_turu = models.CharField(max_length=50, blank=True, null=True, verbose_name="Kaynak Türü")
    dosya_adi = models.CharField(max_length=255, blank=True, null=True, verbose_name="Dosya Adı")
    sayfa_no = models.IntegerField(blank=True, null=True, verbose_name="Sayfa No")
    satir_no = models.IntegerField(blank=True, null=True, verbose_name="Satır No")
    musabaka_adi = models.CharField(max_length=500, blank=True, null=True, verbose_name="Müsabaka Adı")
    sehir = models.CharField(max_length=100, blank=True, null=True, verbose_name="Şehir")
    yaris_tarihi_ham = models.CharField(max_length=100, blank=True, null=True, verbose_name="Yarış Tarihi (Ham)")
    yaris_tarihi_baslangic = models.CharField(max_length=20, blank=True, null=True, verbose_name="Yarış Tarihi (Başlangıç)")
    yaris_tarihi_bitis = models.CharField(max_length=20, blank=True, null=True, verbose_name="Yarış Tarihi (Bitiş)")
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

    class Meta:
        managed = False
        db_table = 'yaris_sonuclari'
        verbose_name = "Yarış Sonucu"
        verbose_name_plural = "Yarış Sonuçları"
        ordering = ['-yaris_tarihi_baslangic', 'id']

    def __str__(self):
        return f"{self.sporcu.sporcu_adi} - {self.mesafe}m {self.stil} ({self.derece})"
