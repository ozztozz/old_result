#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
live_startlist_worker.py
========================
TYF Canlı yarış sayfasındaki (örn: canli.tyf.gov.tr/istanbul/cs-1005380/)
yayınlanan tüm Start Listelerini (StartList_*.pdf) tespit eder,
Gemini Flash Lite ile parse eder ve Django veritabanına aktarır.

Kullanım:
    python src/live_startlist_worker.py --url https://canli.tyf.gov.tr/istanbul/cs-1005380/
    python src/live_startlist_worker.py --event-id 1
"""

import os
import sys
import re
import json
import ssl
import time
import hashlib
import argparse
import urllib.request
from urllib.parse import urljoin, urlparse
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple

# Proje kökünü sys.path'e ekle
ROOT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT_DIR))
sys.path.insert(0, str(ROOT_DIR / "yuzme_projesi"))

def init_django():
    """Django ORM ortamını başlatır."""
    try:
        import django
        from django.apps import apps
        if not apps.ready:
            os.environ.setdefault("DJANGO_SETTINGS_MODULE", "yuzme_projesi.settings")
            django.setup()
    except Exception as e:
        pass

init_django()

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from src.gemini_live_parser import GeminiLiveParser, download_pdf_bytes

try:
    from bs4 import BeautifulSoup
except ImportError:
    BeautifulSoup = None


def get_ssl_context():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def parse_tr_date_range(d_str: str) -> Tuple[str, str]:
    """Türkçe tarih aralığını ISO formatına dönüştürür (örn: '24. - 26.4.2026' -> '2026-04-24', '2026-04-26')."""
    if not d_str:
        return '', ''
    d_clean = re.sub(r'\s+', ' ', d_str.strip())
    m = re.search(r'(\d{1,2})\.?\s*(?:-\s*(\d{1,2})\.?)?\s*(\d{1,2})\.(\d{4})', d_clean)
    if m:
        d1, d2, month, year = m.group(1), m.group(2), m.group(3), m.group(4)
        m_str = f'{int(month):02d}'
        start_date = f'{year}-{m_str}-{int(d1):02d}'
        end_date = f'{year}-{m_str}-{int(d2):02d}' if d2 else start_date
        return start_date, end_date
    return '', ''


def download_pdf_with_meta(url: str) -> Tuple[bytes, Dict[str, Any]]:
    """Dosyayı indirir ve ETag, Last-Modified ve SHA-256 hash meta verilerini çıkarır."""
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
    )
    with urllib.request.urlopen(req, context=get_ssl_context(), timeout=30) as resp:
        content = resp.read()
        etag = (resp.headers.get("ETag") or "").strip('"')
        last_modified = resp.headers.get("Last-Modified") or ""
        sha256 = hashlib.sha256(content).hexdigest()
        meta = {
            "etag": etag,
            "last_modified": last_modified,
            "content_hash": sha256,
            "dosya_boyutu": len(content)
        }
        return content, meta


def fetch_event_page(event_url: str, mod: str = "start_listesi") -> Tuple[str, str, str, str, str, List[str], str]:
    """
    Canlı yarış ana sayfasını çeker, başlığı, şehri, tarihini ve sayfadaki PDF linklerini döner.
    mod: 'start_listesi', 'sonuc_listesi' veya 'hepsi'
    Döner: (meet_title, city, date_str, start_date, end_date, pdf_urls, html)
    """
    req = urllib.request.Request(
        event_url,
        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
    )
    with urllib.request.urlopen(req, context=get_ssl_context(), timeout=30) as resp:
        html = resp.read().decode("utf-8", errors="ignore")

    meet_title = ""
    city = ""
    date_str = ""
    start_date = ""
    end_date = ""
    pdf_urls = []

    if BeautifulSoup:
        soup = BeautifulSoup(html, "html.parser")
        if soup.title and soup.title.string:
            meet_title = soup.title.string.replace("- SPLASH Meet Manager 11", "").strip()

        plain_text = soup.get_text()

        # Sayfadan Şehir ve Tarih çıkarımı (Örn: İSTANBUL (TUR) 24. - 26.4.2026)
        m_city = re.search(r'([A-ZÇĞİÖŞÜa-zçğıöşü\s]{3,30})\s*\((?:TUR|TR)\)', plain_text)
        if m_city:
            city = re.sub(r'\s+', ' ', m_city.group(1)).strip()

        m_date = re.search(r'(\d{1,2}\.?\s*(?:-\s*\d{1,2}\.)?\s*\d{1,2}\.\d{4})', plain_text)
        if m_date:
            date_str = re.sub(r'\s+', ' ', m_date.group(1)).strip()
            start_date, end_date = parse_tr_date_range(date_str)
    else:
        # BeautifulSoup yoksa düz HTML üzerinden regex dene
        m_city = re.search(r'([A-ZÇĞİÖŞÜa-zçğıöşü\s]{3,30})\s*\((?:TUR|TR)\)', html)
        if m_city:
            city = re.sub(r'\s+', ' ', m_city.group(1)).strip()

        m_date = re.search(r'(\d{1,2}\.?\s*(?:-\s*\d{1,2}\.)?\s*\d{1,2}\.\d{4})', html)
        if m_date:
            date_str = re.sub(r'\s+', ' ', m_date.group(1)).strip()
            start_date, end_date = parse_tr_date_range(date_str)

    if not city:
        # URL'den şehir tahmini (/istanbul/, /ankara/ vs.)
        m_u = re.search(r'canli\.tyf\.gov\.tr/([a-zA-ZçğıöşüÇĞİÖŞÜ]+)/', event_url)
        if m_u:
            c_raw = m_u.group(1).lower()
            city = c_raw.replace('i', 'İ').replace('ı', 'I').upper()

    if BeautifulSoup:
        soup = BeautifulSoup(html, "html.parser")
        if soup.title and soup.title.string:
            meet_title = soup.title.string.replace("- SPLASH Meet Manager 11", "").strip()

        # Linkleri topla
        seen = set()
        for a in soup.find_all("a", href=True):
            href = a["href"].strip()
            hl = href.lower()
            matches = False
            if mod == "sonuc_listesi":
                matches = ("resultlist" in hl or "result_list" in hl or "sonuc" in hl)
            elif mod == "hepsi":
                matches = ("startlist" in hl or "start_list" in hl or "resultlist" in hl or "result_list" in hl)
            else: # default start_listesi
                matches = ("startlist" in hl or "start_list" in hl)

            if matches:
                full_url = urljoin(event_url, href)
                if full_url not in seen:
                    seen.add(full_url)
                    pdf_urls.append(full_url)
    else:
        # Regex fallback
        m_title = re.search(r"<title>(.*?)</title>", html, re.I)
        if m_title:
            meet_title = m_title.group(1).replace("- SPLASH Meet Manager 11", "").strip()
        pattern = r'href=["\']([^"\']*(?:startlist|start_list|resultlist|result_list)[^"\']*)["\']'
        links = re.findall(pattern, html, re.I)
        seen = set()
        for href in links:
            hl = href.lower()
            matches = False
            if mod == "sonuc_listesi":
                matches = ("resultlist" in hl or "result_list" in hl or "sonuc" in hl)
            elif mod == "hepsi":
                matches = ("startlist" in hl or "start_list" in hl or "resultlist" in hl or "result_list" in hl)
            else:
                matches = ("startlist" in hl or "start_list" in hl)
            if matches:
                full_url = urljoin(event_url, href)
                if full_url not in seen:
                    seen.add(full_url)
                    pdf_urls.append(full_url)

    # Yarış numarasına göre sırala (StartList_1.pdf, ResultList_1.pdf...)
    def sort_key(u: str) -> int:
        m = re.search(r"(?:StartList|ResultList)_(\d+)\.pdf", u, re.I)
        if not m:
            m = re.search(r"_(\d+)\.pdf", u, re.I)
        return int(m.group(1)) if m else 99999

    pdf_urls.sort(key=sort_key)
    return meet_title, city, date_str, start_date, end_date, pdf_urls, html


def send_to_django_api(api_url: str, payload: Dict[str, Any], api_key: Optional[str] = None) -> bool:
    """Ayrıştırılan yarış sonucunu doğrudan Django ORM'e veya HTTP API'ye aktarır."""
    # 1. Doğrudan Django ORM erişimi varsa (yerel çalışma için en hızlı ve güvenli yol)
    try:
        import django
        from django.apps import apps
        if apps.ready:
            try:
                from sonuclar.views import _process_single_race_payload
                _process_single_race_payload(payload)
                return True
            except ImportError:
                from yuzme_projesi.sonuclar.views import _process_single_race_payload
                _process_single_race_payload(payload)
                return True
    except Exception as err_orm:
        pass

    # 2. HTTP API üzerinden aktarım
    data_json = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if api_key:
        headers["X-Api-Key"] = api_key

    req = urllib.request.Request(api_url, data=data_json, headers=headers)
    ctx = get_ssl_context()
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=45) as resp:
            resp_body = resp.read().decode("utf-8")
            res = json.loads(resp_body)
            if res.get("durum") == "basarili":
                return True
            print(f"  [!] Django API uyarısı: {res.get('mesaj')}", file=sys.stderr)
            return True
    except Exception as e:
        print(f"  [!] Django API aktarım hatası ({api_url}): {e}", file=sys.stderr)
        return False


def run_live_event_startlists(
    event_url: str,
    django_api_url: Optional[str] = None,
    api_key: Optional[str] = None,
    gemini_key: Optional[str] = None,
    limit: Optional[int] = None,
    mod: str = "start_listesi",
    canli_yaris_id: Optional[int] = None
) -> Dict[str, Any]:
    """
    Belirtilen canlı yarış URL'sindeki listeleri (start veya sonuç) Gemini ile tarar.
    """
    api_target = django_api_url or os.environ.get("DJANGO_API_URL", "http://127.0.0.1:8000/api/canli-aktar/")
    parser = GeminiLiveParser(api_key=gemini_key)

    doc_type_label = "Sonuç Listesi" if mod == "sonuc_listesi" else "Start Listesi"
    print(f"[*] Canlı yarış sayfası taranıyor ({doc_type_label}): {event_url}")
    meet_title, city, date_str, start_date, end_date, pdf_urls, _ = fetch_event_page(event_url, mod=mod)
    print(f"[*] Müsabaka: {meet_title or 'Bilinmiyor'} | Şehir: {city or '-'} | Tarih: {date_str or start_date or '-'}")
    print(f"[*] Tespit edilen {doc_type_label} sayısı: {len(pdf_urls)}")

    if limit and limit > 0:
        pdf_urls = pdf_urls[:limit]
        print(f"[*] Test modu: İlk {limit} liste taranacak.")

    stats = {
        "musabaka_adi": meet_title,
        "sehir": city,
        "tarih": date_str or start_date,
        "yaris_tarihi_baslangic": start_date,
        "yaris_tarihi_bitis": end_date,
        "toplam_liste": len(pdf_urls),
        "toplam_start_listesi": len(pdf_urls) if mod == 'start_listesi' else 0,
        "basarili_sayisi": 0,
        "hatali_sayisi": 0,
        "toplam_kayit": 0
    }

    for idx, pdf_url in enumerate(pdf_urls, 1):
        print(f"\n[{idx}/{len(pdf_urls)}] {doc_type_label} taranıyor: {pdf_url}")
        t0 = time.time()
        try:
            pdf_bytes, meta = download_pdf_with_meta(pdf_url)
            filename = os.path.basename(pdf_url)

            # Yarış no tespiti
            m_no = re.search(r"(?:StartList|ResultList)_(\d+)\.pdf", filename, re.I)
            if not m_no:
                m_no = re.search(r"_(\d+)\.pdf", filename, re.I)
            yaris_no = m_no.group(1) if m_no else None

            # Eğer sonuç listesiyse start listesindeki sporcuları Django'dan çek
            startlist_swimmers = None
            if mod == "sonuc_listesi" and yaris_no and canli_yaris_id:
                try:
                    from sonuclar.models import YarisSonucu, CanliYaris
                    canli_obj = CanliYaris.objects.filter(id=canli_yaris_id).first()
                    target_eid = canli_obj.event_id if (canli_obj and canli_obj.event_id) else None
                    if target_eid:
                        qs_sw = YarisSonucu.objects.filter(event_id=target_eid, yaris_no=yaris_no).select_related('sporcu', 'kulup')
                        startlist_swimmers = []
                        for r in qs_sw:
                            startlist_swimmers.append({
                                "id": r.id,
                                "sporcu_adi": r.sporcu.sporcu_adi,
                                "kulup_adi": r.kulup.kulup_adi if r.kulup else "",
                                "dogum_yili": r.sporcu.dogum_yili,
                                "seri": r.seri,
                                "kulvar": r.kulvar
                            })
                        if startlist_swimmers:
                            print(f"  [*] Bu yarış için {len(startlist_swimmers)} start kaydı bulundu; Gemini eşleştirmesine iletiliyor...")
                except Exception as e:
                    print(f"  [!] Start adayları çekilirken hata: {e}")

            parsed_data = parser.parse_pdf_bytes(
                pdf_bytes,
                doc_type=mod,
                hint=pdf_url,
                startlist_swimmers=startlist_swimmers
            )
            if not parsed_data.get("musabaka_adi") and meet_title:
                parsed_data["musabaka_adi"] = meet_title
            if not parsed_data.get("sehir") and city:
                parsed_data["sehir"] = city
            if not parsed_data.get("tarih") and (date_str or start_date):
                parsed_data["tarih"] = date_str or start_date
            if start_date and not parsed_data.get("yaris_tarihi_baslangic"):
                parsed_data["yaris_tarihi_baslangic"] = start_date
            if end_date and not parsed_data.get("yaris_tarihi_bitis"):
                parsed_data["yaris_tarihi_bitis"] = end_date

            parsed_data["dosya_adi"] = filename
            parsed_data["dosya_url"] = pdf_url
            parsed_data["etag"] = meta.get("etag")
            parsed_data["last_modified"] = meta.get("last_modified")
            parsed_data["content_hash"] = meta.get("content_hash")
            parsed_data["dosya_boyutu"] = meta.get("dosya_boyutu")
            if canli_yaris_id:
                parsed_data["canli_yaris_id"] = canli_yaris_id

            kayitlar = parsed_data.get("kayitlar", [])
            yeni_sporcular = parsed_data.get("yeni_sporcular", [])
            total_items = len(kayitlar) + len(yeni_sporcular)
            stats["toplam_kayit"] += total_items
            print(f"  -> {total_items} sporcu ayrıştırıldı ({time.time()-t0:.2f}s). Django'ya aktarılıyor...")

            # Django'ya post et
            ok = send_to_django_api(api_target, parsed_data, api_key=api_key)
            if ok:
                stats["basarili_sayisi"] += 1
            else:
                stats["hatali_sayisi"] += 1

        except Exception as e:
            print(f"  [!] Hata oluştu ({pdf_url}): {e}", file=sys.stderr)
            stats["hatali_sayisi"] += 1

    print("\n" + "=" * 60)
    print(f" İŞLEM TAMAMLANDI")
    print(f" Toplam Liste: {stats['toplam_liste']}")
    print(f" Başarılı     : {stats['basarili_sayisi']}")
    print(f" Hatalı       : {stats['hatali_sayisi']}")
    print(f" Toplam Kayıt : {stats['toplam_kayit']} sporcu")
    print("=" * 60)
    return stats


def main():
    parser = argparse.ArgumentParser(description="TYF Canlı Start Listesi Takip ve Aktarım Botu")
    parser.add_argument("--url", default="https://canli.tyf.gov.tr/istanbul/cs-1005380/", help="Canlı yarış linki")
    parser.add_argument("--api", default=None, help="Django API URL (Örn: http://127.0.0.1:8000/api/canli-aktar/)")
    parser.add_argument("--api-key", default=None, help="Django X-Api-Key")
    parser.add_argument("--limit", type=int, default=None, help="İşlenecek maksimum start listesi sayısı (test için)")
    args = parser.parse_args()

    run_live_event_startlists(
        event_url=args.url,
        django_api_url=args.api,
        api_key=args.api_key,
        limit=args.limit
    )


if __name__ == "__main__":
    main()

