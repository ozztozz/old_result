# -*- coding: utf-8 -*-
from django.views.decorators.http import require_GET
from django.db.models import Q
from sonuclar.models import Sporcu, Kulup, Event
from .utils import api_response, api_error


@require_GET
def get_config(request):
    """Mobil uygulama yapılandırma ve sürüm kontrol uç noktası."""
    data = {
        'min_version': '1.0.0',
        'latest_version': '1.0.0',
        'maintenance': False,
        'maintenance_message': '',
        'features': {
            'live_tracking': True,
            'push_notifications': False,
            'meet_analysis': False,
            'favorites_offline': True,
        }
    }
    return api_response(data, request=request, cache_seconds=60)


@require_GET
def search_global(request):
    """
    Genel arama uç noktası (Autocomplete & Search).
    Parametreler: q (en az 2 karakter), type (all / athlete / club / meet)
    """
    q = (request.GET.get('q') or '').strip()
    search_type = (request.GET.get('type') or 'all').strip().lower()

    if len(q) < 2:
        return api_response({'athletes': [], 'clubs': [], 'meets': []}, request=request)

    res_athletes = []
    res_clubs = []
    res_meets = []

    if search_type in ('all', 'athlete'):
        athletes_qs = (
            Sporcu.objects.filter(sporcu_adi__icontains=q)
            .select_related('birincil_kulup')
            .only('id', 'sporcu_adi', 'dogum_yili', 'birincil_kulup__kulup_adi')[:15]
        )
        for a in athletes_qs:
            res_athletes.append({
                'id': a.id,
                'name': a.sporcu_adi,
                'birth_year': a.dogum_yili,
                'club_name': a.birincil_kulup.kulup_adi if a.birincil_kulup else None,
            })

    if search_type in ('all', 'club'):
        clubs_qs = (
            Kulup.objects.filter(kulup_adi__icontains=q)
            .only('id', 'kulup_adi', 'toplam_sporcu_sayisi')[:10]
        )
        for c in clubs_qs:
            res_clubs.append({
                'id': c.id,
                'name': c.kulup_adi,
                'athlete_count': c.toplam_sporcu_sayisi or 0,
            })

    if search_type in ('all', 'meet'):
        meets_qs = (
            Event.objects.filter(musabaka_adi__icontains=q)
            .only('id', 'musabaka_adi', 'sehir', 'yaris_tarihi_baslangic')
            .order_by('-yaris_tarihi_baslangic')[:10]
        )
        for m in meets_qs:
            res_meets.append({
                'id': m.id,
                'name': m.musabaka_adi,
                'city': m.sehir,
                'date': m.yaris_tarihi_baslangic,
            })

    return api_response({
        'athletes': res_athletes,
        'clubs': res_clubs,
        'meets': res_meets,
    }, request=request, cache_seconds=30)
