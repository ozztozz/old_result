# -*- coding: utf-8 -*-
from django.views.decorators.http import require_GET
from sonuclar.models import CanliYaris, YarisSonucu
from .utils import (
    api_response,
    api_error,
    seconds_to_cs,
    map_result_status,
    map_stroke,
    parse_qualifying_standard,
)


@require_GET
def get_live_meets(request):
    """Aktif ve son tamamlanan canlı yarışların durum özeti."""
    meets = CanliYaris.objects.all().order_by('-olusturulma_tarihi')[:15]
    data = []

    for m in meets:
        data.append({
            'id': m.id,
            'meet_id': m.event_id,
            'name': m.musabaka_adi or (m.event.musabaka_adi if m.event else 'Canlı Müsabaka'),
            'city': m.gosterilen_sehir,
            'date': m.gosterilen_tarih,
            'status': m.durum,
            'total_athletes': m.eklenen_kayit_sayisi or 0,
            'start_list_progress': {
                'processed': m.islenen_start_listesi or 0,
                'total': m.toplam_start_listesi or 0,
            },
            'result_list_progress': {
                'processed': m.islenen_sonuc_listesi or 0,
                'total': m.toplam_sonuc_listesi or 0,
            },
            'last_activity': m.son_islem_tarihi.isoformat() if m.son_islem_tarihi else None,
        })

    return api_response({'data': data}, request=request, cache_seconds=10)


@require_GET
def get_live_feed(request, live_id: int):
    """
    Belirli bir canlı yarışın start ve netice listesi akışı (Seri ve Kulvar detaylı).
    Parametreler: event_no, status (all/finished/pending)
    """
    try:
        live = CanliYaris.objects.select_related('event').get(pk=live_id)
    except CanliYaris.DoesNotExist:
        return api_error('not_found', 'Canlı yarış oturumu bulunamadı', status=404)

    if not live.event:
        return api_response({
            'live_id': live.id,
            'status': live.durum,
            'events': [],
            'data': [],
        }, request=request)

    qs = live.event.yaris_sonuclari.select_related('sporcu', 'kulup')

    event_no = (request.GET.get('event_no') or '').strip()
    if event_no:
        qs = qs.filter(yaris_no=event_no)

    status = (request.GET.get('status') or 'all').strip().lower()
    if status == 'finished':
        qs = qs.exclude(derece='Bekleniyor')
    elif status == 'pending':
        qs = qs.filter(derece='Bekleniyor')

    # Mevcut yarış numaraları listesi
    event_numbers = list(
        live.event.yaris_sonuclari.exclude(yaris_no__isnull=True)
        .exclude(yaris_no='')
        .values('yaris_no', 'mesafe', 'stil')
        .distinct()
    )
    events_prog = []
    seen_enos = set()
    for e in event_numbers:
        eno = str(e['yaris_no']).strip()
        if eno not in seen_enos:
            seen_enos.add(eno)
            events_prog.append({
                'event_no': eno,
                'distance': e.get('mesafe'),
                'stroke': map_stroke(e.get('stil')),
                'stroke_label': (e.get('stil') or '').strip(),
            })

    try:
        events_prog.sort(key=lambda x: int(x['event_no']) if x['event_no'].isdigit() else 9999)
    except Exception:
        events_prog.sort(key=lambda x: x['event_no'])

    # Sonuçları seri ve kulvara göre sırala
    results_raw = qs.order_by('yaris_no', 'seri', 'kulvar')[:200]
    feed_data = []

    for r in results_raw:
        time_cs = seconds_to_cs(r.derece_saniye or r.derece)
        seed_cs = seconds_to_cs(r.giris_derecesi)
        res_status = map_result_status(r.derece, r.sira)

        feed_data.append({
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
            'athlete': {
                'id': r.sporcu_id,
                'name': r.sporcu.sporcu_adi if r.sporcu else '',
                'birth_year': r.sporcu.dogum_yili if r.sporcu else None,
            },
            'club': {
                'id': r.kulup_id,
                'name': r.kulup.kulup_adi if r.kulup else 'Ferdi',
            } if r.kulup else None,
        })

    return api_response({
        'live_id': live.id,
        'status': live.durum,
        'events': events_prog,
        'data': feed_data,
    }, request=request, cache_seconds=10)
