# -*- coding: utf-8 -*-
from django.urls import path
from . import views_config, views_meets, views_athletes, views_live, views_tools

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
    path('athletes/<int:athlete_id>/baraj-targets/', views_athletes.get_athlete_baraj_targets, name='athlete_baraj_targets'),
    path('athletes/<int:athlete_id>/clubs/', views_athletes.get_athlete_clubs, name='athlete_clubs'),
    path('athletes/summary/', views_athletes.get_athletes_summary, name='athletes_summary'),

    # 4. Canlı Yarış Takibi
    path('live/', views_live.get_live_meets, name='live_meets'),
    path('live/<int:live_id>/feed/', views_live.get_live_feed, name='live_feed'),

    # 5. Bayrak Simülatörü, Sıralamalar & Özet Akışı
    path('clubs/', views_config.get_clubs_list, name='clubs_list'),
    path('clubs/map/', views_config.get_clubs_map, name='clubs_map'),
    path('clubs/<int:club_id>/', views_config.get_club_detail, name='club_detail'),
    path('clubs/relay-simulator/', views_tools.get_relay_simulator, name='relay_simulator'),
    path('rankings/', views_tools.get_rankings, name='rankings'),
    path('highlights/', views_tools.get_highlights_feed, name='highlights_feed'),
    path('news-feed/', views_meets.get_news_feed, name='news_feed'),
    path('calendar/', views_meets.get_event_calendar, name='event_calendar'),
    path('barajlar/', views_meets.get_barajlar_list, name='barajlar_list'),
]

