# -*- coding: utf-8 -*-
from itertools import permutations
from django.db.models import Min, Q
from django.utils import timezone
from django.views.decorators.http import require_GET
from sonuclar.models import Kulup, YarisSonucu
from .utils import (
    api_response,
    api_error,
    seconds_to_cs,
    map_stroke,
    detect_course,
    parse_qualifying_standard,
)


def _format_cs(cs: int) -> str:
    mins = cs // 6000
    rem = cs % 6000
    secs = rem // 100
    hund = rem % 100
    return f'{mins}:{secs:02d}.{hund:02d}' if mins > 0 else f'{secs:02d}.{hund:02d}'

STROKE_REV_MAP = {
    'free': ['Serbest', 'SERBEST', 'serbest'],
    'freestyle': ['Serbest', 'SERBEST', 'serbest'],
    'back': ['Sırtüstü', 'SIRTÜSTÜ', 'SIRTUSTU', 'sırtüstü'],
    'breast': ['Kurbağalama', 'KURBAĞALAMA', 'KURBAGALAMA', 'kurbağalama'],
    'fly': ['Kelebek', 'KELEBEK', 'kelebek'],
    'medley': ['Karışık', 'KARIŞIK', 'KARISIK', 'karışık'],
    'im': ['Karışık', 'KARIŞIK', 'KARISIK', 'karışık'],
}


def _gender_filter_values(g: str):
    gl = (g or '').strip().lower()
    if gl in ('erkek', 'e', 'men', 'boy', 'm'):
        return ['Erkek', 'ERKEK', 'Erkekler']
    if gl in ('kadın', 'kadin', 'k', 'bayan', 'women', 'girl', 'f'):
        return ['Kadın', 'KADIN', 'Kadınlar', 'Kadin', 'Kızlar']
    return None


@require_GET
def get_relay_simulator(request):
    """
    Kulüp sporcularının güncel PB derecelerinden en hızlı bayrak takımını simüle eder.
    Parametreler: club_id, club_name, relay_type (4x50_free|4x100_free|4x50_medley|4x100_medley),
                  gender (Erkek|Kadın), course (LC|SC), birth_year (opsiyonel).
    """
    club_id = request.GET.get('club_id')
    club_name = (request.GET.get('club_name') or '').strip()
    relay_type = (request.GET.get('relay_type') or '4x50_free').strip().lower()
    gender = (request.GET.get('gender') or 'Erkek').strip()
    course = (request.GET.get('course') or 'LC').strip().upper()
    birth_year = (request.GET.get('birth_year') or '').strip()

    club = None
    if club_id and str(club_id).isdigit():
        club = Kulup.objects.filter(pk=int(club_id)).first()
    elif club_name:
        club = Kulup.objects.filter(kulup_adi__iexact=club_name).first() or Kulup.objects.filter(kulup_adi__icontains=club_name).first()

    if not club:
        return api_error('not_found', 'Kulüp bulunamadı', status=404)

    dist = 100 if '100' in relay_type else 50
    is_medley = 'medley' in relay_type

    needed_strokes = (
        [('back', 'Sırtüstü'), ('breast', 'Kurbağalama'), ('fly', 'Kelebek'), ('free', 'Serbest')]
        if is_medley
        else [('free', 'Serbest')]
    )
    allowed_stils = []
    for key, _ in needed_strokes:
        allowed_stils.extend(STROKE_REV_MAP[key])

    cutoff_year = timezone.now().year - 2
    qs = (
        YarisSonucu.objects.filter(
            kulup=club,
            mesafe=dist,
            stil__in=allowed_stils,
            derece_saniye__gt=0,
            event__yaris_tarihi_baslangic__gte=f'{cutoff_year}-01-01',
        )
        .exclude(sporcu__sporcu_adi__startswith='Maskeli sporcu')
        .exclude(uyari_notu__iregex=r'DSQ|DNS|DNF|EXH')
        .select_related('sporcu', 'event')
    )

    g_vals = _gender_filter_values(gender)
    if g_vals:
        qs = qs.filter(cinsiyet__in=g_vals)
    if birth_year.isdigit():
        qs = qs.filter(sporcu__dogum_yili=int(birth_year))

    # Sporcu + stil bazında en iyi (en küçük) dereceyi bul
    best_by_key = {}  # (stroke_code, sporcu_id) -> dict
    for r in qs:
        ev_course = detect_course(r.event.musabaka_adi if r.event else '')
        if course in ('LC', 'SC') and ev_course != course:
            continue
        sc = map_stroke(r.stil)
        cs = seconds_to_cs(r.derece_saniye)
        if not cs or cs <= 0:
            continue
        k = (sc, r.sporcu_id)
        prev = best_by_key.get(k)
        if prev is None or cs < prev['time_cs']:
            best_by_key[k] = {
                'athlete_id': r.sporcu_id,
                'athlete_name': r.sporcu.sporcu_adi,
                'birth_year': r.sporcu.dogum_yili,
                'stroke': sc,
                'stroke_label': (r.stil or '').strip(),
                'distance': dist,
                'time_cs': cs,
                'time': _format_cs(cs),
                'date': r.event.yaris_tarihi_baslangic if r.event else '',
            }

    legs = []
    if not is_medley:
        cands = [v for (sc, _), v in best_by_key.items() if sc == 'free']
        cands.sort(key=lambda x: x['time_cs'])
        for idx, c in enumerate(cands[:4], start=1):
            legs.append({'leg': idx, **c})
    else:
        leg_Order = ['back', 'breast', 'fly', 'free']
        pools = {}
        for sc in leg_Order:
            cands = [v for (s_code, _), v in best_by_key.items() if s_code == sc]
            cands.sort(key=lambda x: x['time_cs'])
            pools[sc] = cands[:8]

        if all(pools[sc] for sc in leg_Order):
            best_combo = None
            best_total = None
            # En hızlı 4 farklı sporcu kombinasyonunu bul
            for b in pools['back']:
                for br in pools['breast']:
                    if br['athlete_id'] == b['athlete_id']:
                        continue
                    for fl in pools['fly']:
                        if fl['athlete_id'] in (b['athlete_id'], br['athlete_id']):
                            continue
                        for fr in pools['free']:
                            if fr['athlete_id'] in (b['athlete_id'], br['athlete_id'], fl['athlete_id']):
                                continue
                            tot = b['time_cs'] + br['time_cs'] + fl['time_cs'] + fr['time_cs']
                            if best_total is None or tot < best_total:
                                best_total = tot
                                best_combo = [b, br, fl, fr]
            if best_combo:
                for idx, item in enumerate(best_combo, start=1):
                    legs.append({'leg': idx, **item})

    total_cs = sum(l['time_cs'] for l in legs) if len(legs) == 4 else None
    return api_response({
        'data': {
            'club_id': club.id,
            'club_name': club.kulup_adi,
            'relay_type': relay_type,
            'course': course,
            'gender': gender,
            'complete': len(legs) == 4,
            'total_cs': total_cs,
            'total_time': _format_cs(total_cs) if total_cs else None,
            'legs': legs,
        }
    }, request=request, cache_seconds=30)


@require_GET
def get_rankings(request):
    """
    Branş, mesafe, cinsiyet, kulvar, il ve doğum yılına göre Top 25 sporcu sıralaması.
    """
    stroke = (request.GET.get('stroke') or 'free').strip().lower()
    distance = (request.GET.get('distance') or '50').strip()
    gender = (request.GET.get('gender') or 'Erkek').strip()
    course = (request.GET.get('course') or 'LC').strip().upper()
    birth_year = (request.GET.get('birth_year') or '').strip()
    city = (request.GET.get('city') or '').strip()

    allowed_stils = STROKE_REV_MAP.get(stroke, STROKE_REV_MAP['free'])
    dist_int = int(distance) if distance.isdigit() else 50
    cutoff_year = timezone.now().year - 2

    qs = (
        YarisSonucu.objects.filter(
            mesafe=dist_int,
            stil__in=allowed_stils,
            derece_saniye__gt=0,
            event__yaris_tarihi_baslangic__gte=f'{cutoff_year}-01-01',
        )
        .exclude(sporcu__sporcu_adi__startswith='Maskeli sporcu')
        .exclude(uyari_notu__iregex=r'DSQ|DNS|DNF|EXH')
        .select_related('sporcu', 'kulup', 'event')
    )

    g_vals = _gender_filter_values(gender)
    if g_vals:
        qs = qs.filter(cinsiyet__in=g_vals)
    if birth_year.isdigit():
        qs = qs.filter(sporcu__dogum_yili=int(birth_year))
    if city:
        qs = qs.filter(event__sehir__icontains=city)

    best_per_athlete = {}
    for r in qs.order_by('derece_saniye')[:800]:
        ev_course = detect_course(r.event.musabaka_adi if r.event else '')
        if course in ('LC', 'SC') and ev_course != course:
            continue
        cs = seconds_to_cs(r.derece_saniye)
        if not cs or cs <= 0:
            continue
        prev = best_per_athlete.get(r.sporcu_id)
        if prev is None or cs < prev['time_cs']:
            best_per_athlete[r.sporcu_id] = {
                'athlete_id': r.sporcu_id,
                'athlete_name': r.sporcu.sporcu_adi,
                'birth_year': r.sporcu.dogum_yili,
                'club_name': r.kulup.kulup_adi if r.kulup else 'Ferdi',
                'time_cs': cs,
                'time': _format_cs(cs),
                'points': r.puan if (r.puan and r.puan > 0) else None,
                'date': r.event.yaris_tarihi_baslangic if r.event else '',
                'meet_name': r.event.musabaka_adi if r.event else '',
                'city': r.event.sehir if r.event else '',
            }

    ranked = sorted(best_per_athlete.values(), key=lambda x: x['time_cs'])[:25]
    for idx, item in enumerate(ranked, start=1):
        item['rank'] = idx

    return api_response({'data': ranked}, request=request, cache_seconds=60)


@require_GET
def get_highlights_feed(request):
    """
    Favori sporcular ve/veya seçili kulüp için en güncel canlı sonuç, kürsü ve baraj akışı.
    """
    ath_ids_raw = (request.GET.get('athlete_ids') or '').strip()
    club_id = (request.GET.get('club_id') or '').strip()
    club_name = (request.GET.get('club_name') or '').strip()

    ath_ids = [int(x) for x in ath_ids_raw.split(',') if x.strip().isdigit()]
    q_filter = Q()
    if ath_ids:
        q_filter |= Q(sporcu_id__in=ath_ids)
    if club_id.isdigit():
        q_filter |= Q(kulup_id=int(club_id))
    elif club_name:
        q_filter |= Q(kulup__kulup_adi__icontains=club_name)

    if not q_filter:
        return api_response({'data': []}, request=request, cache_seconds=15)

    rows = (
        YarisSonucu.objects.filter(q_filter, kaynak_turu='CANLI_SONUC', derece_saniye__gt=0)
        .exclude(uyari_notu__iregex=r'DSQ|DNS|DNF|EXH')
        .select_related('sporcu', 'kulup', 'event')
        .order_by('-event__yaris_tarihi_baslangic', '-id')[:25]
    )

    feed = []
    for r in rows:
        cs = seconds_to_cs(r.derece_saniye)
        std = parse_qualifying_standard(r.baraj)
        feed.append({
            'id': r.id,
            'athlete_id': r.sporcu_id,
            'athlete_name': r.sporcu.sporcu_adi,
            'club_name': r.kulup.kulup_adi if r.kulup else 'Ferdi',
            'meet_id': r.event_id,
            'meet_name': r.event.musabaka_adi if r.event else '',
            'date': r.event.yaris_tarihi_baslangic if r.event else '',
            'distance': r.mesafe,
            'stroke': map_stroke(r.stil),
            'stroke_label': (r.stil or '').strip(),
            'rank': str(r.sira or '').strip(),
            'time': r.derece,
            'time_cs': cs,
            'points': r.puan if (r.puan and r.puan > 0) else None,
            'qualifying_standard': std,
        })

    return api_response({'data': feed}, request=request, cache_seconds=15)
