# -*- coding: utf-8 -*-
from django.contrib import admin
from .models import Kulup, Sporcu, SporcuKulupTarihce, YarisSonucu, CanliYaris, Event, CanliYarisDosya


@admin.register(CanliYarisDosya)
class CanliYarisDosyaAdmin(admin.ModelAdmin):
    list_display = ('dosya_adi', 'event', 'dosya_turu', 'yaris_no', 'mesafe', 'stil', 'durum', 'kayit_sayisi', 'etag', 'content_hash', 'son_islem_tarihi')
    search_fields = ('dosya_adi', 'event__musabaka_adi', 'yaris_no', 'content_hash')
    list_filter = ('dosya_turu', 'durum')
    list_select_related = ('event', 'canli_yaris')
    readonly_fields = ('content_hash', 'etag', 'last_modified', 'dosya_boyutu', 'kayit_sayisi', 'son_kontrol_tarihi', 'son_islem_tarihi', 'olusturulma_tarihi', 'guncellenme_tarihi')



@admin.register(Event)
class EventAdmin(admin.ModelAdmin):
    list_display = ('musabaka_adi', 'sehir', 'yaris_tarihi_baslangic', 'yaris_tarihi_bitis', 'toplam_yaris_sayisi', 'toplam_sporcu_sayisi', 'kaynak_turu')
    search_fields = ('musabaka_adi', 'sehir')
    list_filter = ('kaynak_turu', 'sehir')
    ordering = ('-yaris_tarihi_baslangic',)
    readonly_fields = ('toplam_yaris_sayisi', 'toplam_sporcu_sayisi', 'olusturulma_tarihi', 'guncellenme_tarihi')


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
    list_display = ('sporcu', 'kulup', 'mesafe', 'stil', 'derece', 'puan', 'sira', 'event')
    search_fields = ('sporcu__sporcu_adi', 'kulup__kulup_adi', 'event__musabaka_adi')
    list_filter = ('stil', 'mesafe', 'cinsiyet')
    ordering = ('-event__yaris_tarihi_baslangic', '-id')
    list_select_related = ('sporcu', 'kulup', 'event')
    readonly_fields = ('sporcu', 'kulup', 'event', 'sporcu_kulup_tarihce', 'derece_saniye', 'ham_satir')
