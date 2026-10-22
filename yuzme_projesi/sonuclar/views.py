# -*- coding: utf-8 -*-
import json
import difflib
import re
import threading
from django.shortcuts import render, get_object_or_404, redirect
from django.contrib import messages
from django.utils import timezone
from django.core.paginator import Paginator
from django.db.models import Q, Count
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from .models import Kulup, Sporcu, SporcuKulupTarihce, YarisSonucu, CanliYaris, is_school_team
from .athlete_matcher import match_athlete


def is_school_meet(meet_name: str) -> bool:
    """Yarış/müsabaka adının Okul Sporları müsabakası olup olmadığını belirler."""
    if not meet_name:
        return False
    ml = meet_name.lower()
    return bool(re.search(r'(?:okul\s*spor|okulspor|okullar|meb)', ml))


def index(request):
    """Ana sayfa - Özet istatistikler ve popüler içerikler."""
    toplam_sporcu = Sporcu.objects.count()
    toplam_kulup = Kulup.objects.count()
    toplam_yaris = YarisSonucu.objects.count()
    toplam_transfer = SporcuKulupTarihce.objects.count()

    # En çok yarışa katılan sporcular
    en_cok_yarisan_sporcular = Sporcu.objects.select_related('birincil_kulup').order_by('-toplam_yaris_sayisi')[:8]

    # En çok sporcusu olan kulüpler
    en_buyuk_kulupler = Kulup.objects.order_by('-toplam_sporcu_sayisi')[:8]

    # Son müsabaka adları
    son_yarismalar = (
        YarisSonucu.objects
        .filter(musabaka_adi__isnull=False)
        .exclude(musabaka_adi="")
        .values('musabaka_adi', 'sehir', 'yaris_tarihi_baslangic')
        .distinct()
        .order_by('-yaris_tarihi_baslangic')[:6]
    )

    context = {
        'toplam_sporcu': toplam_sporcu,
        'toplam_kulup': toplam_kulup,
        'toplam_yaris': toplam_yaris,
        'toplam_transfer': toplam_transfer,
        'en_cok_yarisan_sporcular': en_cok_yarisan_sporcular,
        'en_buyuk_kulupler': en_buyuk_kulupler,
        'son_yarismalar': son_yarismalar,
    }
    return render(request, 'sonuclar/index.html', context)


def sporcu_listesi(request):
    """Sporcuların listesi, araması ve filtrelemesi."""
    q = request.GET.get('q', '').strip()
    cinsiyet = request.GET.get('cinsiyet', '').strip()
    kulup_adi = request.GET.get('kulup', '').strip()

    qs = Sporcu.objects.select_related('birincil_kulup')

    if q:
        qs = qs.filter(sporcu_adi__icontains=q)
    if cinsiyet in ('ERKEK', 'KADIN'):
        qs = qs.filter(cinsiyet=cinsiyet)
    if kulup_adi:
        qs = qs.filter(birincil_kulup__kulup_adi__icontains=kulup_adi)

    # Sıralama
    sirala = request.GET.get('sirala', 'isim')
    if sirala == 'yaris':
        qs = qs.order_by('-toplam_yaris_sayisi')
    elif sirala == 'tarih':
        qs = qs.order_by('-son_yaris_tarihi')
    else:
        qs = qs.order_by('sporcu_adi')

    paginator = Paginator(qs, 40)
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)

    context = {
        'page_obj': page_obj,
        'q': q,
        'cinsiyet': cinsiyet,
        'kulup_adi': kulup_adi,
        'sirala': sirala,
        'total_count': paginator.count,
    }
    return render(request, 'sonuclar/sporcu_listesi.html', context)


def sporcu_detay(request, pk):
    """Sporcu detay sayfası: Profil, Kulüp Tarihçesi, En İyi Dereceler (PB) ve Kategori/Mesafe filtreli Yarış Sonuçları."""
    sporcu = get_object_or_404(Sporcu.objects.select_related('birincil_kulup'), pk=pk)

    # Kulüp Transfer Tarihçesi
    tarihce = sporcu.kulup_tarihcesi.select_related('kulup').order_by('donem_sirasi')

    # Kişisel En İyi Dereceler (PB)
    pbs = sporcu.en_iyi_dereceler()

    # Kategori (Stil) ve Mesafe Filtreleri
    kategori = (request.GET.get('kategori') or request.GET.get('stil') or '').strip()
    mesafe_raw = request.GET.get('mesafe', '').strip()
    sirala = request.GET.get('sirala', 'tarih_desc')

    sonuclar_qs = sporcu.yaris_sonuclari.select_related('kulup')

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
        sonuclar_qs = sonuclar_qs.order_by('derece_saniye', '-yaris_tarihi_baslangic')
    elif sirala == 'tarih_asc':
        sonuclar_qs = sonuclar_qs.order_by('yaris_tarihi_baslangic', 'id')
    else:
        sonuclar_qs = sonuclar_qs.order_by('-yaris_tarihi_baslangic', '-id')

    total_filtered_races = sonuclar_qs.count()
    paginator = Paginator(sonuclar_qs, 30)
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)

    mevcut_stiller = ['Serbest', 'Sırtüstü', 'Kurbağalama', 'Kelebek', 'Karışık']
    mevcut_mesafeler = [50, 100, 200, 400, 800, 1500]

    son_yaris = sporcu.yaris_sonuclari.order_by('-yaris_tarihi_baslangic', '-id').first()

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
    }
    return render(request, 'sonuclar/sporcu_detay.html', context)


def kulup_listesi(request):
    """Kulüpler listesi ve arama."""
    q = request.GET.get('q', '').strip()
    sirala = request.GET.get('sirala', 'yaris')

    qs = Kulup.objects.all()

    if q:
        qs = qs.filter(kulup_adi__icontains=q)

    if sirala == 'sporcu':
        qs = qs.order_by('-toplam_sporcu_sayisi')
    elif sirala == 'isim':
        qs = qs.order_by('kulup_adi')
    else:
        qs = qs.order_by('-toplam_yaris_sayisi')

    paginator = Paginator(qs, 40)
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)

    context = {
        'page_obj': page_obj,
        'q': q,
        'sirala': sirala,
        'total_count': paginator.count,
    }
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
    son_sonuclar = kulup.yaris_sonuclari.select_related('sporcu').order_by('-yaris_tarihi_baslangic')[:25]

    context = {
        'kulup': kulup,
        'page_obj': page_obj,
        'son_sonuclar': son_sonuclar,
        'total_swimmers': tarihce_qs.count(),
    }
    return render(request, 'sonuclar/kulup_detay.html', context)


def yaris_sonuclari_ara(request):
    """Detaylı yarış sonuçları sorgulama ve filtreleme motoru."""
    q_sporcu = request.GET.get('sporcu', '').strip()
    q_kulup = request.GET.get('kulup', '').strip()
    q_musabaka = request.GET.get('musabaka', '').strip()
    stil = request.GET.get('stil', '').strip()
    mesafe = request.GET.get('mesafe', '').strip()
    cinsiyet = request.GET.get('cinsiyet', '').strip()
    yil = request.GET.get('yil', '').strip()

    qs = YarisSonucu.objects.select_related('sporcu', 'kulup')

    if q_sporcu:
        qs = qs.filter(sporcu__sporcu_adi__icontains=q_sporcu)
    if q_kulup:
        qs = qs.filter(kulup__kulup_adi__icontains=q_kulup)
    if q_musabaka:
        qs = qs.filter(musabaka_adi__icontains=q_musabaka)
    if stil:
        qs = qs.filter(stil=stil)
    if mesafe and mesafe.isdigit():
        qs = qs.filter(mesafe=int(mesafe))
    if cinsiyet:
        qs = qs.filter(cinsiyet=cinsiyet)
    if yil and yil.isdigit():
        qs = qs.filter(yaris_tarihi_baslangic__startswith=yil)

    paginator = Paginator(qs, 50)
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)

    # Filtre seçenekleri
    stiller = ['Serbest', 'Sırtüstü', 'Kurbağalama', 'Kelebek', 'Karışık']
    mesafeler = [50, 100, 200, 400, 800, 1500]

    context = {
        'page_obj': page_obj,
        'q_sporcu': q_sporcu,
        'q_kulup': q_kulup,
        'q_musabaka': q_musabaka,
        'stil': stil,
        'mesafe': mesafe,
        'cinsiyet': cinsiyet,
        'yil': yil,
        'stiller': stiller,
        'mesafeler': mesafeler,
        'total_count': paginator.count,
    }
    return render(request, 'sonuclar/yaris_sonuclari.html', context)


def api_sporcu_ara(request):
    """Canlı arama (autocomplete) için JSON endpoint."""
    q = request.GET.get('term', '').strip() or request.GET.get('q', '').strip()
    if not q or len(q) < 2:
        return JsonResponse([], safe=False)

    results = []
    sporcular = Sporcu.objects.filter(sporcu_adi__icontains=q).select_related('birincil_kulup')[:10]
    for sp in sporcular:
        kulup_adi = sp.birincil_kulup.kulup_adi if sp.birincil_kulup else "Kulüpsüz"
        results.append({
            'id': sp.id,
            'label': f"{sp.sporcu_adi} ({sp.yas_dogum_yili} Yaş) - {kulup_adi}",
            'value': sp.sporcu_adi,
            'url': f"/sporcular/{sp.id}/"
        })
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
    yaris_tarihi = (payload.get('yaris_tarihi') or '').strip()
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

    # Bu müsabaka ve branş için var olan yarışları önbelleğe al
    existing_races_map = {}
    if musabaka_adi and mesafe and stil:
        q_init = YarisSonucu.objects.filter(musabaka_adi=musabaka_adi, mesafe=mesafe, stil=stil)
        if yaris_no:
            q_init = q_init.filter(yaris_no=yaris_no)
        for r in q_init.select_related('sporcu', 'kulup'):
            existing_races_map[r.sporcu_id] = r

    for item in kayitlar:
        sporcu_adi = (item.get('sporcu') or item.get('name') or item.get('sporcu_adi') or '').strip()
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
        baraj_val = str(item.get('baraj') or '').strip()

        # 1. Takım / Kulüp Yönetimi
        kulup, kulup_created = Kulup.objects.get_or_create(kulup_adi=kulup_adi)
        if kulup_created:
            stats['yeni_kulup'] += 1
            if kulup_adi.lower() != 'ferdi':
                if is_okul_musabakasi or is_school_meet(musabaka_adi) or is_school_team(kulup_adi):
                    kulup.okul_mu = 1
                    kulup.save(update_fields=['okul_mu'])
        elif is_okul_musabakasi or is_school_meet(musabaka_adi):
            if kulup.okul_mu == 0 and kulup_adi.lower() != 'ferdi':
                has_sk = bool(re.search(r'(?:spor\s*kul[uü]b[uü]|(?:\b|[_\s])sk\b|(?:\b|[_\s])gsk\b|(?:\b|[_\s])skd\b|y[uü]zme\s*kul[uü]b[uü]|ihtisas|derne[gğ]i|belediye\s*spor|belediyespor|kolejliler)', kulup_adi.lower()))
                if not has_sk:
                    kulup.okul_mu = 1
                    kulup.save(update_fields=['okul_mu'])

        # 2. Sporcu Yönetimi ve Akıllı Eşleştirme (match_athlete)
        sporcu = None
        match_res = match_athlete(
            name=sporcu_adi,
            birth_year_or_date=dogum_yili,
            club=kulup_adi
        )

        if match_res.get('durum') == 'basarili':
            found_id = match_res.get('bulunan_id')
            if not found_id and match_res.get('muhtemel_eslesmeler'):
                top_cand = match_res['muhtemel_eslesmeler'][0]
                if top_cand.get('benzerlik_orani', 0) >= 88.0:
                    found_id = top_cand.get('id')

            if found_id:
                try:
                    sporcu = Sporcu.objects.get(id=found_id)
                    stats['eslesen_sporcu'] += 1
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
            if musabaka_adi:
                cand_meet = cand_qs.filter(musabaka_adi=musabaka_adi)
                if yaris_no:
                    cand_y_no = cand_meet.filter(yaris_no=yaris_no)
                    if cand_y_no.exists():
                        existing_race = cand_y_no.first()
                if not existing_race and cand_meet.exists():
                    existing_race = cand_meet.first()

            if not existing_race and yaris_tarihi_baslangic:
                cand_date = cand_qs.filter(yaris_tarihi_baslangic=yaris_tarihi_baslangic)
                if yaris_no:
                    cand_d_no = cand_date.filter(yaris_no=yaris_no)
                    if cand_d_no.exists():
                        existing_race = cand_d_no.first()
                if not existing_race and cand_date.exists():
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
                    existing_race.save()
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
                        existing_race.save()
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
                        existing_race.save()
                        stats['guncellenen_sonuc'] += 1
        else:
            # YENİ YARIŞ SONUCU / START KAYDI
            yeni_derece = derece_val if tur == 'sonuc_listesi' else "Bekleniyor"
            yeni_yaris = YarisSonucu.objects.create(
                sporcu=sporcu,
                kulup=kulup,
                sporcu_kulup_tarihce=tarihce,
                kaynak_turu="CANLI_SONUC" if tur == 'sonuc_listesi' else "CANLI_START_LISTESI",
                dosya_adi=dosya_adi,
                musabaka_adi=musabaka_adi,
                sehir=sehir,
                yaris_tarihi_ham=yaris_tarihi,
                yaris_tarihi_baslangic=yaris_tarihi_baslangic,
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
            existing_races_map[sporcu.id] = yeni_yaris
            stats['eklenen_sonuc'] += 1

            # YALNIZCA YENİ YARIŞ EKLENDİĞİNDE SAYAÇLARI ARTIR
            sporcu.toplam_yaris_sayisi = (sporcu.toplam_yaris_sayisi or 0) + 1
            if yaris_tarihi_baslangic:
                if not sporcu.ilk_yaris_tarihi or yaris_tarihi_baslangic < sporcu.ilk_yaris_tarihi:
                    sporcu.ilk_yaris_tarihi = yaris_tarihi_baslangic
                if not sporcu.son_yaris_tarihi or yaris_tarihi_baslangic > sporcu.son_yaris_tarihi:
                    sporcu.son_yaris_tarihi = yaris_tarihi_baslangic
            sporcu.save(update_fields=['toplam_yaris_sayisi', 'ilk_yaris_tarihi', 'son_yaris_tarihi'])

            tarihce.toplam_yaris_sayisi = (tarihce.toplam_yaris_sayisi or 0) + 1
            tarihce.save(update_fields=['toplam_yaris_sayisi'])

            kulup.toplam_yaris_sayisi = (kulup.toplam_yaris_sayisi or 0) + 1
            kulup.save(update_fields=['toplam_yaris_sayisi'])

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
        if data.get('limit'):
            try:
                limit = int(data.get('limit'))
            except Exception:
                limit = 10
    else:
        name = request.GET.get('sporcu_adi') or request.GET.get('ad_soyad') or request.GET.get('ad') or request.GET.get('name') or request.GET.get('q') or ''
        birth_info = request.GET.get('dogum_yili') or request.GET.get('dogum_tarihi') or request.GET.get('birth_date') or request.GET.get('yb')
        club = request.GET.get('kulup') or request.GET.get('club')
        if request.GET.get('limit'):
            try:
                limit = int(request.GET.get('limit'))
            except Exception:
                limit = 10

    res = match_athlete(name=name, birth_year_or_date=birth_info, club=club, limit=limit)
    status_code = 200 if res.get("durum") in ["basarili", "bulunamadi"] else 400
    return JsonResponse(res, status=status_code, json_dumps_params={'ensure_ascii': False})


def sporcu_eslestir_sayfasi(request):
    """
    Sporcu Eşleştirme Test ve Arama Arayüzü (Web Arayüzü)
    """
    name = request.GET.get('ad', '').strip()
    birth_info = request.GET.get('dogum_yili', '').strip()
    club = request.GET.get('kulup', '').strip()

    sonuc = None
    en_iyi_dereceler = []
    if name:
        sonuc = match_athlete(name=name, birth_year_or_date=birth_info, club=club)
        if sonuc and sonuc.get("bulunan_id"):
            sp = Sporcu.objects.filter(id=sonuc["bulunan_id"]).first()
            if sp:
                en_iyi_dereceler = sp.en_iyi_dereceler()

    context = {
        'ad': name,
        'dogum_yili': birth_info,
        'kulup': club,
        'sonuc': sonuc,
        'en_iyi_dereceler': en_iyi_dereceler,
    }
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

    # Kulüp Tarihçesi
    tarihce_list = []
    for t in sp.kulup_tarihcesi.select_related('kulup').order_by('donem_sirasi'):
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
        races_qs = sp.yaris_sonuclari.select_related('kulup')
        if kategori_str:
            races_qs = races_qs.filter(stil__icontains=kategori_str)
        if mesafe_val is not None:
            races_qs = races_qs.filter(mesafe=mesafe_val)

        # Sıralama
        if sirala == 'derece':
            races_qs = races_qs.order_by('derece_saniye', '-yaris_tarihi_baslangic')
        elif sirala in ('tarih_asc', 'eskiden_yeniye', 'kronolojik'):
            races_qs = races_qs.order_by('yaris_tarihi_baslangic', 'id')
        else:
            races_qs = races_qs.order_by('-yaris_tarihi_baslangic', '-id')

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
        musabaka_adi = request.POST.get("musabaka_adi", "").strip()
        if canli_url:
            yaris = CanliYaris.objects.create(
                canli_url=canli_url,
                musabaka_adi=musabaka_adi or None,
                durum="BEKLIYOR"
            )
            messages.success(request, f"Canlı yarış linki eklendi: {yaris.canli_url}")
            return redirect("sonuclar:canli_yaris_listesi")
        else:
            messages.error(request, "Lütfen geçerli bir canlı yarış linki girin.")

    yarislar = CanliYaris.objects.all().order_by("-olusturulma_tarihi")
    return render(request, "sonuclar/canli_yarislar.html", {"yarislar": yarislar})


def canli_yaris_tara(request, pk):
    """Tekil bir canlı yarışın start listelerini tarama tetikleyicisi."""
    if request.method != "POST":
        return redirect("sonuclar:canli_yaris_listesi")

    yaris = get_object_or_404(CanliYaris, pk=pk)

    import os
    import ssl
    import urllib.request
    cf_url = os.environ.get("GOOGLE_CLOUD_FUNCTION_URL")
    host = request.get_host().lower()
    is_localhost = host.startswith("127.0.0.1") or host.startswith("localhost")

    # Eğer canlı sunucudaysak (PythonAnywhere) ve Cloud Run URL tanımlıysa asenkron Webhook mimarisini kullan
    if cf_url and not is_localhost:
        yaris.durum = "ISLENIYOR"
        yaris.son_islem_tarihi = timezone.now()
        yaris.save()

        # Cloud Run'a 'async_mode' ile istek gönder - Cloud Run anında 200 döner, arka planda tarar
        req_payload = json.dumps({
            "event_id": yaris.id,
            "event_url": yaris.canli_url,
            "django_api_url": request.build_absolute_uri("/api/canli-aktar/"),
            "callback_url": request.build_absolute_uri("/api/canli-durum-guncelle/"),
            "async_mode": True
        }).encode("utf-8")

        try:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            req = urllib.request.Request(cf_url, data=req_payload, headers={"Content-Type": "application/json"})
            # Kısa timeout ile sadece tetikleme cevabını bekle (PythonAnywhere zaman aşımına uğramaz)
            with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
                resp_data = json.loads(resp.read().decode("utf-8"))
                toplam = resp_data.get("toplam_start_listesi", 0)
                yaris.toplam_start_listesi = toplam
                if resp_data.get("musabaka_adi"):
                    yaris.musabaka_adi = resp_data["musabaka_adi"]
                yaris.save()
                messages.info(request, f"Google Cloud taraması başlatıldı ({toplam} start listesi tespit edildi). Sayfayı kapatabilirsiniz, sonuçlar arka planda yüklenecektir.")
        except Exception as e:
            yaris.durum = "HATA"
            yaris.hata_mesaji = f"Cloud Run tetikleme hatası: {str(e)}"
            yaris.save()
            messages.error(request, f"Cloud Run tetiklenemedi: {str(e)}")

        return redirect("sonuclar:canli_yaris_listesi")

    # Yerel geliştirme ortamında doğrudan yerel worker ile arka planda çalıştır
    def worker_thread(event_id, url, api_target):
        try:
            from src.live_startlist_worker import run_live_event_startlists
            obj = CanliYaris.objects.get(id=event_id)
            obj.durum = "ISLENIYOR"
            obj.son_islem_tarihi = timezone.now()
            obj.save()

            stats = run_live_event_startlists(event_url=url, django_api_url=api_target)

            obj = CanliYaris.objects.get(id=event_id)
            obj.durum = "TAMAMLANDI" if stats.get("basarili_sayisi", 0) > 0 else "HATA"
            obj.musabaka_adi = stats.get("musabaka_adi") or obj.musabaka_adi
            obj.toplam_start_listesi = stats.get("toplam_start_listesi", 0)
            obj.islenen_start_listesi = stats.get("basarili_sayisi", 0)
            obj.eklenen_kayit_sayisi = stats.get("toplam_kayit", 0)
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

    api_url = request.build_absolute_uri("/api/canli-aktar/")
    t = threading.Thread(target=worker_thread, args=(yaris.id, yaris.canli_url, api_url), daemon=True)
    t.start()
    yaris.durum = "ISLENIYOR"
    yaris.save()

    messages.success(request, "Start listesi taraması yerel ortamda başlatıldı. Gemini ile işleniyor...")
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

    if data.get("musabaka_adi"):
        yaris.musabaka_adi = data["musabaka_adi"]
    if "toplam_start_listesi" in data:
        yaris.toplam_start_listesi = int(data["toplam_start_listesi"])
    if "islenen_start_listesi" in data:
        yaris.islenen_start_listesi = int(data["islenen_start_listesi"])
    elif "basarili" in data:
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


def api_canli_yarislar_durum(request):
    """
    Arayüzün durumları canlı yenilemesi için JSON liste döner.
    """
    yarislar = CanliYaris.objects.all().values(
        "id", "musabaka_adi", "durum", "toplam_start_listesi",
        "islenen_start_listesi", "eklenen_kayit_sayisi", "hata_mesaji"
    )
    return JsonResponse({"yarislar": list(yarislar)})





