# -*- coding: utf-8 -*-
"""
live_db_runner.py
=================
HTTP API katmanına ve Cloud Scheduler'a ihtiyaç duymadan doğrudan Django ORM üzerinden:
1. TYF ve İl Temsilciliği sayfalarından yeni canlı yarışları keşfedip veritabanına ekler (scrape_all_tyf_live_sources).
2. Karar motoruyla (evaluate_single_meet) yarışın start listesi eksikse veya bugün yarış günüyse PDF taramasını çalıştırır;
   yarış ileri tarihteyse ve start listeleri tamamsa yarış gününe kadar gereksiz tarama yapmaz.
3. Yeni veya değişen PDF'leri Gemini Flash Lite ile ayrıştırıp doğrudan SQLite (WAL) veritabanına yazar.
4. Sıkı Tamamlanma Kontrolü (is_meet_truly_completed):
   - Sadece start listeleri işlendiğinde veya yarışların bir kısmı sonuçlandığında (örn: 5/30 sonuç)
     yarışı erken 'TAMAMLANDI' yapmaz; tüm yarışların sonuç listeleri işlenene kadar 'ISLENIYOR' tutar.
"""

import os
import re
from datetime import datetime, timezone as dt_timezone, timedelta
from typing import Dict, List, Any, Optional, Tuple

from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from sonuclar.models import (
    CanliYaris,
    CanliYarisDosya,
    Event,
    YarisSonucu,
    Kulup,
    Sporcu,
    SporcuKulupTarihce,
    is_school_team,
)
from sonuclar.athlete_matcher import match_athlete
from sonuclar.turkish_names import standardize_turkish_athlete_name, tr_fold

from google import genai
from google_cloud_runner.main import (
    DEFAULT_MODEL,
    detect_pdf_type,
    download_file_with_meta,
    fetch_meet_pdf_urls,
    fetch_remote_headers_map,
    parse_meet_pdf,
    parse_reglaman_pdf,
)
from google_cloud_runner.tyf_live_scraper import (
    TR_TIMEZONE,
    evaluate_single_meet,
    scrape_all_tyf_live_sources,
)


def get_gemini_client() -> genai.Client:
    """Ortam değişkenlerinden (.env) Gemini istemcisini oluşturur."""
    gemini_key = (
        os.environ.get("GEMINI_API_KEY")
        or os.environ.get("GEMINI_API_KEY_2")
        or ""
    ).strip().strip("'\"")
    if not gemini_key:
        raise RuntimeError("GEMINI_API_KEY veya GEMINI_API_KEY_2 ortam değişkeni tanımlanmamış.")
    return genai.Client(api_key=gemini_key)


def is_meet_truly_completed(
    yaris: CanliYaris,
    kalan_dosya: int = 0,
    hatalar: Optional[List[str]] = None,
) -> bool:
    """
    Bir canlı yarışın gerçekten 'TAMAMLANDI' olup olmadığını sıkı kurallarla denetler:
    1. Bekleyen (kalan_dosya > 0) veya hata veren dosya varsa -> False
    2. Hiç start ve sonuç listesi yoksa -> False
    3. Start listeleri henüz bitmemişse (islenen_start < toplam_start) -> False
    4. Henüz hiç sonuç listesi yayınlanmamışsa (toplam_sonuc == 0) veya işlenmemiş sonuç varsa -> False
    5. Sonuç listesi sayısı, start listesi sayısından azsa (örn: 30 yarışın 5'i yüzüldü):
       - Müsabaka bitiş tarihi henüz geçmemişse (bugün <= bitis_tarihi) -> False (devam ediyor)
       - Veritabanında hâlâ 'Bekleniyor' durumunda sporcu varsa ve müsabaka bitiş tarihi geçmemişse -> False
    """
    if kalan_dosya > 0 or hatalar:
        return False

    t_start = int(yaris.toplam_start_listesi or 0)
    i_start = int(yaris.islenen_start_listesi or 0)
    t_sonuc = int(yaris.toplam_sonuc_listesi or 0)
    i_sonuc = int(yaris.islenen_sonuc_listesi or 0)

    if t_start == 0 and t_sonuc == 0:
        return False

    if t_start > 0 and i_start < t_start:
        return False

    if t_sonuc == 0 or i_sonuc < t_sonuc:
        return False

    today_str = datetime.now(TR_TIMEZONE).date().isoformat()
    end_iso = None
    if yaris.event_id and yaris.event:
        end_iso = yaris.event.yaris_tarihi_bitis or yaris.event.yaris_tarihi_baslangic

    # Eğer sonuç listesi sayısı start listesi sayısına ulaşmadıysa (yarışlar devam ediyor demektir)
    if t_start > 0 and i_sonuc < t_start:
        # Bitiş tarihi bilinmiyorsa veya bugün henüz bitiş tarihini geçmediyse kesinlikle TAMAMLANDI yapma!
        if not end_iso or today_str <= end_iso:
            return False

    # Müsabaka günü devam ediyorsa ve veritabanında hâlâ 'Bekleniyor' kaydı varsa TAMAMLANDI yapma
    if yaris.event_id and (not end_iso or today_str <= end_iso):
        has_waiting_swimmers = YarisSonucu.objects.filter(
            event_id=yaris.event_id,
            derece="Bekleniyor"
        ).exists()
        if has_waiting_swimmers and i_sonuc < t_start:
            return False

    return True


def canli_yaris_to_eval_dict(yaris: CanliYaris) -> Dict[str, Any]:
    """CanliYaris model nesnesini evaluate_single_meet karar motorunun beklediği sözlüğe çevirir."""
    return {
        "id": yaris.id,
        "event_id": yaris.event_id,
        "canli_url": yaris.canli_url,
        "musabaka_adi": yaris.musabaka_adi or "",
        "sehir": yaris.gosterilen_sehir,
        "tarih": yaris.gosterilen_tarih,
        "baslangic_tarihi": yaris.event.yaris_tarihi_baslangic if yaris.event else None,
        "bitis_tarihi": yaris.event.yaris_tarihi_bitis if yaris.event else None,
        "durum": yaris.durum,
        "toplam_start_listesi": yaris.toplam_start_listesi,
        "islenen_start_listesi": yaris.islenen_start_listesi,
        "toplam_sonuc_listesi": yaris.toplam_sonuc_listesi,
        "islenen_sonuc_listesi": yaris.islenen_sonuc_listesi,
    }


def should_scan_meet_db(yaris: CanliYaris) -> Tuple[bool, str]:
    """
    Yarışın şu an taranması gerekip gerekmediğini kontrol eder:
    - Start listesi henüz tamamlanmamışsa -> True
    - Bugün yarış günüyse (baslangic_tarihi <= bugun <= bitis_tarihi) -> True
    - Yarış gelecek tarihteyse ve start listeleri tamamsa -> False (Yarış gününü bekler)
    """
    return evaluate_single_meet(canli_yaris_to_eval_dict(yaris))


def fetch_known_files_db(yaris: CanliYaris) -> Dict[str, Dict[str, Any]]:
    """Doğrudan veritabanından o yarışa ait işlenmiş dosyaları çeker (0 HTTP overhead)."""
    q_filter = Q(canli_yaris=yaris)
    if yaris.event_id:
        q_filter |= Q(event_id=yaris.event_id)

    dosyalar = CanliYarisDosya.objects.filter(q_filter).values(
        "dosya_adi", "etag", "dosya_boyutu", "durum", "last_modified", "kayit_sayisi"
    )
    return {d["dosya_adi"]: d for d in dosyalar}


def fetch_startlist_swimmers_db(yaris: CanliYaris, yaris_no: str) -> List[Dict[str, Any]]:
    """Doğrudan veritabanından o yarışın start listesindeki sporcularını ve ID'lerini çeker."""
    qs = YarisSonucu.objects.all()
    if yaris.event_id:
        qs = qs.filter(event_id=yaris.event_id)
    elif yaris.musabaka_adi:
        qs = qs.filter(event__musabaka_adi=yaris.musabaka_adi)
    else:
        return []

    if yaris_no:
        qs = qs.filter(yaris_no=str(yaris_no).strip())

    sporcular_list = []
    for r in qs.select_related("sporcu", "kulup").order_by("seri", "kulvar", "id"):
        sporcular_list.append({
            "id": r.id,
            "sporcu_adi": r.sporcu.sporcu_adi,
            "kulup_adi": r.kulup.kulup_adi if r.kulup else "",
            "dogum_yili": r.sporcu.dogum_yili,
            "cinsiyet": r.cinsiyet or r.sporcu.cinsiyet,
            "seri": r.seri,
            "kulvar": r.kulvar,
            "giris_derecesi": r.giris_derecesi,
            "mevcut_derece": r.derece,
        })
    return sporcular_list


def update_meet_status_db(yaris: CanliYaris, data: Dict[str, Any]) -> None:
    """CanliYaris modelini doğrudan veritabanında günceller."""
    yaris.refresh_from_db()

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

    if data.get("toplam_sporcu"):
        yaris.eklenen_kayit_sayisi = (yaris.eklenen_kayit_sayisi or 0) + int(data["toplam_sporcu"])

    if "hatalar" in data:
        hatalar = data["hatalar"]
        if hatalar:
            yaris.hata_mesaji = "\n".join(hatalar) if isinstance(hatalar, list) else str(hatalar)
        else:
            yaris.hata_mesaji = None

    durum = data.get("durum")
    kalan_dosya = int(data.get("kalan_dosya", 0))
    hatalar_list = data.get("hatalar") or []

    if durum == "TAMAMLANDI":
        if is_meet_truly_completed(yaris, kalan_dosya=kalan_dosya, hatalar=hatalar_list):
            yaris.durum = "TAMAMLANDI"
        else:
            yaris.durum = "ISLENIYOR"
    elif durum in ("BEKLIYOR", "ISLENIYOR", "HATA"):
        yaris.durum = durum

    yaris.son_islem_tarihi = timezone.now()
    yaris.save()


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


def _process_single_race_payload(payload: dict) -> dict:
    """Tek bir yarışın (start listesi veya sonuç listesi) kayıtlarını doğrudan veritabanına aktarır."""
    tur = payload.get('tur', 'sonuc_listesi')
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

    if not tum_kayitlar:
        raise ValueError(f"{dosya_adi or 'Dosya'} içinde geçerli sporcu/kulvar kaydı bulunamadı (0 kayıt).")

    unique_clubs = set()
    unique_names = set()
    for it in tum_kayitlar:
        if it.get('id'):
            continue
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

    sporcu_exact_cache = {}
    for sp in Sporcu.objects.filter(sporcu_adi__in=unique_names).select_related('birincil_kulup'):
        sporcu_exact_cache.setdefault(tr_fold(sp.sporcu_adi), []).append(sp)

    races_to_create = []
    races_to_update = []
    sporcular_to_update = set()
    kulupler_to_update = set()
    tarihceler_to_save = set()

    existing_race_ids = [it['id'] for it in tum_kayitlar if it.get('id')]
    target_races_map = {}
    if existing_race_ids:
        for r in YarisSonucu.objects.filter(id__in=existing_race_ids).select_related('sporcu'):
            target_races_map[r.id] = r

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

        race_id = item.get('id')
        if race_id:
            target_race = target_races_map.get(race_id)
            if target_race:
                is_dq_item = bool(
                    'disk' in str(sira_val).lower() or
                    'dq' in str(sira_val).lower() or
                    (derece_val and 'sw' in str(derece_val).lower())
                )
                if is_dq_item:
                    derece_sn = None
                    puan_val = None
                    baraj_val = ""
                    if not sira_val or sira_val == '-':
                        sira_val = "DQ"
                    if derece_val:
                        target_race.uyari_notu = derece_val
                else:
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
        derece_sn = _time_to_seconds(derece_val)

        kulup = club_cache.get(kulup_adi.lower())
        if not kulup:
            kulup, _ = Kulup.objects.get_or_create(kulup_adi=kulup_adi)
            club_cache[kulup_adi.lower()] = kulup

        sporcu = None
        cands = sporcu_exact_cache.get(tr_fold(sporcu_adi))
        if cands:
            for cand in cands:
                if dogum_yili and cand.dogum_yili == dogum_yili:
                    if not cinsiyet or not cand.cinsiyet or cand.cinsiyet.upper().startswith(cinsiyet[0].upper()):
                        sporcu = cand
                        stats['eslesen_sporcu'] += 1
                        break
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
            if not sporcu and len(cands) == 1 and not dogum_yili:
                sporcu = cands[0]
                stats['eslesen_sporcu'] += 1

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
                    is_identical = (
                        (existing_race.derece or '') == (derece_val or '') and
                        (existing_race.sira or '') == (sira_val or '') and
                        (existing_race.puan or None) == puan_val
                    )
                    if is_identical:
                        stats['mukerrer_atlanilan'] += 1
                    else:
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
            else:
                if existing_race.derece != "Bekleniyor":
                    stats['mukerrer_atlanilan'] += 1
                else:
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

    if races_to_create:
        YarisSonucu.objects.bulk_create(races_to_create, batch_size=500)
    if races_to_update:
        YarisSonucu.objects.bulk_update(
            races_to_update,
            ['derece', 'derece_saniye', 'sira', 'puan', 'baraj', 'seri', 'kulvar', 'giris_derecesi', 'kulup', 'canli_dosya', 'dosya_adi', 'kaynak_turu', 'uyari_notu'],
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


def process_single_meet_db(
    yaris: CanliYaris,
    client: genai.Client,
    model: str = DEFAULT_MODEL,
    batch_size: Optional[int] = None,
    limit: Optional[int] = None,
) -> Dict[str, Any]:
    """
    Tek bir CanliYaris kaydını doğrudan Django ORM ile işler:
    1. Bilinen işlenmiş dosyaları doğrudan veritabanından çeker.
    2. TYF sunucusundan ETag / Last-Modified başlıklarını paralel HTTP HEAD ile kontrol eder.
    3. Yeni veya değişen PDF'leri Gemini ile ayrıştırıp doğrudan _process_single_race_payload() ile DB'ye yazar.
    """
    event_id = yaris.id
    event_url = yaris.canli_url
    reglaman_linki = yaris.reglaman_linki or ""
    barajlar_data = yaris.barajlar or {}

    print(f"\n=======================================================")
    print(f"[*] Canlı Yarış Doğrudan DB İşleniyor: ID #{event_id} - {event_url}")
    print(f"=======================================================")

    stats: Dict[str, Any] = {
        "event_id": event_id,
        "event_url": event_url,
        "reglaman_linki": reglaman_linki,
        "barajlar": barajlar_data,
        "durum": "ISLENIYOR",
        "musabaka_adi": yaris.musabaka_adi or "",
        "sehir": yaris.sehir or "",
        "tarih": yaris.tarih or "",
        "toplam_start_listesi": 0,
        "islenen_start_listesi": 0,
        "toplam_sonuc_listesi": 0,
        "islenen_sonuc_listesi": 0,
        "basarili": 0,
        "atlanilan": 0,
        "hatali": 0,
        "kalan_dosya": 0,
        "toplam_sporcu": 0,
        "hatalar": [],
    }

    try:
        if reglaman_linki and (not barajlar_data or not barajlar_data.get("barajlar")):
            print(f"[*] Reglaman PDF ayrıştırılıyor: {reglaman_linki}")
            barajlar_data = parse_reglaman_pdf(reglaman_linki, client, model=model)
            if barajlar_data and barajlar_data.get("barajlar"):
                stats["barajlar"] = barajlar_data
                update_meet_status_db(yaris, {
                    "reglaman_linki": reglaman_linki,
                    "barajlar": barajlar_data,
                })

        meet_title, city, date_str, start_date, end_date, all_pdf_urls = fetch_meet_pdf_urls(event_url, mode="all")
        if meet_title:
            stats["musabaka_adi"] = meet_title
        if city:
            stats["sehir"] = city
        if date_str or start_date:
            stats["tarih"] = date_str or start_date

        if not yaris.event_id and stats["musabaka_adi"]:
            event_obj, _ = Event.objects.get_or_create(
                musabaka_adi=stats["musabaka_adi"],
                defaults={
                    "sehir": stats["sehir"],
                    "yaris_tarihi_baslangic": start_date or "",
                    "yaris_tarihi_bitis": end_date or "",
                    "yaris_tarihi_ham": date_str or "",
                    "kaynak_turu": "CANLI_TAKIP",
                },
            )
            yaris.event = event_obj
            yaris.save(update_fields=["event"])
        elif yaris.event_id and yaris.event:
            ev = yaris.event
            ev_dirty = []
            if start_date and not ev.yaris_tarihi_baslangic:
                ev.yaris_tarihi_baslangic = start_date
                ev_dirty.append("yaris_tarihi_baslangic")
            if end_date and not ev.yaris_tarihi_bitis:
                ev.yaris_tarihi_bitis = end_date
                ev_dirty.append("yaris_tarihi_bitis")
            if ev_dirty:
                ev.save(update_fields=ev_dirty)

        start_urls = [u for u in all_pdf_urls if detect_pdf_type(u, b"") == "start_listesi"]
        result_urls = [u for u in all_pdf_urls if detect_pdf_type(u, b"") == "sonuc_listesi"]

        stats["toplam_start_listesi"] = len(start_urls)
        stats["toplam_sonuc_listesi"] = len(result_urls)

        known_files = fetch_known_files_db(yaris)
        print(f"[*] Veritabanından {len(known_files)} adet işlenmiş dosya kaydı okundu.")

        remote_headers = fetch_remote_headers_map(all_pdf_urls)

        def is_file_unchanged(fname: str) -> bool:
            kf = known_files.get(fname)
            if not kf or kf.get("durum") != "ISLENDI":
                return False
            rh = remote_headers.get(fname) or {}
            known_etag = (kf.get("etag") or "").strip('"')
            remote_etag = (rh.get("etag") or "").strip('"')
            known_lm = (kf.get("last_modified") or "").strip()
            remote_lm = (rh.get("last_modified") or "").strip()

            if remote_etag and known_etag:
                return remote_etag == known_etag
            if remote_lm and known_lm:
                return remote_lm == known_lm
            return True

        pending_start_urls = []
        already_done_starts = 0
        for u in start_urls:
            if is_file_unchanged(os.path.basename(u)):
                already_done_starts += 1
            else:
                pending_start_urls.append(u)

        pending_result_urls = []
        already_done_results = 0
        for u in result_urls:
            if is_file_unchanged(os.path.basename(u)):
                already_done_results += 1
            else:
                pending_result_urls.append(u)

        stats["islenen_start_listesi"] = already_done_starts
        stats["islenen_sonuc_listesi"] = already_done_results
        stats["atlanilan"] = already_done_starts + already_done_results

        update_meet_status_db(yaris, {
            "durum": "ISLENIYOR",
            "musabaka_adi": stats["musabaka_adi"],
            "sehir": stats["sehir"],
            "tarih": stats["tarih"],
            "toplam_start_listesi": stats["toplam_start_listesi"],
            "islenen_start_listesi": stats["islenen_start_listesi"],
            "toplam_sonuc_listesi": stats["toplam_sonuc_listesi"],
            "islenen_sonuc_listesi": stats["islenen_sonuc_listesi"],
        })

        pending_queue = (
            [("start_listesi", u) for u in pending_start_urls]
            + [("sonuc_listesi", u) for u in pending_result_urls]
        )

        if not pending_queue:
            stats["kalan_dosya"] = 0
            stats["durum"] = "TAMAMLANDI"  # update_meet_status_db içinde is_meet_truly_completed ile doğrulanır
            update_meet_status_db(yaris, stats)
            stats["durum"] = yaris.durum
            print(f"[*] Yeni indirilecek dosya yok. Güncel Durum: {yaris.durum} (Start: {stats['islenen_start_listesi']}/{stats['toplam_start_listesi']}, Sonuç: {stats['islenen_sonuc_listesi']}/{stats['toplam_sonuc_listesi']})")
            return stats

        # Dosya kısıtı kaldırıldı (Tüm bekleyen dosyalar tek seferde işlenir)
        current_batch = pending_queue

        remaining_after_batch = len(pending_queue) - len(current_batch)
        if remaining_after_batch > 0:
            print(f"[*] {len(pending_queue)} bekleyen dosyadan {len(current_batch)} tanesi işleniyor (Kalan: {remaining_after_batch})...")
        else:
            print(f"[*] {len(pending_queue)} bekleyen dosyanın tamamı sınırlama olmadan işleniyor...")

        for doc_type, pdf_url in current_batch:
            filename = os.path.basename(pdf_url)
            try:
                pdf_bytes, meta = download_file_with_meta(pdf_url)

                startlist_swimmers = None
                if doc_type == "sonuc_listesi":
                    m_no = re.search(r"(?:ResultList|StartList)_(\d+)\.pdf", filename, re.I) or re.search(r"_(\d+)\.pdf", filename, re.I)
                    yaris_no = m_no.group(1) if m_no else None
                    if yaris_no:
                        startlist_swimmers = fetch_startlist_swimmers_db(yaris, yaris_no)

                print(f"  [>] {filename} ayrıştırılıyor ({doc_type})...")
                parsed = parse_meet_pdf(
                    pdf_bytes,
                    client,
                    pdf_url=pdf_url,
                    model=model,
                    startlist_swimmers=startlist_swimmers,
                    barajlar_data=barajlar_data,
                )
                parsed["tur"] = doc_type
                if not parsed.get("musabaka_adi") and stats["musabaka_adi"]:
                    parsed["musabaka_adi"] = stats["musabaka_adi"]
                if not parsed.get("sehir") and stats["sehir"]:
                    parsed["sehir"] = stats["sehir"]
                if not parsed.get("tarih") and stats["tarih"]:
                    parsed["tarih"] = stats["tarih"]
                if start_date and not parsed.get("yaris_tarihi_baslangic"):
                    parsed["yaris_tarihi_baslangic"] = start_date
                if end_date and not parsed.get("yaris_tarihi_bitis"):
                    parsed["yaris_tarihi_bitis"] = end_date

                parsed["canli_yaris_id"] = event_id
                parsed["dosya_adi"] = filename
                parsed["dosya_url"] = pdf_url
                parsed["etag"] = meta.get("etag")
                parsed["last_modified"] = meta.get("last_modified")
                parsed["dosya_boyutu"] = meta.get("dosya_boyutu")

                max_db_retries = 3
                db_stats = {}
                for db_attempt in range(max_db_retries):
                    try:
                        with transaction.atomic():
                            db_stats = _process_single_race_payload(parsed)
                        break
                    except Exception as db_e:
                        if "locked" in str(db_e).lower() and db_attempt < max_db_retries - 1:
                            time.sleep(1 + db_attempt)
                            continue
                        raise

                record_count = (
                    db_stats.get("eklenen_sonuc", 0)
                    + db_stats.get("guncellenen_sonuc", 0)
                    + db_stats.get("mukerrer_atlanilan", 0)
                )
                stats["basarili"] += 1
                if doc_type == "start_listesi":
                    stats["islenen_start_listesi"] += 1
                else:
                    stats["islenen_sonuc_listesi"] += 1
                stats["toplam_sporcu"] += db_stats.get("eklenen_sonuc", 0)

                update_meet_status_db(yaris, {
                    "durum": "ISLENIYOR",
                    "toplam_start_listesi": stats["toplam_start_listesi"],
                    "islenen_start_listesi": stats["islenen_start_listesi"],
                    "toplam_sonuc_listesi": stats["toplam_sonuc_listesi"],
                    "islenen_sonuc_listesi": stats["islenen_sonuc_listesi"],
                    "toplam_sporcu": db_stats.get("eklenen_sonuc", 0),
                })
                stats["toplam_sporcu"] = 0
                print(f"  [+] {filename} doğrudan veritabanına yazıldı ({record_count} kayıt).")

            except Exception as e:
                err = f"{filename} ({doc_type}): {str(e)}"
                print(f"  [!] Hata: {err}")
                stats["hatali"] += 1
                stats["hatalar"].append(err)

        stats["kalan_dosya"] = remaining_after_batch

    except Exception as e:
        err = f"Genel Tarama Hatası ({event_url}): {str(e)}"
        print(f"[!] {err}")
        stats["hatali"] += 1
        stats["hatalar"].append(err)

    if stats.get("kalan_dosya", 0) > 0:
        stats["durum"] = "ISLENIYOR"
    elif stats["hatali"] > 0:
        stats["durum"] = "ISLENIYOR" if (stats["basarili"] + stats["atlanilan"]) > 0 else "HATA"
    else:
        stats["durum"] = "TAMAMLANDI"

    update_meet_status_db(yaris, stats)
    stats["durum"] = yaris.durum
    return stats


def discover_new_meets_db() -> int:
    """TYF merkezi sayfası ve il temsilciliklerini tarayıp yeni canlı yarışları doğrudan veritabanına ekler."""
    scraped_meets = scrape_all_tyf_live_sources(probe_range=None)
    added_count = 0
    for m in scraped_meets:
        u = (m.get("canli_url") or "").strip()
        if not u:
            continue
        yaris, created = CanliYaris.objects.get_or_create(
            canli_url=u,
            defaults={
                "musabaka_adi": m.get("musabaka_adi") or "",
                "sehir": m.get("sehir") or "",
                "tarih": m.get("tarih") or "",
                "reglaman_linki": m.get("reglaman_linki") or None,
                "durum": "BEKLIYOR",
            },
        )
        if created:
            added_count += 1
            print(f"[+] Yeni canlı yarış keşfedildi ve eklendi: {yaris.musabaka_adi or u}")
    return added_count
