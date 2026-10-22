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


def fetch_event_page(event_url: str) -> Tuple[str, List[str], str]:
    """
    Canlı yarış ana sayfasını çeker, başlığı ve sayfadaki tüm StartList PDF linklerini döner.
    """
    req = urllib.request.Request(
        event_url,
        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
    )
    with urllib.request.urlopen(req, context=get_ssl_context(), timeout=30) as resp:
        html = resp.read().decode("utf-8", errors="ignore")

    meet_title = ""
    start_list_urls = []

    if BeautifulSoup:
        soup = BeautifulSoup(html, "html.parser")
        if soup.title and soup.title.string:
            meet_title = soup.title.string.replace("- SPLASH Meet Manager 11", "").strip()

        # Linkleri topla
        seen = set()
        for a in soup.find_all("a", href=True):
            href = a["href"].strip()
            if "startlist" in href.lower() or "start_list" in href.lower():
                full_url = urljoin(event_url, href)
                if full_url not in seen:
                    seen.add(full_url)
                    start_list_urls.append(full_url)
    else:
        # Regex fallback
        m_title = re.search(r"<title>(.*?)</title>", html, re.I)
        if m_title:
            meet_title = m_title.group(1).replace("- SPLASH Meet Manager 11", "").strip()
        links = re.findall(r'href=["\']([^"\']*(?:startlist|start_list)[^"\']*)["\']', html, re.I)
        seen = set()
        for href in links:
            full_url = urljoin(event_url, href)
            if full_url not in seen:
                seen.add(full_url)
                start_list_urls.append(full_url)

    # Yarış numarasına göre sırala (StartList_1.pdf, StartList_2.pdf...)
    def sort_key(u: str) -> int:
        m = re.search(r"StartList_(\d+)\.pdf", u, re.I)
        return int(m.group(1)) if m else 99999

    start_list_urls.sort(key=sort_key)
    return meet_title, start_list_urls, html


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
    limit: Optional[int] = None
) -> Dict[str, Any]:
    """
    Belirtilen canlı yarış URL'sindeki tüm start listelerini Gemini ile tarar.
    """
    api_target = django_api_url or os.environ.get("DJANGO_API_URL", "http://127.0.0.1:8000/api/canli-aktar/")
    parser = GeminiLiveParser(api_key=gemini_key)

    print(f"[*] Canlı yarış sayfası taranıyor: {event_url}")
    meet_title, start_urls, _ = fetch_event_page(event_url)
    print(f"[*] Müsabaka: {meet_title or 'Bilinmiyor'}")
    print(f"[*] Tespit edilen Start Listesi sayısı: {len(start_urls)}")

    if limit and limit > 0:
        start_urls = start_urls[:limit]
        print(f"[*] Test modu: İlk {limit} liste taranacak.")

    stats = {
        "musabaka_adi": meet_title,
        "toplam_start_listesi": len(start_urls),
        "basarili_sayisi": 0,
        "hatali_sayisi": 0,
        "toplam_kayit": 0
    }

    for idx, pdf_url in enumerate(start_urls, 1):
        print(f"\n[{idx}/{len(start_urls)}] Start Listesi taranıyor: {pdf_url}")
        t0 = time.time()
        try:
            parsed_data = parser.parse_url(pdf_url, doc_type="start_listesi")
            if not parsed_data.get("musabaka_adi") and meet_title:
                parsed_data["musabaka_adi"] = meet_title

            kayitlar = parsed_data.get("kayitlar", [])
            stats["toplam_kayit"] += len(kayitlar)
            print(f"  -> {len(kayitlar)} sporcu ayrıştırıldı ({time.time()-t0:.2f}s). Django API'ye aktarılıyor...")

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
    print(f" Toplam Liste: {stats['toplam_start_listesi']}")
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

