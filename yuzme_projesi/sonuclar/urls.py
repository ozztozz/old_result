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
    path('api/sporcu-ara/', views.api_sporcu_ara, name='api_sporcu_ara'),
    path('api/canli-aktar/', views.api_canli_aktar, name='api_canli_aktar'),
]

