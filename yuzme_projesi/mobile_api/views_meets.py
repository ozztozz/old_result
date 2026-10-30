# -*- coding: utf-8 -*-
from django.views.decorators.http import require_GET
from django.core.paginator import Paginator
from django.db.models import Case, When, Value, IntegerField
from django.db.models.functions import Cast
from sonuclar.models import Event, YarisSonucu
from .utils import (
    api_response,
    api_error,
    seconds_to_cs,
    map_result_status,
    map_stroke,
    parse_qualifying_standard,
    detect_course,
)


@require_GET
def get_meets_list(request):
    """Müsabakalar listesi uç noktası (Sayfalı ve filtreli)."""
    qs = Event.objects.all().order_by('-yaris_tarihi_baslangic', '-id')

    year = (request.GET.get('year') or '').strip()
    if year.isdigit():
        qs = qs.filter(yaris_tarihi_baslangic__startswith=year)

    city = (request.GET.get('city') or '').strip()
    if city:
        qs = qs.filter(sehir__icontains=city)

    q = (request.GET.get('q') or '').strip()
    if q:
        qs = qs.filter(musabaka_adi__icontains=q)

    page_size = min(int(request.GET.get('page_size', 20)), 50)
    page_num = int(request.GET.get('page', 1))

    paginator = Paginator(qs, page_size)
    page_obj = paginator.get_page(page_num)

    meets_data = []
    for m in page_obj:
        course = detect_course(m.musabaka_adi or m.kaynak_turu)
        meets_data.append({
            'id': m.id,
            'name': m.musabaka_adi,
            'city': m.sehir or '',
            'start_date': m.yaris_tarihi_baslangic or m.yaris_tarihi_ham or '',
            'end_date': m.yaris_tarihi_bitis or '',
            'course': course,
            'total_races': m.toplam_yaris_sayisi or 0,
            'total_athletes': m.toplam_sporcu_sayisi or 0,
        })

    return api_response({
        'data': meets_data,
        'page': page_num,
        'total_pages': paginator.num_pages,
        'total_count': paginator.count,
        'has_next': page_obj.has_next(),
    }, request=request, cache_seconds=60)


@require_GET
def get_meet_detail(request, meet_id: int):
    """Tekil müsabaka detayları ve yarış programı."""
    try:
        meet = Event.objects.get(pk=meet_id)
    except Event.DoesNotExist:
        return api_error('not_found', 'Müsabaka bulunamadı', status=404)

    # Yarış programı (Yarış no bazında gruplanmış liste)
    program_rows = (
        meet.yaris_sonuclari.exclude(yaris_no__isnull=True)
        .exclude(yaris_no='')
        .values('yaris_no', 'mesafe', 'stil', 'cinsiyet')
        .distinct()
    )

    prog_dict = {}
    for r in program_rows:
        yno = str(r['yaris_no']).strip()
        if not yno:
            continue
        if yno not in prog_dict:
            prog_dict[yno] = {
                'event_no': yno,
                'distance': r.get('mesafe'),
                'stroke': map_stroke(r.get('stil')),
                'stroke_label': (r.get('stil') or '').strip(),
                'gender': (r.get('cinsiyet') or '').strip(),
            }
        else:
            if not prog_dict[yno]['distance'] and r.get('mesafe'):
                prog_dict[yno]['distance'] = r.get('mesafe')
            if not prog_dict[yno]['stroke_label'] and r.get('stil'):
                prog_dict[yno]['stroke'] = map_stroke(r.get('stil'))
                prog_dict[yno]['stroke_label'] = (r.get('stil') or '').strip()

    events_list = list(prog_dict.values())
    try:
        events_list.sort(key=lambda x: int(x['event_no']) if str(x['event_no']).isdigit() else 9999)
    except Exception:
        events_list.sort(key=lambda x: str(x['event_no']))

    course = detect_course(meet.musabaka_adi or meet.kaynak_turu)

    return api_response({
        'data': {
            'id': meet.id,
            'name': meet.musabaka_adi,
            'city': meet.sehir or '',
            'start_date': meet.yaris_tarihi_baslangic or meet.yaris_tarihi_ham or '',
            'end_date': meet.yaris_tarihi_bitis or '',
            'course': course,
            'total_races': meet.toplam_yaris_sayisi or 0,
            'total_athletes': meet.toplam_sporcu_sayisi or 0,
            'events': events_list,
        }
    }, request=request, cache_seconds=120)


@require_GET
def get_meet_participants(request, meet_id: int):
    """
    Müsabakanın katılan kulüp ve sporcu listesi (0 ms mobil bağımlı filtreleme için).
    Mobil istemci bu JSON'u indirip cihaz hafızasında tutar; kulüp seçilince sporcu listesi anında daralır.
    """
    try:
        meet = Event.objects.get(pk=meet_id)
    except Event.DoesNotExist:
        return api_error('not_found', 'Müsabaka bulunamadı', status=404)

    # Katılan kulüpler
    clubs_raw = (
        meet.yaris_sonuclari.exclude(kulup__isnull=True)
        .values('kulup_id', 'kulup__kulup_adi')
        .distinct()
        .order_by('kulup__kulup_adi')
    )
    clubs_data = [{'id': c['kulup_id'], 'name': c['kulup__kulup_adi']} for c in clubs_raw]

    # Katılan sporcular (tekilleştirilmiş)
    athletes_raw = (
        meet.yaris_sonuclari.exclude(sporcu__isnull=True)
        .values('sporcu_id', 'sporcu__sporcu_adi', 'sporcu__dogum_yili', 'kulup_id')
        .distinct()
        .order_by('sporcu__sporcu_adi')
    )
    seen_ids = set()
    athletes_data = []
    for a in athletes_raw:
        aid = a['sporcu_id']
        if aid not in seen_ids:
            seen_ids.add(aid)
            athletes_data.append({
                'id': aid,
                'name': a['sporcu__sporcu_adi'],
                'birth_year': a['sporcu__dogum_yili'],
                'club_id': a['kulup_id'],
            })

    return api_response({
        'meet_id': meet.id,
        'clubs': clubs_data,
        'athletes': athletes_data,
    }, request=request, cache_seconds=300)


@require_GET
def get_meet_results(request, meet_id: int):
    """
    Müsabaka yarış sonuçları (Yarış No, Kulüp, Sporcu ve Durum filtreli).
    """
    try:
        meet = Event.objects.get(pk=meet_id)
    except Event.DoesNotExist:
        return api_error('not_found', 'Müsabaka bulunamadı', status=404)

    qs = meet.yaris_sonuclari.select_related('sporcu', 'kulup')

    event_no = (request.GET.get('event_no') or '').strip()
    if event_no:
        qs = qs.filter(yaris_no=event_no)

    club_id = request.GET.get('club_id')
    if club_id and club_id.isdigit():
        qs = qs.filter(kulup_id=int(club_id))

    athlete_id = request.GET.get('athlete_id')
    if athlete_id and athlete_id.isdigit():
        qs = qs.filter(sporcu_id=int(athlete_id))

    status = (request.GET.get('status') or 'all').strip().lower()
    if status == 'finished':
        qs = qs.exclude(derece='Bekleniyor')
    elif status == 'pending':
        qs = qs.filter(derece='Bekleniyor')

    # Akıllı sıralama: Yarış No -> Sonuçlananlar önce -> Sıra -> Derece
    qs = qs.annotate(
        is_pending=Case(
            When(derece='Bekleniyor', then=Value(1)),
            default=Value(0),
            output_field=IntegerField()
        ),
        yaris_no_int=Cast('yaris_no', IntegerField()),
        sira_int=Case(
            When(sira='', then=Value(9999)),
            When(sira__isnull=True, then=Value(9999)),
            default=Cast('sira', IntegerField()),
            output_field=IntegerField()
        )
    ).order_by('yaris_no_int', 'is_pending', 'sira_int', 'derece_saniye')

    page_size = min(int(request.GET.get('page_size', 50)), 100)
    page_num = int(request.GET.get('page', 1))

    paginator = Paginator(qs, page_size)
    page_obj = paginator.get_page(page_num)

    results_data = []
    for r in page_obj:
        time_cs = seconds_to_cs(r.derece_saniye or r.derece)
        seed_cs = seconds_to_cs(r.giris_derecesi)
        res_status = map_result_status(r.derece, r.sira)
        standard = parse_qualifying_standard(r.baraj)
        source = 'live' if (r.kaynak_turu or '').upper() == 'CANLI' else 'official'

        results_data.append({
            'id': r.id,
            'event_no': str(r.yaris_no or ''),
            'distance': r.mesafe,
            'stroke': map_stroke(r.stil),
            'stroke_label': (r.stil or '').strip(),
            'heat': (r.seri or '').strip(),
            'lane': r.kulvar,
            'rank': str(r.sira or '').strip(),
            'time': r.derece if r.derece != 'Bekleniyor' else None,
            'time_cs': time_cs if res_status == 'OK' else None,
            'seed_time': (r.giris_derecesi or '').strip() or None,
            'seed_time_cs': seed_cs,
            'result_status': res_status,
            'points': r.puan if (r.puan and r.puan > 0) else None,
            'qualifying_standard': standard,
            'source': source,
            'athlete': {
                'id': r.sporcu_id,
                'name': r.sporcu.sporcu_adi if r.sporcu else '',
                'birth_year': r.sporcu.dogum_yili if r.sporcu else None,
                'age': r.hesaplanan_yas or None,
            },
            'club': {
                'id': r.kulup_id,
                'name': r.kulup.kulup_adi if r.kulup else 'Ferdi',
            } if r.kulup else None,
        })

    return api_response({
        'data': results_data,
        'page': page_num,
        'total_pages': paginator.num_pages,
        'total_count': paginator.count,
        'has_next': page_obj.has_next(),
    }, request=request, cache_seconds=15)

