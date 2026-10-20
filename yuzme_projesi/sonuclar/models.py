# -*- coding: utf-8 -*-
from django.db import models
from django.db.models import Min


class Kulup(models.Model):
    kulup_adi = models.CharField(max_length=255, unique=True, verbose_name="Kulüp Adı")
    toplam_sporcu_sayisi = models.IntegerField(default=0, verbose_name="Toplam Sporcu Sayısı")
    toplam_yaris_sayisi = models.IntegerField(default=0, verbose_name="Toplam Yarış Sayısı")
    ilk_yaris_tarihi = models.CharField(max_length=20, blank=True, null=True, verbose_name="İlk Yarış Tarihi")
    son_yaris_tarihi = models.CharField(max_length=20, blank=True, null=True, verbose_name="Son Yarış Tarihi")

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
        """Sporcunun en güncel/aktif kulübünü döner."""
        tarihce = self.kulup_tarihcesi.filter(aktif_kulup_mu=1).first()
        return tarihce.kulup if tarihce else self.birincil_kulup

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
