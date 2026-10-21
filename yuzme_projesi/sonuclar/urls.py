# -*- coding: utf-8 -*-
from django.urls import path
from . import views

app_name = 'sonuclar'

urlpatterns = [
    path('', views.index, name='index'),
    path('sporcular/', views.sporcu_listesi, name='sporcu_listesi'),
    path('sporcular/<int:pk>/', views.sporcu_detay, name='sporcu_detay'),
    path('kulupler/', views.kulup_listesi, name='kulup_listesi'),
    path('kulupler/<int:pk>/', views.kulup_detay, name='kulup_detay'),
    path('sonuclar/', views.yaris_sonuclari_ara, name='yaris_sonuclari_ara'),
    path('sporcu-eslestirme/', views.sporcu_eslestir_sayfasi, name='sporcu_eslestir_sayfasi'),
    path('api/sporcu-ara/', views.api_sporcu_ara, name='api_sporcu_ara'),
    path('api/sporcu-eslestir/', views.api_sporcu_eslestir, name='api_sporcu_eslestir'),
    path('api/sporcular/<int:sporcu_id>/sonuclar/', views.api_sporcu_sonuclari, name='api_sporcu_sonuclari'),
    path('api/sporcular/<int:sporcu_id>/sonuclar/<str:kategori>/<int:mesafe>/', views.api_sporcu_sonuclari, name='api_sporcu_kategori_mesafe_sonuclari'),
    path('api/sporcular/<int:sporcu_id>/<str:kategori>/<int:mesafe>/', views.api_sporcu_sonuclari, name='api_sporcu_kategori_mesafe_sonuclari_short'),
    path('api/sporcular/<int:sporcu_id>/', views.api_sporcu_sonuclari, name='api_sporcu_detay_api'),
    path('api/sporcu-sonuclari/', views.api_sporcu_sonuclari, name='api_sporcu_sonuclari_query'),
    path('api/canli-aktar/', views.api_canli_aktar, name='api_canli_aktar'),
]

