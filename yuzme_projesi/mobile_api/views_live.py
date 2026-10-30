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

    # Mevcut yarışlar listesi (Mesafe, stil, cinsiyet ve yaş grubu detaylı)
    from django.db.models import Count, Q

    # Her yarış için durum özeti (tek sorguda!)
    # Kullanıcı kuralı: "Bekliyor" statüsü sonucu olmayan yarış demek.
    # Yarışa girmemiş tekil sporcular 'Bekleniyor' kalmış olabilir.
    # Dolayısıyla yarışta en az 1 bitmiş derece varsa o yarış "Sonuçlandı" kabul edilir.
    event_stats = {}
    try:
        stats_qs = live.event.yaris_sonuclari.values('yaris_no').annotate(
            total=Count('id'),
            finished_count=Count(
                'id',
                filter=(Q(derece_saniye__gt=0) | (~Q(derece='Bekleniyor') & ~Q(derece='') & Q(derece__isnull=False)))
            ),
        )
        for row in stats_qs:
            eno_key = str(row['yaris_no']).strip()
            total_cnt = row['total'] or 0
            finished_cnt = row['finished_count'] or 0
            # En az 1 bitmiş derece varsa yarış Sonuçlandı; 0 derece varsa Bekliyor
            is_pending = (finished_cnt == 0)
            event_stats[eno_key] = {
                'total': total_cnt,
                'finished': finished_cnt,
                'is_pending': is_pending,
            }
    except Exception:
        pass

    event_numbers = list(
        live.event.yaris_sonuclari.exclude(yaris_no__isnull=True)
        .exclude(yaris_no='')
        .values('yaris_no', 'mesafe', 'stil', 'cinsiyet', 'yas_grubu')
        .distinct()
    )
    events_prog = []
    seen_enos = set()
    for e in event_numbers:
        eno = str(e['yaris_no']).strip()
        if eno not in seen_enos:
            seen_enos.add(eno)
            dist = e.get('mesafe')
            stil = (e.get('stil') or '').strip()
            gender = (e.get('cinsiyet') or '').strip()
            age_grp = (e.get('yas_grubu') or '').strip()

            title_parts = []
            if dist:
                title_parts.append(f"{dist}m")
            if stil:
                title_parts.append(stil)
            name_str = " ".join(title_parts) if title_parts else "Yarış"

            stat = event_stats.get(eno, {})
            is_pend = stat.get('is_pending', True)

            events_prog.append({
                'event_no': eno,
                'name': name_str,
                'distance': dist,
                'stroke': map_stroke(stil),
                'stroke_label': stil,
                'gender': gender,
                'age_group': age_grp,
                'is_pending': is_pend,
                'status': 'Bekliyor' if is_pend else 'Sonuçlandı',
                'total_athletes': stat.get('total', 0),
            })

    try:
        events_prog.sort(key=lambda x: int(x['event_no']) if x['event_no'].isdigit() else 9999)
    except Exception:
        events_prog.sort(key=lambda x: x['name'])

    # Sonuçları sırala:
    # Eğer sonuçlar varsa dereceye göre (DQ en sonda),
    # henüz sonuç yoksa (start listesi) seri ve kulvara göre sıralanır
    has_results = qs.filter(derece_saniye__gt=0).exists()
    if has_results:
        results_raw = list(qs[:500])
        def sort_key(r):
            is_dq = (r.sira or '').strip().upper() in ('DQ', 'DNS', 'DNF') or (r.derece or '').strip().upper() in ('DQ', 'DNS', 'DNF')
            is_waiting = (r.derece or '').strip() == 'Bekleniyor'
            sec = r.derece_saniye if (r.derece_saniye and r.derece_saniye > 0) else 999999.0
            seri_val = int(r.seri) if (r.seri and r.seri.isdigit()) else 999
            kulvar_val = r.kulvar or 999
            # Sıralama önceliği:
            # 0: Geçerli dereceye sahip olanlar (en hızlı derece en üstte)
            # 1: Bekleyenler (seri ve kulvara göre)
            # 2: Diskalifiye / Terk (en sonda)
            if is_dq:
                return (2, 0, seri_val, kulvar_val)
            elif is_waiting or sec >= 999999.0:
                return (1, 0, seri_val, kulvar_val)
            else:
                return (0, sec, seri_val, kulvar_val)

        results_raw.sort(key=sort_key)
    else:
        results_raw = list(qs.order_by('seri', 'kulvar')[:500])
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

