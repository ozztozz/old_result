# -*- coding: utf-8 -*-
"""
google_cloud_runner/tyf_live_scraper.py
======================================================
TYF Canlı Yarış Tarayıcısı, API Senkronizasyon ve Cloud Scheduler Orkestratörü
(TEK DOSYA MİMARİSİ)

Görevleri:
1. 81 İl Temsilciliği Sayfaları (https://www.tyf.gov.tr/<il>-il-temsilciligi/):
   Sağ menüdeki 'CANLI SONUÇLAR' butonundan aktif yarış linklerini çeker.
2. TYF Merkezi Canlı Sayfası (https://www.tyf.gov.tr/canli-sonuc/):
   Resmi canlı sonuç tablosunu okur.
3. Splash Meet Manager ID Tarama (Dinamik Probe) [İPTAL EDİLDİ]:
   Gereksiz HTTP isteklerini ve sunucu yükünü önlemek için numaratör taraması devre dışı bırakıldı.
4. Django API Entegrasyonu:
   Bulunan canlı yarışları /api/canli-yaris-ekle/ endpoint'ine aktarır.
5. Cloud Scheduler & Karar Motoru:
   /api/canli-bekleyen-yaris/ adresini kontrol eder:
   - Start listesi ayrıştırılmamışsa -> Scheduler RESUME (Parser çalışmalı).
   - Start listesi tamam ve bugün yarış günüyse -> Scheduler RESUME (Canlı sonuçlar için).
   - Yarış günü değil veya tüm sonuçlar tamamsa -> Scheduler PAUSE (Maliyet tasarrufu).
"""

import os
import re
import logging
import json
from datetime import datetime, timezone, timedelta, date
from typing import List, Dict, Any, Optional, Tuple
from concurrent.futures import ThreadPoolExecutor

import warnings
import requests
from requests.adapters import HTTPAdapter
from bs4 import BeautifulSoup

# SSL uyarılarını bastır
warnings.filterwarnings("ignore")

# Türkiye Zaman Dilimi (UTC+3)
TR_TIMEZONE = timezone(timedelta(hours=3))

logger = logging.getLogger("TYFLiveScraper")
if not logger.handlers:
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

TYF_CANLI_SONUC_URL = "https://www.tyf.gov.tr/canli-sonuc/"
DEFAULT_API_BASE_URL = os.environ.get("DJANGO_API_BASE_URL", "https://ozztozz.pythonanywhere.com").rstrip("/")
DEFAULT_PROBE_COUNT = 0  # Numaratör taraması iptal edildi
FALLBACK_START_RACE_ID = 1005787

ALL_81_CITIES = [
    "ankara","istanbul"
]

# TYF genel (kök ve /tyf/) + 81 ilin tamamı
ALL_TARGET_LOCATIONS = ["", "tyf"] + ALL_81_CITIES


# ==============================================================================
# 1. HTTP BAĞLANTI HAVUZU (REQUESTS SESSION)
# ==============================================================================
def create_http_session(pool_size: int = 70) -> requests.Session:
    """Yüksek eşzamanlı istekler için HTTP Keep-Alive havuzlu requests Session üretir."""
    session = requests.Session()
    adapter = HTTPAdapter(
        pool_connections=pool_size,
        pool_maxsize=pool_size,
        max_retries=1
    )
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    session.headers.update({
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
        ),
        "Accept-Language": "tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7",
    })
    return session


GLOBAL_SESSION = create_http_session(pool_size=70)


def clean_meet_title(raw_title: str) -> str:
    """Başlıktan '- SPLASH Meet Manager 11' uzantısını temizler."""
    if not raw_title:
        return ""
    cleaned = re.sub(r"\s*-\s*SPLASH\s+Meet\s+Manager\s*\d*", "", raw_title, flags=re.IGNORECASE)
    return cleaned.strip()


# ==============================================================================
# 2. TARİH VE START LISTESI DEĞERLENDİRME MANTIĞI
# ==============================================================================
def evaluate_single_meet(meet: Dict[str, Any], today: Optional[date] = None) -> Tuple[bool, str]:
    """
    Tek bir yarış için parser'ın çalışması gerekip gerekmediğini kararlaştırır.
    API'den doğrudan gelen 'baslangic_tarihi' ve 'bitis_tarihi' (YYYY-MM-DD) alanlarını kullanır.
    
    Dönüş: (should_run: bool, reason: str)
    """
    if today is None:
        today = datetime.now(TR_TIMEZONE).date()

    meet_id = meet.get("id")
    title = meet.get("musabaka_adi") or meet.get("canli_url") or f"Yarış #{meet_id}"
    durum = (meet.get("durum") or "BEKLIYOR").upper()
    toplam_start = int(meet.get("toplam_start_listesi") or 0)
    islenen_start = int(meet.get("islenen_start_listesi") or 0)
    toplam_sonuc = int(meet.get("toplam_sonuc_listesi") or 0)
    islenen_sonuc = int(meet.get("islenen_sonuc_listesi") or 0)

    if durum == "TAMAMLANDI":
        return False, f"[{title}] Müsabaka tamamlanmış durumda."

    # 1. KURAL: Start listeleri henüz ayrıştırılmamış mı?
    startlist_tamam = (toplam_start > 0 and islenen_start >= toplam_start)
    if not startlist_tamam:
        kalan = max(0, toplam_start - islenen_start) if toplam_start > 0 else "Bilinmiyor"
        return True, f"[{title}] Start listeleri henüz ayrıştırılmadı (İşlenen: {islenen_start}/{toplam_start}, Kalan: {kalan}). Parser çalışmalı."

    # 2. KURAL: Start listeleri tamam, yarış günü kontrolü
    # API'den gelen ISO tarih bilgileri (YYYY-MM-DD)
    start_iso = meet.get("baslangic_tarihi")
    end_iso = meet.get("bitis_tarihi") or start_iso

    if start_iso and end_iso:
        today_str = today.isoformat()

        # A) Yarış henüz başlamadı (Gelecek tarih)
        if today_str < start_iso:
            return False, f"[{title}] Start listeleri hazır. Yarış {start_iso} tarihinde başlayacak. Şu an sonuç yok, scheduler duraklatılabilir."

        # B) Bugün yarış günü! (start_date <= today <= end_date)
        elif start_iso <= today_str <= end_iso:
            sonuclar_tamam = (toplam_sonuc > 0 and islenen_sonuc >= toplam_sonuc and durum == "TAMAMLANDI")
            if sonuclar_tamam:
                return False, f"[{title}] Bugün yarış günü fakat tüm sonuçlar tamamlandı ({islenen_sonuc}/{toplam_sonuc})."
            return True, f"[{title}] BUGÜN YARIŞ GÜNÜ ({start_iso} - {end_iso})! Canlı sonuçları yakalamak için parser aktif çalışmalı."

        # C) Yarış bitiş tarihi geçti (Geçmiş yarış)
        else:
            if durum != "TAMAMLANDI" and (toplam_sonuc == 0 or islenen_sonuc < toplam_sonuc):
                return True, f"[{title}] Yarış tarihi bitti ({end_iso}) fakat eksik sonuç listeleri var ({islenen_sonuc}/{toplam_sonuc}). Tamamlanması için parser çalışmalı."
            return False, f"[{title}] Yarış geçmiş tarihte bitti ({end_iso})."

    # Tarih bilgisi henüz yoksa güvenli modda çalıştır
    return True, f"[{title}] Tarih bilgisi henüz oluşmamış, güvenli modda start/sonuç kontrolü için çalıştırılıyor."


def evaluate_meets_schedule(meets: List[Dict[str, Any]], today: Optional[date] = None) -> Tuple[bool, List[str]]:
    """
    Tüm bekleyen canlı yarışları inceler.
    En az bir yarış için çalışma gerekiyorsa should_run = True döner.
    """
    if today is None:
        today = datetime.now(TR_TIMEZONE).date()

    if not meets:
        return False, ["Bekleyen veya işlemde canlı yarış bulunmuyor."]

    should_run = False
    reasons = []

    for m in meets:
        meet_run, reason = evaluate_single_meet(m, today=today)
        reasons.append(reason)
        if meet_run:
            should_run = True

    return should_run, reasons


# ==============================================================================
# 3. GOOGLE CLOUD SCHEDULER KONTROLCÜSÜ (GCP API)
# ==============================================================================
class CloudSchedulerController:
    """
    Google Cloud Scheduler Job kontrol sınıfı.
    GCP Scheduler Job'ını pause (duraklat) ve resume (etkinleştir) eder.
    """
    def __init__(
        self,
        project_id: Optional[str] = None,
        location_id: Optional[str] = None,
        job_name: Optional[str] = None
    ):
        self.project_id = project_id or os.environ.get("GCP_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT")
        self.location_id = location_id or os.environ.get("GCP_REGION") or os.environ.get("CLOUD_SCHEDULER_LOCATION", "europe-west1")
        self.job_name = job_name or os.environ.get("SCHEDULER_JOB_NAME") or os.environ.get("YUZME_SCHEDULER_JOB_ADI", "tyf-live-routine-scan")

        self._client = None
        self._job_path = None

    @property
    def client(self):
        if self._client is None:
            try:
                from google.cloud import scheduler_v1
                self._client = scheduler_v1.CloudSchedulerClient()
            except ImportError:
                raise ImportError(
                    "google-cloud-scheduler kütüphanesi yüklü değil. "
                    "Lütfen 'pip install google-cloud-scheduler' komutunu çalıştırın."
                )
        return self._client

    @property
    def job_path(self) -> str:
        if not self._job_path:
            if not self.project_id:
                raise ValueError("GCP_PROJECT veya GOOGLE_CLOUD_PROJECT ortam değişkeni tanımlanmalıdır.")
            self._job_path = self.client.job_path(self.project_id, self.location_id, self.job_name)
        return self._job_path

    def get_job_state(self) -> str:
        """Scheduler job'ının mevcut durumunu döner (örn: 'ENABLED', 'PAUSED')."""
        try:
            job = self.client.get_job(name=self.job_path)
            state_name = job.state.name if hasattr(job.state, "name") else str(job.state)
            return state_name
        except Exception as e:
            logger.warning(f"Job durumu okunamadı: {e}")
            return "UNKNOWN"

    def toggle_scheduler(self, has_race: bool, reason: str = "") -> bool:
        """Cloud Scheduler Job'ını aktif eder (RESUME) veya duraklatır (PAUSE)."""
        action = "RESUME" if has_race else "PAUSE"
        logger.info(f"[*] Cloud Scheduler İşlemi: {action} (Job: {self.job_name})")
        if reason:
            logger.info(f"    Gerekçe: {reason}")

        try:
            if has_race:
                self.client.resume_job(name=self.job_path)
                logger.info("  [+] Yarış/Startlist var: Cloud Scheduler başarıyla ETKİNLEŞTİRİLDİ (RESUMED).")
            else:
                self.client.pause_job(name=self.job_path)
                logger.info("  [+] Yarış/Görev yok: Cloud Scheduler başarıyla DURAKLATILDI (PAUSED).")
            return True
        except Exception as e:
            err_str = str(e)
            if "Cannot resume job that is not paused" in err_str or "already enabled" in err_str.lower():
                logger.info("  [*] Bilgi: Scheduler job zaten etkin durumda.")
                return True
            elif "Cannot pause job that is already paused" in err_str or "already paused" in err_str.lower():
                logger.info("  [*] Bilgi: Scheduler job zaten duraklatılmış durumda.")
                return True
            else:
                logger.error(f"  [!] Cloud Scheduler güncelleme hatası: {e}")
                return False


# ==============================================================================
# 4. TYF VE İL TEMSİLCİLİKLERİ TARAYICILARI
# ==============================================================================
def get_latest_race_number_from_api(api_base_url: str = DEFAULT_API_BASE_URL, session: Optional[requests.Session] = None) -> int:
    """
    API endpoint'ini (/api/canli-bekleyen-yaris/) sorgulayarak sistemdeki en son yarış numarasını alır.
    Bulamazsa FALLBACK_START_RACE_ID döner.
    """
    s = session or GLOBAL_SESSION
    endpoint = f"{api_base_url.rstrip('/')}/api/canli-bekleyen-yaris/"
    try:
        res = s.get(endpoint, timeout=8)
        if res.status_code == 200:
            data = res.json()
            latest = data.get("en_son_yaris_no")
            if latest and isinstance(latest, int) and latest > 1000000:
                logger.info(f"API'den en son yarış numarası alındı: #{latest}")
                return latest

            max_num = None
            for y in data.get("yarislar", []):
                m = re.search(r"cs-(\d+)", y.get("canli_url", ""))
                if m:
                    val = int(m.group(1))
                    if max_num is None or val > max_num:
                        max_num = val
            if max_num:
                logger.info(f"Yarış listesinden en son yarış numarası çıkarıldı: #{max_num}")
                return max_num
    except Exception as e:
        logger.warning(f"API'den son yarış numarası alınırken hata: {e}")

    logger.info(f"Varsayılan başlangıç yarış numarası kullanılıyor: #{FALLBACK_START_RACE_ID}")
    return FALLBACK_START_RACE_ID


def scrape_tyf_central_page(source_url: str = TYF_CANLI_SONUC_URL, session: Optional[requests.Session] = None) -> List[Dict[str, str]]:
    """TYF ana canli-sonuc sayfasını tarar."""
    logger.info(f"TYF merkezi canlı sonuç sayfası taranıyor: {source_url}")
    meets = []
    s = session or GLOBAL_SESSION

    try:
        res = s.get(source_url, timeout=12)
        if res.status_code != 200:
            return meets
        html = res.text
    except Exception as e:
        logger.warning(f"TYF merkezi sayfası çekilirken hata: {e}")
        return meets

    soup = BeautifulSoup(html, "html.parser")
    tables = soup.find_all("table")
    for table in tables:
        rows = table.find_all("tr")
        for row in rows:
            cols = row.find_all(["td", "th"])
            row_text = " ".join(c.get_text(strip=True) for c in cols)
            if "devam eden bir canlı yayın bulunmamaktadır" in row_text.lower():
                continue

            links = row.find_all("a", href=True)
            for link in links:
                href = link["href"].strip()
                if "canli.tyf.gov.tr" in href or "/cs-" in href:
                    if href.startswith("/"):
                        href = requests.compat.urljoin("https://canli.tyf.gov.tr", href)
                    elif not href.startswith("http"):
                        href = "https://" + href

                    title = link.get_text(strip=True)
                    date_text = ""
                    if len(cols) >= 2:
                        for c in cols:
                            text = c.get_text(strip=True)
                            if text and text != title and any(ch.isdigit() for ch in text):
                                date_text = text
                                break

                    city = ""
                    url_match = re.search(r"canli\.tyf\.gov\.tr/([^/]+)/", href, re.IGNORECASE)
                    if url_match:
                        slug = url_match.group(1).lower()
                        if slug not in ["public", "assets", "live", "static"]:
                            city = slug.capitalize()

                    meets.append({
                        "canli_url": href if href.endswith("/") else href + "/",
                        "musabaka_adi": title,
                        "tarih": date_text,
                        "sehir": city
                    })

    return meets


def check_single_city_page(city: str, session: Optional[requests.Session] = None) -> Optional[Dict[str, str]]:
    """Tek bir il temsilciliği sayfasını tarayıp CANLI SONUÇLAR butonunu arar."""
    s = session or GLOBAL_SESSION
    url = f"https://www.tyf.gov.tr/{city}-il-temsilciligi/"
    try:
        res = s.get(url, timeout=7)
        if res.status_code == 200:
            soup = BeautifulSoup(res.text, "html.parser")
            for a in soup.find_all("a", href=True):
                href = a["href"].strip()
                if "canli.tyf.gov.tr" in href and "cs-" in href:
                    title = a.get_text(strip=True)
                    if not title or title.upper() in ["CANLI SONUÇLAR", "CANLI SONUCLAR"]:
                        title = f"{city.capitalize()} TYF Canlı Müsabaka"
                    return {
                        "canli_url": href if href.endswith("/") else href + "/",
                        "musabaka_adi": title,
                        "sehir": city.capitalize(),
                        "tarih": ""
                    }
    except Exception:
        pass
    return None


def scan_all_city_representative_pages(cities: List[str] = ALL_81_CITIES, max_workers: int = 25, session: Optional[requests.Session] = None) -> List[Dict[str, str]]:
    """81 ilin temsilcilik sayfalarını paralel olarak tarar."""
    logger.info(f"{len(cities)} il temsilciliği sayfası taranıyor...")
    s = session or GLOBAL_SESSION
    results = []

    def _worker(c):
        return check_single_city_page(c, session=s)

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        for res in executor.map(_worker, cities):
            if res:
                results.append(res)
                logger.info(f"İl sayfasından canlı yarış bulundu: [{res['sehir']}] {res['canli_url']}")
    return results


def probe_single_race_url(item: Tuple[str, int], session: Optional[requests.Session] = None) -> Optional[Dict[str, str]]:
    """(lokasyon, id) kombinasyonunun canli.tyf.gov.tr'de 200 dönüp dönmediğini test eder."""
    s = session or GLOBAL_SESSION
    loc, num = item
    if not loc:
        url = f"https://canli.tyf.gov.tr/cs-{num}/"
        city_name = "TYF"
    elif loc == "tyf":
        url = f"https://canli.tyf.gov.tr/tyf/cs-{num}/"
        city_name = "TYF"
    else:
        url = f"https://canli.tyf.gov.tr/{loc}/cs-{num}/"
        city_name = loc.capitalize()

    try:
        res = s.get(url, timeout=4, stream=True)
        if res.status_code == 200:
            content_sample = res.raw.read(4096).decode("utf-8", errors="ignore")
            soup = BeautifulSoup(content_sample, "html.parser")
            title_tag = soup.find("title")
            raw_title = title_tag.get_text(strip=True) if title_tag else ""
            title = clean_meet_title(raw_title) or f"{city_name} Canlı Yarış #{num}"
            return {
                "canli_url": url,
                "musabaka_adi": title,
                "sehir": city_name,
                "tarih": ""
            }
    except Exception:
        pass
    return None


def scan_race_id_range(start_id: int, end_id: int, locations: List[str] = ALL_TARGET_LOCATIONS, max_workers: int = 40, session: Optional[requests.Session] = None) -> List[Dict[str, str]]:
    """Belirli bir ID aralığını TYF kök adresi (/cs-<id>/), /tyf/ ve 81 il için tarar."""
    s = session or GLOBAL_SESSION
    total_checks = (end_id - start_id + 1) * len(locations)
    logger.info(f"Yarış ID aralığı taranıyor: {start_id} - {end_id} ({len(locations)} lokasyon, toplam {total_checks} istek)...")
    tasks = [(loc, n) for loc in locations for n in range(start_id, end_id + 1)]
    found = []

    def _worker(task):
        return probe_single_race_url(task, session=s)

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        for res in executor.map(_worker, tasks):
            if res:
                found.append(res)
                logger.info(f"ID taramasında yarış bulundu: [{res['sehir']}] {res['musabaka_adi']} ({res['canli_url']})")
    return found


def scrape_all_tyf_live_sources(probe_range: Optional[Tuple[int, int]] = None, session: Optional[requests.Session] = None) -> List[Dict[str, str]]:
    """Tüm TYF canlı yarış kaynaklarını birleştirir."""
    s = session or GLOBAL_SESSION
    all_meets: List[Dict[str, str]] = []
    seen_urls = set()

    def add_meet(m: Dict[str, str]):
        u = m.get("canli_url", "").strip()
        if u and u not in seen_urls:
            seen_urls.add(u)
            if "SPLASH" not in m.get("musabaka_adi", "") and not m.get("musabaka_adi"):
                try:
                    res = s.get(u, timeout=4)
                    if res.status_code == 200:
                        soup = BeautifulSoup(res.text[:4096], "html.parser")
                        t = soup.find("title")
                        if t:
                            m["musabaka_adi"] = clean_meet_title(t.get_text(strip=True))
                except Exception:
                    pass
            all_meets.append(m)

    # 1. 81 İl Temsilciliği Sayfaları (En hızlı ve garanti yol)
    cities_meets = scan_all_city_representative_pages(session=s)
    for m in cities_meets:
        add_meet(m)

    # 2. TYF Merkezi Sayfa
    central = scrape_tyf_central_page(session=s)
    for m in central:
        add_meet(m)

    # 3. ID Aralığı (Numaratör) Taraması - İPTAL EDİLDİ
    if probe_range:
        logger.info("Numaratör (ID aralığı) taraması iptal edildiği için atlandı.")

    logger.info(f"Toplam tespit edilen tekil canlı yarış: {len(all_meets)}")
    return all_meets


def register_meet_via_api(api_base_url: str, meet: Dict[str, str], api_token: Optional[str] = None, session: Optional[requests.Session] = None) -> Dict[str, Any]:
    """Tespit edilen canlı yarışı Django /api/canli-yaris-ekle/ endpoint'ine POST eder."""
    s = session or GLOBAL_SESSION
    endpoint = f"{api_base_url.rstrip('/')}/api/canli-yaris-ekle/"
    headers = {
        "Content-Type": "application/json; charset=utf-8",
        "User-Agent": "Antigravity-TYF-Live-Bot/1.0"
    }
    if api_token:
        headers["Authorization"] = f"Bearer {api_token}"

    try:
        res = s.post(endpoint, json=meet, headers=headers, timeout=15)
        if res.status_code in (200, 201):
            return res.json()
        else:
            logger.error(f"API HTTP Hatası ({res.status_code}): {res.text[:200]}")
            return {"durum": "hata", "kod": res.status_code, "mesaj": res.text[:200]}
    except Exception as e:
        logger.error(f"API İsteğinde Hata: {e}")
        return {"durum": "hata", "mesaj": str(e)}


def scan_and_sync_meets(api_base_url: str = DEFAULT_API_BASE_URL, probe_range: Optional[Tuple[int, int]] = None, auto_probe_count: Optional[int] = None) -> List[Dict[str, Any]]:
    """
    1. ADIM: TYF merkezi sayfası + 81 İl sayfalarını + API'den alınan son yarış numarasından itibaren probe aralığını tara.
    Tespit edilen yarışları Django API'ye kaydet.
    """
    logger.info("--- [ADIM 1] TYF ve İl Temsilcilikleri Sayfaları Taranıyor ---")

    # Numaratör (ID probe) taraması iptal edildi; yalnızca resmi il ve TYF sayfaları taranır
    scraped_meets = scrape_all_tyf_live_sources(probe_range=None)
    results = []

    if not scraped_meets:
        logger.info("Tarama sonucunda eklenecek yeni canlı yarış bulunamadı.")
        return results

    for meet in scraped_meets:
        res = register_meet_via_api(api_base_url, meet)
        results.append({"meet": meet, "api_result": res})
        logger.info(f"API Kayıt Sonucu: {meet['musabaka_adi']} -> {res.get('durum')} (Yeni: {res.get('yeni_kayit')})")

    return results


def check_and_orchestrate(api_base_url: str = DEFAULT_API_BASE_URL, probe_range: Optional[Tuple[int, int]] = None, auto_probe_count: Optional[int] = None) -> bool:
    """
    1- TYF sayfaları (ve il temsilcilikleri) taranır, canlı yarış varsa API üzerinden siteye eklenir.
    2- Ekleme sonrasında /api/canli-bekleyen-yaris/ kontrol edilir.
       Parse edilmesi gereken yarış varsa Cloud Scheduler etkinleştirilir.
    """
    s = GLOBAL_SESSION

    # 1. ADIM: TYF Taraması
    scan_and_sync_meets(api_base_url=api_base_url, probe_range=probe_range, auto_probe_count=auto_probe_count)

    # 2. ADIM: Bekleyen yarış kontrolü
    logger.info(f"--- [ADIM 2] Bekleyen Yarışlar Kontrol Ediliyor ({api_base_url}/api/canli-bekleyen-yaris/) ---")
    endpoint = f"{api_base_url.rstrip('/')}/api/canli-bekleyen-yaris/"

    meets_data = []
    try:
        res = s.get(endpoint, timeout=15)
        if res.status_code == 200:
            res_json = res.json()
            meets_data = res_json.get("yarislar", [])
            logger.info(f"API'den dönen bekleyen yarış sayısı: {len(meets_data)}")
        else:
            alt_endpoint = f"{api_base_url.rstrip('/')}/api/canli-bekleyen-yarislar/"
            res_alt = s.get(alt_endpoint, timeout=15)
            if res_alt.status_code == 200:
                meets_data = res_alt.json().get("yarislar", [])
    except Exception as e:
        logger.error(f"Bekleyen yarışlar alınırken hata: {e}")

    # Cloud Scheduler kontrolcüsü
    scheduler = None
    try:
        scheduler = CloudSchedulerController()
    except Exception as e:
        logger.warning(f"CloudSchedulerController başlatılamadı: {e}")

    should_run, reasons = evaluate_meets_schedule(meets_data)

    logger.info("=== DEĞERLENDİRME SONUCU ===")
    for r in reasons:
        logger.info(f"- {r}")

    if should_run:
        logger.info(">> SONUÇ: PARSER ÇALIŞTIRILMALI (Scheduler Etkinleştiriliyor) <<")
        if scheduler:
            scheduler.toggle_scheduler(True)
    else:
        logger.info(">> SONUÇ: PARSE EDİLECEK YARIŞ YOK (Scheduler Duraklatılıyor) <<")
        if scheduler:
            scheduler.toggle_scheduler(False)

    return should_run


def tyf_live_scraper_handler(request):
    """
    Google Cloud Functions (gen2) / Cloud Run HTTP giriş noktası.
    Cloud Scheduler HTTP POST isteği attığında bu fonksiyon tetiklenir.
    """
    req_json = request.get_json(silent=True) or {}
    api_url = req_json.get("api_url") or request.args.get("api_url") or DEFAULT_API_BASE_URL
    # Numaratör taraması iptal edildi
    should_run = check_and_orchestrate(api_base_url=api_url, auto_probe_count=None)
    return (json.dumps({
        "durum": "basarili",
        "parser_calismali": should_run,
        "mesaj": "TYF tarama ve Scheduler orkestrasyonu tamamlandı."
    }, ensure_ascii=False), 200, {"Content-Type": "application/json; charset=utf-8"})


# GCP Cloud Functions varsayılan Entry point uyumluluk takma adı (Alias)
hello_http = tyf_live_scraper_handler


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="TYF Live Scraper and Scheduler Orchestrator")
    parser.add_argument("--api-url", default=DEFAULT_API_BASE_URL, help="Django API Base URL")
    parser.add_argument("--scan-only", action="store_true", help="Sadece TYF taraması yap ve API'ye ekle")
    parser.add_argument("--probe-start", type=int, default=None, help="Yarış ID tarama başlangıç (Örn: 1005787)")
    parser.add_argument("--probe-end", type=int, default=None, help="Yarış ID tarama bitiş (Örn: 1005800)")
    parser.add_argument("--probe-count", type=int, default=None, help="API'deki son yarış numarasından itibaren taranacak adres adedi (Örn: 100)")
    args = parser.parse_args()

    probe_rng = None
    if args.probe_start and args.probe_end:
        probe_rng = (args.probe_start, args.probe_end)

    if args.scan_only:
        scan_and_sync_meets(api_base_url=args.api_url, probe_range=probe_rng, auto_probe_count=args.probe_count)
    else:
        check_and_orchestrate(api_base_url=args.api_url, probe_range=probe_rng, auto_probe_count=args.probe_count)
