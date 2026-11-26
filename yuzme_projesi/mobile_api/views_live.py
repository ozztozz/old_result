# -*- coding: utf-8 -*-
import re
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone as dt_timezone
from django.db.models import Count, Q
from django.views.decorators.http import require_GET
from sonuclar.models import CanliYaris, YarisSonucu
from sonuclar.live_engine import parse_tr_date_range
from sonuclar.local_baraj_parser import _fold_tr
from .utils import (
    api_response,
    api_error,
    cache_api_response,
    seconds_to_cs,
    map_result_status,
    map_stroke,
    parse_qualifying_standard,
    compute_age_group_info,
)

TR_TIMEZONE = dt_timezone(timedelta(hours=3))


def _extract_live_meet_dates(m: CanliYaris):
    """Müsabakanın (baslangic_iso, bitis_iso) tarihlerini döndürür."""
    start_iso = ""
    end_iso = ""
    if m.event_id and m.event:
        cand_s = str(m.event.yaris_tarihi_baslangic or "").strip()
        cand_e = str(m.event.yaris_tarihi_bitis or "").strip()
        if re.match(r"^\d{4}-\d{2}-\d{2}$", cand_s):
            start_iso = cand_s
        if re.match(r"^\d{4}-\d{2}-\d{2}$", cand_e):
            end_iso = cand_e

    if not start_iso or not end_iso:
        raw_t = (m.gosterilen_tarih or m.tarih or "").strip()
        if raw_t and raw_t != "-":
            m_iso = re.search(r"(\d{4}-\d{2}-\d{2})", raw_t)
            if m_iso:
                if not start_iso:
                    start_iso = m_iso.group(1)
            else:
                p_start, p_end = parse_tr_date_range(raw_t)
                if not start_iso and p_start:
                    start_iso = p_start
                if not end_iso and p_end:
                    end_iso = p_end

    if not end_iso and start_iso:
        end_iso = start_iso
    return start_iso, end_iso


def _live_meet_sort_key(m: CanliYaris, today_iso: str = ""):
    start_iso, end_iso = _extract_live_meet_dates(m)
    is_live_today = 1 if (today_iso and start_iso and end_iso and start_iso <= today_iso <= end_iso) else 0
    is_active = 1 if (m.durum or "").upper() in ("ISLENIYOR", "BEKLIYOR", "BEKLEMEDE") else 0
    athlete_count = int(m.eklenen_kayit_sayisi or 0)
    ts = m.olusturulma_tarihi.timestamp() if m.olusturulma_tarihi else 0.0
    return (is_live_today, is_active, start_iso or "", athlete_count, ts, m.id)


@require_GET
@cache_api_response(10)
def get_live_meets(request):
    """Önümüzdeki 10 gün içinde başlayacak ve 1 haftadan eski olmayan (start listesi bulunan) canlı yarışlar."""
    today_tr = datetime.now(TR_TIMEZONE).date()
    today_iso = today_tr.isoformat()
    week_ago_iso = (today_tr - timedelta(days=7)).isoformat()
    ten_days_ahead_iso = (today_tr + timedelta(days=10)).isoformat()

    qs = (
        CanliYaris.objects.select_related('event')
        .filter(Q(toplam_start_listesi__gt=0) | Q(islenen_start_listesi__gt=0))
        .exclude(event__yaris_tarihi_bitis__startswith='20', event__yaris_tarihi_bitis__lt=week_ago_iso)
        .exclude(event__yaris_tarihi_baslangic__startswith='20', event__yaris_tarihi_baslangic__gt=ten_days_ahead_iso)
    )

    filtered = []
    for m in qs:
        # Start listesi olmayan (henüz boş) yarışları gösterme
        if (m.toplam_start_listesi or 0) <= 0 and (m.islenen_start_listesi or 0) <= 0:
            continue

        start_iso, end_iso = _extract_live_meet_dates(m)
        if start_iso:
            # 10 günden daha uzak gelecekteki yarışları ve 1 haftadan eski yarışları ele
            if start_iso > ten_days_ahead_iso:
                continue
            if end_iso and end_iso < week_ago_iso:
                continue
        else:
            # Tarihi çözülemeyen kayıtlarda oluşturulma tarihine göre 7 gün sınırı uygula
            if m.olusturulma_tarihi:
                created_tr = m.olusturulma_tarihi.astimezone(TR_TIMEZONE).date()
                if created_tr.isoformat() < week_ago_iso or created_tr.isoformat() > ten_days_ahead_iso:
                    continue

        filtered.append(m)

    meets = sorted(
        filtered,
        key=lambda m: _live_meet_sort_key(m, today_iso),
        reverse=True,
    )[:50]

    event_ids = [m.event_id for m in meets if m.event_id]
    event_year_map = {}
    for m in meets:
        if m.event_id:
            s_iso, _ = _extract_live_meet_dates(m)
            yr = int(s_iso[:4]) if (s_iso and len(s_iso) >= 4 and s_iso[:4].isdigit()) else today_tr.year
            event_year_map[m.event_id] = yr

    age_range_by_event = {}
    if event_ids:
        agg_rows = (
            YarisSonucu.objects.filter(event_id__in=event_ids)
            .values('event_id', 'hesaplanan_yas', 'sporcu__dogum_yili')
            .annotate(cnt=Count('id'))
        )
        counts_by_event = defaultdict(Counter)
        for row in agg_rows:
            eid = row['event_id']
            cnt = row['cnt'] or 0
            if cnt <= 0:
                continue
            age = row.get('hesaplanan_yas')
            if not (age and 0 < age < 100):
                by = row.get('sporcu__dogum_yili')
                if by and by > 1900:
                    yr = event_year_map.get(eid, today_tr.year)
                    calc = yr - int(by)
                    if 0 < calc < 100:
                        age = calc
            if age and 0 < age < 100:
                counts_by_event[eid][int(age)] += cnt

        for eid, age_counter in counts_by_event.items():
            total_cnt = sum(age_counter.values())
            if total_cnt <= 0:
                continue
            min_threshold = 1 if total_cnt < 10 else max(3, int(total_cnt * 0.03))
            valid_ages = [a for a, c in age_counter.items() if c >= min_threshold]
            if not valid_ages:
                valid_ages = list(age_counter.keys())
            min_a = min(valid_ages)
            max_a = max(valid_ages)
            age_range_by_event[eid] = (
                f'{min_a} Yaş' if min_a == max_a else f'{min_a}–{max_a} Yaş'
            )

    data = []

    for m in meets:
        data.append({
            'id': m.id,
            'meet_id': m.event_id,
            'name': m.musabaka_adi or (m.event.musabaka_adi if m.event else 'Canlı Müsabaka'),
            'city': m.gosterilen_sehir,
            'date': m.gosterilen_tarih,
            'age_range': age_range_by_event.get(m.event_id),
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
@cache_api_response(8)
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

    event_no = (request.GET.get('event_no') or '').strip()
    events_only = (request.GET.get('events_only') or '').strip().lower() in ('1', 'true', 'yes')
    include_events = (request.GET.get('include_events') or '1').strip().lower() not in ('0', 'false', 'no')
    summary_only = (request.GET.get('summary') or '').strip().lower() in ('1', 'true', 'yes')
    filter_club_id = (request.GET.get('club_id') or '').strip()
    filter_club_name = (request.GET.get('club_name') or '').strip().lower()
    filter_athlete_name = (request.GET.get('athlete_name') or '').strip().lower()

    events_prog = []
    event_prog_map = {}
    if events_only or include_events:
        # Her yarış için durum ve metadata özeti tek sorguda
        try:
            event_rows = (
                live.event.yaris_sonuclari.exclude(yaris_no__isnull=True)
                .exclude(yaris_no='')
                .values('yaris_no', 'mesafe', 'stil', 'cinsiyet', 'yas_grubu')
                .annotate(
                    total=Count('id'),
                    finished_count=Count(
                        'id',
                        filter=(Q(derece_saniye__gt=0) | (~Q(derece='Bekleniyor') & ~Q(derece='') & Q(derece__isnull=False)))
                    ),
                )
            )
            for row in event_rows:
                eno = str(row['yaris_no']).strip()
                if not eno:
                    continue
                total_cnt = row['total'] or 0
                finished_cnt = row['finished_count'] or 0
                dist = row.get('mesafe')
                stil = (row.get('stil') or '').strip()
                gender = (row.get('cinsiyet') or '').strip()
                age_grp = (row.get('yas_grubu') or '').strip()

                if eno not in event_prog_map:
                    title_parts = []
                    if dist:
                        title_parts.append(f"{dist}m")
                    if stil:
                        title_parts.append(stil)
                    name_str = " ".join(title_parts) if title_parts else "Yarış"
                    is_pend = (finished_cnt == 0)
                    event_prog_map[eno] = {
                        'event_no': eno,
                        'name': name_str,
                        'distance': dist,
                        'stroke': map_stroke(stil),
                        'stroke_label': stil,
                        'gender': gender,
                        'age_group': age_grp,
                        'is_pending': is_pend,
                        'status': 'Bekliyor' if is_pend else 'Sonuçlandı',
                        'total_athletes': total_cnt,
                    }
                else:
                    entry = event_prog_map[eno]
                    entry['total_athletes'] += total_cnt
                    if finished_cnt > 0:
                        entry['is_pending'] = False
                        entry['status'] = 'Sonuçlandı'
                    if not entry['distance'] and dist:
                        entry['distance'] = dist
                    if not entry['stroke_label'] and stil:
                        entry['stroke'] = map_stroke(stil)
                        entry['stroke_label'] = stil
        except Exception:
            pass

        events_prog = list(event_prog_map.values())
        try:
            events_prog.sort(key=lambda x: int(x['event_no']) if x['event_no'].isdigit() else 9999)
        except Exception:
            events_prog.sort(key=lambda x: x['name'])

    if events_only:
        return api_response({
            'live_id': live.id,
            'status': live.durum,
            'events': events_prog,
            'data': [],
        }, request=request, cache_seconds=10)

    only_fields = [
        'id', 'event_id', 'yaris_no', 'mesafe', 'stil', 'seri', 'kulvar', 'sira',
        'derece', 'derece_saniye', 'giris_derecesi', 'puan',
        'hesaplanan_yas', 'sporcu_yas', 'yas_grubu',
        'sporcu_id', 'sporcu__sporcu_adi', 'sporcu__dogum_yili',
        'kulup_id', 'kulup__kulup_adi',
    ]
    if not summary_only:
        only_fields.append('ara_dereceler')

    qs = live.event.yaris_sonuclari.select_related('sporcu', 'kulup').only(*only_fields)

    if event_no:
        qs = qs.filter(yaris_no=event_no)

    status = (request.GET.get('status') or 'all').strip().lower()
    if status == 'finished':
        qs = qs.exclude(derece='Bekleniyor')
    elif status == 'pending':
        qs = qs.filter(derece='Bekleniyor')

    import re

    def parse_leading_int(val, default=999999):
        if val is None:
            return default
        if isinstance(val, int):
            return val
        m = re.search(r'\d+', str(val))
        if m:
            try:
                return int(m.group(0))
            except ValueError:
                return default
        return default

    def sort_entry(r):
        is_dq = (r.sira or '').strip().upper() in ('DQ', 'DNS', 'DNF') or (r.derece or '').strip().upper() in ('DQ', 'DNS', 'DNF')
        is_waiting = (r.derece or '').strip() == 'Bekleniyor'
        sec = r.derece_saniye if (r.derece_saniye and r.derece_saniye > 0) else 999999.0
        seri_val = parse_leading_int(r.seri, default=999)
        kulvar_val = parse_leading_int(r.kulvar, default=999)
        rank_val = parse_leading_int(r.sira, default=999999)

        if is_dq:
            return (2, seri_val, kulvar_val)
        elif is_waiting or sec >= 999999.0:
            return (1, seri_val, kulvar_val)
        else:
            rank_score = rank_val if rank_val < 999999 else sec
            return (0, rank_score, sec, seri_val, kulvar_val)

    def sort_no_result(r):
        return (parse_leading_int(r.seri, default=999), parse_leading_int(r.kulvar, default=999))

    results_raw = list(qs)
    has_results = any((r.derece_saniye or 0) > 0 for r in results_raw)
    if event_no:
        if has_results:
            results_raw.sort(key=sort_entry)
        else:
            results_raw.sort(key=sort_no_result)
    elif summary_only:
        # Özet modu: Her yarış için en fazla ilk 3 + (varsa) seçili kulüp/sporcu satırları
        from collections import defaultdict
        grouped = defaultdict(list)
        for r in results_raw:
            grouped[str(r.yaris_no or '').strip()].append(r)

        def _norm_club(name: str) -> str:
            s = _fold_tr(name or '')
            for suf in ('spor kulubu', 'yuzme kulubu', 'kulubu', 'dernegi', 's.k.', 's.k', 'sk'):
                s = s.replace(suf, '')
            return ' '.join(s.split())

        norm_filter_club = _norm_club(filter_club_name)
        norm_filter_athlete = _fold_tr(filter_athlete_name)

        def is_focus_row(r):
            if filter_club_id.isdigit() and r.kulup_id == int(filter_club_id):
                return True
            if norm_filter_club and r.kulup:
                nc = _norm_club(r.kulup.kulup_adi or '')
                if nc and (norm_filter_club in nc or nc in norm_filter_club):
                    return True
            if norm_filter_athlete and r.sporcu and _fold_tr(r.sporcu.sporcu_adi or '') == norm_filter_athlete:
                return True
            return False

        summarized = []
        sorted_enos = sorted(grouped.keys(), key=lambda x: parse_leading_int(x, default=999999))
        for eno in sorted_enos:
            ev_rows = grouped[eno]
            ev_has_res = any((r.derece_saniye or 0) > 0 for r in ev_rows)
            ev_rows.sort(key=sort_entry if ev_has_res else sort_no_result)
            kept_ids = set()
            for r in ev_rows[:3]:
                kept_ids.add(r.id)
                summarized.append(r)
            if filter_club_id or filter_club_name or filter_athlete_name:
                for r in ev_rows[3:]:
                    if r.id not in kept_ids and is_focus_row(r):
                        kept_ids.add(r.id)
                        summarized.append(r)
        results_raw = summarized
    else:
        # Tüm müsabaka akışı: Önce yarış numarası (sayısal), sonra yarış içi sıralama
        def sort_full_meet(r):
            eno_val = parse_leading_int(r.yaris_no, default=999999)
            sub_sort = sort_entry(r) if has_results else sort_no_result(r)
            return (eno_val, sub_sort)

        results_raw.sort(key=sort_full_meet)

    event_year = None
    if live.event and live.event.yaris_tarihi_baslangic and len(str(live.event.yaris_tarihi_baslangic)) >= 4:
        yr_str = str(live.event.yaris_tarihi_baslangic)[:4]
        if yr_str.isdigit():
            event_year = int(yr_str)
    if not event_year:
        event_year = datetime.now(TR_TIMEZONE).year

    feed_data = []

    for r in results_raw:
        time_cs = seconds_to_cs(r.derece_saniye or r.derece)
        seed_cs = seconds_to_cs(r.giris_derecesi)
        res_status = map_result_status(r.derece, r.sira)
        age_group_label, age_group_order = compute_age_group_info(r, event_year)

        feed_data.append({
            'id': r.id,
            'event_no': str(r.yaris_no or '').strip(),
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
            'split_times': None if summary_only else (r.ara_dereceler if isinstance(r.ara_dereceler, dict) and r.ara_dereceler else None),
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
        'live_id': live.id,
        'status': live.durum,
        'events': events_prog,
        'data': feed_data,
    }, request=request, cache_seconds=10)

