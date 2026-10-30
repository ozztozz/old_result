# -*- coding: utf-8 -*-
from django.urls import path
from . import views_config, views_meets, views_athletes, views_live

app_name = 'mobile_api'

urlpatterns = [
    # 1. Yapılandırma & Genel Arama
    path('config/', views_config.get_config, name='config'),
    path('search/', views_config.search_global, name='search'),

    # 2. Müsabakalar & Sonuçlar
    path('meets/', views_meets.get_meets_list, name='meets_list'),
    path('meets/<int:meet_id>/', views_meets.get_meet_detail, name='meet_detail'),
    path('meets/<int:meet_id>/participants/', views_meets.get_meet_participants, name='meet_participants'),
    path('meets/<int:meet_id>/results/', views_meets.get_meet_results, name='meet_results'),

    # 3. Sporcular, PB Karnesi & Favoriler
    path('athletes/<int:athlete_id>/', views_athletes.get_athlete_detail, name='athlete_detail'),
    path('athletes/<int:athlete_id>/races/', views_athletes.get_athlete_races, name='athlete_races'),
    path('athletes/<int:athlete_id>/clubs/', views_athletes.get_athlete_clubs, name='athlete_clubs'),
    path('athletes/summary/', views_athletes.get_athletes_summary, name='athletes_summary'),

    # 4. Canlı Yarış Takibi
    path('live/', views_live.get_live_meets, name='live_meets'),
    path('live/<int:live_id>/feed/', views_live.get_live_feed, name='live_feed'),
]
