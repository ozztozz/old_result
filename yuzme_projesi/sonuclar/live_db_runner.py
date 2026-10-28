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

from sonuclar.models import CanliYaris, CanliYarisDosya, Event, YarisSonucu
from sonuclar.views import _process_single_race_payload

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

        if limit and limit > 0:
            current_batch = pending_queue[:limit]
        elif batch_size and batch_size > 0:
            current_batch = pending_queue[:batch_size]
        else:
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
