# -*- coding: utf-8 -*-
from django.views.decorators.http import require_GET
from django.core.paginator import Paginator
from django.db.models import Case, Count, Prefetch, Q, When, Value, IntegerField
from django.db.models.functions import Cast
from django.utils import timezone
from sonuclar.models import Event, YarisSonucu, TyfBelge, BarajKurali
from .utils import (
    api_response,
    api_error,
    cache_api_response,
    seconds_to_cs,
    map_result_status,
    map_stroke,
    parse_qualifying_standard,
    detect_course,
    compute_age_group_info,
)


@require_GET
@cache_api_response(60)
def get_meets_list(request):
    """Müsabakalar listesi uç noktası (Sayfalı ve filtreli)."""
    qs = Event.objects.all().order_by('-yaris_tarihi_baslangic', '-id')
    needs_distinct = False

    year = (request.GET.get('year') or '').strip()
    if year.isdigit():
        qs = qs.filter(yaris_tarihi_baslangic__startswith=year)

    city = (request.GET.get('city') or '').strip()
    if city:
        qs = qs.filter(sehir__icontains=city)

    q = (request.GET.get('q') or '').strip()
    if q:
        qs = qs.filter(musabaka_adi__icontains=q)

    club_id = (request.GET.get('club_id') or '').strip()
    club = (request.GET.get('club') or '').strip()
    if club_id.isdigit():
        qs = qs.filter(yaris_sonuclari__kulup_id=int(club_id))
        needs_distinct = True
    elif club:
        qs = qs.filter(yaris_sonuclari__kulup__kulup_adi__icontains=club)
        needs_distinct = True

    athlete_id = (request.GET.get('athlete_id') or '').strip()
    athlete = (request.GET.get('athlete') or '').strip()
    if athlete_id.isdigit():
        qs = qs.filter(yaris_sonuclari__sporcu_id=int(athlete_id))
        needs_distinct = True
    elif athlete:
        qs = qs.filter(yaris_sonuclari__sporcu__sporcu_adi__icontains=athlete)
        needs_distinct = True

    gender = (request.GET.get('gender') or '').strip().lower()
    if gender in ('erkek', 'e', 'men', 'male', 'm'):
        qs = qs.filter(yaris_sonuclari__cinsiyet__in=['Erkek', 'ERKEK', 'Erkekler'])
        needs_distinct = True
    elif gender in ('kadın', 'kadin', 'k', 'bayan', 'women', 'female', 'f'):
        qs = qs.filter(
            yaris_sonuclari__cinsiyet__in=['Kadın', 'KADIN', 'Kadınlar', 'Kadin', 'Kızlar']
        )
        needs_distinct = True

    if needs_distinct:
        qs = qs.distinct()

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
            'course': m.havuz or course,
            'age_group': m.yas_grubu or '',
            'min_age': m.min_yas,
            'max_age': m.max_yas,
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
@cache_api_response(60)
def get_news_feed(request):
    """
    Giriş sayfası haber/duyuru bandı:
    TYF Takvim, Reglaman ve Milli Takım Kriter belgelerini özetleri,
    yaş grupları, baraj sayıları ve Django üzerinde saklanan PDF linkleriyle döndürür.
    """
    from django.db.models import Count

    qs = (
        TyfBelge.objects.filter(aktif=True)
        .annotate(baraj_sayisi=Count('baraj_kurallari'))
        .order_by('-guncellenme_tarihi', '-id')
    )
    belge_turu = (request.GET.get('type') or '').strip().upper()
    if belge_turu in ('TAKVIM', 'REGLAMAN', 'MILLI_TAKIM', 'DUYURU'):
        qs = qs.filter(belge_turu=belge_turu)

    try:
        limit = min(max(int(request.GET.get('limit', 20)), 1), 50)
    except ValueError:
        limit = 20

    items = []
    for b in qs[:limit]:
        pdf_url = ''
        if b.yerel_dosya:
            try:
                pdf_url = request.build_absolute_uri(b.yerel_dosya.url)
            except Exception:
                pdf_url = b.yerel_dosya.url
        if not pdf_url:
            pdf_url = b.kaynak_url

        items.append({
            'id': b.id,
            'belge_turu': b.belge_turu,
            'baslik': b.baslik,
            'revizyon_etiketi': b.revizyon_etiketi or '',
            'tarih_metni': b.tarih_metni or '',
            'baslangic_tarihi': b.baslangic_tarihi or '',
            'bitis_tarihi': b.bitis_tarihi or '',
            'sehir_yer': b.sehir_yer or '',
            'havuz': b.havuz or '',
            'yas_grubu': b.yas_grubu or '',
            'min_yas': b.min_yas,
            'max_yas': b.max_yas,
            'ozet': b.ozet or '',
            'onemli_notlar': b.onemli_notlar or [],
            'event_id': b.event_id,
            'baraj_sayisi': b.baraj_sayisi,
            'pdf_url': pdf_url,
            'source_url': b.kaynak_url,
            'guncellenme_tarihi': b.guncellenme_tarihi.isoformat() if b.guncellenme_tarihi else '',
        })

    return api_response({'data': items}, request=request, cache_seconds=60)


@require_GET
@cache_api_response(60)
def get_event_calendar(request):
    """
    Ulusal (TYF) ve İl etkinlik takvimi uç noktası.
    İleride eklenecek il etkinlikleri (`kaynak_turu` 'IL_' ile başlayanlar veya şehir bazlı)
    ve TYF takvim/reglaman etkinliklerini tek bir kronolojik yapıda sunar.
    """
    from django.db.models import Count, Q

    today_iso = timezone.localdate().isoformat()
    include_past = request.GET.get('include_past') == '1'
    scope = (request.GET.get('scope') or 'all').strip().lower()
    city = (request.GET.get('city') or '').strip()
    pool = (request.GET.get('pool') or '').strip().lower()
    age_raw = (request.GET.get('age') or '').strip()
    q = (request.GET.get('q') or '').strip()

    qs = Event.objects.exclude(yaris_tarihi_baslangic__isnull=True).exclude(yaris_tarihi_baslangic='')
    if not include_past:
        qs = qs.filter(
            Q(yaris_tarihi_bitis__gte=today_iso) |
            (Q(yaris_tarihi_bitis__isnull=True) & Q(yaris_tarihi_baslangic__gte=today_iso)) |
            (Q(yaris_tarihi_bitis='') & Q(yaris_tarihi_baslangic__gte=today_iso))
        )

    if scope == 'national':
        qs = qs.filter(Q(kaynak_turu__startswith='TYF') | Q(kaynak_turu__isnull=True))
    elif scope == 'provincial':
        qs = qs.filter(Q(kaynak_turu__startswith='IL') | Q(kaynak_turu__icontains='PROVINCIAL'))

    if city:
        qs = qs.filter(sehir__icontains=city)
    if pool in ('25m', '50m'):
        qs = qs.filter(Q(havuz__icontains=pool) | Q(musabaka_adi__icontains=pool))
    if age_raw.isdigit():
        age_int = int(age_raw)
        qs = qs.filter(
            (Q(min_yas__isnull=True) | Q(min_yas__lte=age_int)) &
            (Q(max_yas__isnull=True) | Q(max_yas__gte=age_int))
        ).exclude(min_yas__isnull=True, max_yas__isnull=True)
    if q:
        qs = qs.filter(Q(musabaka_adi__icontains=q) | Q(sehir__icontains=q) | Q(yas_grubu__icontains=q))

    qs = (
        qs.annotate(baraj_count=Count('baraj_kurallari', distinct=True))
        .prefetch_related(
            Prefetch(
                'tyf_belgeler',
                queryset=TyfBelge.objects.filter(aktif=True).order_by('-id'),
                to_attr='aktif_belgeler',
            )
        )
        .order_by('yaris_tarihi_baslangic', 'id')
    )

    events_data = []
    cities_set = set()
    for ev in qs[:200]:
        sehir = (ev.sehir or '').strip()
        if sehir and sehir.upper() not in ('İLLER', 'ILLER', '-'):
            cities_set.add(sehir)

        src = (ev.kaynak_turu or '').upper()
        ev_scope = 'IL' if src.startswith('IL') else 'ULUSAL'

        belge = ev.aktif_belgeler[0] if getattr(ev, 'aktif_belgeler', None) else None
        pdf_url = ''
        ozet = ''
        if belge:
            ozet = belge.ozet or ''
            if belge.yerel_dosya:
                try:
                    pdf_url = request.build_absolute_uri(belge.yerel_dosya.url)
                except Exception:
                    pdf_url = belge.yerel_dosya.url
            if not pdf_url:
                pdf_url = belge.kaynak_url

        events_data.append({
            'id': ev.id,
            'name': ev.musabaka_adi,
            'city': sehir,
            'start_date': ev.yaris_tarihi_baslangic or '',
            'end_date': ev.yaris_tarihi_bitis or '',
            'raw_date': ev.yaris_tarihi_ham or '',
            'pool': ev.havuz or detect_course(ev.musabaka_adi or ev.kaynak_turu),
            'age_group': ev.yas_grubu or '',
            'min_age': ev.min_yas,
            'max_age': ev.max_yas,
            'source_type': ev.kaynak_turu or '',
            'scope': ev_scope,
            'has_results': (ev.toplam_yaris_sayisi or 0) > 0,
            'baraj_count': ev.baraj_count,
            'pdf_url': pdf_url,
            'ozet': ozet,
        })

    return api_response({
        'data': events_data,
        'meta': {
            'total': len(events_data),
            'cities': sorted(cities_set),
        },
    }, request=request, cache_seconds=60)


@require_GET
@cache_api_response(300)
def get_barajlar_list(request):
    """
    Resmi TYF Katılım ve Harcırah Barajları listesi uç noktası.
    Bağlı olduğu etkinlik (`event_id`), yer (`city`) ve tarih (`month` / `start_date`) ile filtrelenebilir.
    """
    baraj_adi = (request.GET.get('baraj_adi') or '').strip()
    event_id_raw = (request.GET.get('event_id') or '').strip()
    city = (request.GET.get('city') or '').strip()
    month = (request.GET.get('month') or '').strip()  # YYYY-MM
    baraj_turu = (request.GET.get('baraj_turu') or '').strip()
    havuz = (request.GET.get('havuz') or '').strip()
    cinsiyet = (request.GET.get('cinsiyet') or '').strip()
    yas_etiketi = (request.GET.get('yas') or '').strip()
    stil = (request.GET.get('stil') or '').strip()

    all_qs = BarajKurali.objects.select_related('event', 'belge')

    # Etkinlik, yer ve tarih seçeneklerini çıkar
    events_map = {}
    cities_set = set()
    months_set = set()
    for b in all_qs.only(
        'baraj_adi', 'event_id',
        'event__musabaka_adi', 'event__sehir', 'event__yaris_tarihi_ham', 'event__yaris_tarihi_baslangic',
        'belge__baslik', 'belge__sehir_yer', 'belge__tarih_metni', 'belge__baslangic_tarihi',
        'belge__baraj_gecerlilik_metni', 'belge__ozet', 'belge__onemli_notlar',
        'belge__yerel_dosya', 'belge__kaynak_url',
    ):
        ev_title = (
            (b.event.musabaka_adi if b.event else None)
            or (b.belge.baslik if b.belge else None)
            or b.baraj_adi
        )
        ev_city = (
            (b.event.sehir if b.event and b.event.sehir else None)
            or (b.belge.sehir_yer if b.belge and b.belge.sehir_yer else '')
        )
        ev_date_text = (
            (b.event.yaris_tarihi_ham if b.event and b.event.yaris_tarihi_ham else None)
            or (b.belge.tarih_metni if b.belge and b.belge.tarih_metni else '')
        )
        ev_start = (
            (b.event.yaris_tarihi_baslangic if b.event and b.event.yaris_tarihi_baslangic else None)
            or (b.belge.baslangic_tarihi if b.belge and b.belge.baslangic_tarihi else '')
        )
        ev_validity = (b.belge.baraj_gecerlilik_metni if b.belge and b.belge.baraj_gecerlilik_metni else '')
        if ev_city:
            cities_set.add(ev_city)
        if ev_start and len(ev_start) >= 7:
            months_set.add(ev_start[:7])

        key = b.event_id or b.baraj_adi
        if key not in events_map:
            ev_pdf_url = ''
            if b.belge:
                if b.belge.yerel_dosya:
                    try:
                        ev_pdf_url = request.build_absolute_uri(b.belge.yerel_dosya.url)
                    except Exception:
                        ev_pdf_url = b.belge.yerel_dosya.url
                if not ev_pdf_url:
                    ev_pdf_url = b.belge.kaynak_url or ''
            events_map[key] = {
                'event_id': b.event_id,
                'baraj_adi': b.baraj_adi,
                'title': ev_title,
                'city': ev_city,
                'date_text': ev_date_text,
                'start_date': ev_start,
                'validity_text': ev_validity,
                'pdf_url': ev_pdf_url,
                'ozet': (b.belge.ozet if b.belge and b.belge.ozet else ''),
                'onemli_notlar': (b.belge.onemli_notlar if b.belge and b.belge.onemli_notlar else []),
            }

    events_list = sorted(
        events_map.values(),
        key=lambda x: (x['start_date'] or '9999-99-99', x['title']),
    )

    qs = all_qs
    if event_id_raw.isdigit():
        qs = qs.filter(event_id=int(event_id_raw))
    elif baraj_adi:
        qs = qs.filter(baraj_adi=baraj_adi)

    if city:
        from django.db.models import Q
        qs = qs.filter(Q(event__sehir__icontains=city) | Q(belge__sehir_yer__icontains=city))
    if month:
        from django.db.models import Q
        qs = qs.filter(Q(event__yaris_tarihi_baslangic__startswith=month) | Q(belge__baslangic_tarihi__startswith=month))
    if baraj_turu:
        qs = qs.filter(baraj_turu=baraj_turu)
    if havuz in ('25m', '50m'):
        qs = qs.filter(havuz=havuz)
    if cinsiyet in ('Erkek', 'Kadın'):
        qs = qs.filter(cinsiyet=cinsiyet)
    if yas_etiketi:
        qs = qs.filter(yas_etiketi=yas_etiketi)
    if stil:
        qs = qs.filter(stil=stil)

    age_qs = all_qs
    if event_id_raw.isdigit():
        age_qs = age_qs.filter(event_id=int(event_id_raw))
    elif baraj_adi:
        age_qs = age_qs.filter(baraj_adi=baraj_adi)

    age_labels = list(
        age_qs
        .exclude(yas_etiketi__isnull=True)
        .exclude(yas_etiketi='')
        .values_list('yas_etiketi', flat=True)
        .distinct()
        .order_by('min_yas', 'yas_etiketi')
    )

    qs = qs.order_by('baraj_adi', 'havuz', 'baraj_turu', 'cinsiyet', 'min_yas', 'stil', 'mesafe')

    data = []
    for b in qs[:500]:
        pdf_url = ''
        source_url = ''
        belge_baslik = ''
        if b.belge:
            belge_baslik = b.belge.baslik or ''
            source_url = b.belge.kaynak_url or ''
            if b.belge.yerel_dosya:
                try:
                    pdf_url = request.build_absolute_uri(b.belge.yerel_dosya.url)
                except Exception:
                    pdf_url = b.belge.yerel_dosya.url
            if not pdf_url:
                pdf_url = source_url

        data.append({
            'id': b.id,
            'baraj_adi': b.baraj_adi,
            'baraj_turu': b.baraj_turu,
            'havuz': b.havuz or '',
            'cinsiyet': b.cinsiyet,
            'yas_etiketi': b.yas_etiketi or '',
            'dogum_yillari': b.dogum_yillari or [],
            'max_dogum_yili': b.max_dogum_yili,
            'mesafe': b.mesafe,
            'stil': b.stil,
            'sure': b.sure,
            'sure_cs': b.sure_cs,
            'event_id': b.event_id,
            'belge_id': b.belge_id,
            'belge_baslik': belge_baslik,
            'pdf_url': pdf_url,
            'source_url': source_url,
        })

    return api_response({
        'data': data,
        'meta': {
            'total': len(data),
            'baraj_names': [e['baraj_adi'] for e in events_list],
            'events': events_list,
            'cities': sorted(cities_set),
            'months': sorted(months_set),
            'age_labels': age_labels,
        },
    }, request=request, cache_seconds=60)


@require_GET
@cache_api_response(120)
def get_meet_detail(request, meet_id: int):
    """Tekil müsabaka detayları ve yarış programı."""
    try:
        meet = Event.objects.get(pk=meet_id)
    except Event.DoesNotExist:
        return api_error('not_found', 'Müsabaka bulunamadı', status=404)

    # Yarış programı (Yarış no bazında gruplanmış liste ve sonuç durumu)
    from django.db.models import Count, Q
    program_rows = (
        meet.yaris_sonuclari.exclude(yaris_no__isnull=True)
        .exclude(yaris_no='')
        .values('yaris_no', 'mesafe', 'stil', 'cinsiyet')
        .annotate(
            total=Count('id'),
            finished_count=Count(
                'id',
                filter=(Q(derece_saniye__gt=0) | (~Q(derece='Bekleniyor') & ~Q(derece='') & Q(derece__isnull=False)))
            )
        )
    )

    prog_dict = {}
    for r in program_rows:
        yno = str(r['yaris_no']).strip()
        if not yno:
            continue
        fin_cnt = r.get('finished_count') or 0
        is_pend = (fin_cnt == 0)

        if yno not in prog_dict:
            prog_dict[yno] = {
                'event_no': yno,
                'distance': r.get('mesafe'),
                'stroke': map_stroke(r.get('stil')),
                'stroke_label': (r.get('stil') or '').strip(),
                'gender': (r.get('cinsiyet') or '').strip(),
                'is_pending': is_pend,
                'status': 'Bekliyor' if is_pend else 'Sonuçlandı',
            }
        else:
            if not prog_dict[yno]['distance'] and r.get('mesafe'):
                prog_dict[yno]['distance'] = r.get('mesafe')
            if not prog_dict[yno]['stroke_label'] and r.get('stil'):
                prog_dict[yno]['stroke'] = map_stroke(r.get('stil'))
                prog_dict[yno]['stroke_label'] = (r.get('stil') or '').strip()
            if fin_cnt > 0:
                prog_dict[yno]['is_pending'] = False
                prog_dict[yno]['status'] = 'Sonuçlandı'

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
@cache_api_response(300)
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
@cache_api_response(15)
def get_meet_results(request, meet_id: int):
    """
    Müsabaka yarış sonuçları (Yarış No, Kulüp, Sporcu ve Durum filtreli).
    """
    try:
        meet = Event.objects.get(pk=meet_id)
    except Event.DoesNotExist:
        return api_error('not_found', 'Müsabaka bulunamadı', status=404)

    qs = meet.yaris_sonuclari.select_related('sporcu', 'kulup').only(
        'id', 'event_id', 'yaris_no', 'mesafe', 'stil', 'seri', 'kulvar', 'sira',
        'derece', 'derece_saniye', 'giris_derecesi', 'puan', 'baraj',
        'kaynak_turu', 'hesaplanan_yas', 'sporcu_yas', 'yas_grubu',
        'sporcu_id', 'sporcu__sporcu_adi', 'sporcu__dogum_yili',
        'kulup_id', 'kulup__kulup_adi',
    )

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
    summary_only = (request.GET.get('summary') or '').strip().lower() in ('1', 'true', 'yes')

    if summary_only and not event_no:
        from collections import defaultdict
        grouped = defaultdict(list)
        for r in qs:
            grouped[str(r.yaris_no or '').strip()].append(r)
        summarized = []
        for eno in sorted(grouped.keys(), key=lambda x: int(x) if x.isdigit() else 999999):
            summarized.extend(grouped[eno][:3])
        page_obj = summarized
        total_pages = 1
        total_count = len(summarized)
        has_next = False
    else:
        paginator = Paginator(qs, page_size)
        page_obj = paginator.get_page(page_num)
        total_pages = paginator.num_pages
        total_count = paginator.count
        has_next = page_obj.has_next()

    event_year = None
    if meet.yaris_tarihi_baslangic and len(str(meet.yaris_tarihi_baslangic)) >= 4:
        yr_str = str(meet.yaris_tarihi_baslangic)[:4]
        if yr_str.isdigit():
            event_year = int(yr_str)
    if not event_year:
        event_year = timezone.now().year

    results_data = []
    for r in page_obj:
        time_cs = seconds_to_cs(r.derece_saniye or r.derece)
        seed_cs = seconds_to_cs(r.giris_derecesi)
        res_status = map_result_status(r.derece, r.sira)
        standard = parse_qualifying_standard(r.baraj)
        source = 'live' if (r.kaynak_turu or '').upper() == 'CANLI' else 'official'
        age_group_label, age_group_order = compute_age_group_info(r, event_year)

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
            'age_group': age_group_label,
            'age_group_order': age_group_order,
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
        'total_pages': total_pages,
        'total_count': total_count,
        'has_next': has_next,
    }, request=request, cache_seconds=15)

