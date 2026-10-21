# -*- coding: utf-8 -*-
from django.shortcuts import render, get_object_or_404
from django.core.paginator import Paginator
from django.db.models import Q, Count
from django.http import JsonResponse
from .models import Kulup, Sporcu, SporcuKulupTarihce, YarisSonucu, is_school_team


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

    context = {
        'sporcu': sporcu,
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


def _normalize_name(name):
    if not name:
        return ""
    mapping = {'İ': 'I', 'ı': 'i', 'I': 'I', 'i': 'i', 'Ş': 'S', 'ş': 's', 'Ğ': 'G', 'ğ': 'g', 'Ü': 'U', 'ü': 'u', 'Ö': 'O', 'ö': 'o', 'Ç': 'C', 'ç': 'c'}
    return re.sub(r'\s+', ' ', ''.join(mapping.get(ch, ch) for ch in name.strip().upper()))


def _find_matching_yaris_kaydi(yaris_qs, target_name):
    """
    Start listesinden gelen kayıtlar arasında, sonuç listesindeki sporcuyu
    (kısaltma veya OCR hatası olsa bile) en doğru şekilde eşleştirir.
    """
    if not target_name:
        return None

    t_norm = _normalize_name(target_name)

    # 1. Birebir tam isim eşleşmesi
    for yk in yaris_qs:
        if _normalize_name(yk.sporcu.sporcu_adi) == t_norm:
            return yk

    # 2. Önek / Kısaltma eşleşmesi (örn: 'Muharrem Kaan S.' -> 'Muharrem Kaan SELAMOĞLU')
    prefix = t_norm.rstrip('.').strip()
    p_matches = [yk for yk in yaris_qs if _normalize_name(yk.sporcu.sporcu_adi).startswith(prefix)]
    if len(p_matches) == 1:
        return p_matches[0]

    # 3. Benzerlik / OCR toleransı (Fuzzy Match >= 0.75)
    best_yk = None
    best_ratio = 0.0
    for yk in yaris_qs:
        ratio = difflib.SequenceMatcher(None, t_norm, _normalize_name(yk.sporcu.sporcu_adi)).ratio()
        if ratio > best_ratio:
            best_ratio = ratio
            best_yk = yk

    if best_ratio >= 0.75:
        return best_yk

    return None


@csrf_exempt
def api_canli_aktar(request):
    """
    Canlı yarış botundan gelen start listesi veya yarış sonucu JSON verisini
    veritabanına kaydeder/günceller. Start listesindeki güvenilir veriyi temel alarak
    sonuç listesindeki sporcuları akıllı eşleştirir.
    """
    if request.method != 'POST':
        return JsonResponse({'status': 'error', 'message': 'Sadece POST desteklenir.'}, status=405)

    try:
        payload = json.loads(request.body.decode('utf-8'))
    except Exception as e:
        return JsonResponse({'status': 'error', 'message': f'Geçersiz JSON: {str(e)}'}, status=400)

    tur = payload.get('tur', 'sonuc_listesi')  # 'start_listesi' veya 'sonuc_listesi'
    musabaka_adi = payload.get('musabaka_adi', '')
    sehir = payload.get('sehir', '')
    yaris_tarihi = payload.get('yaris_tarihi', '')
    yaris_tarihi_baslangic = payload.get('yaris_tarihi_baslangic', yaris_tarihi)
    yaris_no = str(payload.get('yaris_no', '')).strip()
    cinsiyet = payload.get('cinsiyet', '')
    mesafe = payload.get('mesafe')
    stil = payload.get('stil', '')
    yas_grubu = payload.get('yas_grubu', '')
    dosya_adi = payload.get('dosya_adi', '')
    kayitlar = payload.get('kayitlar', [])
    is_okul_musabakasi = bool(payload.get('okul_musabakasi')) or is_school_meet(musabaka_adi)

    eklenen_sayisi = 0
    guncellenen_sayisi = 0

    # Bu yarışa ait mevcut kayıtları önceden çek (Start listesinden gelmiş olanlar dahil)
    mevcut_yaris_kayitlari = list(
        YarisSonucu.objects.filter(
            musabaka_adi=musabaka_adi,
            yaris_no=yaris_no
        ).select_related('sporcu', 'kulup')
    )

    for item in kayitlar:
        sporcu_adi = (item.get('sporcu') or item.get('name') or '').strip()
        kulup_adi = (item.get('kulup') or item.get('club') or 'Ferdi').strip()
        yb = item.get('dogum_yili') or item.get('yb')

        dogum_yili = None
        if yb:
            try:
                yb_int = int(str(yb).strip())
                if yb_int < 100:
                    dogum_yili = 2000 + yb_int if yb_int <= 30 else 1900 + yb_int
                else:
                    dogum_yili = yb_int
            except Exception:
                pass

        if not sporcu_adi:
            continue

        seri_val = item.get('seri') or item.get('heat')
        kulvar_val = item.get('kulvar') or item.get('lane')
        if kulvar_val:
            try:
                kulvar_val = int(kulvar_val)
            except Exception:
                kulvar_val = None

        giris_derecesi_val = item.get('giris_derecesi') or item.get('seed_time')
        derece_val = item.get('derece') or item.get('time')
        sira_val = str(item.get('sira') or item.get('rank') or '')
        puan_val = item.get('puan') or item.get('points')
        if puan_val:
            try:
                puan_val = int(puan_val)
            except Exception:
                puan_val = None

        # 1. Kulüp Yönetimi (Okul Takımı vs Spor Kulübü)
        kulup, created = Kulup.objects.get_or_create(kulup_adi=kulup_adi)
        if kulup_adi.lower() != 'ferdi':
            if created:
                if is_okul_musabakasi or is_school_team(kulup_adi):
                    kulup.okul_mu = 1
                    kulup.save(update_fields=['okul_mu'])
            elif is_okul_musabakasi and kulup.okul_mu == 0:
                has_sk = bool(re.search(r'(?:spor\s*kul[uü]b[uü]|(?:\b|[_\s])sk\b|(?:\b|[_\s])gsk\b|(?:\b|[_\s])skd\b|y[uü]zme\s*kul[uü]b[uü]|ihtisas|derne[gğ]i|belediye\s*spor|belediyespor|kolejliler)', kulup_adi.lower()))
                if not (has_sk and kulup.yaris_sonuclari.filter(kulup__okul_mu=0).count() >= 50):
                    kulup.okul_mu = 1
                    kulup.save(update_fields=['okul_mu'])

        # 2. Sporcu Yönetimi
        sporcu = None
        sp_qs = Sporcu.objects.filter(sporcu_adi__iexact=sporcu_adi)
        if dogum_yili:
            sp_qs_yr = sp_qs.filter(dogum_yili=dogum_yili)
            if sp_qs_yr.exists():
                sporcu = sp_qs_yr.first()
        if not sporcu:
            sporcu = sp_qs.first()

        if not sporcu:
            sporcu = Sporcu.objects.create(
                sporcu_adi=sporcu_adi,
                dogum_yili=dogum_yili,
                yas_dogum_yili=str(dogum_yili) if dogum_yili else "",
                cinsiyet=cinsiyet,
                birincil_kulup=kulup
            )
        else:
            sp_updates = []
            if dogum_yili and not sporcu.dogum_yili:
                sporcu.dogum_yili = dogum_yili
                sporcu.yas_dogum_yili = str(dogum_yili)
                sp_updates.extend(['dogum_yili', 'yas_dogum_yili'])
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
        tarihce.toplam_yaris_sayisi = (tarihce.toplam_yaris_sayisi or 0) + 1
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

        # Sporcunun yarış istatistiklerini güncelle
        sporcu.toplam_yaris_sayisi = (sporcu.toplam_yaris_sayisi or 0) + 1
        if yaris_tarihi_baslangic:
            if not sporcu.ilk_yaris_tarihi or yaris_tarihi_baslangic < sporcu.ilk_yaris_tarihi:
                sporcu.ilk_yaris_tarihi = yaris_tarihi_baslangic
            if not sporcu.son_yaris_tarihi or yaris_tarihi_baslangic > sporcu.son_yaris_tarihi:
                sporcu.son_yaris_tarihi = yaris_tarihi_baslangic
        sporcu.save(update_fields=['toplam_yaris_sayisi', 'ilk_yaris_tarihi', 'son_yaris_tarihi'])

        # Start listesindeki kayıtlarla eşleştir
        eslesen_kayit = _find_matching_yaris_kaydi(mevcut_yaris_kayitlari, sporcu_adi)

        if tur == 'start_listesi':
            if eslesen_kayit:
                if seri_val:
                    eslesen_kayit.seri = str(seri_val)
                if kulvar_val is not None:
                    eslesen_kayit.kulvar = kulvar_val
                if giris_derecesi_val:
                    eslesen_kayit.giris_derecesi = str(giris_derecesi_val)
                if eslesen_kayit.sporcu_kulup_tarihce is None:
                    eslesen_kayit.sporcu_kulup_tarihce = tarihce
                eslesen_kayit.save()
                guncellenen_sayisi += 1
            else:
                yeni = YarisSonucu.objects.create(
                    sporcu=sporcu,
                    kulup=kulup,
                    sporcu_kulup_tarihce=tarihce,
                    kaynak_turu="CANLI_START_LISTESI",
                    dosya_adi=dosya_adi,
                    musabaka_adi=musabaka_adi,
                    sehir=sehir,
                    yaris_tarihi_ham=yaris_tarihi,
                    yaris_tarihi_baslangic=yaris_tarihi_baslangic,
                    yaris_no=yaris_no,
                    cinsiyet=cinsiyet,
                    mesafe=mesafe,
                    stil=stil,
                    yas_grubu=item.get('yas_grubu') or yas_grubu,
                    seri=str(seri_val) if seri_val else None,
                    kulvar=kulvar_val,
                    giris_derecesi=str(giris_derecesi_val) if giris_derecesi_val else None,
                    derece="Bekleniyor"
                )
                mevcut_yaris_kayitlari.append(yeni)
                eklenen_sayisi += 1
        else: # sonuc_listesi
            derece_sn = _time_to_seconds(derece_val)
            if eslesen_kayit:
                eslesen_kayit.sira = sira_val
                eslesen_kayit.derece = derece_val
                eslesen_kayit.derece_saniye = derece_sn
                eslesen_kayit.puan = puan_val
                if seri_val:
                    eslesen_kayit.seri = str(seri_val)
                if kulvar_val is not None:
                    eslesen_kayit.kulvar = kulvar_val
                if giris_derecesi_val:
                    eslesen_kayit.giris_derecesi = str(giris_derecesi_val)
                if eslesen_kayit.sporcu_kulup_tarihce is None:
                    eslesen_kayit.sporcu_kulup_tarihce = tarihce
                eslesen_kayit.save()
                guncellenen_sayisi += 1
            else:
                yeni = YarisSonucu.objects.create(
                    sporcu=sporcu,
                    kulup=kulup,
                    sporcu_kulup_tarihce=tarihce,
                    kaynak_turu="CANLI_SONUC",
                    dosya_adi=dosya_adi,
                    musabaka_adi=musabaka_adi,
                    sehir=sehir,
                    yaris_tarihi_ham=yaris_tarihi,
                    yaris_tarihi_baslangic=yaris_tarihi_baslangic,
                    yaris_no=yaris_no,
                    cinsiyet=cinsiyet,
                    mesafe=mesafe,
                    stil=stil,
                    yas_grubu=item.get('yas_grubu') or yas_grubu,
                    sira=sira_val,
                    seri=str(seri_val) if seri_val else None,
                    kulvar=kulvar_val,
                    giris_derecesi=str(giris_derecesi_val) if giris_derecesi_val else None,
                    derece=derece_val,
                    derece_saniye=derece_sn,
                    puan=puan_val
                )
                mevcut_yaris_kayitlari.append(yeni)
                eklenen_sayisi += 1

    return JsonResponse({
        'status': 'success',
        'tur': tur,
        'yaris_no': yaris_no,
        'eklenen': eklenen_sayisi,
        'guncellenen': guncellenen_sayisi,
        'toplam_kayit': len(kayitlar)
    })


from .athlete_matcher import match_athlete

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
    1. Profil bilgilerini (ad, doğum yılı, cinsiyet, aktif kulüp, okul, yarış sayısı)
    2. Belirli bir kategori (stil) ve mesafe seçilmişse o branştaki tüm sonuç listesini ve en iyi derecesini (PB)
    3. Herhangi bir kategori seçilmemişse stil ve mesafe bazındaki kişisel en iyi derecelerini (PB özeti)
    4. Kulüp temsil tarihçesini
    JSON formatında döner.

    Kullanım URL'leri:
      - GET /api/sporcular/<sporcu_id>/sonuclar/
      - GET /api/sporcular/<sporcu_id>/sonuclar/<kategori>/<mesafe>/
      - GET /api/sporcular/<sporcu_id>/<kategori>/<mesafe>/
      - GET /api/sporcu-sonuclari/?sporcu_id=<id>&kategori=<stil>&mesafe=<mesafe>
      - POST /api/sporcu-sonuclari/ {"sporcu_id": <id>, "kategori": "Serbest", "mesafe": 50}

    Parametreler:
      - kategori / stil: 'Serbest', 'Kurbağalama', 'Sırtüstü', 'Kelebek', 'Karışık'
      - mesafe: 50, 100, 200, 400, 800, 1500
      - sirala: 'tarih' (en yeni önce - varsayılan), 'tarih_asc' (kronolojik), 'derece' (en hızlı önce)
      - tum_yarislar: 1 / true (Tüm geçmiş yarışları da döner)
    """
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

        response_data = {
            "durum": "basarili",
            "sporcu": sporcu_data,
            "filtre": {
                "kategori": kategori_str or None,
                "mesafe": mesafe_val,
                "sirala": sirala
            },
            "en_iyi_derece": best_race_dict,
            "toplam_sonuc_sayisi": len(filtered_results_list),
            "sonuclar": filtered_results_list,
            "en_iyi_sonuclar": [best_race_dict] if best_race_dict else pb_list,
            "kulup_tarihcesi": tarihce_list
        }
        return JsonResponse(response_data, status=200, json_dumps_params={'ensure_ascii': False})

    # Kategori veya mesafe belirtilmemişse genel PB özeti dön
    response_data = {
        "durum": "basarili",
        "sporcu": sporcu_data,
        "toplam_brans_sayisi": len(pb_list),
        "en_iyi_sonuclar": pb_list,
        "sonuclar": pb_list,
        "kulup_tarihcesi": tarihce_list
    }

    if tum_yarislar:
        tum_qs = sp.yaris_sonuclari.select_related('kulup').order_by('-yaris_tarihi_baslangic', '-id')
        all_races_list = []
        for y in tum_qs[:100]:
            all_races_list.append({
                "id": y.id,
                "yaris_no": y.yaris_no,
                "musabaka_adi": y.musabaka_adi,
                "sehir": y.sehir,
                "tarih": y.yaris_tarihi_baslangic or y.yaris_tarihi_ham,
                "mesafe": y.mesafe,
                "stil": y.stil,
                "etkinlik": f"{y.mesafe}m {y.stil}" if y.mesafe and y.stil else (y.stil or ""),
                "derece": y.derece,
                "derece_saniye": y.derece_saniye,
                "puan": y.puan,
                "sira": y.sira,
                "kulup": y.kulup.kulup_adi if y.kulup else ""
            })
        response_data["tum_yarislar"] = all_races_list

    return JsonResponse(response_data, status=200, json_dumps_params={'ensure_ascii': False})



