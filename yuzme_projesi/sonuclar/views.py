# -*- coding: utf-8 -*-
import json
import difflib
import re
import threading
from collections import defaultdict, Counter
from django.shortcuts import render, get_object_or_404, redirect
from django.contrib import messages
from django.utils import timezone
from django.core.paginator import Paginator
from django.core.cache import cache
from django.db import transaction
from django.db.models import Q, Count, Sum, Avg, Max, Case, When, Value, IntegerField, FloatField, BooleanField, CharField, F
from django.db.models.functions import Cast, Concat
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from .models import Kulup, Sporcu, SporcuKulupTarihce, YarisSonucu, CanliYaris, Event, CanliYarisDosya, is_school_team
from .athlete_matcher import match_athlete
from .turkish_names import standardize_turkish_athlete_name, tr_fold


def is_school_meet(meet_name: str) -> bool:
    """Yarış/müsabaka adının Okul Sporları müsabakası olup olmadığını belirler."""
    if not meet_name:
        return False
    ml = meet_name.lower()
    return bool(re.search(r'(?:okul\s*spor|okulspor|okullar|meb)', ml))


def _time_to_seconds(time_str):
    if not time_str:
        return None
    s = str(time_str).strip()
    try:
        if ':' in s:
            parts = s.split(':')
            if len(parts) == 2:
                return round(float(parts[0]) * 60 + float(parts[1]), 2)
            elif len(parts) == 3:
                return round(float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2]), 2)
        return round(float(s), 2)
    except Exception:
        return None


def index(request):
    """Ana sayfa - Özet istatistikler ve popüler içerikler (RAM Önbellekli - Zero CPU)."""
    cache_key = 'homepage_stats_context'
    context = cache.get(cache_key)
    if context is None:
        context = {
            'toplam_sporcu': Sporcu.objects.count(),
            'toplam_kulup': Kulup.objects.count(),
            'toplam_yaris': YarisSonucu.objects.count(),
            'toplam_transfer': SporcuKulupTarihce.objects.count(),
            'en_cok_yarisan_sporcular': list(Sporcu.objects.select_related('birincil_kulup').order_by('-toplam_yaris_sayisi')[:8]),
            'en_buyuk_kulupler': list(Kulup.objects.order_by('-toplam_sporcu_sayisi')[:8]),
            'son_yarismalar': list(Event.objects.order_by('-yaris_tarihi_baslangic')[:6]),
        }
        cache.set(cache_key, context, 900)  # 15 dakika boyunca RAM'de sakla

    return render(request, 'sonuclar/index.html', context)


def sporcu_listesi(request):
    """Sporcuların listesi, araması ve filtrelemesi (İsteğe bağlı arama - On-demand)."""
    q = request.GET.get('q', '').strip()
    cinsiyet = request.GET.get('cinsiyet', '').strip()
    kulup_adi = request.GET.get('kulup', '').strip()
    sirala = request.GET.get('sirala', 'isim')

    has_query = bool(q or cinsiyet or kulup_adi)

    if not has_query:
        page_obj = None
        total_count = 0
    else:
        qs = Sporcu.objects.select_related('birincil_kulup')

        if q:
            qs = qs.filter(sporcu_adi__icontains=q)
        if cinsiyet in ('ERKEK', 'KADIN'):
            qs = qs.filter(cinsiyet=cinsiyet)
        if kulup_adi:
            qs = qs.filter(birincil_kulup__kulup_adi__icontains=kulup_adi)

        # Sıralama
        if sirala == 'yaris':
            qs = qs.order_by('-toplam_yaris_sayisi')
        elif sirala == 'tarih':
            qs = qs.order_by('-son_yaris_tarihi')
        else:
            qs = qs.order_by('sporcu_adi')

        paginator = Paginator(qs, 30)
        page_number = request.GET.get('page')
        page_obj = paginator.get_page(page_number)
        total_count = paginator.count

    context = {
        'page_obj': page_obj,
        'has_query': has_query,
        'q': q,
        'cinsiyet': cinsiyet,
        'kulup_adi': kulup_adi,
        'sirala': sirala,
        'total_count': total_count,
    }
    if request.headers.get('HX-Request'):
        return render(request, 'sonuclar/partials/sporcu_table_partial.html', context)
    return render(request, 'sonuclar/sporcu_listesi.html', context)


def sporcu_detay(request, pk):
    """Sporcu detay sayfası: Profil, Kulüp Tarihçesi, En İyi Dereceler (PB) ve Kategori/Mesafe filtreli Yarış Sonuçları."""
    sporcu = get_object_or_404(Sporcu.objects.select_related('birincil_kulup'), pk=pk)

    # Kulüp Transfer Tarihçesi (Tarihe göre: Aktif ve en yeni kulüp en üstte)
    tarihce = sporcu.kulup_tarihcesi.select_related('kulup').order_by('-aktif_kulup_mu', '-son_yaris_tarihi', '-ilk_yaris_tarihi')

    # Kişisel En İyi Dereceler (PB)
    pbs = sporcu.en_iyi_dereceler()

    # Kategori (Stil) ve Mesafe Filtreleri
    kategori = (request.GET.get('kategori') or request.GET.get('stil') or '').strip()
    mesafe_raw = request.GET.get('mesafe', '').strip()
    sirala = request.GET.get('sirala', 'tarih_desc')

    sonuclar_qs = sporcu.yaris_sonuclari.select_related('kulup', 'event')

    if kategori:
        sonuclar_qs = sonuclar_qs.filter(stil__icontains=kategori)

    mesafe_val = None
    if mesafe_raw:
        try:
            mesafe_val = int(mesafe_raw)
            sonuclar_qs = sonuclar_qs.filter(mesafe=mesafe_val)
        except ValueError:
            pass

    if sirala == 'derece':
        sonuclar_qs = sonuclar_qs.order_by('derece_saniye', '-event__yaris_tarihi_baslangic')
    elif sirala == 'tarih_asc':
        sonuclar_qs = sonuclar_qs.order_by('event__yaris_tarihi_baslangic', 'id')
    else:
        sonuclar_qs = sonuclar_qs.order_by('-event__yaris_tarihi_baslangic', '-id')

    total_filtered_races = sonuclar_qs.count()
    paginator = Paginator(sonuclar_qs, 30)
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)

    mevcut_stiller = ['Serbest', 'Sırtüstü', 'Kurbağalama', 'Kelebek', 'Karışık']
    mevcut_mesafeler = [50, 100, 200, 400, 800, 1500]

    son_yaris = sporcu.yaris_sonuclari.select_related('event', 'kulup').order_by('-event__yaris_tarihi_baslangic', '-id').first()

    # --- SPORCU DEĞERLENDİRME & BAŞARI METRİKLERİ ---
    tum_yarislar = list(sporcu.yaris_sonuclari.select_related('event', 'kulup').all())
    toplam_yaris = len(tum_yarislar)

    # 1. FINA Puanı ve Zirve Performans (Peak FINA)
    puanli_sonuclar = [r for r in tum_yarislar if r.puan and r.puan > 0]
    toplam_puan = sum(r.puan for r in puanli_sonuclar)
    ort_puan = round(toplam_puan / len(puanli_sonuclar), 1) if puanli_sonuclar else 0
    best_race = max(puanli_sonuclar, key=lambda r: r.puan, default=None)

    # 2. Kürsü, Madalya ve Baraj İstatistikleri
    altin_sayisi = sum(1 for r in tum_yarislar if str(r.sira).strip() == '1')
    gumus_sayisi = sum(1 for r in tum_yarislar if str(r.sira).strip() == '2')
    bronz_sayisi = sum(1 for r in tum_yarislar if str(r.sira).strip() == '3')
    toplam_kursu = altin_sayisi + gumus_sayisi + bronz_sayisi
    kursu_orani = round((toplam_kursu / toplam_yaris) * 100, 1) if toplam_yaris > 0 else 0
    baraj_sayisi = sum(1 for r in tum_yarislar if r.baraj and str(r.baraj).strip().upper() not in ('HAYIR', 'GEÇMEDİ', 'GECMEDI', 'YOK', '-'))

    # 3. Giriş Derecesi vs Çıkış Derecesi (Seed vs Finish Zaman Gelişimi)
    gelistiren_count = 0
    gerileyen_count = 0
    toplam_fark = 0.0
    en_buyuk_gelisim = None

    for r in tum_yarislar:
        g_raw = (r.giris_derecesi or '').strip()
        if g_raw and g_raw.upper() not in ('NT', 'NT.', 'DERECE YOK', '-') and r.derece_saniye and r.derece_saniye > 0:
            g_sn = _time_to_seconds(g_raw)
            if g_sn and g_sn > 0:
                fark = round(r.derece_saniye - g_sn, 2)
                toplam_fark += fark
                if fark < 0:
                    gelistiren_count += 1
                    if en_buyuk_gelisim is None or fark < en_buyuk_gelisim['fark']:
                        en_buyuk_gelisim = {
                            'fark': fark,
                            'fark_sn': abs(fark),
                            'brans': f"{r.mesafe}m {r.stil}",
                            'derece': r.derece,
                            'giris': r.giris_derecesi,
                            'musabaka': r.event.musabaka_adi if r.event else (r.dosya_adi or '')
                        }
                elif fark > 0:
                    gerileyen_count += 1

    karsilastirilan = gelistiren_count + gerileyen_count
    has_giris_analizi = karsilastirilan > 0
    gelisim_orani = round((gelistiren_count / karsilastirilan) * 100, 1) if karsilastirilan > 0 else 0
    ort_fark = round(toplam_fark / karsilastirilan, 2) if karsilastirilan > 0 else 0

    # 4. Branş & Stil Dağılımı ve Uzmanlık Alanı
    stil_stats = defaultdict(lambda: {'count': 0, 'fina_total': 0, 'fina_count': 0, 'best_fina': 0, 'best_race': None})
    musabaka_set = set()
    aktif_yillar = set()

    for r in tum_yarislar:
        stil = (r.stil or 'Diğer').strip()
        stil_stats[stil]['count'] += 1
        if r.puan and r.puan > 0:
            stil_stats[stil]['fina_total'] += r.puan
            stil_stats[stil]['fina_count'] += 1
            if r.puan > stil_stats[stil]['best_fina']:
                stil_stats[stil]['best_fina'] = r.puan
                stil_stats[stil]['best_race'] = r

        if r.event_id:
            musabaka_set.add(r.event_id)
        elif r.dosya_adi:
            musabaka_set.add(r.dosya_adi)

        tarih_val = (r.event.yaris_tarihi_baslangic if r.event else None) or r.dosya_adi
        if tarih_val and len(str(tarih_val)) >= 4:
            yil_c = str(tarih_val)[:4]
            if yil_c.isdigit():
                aktif_yillar.add(int(yil_c))

    style_color_map = {
        'serbest': {'accent': 'emerald', 'bg': 'bg-emerald-500/10', 'border': 'border-emerald-500/30', 'text': 'text-emerald-600 dark:text-emerald-400', 'bar': 'bg-emerald-500', 'icon': 'bi-lightning-charge-fill'},
        'sırtüstü': {'accent': 'sky', 'bg': 'bg-sky-500/10', 'border': 'border-sky-500/30', 'text': 'text-sky-600 dark:text-sky-400', 'bar': 'bg-sky-500', 'icon': 'bi-water'},
        'sirtustu': {'accent': 'sky', 'bg': 'bg-sky-500/10', 'border': 'border-sky-500/30', 'text': 'text-sky-600 dark:text-sky-400', 'bar': 'bg-sky-500', 'icon': 'bi-water'},
        'kurbağalama': {'accent': 'rose', 'bg': 'bg-rose-500/10', 'border': 'border-rose-500/30', 'text': 'text-rose-600 dark:text-rose-400', 'bar': 'bg-rose-500', 'icon': 'bi-shield-check'},
        'kurbagalama': {'accent': 'rose', 'bg': 'bg-rose-500/10', 'border': 'border-rose-500/30', 'text': 'text-rose-600 dark:text-rose-400', 'bar': 'bg-rose-500', 'icon': 'bi-shield-check'},
        'kelebek': {'accent': 'amber', 'bg': 'bg-amber-500/10', 'border': 'border-amber-500/30', 'text': 'text-amber-600 dark:text-amber-400', 'bar': 'bg-amber-500', 'icon': 'bi-fire'},
        'karışık': {'accent': 'indigo', 'bg': 'bg-indigo-500/10', 'border': 'border-indigo-500/30', 'text': 'text-indigo-600 dark:text-indigo-400', 'bar': 'bg-indigo-500', 'icon': 'bi-stars'},
        'karisik': {'accent': 'indigo', 'bg': 'bg-indigo-500/10', 'border': 'border-indigo-500/30', 'text': 'text-indigo-600 dark:text-indigo-400', 'bar': 'bg-indigo-500', 'icon': 'bi-stars'},
    }

    stil_list = []
    for stil_adi, st in stil_stats.items():
        st_ort = round(st['fina_total'] / st['fina_count'], 1) if st['fina_count'] > 0 else 0
        st_key = (stil_adi or '').strip().lower()
        st_meta = style_color_map.get(st_key, {'accent': 'slate', 'bg': 'bg-slate-500/10', 'border': 'border-slate-500/30', 'text': 'text-slate-600 dark:text-slate-400', 'bar': 'bg-slate-500', 'icon': 'bi-activity'})
        item = {
            'stil': stil_adi,
            'count': st['count'],
            'yuzde': round((st['count'] / toplam_yaris) * 100, 1) if toplam_yaris > 0 else 0,
            'ort_puan': st_ort,
            'best_fina': st['best_fina'],
            'best_race': st['best_race']
        }
        item.update(st_meta)
        stil_list.append(item)

    stil_list.sort(key=lambda x: x['count'], reverse=True)

    en_cok_yuzulen_stil = stil_list[0]['stil'] if stil_list else '-'

    # YAŞ VE CİNSİYET DİKKATE ALINARAK UZMANLIK BELİRLEME
    # TYF ve uluslararası yaş grupları elit/hedef FINA referans skalası
    AGE_BENCHMARKS = {
        'ERKEK': {10: 280, 11: 340, 12: 420, 13: 490, 14: 550, 15: 600, 16: 640, 17: 670, 18: 700, 19: 720},
        'KADIN': {10: 300, 11: 360, 12: 440, 13: 500, 14: 540, 15: 580, 16: 620, 17: 650, 18: 680, 19: 700}
    }
    gender_key = (sporcu.cinsiyet or 'ERKEK').upper()
    gender_benchmarks = AGE_BENCHMARKS.get(gender_key, AGE_BENCHMARKS['ERKEK'])

    # Sporcunun yarıştığı yaşlar ve son 2 aktif yaş dönemi (güncel uzmanlık dönemi)
    yaristigi_yaslar = sorted(set(r.hesaplanan_yas for r in tum_yarislar if r.hesaplanan_yas))
    guncel_yas_donemi = set(yaristigi_yaslar[-2:]) if len(yaristigi_yaslar) >= 2 else (set(yaristigi_yaslar) if yaristigi_yaslar else set())

    # Her stil için yaş & cinsiyet ağırlıklı skorlama
    stil_skorlari = {}
    for st_item in stil_list:
        stil_adi = st_item['stil']
        st_races = [r for r in tum_yarislar if (r.stil or '').strip() == stil_adi]
        if not st_races:
            continue

        # 1. Güncel / Olgunluk Dönemi Ortalaması (Küçük yaşlardaki çocukluk puanlarının günceli yanıltmaması için)
        recent_races = [r for r in st_races if r.hesaplanan_yas in guncel_yas_donemi] if guncel_yas_donemi else st_races
        recent_pts = [r.puan for r in recent_races if r.puan and r.puan > 0]
        recent_ort = (sum(recent_pts) / len(recent_pts)) if recent_pts else st_item['ort_puan']

        # 2. Yaş ve Cinsiyete Göre Nispi Verimlilik (O yaştaki FINA / Yaş Grubu Hedefi)
        verim_list = []
        for r in st_races:
            if r.puan and r.puan > 0:
                target_bench = gender_benchmarks.get(r.hesaplanan_yas, 500) if r.hesaplanan_yas else 500
                verim_list.append((r.puan / target_bench) * 100)
        yas_cinsiyet_verim = (sum(verim_list) / len(verim_list)) if verim_list else 100.0

        # 3. Kendi Yaş/Cinsiyet Grubunda Kürsü & Baraj Başarısı
        medals = sum(1 for r in st_races if str(r.sira).strip() in ('1', '2', '3'))
        barajlar = sum(1 for r in st_races if r.baraj and str(r.baraj).upper() not in ('HAYIR', 'GEÇMEDİ', 'GECMEDI', 'YOK', '-'))
        medal_rate = (medals / len(st_races)) * 100
        baraj_rate = (barajlar / len(st_races)) * 100

        # Birleşik Uzmanlık Skoru:
        # %40 Güncel Yaş Dönemi FINA'sı
        # %30 Yaş & Cinsiyet Hedefine Göre Nispi Verimlilik
        # %20 Yaş Grubundaki Kürsü & Baraj Oranı
        # %10 Yarış Deneyimi Hacmi
        score = (
            (recent_ort * 0.40) +
            (yas_cinsiyet_verim * 3.0) +
            ((medal_rate * 0.6 + baraj_rate * 0.4) * 1.5) +
            (min(len(st_races), 50) * 1.0)
        )
        stil_skorlari[stil_adi] = score

    if stil_skorlari:
        valid_stiller = [st for st in stil_skorlari if len([r for r in tum_yarislar if (r.stil or '').strip() == st]) >= 2]
        if valid_stiller:
            en_guclu_stil = max(valid_stiller, key=lambda s: stil_skorlari[s])
        else:
            en_guclu_stil = max(stil_skorlari, key=lambda s: stil_skorlari[s])
    else:
        en_guclu_stil = en_cok_yuzulen_stil
    aktif_yil_sayisi = (max(aktif_yillar) - min(aktif_yillar) + 1) if len(aktif_yillar) >= 2 else (1 if aktif_yillar else 0)

    # Sporcu Baş Harfleri (Avatar / Monogram)
    names = (sporcu.sporcu_adi or '').strip().split()
    initials = (names[0][0] + (names[-1][0] if len(names) > 1 else '')).upper() if names else 'S'
    guncel_yas = (timezone.now().year - sporcu.dogum_yili) if sporcu.dogum_yili else None

    # Kişiselleştirilmiş Atletizm & Performans Notu (Scout Summary)
    stil_counter = Counter(r.stil for r in tum_yarislar if r.stil)
    top_stiller = [st for st, _ in stil_counter.most_common(2)]
    top_stiller_str = " ve ".join(top_stiller) if top_stiller else "çeşitli"

    not_parts = []
    if top_stiller:
        not_parts.append(f"Ağırlıklı olarak {top_stiller_str} branşlarında yarışan {sporcu.sporcu_adi}, toplam {toplam_yaris} resmi yarışta havuza girdi.")
    else:
        not_parts.append(f"Kariyerinde toplam {toplam_yaris} resmi yarışta mücadele eden {sporcu.sporcu_adi},")

    if toplam_kursu > 0:
        not_parts.append(f"{toplam_kursu} kez kürsüye çıkarak (%{kursu_orani} podyum) istikrarlı bir madalya başarısı yakaladı.")
    
    if baraj_sayisi > 0:
        not_parts.append(f"Kariyerinde {baraj_sayisi} yarışta baraj derecesini geçmeyi başardı.")

    if best_race and best_race.puan:
        not_parts.append(f"Zirve performansını {best_race.mesafe}m {best_race.stil} branşında {best_race.derece} ({best_race.puan} FINA) ile kaydetti.")

    sporcu_notu = " ".join(not_parts) if not_parts else "Kayıtlı yarış verileri üzerinden gelişim grafiği takip edilmektedir."

    degerlendirme = {
        'initials': initials,
        'guncel_yas': guncel_yas,
        'sporcu_notu': sporcu_notu,
        'toplam_yaris': toplam_yaris,
        'toplam_puan': toplam_puan,
        'ort_puan': ort_puan,
        'best_race': best_race,
        'altin_sayisi': altin_sayisi,
        'gumus_sayisi': gumus_sayisi,
        'bronz_sayisi': bronz_sayisi,
        'toplam_kursu': toplam_kursu,
        'kursu_orani': kursu_orani,
        'baraj_sayisi': baraj_sayisi,
        'has_giris_analizi': has_giris_analizi,
        'karsilastirilan': karsilastirilan,
        'gelistiren_count': gelistiren_count,
        'gerileyen_count': gerileyen_count,
        'gelisim_orani': gelisim_orani,
        'ort_fark': ort_fark,
        'en_buyuk_gelisim': en_buyuk_gelisim,
        'stil_list': stil_list,
        'en_cok_yuzulen_stil': en_cok_yuzulen_stil,
        'en_guclu_stil': en_guclu_stil,
        'toplam_musabaka': len(musabaka_set),
        'aktif_yil_sayisi': aktif_yil_sayisi,
    }

    context = {
        'sporcu': sporcu,
        'son_yaris': son_yaris,
        'tarihce': tarihce,
        'pbs': pbs,
        'page_obj': page_obj,
        'total_races': total_filtered_races,
        'total_all_races': sporcu.toplam_yaris_sayisi,
        'secilen_kategori': kategori,
        'secilen_mesafe': mesafe_val,
        'secilen_sirala': sirala,
        'mevcut_stiller': mevcut_stiller,
        'mevcut_mesafeler': mevcut_mesafeler,
        'degerlendirme': degerlendirme,
    }
    return render(request, 'sonuclar/sporcu_detay.html', context)


def kulup_listesi(request):
    """Kulüpler listesi ve arama (İsteğe bağlı arama - On-demand)."""
    q = request.GET.get('q', '').strip()
    sirala = request.GET.get('sirala', 'yaris')

    has_query = bool(q)

    if not has_query:
        page_obj = None
        total_count = 0
    else:
        qs = Kulup.objects.all()
        if q:
            qs = qs.filter(kulup_adi__icontains=q)

        if sirala == 'sporcu':
            qs = qs.order_by('-toplam_sporcu_sayisi')
        elif sirala == 'isim':
            qs = qs.order_by('kulup_adi')
        else:
            qs = qs.order_by('-toplam_yaris_sayisi')

        paginator = Paginator(qs, 30)
        page_number = request.GET.get('page')
        page_obj = paginator.get_page(page_number)
        total_count = paginator.count

    context = {
        'page_obj': page_obj,
        'has_query': has_query,
        'q': q,
        'sirala': sirala,
        'total_count': total_count,
    }
    if request.headers.get('HX-Request'):
        return render(request, 'sonuclar/partials/kulup_table_partial.html', context)
    return render(request, 'sonuclar/kulup_listesi.html', context)


def kulup_detay(request, pk):
    """Kulüp detay sayfası: Kulüp profili, Sporcuları ve Son Yarış Sonuçları."""
    kulup = get_object_or_404(Kulup, pk=pk)

    # Bu kulüpte yarışmış sporcular (Aktif olanlar ve tümü)
    tarihce_qs = SporcuKulupTarihce.objects.filter(kulup=kulup).select_related('sporcu').order_by('-aktif_kulup_mu', '-toplam_yaris_sayisi')
    
    paginator = Paginator(tarihce_qs, 40)
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)

    # Kulübün son yarış sonuçları
    son_sonuclar = kulup.yaris_sonuclari.select_related('sporcu', 'event').order_by('-event__yaris_tarihi_baslangic')[:25]

    context = {
        'kulup': kulup,
        'page_obj': page_obj,
        'son_sonuclar': son_sonuclar,
        'total_swimmers': paginator.count,
    }
    return render(request, 'sonuclar/kulup_detay.html', context)


def yaris_sonuclari_ara(request):
    """Detaylı yarış sonuçları sorgulama ve filtreleme motoru (İsteğe bağlı arama - On-demand)."""
    q_sporcu = request.GET.get('sporcu', '').strip()
    q_kulup = request.GET.get('kulup', '').strip()
    q_musabaka = request.GET.get('musabaka', '').strip()
    stil = request.GET.get('stil', '').strip()
    mesafe = request.GET.get('mesafe', '').strip()
    cinsiyet = request.GET.get('cinsiyet', '').strip()
    yil = request.GET.get('yil', '').strip()

    has_filter = bool(q_sporcu or q_kulup or q_musabaka or stil or mesafe or cinsiyet or yil)

    if not has_filter:
        page_obj = None
        total_count = 0
    else:
        qs = YarisSonucu.objects.select_related('sporcu', 'kulup', 'event')

        if q_sporcu:
            qs = qs.filter(sporcu__sporcu_adi__icontains=q_sporcu)
        if q_kulup:
            qs = qs.filter(kulup__kulup_adi__icontains=q_kulup)
        if q_musabaka:
            qs = qs.filter(event__musabaka_adi__icontains=q_musabaka)
        if stil:
            qs = qs.filter(stil=stil)
        if mesafe and mesafe.isdigit():
            qs = qs.filter(mesafe=int(mesafe))
        if cinsiyet:
            qs = qs.filter(cinsiyet=cinsiyet)
        if yil and yil.isdigit():
            qs = qs.filter(event__yaris_tarihi_baslangic__startswith=yil)

        paginator = Paginator(qs, 30)
        page_number = request.GET.get('page')
        page_obj = paginator.get_page(page_number)
        total_count = paginator.count

    # Filtre seçenekleri
    stiller = ['Serbest', 'Sırtüstü', 'Kurbağalama', 'Kelebek', 'Karışık']
    mesafeler = [50, 100, 200, 400, 800, 1500]

    context = {
        'page_obj': page_obj,
        'has_filter': has_filter,
        'q_sporcu': q_sporcu,
        'q_kulup': q_kulup,
        'q_musabaka': q_musabaka,
        'stil': stil,
        'mesafe': mesafe,
        'cinsiyet': cinsiyet,
        'yil': yil,
        'stiller': stiller,
        'mesafeler': mesafeler,
        'total_count': total_count,
    }
    if request.headers.get('HX-Request'):
        return render(request, 'sonuclar/partials/yaris_sonuclari_table_partial.html', context)
    return render(request, 'sonuclar/yaris_sonuclari.html', context)


def api_sporcu_ara(request):
    """Canlı arama (autocomplete) için JSON endpoint (Cache + .only() optimize edilmiş)."""
    q = request.GET.get('term', '').strip() or request.GET.get('q', '').strip()
    if not q or len(q) < 2:
        return JsonResponse([], safe=False)

    cache_key = f'autocomplete_{q.lower()}'
    cached_res = cache.get(cache_key)
    if cached_res is not None:
        return JsonResponse(cached_res, safe=False)

    results = []
    sporcular = (
        Sporcu.objects.filter(sporcu_adi__icontains=q)
        .select_related('birincil_kulup')
        .only('id', 'sporcu_adi', 'yas_dogum_yili', 'birincil_kulup__kulup_adi')[:10]
    )
    for sp in sporcular:
        kulup_adi = sp.birincil_kulup.kulup_adi if sp.birincil_kulup else "Kulüpsüz"
        results.append({
            'id': sp.id,
            'label': f"{sp.sporcu_adi} ({sp.yas_dogum_yili} Yaş) - {kulup_adi}",
            'value': sp.sporcu_adi,
            'url': f"/sporcular/{sp.id}/"
        })
    cache.set(cache_key, results, 300)  # 5 dakika önbellek
    return JsonResponse(results, safe=False)


from django.views.decorators.csrf import csrf_exempt
import json
import difflib
import re

def _time_to_seconds(time_str):
    if not time_str:
        return None
    s = str(time_str).strip()
    try:
        if ':' in s:
            parts = s.split(':')
            if len(parts) == 2:
                return round(float(parts[0]) * 60 + float(parts[1]), 2)
            elif len(parts) == 3:
                return round(float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2]), 2)
        return round(float(s), 2)
    except Exception:
        return None


def _process_single_race_payload(payload: dict) -> dict:
    """Tek bir yarışın (start listesi veya sonuç listesi) kayıtlarını veritabanına aktarır."""
    tur = payload.get('tur', 'sonuc_listesi')  # 'start_listesi' veya 'sonuc_listesi'
    musabaka_adi = (payload.get('musabaka_adi') or '').strip()
    sehir = (payload.get('sehir') or '').strip()
    yaris_tarihi = (payload.get('yaris_tarihi') or payload.get('tarih') or '').strip()
    yaris_tarihi_baslangic = (payload.get('yaris_tarihi_baslangic') or yaris_tarihi).strip()
    yaris_no = str(payload.get('yaris_no') or '').strip()
    cinsiyet = (payload.get('cinsiyet') or '').strip()
    mesafe = payload.get('mesafe')
    if mesafe:
        try:
            mesafe = int(mesafe)
        except Exception:
            pass
    stil = (payload.get('stil') or '').strip()
    yas_grubu = (payload.get('yas_grubu') or '').strip()
    dosya_adi = (payload.get('dosya_adi') or '').strip()
    kayitlar = payload.get('kayitlar', [])
    is_okul_musabakasi = bool(payload.get('okul_musabakasi')) or is_school_meet(musabaka_adi)

    stats = {
        'eklenen_sonuc': 0,
        'guncellenen_sonuc': 0,
        'mukerrer_atlanilan': 0,
        'eslesen_sporcu': 0,
        'yeni_sporcu': 0,
        'yeni_kulup': 0
    }

    # Müsabakayı Event tablosunda bul veya oluştur
    canli_yaris_id = payload.get('canli_yaris_id')
    canli_yaris_obj = None
    if canli_yaris_id and str(canli_yaris_id).isdigit():
        canli_yaris_obj = CanliYaris.objects.filter(id=int(canli_yaris_id)).first()

    event = None
    if canli_yaris_obj and canli_yaris_obj.event:
        event = canli_yaris_obj.event
    elif musabaka_adi:
        event, _ = Event.objects.get_or_create(
            musabaka_adi=musabaka_adi,
            yaris_tarihi_baslangic=yaris_tarihi_baslangic or '',
            defaults={
                'sehir': sehir,
                'yaris_tarihi_ham': yaris_tarihi,
                'yaris_tarihi_bitis': payload.get('yaris_tarihi_bitis') or '',
                'kaynak_turu': "CANLI_SONUC" if tur == 'sonuc_listesi' else "CANLI_START_LISTESI"
            }
        )
        if canli_yaris_obj and not canli_yaris_obj.event:
            canli_yaris_obj.event = event
            canli_yaris_obj.save(update_fields=['event'])

    # Canlı yarış ve Event üzerinde eksik şehir/tarih bilgilerini senkronize et
    if canli_yaris_obj:
        dirty_canli = []
        if sehir and not canli_yaris_obj.sehir:
            canli_yaris_obj.sehir = sehir
            dirty_canli.append('sehir')
        if (yaris_tarihi or yaris_tarihi_baslangic) and not canli_yaris_obj.tarih:
            canli_yaris_obj.tarih = yaris_tarihi_baslangic or yaris_tarihi
            dirty_canli.append('tarih')
        if musabaka_adi and not canli_yaris_obj.musabaka_adi:
            canli_yaris_obj.musabaka_adi = musabaka_adi
            dirty_canli.append('musabaka_adi')
        if dirty_canli:
            canli_yaris_obj.save(update_fields=dirty_canli)

    if event:
        dirty_event = []
        if sehir and not event.sehir:
            event.sehir = sehir
            dirty_event.append('sehir')
        if yaris_tarihi_baslangic and not event.yaris_tarihi_baslangic:
            event.yaris_tarihi_baslangic = yaris_tarihi_baslangic
            event.yaris_tarihi_ham = yaris_tarihi
            dirty_event.extend(['yaris_tarihi_baslangic', 'yaris_tarihi_ham'])
        if dirty_event:
            event.save(update_fields=dirty_event)

    # Canlı Yarış Dosya Takip kaydı (ETag, Last-Modified, SHA-256 Hash)
    dosya_obj = None
    if dosya_adi and event:
        dosya_turu = "SONUC_LISTESI" if tur == 'sonuc_listesi' else "START_LISTESI"
        dosya_obj, _ = CanliYarisDosya.objects.get_or_create(
            event=event,
            dosya_adi=dosya_adi,
            defaults={
                'canli_yaris': canli_yaris_obj,
                'dosya_url': payload.get('dosya_url') or payload.get('pdf_url'),
                'dosya_turu': dosya_turu,
                'yaris_no': yaris_no,
                'mesafe': mesafe,
                'stil': stil,
                'cinsiyet': cinsiyet,
                'yas_grubu': yas_grubu,
                'etag': payload.get('etag'),
                'last_modified': payload.get('last_modified'),
                'content_hash': payload.get('content_hash'),
                'dosya_boyutu': payload.get('dosya_boyutu'),
                'durum': 'ISLENDI',
                'son_kontrol_tarihi': timezone.now(),
                'son_islem_tarihi': timezone.now()
            }
        )
        if not _:
            if payload.get('etag'): dosya_obj.etag = payload.get('etag')
            if payload.get('last_modified'): dosya_obj.last_modified = payload.get('last_modified')
            if payload.get('content_hash'): dosya_obj.content_hash = payload.get('content_hash')
            if payload.get('dosya_boyutu'): dosya_obj.dosya_boyutu = payload.get('dosya_boyutu')
            dosya_obj.durum = 'ISLENDI'
            dosya_obj.son_islem_tarihi = timezone.now()
            dosya_obj.son_kontrol_tarihi = timezone.now()
            dosya_obj.save()

    # Bu müsabaka ve branş için var olan yarışları önbelleğe al
    existing_races_map = {}
    if musabaka_adi and mesafe and stil:
        q_init = YarisSonucu.objects.filter(mesafe=mesafe, stil=stil)
        if event:
            q_init = q_init.filter(event=event)
        else:
            q_init = q_init.filter(event__musabaka_adi=musabaka_adi)
        if yaris_no:
            q_init = q_init.filter(yaris_no=yaris_no)
        for r in q_init.select_related('sporcu', 'kulup'):
            existing_races_map[r.sporcu_id] = r

    tum_kayitlar = list(kayitlar)
    for y_item in payload.get('yeni_sporcular', []):
        tum_kayitlar.append(y_item)

    # 1. Kulüpleri toplu çek ve önbelleğe al (N+1 SQL sorgularını önler)
    unique_clubs = set()
    unique_names = set()
    for it in tum_kayitlar:
        c_name = (it.get('kulup') or it.get('club') or it.get('kulup_adi') or 'Ferdi').strip()
        if c_name:
            unique_clubs.add(c_name)
        s_name = (it.get('sporcu') or it.get('name') or it.get('sporcu_adi') or '').strip()
        if s_name:
            unique_names.add(s_name)
            s_std = standardize_turkish_athlete_name(s_name)
            if s_std:
                unique_names.add(s_std)

    club_cache = {}
    for k in Kulup.objects.filter(kulup_adi__in=unique_clubs):
        club_cache[k.kulup_adi.lower()] = k

    for c_name in unique_clubs:
        c_low = c_name.lower()
        if c_low not in club_cache:
            k_obj, k_created = Kulup.objects.get_or_create(kulup_adi=c_name)
            if k_created:
                stats['yeni_kulup'] += 1
                if c_low != 'ferdi':
                    if is_okul_musabakasi or is_school_meet(musabaka_adi) or is_school_team(c_name):
                        k_obj.okul_mu = 1
                        k_obj.save(update_fields=['okul_mu'])
            club_cache[c_low] = k_obj

    # 2. Sporcuları tek SQL sorgusuyla önbelleğe al (1000x hızlı eşleştirme)
    # Sporcuların %95'i tam isim eşleşmesiyle 0.001 ms'de bulunur, ağır LIKE sorguları engellenir
    sporcu_exact_cache = {}
    for sp in Sporcu.objects.filter(sporcu_adi__in=unique_names).select_related('birincil_kulup'):
        sporcu_exact_cache.setdefault(tr_fold(sp.sporcu_adi), []).append(sp)

    races_to_create = []
    races_to_update = []
    sporcular_to_update = set()
    kulupler_to_update = set()
    tarihceler_to_save = set()

    for item in tum_kayitlar:
        derece_val = item.get('derece') or item.get('time')
        sira_val = str(item.get('sira') or item.get('rank') or '').strip()
        puan_val = item.get('puan') or item.get('points')
        if puan_val:
            try:
                puan_val = int(puan_val)
            except Exception:
                puan_val = None
        baraj_val = str(item.get('baraj') or payload.get('baraj_derecesi') or '').strip()

        # 1. DOĞRUDAN GEMINI'DEN GELEN ID İLE HIZLI GÜNCELLEME (O(1))
        race_id = item.get('id')
        if race_id:
            try:
                target_race = YarisSonucu.objects.select_related('sporcu').get(id=race_id)
                derece_sn = _time_to_seconds(derece_val)
                target_race.derece = derece_val or target_race.derece
                target_race.derece_saniye = derece_sn
                target_race.sira = sira_val
                target_race.puan = puan_val
                if baraj_val:
                    target_race.baraj = baraj_val
                target_race.kaynak_turu = "CANLI_SONUC"
                if dosya_adi:
                    target_race.dosya_adi = dosya_adi
                if dosya_obj:
                    target_race.canli_dosya = dosya_obj
                races_to_update.append(target_race)
                stats['guncellenen_sonuc'] += 1
                continue
            except YarisSonucu.DoesNotExist:
                pass
        raw_sporcu_adi = (item.get('sporcu') or item.get('name') or item.get('sporcu_adi') or '').strip()
        sporcu_adi = standardize_turkish_athlete_name(raw_sporcu_adi) or raw_sporcu_adi
        kulup_adi = (item.get('kulup') or item.get('club') or item.get('kulup_adi') or 'Ferdi').strip()
        yb = item.get('dogum_yili') or item.get('yb') or item.get('yas') or item.get('birth_year')

        dogum_yili = None
        if yb:
            try:
                yb_int = int(str(yb).strip())
                if yb_int < 100:
                    dogum_yili = 2000 + yb_int if yb_int <= 35 else 1900 + yb_int
                else:
                    dogum_yili = yb_int
            except Exception:
                pass

        if not sporcu_adi:
            continue

        seri_val = item.get('seri') or item.get('heat')
        kulvar_val = item.get('kulvar') or item.get('lane')
        if kulvar_val is not None:
            try:
                kulvar_val = int(kulvar_val)
            except Exception:
                kulvar_val = None

        giris_derecesi_val = item.get('giris_derecesi') or item.get('seed_time')
        derece_val = item.get('derece') or item.get('time')
        sira_val = str(item.get('sira') or item.get('rank') or '').strip()
        puan_val = item.get('puan') or item.get('points')
        if puan_val:
            try:
                puan_val = int(puan_val)
            except Exception:
                puan_val = None
        baraj_val = str(item.get('baraj') or payload.get('baraj_derecesi') or '').strip()

        # 1. Takım / Kulüp Yönetimi (Önbellekten O(1))
        kulup = club_cache.get(kulup_adi.lower())
        if not kulup:
            kulup, _ = Kulup.objects.get_or_create(kulup_adi=kulup_adi)
            club_cache[kulup_adi.lower()] = kulup

        # 2. Sporcu Yönetimi ve Akıllı Eşleştirme
        sporcu = None
        # Önce O(1) in-memory tam eşleşme kontrolü:
        cands = sporcu_exact_cache.get(tr_fold(sporcu_adi))
        if cands:
            # A. Birebir doğum yılı ve cinsiyet uyumu
            for cand in cands:
                if dogum_yili and cand.dogum_yili == dogum_yili:
                    if not cinsiyet or not cand.cinsiyet or cand.cinsiyet.upper().startswith(cinsiyet[0].upper()):
                        sporcu = cand
                        stats['eslesen_sporcu'] += 1
                        break
            # B. Doğum yılı +-1 toleransı ve kulüp geçmişi uyumu
            if not sporcu and kulup_adi:
                norm_target_club = kulup_adi.lower().strip()
                for cand in cands:
                    if not cinsiyet or not cand.cinsiyet or cand.cinsiyet.upper().startswith(cinsiyet[0].upper()):
                        if not dogum_yili or not cand.dogum_yili or abs(cand.dogum_yili - dogum_yili) <= 1:
                            cand_clubs = [cand.birincil_kulup.kulup_adi.lower()] if cand.birincil_kulup else []
                            cand_clubs.extend([h.kulup.kulup_adi.lower() for h in cand.kulup_tarihcesi.all()])
                            if any(norm_target_club in c or c in norm_target_club for c in cand_clubs):
                                sporcu = cand
                                stats['eslesen_sporcu'] += 1
                                break
            # C. Eğer listede tek aday varsa ve doğum yılı bilgisi yoksa
            if not sporcu and len(cands) == 1 and not dogum_yili:
                sporcu = cands[0]
                stats['eslesen_sporcu'] += 1

        # Tam eşleşme yoksa fuzzy fallback (match_athlete)
        if not sporcu:
            match_res = match_athlete(
                name=sporcu_adi,
                birth_year_or_date=dogum_yili,
                club=kulup_adi,
                gender=cinsiyet
            )
            if match_res.get('durum') == 'basarili':
                found_id = match_res.get('bulunan_id')
                if not found_id and match_res.get('muhtemel_eslesmeler'):
                    top_cand = match_res['muhtemel_eslesmeler'][0]
                    cand_score = top_cand.get('benzerlik_orani', 0)
                    cand_gender = (top_cand.get('cinsiyet') or '').upper()
                    in_gender = (cinsiyet or '').upper()
                    gender_ok = not in_gender or not cand_gender or in_gender.startswith(cand_gender[0]) or cand_gender.startswith(in_gender[0])

                    if gender_ok:
                        if cand_score >= 95.0:
                            found_id = top_cand.get('id')
                        elif cand_score >= 90.0 and kulup_adi:
                            cand_club = (top_cand.get('kulup') or '').lower()
                            if kulup_adi.lower() in cand_club or cand_club in kulup_adi.lower():
                                found_id = top_cand.get('id')

                if found_id:
                    try:
                        sporcu = Sporcu.objects.get(id=found_id)
                        stats['eslesen_sporcu'] += 1
                        sporcu_exact_cache.setdefault(tr_fold(sporcu_adi), []).append(sporcu)
                    except Sporcu.DoesNotExist:
                        sporcu = None

        if not sporcu:
            # Yeni sporcu kaydı
            sporcu = Sporcu.objects.create(
                sporcu_adi=sporcu_adi,
                dogum_yili=dogum_yili,
                yas_dogum_yili=str(dogum_yili) if dogum_yili else "",
                cinsiyet=cinsiyet or item.get('cinsiyet') or "",
                birincil_kulup=kulup if kulup.okul_mu == 0 else None,
                toplam_yaris_sayisi=0
            )
            sporcu_exact_cache.setdefault(tr_fold(sporcu_adi), []).append(sporcu)
            stats['yeni_sporcu'] += 1
        else:
            # Mevcut sporcuda eksik olan doğum yılı veya cinsiyeti güncelle
            sp_updates = []
            if dogum_yili and not sporcu.dogum_yili:
                sporcu.dogum_yili = dogum_yili
                sporcu.yas_dogum_yili = str(dogum_yili)
                sp_updates.extend(['dogum_yili', 'yas_dogum_yili'])
            if (cinsiyet or item.get('cinsiyet')) and not sporcu.cinsiyet:
                sporcu.cinsiyet = cinsiyet or item.get('cinsiyet')
                sp_updates.append('cinsiyet')
            if kulup.okul_mu == 0 and (sporcu.birincil_kulup is None or sporcu.birincil_kulup.okul_mu == 1):
                sporcu.birincil_kulup = kulup
                sp_updates.append('birincil_kulup')
            if sp_updates:
                sporcu.save(update_fields=sp_updates)

        # 3. Sporcu - Kulüp Tarihçesi Yönetimi
        tarihce, _ = SporcuKulupTarihce.objects.get_or_create(
            sporcu=sporcu,
            kulup=kulup,
            defaults={'donem_sirasi': sporcu.kulup_tarihcesi.count() + 1}
        )
        if yaris_tarihi_baslangic:
            if not tarihce.ilk_yaris_tarihi or yaris_tarihi_baslangic < tarihce.ilk_yaris_tarihi:
                tarihce.ilk_yaris_tarihi = yaris_tarihi_baslangic
            if not tarihce.son_yaris_tarihi or yaris_tarihi_baslangic > tarihce.son_yaris_tarihi:
                tarihce.son_yaris_tarihi = yaris_tarihi_baslangic

        if kulup.okul_mu == 0:
            SporcuKulupTarihce.objects.filter(sporcu=sporcu).exclude(id=tarihce.id).update(aktif_kulup_mu=0)
            tarihce.aktif_kulup_mu = 1
        else:
            has_real_club = sporcu.kulup_tarihcesi.filter(kulup__okul_mu=0).exists()
            tarihce.aktif_kulup_mu = 0 if has_real_club else 1
        tarihce.save()

        # 4. Yarış Kaydı ve Mükerrerlikten Koruma (Deduplication)
        derece_sn = _time_to_seconds(derece_val)
        existing_race = existing_races_map.get(sporcu.id)

        if not existing_race:
            cand_qs = YarisSonucu.objects.filter(sporcu=sporcu, mesafe=mesafe, stil=stil)
            if event:
                cand_meet = cand_qs.filter(event=event)
            elif musabaka_adi:
                cand_meet = cand_qs.filter(event__musabaka_adi=musabaka_adi)
            else:
                cand_meet = None

            if cand_meet:
                if yaris_no:
                    cand_y_no = cand_meet.filter(yaris_no=yaris_no)
                    if cand_y_no.exists():
                        existing_race = cand_y_no.first()
                if not existing_race and not yaris_no and cand_meet.exists():
                    existing_race = cand_meet.first()

            if not existing_race and not event and yaris_tarihi_baslangic:
                cand_date = cand_qs.filter(event__yaris_tarihi_baslangic=yaris_tarihi_baslangic)
                if yaris_no:
                    cand_d_no = cand_date.filter(yaris_no=yaris_no)
                    if cand_d_no.exists():
                        existing_race = cand_d_no.first()
                if not existing_race and not yaris_no and cand_date.exists():
                    existing_race = cand_date.first()

            if existing_race:
                existing_races_map[sporcu.id] = existing_race

        if existing_race:
            if tur == 'sonuc_listesi':
                if existing_race.derece == "Bekleniyor":
                    # Start listesinden gelen kayıt sonuçlandı -> Güncelle
                    existing_race.sira = sira_val
                    existing_race.derece = derece_val
                    existing_race.derece_saniye = derece_sn
                    existing_race.puan = puan_val
                    existing_race.kaynak_turu = "CANLI_SONUC"
                    if baraj_val:
                        existing_race.baraj = baraj_val
                    if seri_val:
                        existing_race.seri = str(seri_val)
                    if kulvar_val is not None:
                        existing_race.kulvar = kulvar_val
                    if giris_derecesi_val:
                        existing_race.giris_derecesi = str(giris_derecesi_val)
                    if kulup:
                        existing_race.kulup = kulup
                    if dosya_obj:
                        existing_race.canli_dosya = dosya_obj
                    if dosya_adi:
                        existing_race.dosya_adi = dosya_adi
                    races_to_update.append(existing_race)
                    stats['guncellenen_sonuc'] += 1
                else:
                    # Zaten sonuçlanmış kayıt; birebir aynı mı kontrol et (MÜKERRERLİK KORUMASI)
                    is_identical = (
                        (existing_race.derece or '') == (derece_val or '') and
                        (existing_race.sira or '') == (sira_val or '') and
                        (existing_race.puan or None) == puan_val
                    )
                    if is_identical:
                        stats['mukerrer_atlanilan'] += 1
                    else:
                        # Derece/sıra TYF tarafından düzeltilmiş
                        existing_race.derece = derece_val
                        existing_race.derece_saniye = derece_sn
                        existing_race.sira = sira_val
                        existing_race.puan = puan_val
                        if baraj_val:
                            existing_race.baraj = baraj_val
                        if dosya_obj:
                            existing_race.canli_dosya = dosya_obj
                        if dosya_adi:
                            existing_race.dosya_adi = dosya_adi
                        races_to_update.append(existing_race)
                        stats['guncellenen_sonuc'] += 1
            else: # start_listesi
                if existing_race.derece != "Bekleniyor":
                    # Sonuç zaten girilmiş, ezme
                    stats['mukerrer_atlanilan'] += 1
                else:
                    # Mevcut start listesi aynı mı?
                    if (existing_race.seri or '') == str(seri_val or '') and existing_race.kulvar == kulvar_val:
                        stats['mukerrer_atlanilan'] += 1
                    else:
                        if seri_val:
                            existing_race.seri = str(seri_val)
                        if kulvar_val is not None:
                            existing_race.kulvar = kulvar_val
                        if giris_derecesi_val:
                            existing_race.giris_derecesi = str(giris_derecesi_val)
                        if baraj_val and not existing_race.baraj:
                            existing_race.baraj = baraj_val
                        if dosya_obj:
                            existing_race.canli_dosya = dosya_obj
                        races_to_update.append(existing_race)
                        stats['guncellenen_sonuc'] += 1
        else:
            # YENİ YARIŞ SONUCU / START KAYDI
            yeni_derece = derece_val if tur == 'sonuc_listesi' else "Bekleniyor"
            yeni_yaris = YarisSonucu(
                event=event,
                sporcu=sporcu,
                kulup=kulup,
                sporcu_kulup_tarihce=tarihce,
                canli_dosya=dosya_obj,
                kaynak_turu="CANLI_SONUC" if tur == 'sonuc_listesi' else "CANLI_START_LISTESI",
                dosya_adi=dosya_adi,
                yaris_no=yaris_no,
                cinsiyet=cinsiyet or sporcu.cinsiyet,
                mesafe=mesafe,
                stil=stil,
                yas_grubu=item.get('yas_grubu') or yas_grubu,
                sira=sira_val if tur == 'sonuc_listesi' else "",
                seri=str(seri_val) if seri_val else None,
                kulvar=kulvar_val,
                giris_derecesi=str(giris_derecesi_val) if giris_derecesi_val else None,
                derece=yeni_derece,
                derece_saniye=derece_sn if tur == 'sonuc_listesi' else None,
                puan=puan_val if tur == 'sonuc_listesi' else None,
                baraj=baraj_val
            )
            races_to_create.append(yeni_yaris)
            existing_races_map[sporcu.id] = yeni_yaris
            stats['eklenen_sonuc'] += 1

            # YALNIZCA YENİ YARIŞ EKLENDİĞİNDE SAYAÇLARI ARTIR
            sporcu.toplam_yaris_sayisi = (sporcu.toplam_yaris_sayisi or 0) + 1
            if yaris_tarihi_baslangic:
                if not sporcu.ilk_yaris_tarihi or yaris_tarihi_baslangic < sporcu.ilk_yaris_tarihi:
                    sporcu.ilk_yaris_tarihi = yaris_tarihi_baslangic
                if not sporcu.son_yaris_tarihi or yaris_tarihi_baslangic > sporcu.son_yaris_tarihi:
                    sporcu.son_yaris_tarihi = yaris_tarihi_baslangic
            sporcular_to_update.add(sporcu)

            tarihce.toplam_yaris_sayisi = (tarihce.toplam_yaris_sayisi or 0) + 1
            tarihceler_to_save.add(tarihce)

            kulup.toplam_yaris_sayisi = (kulup.toplam_yaris_sayisi or 0) + 1
            kulupler_to_update.add(kulup)

    # BULK İŞLEMLER (YÜKSEK PERFORMANSLI TOPLU YAZIM)
    if races_to_create:
        YarisSonucu.objects.bulk_create(races_to_create, batch_size=500)
    if races_to_update:
        YarisSonucu.objects.bulk_update(
            races_to_update,
            ['derece', 'derece_saniye', 'sira', 'puan', 'baraj', 'seri', 'kulvar', 'giris_derecesi', 'kulup', 'canli_dosya', 'dosya_adi', 'kaynak_turu'],
            batch_size=500
        )
    if sporcular_to_update:
        Sporcu.objects.bulk_update(list(sporcular_to_update), ['toplam_yaris_sayisi', 'ilk_yaris_tarihi', 'son_yaris_tarihi'], batch_size=500)
    if kulupler_to_update:
        Kulup.objects.bulk_update(list(kulupler_to_update), ['toplam_yaris_sayisi'], batch_size=500)
    for t in tarihceler_to_save:
        t.save()

    if dosya_obj:
        dosya_obj.kayit_sayisi = len(tum_kayitlar)
        dosya_obj.save(update_fields=['kayit_sayisi'])

    return stats


@csrf_exempt
def api_canli_aktar(request):
    """
    GitHub Actions veya Canlı yarış botundan gelen start listesi ve yarış sonuçlarını
    veritabanına aktaran API katmanı.
    
    Özellikler:
    - Sporcu eşleştirmesi (match_athlete) ile sporcuları güvenle bağlar.
    - Yeni sporcuları ve yeni takımları (kulüp/okul ayrımıyla) otomatik kaydeder.
    - Start listesinden gelen kayıtları yarış sonuçlandığında günceller.
    - Tekrar eden isteklerde mükerrerlikten korur (idempotent / deduplication).
    """
    if request.method != 'POST':
        return JsonResponse({'durum': 'hata', 'mesaj': 'Sadece POST metodu desteklenir.'}, status=405)

    try:
        raw_body = request.body.decode('utf-8')
        data = json.loads(raw_body)
    except Exception as e:
        return JsonResponse({'durum': 'hata', 'mesaj': f'Geçersiz JSON verisi: {str(e)}'}, status=400)

    # Toplu liste veya tekil yarış desteği
    if isinstance(data, list):
        race_payloads = data
    elif isinstance(data, dict) and 'yarislar' in data and isinstance(data['yarislar'], list):
        race_payloads = data['yarislar']
    elif isinstance(data, dict):
        race_payloads = [data]
    else:
        return JsonResponse({'durum': 'hata', 'mesaj': 'Geçersiz veri yapısı.'}, status=400)

    total_stats = {
        'eklenen_sonuc_sayisi': 0,
        'guncellenen_sonuc_sayisi': 0,
        'mukerrer_atlanilan_sayisi': 0,
        'eslesen_sporcu_sayisi': 0,
        'yeni_sporcu_sayisi': 0,
        'yeni_kulup_sayisi': 0
    }

    last_tur = 'sonuc_listesi'
    with transaction.atomic():
        for r_payload in race_payloads:
            last_tur = r_payload.get('tur', last_tur)
            st = _process_single_race_payload(r_payload)
            total_stats['eklenen_sonuc_sayisi'] += st['eklenen_sonuc']
            total_stats['guncellenen_sonuc_sayisi'] += st['guncellenen_sonuc']
            total_stats['mukerrer_atlanilan_sayisi'] += st['mukerrer_atlanilan']
            total_stats['eslesen_sporcu_sayisi'] += st['eslesen_sporcu']
            total_stats['yeni_sporcu_sayisi'] += st['yeni_sporcu']
            total_stats['yeni_kulup_sayisi'] += st['yeni_kulup']

    return JsonResponse({
        'durum': 'basarili',
        'status': 'success',
        'tur': last_tur,
        'mesaj': (
            f"{total_stats['eklenen_sonuc_sayisi']} yarış eklendi, "
            f"{total_stats['guncellenen_sonuc_sayisi']} yarış güncellendi, "
            f"{total_stats['mukerrer_atlanilan_sayisi']} mükerrer kayıt atlandı."
        ),
        'istatistikler': total_stats
    }, status=200, json_dumps_params={'ensure_ascii': False})

@csrf_exempt
def api_sporcu_eslestir(request):
    """
    Sporcu Eşleştirme API'si (Açık / Yetkisiz Endpoint)
    ----------------------------------------------------
    GET veya POST parametreleriyle gelen sporcu adı ve doğum tarihi/yılına göre
    veritabanındaki Sporcu kayıtlarını sorgular.

    - Tam Eşleşme varsa: Doğrudan bulunan_id ve sporcu detayını döner.
    - Tam Eşleşme yoksa: En yüksek benzerlik puanına sahip muhtemel sporcuları liste halinde döner.
    """
    name = ""
    birth_info = None
    club = None
    limit = 10

    if request.method == 'POST':
        if request.content_type and 'application/json' in request.content_type:
            try:
                data = json.loads(request.body.decode('utf-8'))
            except Exception:
                data = {}
        else:
            data = request.POST

        name = data.get('sporcu_adi') or data.get('ad_soyad') or data.get('ad') or data.get('name') or data.get('sporcu') or ''
        birth_info = data.get('dogum_yili') or data.get('dogum_tarihi') or data.get('birth_date') or data.get('yb')
        club = data.get('kulup') or data.get('club')
        gender = data.get('cinsiyet') or data.get('gender')
        if data.get('limit'):
            try:
                limit = int(data.get('limit'))
            except Exception:
                limit = 10
    else:
        name = request.GET.get('sporcu_adi') or request.GET.get('ad_soyad') or request.GET.get('ad') or request.GET.get('name') or request.GET.get('q') or ''
        birth_info = request.GET.get('dogum_yili') or request.GET.get('dogum_tarihi') or request.GET.get('birth_date') or request.GET.get('yb')
        club = request.GET.get('kulup') or request.GET.get('club')
        gender = request.GET.get('cinsiyet') or request.GET.get('gender')
        if request.GET.get('limit'):
            try:
                limit = int(request.GET.get('limit'))
            except Exception:
                limit = 10

    res = match_athlete(name=name, birth_year_or_date=birth_info, club=club, gender=gender, limit=limit)
    status_code = 200 if res.get("durum") in ["basarili", "bulunamadi"] else 400
    return JsonResponse(res, status=status_code, json_dumps_params={'ensure_ascii': False})


def sporcu_eslestir_sayfasi(request):
    """
    Sporcu Eşleştirme Test ve Arama Arayüzü (Web Arayüzü)
    """
    name = request.GET.get('ad', '').strip()
    birth_info = request.GET.get('dogum_yili', '').strip()
    club = request.GET.get('kulup', '').strip()
    cinsiyet = request.GET.get('cinsiyet', '').strip()

    sonuc = None
    en_iyi_dereceler = []
    if name:
        sonuc = match_athlete(name=name, birth_year_or_date=birth_info, club=club, gender=cinsiyet)
        if sonuc and sonuc.get("bulunan_id"):
            sp = Sporcu.objects.filter(id=sonuc["bulunan_id"]).first()
            if sp:
                en_iyi_dereceler = sp.en_iyi_dereceler()

    context = {
        'ad': name,
        'dogum_yili': birth_info,
        'kulup': club,
        'cinsiyet': cinsiyet,
        'sonuc': sonuc,
        'en_iyi_dereceler': en_iyi_dereceler,
    }
    if request.headers.get('HX-Request'):
        return render(request, 'sonuclar/partials/sporcu_eslestir_sonuc_partial.html', context)
    return render(request, 'sonuclar/sporcu_eslestir.html', context)


@csrf_exempt
def api_sporcu_sonuclari(request, sporcu_id=None, kategori=None, mesafe=None):
    """
    Sporcu ID ile Kategori ve Mesafe Bazında Sonuçlar API'si
    -------------------------------------------------------
    GET veya POST ile gelen sporcu ID'sine göre sporcunun:
    1. Belirli bir kategori (stil) ve mesafe seçilmişse o branştaki tüm sonuç listesini ve en iyi derecesini (PB)
    2. Herhangi bir kategori seçilmemişse stil ve mesafe bazındaki kişisel en iyi derecelerini (PB özeti)
    JSON formatında döner.
    """
    if request.method == 'OPTIONS':
        resp = JsonResponse({}, status=200)
        resp["Access-Control-Allow-Origin"] = "*"
        resp["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        resp["Access-Control-Allow-Headers"] = "Content-Type, X-Requested-With, Accept"
        return resp

    target_id = sporcu_id
    kategori_filter = kategori
    mesafe_filter = mesafe
    sirala = 'tarih'
    tum_yarislar = False

    if request.method == 'POST':
        if request.content_type and 'application/json' in request.content_type:
            try:
                data = json.loads(request.body.decode('utf-8'))
            except Exception:
                data = {}
        else:
            data = request.POST

        if not target_id:
            target_id = data.get('sporcu_id') or data.get('id') or data.get('bulunan_id')
        if not kategori_filter:
            kategori_filter = data.get('kategori') or data.get('stil') or data.get('brans')
        if mesafe_filter is None:
            mesafe_filter = data.get('mesafe')
        sirala = data.get('sirala') or sirala
        tum_yarislar = str(data.get('tum_yarislar', '')).lower() in ('1', 'true', 'yes') or str(data.get('tum_sonuclar', '')).lower() in ('1', 'true', 'yes')
    else:
        if not target_id:
            target_id = request.GET.get('sporcu_id') or request.GET.get('id') or request.GET.get('bulunan_id')
        if not kategori_filter:
            kategori_filter = request.GET.get('kategori') or request.GET.get('stil') or request.GET.get('brans')
        if mesafe_filter is None:
            mesafe_filter = request.GET.get('mesafe')
        sirala = request.GET.get('sirala') or sirala
        tum_yarislar = str(request.GET.get('tum_yarislar', '')).lower() in ('1', 'true', 'yes') or str(request.GET.get('tum_sonuclar', '')).lower() in ('1', 'true', 'yes')

    if not target_id:
        return JsonResponse({
            "durum": "gecersiz_istek",
            "mesaj": "Geçerli bir sporcu ID'si belirtilmelidir (örn: ?sporcu_id=441 veya /api/sporcular/441/sonuclar/).",
            "sporcu": None,
            "en_iyi_sonuclar": [],
            "sonuclar": []
        }, status=400, json_dumps_params={'ensure_ascii': False})

    try:
        target_id = int(str(target_id).strip())
    except (ValueError, TypeError):
        return JsonResponse({
            "durum": "gecersiz_istek",
            "mesaj": f"Geçersiz sporcu ID formatı: '{target_id}'. ID bir tamsayı olmalıdır.",
            "sporcu": None,
            "en_iyi_sonuclar": [],
            "sonuclar": []
        }, status=400, json_dumps_params={'ensure_ascii': False})

    try:
        sp = Sporcu.objects.select_related('birincil_kulup').get(id=target_id)
    except Sporcu.DoesNotExist:
        return JsonResponse({
            "durum": "bulunamadi",
            "mesaj": f"ID: {target_id} olan sporcu veritabanında bulunamadı.",
            "sporcu": None,
            "en_iyi_sonuclar": [],
            "sonuclar": []
        }, status=404, json_dumps_params={'ensure_ascii': False})

    aktif_k = sp.aktif_kulup()
    okul_adi = sp.okul()

    sporcu_data = {
        "id": sp.id,
        "sporcu_adi": sp.sporcu_adi,
        "dogum_yili": sp.dogum_yili,
        "yas_dogum_yili": sp.yas_dogum_yili,
        "cinsiyet": sp.cinsiyet,
        "kulup": aktif_k.kulup_adi if aktif_k else (sp.birincil_kulup.kulup_adi if sp.birincil_kulup else "Kulüpsüz / Ferdi"),
        "okul": okul_adi,
        "toplam_yaris_sayisi": sp.toplam_yaris_sayisi,
        "ilk_yaris_tarihi": sp.ilk_yaris_tarihi,
        "son_yaris_tarihi": sp.son_yaris_tarihi,
        "profil_url": f"/sporcular/{sp.id}/"
    }

    # Kulüp Tarihçesi (Tarihe göre: Aktif ve en yeni kulüp en üstte)
    tarihce_list = []
    for t in sp.kulup_tarihcesi.select_related('kulup').order_by('-aktif_kulup_mu', '-son_yaris_tarihi', '-ilk_yaris_tarihi'):
        tarihce_list.append({
            "kulup_id": t.kulup.id,
            "kulup_adi": t.kulup.kulup_adi,
            "okul_mu": t.kulup.okul_mu,
            "aktif_kulup_mu": t.aktif_kulup_mu,
            "toplam_yaris_sayisi": t.toplam_yaris_sayisi,
            "ilk_yaris_tarihi": t.ilk_yaris_tarihi,
            "son_yaris_tarihi": t.son_yaris_tarihi,
            "donem_sirasi": t.donem_sirasi
        })

    # Mesafe int dönüşümü
    mesafe_val = None
    if mesafe_filter is not None and str(mesafe_filter).strip():
        try:
            mesafe_val = int(str(mesafe_filter).strip())
        except (ValueError, TypeError):
            pass

    kategori_str = str(kategori_filter).strip() if kategori_filter else ""

    # Kişisel En İyi Dereceler (PB listesi)
    pbs = sp.en_iyi_dereceler()
    pb_list = []
    for pb in pbs:
        if kategori_str and kategori_str.lower() not in (pb.stil or '').lower():
            continue
        if mesafe_val is not None and pb.mesafe != mesafe_val:
            continue

        pb_list.append({
            "etkinlik": f"{pb.mesafe}m {pb.stil}" if pb.mesafe and pb.stil else (pb.stil or ""),
            "mesafe": pb.mesafe,
            "stil": pb.stil,
            "derece": pb.derece,
            "derece_saniye": pb.derece_saniye,
            "puan": pb.puan,
            "sira": pb.sira,
            "baraj": pb.baraj,
            "tarih": pb.yaris_tarihi_baslangic or pb.yaris_tarihi_ham,
            "musabaka_adi": pb.musabaka_adi,
            "sehir": pb.sehir,
            "kulup": pb.kulup.kulup_adi if pb.kulup else "",
            "kulup_okul_mu": pb.kulup.okul_mu if pb.kulup else 0
        })

    # Kategori veya Mesafe filtresi verilmişse (veya tum_yarislar istenmişse)
    # sporcunun o branştaki tüm sonuçlarını liste halinde dön
    if kategori_str or mesafe_val is not None:
        races_qs = sp.yaris_sonuclari.select_related('kulup', 'event')
        if kategori_str:
            races_qs = races_qs.filter(stil__icontains=kategori_str)
        if mesafe_val is not None:
            races_qs = races_qs.filter(mesafe=mesafe_val)

        # Sıralama
        if sirala == 'derece':
            races_qs = races_qs.order_by('derece_saniye', '-event__yaris_tarihi_baslangic')
        elif sirala in ('tarih_asc', 'eskiden_yeniye', 'kronolojik'):
            races_qs = races_qs.order_by('event__yaris_tarihi_baslangic', 'id')
        else:
            races_qs = races_qs.order_by('-event__yaris_tarihi_baslangic', '-id')

        # O branştaki en iyi derece (PB) tespiti
        valid_pb_race = races_qs.filter(
            derece_saniye__isnull=False,
            derece_saniye__gt=0
        ).order_by('derece_saniye').first()

        best_race_dict = None
        if valid_pb_race:
            best_race_dict = {
                "id": valid_pb_race.id,
                "etkinlik": f"{valid_pb_race.mesafe}m {valid_pb_race.stil}" if valid_pb_race.mesafe and valid_pb_race.stil else (valid_pb_race.stil or ""),
                "mesafe": valid_pb_race.mesafe,
                "stil": valid_pb_race.stil,
                "derece": valid_pb_race.derece,
                "derece_saniye": valid_pb_race.derece_saniye,
                "puan": valid_pb_race.puan,
                "sira": valid_pb_race.sira,
                "baraj": valid_pb_race.baraj,
                "tarih": valid_pb_race.yaris_tarihi_baslangic or valid_pb_race.yaris_tarihi_ham,
                "musabaka_adi": valid_pb_race.musabaka_adi,
                "sehir": valid_pb_race.sehir,
                "kulup": valid_pb_race.kulup.kulup_adi if valid_pb_race.kulup else "",
                "kulup_okul_mu": valid_pb_race.kulup.okul_mu if valid_pb_race.kulup else 0
            }

        filtered_results_list = []
        for y in races_qs:
            filtered_results_list.append({
                "id": y.id,
                "tarih": y.yaris_tarihi_baslangic or y.yaris_tarihi_ham,
                "musabaka_adi": y.musabaka_adi,
                "sehir": y.sehir,
                "mesafe": y.mesafe,
                "stil": y.stil,
                "etkinlik": f"{y.mesafe}m {y.stil}" if y.mesafe and y.stil else (y.stil or ""),
                "derece": y.derece,
                "derece_saniye": y.derece_saniye,
                "puan": y.puan,
                "sira": y.sira,
                "seri": y.seri,
                "kulvar": y.kulvar,
                "giris_derecesi": y.giris_derecesi,
                "baraj": y.baraj,
                "kulup": y.kulup.kulup_adi if y.kulup else "",
                "kulup_okul_mu": y.kulup.okul_mu if y.kulup else 0,
                "yas_grubu": y.yas_grubu,
                "sporcu_yasi": y.hesaplanan_yas or y.sporcu_yas,
                "kisisel_en_iyi_mi": bool(valid_pb_race and y.id == valid_pb_race.id)
            })

        # Sadece en_iyi_derece ve sonuclar döner
        resp = JsonResponse({
            "en_iyi_derece": best_race_dict,
            "sonuclar": filtered_results_list
        }, status=200, json_dumps_params={'ensure_ascii': False})
        resp["Access-Control-Allow-Origin"] = "*"
        resp["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        resp["Access-Control-Allow-Headers"] = "Content-Type, X-Requested-With, Accept"
        return resp

    # Kategori veya mesafe belirtilmemişse
    resp = JsonResponse({
        "en_iyi_derece": pb_list,
        "sonuclar": pb_list
    }, status=200, json_dumps_params={'ensure_ascii': False})
    resp["Access-Control-Allow-Origin"] = "*"
    resp["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    resp["Access-Control-Allow-Headers"] = "Content-Type, X-Requested-With, Accept"
    return resp


def canli_yaris_listesi(request):
    """Canlı yarışların listelendiği ve yeni linkin eklendiği panel."""
    if request.method == "POST":
        canli_url = request.POST.get("canli_url", "").strip()
        reglaman_linki = request.POST.get("reglaman_linki", "").strip()
        musabaka_adi = request.POST.get("musabaka_adi", "").strip()
        if canli_url:
            sehir_val = None
            tarih_val = None
            start_d, end_d = '', ''
            try:
                from src.live_startlist_worker import fetch_event_page
                title_scraped, city_scraped, date_scraped, start_d, end_d, _, _ = fetch_event_page(canli_url)
                if not musabaka_adi and title_scraped:
                    musabaka_adi = title_scraped
                sehir_val = city_scraped
                tarih_val = date_scraped or start_d
            except Exception:
                pass

            if not sehir_val:
                m_url_city = re.search(r'canli\.tyf\.gov\.tr/([a-zA-ZçğıöşüÇĞİÖŞÜ]+)/', canli_url)
                if m_url_city:
                    c_raw = m_url_city.group(1).lower()
                    sehir_val = c_raw.replace('i', 'İ').replace('ı', 'I').upper()

            event_obj = None
            if musabaka_adi:
                event_obj, _ = Event.objects.get_or_create(
                    musabaka_adi=musabaka_adi,
                    defaults={
                        'sehir': sehir_val,
                        'yaris_tarihi_baslangic': start_d,
                        'yaris_tarihi_bitis': end_d,
                        'yaris_tarihi_ham': tarih_val or '',
                        'kaynak_turu': "CANLI_TAKIP"
                    }
                )

            yaris = CanliYaris.objects.create(
                event=event_obj,
                canli_url=canli_url,
                reglaman_linki=reglaman_linki or None,
                musabaka_adi=musabaka_adi or None,
                sehir=sehir_val,
                tarih=tarih_val,
                durum="BEKLIYOR"
            )
            messages.success(request, f"Canlı yarış linki eklendi: {yaris.canli_url}")
            return redirect("sonuclar:canli_yaris_listesi")
        else:
            messages.error(request, "Lütfen geçerli bir canlı yarış linki girin.")

    yarislar = CanliYaris.objects.all().select_related('event').order_by("-olusturulma_tarihi")
    return render(request, "sonuclar/canli_yarislar.html", {"yarislar": yarislar})


def canli_yaris_tara(request, pk):
    """Canlı yarışı Cloud Run tarama sırasına (BEKLIYOR) alır veya yerel ortamda çalıştırır."""
    if request.method != "POST":
        return redirect("sonuclar:canli_yaris_listesi")

    yaris = get_object_or_404(CanliYaris, pk=pk)

    mod = request.POST.get('mod', 'hepsi')
    limit_raw = request.POST.get('limit', '').strip()
    limit = int(limit_raw) if (limit_raw and limit_raw.isdigit()) else None

    host = request.get_host().lower()
    is_localhost = host.startswith("127.0.0.1") or host.startswith("localhost")

    # Yerel geliştirme ortamında doğrudan yerel worker ile arka planda çalıştırma seçeneği
    if is_localhost and request.POST.get('yerel_calistir') == '1':
        def worker_thread(event_id, url, api_target, mod_val, limit_val):
            try:
                from src.live_startlist_worker import run_live_event_startlists
                obj = CanliYaris.objects.get(id=event_id)
                obj.durum = "ISLENIYOR"
                obj.son_islem_tarihi = timezone.now()
                obj.save()

                stats = run_live_event_startlists(
                    event_url=url,
                    django_api_url=api_target,
                    limit=limit_val,
                    mod=mod_val,
                    canli_yaris_id=event_id
                )

                obj = CanliYaris.objects.get(id=event_id)
                obj.durum = "TAMAMLANDI" if stats.get("basarili_sayisi", 0) > 0 else "HATA"
                obj.musabaka_adi = stats.get("musabaka_adi") or obj.musabaka_adi
                if stats.get("sehir"): obj.sehir = stats["sehir"]
                if stats.get("tarih"): obj.tarih = stats["tarih"]
                if mod_val == 'sonuc_listesi':
                    obj.toplam_sonuc_listesi = stats.get("toplam_liste", 0)
                    obj.islenen_sonuc_listesi = stats.get("basarili_sayisi", 0)
                else:
                    obj.toplam_start_listesi = stats.get("toplam_liste", 0)
                    obj.islenen_start_listesi = stats.get("basarili_sayisi", 0)
                obj.eklenen_kayit_sayisi = (obj.eklenen_kayit_sayisi or 0) + stats.get("toplam_kayit", 0)
                obj.son_islem_tarihi = timezone.now()
                obj.save()
            except Exception as e:
                try:
                    obj = CanliYaris.objects.get(id=event_id)
                    obj.durum = "HATA"
                    obj.hata_mesaji = str(e)
                    obj.son_islem_tarihi = timezone.now()
                    obj.save()
                except Exception:
                    pass

        api_target = request.build_absolute_uri("/api/canli-aktar/")
        threading.Thread(
            target=worker_thread,
            args=(yaris.id, yaris.canli_url, api_target, mod, limit),
            daemon=True
        ).start()
        messages.info(request, f"Yerel test taraması başlatıldı (ID #{yaris.id}).")
        return redirect("sonuclar:canli_yaris_listesi")

    # Prod / Standart Mimari: Web uygulamasından Cloud Run tetiklenmez!
    # Yarış 'BEKLIYOR' durumuna alınır; Cloud Run rutin taramasında bu linki otomatik alıp işler.
    yaris.durum = "BEKLIYOR"
    yaris.hata_mesaji = None
    yaris.son_islem_tarihi = timezone.now()
    yaris.save()
    messages.success(request, f"'{yaris.musabaka_adi or yaris.canli_url}' tarama sırasına alındı (Durum: Bekliyor). Cloud Run periyodik taraması bu yarışı otomatik tarayacaktır.")
    return redirect("sonuclar:canli_yaris_listesi")


def canli_yaris_sil(request, pk):
    """Canlı yarış kaydını siler."""
    if request.method == "POST":
        yaris = get_object_or_404(CanliYaris, pk=pk)
        yaris.delete()
        messages.success(request, "Canlı yarış kaydı silindi.")
    return redirect("sonuclar:canli_yaris_listesi")


@csrf_exempt
def api_canli_durum_guncelle(request):
    """
    Cloud Run veya arka plan worker'ından gelen canlı yarış durum güncellemesini kaydeder.
    """
    if request.method != "POST":
        return JsonResponse({"durum": "hata", "mesaj": "Sadece POST metodu desteklenir."}, status=405)

    try:
        data = json.loads(request.body.decode("utf-8"))
    except Exception as e:
        return JsonResponse({"durum": "hata", "mesaj": f"Geçersiz JSON: {e}"}, status=400)

    event_id = data.get("event_id")
    event_url = data.get("event_url")

    yaris = None
    if event_id:
        yaris = CanliYaris.objects.filter(id=event_id).first()
    if not yaris and event_url:
        yaris = CanliYaris.objects.filter(canli_url=event_url).first()

    if not yaris:
        return JsonResponse({"durum": "hata", "mesaj": "Canlı yarış kaydı bulunamadı."}, status=404)

    durum = data.get("durum")
    if durum in ["BEKLIYOR", "ISLENIYOR", "TAMAMLANDI", "HATA"]:
        yaris.durum = durum

    if data.get("reglaman_linki"):
        yaris.reglaman_linki = data["reglaman_linki"]
    if data.get("barajlar"):
        yaris.barajlar = data["barajlar"]
    if data.get("musabaka_adi"):
        yaris.musabaka_adi = data["musabaka_adi"]
    if data.get("sehir"):
        yaris.sehir = data["sehir"]
    if data.get("tarih"):
        yaris.tarih = data["tarih"]
    if "toplam_start_listesi" in data:
        yaris.toplam_start_listesi = int(data["toplam_start_listesi"])
    if "islenen_start_listesi" in data:
        yaris.islenen_start_listesi = int(data["islenen_start_listesi"])
    if "toplam_sonuc_listesi" in data:
        yaris.toplam_sonuc_listesi = int(data["toplam_sonuc_listesi"])
    if "islenen_sonuc_listesi" in data:
        yaris.islenen_sonuc_listesi = int(data["islenen_sonuc_listesi"])
    elif "basarili" in data and not data.get("toplam_sonuc_listesi"):
        yaris.islenen_start_listesi = int(data["basarili"])
    if "toplam_sporcu" in data:
        yaris.eklenen_kayit_sayisi = int(data["toplam_sporcu"])
    elif "eklenen_kayit_sayisi" in data:
        yaris.eklenen_kayit_sayisi = int(data["eklenen_kayit_sayisi"])

    if data.get("hatalar"):
        hatalar = data["hatalar"]
        yaris.hata_mesaji = "\n".join(hatalar) if isinstance(hatalar, list) else str(hatalar)

    yaris.son_islem_tarihi = timezone.now()
    yaris.save()

    return JsonResponse({"durum": "basarili", "mesaj": f"Yarış #{yaris.id} durumu güncellendi: {yaris.durum}"})


@csrf_exempt
def api_canli_yaris_ekle(request):
    """
    Harici bot/scraper tarafından TYF sayfalarında tespit edilen yeni canlı yarışları sisteme ekler.
    Mükerrer eklemeyi engeller (canli_url bazında get_or_create).
    """
    if request.method != "POST":
        return JsonResponse({"durum": "hata", "mesaj": "Sadece POST metodu desteklenir."}, status=405)

    try:
        data = json.loads(request.body.decode("utf-8"))
    except Exception as e:
        return JsonResponse({"durum": "hata", "mesaj": f"Geçersiz JSON: {e}"}, status=400)

    canli_url = (data.get("canli_url") or data.get("yaris_url") or "").strip()
    if not canli_url:
        return JsonResponse({"durum": "hata", "mesaj": "canli_url parametresi zorunludur."}, status=400)

    musabaka_adi = (data.get("musabaka_adi") or data.get("yaris_adi") or "").strip()
    sehir = (data.get("sehir") or "").strip()
    tarih = (data.get("tarih") or "").strip()
    reglaman_linki = (data.get("reglaman_linki") or "").strip()

    yaris, created = CanliYaris.objects.get_or_create(
        canli_url=canli_url,
        defaults={
            "musabaka_adi": musabaka_adi,
            "sehir": sehir,
            "tarih": tarih,
            "reglaman_linki": reglaman_linki if reglaman_linki else None,
            "durum": "BEKLIYOR"
        }
    )

    updated = False
    if musabaka_adi and not yaris.musabaka_adi:
        yaris.musabaka_adi = musabaka_adi
        updated = True
    if sehir and not yaris.sehir:
        yaris.sehir = sehir
        updated = True
    if tarih and not yaris.tarih:
        yaris.tarih = tarih
        updated = True
    if reglaman_linki and not yaris.reglaman_linki:
        yaris.reglaman_linki = reglaman_linki
        updated = True
    if updated:
        yaris.save()

    return JsonResponse({
        "durum": "basarili",
        "yeni_kayit": created,
        "yaris": {
            "id": yaris.id,
            "canli_url": yaris.canli_url,
            "musabaka_adi": yaris.musabaka_adi,
            "sehir": yaris.sehir,
            "tarih": yaris.tarih,
            "durum": yaris.durum
        }
    }, status=201 if created else 200)


def api_canli_yarislar_durum(request):
    """
    Arayüzün durumları canlı yenilemesi için JSON liste döner.
    """
    yarislar = CanliYaris.objects.all().values(
        "id", "musabaka_adi", "durum", "toplam_start_listesi",
        "islenen_start_listesi", "toplam_sonuc_listesi", "islenen_sonuc_listesi",
        "eklenen_kayit_sayisi", "hata_mesaji"
    )
    return JsonResponse({"yarislar": list(yarislar)})


@csrf_exempt
def api_canli_bekleyen_yarislar(request):
    """
    Cloud Run rutin tarama botu için işlenmeyi bekleyen canlı yarışları döner.
    Cloud Run bu endpoint'i periyodik (ör: Cloud Scheduler) çağırıp bekleyen yarışları çeker.
    """
    durum_param = request.GET.get('durum', '').strip()
    if durum_param:
        qs = CanliYaris.objects.filter(durum=durum_param)
    else:
        # Varsayılan: Bekleyen veya işlemde kalan yarışlar
        qs = CanliYaris.objects.filter(durum__in=['BEKLIYOR', 'ISLENIYOR'])

    yarislar_data = []
    for y in qs.order_by('-olusturulma_tarihi'):
        yarislar_data.append({
            "id": y.id,
            "event_id": y.event_id,
            "canli_url": y.canli_url,
            "reglaman_linki": y.reglaman_linki or "",
            "barajlar": y.barajlar or {},
            "musabaka_adi": y.musabaka_adi or "",
            "sehir": y.gosterilen_sehir,
            "tarih": y.gosterilen_tarih,
            "baslangic_tarihi": y.event.yaris_tarihi_baslangic if y.event else None,
            "bitis_tarihi": y.event.yaris_tarihi_bitis if y.event else None,
            "durum": y.durum,
            "toplam_start_listesi": y.toplam_start_listesi,
            "islenen_start_listesi": y.islenen_start_listesi,
            "toplam_sonuc_listesi": y.toplam_sonuc_listesi,
            "islenen_sonuc_listesi": y.islenen_sonuc_listesi,
            "eklenen_kayit_sayisi": y.eklenen_kayit_sayisi,
            "son_islem_tarihi": y.son_islem_tarihi.isoformat() if y.son_islem_tarihi else None
        })

    # Sistemde kayıtlı tüm canlı yarışlar arasındaki en son yarış numarası
    en_son_yaris_no = None
    all_urls = CanliYaris.objects.values_list('canli_url', flat=True)
    for u in all_urls:
        m = re.search(r'cs-(\d+)', u or '')
        if m:
            val = int(m.group(1))
            if en_son_yaris_no is None or val > en_son_yaris_no:
                en_son_yaris_no = val

    return JsonResponse({
        "durum": "basarili",
        "toplam": len(yarislar_data),
        "en_son_yaris_no": en_son_yaris_no,
        "yarislar": yarislar_data
    })


def musabaka_listesi(request):
    """Müsabakalar (Events) listesi ve arama sayfası (İsteğe bağlı arama - On-demand)."""
    q = request.GET.get('q', '').strip()
    sehir = request.GET.get('sehir', '').strip()
    yil = request.GET.get('yil', '').strip()

    has_query = bool(q or sehir or yil)

    if not has_query:
        page_obj = None
        total_count = 0
    else:
        qs = Event.objects.all()
        if q:
            qs = qs.filter(musabaka_adi__icontains=q)
        if sehir:
            qs = qs.filter(sehir__icontains=sehir)
        if yil and yil.isdigit():
            qs = qs.filter(yaris_tarihi_baslangic__startswith=yil)

        paginator = Paginator(qs, 30)
        page_number = request.GET.get('page')
        page_obj = paginator.get_page(page_number)
        total_count = paginator.count

    sehirler = cache.get('distinct_event_cities')
    if sehirler is None:
        sehirler = list(Event.objects.exclude(sehir__isnull=True).exclude(sehir='').values_list('sehir', flat=True).distinct().order_by('sehir'))
        cache.set('distinct_event_cities', sehirler, 3600)  # 1 saat önbellek

    context = {
        'page_obj': page_obj,
        'has_query': has_query,
        'q': q,
        'sehir': sehir,
        'yil': yil,
        'sehirler': sehirler,
        'total_count': total_count,
    }
    if request.headers.get('HX-Request'):
        return render(request, 'sonuclar/partials/musabaka_table_partial.html', context)
    return render(request, 'sonuclar/musabaka_listesi.html', context)


def musabaka_detay(request, pk):
    """Tekil müsabaka detay sayfası ve yarış sonuçları (PythonAnywhere Optimize Edilmiş - On-demand Lazy Query)."""
    event = get_object_or_404(Event, pk=pk)

    # Filtreleme (Yarış No, Durum, Kulüp/Takım & Sporcu)
    secili_yaris_no = request.GET.get('yaris_no', '').strip()
    secili_durum = request.GET.get('durum', '').strip()
    secili_kulup = request.GET.get('kulup', '').strip()
    secili_sporcu = request.GET.get('sporcu', '').strip()
    target = request.headers.get('HX-Target') or request.GET.get('target', '')

    is_modal_request = bool(
        secili_yaris_no or 
        target in ('modalContent', '#yarisSonuclarModalContent', 'yarisSonuclarModalContent') or
        (request.headers.get('HX-Request') and target not in ('programContent', '#programContent'))
    )

    # 1. Sadece bu müsabakaya katılan kulüpler / takımlar (Index üzerinden hızlı DISTINCT)
    katilan_kulupler = list(
        event.yaris_sonuclari.exclude(kulup__isnull=True)
        .values('kulup_id', 'kulup__kulup_adi')
        .distinct()
        .order_by('kulup__kulup_adi')
    )

    # 2. Seçili kulüp istatistikleri (Yarış programı bazında)
    kulup_yaris_counts = {}
    secili_kulup_id = int(secili_kulup) if secili_kulup and secili_kulup.isdigit() else None
    secili_kulup_obj = None
    kulup_toplam_yaris_sayisi = 0
    kulup_toplam_sporcu_sayisi = 0
    kulup_katilinan_yaris_sayisi = 0

    if secili_kulup_id:
        secili_kulup_obj = Kulup.objects.filter(id=secili_kulup_id).first()
        kc_qs = (
            event.yaris_sonuclari.filter(kulup_id=secili_kulup_id)
            .exclude(yaris_no__isnull=True).exclude(yaris_no='')
            .values('yaris_no')
            .annotate(
                kulup_toplam=Count('id'),
                kulup_tamamlanan=Count('id', filter=~Q(derece='Bekleniyor')),
                kulup_bekleyen=Count('id', filter=Q(derece='Bekleniyor')),
            )
        )
        for kc in kc_qs:
            yno_str = str(kc['yaris_no']).strip()
            kulup_yaris_counts[yno_str] = {
                'toplam': kc['kulup_toplam'],
                'tamamlanan': kc['kulup_tamamlanan'],
                'bekleyen': kc['kulup_bekleyen'],
            }
            kulup_toplam_yaris_sayisi += kc['kulup_toplam']
        
        kulup_katilinan_yaris_sayisi = len(kulup_yaris_counts)
        kulup_toplam_sporcu_sayisi = (
            event.yaris_sonuclari.filter(kulup_id=secili_kulup_id)
            .values('sporcu_id').distinct().count()
        )

    # 3. Yarış programı ve anlık durum istatistikleri (Tek toplu ORM sorgusu)
    races_qs = (
        event.yaris_sonuclari.exclude(yaris_no__isnull=True).exclude(yaris_no='')
        .values('yaris_no', 'mesafe', 'stil', 'cinsiyet', 'yas_grubu')
        .annotate(
            toplam=Count('id'),
            tamamlanan=Count('id', filter=~Q(derece='Bekleniyor')),
            bekleyen=Count('id', filter=Q(derece='Bekleniyor')),
        )
    )

    yaris_dict = {}
    event_toplam_tamamlanan = 0
    event_toplam_bekleyen = 0
    event_hesaplanan_yaris_sayisi = 0

    for r in races_qs:
        yno = str(r['yaris_no']).strip()
        if not yno:
            continue
        event_toplam_tamamlanan += r['tamamlanan']
        event_toplam_bekleyen += r['bekleyen']
        event_hesaplanan_yaris_sayisi += r['toplam']

        if yno not in yaris_dict:
            yaris_dict[yno] = {
                'no': yno,
                'yaris_no': yno,
                'mesafe': r['mesafe'],
                'stil': (r['stil'] or '').strip(),
                'cinsiyet': (r['cinsiyet'] or '').strip(),
                'yas_grubu': (r['yas_grubu'] or '').strip(),
                'toplam': r['toplam'],
                'tamamlanan': r['tamamlanan'],
                'bekleyen': r['bekleyen'],
            }
        else:
            yaris_dict[yno]['toplam'] += r['toplam']
            yaris_dict[yno]['tamamlanan'] += r['tamamlanan']
            yaris_dict[yno]['bekleyen'] += r['bekleyen']
            if not yaris_dict[yno]['mesafe'] and r['mesafe']:
                yaris_dict[yno]['mesafe'] = r['mesafe']
            if not yaris_dict[yno]['stil'] and r['stil']:
                yaris_dict[yno]['stil'] = (r['stil'] or '').strip()
            if not yaris_dict[yno]['cinsiyet'] and r['cinsiyet']:
                yaris_dict[yno]['cinsiyet'] = (r['cinsiyet'] or '').strip()

    yaris_programi = []
    toplam_biten_yaris = 0
    toplam_bekleyen_yaris = 0
    toplam_canli_yaris = 0

    for yno, data in yaris_dict.items():
        tamamlanan = data['tamamlanan']

        # Kural: Eğer en az 1 sonuç varsa 'Sonuçlandı', hiç sonuç yoksa 'Start Listesi'
        if tamamlanan > 0:
            durum_kodu = 'tamamlandi'
            durum_etiketi = 'Sonuçlandı'
            durum_renk = 'success'
            durum_ikon = 'bi-check2-circle'
            toplam_biten_yaris += 1
        else:
            durum_kodu = 'bekliyor'
            durum_etiketi = 'Start Listesi'
            durum_renk = 'warning'
            durum_ikon = 'bi-clock-history'
            toplam_bekleyen_yaris += 1

        # Kulübe ait yarış istatistikleri
        k_info = kulup_yaris_counts.get(yno)
        if k_info:
            kulup_sporcu_sayisi = k_info['toplam']
            kulup_tamamlanan = k_info['tamamlanan']
            kulup_bekleyen = k_info['bekleyen']
        else:
            kulup_sporcu_sayisi = 0 if secili_kulup_id else None
            kulup_tamamlanan = 0
            kulup_bekleyen = 0

        data.update({
            'durum_kodu': durum_kodu,
            'durum_etiketi': durum_etiketi,
            'durum_renk': durum_renk,
            'durum_ikon': durum_ikon,
            'kulup_sporcu_sayisi': kulup_sporcu_sayisi,
            'kulup_tamamlanan': kulup_tamamlanan,
            'kulup_bekleyen': kulup_bekleyen,
        })
        yaris_programi.append(data)

    def _sort_yaris(x):
        try:
            return int(x['no'])
        except (ValueError, TypeError):
            return 9999

    yaris_programi.sort(key=_sort_yaris)

    secili_yaris_detay = next((y for y in yaris_programi if y['no'] == secili_yaris_no), None)
    canli_yaris = CanliYaris.objects.filter(event_id=event.id).first()

    event_toplam_yaris = event.toplam_yaris_sayisi or event_hesaplanan_yaris_sayisi
    event_toplam_sporcu = event.toplam_sporcu_sayisi

    page_obj = None
    completed_count = event_toplam_tamamlanan
    pending_count = event_toplam_bekleyen
    total_count = event_toplam_yaris

    # 4. Sonuçlar Tablosu (Sadece Modal açıldığında veya yarış no seçildiğinde on-demand çalışır)
    if is_modal_request:
        sonuclar_qs = event.yaris_sonuclari.select_related('sporcu', 'kulup')
        if secili_yaris_no:
            sonuclar_qs = sonuclar_qs.filter(yaris_no=secili_yaris_no)
        if secili_kulup_id:
            sonuclar_qs = sonuclar_qs.filter(kulup_id=secili_kulup_id)
        if secili_sporcu and secili_sporcu.isdigit():
            sonuclar_qs = sonuclar_qs.filter(sporcu_id=int(secili_sporcu))

        if secili_yaris_detay:
            completed_count = secili_yaris_detay['tamamlanan']
            pending_count = secili_yaris_detay['bekleyen']
        else:
            completed_count = sonuclar_qs.exclude(derece='Bekleniyor').count()
            pending_count = sonuclar_qs.filter(derece='Bekleniyor').count()

        if secili_durum == 'sonuc':
            sonuclar_qs = sonuclar_qs.exclude(derece='Bekleniyor')
        elif secili_durum == 'bekliyor':
            sonuclar_qs = sonuclar_qs.filter(derece='Bekleniyor')

        # Müsabaka yılı tespiti (Hesaplanan yaş için)
        event_year = None
        if event.yaris_tarihi_baslangic and len(event.yaris_tarihi_baslangic) >= 4 and event.yaris_tarihi_baslangic[:4].isdigit():
            event_year = int(event.yaris_tarihi_baslangic[:4])
        elif event.yaris_tarihi_ham:
            m = re.search(r'\b(20\d{2})\b', event.yaris_tarihi_ham)
            if m:
                event_year = int(m.group(1))
        if not event_year:
            event_year = timezone.now().year

        sonuclar_qs = sonuclar_qs.annotate(
            yaris_no_int=Cast('yaris_no', IntegerField()),
            raw_sporcu_yas_int=Cast('sporcu_yas', IntegerField()),
            raw_yas_grubu_int=Cast('yas_grubu', IntegerField()),
            raw_hesaplanan_yas_int=Case(
                When(hesaplanan_yas__isnull=False, hesaplanan_yas__gt=0, then=F('hesaplanan_yas')),
                When(sporcu__dogum_yili__isnull=False, sporcu__dogum_yili__gt=1900, then=Value(event_year) - F('sporcu__dogum_yili')),
                When(sporcu_yas__isnull=False, sporcu_yas__gt='', then='raw_sporcu_yas_int'),
                When(yas_grubu__isnull=False, yas_grubu__gt='', then='raw_yas_grubu_int'),
                default=Value(999),
                output_field=IntegerField()
            ),
            yas_int=Case(
                When(raw_hesaplanan_yas_int__gte=13, raw_hesaplanan_yas_int__lt=900, then=Value(13)),
                When(raw_hesaplanan_yas_int__lte=0, then=Value(900)),
                default='raw_hesaplanan_yas_int',
                output_field=IntegerField()
            ),
            yas_gosterim=Case(
                When(hesaplanan_yas__isnull=False, hesaplanan_yas__gt=0, then=Cast(F('hesaplanan_yas'), CharField())),
                When(sporcu__dogum_yili__isnull=False, sporcu__dogum_yili__gt=1900, then=Cast(Value(event_year) - F('sporcu__dogum_yili'), CharField())),
                When(sporcu_yas__isnull=False, sporcu_yas__gt='', then=F('sporcu_yas')),
                When(yas_grubu__isnull=False, yas_grubu__gt='', then=F('yas_grubu')),
                default=Value(''),
                output_field=CharField()
            ),
            yas_grup_adi=Case(
                When(raw_hesaplanan_yas_int__gte=13, raw_hesaplanan_yas_int__lt=900, then=Value('13+ Yaş Grubu')),
                When(Q(raw_hesaplanan_yas_int__gt=0) & Q(raw_hesaplanan_yas_int__lt=13), then=Concat(Cast('raw_hesaplanan_yas_int', CharField()), Value(' Yaş Grubu'))),
                When(yas_grubu__isnull=False, yas_grubu__gt='', then=F('yas_grubu')),
                default=Value('Genel Sıralama'),
                output_field=CharField()
            ),
            derece_kategori=Case(
                When(
                    Q(sira__icontains='disk') | Q(derece__icontains='disk') | 
                    Q(sira__icontains='dq') | Q(derece__icontains='dq') | 
                    Q(derece__startswith='SW') | Q(sira__startswith='SW') |
                    Q(derece__iexact='dnf') | Q(sira__iexact='dnf'),
                    then=Value(2)
                ),
                When(
                    Q(derece='Bekleniyor') | Q(derece__isnull=True) | Q(derece='') | Q(derece='-') |
                    Q(sira__icontains='dns') | Q(derece__icontains='dns') |
                    Q(derece_saniye__isnull=True) | Q(derece_saniye__lte=0),
                    then=Value(3)
                ),
                default=Value(1),
                output_field=IntegerField()
            ),
            is_dq=Case(
                When(
                    Q(sira__icontains='disk') | Q(derece__icontains='disk') | 
                    Q(sira__icontains='dq') | Q(derece__icontains='dq') | 
                    Q(derece__startswith='SW') | Q(sira__startswith='SW') |
                    Q(derece__iexact='dnf') | Q(sira__iexact='dnf'),
                    then=Value(True)
                ),
                default=Value(False),
                output_field=BooleanField()
            ),
            saniyesi=Case(
                When(derece_saniye__isnull=True, then=Value(999999.0)),
                When(derece_saniye__lte=0, then=Value(999999.0)),
                default=F('derece_saniye'),
                output_field=FloatField()
            ),
            sira_int=Case(
                When(sira='', then=Value(9999)),
                When(sira__isnull=True, then=Value(9999)),
                When(Q(sira__icontains='disk') | Q(sira__icontains='dq') | Q(sira__startswith='SW'), then=Value(9999)),
                default=Cast('sira', IntegerField()),
                output_field=IntegerField()
            )
        ).order_by('yaris_no_int', 'yas_int', 'derece_kategori', 'saniyesi', 'sira_int', 'seri', 'kulvar')

        per_page = 250 if secili_yaris_no else 50
        paginator = Paginator(sonuclar_qs, per_page)
        page_number = request.GET.get('page')
        page_obj = paginator.get_page(page_number)
        total_count = paginator.count

    context = {
        'event': event,
        'event_toplam_yaris': event_toplam_yaris,
        'event_toplam_sporcu': event_toplam_sporcu,
        'page_obj': page_obj,
        'total_races': total_count,
        'completed_count': completed_count,
        'pending_count': pending_count,
        'yaris_nolari': yaris_programi,
        'yaris_programi': yaris_programi,
        'toplam_biten_yaris': toplam_biten_yaris,
        'toplam_canli_yaris': toplam_canli_yaris,
        'toplam_bekleyen_yaris': toplam_bekleyen_yaris,
        'secili_yaris_detay': secili_yaris_detay,
        'canli_yaris': canli_yaris,
        'katilan_kulupler': katilan_kulupler,
        'katilan_sporcular': [],
        'secili_yaris_no': secili_yaris_no,
        'secili_durum': secili_durum,
        'secili_kulup': int(secili_kulup) if secili_kulup.isdigit() else '',
        'secili_kulup_obj': secili_kulup_obj,
        'kulup_toplam_yaris_sayisi': kulup_toplam_yaris_sayisi,
        'kulup_toplam_sporcu_sayisi': kulup_toplam_sporcu_sayisi,
        'kulup_katilinan_yaris_sayisi': kulup_katilinan_yaris_sayisi,
        'secili_sporcu': int(secili_sporcu) if secili_sporcu.isdigit() else '',
    }

    # HTMX kısmi yanıt desteği (SPA akıcılığı)
    if request.headers.get('HX-Request'):
        if target in ('programContent', '#programContent'):
            return render(request, 'sonuclar/partials/musabaka_program_partial.html', context)
        if target in ('sonuclarContent', '#sonuclarContent'):
            return render(request, 'sonuclar/partials/musabaka_sonuclar_partial.html', context)
        return render(request, 'sonuclar/partials/musabaka_sonuclar_modal_content.html', context)

    return render(request, 'sonuclar/musabaka_detay.html', context)

def musabaka_sporcu_modal(request, event_id, sporcu_id):
    """Müsabaka detay ve analiz sayfalarında sporcuya tıklandığında HTMX ile sporcu analiz modalı getirir."""
    event = get_object_or_404(Event, pk=event_id)
    sporcu = get_object_or_404(Sporcu, pk=sporcu_id)

    # Sporcunun sadece bu müsabakadaki yarışları
    sonuclar = (
        YarisSonucu.objects.filter(event=event, sporcu=sporcu)
        .select_related('kulup')
        .annotate(
            yaris_no_int=Cast('yaris_no', IntegerField()),
            saniyesi=Case(
                When(derece_saniye__isnull=True, then=Value(999999.0)),
                When(derece_saniye__lte=0, then=Value(999999.0)),
                default=F('derece_saniye'),
                output_field=FloatField()
            )
        )
        .order_by('yaris_no_int', 'saniyesi')
    )

    sonuclar_list = list(sonuclar)
    kulup = sonuclar_list[0].kulup if sonuclar_list else None
    toplam_yaris = len(sonuclar_list)

    # Müsabaka yılı ve sporcu yaşı
    event_year = None
    if event.yaris_tarihi_baslangic and len(event.yaris_tarihi_baslangic) >= 4 and event.yaris_tarihi_baslangic[:4].isdigit():
        event_year = int(event.yaris_tarihi_baslangic[:4])
    elif event.yaris_tarihi_ham:
        m = re.search(r'\b(20\d{2})\b', event.yaris_tarihi_ham)
        if m:
            event_year = int(m.group(1))
    if not event_year:
        event_year = timezone.now().year

    sporcu_yasi = (event_year - sporcu.dogum_yili) if sporcu.dogum_yili else None

    # Sporcuya Özel Müsabaka Performans & Gelişim Analizi
    puanli_sonuclar = [r for r in sonuclar_list if r.puan and r.puan > 0]
    toplam_puan = sum(r.puan for r in puanli_sonuclar)
    ort_puan = round(toplam_puan / len(puanli_sonuclar), 1) if puanli_sonuclar else 0
    best_race = max(puanli_sonuclar, key=lambda r: r.puan, default=None)
    max_puan = best_race.puan if best_race else 0

    altin_sayisi = sum(1 for r in sonuclar_list if str(r.sira).strip() == '1')
    gumus_sayisi = sum(1 for r in sonuclar_list if str(r.sira).strip() == '2')
    bronz_sayisi = sum(1 for r in sonuclar_list if str(r.sira).strip() == '3')
    baraj_sayisi = sum(1 for r in sonuclar_list if r.baraj and str(r.baraj).strip().upper() not in ('HAYIR', 'GEÇMEDİ', 'GECMEDI', 'YOK', '-'))

    # Giriş vs Çıkış Derece Analizi
    gelistiren_count = 0
    gerileyen_count = 0
    toplam_fark = 0.0

    for r in sonuclar_list:
        g_raw = (r.giris_derecesi or '').strip()
        if g_raw.upper() in ('NT', 'NT.', 'DERECE YOK', '-'):
            r.fark_durum = 'nt'
        elif g_raw and r.derece_saniye and r.derece_saniye > 0:
            g_sn = _time_to_seconds(g_raw)
            if g_sn and g_sn > 0:
                fark = round(r.derece_saniye - g_sn, 2)
                yuzde = round(((g_sn - r.derece_saniye) / g_sn) * 100, 1)
                r.fark_saniye = fark
                r.fark_yuzde = yuzde
                toplam_fark += fark
                if fark < 0:
                    r.fark_durum = 'gelisti'
                    gelistiren_count += 1
                elif fark > 0:
                    r.fark_durum = 'geriledi'
                    gerileyen_count += 1
                else:
                    r.fark_durum = 'ayni'
            else:
                r.fark_durum = 'nt'
        else:
            r.fark_durum = 'yok'

    karsilastirilan = gelistiren_count + gerileyen_count
    gelisim_orani = round((gelistiren_count / karsilastirilan) * 100, 1) if karsilastirilan > 0 else 0
    toplam_kazanc = round(toplam_fark, 2)

    context = {
        'event': event,
        'sporcu': sporcu,
        'kulup': kulup,
        'sonuclar': sonuclar_list,
        'sporcu_yasi': sporcu_yasi,
        'toplam_yaris': toplam_yaris,
        'toplam_puan': toplam_puan,
        'ort_puan': ort_puan,
        'max_puan': max_puan,
        'best_race': best_race,
        'altin_sayisi': altin_sayisi,
        'gumus_sayisi': gumus_sayisi,
        'bronz_sayisi': bronz_sayisi,
        'baraj_sayisi': baraj_sayisi,
        'gelistiren_count': gelistiren_count,
        'gerileyen_count': gerileyen_count,
        'gelisim_orani': gelisim_orani,
        'toplam_kazanc': toplam_kazanc,
        'has_gelisim': (karsilastirilan > 0),
    }
    return render(request, 'sonuclar/partials/sporcu_musabaka_modal.html', context)


def musabaka_kulup_modal(request, event_id, kulup_id):
    """Müsabaka detay ve analiz sayfalarında kulübe tıklandığında HTMX ile o takıma özel analiz modalı getirir."""
    event = get_object_or_404(Event, pk=event_id)
    kulup = get_object_or_404(Kulup, pk=kulup_id)

    # 1. Kulübün bu müsabakadaki tüm yarış sonuçları
    qs = (
        YarisSonucu.objects.filter(event=event, kulup=kulup)
        .select_related('sporcu')
        .annotate(
            yaris_no_int=Cast('yaris_no', IntegerField()),
            saniyesi=Case(
                When(derece_saniye__isnull=True, then=Value(999999.0)),
                When(derece_saniye__lte=0, then=Value(999999.0)),
                default=F('derece_saniye'),
                output_field=FloatField()
            )
        )
        .order_by('yaris_no_int', 'saniyesi')
    )

    sonuclar_list = list(qs)
    toplam_yaris = len(sonuclar_list)

    # 2. FINA ve Madalya İstatistikleri
    puanli_sonuclar = [r for r in sonuclar_list if r.puan and r.puan > 0]
    toplam_puan = sum(r.puan for r in puanli_sonuclar)
    ort_puan = round(toplam_puan / len(puanli_sonuclar), 1) if puanli_sonuclar else 0
    max_puan = max((r.puan for r in puanli_sonuclar), default=0)

    altin_sayisi = sum(1 for r in sonuclar_list if str(r.sira).strip() == '1')
    gumus_sayisi = sum(1 for r in sonuclar_list if str(r.sira).strip() == '2')
    bronz_sayisi = sum(1 for r in sonuclar_list if str(r.sira).strip() == '3')
    baraj_sayisi = sum(1 for r in sonuclar_list if r.baraj and str(r.baraj).strip().upper() not in ('HAYIR', 'GEÇMEDİ', 'GECMEDI', 'YOK', '-'))

    # 3. Giriş vs Çıkış (Seed vs Finish) Zaman Gelişimi
    gelistiren_count = 0
    gerileyen_count = 0
    toplam_fark = 0.0

    for r in sonuclar_list:
        g_raw = (r.giris_derecesi or '').strip()
        if g_raw.upper() in ('NT', 'NT.', 'DERECE YOK', '-'):
            r.fark_durum = 'nt'
        elif g_raw and r.derece_saniye and r.derece_saniye > 0:
            g_sn = _time_to_seconds(g_raw)
            if g_sn and g_sn > 0:
                fark = round(r.derece_saniye - g_sn, 2)
                yuzde = round(((g_sn - r.derece_saniye) / g_sn) * 100, 1)
                r.fark_saniye = fark
                r.fark_yuzde = yuzde
                toplam_fark += fark
                if fark < 0:
                    r.fark_durum = 'gelisti'
                    gelistiren_count += 1
                elif fark > 0:
                    r.fark_durum = 'geriledi'
                    gerileyen_count += 1
                else:
                    r.fark_durum = 'ayni'
            else:
                r.fark_durum = 'nt'
        else:
            r.fark_durum = 'yok'

    karsilastirilan = gelistiren_count + gerileyen_count
    gelisim_orani = round((gelistiren_count / karsilastirilan) * 100, 1) if karsilastirilan > 0 else 0
    ort_fark = round(toplam_fark / karsilastirilan, 2) if karsilastirilan > 0 else 0

    # 4. Sporcu Bazlı Performans Dağılımı (Kadro Başarısı)
    sporcu_dict = {}
    for r in sonuclar_list:
        sp = r.sporcu
        if sp.id not in sporcu_dict:
            sporcu_dict[sp.id] = {
                'sporcu': sp,
                'yaris_sayisi': 0,
                'toplam_puan': 0,
                'max_puan': 0,
                'best_race': '',
                'gelistiren': 0,
                'altin': 0,
                'gumus': 0,
                'bronz': 0,
            }
        entry = sporcu_dict[sp.id]
        entry['yaris_sayisi'] += 1
        p = r.puan or 0
        entry['toplam_puan'] += p
        if p > entry['max_puan']:
            entry['max_puan'] = p
            entry['best_race'] = f"{r.mesafe}m {r.stil} ({r.derece})"
        if getattr(r, 'fark_durum', '') == 'gelisti':
            entry['gelistiren'] += 1
        s_val = str(r.sira).strip()
        if s_val == '1':
            entry['altin'] += 1
        elif s_val == '2':
            entry['gumus'] += 1
        elif s_val == '3':
            entry['bronz'] += 1

    athletes_list = sorted(sporcu_dict.values(), key=lambda x: (x['max_puan'], x['toplam_puan']), reverse=True)
    toplam_sporcu = len(athletes_list)
    mvp_athlete = athletes_list[0] if athletes_list else None

    context = {
        'event': event,
        'kulup': kulup,
        'sonuclar': sonuclar_list,
        'toplam_yaris': toplam_yaris,
        'toplam_sporcu': toplam_sporcu,
        'toplam_puan': toplam_puan,
        'ort_puan': ort_puan,
        'max_puan': max_puan,
        'altin_sayisi': altin_sayisi,
        'gumus_sayisi': gumus_sayisi,
        'bronz_sayisi': bronz_sayisi,
        'baraj_sayisi': baraj_sayisi,
        'gelistiren_count': gelistiren_count,
        'gerileyen_count': gerileyen_count,
        'gelisim_orani': gelisim_orani,
        'ort_fark': ort_fark,
        'has_gelisim': (karsilastirilan > 0),
        'athletes_list': athletes_list,
        'mvp_athlete': mvp_athlete,
    }
    return render(request, 'sonuclar/partials/kulup_musabaka_modal.html', context)


def musabaka_analiz(request, pk):
    """Müsabaka ve yarış bazlı FINA puanı & kulüp/sporcu performans analizi."""
    event = get_object_or_404(Event, pk=pk)

    secili_yaris_no = request.GET.get('yaris_no', '').strip()
    cinsiyet_filtre = request.GET.get('cinsiyet', '').strip()

    # 1. Yarış Programı (Dropdown seçimi için tek hızlı GROUP BY)
    races_qs = (
        event.yaris_sonuclari.exclude(yaris_no__isnull=True).exclude(yaris_no='')
        .values('yaris_no', 'mesafe', 'stil', 'cinsiyet', 'yas_grubu')
        .annotate(
            toplam=Count('id'),
            puanli_sayisi=Count('id', filter=Q(puan__gt=0))
        )
    )

    yaris_dict = {}
    for r in races_qs:
        yno = str(r['yaris_no']).strip()
        if not yno:
            continue
        if yno not in yaris_dict:
            yaris_dict[yno] = {
                'yaris_no': yno,
                'mesafe': r['mesafe'],
                'stil': (r['stil'] or '').strip(),
                'cinsiyet': (r['cinsiyet'] or '').strip(),
                'yas_grubu': (r['yas_grubu'] or '').strip(),
                'toplam': r['toplam'],
                'puanli_sayisi': r['puanli_sayisi'],
            }
        else:
            yaris_dict[yno]['toplam'] += r['toplam']
            yaris_dict[yno]['puanli_sayisi'] += r['puanli_sayisi']

    yaris_programi = list(yaris_dict.values())
    def _sort_yaris(x):
        try:
            return int(x['yaris_no'])
        except (ValueError, TypeError):
            return 9999
    yaris_programi.sort(key=_sort_yaris)

    secili_yaris_detay = next((y for y in yaris_programi if y['yaris_no'] == secili_yaris_no), None)

    # 2. Ana Filtreleme (Base Queryset)
    base_qs = event.yaris_sonuclari.all()
    if secili_yaris_no:
        base_qs = base_qs.filter(yaris_no=secili_yaris_no)
    if cinsiyet_filtre == 'E':
        base_qs = base_qs.filter(cinsiyet__istartswith='E')
    elif cinsiyet_filtre == 'K':
        base_qs = base_qs.filter(cinsiyet__istartswith='K')

    puan_qs = base_qs.filter(puan__gt=0)

    # 3. KPI İstatistikleri (Tek Aggregate Sorgusu - O(1) hızında)
    agg_stats = puan_qs.aggregate(
        toplam_puan=Sum('puan'),
        ort_puan=Avg('puan'),
        max_puan=Max('puan'),
        toplam_derece=Count('id'),
    )

    toplam_puan = agg_stats['toplam_puan'] or 0
    ort_puan = round(agg_stats['ort_puan'], 1) if agg_stats['ort_puan'] else 0
    max_puan = agg_stats['max_puan'] or 0
    toplam_derece = agg_stats['toplam_derece'] or 0

    toplam_sporcu = base_qs.values('sporcu_id').distinct().count()
    toplam_kulup = base_qs.exclude(kulup__isnull=True).values('kulup_id').distinct().count()

    # Baraj istatistiği
    baraj_gecenler = base_qs.exclude(
        Q(baraj__isnull=True) | Q(baraj='') | Q(baraj='-') | Q(baraj__iexact='HAYIR') | Q(baraj__iexact='GEÇMEDİ') | Q(baraj__iexact='GECMEDI') | Q(baraj__iexact='YOK')
    ).count()

    # 4. MVP / Zirve Performanslar (Top 3)
    mvp_list = list(
        puan_qs.select_related('sporcu', 'kulup')
        .order_by('-puan')[:3]
    )

    # 5. Kulüp Sıralaması (Ortalama veya Toplam FINA Puanı - Varsayılan: Ortalama, Min. 3 Sporcu)
    kulup_sirala = request.GET.get('kulup_sirala', 'ortalama').strip()
    if kulup_sirala not in ('ortalama', 'toplam'):
        kulup_sirala = 'ortalama'

    min_sporcu_param = request.GET.get('min_sporcu', '3').strip()
    try:
        min_sporcu = int(min_sporcu_param)
    except ValueError:
        min_sporcu = 3

    order_fields = ('-ort_puan', '-toplam_puan') if kulup_sirala == 'ortalama' else ('-toplam_puan', '-ort_puan')
    club_qs = (
        puan_qs.exclude(kulup__isnull=True)
        .values('kulup_id', 'kulup__kulup_adi')
        .annotate(
            toplam_puan=Sum('puan'),
            ort_puan=Avg('puan'),
            yaris_sayisi=Count('id'),
            sporcu_sayisi=Count('sporcu_id', distinct=True),
            birincilik=Count('id', filter=Q(sira='1')),
            ikincilik=Count('id', filter=Q(sira='2')),
            ucunculuk=Count('id', filter=Q(sira='3')),
        )
    )

    # 1-2 yarışçısı olan kulüpleri filtrele (En az 3 yarışçı)
    if min_sporcu > 1:
        filtered_qs = club_qs.filter(sporcu_sayisi__gte=min_sporcu)
        if filtered_qs.exists():
            club_qs = filtered_qs
        else:
            min_sporcu = 1

    club_rankings = list(club_qs.order_by(*order_fields)[:30])

    if kulup_sirala == 'ortalama':
        max_benchmark = max((c['ort_puan'] for c in club_rankings), default=1) or 1
        for i, c in enumerate(club_rankings, 1):
            c['sira'] = i
            c['ort_puan'] = round(c['ort_puan'], 1) if c['ort_puan'] else 0
            c['oran'] = round((c['ort_puan'] / max_benchmark) * 100, 1)
    else:
        max_benchmark = club_rankings[0]['toplam_puan'] if club_rankings and club_rankings[0]['toplam_puan'] else 1
        for i, c in enumerate(club_rankings, 1):
            c['sira'] = i
            c['ort_puan'] = round(c['ort_puan'], 1) if c['ort_puan'] else 0
            c['oran'] = round((c['toplam_puan'] / max_benchmark) * 100, 1)

    # 6. En İyi Performanslar (En yüksek FINA puanlı dereceler)
    en_iyi_genel = list(
        puan_qs.select_related('sporcu', 'kulup')
        .order_by('-puan')[:15]
    )
    en_iyi_erkekler = list(
        puan_qs.filter(cinsiyet__istartswith='E')
        .select_related('sporcu', 'kulup')
        .order_by('-puan')[:10]
    )
    en_iyi_kadinlar = list(
        puan_qs.filter(cinsiyet__istartswith='K')
        .select_related('sporcu', 'kulup')
        .order_by('-puan')[:10]
    )

    # 7. Tekil Yarış Seçilmişse Kürsü (Podium) ve Tüm Sonuçlar
    yaris_podium = []
    tekil_yaris_sonuclari = []
    if secili_yaris_no:
        yaris_podium = list(
            base_qs.filter(derece_saniye__gt=0)
            .exclude(sira__icontains='disk').exclude(sira__icontains='dq').exclude(sira__icontains='dns').exclude(sira__icontains='dnf')
            .exclude(derece__icontains='disk').exclude(derece__icontains='dq').exclude(derece__icontains='dns').exclude(derece__icontains='dnf')
            .select_related('sporcu', 'kulup')
            .order_by('derece_saniye')[:3]
        )
        tekil_yaris_sonuclari = list(
            base_qs.select_related('sporcu', 'kulup')
            .order_by(
                Case(
                    When(derece_saniye__isnull=False, derece_saniye__gt=0, then=F('derece_saniye')),
                    default=Value(99999.0),
                    output_field=FloatField()
                ),
                '-puan'
            )[:100]
        )

    # 8. Giriş Derecesi vs Çıkış Derecesi (Seed vs Finish) Karşılaştırmalı Gelişim Analizi
    giris_qs = (
        base_qs.filter(derece_saniye__gt=0)
        .exclude(giris_derecesi__isnull=True).exclude(giris_derecesi='')
        .select_related('sporcu', 'kulup')
    )

    gelistiren_count = 0
    gerileyen_count = 0
    ayni_count = 0
    nt_count = 0
    toplam_fark_sn = 0.0

    gelisen_sporcular = []
    club_gelisim_dict = defaultdict(lambda: {'kulup_id': None, 'kulup_adi': '', 'toplam': 0, 'gelistiren': 0, 'toplam_fark': 0.0, 'sporcular': set()})

    for r in giris_qs:
        g_raw = (r.giris_derecesi or '').strip()
        if g_raw.upper() in ('NT', 'NT.', 'DERECE YOK', '-'):
            nt_count += 1
            continue

        g_sn = _time_to_seconds(g_raw)
        if not g_sn or g_sn <= 0:
            nt_count += 1
            continue

        d_sn = r.derece_saniye
        fark = round(d_sn - g_sn, 2)
        yuzde = round(((g_sn - d_sn) / g_sn) * 100, 1)

        toplam_fark_sn += fark

        kid = r.kulup_id or 0
        k_adi = r.kulup.kulup_adi if r.kulup else 'Ferdi'
        c_entry = club_gelisim_dict[kid]
        c_entry['kulup_id'] = kid
        c_entry['kulup_adi'] = k_adi
        c_entry['toplam'] += 1
        c_entry['toplam_fark'] += fark
        c_entry['sporcular'].add(r.sporcu_id)

        if fark < 0:
            gelistiren_count += 1
            c_entry['gelistiren'] += 1
            gelisen_sporcular.append({
                'sporcu': r.sporcu,
                'kulup': r.kulup,
                'mesafe': r.mesafe,
                'stil': r.stil,
                'cinsiyet': r.cinsiyet,
                'giris_derecesi': r.giris_derecesi,
                'derece': r.derece,
                'fark': fark,
                'fark_abs': abs(fark),
                'yuzde': yuzde,
                'puan': r.puan,
            })
        elif fark > 0:
            gerileyen_count += 1
        else:
            ayni_count += 1

    toplam_karsilastirilan = gelistiren_count + gerileyen_count + ayni_count
    has_giris_analizi = (toplam_karsilastirilan > 0)
    gelisim_orani = round((gelistiren_count / toplam_karsilastirilan) * 100, 1) if toplam_karsilastirilan > 0 else 0
    gerileme_orani = round((gerileyen_count / toplam_karsilastirilan) * 100, 1) if toplam_karsilastirilan > 0 else 0
    ort_fark = round(toplam_fark_sn / toplam_karsilastirilan, 2) if toplam_karsilastirilan > 0 else 0

    # En çok derece düşüren ilk 15 performans
    gelisen_sporcular.sort(key=lambda x: x['fark'])
    en_cok_gelistirenler = gelisen_sporcular[:15]

    # Kulüp gelişim sıralaması (en yüksek gelişim başarı oranı, en az min_sporcu yarışçı)
    club_gelisim_list = []
    for kid, c_data in club_gelisim_dict.items():
        if len(c_data['sporcular']) >= min_sporcu:
            c_data['sporcu_sayisi'] = len(c_data['sporcular'])
            c_data['oran'] = round((c_data['gelistiren'] / c_data['toplam']) * 100, 1)
            c_data['ort_fark'] = round(c_data['toplam_fark'] / c_data['toplam'], 2)
            club_gelisim_list.append(c_data)

    club_gelisim_list.sort(key=lambda x: (x['oran'], x['gelistiren']), reverse=True)

    # Tekil yarış sonuçlarına da fark hesaplamalarını ekle
    if secili_yaris_no and tekil_yaris_sonuclari:
        for r in tekil_yaris_sonuclari:
            g_raw = (r.giris_derecesi or '').strip()
            if g_raw.upper() in ('NT', 'NT.', 'DERECE YOK', '-'):
                r.fark_durum = 'nt'
            elif g_raw and r.derece_saniye and r.derece_saniye > 0:
                g_sn = _time_to_seconds(g_raw)
                if g_sn and g_sn > 0:
                    fark = round(r.derece_saniye - g_sn, 2)
                    yuzde = round(((g_sn - r.derece_saniye) / g_sn) * 100, 1)
                    r.fark_saniye = fark
                    r.fark_yuzde = yuzde
                    if fark < 0:
                        r.fark_durum = 'gelisti'
                    elif fark > 0:
                        r.fark_durum = 'geriledi'
                    else:
                        r.fark_durum = 'ayni'
                else:
                    r.fark_durum = 'nt'
            else:
                r.fark_durum = 'yok'

    context = {
        'event': event,
        'yaris_programi': yaris_programi,
        'secili_yaris_no': secili_yaris_no,
        'secili_yaris_detay': secili_yaris_detay,
        'cinsiyet_filtre': cinsiyet_filtre,
        'toplam_puan': toplam_puan,
        'ort_puan': ort_puan,
        'max_puan': max_puan,
        'toplam_derece': toplam_derece,
        'toplam_sporcu': toplam_sporcu,
        'toplam_kulup': toplam_kulup,
        'baraj_gecenler': baraj_gecenler,
        'mvp_list': mvp_list,
        'club_rankings': club_rankings,
        'kulup_sirala': kulup_sirala,
        'min_sporcu': min_sporcu,
        'en_iyi_genel': en_iyi_genel,
        'en_iyi_erkekler': en_iyi_erkekler,
        'en_iyi_kadinlar': en_iyi_kadinlar,
        'yaris_podium': yaris_podium,
        'tekil_yaris_sonuclari': tekil_yaris_sonuclari,
        'has_giris_analizi': has_giris_analizi,
        'toplam_karsilastirilan': toplam_karsilastirilan,
        'gelistiren_count': gelistiren_count,
        'gerileyen_count': gerileyen_count,
        'ayni_count': ayni_count,
        'nt_count': nt_count,
        'gelisim_orani': gelisim_orani,
        'gerileme_orani': gerileme_orani,
        'ort_fark': ort_fark,
        'en_cok_gelistirenler': en_cok_gelistirenler,
        'club_gelisim_list': club_gelisim_list,
    }

    if request.headers.get('HX-Request'):
        return render(request, 'sonuclar/partials/musabaka_analiz_content.html', context)

    return render(request, 'sonuclar/musabaka_analiz.html', context)



@csrf_exempt
def api_canli_startlist_sporculari(request):
    """
    Belirli bir müsabaka ve yarış no için start listesindeki sporcuları döner.
    Gemini sonuç listesini ayrıştırırken bu ID'leri kullanarak doğrudan eşleştirir.
    Parametreler (GET):
        event_id veya canli_url veya musabaka_adi
        yaris_no (ör: 1)
    """
    event_id = request.GET.get('event_id')
    canli_url = request.GET.get('canli_url', '').strip()
    musabaka_adi = request.GET.get('musabaka_adi', '').strip()
    yaris_no = request.GET.get('yaris_no', '').strip()

    qs = YarisSonucu.objects.all()

    if event_id and str(event_id).isdigit():
        canli_match = CanliYaris.objects.filter(id=int(event_id)).first()
        if canli_match and canli_match.event_id:
            qs = qs.filter(event_id=canli_match.event_id)
        else:
            qs = qs.filter(event_id=int(event_id))
    elif canli_url:
        canli = CanliYaris.objects.filter(canli_url=canli_url).first()
        if canli and canli.event_id:
            qs = qs.filter(event_id=canli.event_id)
        elif canli and canli.musabaka_adi:
            qs = qs.filter(event__musabaka_adi=canli.musabaka_adi)
    elif musabaka_adi:
        qs = qs.filter(event__musabaka_adi=musabaka_adi)
    else:
        return JsonResponse({"durum": "hata", "mesaj": "event_id, canli_url veya musabaka_adi parametresi gereklidir."}, status=400)

    if yaris_no:
        qs = qs.filter(yaris_no=yaris_no)

    sporcular_list = []
    for r in qs.select_related('sporcu', 'kulup').order_by('seri', 'kulvar', 'id'):
        sporcular_list.append({
            "id": r.id,  # YarisSonucu ID
            "sporcu_adi": r.sporcu.sporcu_adi,
            "kulup_adi": r.kulup.kulup_adi if r.kulup else "",
            "dogum_yili": r.sporcu.dogum_yili,
            "cinsiyet": r.cinsiyet or r.sporcu.cinsiyet,
            "seri": r.seri,
            "kulvar": r.kulvar,
            "giris_derecesi": r.giris_derecesi,
            "mevcut_derece": r.derece
        })

    return JsonResponse({
        "durum": "basarili",
        "yaris_no": yaris_no,
        "toplam": len(sporcular_list),
        "sporcular": sporcular_list
    }, json_dumps_params={'ensure_ascii': False})


@csrf_exempt
def api_canli_dosya_kontrol(request):
    """
    Belirli bir dosyanın (PDF) daha önce işlenip işlenmediğini ve mevcut hash/etag durumunu döner.
    Eğer dosya_adi verilmezse, o event_id / canli_url'ye ait tüm işlenmiş dosyaların haritasını döner.
    Runner gereksiz indirme ve Gemini çağırmayı bu sayede önler.
    GET query param veya POST JSON body destekler.
    """
    params = {}
    if request.method == "POST":
        try:
            params = json.loads(request.body.decode("utf-8"))
        except Exception:
            params = request.POST.dict()
    else:
        params = request.GET.dict()

    dosya_adi = params.get('dosya_adi', '').strip()
    event_id = params.get('event_id') or params.get('canli_yaris_id')
    canli_url = params.get('canli_url', '').strip()
    req_etag = (params.get('etag') or '').strip().strip('"')
    req_last_modified = (params.get('last_modified') or '').strip()

    canli_match = None
    target_eid = None
    if event_id and str(event_id).isdigit():
        canli_match = CanliYaris.objects.filter(id=int(event_id)).first()
        if canli_match and canli_match.event_id:
            target_eid = canli_match.event_id
        else:
            target_eid = int(event_id)
    elif canli_url:
        canli_match = CanliYaris.objects.filter(canli_url=canli_url).first()
        if canli_match and canli_match.event_id:
            target_eid = canli_match.event_id

    # TOPLU KONTROL: dosya_adi belirtilmemişse o yarışa ait bilinen tüm dosyaların sözlüğünü döner
    if not dosya_adi:
        if target_eid or canli_match:
            from django.db.models import Q
            q_filter = Q()
            if target_eid:
                q_filter |= Q(event_id=target_eid)
            if canli_match:
                q_filter |= Q(canli_yaris=canli_match)

            dosyalar = CanliYarisDosya.objects.filter(q_filter).values(
                "dosya_adi", "etag", "dosya_boyutu", "durum", "last_modified", "kayit_sayisi"
            )
            dosyalar_map = {d["dosya_adi"]: d for d in dosyalar}
            return JsonResponse({
                "durum": "basarili",
                "toplam": len(dosyalar_map),
                "dosyalar": dosyalar_map
            })
        return JsonResponse({"durum": "hata", "mesaj": "dosya_adi veya event_id parametresi gereklidir."}, status=400)

    # TEKİL DOSYA KONTROLÜ (ETag ve Last-Modified ile değişim kontrolü)
    qs = CanliYarisDosya.objects.filter(dosya_adi=dosya_adi)
    if target_eid:
        qs = qs.filter(event_id=target_eid)

    dosya = qs.first()
    if not dosya:
        return JsonResponse({"durum": "bulunamadi", "islenmis_mi": False, "degisti_mi": True})

    is_done = (dosya.durum == 'ISLENDI')
    degisti_mi = True
    if is_done:
        known_etag = (dosya.etag or '').strip().strip('"')
        known_lm = (dosya.last_modified or '').strip()
        if req_etag and known_etag:
            degisti_mi = (req_etag != known_etag)
        elif req_last_modified and known_lm:
            degisti_mi = (req_last_modified != known_lm)
        else:
            degisti_mi = False

    return JsonResponse({
        "durum": "basarili",
        "islenmis_mi": is_done,
        "islendi_mi": is_done,
        "degisti_mi": degisti_mi,
        "etag": dosya.etag,
        "content_hash": dosya.content_hash,
        "last_modified": dosya.last_modified,
        "kayit_sayisi": dosya.kayit_sayisi
    })






