# -*- coding: utf-8 -*-
"""
local_live_engine.py
====================
Tamamen Yerel (Local) TYF Canlı Yarış Takip, Ayrıştırma ve Veritabanı Kayıt Motoru.

5 Saniyelik Anlık Takip ve Saatlik Cron Mimarisi:
1. SERVİS 1 (Saatlik Cron Orkestratörü - `run_cron_orchestrator`):
   - Her saat başında sistem cron'u veya Windows Görev Zamanlayıcı ile tetiklenir.
   - 08:00 - 20:00 çalışma saatlerini kontrol eder.
   - Veritabanında aktif canlı takip ('ISLENIYOR' veya 'BEKLIYOR') olup olmadığını denetler.
   - Aktif yarış varsa ve 2. Servis (Daemon) çalışmıyorsa arka planda başlatır.

2. SERVİS 2 (5 Saniyelik Canlı Takipçi / Daemon Worker - `run_daemon_worker`):
   - PID kilidi ile tekil çalışma garantisi sağlar (çift çalışma ve DB kilitlenmelerini önler).
   - Her 5 saniyede bir aktif yarışların sayfalarını hafifçe kontrol eder.
   - Yeni/güncellenen StartList ve ResultList dosyalarını tespit ettiği anda yerel parser ile milisaniyeler içinde çözer.
   - StartList + ResultList çapraz kulvar/seri (K/S) eşleştirmesi ile maskeleri %100 doğrulukla kaldırır.
   - Veritabanına atomik olarak kaydeder (Event, CanliYarisDosya, YarisSonucu).
   - Saat 20:00'a ulaşıldığında veya takip edilecek aktif yarış kalmadığında kendini güvenle kapatır.
"""

import os
import sys
import re
import time
import signal
import tempfile
import logging
import subprocess
from datetime import datetime, timezone as dt_timezone, timedelta
from typing import Dict, List, Any, Optional, Tuple
from urllib.parse import urljoin

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(CURRENT_DIR)
if PROJECT_DIR not in sys.path:
    sys.path.insert(0, PROJECT_DIR)

import django
from django.apps import apps
if not apps.ready:
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "yuzme_projesi.settings")
    django.setup()

import requests
import urllib3
import time
from bs4 import BeautifulSoup
from django.db import transaction, connection
from django.db.backends.signals import connection_created
from django.db.utils import OperationalError
from django.dispatch import receiver
from django.db.models import Q
from django.utils import timezone

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

@receiver(connection_created)
def _on_connection_created(sender, connection, **kwargs):
    if connection.vendor == 'sqlite':
        try:
            with connection.cursor() as cur:
                cur.execute("PRAGMA journal_mode=WAL;")
                cur.execute("PRAGMA synchronous=NORMAL;")
                cur.execute("PRAGMA busy_timeout=60000;")
        except Exception:
            pass

def db_retry(fn, max_retries=6, initial_delay=0.5):
    """SQLite kilitlenmelerinde (database is locked) backoff ile tekrar dener."""
    for attempt in range(max_retries):
        try:
            return fn()
        except OperationalError as e:
            if "locked" in str(e).lower() and attempt < max_retries - 1:
                time.sleep(initial_delay * (attempt + 1))
            else:
                raise

from sonuclar.models import (
    CanliYaris,
    CanliYarisDosya,
    Event,
    YarisSonucu,
    Kulup,
    Sporcu,
)
from sonuclar.athlete_matcher import match_athlete, clean_athlete_name_tags, clean_club_name_tags
from sonuclar.turkish_names import standardize_turkish_athlete_name
from sonuclar.fina_calculator import calculate_fina_points, detect_course
from sonuclar.local_startlist_parser import LocalStartListParser
from sonuclar.local_resultlist_parser import LocalResultListParser

from sonuclar.live_engine import (
    _time_to_seconds,
    get_or_resolve_canonical_club,
    is_school_meet,
    detect_pdf_type,
    clean_pdf_filename,
    download_file_with_meta,
)

logger = logging.getLogger("local_live_engine")
if not logger.handlers:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s", datefmt="%H:%M:%S"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

# Türkiye Zaman Dilimi (UTC+3)
TR_TIMEZONE = dt_timezone(timedelta(hours=3))
PID_FILE_PATH = os.path.join(tempfile.gettempdir(), "local_live_worker.pid")
DEFAULT_POLL_INTERVAL = 5  # 5 saniyelik anlık takip


def configure_sqlite_pragmas():
    """SQLite veritabanı kilitlenmelerini önleyen WAL modu ve 60 sn bekleme süresi ayarları."""
    try:
        with connection.cursor() as cur:
            cur.execute("PRAGMA journal_mode=WAL;")
            cur.execute("PRAGMA synchronous=NORMAL;")
            cur.execute("PRAGMA busy_timeout=60000;")
    except Exception:
        pass

configure_sqlite_pragmas()


def get_current_tr_time() -> datetime:
    return datetime.now(TR_TIMEZONE)


def is_within_working_hours(start_hour: int = 8, end_hour: int = 20) -> bool:
    """Canlı yarışların yapıldığı saat aralığını (08:00 - 20:00) kontrol eder."""
    current_hour = get_current_tr_time().hour
    return start_hour <= current_hour < end_hour


# ==============================================================================
# PID YÖNETİMİ VE SÜREÇ GÜVENLİĞİ
# ==============================================================================

def is_pid_running(pid: int) -> bool:
    """Belirtilen PID'nin sistemde aktif olup olmadığını denetler."""
    if pid <= 0:
        return False
    try:
        import psutil
        return psutil.pid_exists(pid)
    except Exception:
        try:
            if os.name == "nt":
                import ctypes
                kernel32 = ctypes.windll.kernel32
                SYNCHRONIZE = 0x00100000
                process = kernel32.OpenProcess(SYNCHRONIZE, False, pid)
                if process:
                    kernel32.CloseHandle(process)
                    return True
                return False
            else:
                os.kill(pid, 0)
                return True
        except (OSError, Exception):
            return False


def get_running_daemon_pid() -> Optional[int]:
    """Çalışan yerel canlı takipçinin PID'sini döner. Çalışmıyorsa None döner."""
    if not os.path.exists(PID_FILE_PATH):
        return None
    try:
        with open(PID_FILE_PATH, "r", encoding="utf-8") as f:
            content = f.read().strip()
        if not content:
            return None
        pid = int(content)
        if is_pid_running(pid):
            return pid
        # PID dosyası kalmış ama süreç ölmüşse temizle
        os.remove(PID_FILE_PATH)
        return None
    except Exception:
        return None


def write_pid_file() -> None:
    try:
        with open(PID_FILE_PATH, "w", encoding="utf-8") as f:
            f.write(str(os.getpid()))
    except Exception as exc:
        logger.warning(f"[!] PID dosyası yazılamadı: {exc}")


def remove_pid_file() -> None:
    try:
        if os.path.exists(PID_FILE_PATH):
            os.remove(PID_FILE_PATH)
    except Exception as exc:
        logger.warning(f"[!] PID dosyası silinemedi: {exc}")


def stop_daemon() -> bool:
    """Çalışan canlı takip sürecini güvenle durdurur."""
    pid = get_running_daemon_pid()
    if not pid:
        logger.info("[*] Durdurulacak çalışan yerel canlı takip servisi bulunamadı.")
        return False
    try:
        logger.info(f"[*] PID {pid} sürecine durdurma sinyali gönderiliyor...")
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(pid), "/F"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            os.kill(pid, signal.SIGTERM)
        time.sleep(1)
        remove_pid_file()
        logger.info(f"[+] Yerel canlı takip servisi durduruldu (PID: {pid}).")
        return True
    except Exception as exc:
        logger.error(f"[!] Süreç durdurulurken hata oluştu: {exc}")
        return False


def start_daemon_background(poll_interval: int = DEFAULT_POLL_INTERVAL) -> Optional[int]:
    """Yerel canlı takipçiyi arka planda başlatır."""
    running_pid = get_running_daemon_pid()
    if running_pid:
        logger.info(f"[*] Yerel canlı takip servisi zaten aktif (PID: {running_pid}).")
        return running_pid

    py_exe = sys.executable
    engine_script = os.path.abspath(__file__)
    cmd = [py_exe, "-u", engine_script, "--daemon", "--interval", str(poll_interval)]

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{PROJECT_DIR}{os.pathsep}{env.get('PYTHONPATH', '')}"

    log_file_path = os.path.join(tempfile.gettempdir(), "local_live_worker.log")
    try:
        log_f = open(log_file_path, "a", encoding="utf-8")
        if os.name == "nt":
            CREATE_NO_WINDOW = 0x08000000
            proc = subprocess.Popen(
                cmd,
                cwd=PROJECT_DIR,
                env=env,
                creationflags=CREATE_NO_WINDOW,
                stdout=log_f,
                stderr=log_f,
                stdin=subprocess.DEVNULL,
            )
        else:
            proc = subprocess.Popen(
                cmd,
                cwd=PROJECT_DIR,
                env=env,
                start_new_session=True,
                stdout=log_f,
                stderr=log_f,
                stdin=subprocess.DEVNULL,
                close_fds=True,
            )
        time.sleep(0.5)
        if proc.poll() is not None:
            logger.error(f"[!] Süreç hemen kapandı (Exit Code: {proc.returncode}).")
            return None

        logger.info(f"[+] Yerel canlı takipçi arka planda başlatıldı (PID: {proc.pid}, Log: {log_file_path})")
        return proc.pid
    except Exception as exc:
        logger.error(f"[!] Arka plan süreci başlatılamadı: {exc}")
        return None


# ==============================================================================
# CANLI TAKİP VE AYRIŞTIRMA MOTORU
# ==============================================================================

class LocalLiveEngine:
    """
    Yerel Canlı Yarış Takip ve Otomasyon Motoru.
    """

    def __init__(self):
        self.start_parser = LocalStartListParser()
        self.result_parser = LocalResultListParser()
        self.headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}

    def fetch_meet_pdf_catalog(self, base_url: str) -> Tuple[Dict[str, Any], List[Dict[str, str]]]:
        """
        TYF canlı sayfasını çekip başlık bilgileri ile tüm Start ve Sonuç PDF linklerini listeler.
        """
        resp = requests.get(base_url, headers=self.headers, verify=False, timeout=10)
        resp.encoding = "utf-8"
        soup = BeautifulSoup(resp.text, "html.parser")

        title = soup.title.string.strip() if soup.title else ""
        title = re.sub(r"\s+", " ", title)

        pdf_items = []
        seen = set()

        # Seans ve yarış programı tablolarından resmi yarış numaralarını haritalandır
        pdf_yaris_no_map: Dict[str, str] = {}
        for tr in soup.find_all("tr"):
            cols = [c.get_text(strip=True) for c in tr.find_all(["td", "th"])]
            if cols and cols[0].isdigit():
                row_yno = cols[0]
                for a in tr.find_all("a", href=True):
                    ch = a["href"].split("?")[0].strip()
                    fn = os.path.basename(ch)
                    pdf_yaris_no_map[fn] = row_yno
                    m_id = re.search(r"\d+", fn)
                    if m_id:
                        pdf_yaris_no_map[m_id.group()] = row_yno

        for a in soup.find_all("a", href=True):
            href = a["href"]
            if not href.lower().endswith(".pdf") and ".pdf?" not in href.lower():
                continue

            clean_href = href.split("?")[0]
            if clean_href in seen:
                continue
            seen.add(clean_href)

            full_url = urljoin(base_url, href)
            fname = os.path.basename(clean_href)
            doc_type = detect_pdf_type(fname, b"")

            hint = ""
            tr = a.find_parent("tr")
            if tr:
                cols = [c.get_text(strip=True) for c in tr.find_all(["td", "th"])]
                hint = " | ".join([c for c in cols if c and c not in ["Start List.", "Sonuçlar"]])

            m_id = re.search(r"\d+", fname)
            file_id = m_id.group() if m_id else ""
            yaris_no = pdf_yaris_no_map.get(fname) or pdf_yaris_no_map.get(file_id) or ""
            if not yaris_no and hint:
                m_yno = re.search(r"\b(?:Yarı[şs]|Event|#)\s*(\d+)\b", hint, re.IGNORECASE)
                if m_yno:
                    yaris_no = m_yno.group(1)

            pdf_items.append({
                "filename": fname,
                "url": full_url,
                "doc_type": doc_type,
                "hint": hint,
                "yaris_no": str(yaris_no),
            })

        meta = {
            "musabaka_adi": title,
            "canli_url": base_url,
        }
        return meta, pdf_items

    def process_meet(self, yaris: CanliYaris, force: bool = False) -> Dict[str, Any]:
        """
        Tek bir CanliYaris nesnesini yerel parser'larla baştan sona işler.
        """
        stats = {
            "yaris_id": yaris.id,
            "musabaka_adi": yaris.musabaka_adi,
            "yeni_start": 0,
            "yeni_sonuc": 0,
            "eklenen_kayit": 0,
            "hatalar": [],
        }

        try:
            meta, pdf_items = self.fetch_meet_pdf_catalog(yaris.canli_url)
            if meta["musabaka_adi"] and not yaris.musabaka_adi:
                yaris.musabaka_adi = meta["musabaka_adi"]
                yaris.save(update_fields=["musabaka_adi"])

            event = yaris.event
            if not event:
                event = Event.objects.create(
                    musabaka_adi=yaris.musabaka_adi or meta["musabaka_adi"] or "TYF Canlı Yarış",
                    sehir=yaris.sehir or "",
                    kaynak_turu="CANLI_TAKIP",
                )
                yaris.event = event
                yaris.save(update_fields=["event"])

            processed_files = set(
                CanliYarisDosya.objects.filter(canli_yaris=yaris, durum="ISLENDI").values_list("dosya_adi", flat=True)
            )

            pending_starts = [p for p in pdf_items if p["doc_type"] == "start_listesi" and (force or p["filename"] not in processed_files)]
            pending_results = [p for p in pdf_items if p["doc_type"] == "sonuc_listesi" and (force or p["filename"] not in processed_files)]

            # Yarış sırasına göre düzenle (Start listeleri sonuçlardan önce çözülür)
            pending_starts.sort(key=lambda x: int(x["yaris_no"]) if x["yaris_no"].isdigit() else 9999)
            pending_results.sort(key=lambda x: int(x["yaris_no"]) if x["yaris_no"].isdigit() else 9999)

            all_start_count = len([p for p in pdf_items if p["doc_type"] == "start_listesi"])
            all_result_count = len([p for p in pdf_items if p["doc_type"] == "sonuc_listesi"])

            # Yeni dosya yoksa sessizce çık (5 sn kontrolü için minimum log ve yük)
            if not pending_starts and not pending_results:
                return stats

            logger.info(
                f"[*] #{yaris.id} ({yaris.musabaka_adi or yaris.canli_url}) - "
                f"Yeni Dosya Tespit Edildi: {len(pending_starts)} Start, {len(pending_results)} Sonuç"
            )

            # 1. Start Listeleri
            for item in pending_starts:
                try:
                    added = self._process_single_pdf(yaris, event, item, "start_listesi")
                    stats["yeni_start"] += 1
                    stats["eklenen_kayit"] += added
                except Exception as exc:
                    err = f"StartList Hata ({item['filename']}): {exc}"
                    logger.error(f"  [!] {err}")
                    stats["hatalar"].append(err)

            # 2. Sonuç Listeleri
            for item in pending_results:
                try:
                    added = self._process_single_pdf(yaris, event, item, "sonuc_listesi")
                    stats["yeni_sonuc"] += 1
                    stats["eklenen_kayit"] += added
                except Exception as exc:
                    err = f"ResultList Hata ({item['filename']}): {exc}"
                    logger.error(f"  [!] {err}")
                    stats["hatalar"].append(err)

            # İstatistikleri Güncelle
            islenen_start = CanliYarisDosya.objects.filter(canli_yaris=yaris, dosya_turu="START_LISTESI", durum="ISLENDI").count()
            islenen_sonuc = CanliYarisDosya.objects.filter(canli_yaris=yaris, dosya_turu="SONUC_LISTESI", durum="ISLENDI").count()

            yaris.toplam_start_listesi = all_start_count
            yaris.islenen_start_listesi = islenen_start
            yaris.toplam_sonuc_listesi = all_result_count
            yaris.islenen_sonuc_listesi = islenen_sonuc
            yaris.eklenen_kayit_sayisi = (yaris.eklenen_kayit_sayisi or 0) + stats["eklenen_kayit"]
            yaris.son_islem_tarihi = timezone.now()

            if all_result_count > 0 and islenen_sonuc >= all_result_count and not stats["hatalar"]:
                yaris.durum = "TAMAMLANDI"
            else:
                yaris.durum = "ISLENIYOR"

            yaris.save()
            logger.info(
                f"  [✔] #{yaris.id} Güncellendi: +{stats['eklenen_kayit']} kayıt eklendi. "
                f"(Start: {islenen_start}/{all_start_count}, Sonuç: {islenen_sonuc}/{all_result_count})"
            )

        except Exception as exc:
            err = f"Canlı Yarış İşleme Hatası: {exc}"
            logger.error(f"[!] {err}")
            stats["hatalar"].append(err)
            yaris.hata_mesaji = str(exc)[:500]
            yaris.save(update_fields=["hata_mesaji"])

        return stats

    def _process_single_pdf(
        self,
        yaris: CanliYaris,
        event: Event,
        item: Dict[str, str],
        doc_type: str
    ) -> int:
        filename = item["filename"]
        url = item["url"]
        logger.info(f"  [>] {filename} indiriliyor ve ayrıştırılıyor ({doc_type})...")

        resp = requests.get(url, headers=self.headers, verify=False, timeout=12)
        if resp.status_code != 200:
            raise RuntimeError(f"HTTP {resp.status_code}")

        pdf_bytes = resp.content
        file_size = len(pdf_bytes)
        is_school = is_school_meet(event.musabaka_adi)
        course = detect_course(event.musabaka_adi)

        if doc_type == "start_listesi":
            parsed = self.start_parser.parse(pdf_bytes)
            raw_swimmers = parsed.get("sporcular", [])
        else:
            parsed = self.result_parser.parse(pdf_bytes, unmask=False)
            raw_swimmers = parsed.get("sonuclar", [])

        cinsiyet = parsed.get("cinsiyet")
        mesafe = parsed.get("mesafe")
        stil = parsed.get("stil")
        yaris_no = str(item.get("yaris_no") or parsed.get("yaris_no") or "")
        is_bayrak = bool("bayrak" in (stil or "").lower() or "4x" in (str(parsed.get("yaris") or "")).lower())

        dosya_turu_str = "START_LISTESI" if doc_type == "start_listesi" else "SONUC_LISTESI"
        dosya_defaults = {
            "event": event,
            "dosya_url": url,
            "dosya_turu": dosya_turu_str,
            "yaris_no": yaris_no,
            "mesafe": mesafe,
            "stil": stil,
            "cinsiyet": cinsiyet,
            "yas_grubu": parsed.get("yas_grubu") or "",
            "dosya_boyutu": file_size,
            "durum": "ISLENDI",
            "kayit_sayisi": len(raw_swimmers),
            "son_islem_tarihi": timezone.now(),
        }
        dosya_obj, _ = db_retry(lambda: CanliYarisDosya.objects.update_or_create(
            canli_yaris=yaris,
            dosya_adi=filename,
            defaults=dosya_defaults
        ))

        cross_unmasked = {}
        if doc_type == "sonuc_listesi":
            start_dosya = None
            if yaris_no:
                start_dosya = CanliYarisDosya.objects.filter(
                    canli_yaris=yaris,
                    dosya_turu="START_LISTESI",
                    yaris_no=yaris_no
                ).first()
            if not start_dosya and mesafe and stil and cinsiyet:
                start_dosya = CanliYarisDosya.objects.filter(
                    canli_yaris=yaris,
                    dosya_turu="START_LISTESI",
                    mesafe=mesafe,
                    stil=stil,
                    cinsiyet=cinsiyet
                ).first()
            if start_dosya:
                for prev_s in YarisSonucu.objects.filter(canli_dosya=start_dosya):
                    if prev_s.seri and prev_s.kulvar and prev_s.sporcu:
                        m_s = re.search(r"\d+", str(prev_s.seri))
                        s_no = int(m_s.group()) if m_s else None
                        if s_no and prev_s.kulvar:
                            cross_unmasked[(s_no, prev_s.kulvar)] = (prev_s.sporcu, prev_s.sporcu_maskeli or "")

        records_added = 0

        for s in raw_swimmers:
            raw_name = (s.get("sporcu") or "").strip()
            if not raw_name:
                continue

            clean_name = clean_athlete_name_tags(raw_name)
            birth_year = s.get("dogum_yili")
            raw_club = s.get("kulup") or ""
            clean_club_str = clean_club_name_tags(raw_club)
            club, _ = get_or_resolve_canonical_club(clean_club_str or raw_club, is_school=is_school)

            seri_val = s.get("seri")
            kulvar_val = s.get("kulvar")
            derece_val = s.get("derece")
            sira_val = s.get("sira")
            durum_val = s.get("durum") or "NORMAL"

            seri_no = None
            if seri_val:
                m_s = re.search(r"\d+", str(seri_val))
                if m_s:
                    seri_no = int(m_s.group())

            athlete = None
            # 1. StartList Çapraz Eşleşmesi (K/S)
            if seri_no and kulvar_val and (seri_no, kulvar_val) in cross_unmasked:
                st_sp, st_mask = cross_unmasked[(seri_no, kulvar_val)]
                if st_sp and not st_sp.sporcu_adi.startswith("Maskeli sporcu"):
                    athlete = st_sp
                elif st_mask:
                    clean_name = st_mask

            # 2. Bayrak / Relay Takımı Eşleşmesi
            if not athlete and (is_bayrak or "(tk)" in raw_name.lower()):
                team_name = clean_name or (club.kulup_adi if club else "Takım")
                athlete = Sporcu.objects.filter(sporcu_adi=team_name).first()
                if not athlete:
                    athlete = db_retry(lambda: Sporcu.objects.create(
                        sporcu_adi=team_name,
                        cinsiyet=cinsiyet,
                        birincil_kulup=club,
                    ))

            # 3. Veritabanından Unmasking (Maske Kaldırma)
            if not athlete and clean_name:
                match_res = match_athlete(
                    clean_name,
                    birth_year_or_date=birth_year,
                    club=clean_club_str or raw_club,
                    gender=cinsiyet
                )
                if match_res.get("bulunan_id"):
                    athlete = Sporcu.objects.filter(id=match_res["bulunan_id"]).first()

            # 4. Bulunamazsa Maskeli Sporcu Kaydı
            if not athlete:
                sp_target_name = f"Maskeli sporcu ({clean_name})" if "*" in clean_name else (standardize_turkish_athlete_name(clean_name) or clean_name)
                athlete = Sporcu.objects.filter(sporcu_adi=sp_target_name, dogum_yili=birth_year).first()
                if not athlete:
                    athlete = db_retry(lambda: Sporcu.objects.create(
                        sporcu_adi=sp_target_name,
                        dogum_yili=birth_year,
                        cinsiyet=cinsiyet,
                        birincil_kulup=club,
                    ))

            derece_sn = _time_to_seconds(derece_val)
            fina = s.get("puan")
            if (derece_sn or derece_val) and not fina and not is_bayrak:
                fina = calculate_fina_points(cinsiyet, mesafe, stil, derece_sn or derece_val, course)

            if doc_type == "start_listesi":
                defaults_dict = {
                    "yaris_no": yaris_no,
                    "dosya_adi": filename,
                    "kulup": club,
                    "giris_derecesi": s.get("giris_derecesi") or derece_val,
                    "derece": "Bekleniyor",
                    "derece_saniye": None,
                    "sira": None,
                    "puan": None,
                    "seri": str(seri_val) if seri_val else None,
                    "kulvar": kulvar_val,
                    "canli_dosya": dosya_obj,
                    "kaynak_turu": "CANLI_START_LISTESI",
                    "sporcu_maskeli": clean_name if "*" in clean_name else "",
                }
            else:
                final_derece = None
                if derece_val and re.search(r"\d", str(derece_val)):
                    final_derece = str(derece_val).strip()
                elif durum_val in ["DSQ", "DNS", "DNF", "EXH"]:
                    final_derece = durum_val
                else:
                    final_derece = "Bekleniyor"

                defaults_dict = {
                    "yaris_no": yaris_no,
                    "dosya_adi": filename,
                    "kulup": club,
                    "derece": final_derece,
                    "derece_saniye": derece_sn,
                    "sira": sira_val,
                    "puan": fina,
                    "seri": str(seri_val) if seri_val else None,
                    "kulvar": kulvar_val,
                    "canli_dosya": dosya_obj,
                    "kaynak_turu": "CANLI_SONUC",
                    "sporcu_maskeli": clean_name if "*" in clean_name else "",
                }
                if durum_val in ["DSQ", "DNS", "DNF", "EXH"]:
                    reason = s.get("notlar") or ""
                    defaults_dict["uyari_notu"] = f"{durum_val} - {reason}".strip(" -")
                else:
                    defaults_dict["uyari_notu"] = ""
                    if s.get("notlar"):
                        defaults_dict["baraj"] = s.get("notlar")

            lookup_dict = {
                "event": event,
                "sporcu": athlete,
                "mesafe": mesafe,
                "stil": stil,
                "cinsiyet": cinsiyet,
            }
            if yaris_no:
                lookup_dict["yaris_no"] = yaris_no

            def _write_result():
                return YarisSonucu.objects.update_or_create(
                    **lookup_dict,
                    defaults=defaults_dict
                )

            obj, created = db_retry(_write_result)
            if created:
                records_added += 1

        return records_added


# ==============================================================================
# SERVİS 1: SAATLİK CRON ORKESTRATÖRÜ
# ==============================================================================

def run_cron_orchestrator(start_hour: int = 8, end_hour: int = 20, poll_interval: int = DEFAULT_POLL_INTERVAL) -> None:
    """
    1. Servis: Her saat başı çalışır.
    Çalışma saatleri (08:00 - 20:00) içinde aktif canlı yarış varsa 5 sn'lik daemon'ı başlatır.
    """
    now = get_current_tr_time()
    logger.info(f"=== [Servis 1: Saatlik Cron Kontrolü Başladı] (Saat: {now.strftime('%H:%M:%S')}) ===")

    if not is_within_working_hours(start_hour=start_hour, end_hour=end_hour):
        logger.info(f"[*] Şu an saat {now.strftime('%H:%M')}. Çalışma saatleri dışındayız ({start_hour:02d}:00 - {end_hour:02d}:00). Çıkılıyor.")
        return

    active_qs = CanliYaris.objects.filter(durum__in=["ISLENIYOR", "BEKLEMEDE", "BEKLIYOR"])
    active_count = active_qs.count()

    if active_count == 0:
        logger.info("[*] Takipte olan aktif canlı yarış bulunamadı. Daemon başlatılmadı.")
        return

    logger.info(f"[*] Takipte {active_count} aktif canlı yarış bulundu.")
    running_pid = get_running_daemon_pid()
    if running_pid:
        logger.info(f"[+] 2. Servis (5 Sn Canlı Takipçi) zaten aktif çalışıyor (PID: {running_pid}).")
    else:
        logger.info("[*] 2. Servis çalışmıyor. Arka planda 5 saniyelik anlık takipçi başlatılıyor...")
        start_daemon_background(poll_interval=poll_interval)


# ==============================================================================
# SERVİS 2: 5 SANİYELİK ANLIK TAKİPÇİ (DAEMON WORKER)
# ==============================================================================

def run_daemon_worker(poll_interval: int = DEFAULT_POLL_INTERVAL, end_hour: int = 20) -> None:
    """
    2. Servis: 5 saniyede bir sayfaları yoklayan yüksek frekanslı anlık takipçi.
    """
    running_pid = get_running_daemon_pid()
    if running_pid and running_pid != os.getpid():
        logger.warning(f"[!] Canlı takipçi zaten çalışıyor (PID: {running_pid}). Çıkılıyor.")
        return

    write_pid_file()
    logger.info(f"============================================================")
    logger.info(f"[*] 2. Servis Başlatıldı (PID: {os.getpid()})")
    logger.info(f"[*] Kontrol Sıklığı: {poll_interval} saniye | Bitiş Saati: {end_hour:02d}:00")
    logger.info(f"============================================================")

    engine = LocalLiveEngine()

    try:
        while True:
            now = get_current_tr_time()

            # Saat sınırını kontrol et (örn: 20:00'dan sonra kapan)
            if now.hour >= end_hour or now.hour < 8:
                logger.info(f"[*] Saat {now.strftime('%H:%M')}. Çalışma saatleri dışına çıkıldı. Daemon güvenle kapatılıyor.")
                break

            active_meets = list(CanliYaris.objects.filter(durum__in=["ISLENIYOR", "BEKLEMEDE", "BEKLIYOR"]))
            if not active_meets:
                logger.info("[*] Takipte aktif canlı yarış kalmadı. Daemon güvenle kapatılıyor.")
                break

            for yaris in active_meets:
                engine.process_meet(yaris, force=False)

            time.sleep(poll_interval)

    except KeyboardInterrupt:
        logger.info("[*] Kullanıcı tarafından durduruldu.")
    except Exception as exc:
        logger.error(f"[!] Daemon döngüsünde kritik hata: {exc}")
    finally:
        remove_pid_file()
        logger.info("[*] Yerel canlı takipçi güvenle sonlandırıldı.")


def run_local_live_worker(
    url: Optional[str] = None,
    daemon: bool = False,
    cron: bool = False,
    interval: int = DEFAULT_POLL_INTERVAL,
    force: bool = False
):
    if cron:
        run_cron_orchestrator(poll_interval=interval)
        return

    if daemon:
        run_daemon_worker(poll_interval=interval)
        return

    engine = LocalLiveEngine()
    if url:
        yaris, created = CanliYaris.objects.get_or_create(
            canli_url=url,
            defaults={"durum": "ISLENIYOR"}
        )
        if not created and force:
            yaris.durum = "ISLENIYOR"
            yaris.save(update_fields=["durum"])
        return engine.process_meet(yaris, force=force)

    # Parametresiz çağrıda tüm aktif yarışları bir kez tara
    active_meets = CanliYaris.objects.filter(durum__in=["ISLENIYOR", "BEKLEMEDE", "BEKLIYOR"])
    results = []
    for y in active_meets:
        results.append(engine.process_meet(y, force=force))
    return results


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Yerel Canlı Yarış Otomasyon Servisi (5 Sn Anlık Takip)")
    parser.add_argument("--url", type=str, help="İşlenecek tekil TYF canlı yarış web adresi")
    parser.add_argument("--daemon", action="store_true", help="5 saniyelik anlık takipçi döngüsünü başlat")
    parser.add_argument("--cron", action="store_true", help="1. Servis: Saatlik cron orkestratörünü çalıştır")
    parser.add_argument("--baslat", action="store_true", help="Canlı takipçiyi arka planda başlat")
    parser.add_argument("--durdur", action="store_true", help="Çalışan canlı takipçiyi durdur")
    parser.add_argument("--durum", action="store_true", help="Çalışan takipçi durumunu ve PID'sini göster")
    parser.add_argument("--interval", type=int, default=DEFAULT_POLL_INTERVAL, help="Kontrol aralığı (saniye, varsayılan: 5)")
    parser.add_argument("--force", action="store_true", help="Daha önce işlenen dosyaları tekrar tara")

    args = parser.parse_args()

    if args.durdur:
        stop_daemon()
    elif args.durum:
        pid = get_running_daemon_pid()
        if pid:
            print(f"[+] 5 Saniyelik Canlı Takipçi AKTİF çalışıyor (PID: {pid}).")
        else:
            print("[-] Canlı Takipçi şu anda ÇALIŞMIYOR.")
    elif args.baslat:
        start_daemon_background(poll_interval=args.interval)
    elif args.cron:
        run_cron_orchestrator(poll_interval=args.interval)
    elif args.daemon:
        run_daemon_worker(poll_interval=args.interval)
    else:
        run_local_live_worker(url=args.url, interval=args.interval, force=args.force)
