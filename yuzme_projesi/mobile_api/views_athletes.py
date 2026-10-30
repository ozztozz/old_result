# -*- coding: utf-8 -*-
from collections import Counter
from django.views.decorators.http import require_GET
from django.core.paginator import Paginator
from django.utils import timezone
from sonuclar.models import Sporcu, YarisSonucu
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
def get_athlete_detail(request, athlete_id: int):
    """
    Sporcu profil kartı, 25m/50m Kişisel En İyi (PB) dereceleri ve kariyer özeti.
    """
    try:
        athlete = Sporcu.objects.select_related('birincil_kulup').get(pk=athlete_id)
    except Sporcu.DoesNotExist:
        return api_error('not_found', 'Sporcu bulunamadı', status=404)

    # Aktif kulüp ve okul
    active_club = athlete.aktif_kulup()
    active_club_data = {
        'id': active_club.id,
        'name': active_club.kulup_adi
    } if active_club else None

    school_name = athlete.okul()

    # Tüm geçerli dereceler
    all_results = list(
        athlete.yaris_sonuclari.select_related('event', 'kulup')
        .filter(derece_saniye__isnull=False, derece_saniye__gt=0)
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

    # Kariyer İstatistikleri
    total_races = athlete.yaris_sonuclari.count()
    podium_results = [r for r in all_results if str(r.sira or '').strip() in ('1', '2', '3')]
    podium_count = len(podium_results)
    podium_rate = round((podium_count / total_races) * 100, 1) if total_races > 0 else 0

    standards_count = athlete.yaris_sonuclari.exclude(
        baraj__isnull=True
    ).exclude(baraj='').exclude(baraj='-').exclude(baraj__iexact='HAYIR').count()

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
def get_athlete_races(request, athlete_id: int):
    """Sporcunun kronolojik tüm yarış geçmişi (Filtreli ve sayfalı)."""
    try:
        athlete = Sporcu.objects.get(pk=athlete_id)
    except Sporcu.DoesNotExist:
        return api_error('not_found', 'Sporcu bulunamadı', status=404)

    qs = athlete.yaris_sonuclari.select_related('event', 'kulup').order_by(
        '-event__yaris_tarihi_baslangic', '-id'
    )

    stroke = (request.GET.get('stroke') or '').strip().lower()
    if stroke:
        rev_stroke_map = {
            'free': ['SERBEST'],
            'back': ['SIRTUSTU', 'SIRTÜSTÜ'],
            'breast': ['KURBAGALAMA', 'KURBAĞALAMA'],
            'fly': ['KELEBEK'],
            'medley': ['KARISIK', 'KARIŞIK'],
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

    athletes = Sporcu.objects.filter(id__in=id_list).select_related('birincil_kulup')
    summary_data = []

    for a in athletes:
        latest_race = a.yaris_sonuclari.select_related('event').order_by(
            '-event__yaris_tarihi_baslangic', '-id'
        ).first()

        best_race = a.yaris_sonuclari.filter(
            puan__gt=0
        ).order_by('-puan').first()

        summary_data.append({
            'id': a.id,
            'name': a.sporcu_adi,
            'birth_year': a.dogum_yili,
            'club_name': a.birincil_kulup.kulup_adi if a.birincil_kulup else 'Ferdi',
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
