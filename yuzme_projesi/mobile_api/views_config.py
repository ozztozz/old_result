# -*- coding: utf-8 -*-
import math
from django.core.paginator import Paginator
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.views.decorators.http import require_GET
from sonuclar.models import Sporcu, Kulup, SporcuKulupTarihce, Event, MobilUygulamaSurumu
from .utils import api_response, api_error


@require_GET
def get_config(request):
    """Mobil uygulama yapılandırma ve sürüm kontrol uç noktası."""
    latest_release = MobilUygulamaSurumu.objects.filter(aktif=True).order_by('-surum_kodu', '-olusturulma_tarihi').first()
    
    latest_version = latest_release.surum_adi if latest_release else '1.0.0'
    build_number = latest_release.surum_kodu if latest_release else 1
    force_update = latest_release.zorunlu_guncelleme if latest_release else False
    notes = latest_release.degisiklik_notlari if latest_release else ''
    download_url = request.build_absolute_uri('/mobil-uygulama/indir/')

    data = {
        'min_version': '1.0.0',
        'latest_version': latest_version,
        'build_number': build_number,
        'force_update': force_update,
        'release_notes': notes,
        'download_url': download_url,
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
    city = (request.GET.get('city') or request.GET.get('il') or '').strip()
    search_type = (request.GET.get('type') or 'all').strip().lower()

    if len(q) < 2 and not (search_type == 'club' and len(city) >= 2):
        return api_response({'athletes': [], 'clubs': [], 'meets': []}, request=request)

    res_athletes = []
    res_clubs = []
    res_meets = []

    if search_type in ('all', 'athlete') and len(q) >= 2:
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
        clubs_qs = Kulup.objects.all()
        if len(q) >= 2:
            clubs_qs = clubs_qs.filter(kulup_adi__icontains=q)
        if city:
            clubs_qs = clubs_qs.filter(il__icontains=city)
        clubs_qs = clubs_qs.order_by('-toplam_sporcu_sayisi', 'kulup_adi').only(
            'id', 'kulup_adi', 'il', 'okul_mu', 'toplam_sporcu_sayisi'
        )[:30 if city else 10]
        for c in clubs_qs:
            res_clubs.append({
                'id': c.id,
                'name': c.kulup_adi,
                'city': c.il or '',
                'is_school': bool(c.okul_mu == 1),
                'athlete_count': c.toplam_sporcu_sayisi or 0,
            })

    if search_type in ('all', 'meet') and len(q) >= 2:
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


_TR_LETTER_CASES = {
    'Ç': ('Ç', 'ç'),
    'Ğ': ('Ğ', 'ğ'),
    'I': ('I', 'ı'),
    'İ': ('İ', 'i'),
    'Ö': ('Ö', 'ö'),
    'Ş': ('Ş', 'ş'),
    'Ü': ('Ü', 'ü'),
}


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """İki koordinat arasındaki kuş uçuşu mesafeyi (km) döner."""
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


@require_GET
def get_clubs_list(request):
    """Sayfalı ve alfabetik/il/tür/konum filtreli kulüp listesi."""
    q = (request.GET.get('q') or '').strip()
    city = (request.GET.get('city') or request.GET.get('il') or '').strip()
    letter = (request.GET.get('letter') or '').strip()
    kind = (request.GET.get('kind') or 'all').strip().lower()
    raw_lat = request.GET.get('lat')
    raw_lon = request.GET.get('lon') or request.GET.get('lng')

    user_lat = user_lon = None
    if raw_lat is not None and raw_lon is not None:
        try:
            user_lat = float(raw_lat)
            user_lon = float(raw_lon)
        except (TypeError, ValueError):
            user_lat = user_lon = None

    qs = Kulup.objects.all()
    if kind == 'club':
        qs = qs.filter(okul_mu=0)
    elif kind == 'school':
        qs = qs.filter(okul_mu=1)
    if q:
        qs = qs.filter(kulup_adi__icontains=q)
    if city:
        qs = qs.filter(il__icontains=city)
    if letter:
        ch = letter[0]
        upper_ch = ch if ch in _TR_LETTER_CASES else ch.upper()
        u_form, l_form = _TR_LETTER_CASES.get(upper_ch, (ch.upper(), ch.lower()))
        qs = qs.filter(Q(kulup_adi__startswith=u_form) | Q(kulup_adi__startswith=l_form))

    page_size = min(int(request.GET.get('page_size', 25)), 50)
    page_num = int(request.GET.get('page', 1))

    if user_lat is not None and user_lon is not None:
        qs = qs.filter(enlem__isnull=False, boylam__isnull=False).only(
            'id', 'kulup_adi', 'il', 'okul_mu', 'toplam_sporcu_sayisi', 'enlem', 'boylam'
        )
        scored = []
        for c in qs:
            dist = _haversine_km(user_lat, user_lon, c.enlem, c.boylam)
            scored.append((dist, c))
        scored.sort(key=lambda x: (x[0], -(x[1].toplam_sporcu_sayisi or 0)))

        paginator = Paginator(scored, page_size)
        page_obj = paginator.get_page(page_num)
        clubs_data = [
            {
                'id': c.id,
                'name': c.kulup_adi,
                'city': c.il or '',
                'is_school': bool(c.okul_mu == 1),
                'athlete_count': c.toplam_sporcu_sayisi or 0,
                'distance_km': round(dist, 1),
            }
            for dist, c in page_obj
        ]
    else:
        qs = qs.order_by('kulup_adi' if letter else '-toplam_sporcu_sayisi', 'kulup_adi').only(
            'id', 'kulup_adi', 'il', 'okul_mu', 'toplam_sporcu_sayisi'
        )
        paginator = Paginator(qs, page_size)
        page_obj = paginator.get_page(page_num)
        clubs_data = [
            {
                'id': c.id,
                'name': c.kulup_adi,
                'city': c.il or '',
                'is_school': bool(c.okul_mu == 1),
                'athlete_count': c.toplam_sporcu_sayisi or 0,
            }
            for c in page_obj
        ]

    return api_response({
        'data': clubs_data,
        'page': page_num,
        'total_pages': paginator.num_pages,
        'total_count': paginator.count,
        'has_next': page_obj.has_next(),
    }, request=request, cache_seconds=30 if user_lat is not None else 60)


@require_GET
def get_clubs_map(request):
    """Haritada gösterilecek koordinatlı kulüplerin listesini döner."""
    q = (request.GET.get('q') or '').strip()
    city = (request.GET.get('city') or request.GET.get('il') or '').strip()
    kind = (request.GET.get('kind') or 'all').strip().lower()

    qs = Kulup.objects.filter(enlem__isnull=False, boylam__isnull=False)
    if kind == 'club':
        qs = qs.filter(okul_mu=0)
    elif kind == 'school':
        qs = qs.filter(okul_mu=1)
    if q:
        qs = qs.filter(kulup_adi__icontains=q)
    if city:
        qs = qs.filter(il__icontains=city)

    qs = qs.order_by('-toplam_sporcu_sayisi').only(
        'id', 'kulup_adi', 'il', 'okul_mu', 'toplam_sporcu_sayisi', 'enlem', 'boylam'
    )[:500]

    data = [
        {
            'id': c.id,
            'name': c.kulup_adi,
            'city': c.il or '',
            'is_school': bool(c.okul_mu == 1),
            'athlete_count': c.toplam_sporcu_sayisi or 0,
            'latitude': c.enlem,
            'longitude': c.boylam,
        }
        for c in qs
    ]
    return api_response({'data': data, 'total_count': len(data)}, request=request, cache_seconds=60)


@require_GET
def get_club_detail(request, club_id):
    """Tekil kulüp profili, iletişim/sosyal medya bilgileri ve performans özeti."""
    club = get_object_or_404(Kulup, pk=club_id)
    ozet = club.build_summary()
    return api_response({
        'id': club.id,
        'name': club.kulup_adi,
        'city': club.il or '',
        'is_school': bool(club.okul_mu == 1),
        'athlete_count': club.toplam_sporcu_sayisi or 0,
        'race_count': club.toplam_yaris_sayisi or 0,
        'first_race_date': club.ilk_yaris_tarihi or '',
        'last_race_date': club.son_yaris_tarihi or '',
        'address': club.adres or '',
        'phone': club.telefon or '',
        'website': club.web_sitesi or '',
        'google_maps_url': club.google_maps_url or '',
        'instagram': club.instagram or '',
        'facebook': club.facebook or '',
        'latitude': club.enlem,
        'longitude': club.boylam,
        'contact_updated_at': club.iletisim_guncellenme_tarihi or '',
        'summary': {
            'active_athletes': ozet['aktif_sporcu_sayisi'],
            'past_athletes': ozet['gecmis_sporcu_sayisi'],
            'male_athletes': ozet['erkek_sayisi'],
            'female_athletes': ozet['kadin_sayisi'],
            'meet_count': ozet['musabaka_sayisi'],
            'city_count': ozet['farkli_il_sayisi'],
            'max_fina': ozet['max_puan'],
            'avg_fina': ozet['avg_puan'],
            'gold': ozet['altin'],
            'silver': ozet['gumus'],
            'bronze': ozet['bronz'],
            'total_medals': ozet['toplam_madalya'],
            'age_groups': [
                {'label': y['grup'], 'count': y['sayi'], 'male': y['erkek'], 'female': y['kadin'], 'pct': y['oran']}
                for y in ozet['yas_dagilimi']
            ],
        },
    }, request=request, cache_seconds=120)
