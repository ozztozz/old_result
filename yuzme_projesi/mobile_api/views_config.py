# -*- coding: utf-8 -*-
from django.core.paginator import Paginator
from django.db.models import Q
from django.views.decorators.http import require_GET
from django.db.models import Q
from sonuclar.models import Sporcu, Kulup, Event, MobilUygulamaSurumu
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


@require_GET
def get_clubs_list(request):
    """Sayfalı ve alfabetik/il/tür filtreli kulüp listesi."""
    q = (request.GET.get('q') or '').strip()
    city = (request.GET.get('city') or request.GET.get('il') or '').strip()
    letter = (request.GET.get('letter') or '').strip()
    kind = (request.GET.get('kind') or 'all').strip().lower()

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

    qs = qs.order_by('kulup_adi' if letter else '-toplam_sporcu_sayisi', 'kulup_adi').only(
        'id', 'kulup_adi', 'il', 'okul_mu', 'toplam_sporcu_sayisi'
    )

    page_size = min(int(request.GET.get('page_size', 25)), 50)
    page_num = int(request.GET.get('page', 1))
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
    }, request=request, cache_seconds=60)
