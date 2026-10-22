# -*- coding: utf-8 -*-
from django.contrib import admin
from .models import Kulup, Sporcu, SporcuKulupTarihce, YarisSonucu, CanliYaris


@admin.register(CanliYaris)
class CanliYarisAdmin(admin.ModelAdmin):
    list_display = ('musabaka_adi', 'sehir', 'tarih', 'durum', 'islenen_start_listesi', 'toplam_start_listesi', 'eklenen_kayit_sayisi', 'son_islem_tarihi')
    search_fields = ('musabaka_adi', 'sehir', 'canli_url')
    list_filter = ('durum',)
    readonly_fields = ('islenen_start_listesi', 'toplam_start_listesi', 'islenen_sonuc_listesi', 'toplam_sonuc_listesi', 'eklenen_kayit_sayisi', 'son_islem_tarihi', 'olusturulma_tarihi', 'guncellenme_tarihi')


@admin.register(Kulup)
class KulupAdmin(admin.ModelAdmin):
    list_display = ('kulup_adi', 'toplam_sporcu_sayisi', 'toplam_yaris_sayisi', 'ilk_yaris_tarihi', 'son_yaris_tarihi')
    search_fields = ('kulup_adi',)
    ordering = ('-toplam_yaris_sayisi',)
    readonly_fields = ('toplam_sporcu_sayisi', 'toplam_yaris_sayisi', 'ilk_yaris_tarihi', 'son_yaris_tarihi')


@admin.register(Sporcu)
class SporcuAdmin(admin.ModelAdmin):
    list_display = ('sporcu_adi', 'dogum_yili', 'cinsiyet', 'birincil_kulup', 'toplam_yaris_sayisi', 'ilk_yaris_tarihi', 'son_yaris_tarihi')
    search_fields = ('sporcu_adi', 'birincil_kulup__kulup_adi')
    list_filter = ('cinsiyet',)
    ordering = ('sporcu_adi',)
    readonly_fields = ('toplam_yaris_sayisi', 'ilk_yaris_tarihi', 'son_yaris_tarihi')


@admin.register(SporcuKulupTarihce)
class SporcuKulupTarihceAdmin(admin.ModelAdmin):
    list_display = ('sporcu', 'kulup', 'donem_sirasi', 'ilk_yaris_tarihi', 'son_yaris_tarihi', 'toplam_yaris_sayisi', 'aktif_kulup_mu')
    search_fields = ('sporcu__sporcu_adi', 'kulup__kulup_adi')
    list_filter = ('aktif_kulup_mu',)
    ordering = ('sporcu__sporcu_adi', 'donem_sirasi')


@admin.register(YarisSonucu)
class YarisSonucuAdmin(admin.ModelAdmin):
    list_display = ('sporcu', 'kulup', 'mesafe', 'stil', 'derece', 'puan', 'sira', 'musabaka_adi', 'yaris_tarihi_baslangic')
    search_fields = ('sporcu__sporcu_adi', 'kulup__kulup_adi', 'musabaka_adi')
    list_filter = ('stil', 'mesafe', 'cinsiyet')
    ordering = ('-yaris_tarihi_baslangic',)
    readonly_fields = ('sporcu', 'kulup', 'sporcu_kulup_tarihce', 'derece_saniye', 'ham_satir')
