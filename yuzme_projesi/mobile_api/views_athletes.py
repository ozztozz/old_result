# -*- coding: utf-8 -*-
from collections import Counter
from django.db.models import Count, F, Prefetch, Q, Window
from django.db.models.functions import RowNumber
from django.views.decorators.http import require_GET
from django.core.paginator import Paginator
from django.utils import timezone
from sonuclar.models import Sporcu, YarisSonucu, CanliYaris
from sonuclar.local_baraj_parser import _fold_tr, _normalize_stil
from .utils import (
    api_response,
    api_error,
    cache_api_response,
    seconds_to_cs,
    map_result_status,
    map_stroke,
    parse_qualifying_standard,
    detect_course,
)


def _resolve_active_club(tarihce_list, fallback_club):
    """Kulüp tarihçesinden aktif kulübü (okul hariç) öncelik sırasına göre çözer."""
    return (
        next((t.kulup for t in tarihce_list if t.kulup and t.kulup.okul_mu == 0 and t.aktif_kulup_mu == 1), None)
        or next((t.kulup for t in tarihce_list if t.kulup and t.kulup.okul_mu == 0), None)
        or (tarihce_list[0].kulup if tarihce_list else None)
        or fallback_club
    )


@require_GET
@cache_api_response(60)
def get_athlete_detail(request, athlete_id: int):
    """
    Sporcu profil kartı, 25m/50m Kişisel En İyi (PB) dereceleri ve kariyer özeti.
    """
    try:
        athlete = (
            Sporcu.objects.select_related('birincil_kulup')
            .only(
                'id', 'sporcu_adi', 'dogum_yili', 'cinsiyet', 'birincil_kulup_id',
                'birincil_kulup__id', 'birincil_kulup__kulup_adi',
            )
            .get(pk=athlete_id)
        )
    except Sporcu.DoesNotExist:
        return api_error('not_found', 'Sporcu bulunamadı', status=404)

    # Aktif kulüp ve okul (tek sorguda kulüp tarihçesinden çözülür)
    tarihce_list = list(
        athlete.kulup_tarihcesi.select_related('kulup')
        .only(
            'id', 'kulup_id', 'aktif_kulup_mu', 'son_yaris_tarihi',
            'kulup__id', 'kulup__kulup_adi', 'kulup__okul_mu',
        )
        .order_by('-son_yaris_tarihi', '-id')
    )
    active_club = _resolve_active_club(tarihce_list, athlete.birincil_kulup)
    active_club_data = {
        'id': active_club.id,
        'name': active_club.kulup_adi
    } if active_club else None

    school_entry = next((t for t in tarihce_list if t.kulup and t.kulup.okul_mu == 1), None)
    school_name = school_entry.kulup.kulup_adi if school_entry else None

    # Tüm geçerli dereceler (yalnızca gerekli sütunlar)
    all_results = list(
        athlete.yaris_sonuclari.select_related('event')
        .filter(derece_saniye__isnull=False, derece_saniye__gt=0)
        .only(
            'id', 'mesafe', 'stil', 'derece', 'derece_saniye', 'puan', 'sira',
            'kaynak_turu', 'event__musabaka_adi', 'event__yaris_tarihi_baslangic',
        )
        .order_by('derece_saniye')
    )

    # 25m (SC) ve 50m (LC) PB Tablosu Hesaplama
    seen_pbs = set()
    pbs_sc = []
    pbs_lc = []

    for r in all_results:
        if not r.mesafe or not r.stil:
            continue
        c = detect_course(r.event.musabaka_adi if r.event else r.kaynak_turu)
        key = (c, r.mesafe, r.stil)
        if key not in seen_pbs:
            seen_pbs.add(key)
            item = {
                'distance': r.mesafe,
                'stroke': map_stroke(r.stil),
                'stroke_label': r.stil.strip(),
                'time': r.derece,
                'time_cs': seconds_to_cs(r.derece_saniye),
                'points': r.puan if (r.puan and r.puan > 0) else None,
                'date': r.event.yaris_tarihi_baslangic if r.event else '',
                'meet_name': r.event.musabaka_adi if r.event else '',
                'course': c,
            }
            if c == 'SC':
                pbs_sc.append(item)
            else:
                pbs_lc.append(item)

    # Standart stil sıralama önceliği: Serbest, Sırt, Kurbağa, Kelebek, Karışık
    order_map = {'free': 1, 'back': 2, 'breast': 3, 'fly': 4, 'medley': 5, 'other': 9}
    sort_fn = lambda x: (order_map.get(x['stroke'], 9), x['distance'])
    pbs_sc.sort(key=sort_fn)
    pbs_lc.sort(key=sort_fn)

    # Kariyer İstatistikleri (tek aggregate sorgusu)
    stats_agg = athlete.yaris_sonuclari.aggregate(
        total_races=Count('id'),
        standards_count=Count(
            'id',
            filter=Q(baraj__isnull=False) & ~Q(baraj='') & ~Q(baraj='-') & ~Q(baraj__iexact='HAYIR'),
        ),
    )
    total_races = stats_agg['total_races'] or 0
    podium_results = [r for r in all_results if str(r.sira or '').strip() in ('1', '2', '3')]
    podium_count = len(podium_results)
    podium_rate = round((podium_count / total_races) * 100, 1) if total_races > 0 else 0
    standards_count = stats_agg['standards_count'] or 0

    # Scout değerlendirme notu
    stiller = [r.stil for r in all_results if r.stil]
    top_stiller = [st for st, _ in Counter(stiller).most_common(2)] if stiller else []
    top_stiller_str = " ve ".join(top_stiller) if top_stiller else "çeşitli"
    best_race = max(all_results, key=lambda x: x.puan or 0) if all_results else None

    notes = []
    if top_stiller:
        notes.append(f"Ağırlıklı olarak {top_stiller_str} branşlarında yarışan {athlete.sporcu_adi}, toplam {total_races} resmi yarışta havuza girdi.")
    else:
        notes.append(f"Kariyerinde toplam {total_races} resmi yarışta mücadele eden {athlete.sporcu_adi},")

    if podium_count > 0:
        notes.append(f"{podium_count} kez kürsüye çıkarak (%{podium_rate} podyum oranı) istikrarlı bir madalya başarısı yakaladı.")
    if standards_count > 0:
        notes.append(f"Kariyerinde {standards_count} yarışta resmi baraj derecesini geçmeyi başardı.")
    if best_race and best_race.puan:
        notes.append(f"Zirve performansını {best_race.mesafe}m {best_race.stil} branşında {best_race.derece} ({best_race.puan} Puan) ile kaydetti.")

    scout_note = " ".join(notes) if notes else "Kayıtlı yarış verileri üzerinden gelişim grafiği takip edilmektedir."

    current_year = timezone.now().year
    current_age = (current_year - athlete.dogum_yili) if athlete.dogum_yili else None

    return api_response({
        'data': {
            'id': athlete.id,
            'name': athlete.sporcu_adi,
            'birth_year': athlete.dogum_yili,
            'age': current_age,
            'gender': athlete.cinsiyet or '',
            'current_club': active_club_data,
            'school': school_name,
            'stats': {
                'total_races': total_races,
                'podium_count': podium_count,
                'podium_rate': podium_rate,
                'standards_passed': standards_count,
            },
            'scout_note': scout_note,
            'personal_bests': {
                'course_50m': pbs_lc,
                'course_25m': pbs_sc,
            }
        }
    }, request=request, cache_seconds=60)


@require_GET
@cache_api_response(30)
def get_athlete_races(request, athlete_id: int):
    """Sporcunun kronolojik tüm yarış geçmişi (Filtreli ve sayfalı)."""
    try:
        athlete = Sporcu.objects.get(pk=athlete_id)
    except Sporcu.DoesNotExist:
        return api_error('not_found', 'Sporcu bulunamadı', status=404)

    qs = (
        athlete.yaris_sonuclari.select_related('event', 'kulup')
        .only(
            'id', 'event_id', 'yaris_no', 'mesafe', 'stil', 'seri', 'kulvar',
            'sira', 'derece', 'derece_saniye', 'puan', 'baraj',
            'event__musabaka_adi', 'event__yaris_tarihi_baslangic', 'kulup__kulup_adi',
        )
        .order_by('-event__yaris_tarihi_baslangic', '-id')
    )

    stroke = (request.GET.get('stroke') or '').strip().lower()
    if stroke:
        rev_stroke_map = {
            'free': ['Serbest', 'SERBEST', 'serbest'],
            'freestyle': ['Serbest', 'SERBEST', 'serbest'],
            'back': ['Sırtüstü', 'SIRTÜSTÜ', 'SIRTUSTU', 'Sirtüstü', 'sırtüstü'],
            'breast': ['Kurbağalama', 'KURBAĞALAMA', 'KURBAGALAMA', 'kurbağalama'],
            'fly': ['Kelebek', 'KELEBEK', 'kelebek'],
            'medley': ['Karışık', 'KARIŞIK', 'KARISIK', 'karışık'],
            'im': ['Karışık', 'KARIŞIK', 'KARISIK', 'karışık'],
        }
        allowed = rev_stroke_map.get(stroke)
        if allowed:
            qs = qs.filter(stil__in=allowed)

    distance = request.GET.get('distance')
    if distance and distance.isdigit():
        qs = qs.filter(mesafe=int(distance))

    year = (request.GET.get('year') or '').strip()
    if year.isdigit():
        qs = qs.filter(event__yaris_tarihi_baslangic__startswith=year)

    page_size = min(int(request.GET.get('page_size', 30)), 100)
    page_num = int(request.GET.get('page', 1))

    paginator = Paginator(qs, page_size)
    page_obj = paginator.get_page(page_num)

    races_data = []
    for r in page_obj:
        time_cs = seconds_to_cs(r.derece_saniye or r.derece)
        res_status = map_result_status(r.derece, r.sira)
        standard = parse_qualifying_standard(r.baraj)
        course = detect_course(r.event.musabaka_adi if r.event else '')

        races_data.append({
            'id': r.id,
            'meet_id': r.event_id,
            'meet_name': r.event.musabaka_adi if r.event else '',
            'date': r.event.yaris_tarihi_baslangic if r.event else '',
            'course': course,
            'event_no': str(r.yaris_no or ''),
            'distance': r.mesafe,
            'stroke': map_stroke(r.stil),
            'stroke_label': (r.stil or '').strip(),
            'heat': (r.seri or '').strip(),
            'lane': r.kulvar,
            'rank': str(r.sira or '').strip(),
            'time': r.derece if r.derece != 'Bekleniyor' else None,
            'time_cs': time_cs if res_status == 'OK' else None,
            'result_status': res_status,
            'points': r.puan if (r.puan and r.puan > 0) else None,
            'qualifying_standard': standard,
            'club_name': r.kulup.kulup_adi if r.kulup else '',
        })

    return api_response({
        'data': races_data,
        'page': page_num,
        'total_pages': paginator.num_pages,
        'total_count': paginator.count,
        'has_next': page_obj.has_next(),
    }, request=request, cache_seconds=30)


@require_GET
@cache_api_response(300)
def get_athlete_clubs(request, athlete_id: int):
    """Sporcunun kulüp lisans tarihçesi."""
    try:
        athlete = Sporcu.objects.get(pk=athlete_id)
    except Sporcu.DoesNotExist:
        return api_error('not_found', 'Sporcu bulunamadı', status=404)

    history_qs = (
        athlete.kulup_tarihcesi.select_related('kulup')
        .order_by('donem_sirasi', '-id')
    )

    history_data = []
    for h in history_qs:
        history_data.append({
            'club_id': h.kulup_id,
            'club_name': h.kulup.kulup_adi if h.kulup else '',
            'first_race_date': h.ilk_yaris_tarihi or '',
            'last_race_date': h.son_yaris_tarihi or '',
            'race_count': h.toplam_yaris_sayisi or 0,
            'is_active': bool(h.aktif_kulup_mu),
        })

    return api_response({
        'data': history_data
    }, request=request, cache_seconds=300)


@require_GET
@cache_api_response(30)
def get_athletes_summary(request):
    """
    Favoriler ekranı için toplu sporcu özeti (N+1 isteklerini önler).
    Parametre: ids (Virgülle ayrılmış ID'ler, ör: ids=1,2,5)
    """
    raw_ids = (request.GET.get('ids') or '').strip()
    if not raw_ids:
        return api_response({'data': []}, request=request)

    id_list = [int(x) for x in raw_ids.split(',') if x.strip().isdigit()][:50]
    if not id_list:
        return api_response({'data': []}, request=request)

    kulup_gecmisi_model = Sporcu.kulup_tarihcesi.rel.related_model
    athletes = (
        Sporcu.objects.filter(id__in=id_list)
        .select_related('birincil_kulup')
        .prefetch_related(
            Prefetch(
                'kulup_tarihcesi',
                queryset=kulup_gecmisi_model.objects.select_related('kulup')
                .only(
                    'id', 'sporcu_id', 'kulup_id', 'aktif_kulup_mu', 'son_yaris_tarihi',
                    'kulup__id', 'kulup__kulup_adi', 'kulup__okul_mu',
                )
                .order_by('-son_yaris_tarihi', '-id'),
                to_attr='prefetched_clubs',
            )
        )
        .only('id', 'sporcu_adi', 'dogum_yili', 'toplam_yaris_sayisi', 'birincil_kulup__kulup_adi')
    )

    latest_rows = (
        YarisSonucu.objects.filter(sporcu_id__in=id_list)
        .select_related('event')
        .only(
            'id', 'sporcu_id', 'mesafe', 'stil', 'derece', 'derece_saniye',
            'event__musabaka_adi', 'event__yaris_tarihi_baslangic',
        )
        .annotate(
            rn=Window(
                expression=RowNumber(),
                partition_by=[F('sporcu_id')],
                order_by=[F('event__yaris_tarihi_baslangic').desc(), F('id').desc()],
            )
        )
        .filter(rn=1)
    )
    latest_map = {r.sporcu_id: r for r in latest_rows}

    best_rows = (
        YarisSonucu.objects.filter(sporcu_id__in=id_list, puan__gt=0)
        .only('id', 'sporcu_id', 'mesafe', 'stil', 'derece', 'puan')
        .annotate(
            rn=Window(
                expression=RowNumber(),
                partition_by=[F('sporcu_id')],
                order_by=[F('puan').desc(), F('id').desc()],
            )
        )
        .filter(rn=1)
    )
    best_map = {r.sporcu_id: r for r in best_rows}

    summary_data = []
    for a in athletes:
        latest_race = latest_map.get(a.id)
        best_race = best_map.get(a.id)
        active_club = _resolve_active_club(a.prefetched_clubs, a.birincil_kulup)

        summary_data.append({
            'id': a.id,
            'name': a.sporcu_adi,
            'birth_year': a.dogum_yili,
            'club_name': active_club.kulup_adi if active_club else 'Ferdi',
            'total_races': a.toplam_yaris_sayisi or 0,
            'latest_race': {
                'meet_name': latest_race.event.musabaka_adi if latest_race and latest_race.event else '',
                'date': latest_race.event.yaris_tarihi_baslangic if latest_race and latest_race.event else '',
                'distance': latest_race.mesafe if latest_race else None,
                'stroke': map_stroke(latest_race.stil) if latest_race else '',
                'time': latest_race.derece if latest_race else '',
                'time_cs': seconds_to_cs(latest_race.derece_saniye or latest_race.derece) if latest_race else None,
            } if latest_race else None,
            'top_performance': {
                'distance': best_race.mesafe if best_race else None,
                'stroke': map_stroke(best_race.stil) if best_race else '',
                'time': best_race.derece if best_race else '',
                'points': best_race.puan if best_race else None,
            } if best_race else None,
        })

    return api_response({'data': summary_data}, request=request, cache_seconds=30)


@require_GET
@cache_api_response(120)
def get_athlete_baraj_targets(request, athlete_id: int):
    """
    Sporcunun cinsiyeti ve doğum yılına göre tanımlı reglaman barajlarını
    ve sporcunun mevcut PB'sine olan farkını (diff_cs) döndürür.
    """
    try:
        athlete = Sporcu.objects.get(pk=athlete_id)
    except Sporcu.DoesNotExist:
        return api_error('not_found', 'Sporcu bulunamadı', status=404)

    stroke_param = (request.GET.get('stroke') or '').strip().lower()
    distance_param = (request.GET.get('distance') or '').strip()
    course_param = (request.GET.get('course') or '').strip().upper()
    pb_cs_param = (request.GET.get('pb_cs') or '').strip()

    stroke_to_tr = {
        'free': 'Serbest',
        'freestyle': 'Serbest',
        'back': 'Sırtüstü',
        'breast': 'Kurbağalama',
        'fly': 'Kelebek',
        'medley': 'Karışık',
        'im': 'Karışık',
    }
    target_stil = stroke_to_tr.get(stroke_param) or _normalize_stil(stroke_param)
    target_dist = int(distance_param) if distance_param.isdigit() else None
    target_havuz = '25m' if course_param in ('SC', 'SCM', '25M', '25') else ('50m' if course_param in ('LC', 'LCM', '50M', '50') else None)
    pb_cs = int(pb_cs_param) if pb_cs_param.isdigit() else None

    g_fold = _fold_tr(athlete.cinsiyet or '')
    target_gender = 'erkek' if 'erkek' in g_fold else ('kadin' if ('kadin' in g_fold or 'bayan' in g_fold) else None)
    birth_year = athlete.dogum_yili

    targets = []
    seen_rules = set()

    # Sporcunun branş/havuz bazlı yarış sonuçları: (havuz, mesafe, stil) -> [(event_date, cs), ...]
    race_records = {}
    from .utils import detect_course, seconds_to_cs
    for r in (
        athlete.yaris_sonuclari.select_related('event')
        .filter(derece_saniye__gt=0, mesafe__isnull=False, stil__isnull=False)
        .only(
            'mesafe', 'stil', 'derece_saniye',
            'event__musabaka_adi', 'event__kaynak_turu', 'event__havuz',
            'event__yaris_tarihi_baslangic',
        )
    ):
        r_stil = _normalize_stil(r.stil or '')
        if not r_stil:
            continue
        r_course = (r.event.havuz if (r.event and r.event.havuz in ('25m', '50m')) else None)
        if not r_course and r.event:
            c_code = detect_course(r.event.musabaka_adi or r.event.kaynak_turu)
            r_course = '25m' if c_code == 'SC' else '50m'
        cs = seconds_to_cs(r.derece_saniye)
        ev_date = (r.event.yaris_tarihi_baslangic or '') if r.event else ''
        if cs and cs > 0 and r_course:
            race_records.setdefault((r_course, int(r.mesafe), r_stil), []).append((ev_date, cs))

    def _best_pb_in_window(havuz_val, mesafe_val, stil_val, start_date, end_date):
        recs = race_records.get((havuz_val or '', mesafe_val, stil_val), [])
        if not recs:
            return pb_cs, pb_cs
        overall_best = min(cs for _, cs in recs)
        if start_date or end_date:
            filtered_cs = [
                cs for ev_d, cs in recs
                if ev_d and (not start_date or ev_d >= start_date) and (not end_date or ev_d <= end_date)
            ]
            return (min(filtered_cs) if filtered_cs else None), overall_best
        if pb_cs is not None:
            return pb_cs, overall_best
        return overall_best, overall_best

    # 1. İlişkisel BarajKurali tablosundan (TYF Takvim & Reglamanları) oku
    from sonuclar.models import BarajKurali
    bk_qs = BarajKurali.objects.select_related('event', 'belge').order_by('-id')
    if target_havuz:
        bk_qs = bk_qs.filter(havuz=target_havuz)
    if target_gender == 'erkek':
        bk_qs = bk_qs.filter(cinsiyet='Erkek')
    elif target_gender == 'kadin':
        bk_qs = bk_qs.filter(cinsiyet='Kadın')
    if target_dist:
        bk_qs = bk_qs.filter(mesafe=target_dist)
    if target_stil:
        bk_qs = bk_qs.filter(stil=target_stil)
    if birth_year is not None:
        bk_qs = bk_qs.filter(Q(max_dogum_yili__isnull=True) | Q(max_dogum_yili__gte=birth_year))

    for bk in bk_qs:
        if birth_year is not None:
            dys = bk.dogum_yillari or []
            max_dy = bk.max_dogum_yili
            if not ((dys and birth_year in dys) or (max_dy is not None and birth_year <= max_dy)):
                continue
        dedup_key = (bk.belge_id, bk.baraj_adi, bk.baraj_turu, bk.havuz, bk.yas_etiketi, bk.mesafe, bk.stil, bk.sure_cs)
        if dedup_key in seen_rules:
            continue
        seen_rules.add(dedup_key)
        g_start = (bk.belge.baraj_gecerlilik_baslangic or '') if bk.belge else ''
        g_end = (bk.belge.baraj_gecerlilik_bitis or '') if bk.belge else ''
        g_text = (bk.belge.baraj_gecerlilik_metni or '') if bk.belge else ''
        meet_date = (
            (bk.belge.tarih_metni if bk.belge and bk.belge.tarih_metni else None)
            or (bk.event.yaris_tarihi_ham if bk.event and bk.event.yaris_tarihi_ham else '')
        )
        ev_city = (
            (bk.event.sehir if bk.event and bk.event.sehir else None)
            or (bk.belge.sehir_yer if bk.belge and bk.belge.sehir_yer else '')
        )
        ev_start = (
            (bk.event.yaris_tarihi_baslangic if bk.event and bk.event.yaris_tarihi_baslangic else None)
            or (bk.belge.baslangic_tarihi if bk.belge and bk.belge.baslangic_tarihi else '')
        )
        eff_pb_cs, overall_pb_cs = _best_pb_in_window(bk.havuz, bk.mesafe, bk.stil, g_start, g_end)
        diff_cs = (eff_pb_cs - bk.sure_cs) if eff_pb_cs is not None else None
        is_in_window = eff_pb_cs is not None
        meet_name = (bk.event.musabaka_adi if bk.event else None) or (bk.belge.baslik if bk.belge else None) or bk.baraj_adi
        pdf_url = ''
        if bk.belge:
            if bk.belge.yerel_dosya:
                try:
                    pdf_url = request.build_absolute_uri(bk.belge.yerel_dosya.url)
                except Exception:
                    pdf_url = bk.belge.yerel_dosya.url
            if not pdf_url:
                pdf_url = bk.belge.kaynak_url or ''
        targets.append({
            'belge_id': bk.belge_id,
            'event_id': bk.event_id,
            'meet_name': meet_name,
            'meet_date': meet_date,
            'city': ev_city,
            'start_date': ev_start,
            'baraj_adi': bk.baraj_adi,
            'baraj_turu': bk.baraj_turu,
            'age_label': bk.yas_etiketi or '',
            'havuz': bk.havuz or '',
            'mesafe': bk.mesafe,
            'stil': bk.stil,
            'target_time': bk.sure,
            'target_cs': bk.sure_cs,
            'pb_cs': eff_pb_cs,
            'overall_pb_cs': overall_pb_cs,
            'is_in_validity_window': is_in_window,
            'diff_cs': diff_cs,
            'passed': (diff_cs <= 0) if diff_cs is not None else None,
            'baraj_gecerlilik_metni': g_text,
            'baraj_gecerlilik_baslangic': g_start,
            'baraj_gecerlilik_bitis': g_end,
            'pdf_url': pdf_url,
        })

    # 2. CanliYaris JSON barajlarını birleştir
    for cy in CanliYaris.objects.exclude(barajlar__isnull=True).only('id', 'musabaka_adi', 'barajlar').order_by('-id'):
        bdata = cy.barajlar
        if not isinstance(bdata, dict) or not bdata.get('barajlar'):
            continue
        baraj_adi = bdata.get('baraj_adi') or cy.musabaka_adi or 'Reglaman Barajı'
        for rule in bdata.get('barajlar') or []:
            if target_havuz and rule.get('havuz') and rule.get('havuz') != target_havuz:
                continue
            if target_gender and _fold_tr(str(rule.get('cinsiyet') or '')) != target_gender:
                continue
            if target_dist and rule.get('mesafe') != target_dist:
                continue
            if target_stil and rule.get('stil') != target_stil:
                continue
            if birth_year is not None:
                dys = rule.get('dogum_yillari') or []
                max_dy = rule.get('max_dogum_yili')
                if not ((dys and birth_year in dys) or (max_dy is not None and birth_year <= max_dy)):
                    continue
            sure_sn = rule.get('sure_saniye')
            if not sure_sn:
                continue
            target_cs = int(round(float(sure_sn) * 100))
            dedup_key = (baraj_adi, rule.get('baraj_turu') or 'Katılım Barajı', rule.get('havuz'), rule.get('yas_etiketi'), target_cs)
            if dedup_key in seen_rules:
                continue
            seen_rules.add(dedup_key)
            diff_cs = (pb_cs - target_cs) if pb_cs is not None else None
            targets.append({
                'meet_name': cy.musabaka_adi or baraj_adi,
                'baraj_adi': baraj_adi,
                'baraj_turu': rule.get('baraj_turu') or 'Katılım Barajı',
                'age_label': rule.get('yas_etiketi') or '',
                'havuz': rule.get('havuz') or '',
                'target_time': rule.get('sure') or '',
                'target_cs': target_cs,
                'diff_cs': diff_cs,
                'passed': (diff_cs <= 0) if diff_cs is not None else None,
            })

    targets.sort(key=lambda t: (t.get('start_date') or '9999-99-99', t.get('meet_name') or ''))
    return api_response({'data': targets}, request=request, cache_seconds=60)

