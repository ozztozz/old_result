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
import json
import hashlib
import time
import signal
import tempfile
import logging
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timezone as dt_timezone, timedelta
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
from requests.adapters import HTTPAdapter
import urllib3
from urllib3.util.retry import Retry
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
from sonuclar.athlete_matcher import match_athlete, clean_athlete_name_tags, clean_club_name_tags, normalize_tr
from sonuclar.turkish_names import standardize_turkish_athlete_name
from sonuclar.fina_calculator import calculate_fina_points, detect_course
from sonuclar.local_startlist_parser import LocalStartListParser
from sonuclar.local_resultlist_parser import LocalResultListParser
from sonuclar.local_baraj_parser import (
    fetch_and_parse_reglaman_barajlar,
    evaluate_baraj_for_result,
)

from sonuclar.live_engine import (
    _time_to_seconds,
    get_or_resolve_canonical_club,
    is_school_meet,
    detect_pdf_type,
    clean_pdf_filename,
    download_file_with_meta,
    fetch_remote_headers_map,
    parse_tr_date_range,
)

logger = logging.getLogger("local_live_engine")
if not logger.handlers:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s", datefmt="%H:%M:%S"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)


def _log_unmatched_result_record(record: Dict[str, Any]) -> None:
    """StartList ile eşleşemeyen ResultList satırlarını analiz için JSONL dosyasına yazar."""
    try:
        log_dir = os.path.join(os.path.dirname(PROJECT_DIR), "logs")
        os.makedirs(log_dir, exist_ok=True)
        log_path = os.path.join(log_dir, "unmatched_result_records.jsonl")
        with open(log_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")
    except Exception:
        pass


def _extract_relay_suffix(name: str) -> str:
    """Bayrak takım adının sonundaki A/B/C/1/2/3 gibi alt-takım ekini ayırır."""
    m = re.search(r'(?:\s+|-)([A-D]|[1-4])(?:\s+tak[ıi]m[ıi])?$', (name or "").strip(), re.IGNORECASE)
    return m.group(1).upper() if m else ""


def _resolve_or_create_relay_team(team_name: str, club: Optional[Kulup] = None) -> Sporcu:
    """
    Bayrak/Takım sporcu kaydını cinsiyet='Takım' üzerinden yüksek esneklikle eşleştirir;
    bulunamazsa cinsiyet='Takım' olarak yeni kayıt oluşturur.
    """
    from rapidfuzz import fuzz

    clean = (team_name or "").strip() or (club.kulup_adi if club else "Takım")
    norm_target = normalize_tr(clean)
    target_suffix = _extract_relay_suffix(clean)

    # 1. Birebir isim eşleşmesi (Takım öncelikli)
    exact = (
        Sporcu.objects.filter(sporcu_adi=clean, cinsiyet="Takım").first()
        or Sporcu.objects.filter(sporcu_adi__iexact=clean, cinsiyet="Takım").first()
        or Sporcu.objects.filter(sporcu_adi=clean, dogum_yili__isnull=True).first()
    )
    if exact:
        return exact

    # 2. Çözümlenmiş kulüp üzerinden Takım eşleşmesi
    if club:
        club_teams = list(Sporcu.objects.filter(cinsiyet="Takım", birincil_kulup=club))
        for ct in club_teams:
            if _extract_relay_suffix(ct.sporcu_adi) == target_suffix:
                return ct
        if len(club_teams) == 1 and not target_suffix:
            return club_teams[0]

    # 3. Tüm 'Takım' kayıtları arasında yüksek esnekliğe sahip bulanık eşleşme
    best_cand = None
    best_score = 0.0
    for cand in Sporcu.objects.filter(cinsiyet="Takım"):
        if _extract_relay_suffix(cand.sporcu_adi) != target_suffix:
            continue
        norm_cand = normalize_tr(cand.sporcu_adi)
        if not norm_cand:
            continue
        if norm_cand == norm_target:
            return cand
        score = max(fuzz.ratio(norm_target, norm_cand), fuzz.token_set_ratio(norm_target, norm_cand) * 0.96)
        if score > best_score:
            best_score = score
            best_cand = cand

    if best_cand and best_score >= 82.0:
        return best_cand

    # 4. Bulunamazsa yeni Takım kaydı oluştur
    return Sporcu.objects.create(
        sporcu_adi=clean,
        cinsiyet="Takım",
        birincil_kulup=club,
    )


_NAME_DICT_CACHE: Dict[str, Any] = {"ts": 0.0, "fn": {"ERKEK": {}, "KADIN": {}}, "ln": {}}
_NAME_DICT_TTL = 3600.0


def _get_name_dict_cache() -> Dict[str, Any]:
    """Gerçek sporcu ad/soyad sözlüğünü (freq>=3, len>=4) süreç başına 1 kez RAM'e yükler."""
    now = time.time()
    if now - _NAME_DICT_CACHE["ts"] < _NAME_DICT_TTL and _NAME_DICT_CACHE["ln"]:
        return _NAME_DICT_CACHE

    from collections import Counter, defaultdict

    def _tr_upper(s: str) -> str:
        return s.replace("i", "İ").replace("ı", "I").upper()

    def _tr_title(s: str) -> str:
        return (s[0].replace("i", "İ").replace("ı", "I").upper() + s[1:].replace("İ", "i").replace("I", "ı").lower()) if s else ""

    fn_raw = {"ERKEK": defaultdict(Counter), "KADIN": defaultdict(Counter)}
    ln_raw = defaultdict(Counter)

    for name, cins in Sporcu.objects.exclude(sporcu_adi__startswith="Maskeli").filter(
        cinsiyet__in=("ERKEK", "KADIN")
    ).values_list("sporcu_adi", "cinsiyet").iterator():
        toks = (name or "").split()
        if len(toks) < 2:
            continue
        for t in toks[:-1]:
            nt = normalize_tr(t).lower()
            if len(nt) >= 4 and nt.isalpha():
                fn_raw[cins][nt][t] += 1
        lt = normalize_tr(toks[-1]).lower()
        if len(lt) >= 4 and lt.isalpha():
            ln_raw[lt][toks[-1]] += 1

    _NAME_DICT_CACHE["fn"] = {
        g: {nt: _tr_title(cnts.most_common(1)[0][0]) for nt, cnts in d.items() if sum(cnts.values()) >= 3}
        for g, d in fn_raw.items()
    }
    _NAME_DICT_CACHE["ln"] = {
        nt: _tr_upper(cnts.most_common(1)[0][0]) for nt, cnts in ln_raw.items() if sum(cnts.values()) >= 3
    }
    _NAME_DICT_CACHE["ts"] = now
    return _NAME_DICT_CACHE


def _predict_masked_name_from_dict(masked_name: str, gender: Optional[str]) -> str:
    """Maskeli kelimeleri RAM sözlüğünde tekil (1 adet) eşleşme varsa gerçek yazımıyla çözer."""
    if not masked_name or "*" not in masked_name:
        return masked_name
    g_norm = "ERKEK" if (gender or "").strip().lower().startswith("erkek") else (
        "KADIN" if (gender or "").strip().lower().startswith(("kad", "kız", "kiz")) else ""
    )
    if not g_norm:
        return masked_name

    cache = _get_name_dict_cache()
    fn_map = cache["fn"].get(g_norm, {})
    ln_map = cache["ln"]
    toks = masked_name.split()
    out_toks = list(toks)

    for i, t in enumerate(toks):
        if "*" not in t:
            continue
        nt = normalize_tr(t, keep_asterisks=True).lower()
        vis = sum(1 for ch in nt if ch != "*")
        if len(nt) < 4 or vis < 2:
            continue
        wmap = ln_map if (i == len(toks) - 1 and len(toks) >= 2) else fn_map
        rx = re.compile("^" + "".join("." if ch == "*" else re.escape(ch) for ch in nt) + "$")
        matches = [real_w for nw, real_w in wmap.items() if len(nw) == len(nt) and rx.match(nw)]
        if len(matches) == 1:
            out_toks[i] = matches[0]

    return " ".join(out_toks)

# Türkiye Zaman Dilimi (UTC+3)
TR_TIMEZONE = dt_timezone(timedelta(hours=3))
PID_FILE_PATH = os.path.join(tempfile.gettempdir(), "local_live_worker.pid")
DEFAULT_POLL_INTERVAL = 5  # 5 saniyelik anlık takip (304 Not Modified ile TYF dostu)


def _normalize_gender(raw_gender: Optional[str]) -> Optional[str]:
    """Cinsiyet metnini ('Erkekler', 'Kızlar', 'Bayanlar', '18 yaş...' vb.) standartlaştırır."""
    if not raw_gender:
        return None
    g = str(raw_gender).strip().lower()
    if any(k in g for k in ("erkek", "men", "boy")):
        return "Erkek"
    if any(k in g for k in ("kadın", "kadin", "bayan", "kız", "kiz", "women", "girl")):
        return "Kadın"
    if any(k in g for k in ("karma", "mix")):
        return "Karma"
    return None


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


def _masked_names_compatibility(name_a: str, name_b: str) -> Tuple[bool, int]:
    """
    İki maskeli ismin aynı sporcuya ait olup olamayacağını kontrol eder.
    Dönüş: (uyumlu_mu, ortak_acik_harf_sayisi)
    """
    toks_a = normalize_tr(name_a, keep_asterisks=True).split()
    toks_b = normalize_tr(name_b, keep_asterisks=True).split()
    if not toks_a or not toks_b or len(toks_a) != len(toks_b):
        return False, 0

    # TYF maskelemesinde ilk ad genellikle tamamen açık gelir; ikisi de açık ve farklıysa erken çık
    if "*" not in toks_a[0] and "*" not in toks_b[0] and toks_a[0] != toks_b[0]:
        return False, 0

    common_visible = 0
    for ta, tb in zip(toks_a, toks_b):
        if len(ta) == len(tb):
            for ca, cb in zip(ta, tb):
                if ca != "*" and cb != "*":
                    if ca != cb:
                        return False, 0
                    common_visible += 1
        else:
            min_len = min(len(ta), len(tb))
            if min_len < 4 or abs(len(ta) - len(tb)) > 2:
                return False, 0
            for ca, cb in zip(ta[:min_len], tb[:min_len]):
                if ca != "*" and cb != "*":
                    if ca != cb:
                        return False, 0
                    common_visible += 1

    return True, common_visible


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
        self.session = requests.Session()
        self.session.verify = False
        self.session.headers.update(self.headers)
        retry_strategy = Retry(
            total=2,
            connect=1,
            read=1,
            backoff_factor=0.5,
            status_forcelist=[429, 500, 502, 503, 504],
        )
        adapter = HTTPAdapter(pool_connections=16, pool_maxsize=16, max_retries=retry_strategy)
        self.session.mount("https://", adapter)
        self.session.mount("http://", adapter)
        self._last_head_check: Dict[int, float] = {}
        self._head_check_interval: float = 300.0
        self._last_future_poll: Dict[int, float] = {}
        self._future_poll_interval: float = 300.0
        self._match_cache: Dict[Tuple[str, Any, str, str], Tuple[float, Optional[int]]] = {}
        self._match_cache_ttl: float = 600.0
        self._html_cache: Dict[int, Dict[str, str]] = {}
        self._club_cache: Dict[Tuple[str, bool], Any] = {}

    def _cached_match_athlete(
        self,
        clean_name: str,
        birth_year: Any,
        club_str: str,
        gender: Optional[str],
    ) -> Optional[int]:
        """match_athlete sonuçlarını (ve negatif/bulunamayanları) 10 dk önbellekte tutar."""
        key = (clean_name, birth_year, club_str or "", gender or "")
        now_ts = time.monotonic()
        cached = self._match_cache.get(key)
        if cached and (now_ts - cached[0]) < self._match_cache_ttl:
            return cached[1]

        match_res = match_athlete(
            clean_name,
            birth_year_or_date=birth_year,
            club=club_str,
            gender=gender,
        )
        found_id = match_res.get("bulunan_id")
        if not found_id and match_res.get("muhtemel_eslesmeler"):
            cands = match_res["muhtemel_eslesmeler"]
            norm_names = {normalize_tr(c.get("sporcu_adi") or "") for c in cands if c.get("sporcu_adi")}
            if len(norm_names) == 1 and float(cands[0].get("benzerlik_orani") or 0) >= 85.0:
                best = max(cands, key=lambda c: (int(c.get("toplam_yaris_sayisi") or 0), -int(c.get("id") or 0)))
                found_id = best.get("id")

        if len(self._match_cache) >= 4000:
            self._match_cache.clear()
        self._match_cache[key] = (now_ts, found_id)
        return found_id

    def filter_due_meets(self, meets: List[CanliYaris], today_iso: str) -> List[CanliYaris]:
        """Başlangıcına 2 günden fazla kalan yarışları atlar; yaklaşan ve start listesi tamamlanmış gelecek yarışları 5 dk'da bir tarar."""
        now_ts = time.time()
        today_date = date.fromisoformat(today_iso[:10])
        due: List[CanliYaris] = []
        for y in meets:
            start_iso, _ = _get_meet_date_bounds(y, y.event)
            if start_iso:
                try:
                    if (date.fromisoformat(start_iso[:10]) - today_date).days > 2:
                        continue
                except ValueError:
                    pass
            if (
                start_iso
                and today_iso < start_iso
                and (y.toplam_start_listesi or 0) > 0
                and (y.islenen_start_listesi or 0) >= (y.toplam_start_listesi or 0)
            ):
                if now_ts - self._last_future_poll.get(y.id, 0.0) < self._future_poll_interval:
                    continue
                self._last_future_poll[y.id] = now_ts
            due.append(y)
        return due

    def prefetch_meet_catalogs(
        self,
        meets: List[CanliYaris],
        max_workers: int = 4,
        force: bool = False,
    ) -> Dict[int, Optional[Tuple[Dict[str, Any], List[Dict[str, str]]]]]:
        """Çok sayıda yarışın HTML kataloglarını paralel çekerek tarama süresini hızlandırır."""
        if not meets:
            return {}
        catalogs: Dict[int, Optional[Tuple[Dict[str, Any], List[Dict[str, str]]]]] = {}

        def _fetch_one(y: CanliYaris):
            return y.id, self.fetch_meet_pdf_catalog(y.canli_url, cache_id=y.id, force=force)

        workers = min(max_workers, len(meets))
        with ThreadPoolExecutor(max_workers=workers) as executor:
            future_map = {executor.submit(_fetch_one, y): y.id for y in meets}
            for fut, yid in future_map.items():
                try:
                    _, cat = fut.result()
                    catalogs[yid] = cat
                except Exception as exc:
                    catalogs[yid] = None
                    logger.warning(f"  [!] Paralel katalog ön-çekme uyarısı (#{yid}): {exc}")
        return catalogs

    def fetch_meet_pdf_catalog(
        self,
        base_url: str,
        cache_id: Optional[int] = None,
        force: bool = False,
    ) -> Tuple[Dict[str, Any], List[Dict[str, str]]]:
        """
        TYF canlı sayfasını çekip başlık bilgileri ile tüm Start ve Sonuç PDF linklerini listeler.
        cache_id verildiğinde 304 Not Modified ve MD5 hash ile değişmeyen sayfaları atlar.
        """
        req_headers = {}
        cached_entry = self._html_cache.get(cache_id) if (cache_id is not None and not force) else None
        if cached_entry:
            if cached_entry.get("etag"):
                req_headers["If-None-Match"] = cached_entry["etag"]
            if cached_entry.get("last_modified"):
                req_headers["If-Modified-Since"] = cached_entry["last_modified"]

        resp = self.session.get(base_url, headers=req_headers or None, timeout=(6, 15))
        if resp.status_code == 304 and cached_entry:
            return {"__unchanged__": True, "canli_url": base_url}, []

        raw_bytes = resp.content
        md5_hex = hashlib.md5(raw_bytes).hexdigest() if cache_id is not None else ""
        if cached_entry and md5_hex and cached_entry.get("md5") == md5_hex:
            cached_entry["etag"] = (resp.headers.get("ETag") or cached_entry.get("etag") or "").strip()
            cached_entry["last_modified"] = (resp.headers.get("Last-Modified") or cached_entry.get("last_modified") or "").strip()
            return {"__unchanged__": True, "canli_url": base_url}, []

        if cache_id is not None:
            self._html_cache[cache_id] = {
                "etag": (resp.headers.get("ETag") or "").strip(),
                "last_modified": (resp.headers.get("Last-Modified") or "").strip(),
                "md5": md5_hex,
            }

        soup = BeautifulSoup(raw_bytes.decode("utf-8", errors="replace"), "html.parser")

        title = soup.title.string.strip() if soup.title else ""
        title = re.sub(r"\s+", " ", title)
        if any(ch in title for ch in ("Ã", "Ä", "Å", "â")):
            try:
                title = title.encode("latin1").decode("utf-8")
            except Exception:
                pass

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

        plain_text = soup.get_text("\n", strip=True)
        city = ""
        date_str = ""
        start_date = ""
        end_date = ""

        # 1) Yeni TYF canlı formatı: "Konya | 14.11.2026 - 15.11.2026 | 50 Metre Havuz"
        m_pipe = re.search(
            r"^([A-ZÇĞİÖŞÜa-zçğıöşü\s]{2,30})\s*\|\s*(\d{1,2}\.\d{1,2}\.\d{4}(?:\s*-\s*\d{1,2}\.\d{1,2}\.\d{4})?)\s*\|",
            plain_text,
            re.MULTILINE,
        )
        if m_pipe:
            city = re.sub(r"\s+", " ", m_pipe.group(1)).strip()
            date_str = re.sub(r"\s+", " ", m_pipe.group(2)).strip()
            start_date, end_date = parse_tr_date_range(date_str)

        # 2) Splash Meet Manager formatı: "İSTANBUL (TUR)"
        if not city:
            m_city = re.search(r"([A-ZÇĞİÖŞÜa-zçğıöşü\s]{3,30})\s*\((?:TUR|TR)\)", plain_text)
            if m_city:
                city = re.sub(r"\s+", " ", m_city.group(1)).strip()

        # 3) Başlıktan şehir: "ANKARA - ..."
        if not city and title:
            m_tcity = re.match(r"^([A-ZÇĞİÖŞÜa-zçğıöşü]+)\s*[\-\:]", title)
            if m_tcity and len(m_tcity.group(1)) >= 3:
                city = m_tcity.group(1).strip()

        # 4) URL path'ten şehir: /istanbul/ (live/canli/cs/results hariç)
        if not city:
            m_u = re.search(r"canli\.tyf\.gov\.tr/([a-zA-ZçğıöşüÇĞİÖŞÜ]+)/", base_url)
            if m_u:
                c_raw = m_u.group(1).lower()
                if c_raw not in ("live", "canli", "canlı", "cs", "results"):
                    city = c_raw

        if city:
            c_low = city.strip().replace("\u0307", "").lower()
            if c_low in ("live", "li̇ve"):
                city = ""
            else:
                first_up = "İ" if c_low[0] == "i" else ("I" if c_low[0] == "ı" else c_low[0].upper())
                city = (first_up + c_low[1:]).replace("\u0307", "")

        if not date_str:
            m_date = re.search(r"(\d{1,2}\.?\s*(?:-\s*\d{1,2}\.)?\s*\d{1,2}\.\d{4})", plain_text)
            if m_date:
                date_str = re.sub(r"\s+", " ", m_date.group(1)).strip()
                start_date, end_date = parse_tr_date_range(date_str)

        meta = {
            "musabaka_adi": title,
            "sehir": city,
            "tarih": date_str,
            "start_date": start_date,
            "end_date": end_date,
            "canli_url": base_url,
        }
        return meta, pdf_items

    def process_meet(
        self,
        yaris: CanliYaris,
        force: bool = False,
        prefetched_catalog: Optional[Tuple[Dict[str, Any], List[Dict[str, str]]]] = None,
    ) -> Dict[str, Any]:
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
            if yaris.reglaman_linki and (
                not yaris.barajlar
                or not isinstance(yaris.barajlar, dict)
                or not yaris.barajlar.get("barajlar")
            ):
                try:
                    parsed_barajlar = fetch_and_parse_reglaman_barajlar(yaris.reglaman_linki)
                    if parsed_barajlar and parsed_barajlar.get("barajlar"):
                        yaris.barajlar = parsed_barajlar
                        db_retry(lambda: yaris.save(update_fields=["barajlar"]))
                        logger.info(
                            f"  [+] #{yaris.id} Reglaman barajları yüklendi: "
                            f"{len(parsed_barajlar['barajlar'])} kural."
                        )
                except Exception as exc:
                    logger.warning(f"  [!] #{yaris.id} Reglaman barajları okunamadı: {exc}")

            meta, pdf_items = (
                prefetched_catalog
                if prefetched_catalog is not None
                else self.fetch_meet_pdf_catalog(yaris.canli_url, cache_id=yaris.id, force=force)
            )
            if meta.get("__unchanged__"):
                # Sayfa 304/MD5 ile değişmediyse: yalnızca bitiş tarihi geçmiş yarışın kapanışını kontrol et
                _, end_iso = _get_meet_date_bounds(yaris, yaris.event)
                now_tr = get_current_tr_time()
                today_iso = now_tr.date().isoformat()
                if end_iso and (today_iso > end_iso or (today_iso == end_iso and now_tr.hour >= 20)):
                    if _should_mark_meet_completed(
                        yaris,
                        yaris.event,
                        int(yaris.toplam_start_listesi or 0),
                        int(yaris.islenen_start_listesi or 0),
                        int(yaris.toplam_sonuc_listesi or 0),
                        int(yaris.islenen_sonuc_listesi or 0),
                        has_errors=False,
                    ):
                        yaris.durum = "TAMAMLANDI"
                        db_retry(lambda: yaris.save(update_fields=["durum"]))
                        logger.info(f"  [✔] #{yaris.id} Müsabaka bitiş tarihi geçtiği ve tüm dosyalar işlendiği için TAMAMLANDI olarak kapatıldı.")
                return stats
            yaris_update_fields = []
            if meta["musabaka_adi"] and not yaris.musabaka_adi:
                yaris.musabaka_adi = meta["musabaka_adi"]
                yaris_update_fields.append("musabaka_adi")
            if meta.get("sehir") and (not yaris.sehir or yaris.sehir.strip().upper() in ("LİVE", "LIVE")):
                yaris.sehir = meta["sehir"]
                yaris_update_fields.append("sehir")
            if meta.get("tarih") and not yaris.tarih:
                yaris.tarih = meta["tarih"]
                yaris_update_fields.append("tarih")
            if yaris_update_fields:
                db_retry(lambda: yaris.save(update_fields=yaris_update_fields))

            event = yaris.event
            if not event:
                raw_sehir = (yaris.sehir or meta.get("sehir") or "").strip()
                if raw_sehir.upper() in ("LİVE", "LIVE"):
                    raw_sehir = ""
                event = db_retry(lambda: Event.objects.create(
                    musabaka_adi=yaris.musabaka_adi or meta["musabaka_adi"] or "TYF Canlı Yarış",
                    sehir=raw_sehir,
                    yaris_tarihi_ham=meta.get("tarih") or (yaris.tarih or ""),
                    yaris_tarihi_baslangic=meta.get("start_date") or "",
                    yaris_tarihi_bitis=meta.get("end_date") or "",
                    kaynak_turu="CANLI_TAKIP",
                ))
                yaris.event = event
                db_retry(lambda: yaris.save(update_fields=["event"]))
            else:
                ev_update_fields = []
                if meta.get("sehir") and (not event.sehir or event.sehir.strip().upper() in ("LİVE", "LIVE")):
                    event.sehir = meta["sehir"]
                    ev_update_fields.append("sehir")
                if meta.get("start_date") and not event.yaris_tarihi_baslangic:
                    event.yaris_tarihi_baslangic = meta["start_date"]
                    ev_update_fields.append("yaris_tarihi_baslangic")
                if meta.get("end_date") and not event.yaris_tarihi_bitis:
                    event.yaris_tarihi_bitis = meta["end_date"]
                    ev_update_fields.append("yaris_tarihi_bitis")
                if meta.get("tarih") and not event.yaris_tarihi_ham:
                    event.yaris_tarihi_ham = meta["tarih"]
                    ev_update_fields.append("yaris_tarihi_ham")
                if ev_update_fields:
                    db_retry(lambda: event.save(update_fields=ev_update_fields))

            known_files = {
                d.dosya_adi: d
                for d in CanliYarisDosya.objects.filter(canli_yaris=yaris)
            }

            now_ts = time.time()
            remote_headers: Dict[str, Dict[str, Any]] = {}
            if not force and known_files and (now_ts - self._last_head_check.get(yaris.id, 0.0) >= self._head_check_interval):
                # Splash '?v=...' parametresi olan linklerde değişiklik HTML URL'sinden 0 istekle anlaşılır;
                # yalnızca '?v=' içermeyen statik URL'ler için HEAD isteği at (TYF rate-limit koruması).
                check_urls = [
                    p["url"]
                    for p in pdf_items
                    if p["filename"] in known_files and "?v=" not in p["url"].lower()
                ]
                if check_urls:
                    remote_headers = fetch_remote_headers_map(check_urls)
                self._last_head_check[yaris.id] = now_ts

            def _needs_processing(p_item: Dict[str, str]) -> bool:
                if force:
                    return True
                kf = known_files.get(p_item["filename"])
                if not kf or kf.durum != "ISLENDI":
                    return True
                if kf.dosya_url and p_item["url"] and kf.dosya_url != p_item["url"]:
                    return True
                rh = remote_headers.get(p_item["filename"])
                if rh:
                    r_etag = (rh.get("etag") or "").strip('"')
                    k_etag = (kf.etag or "").strip('"')
                    if r_etag and k_etag and r_etag != k_etag:
                        return True
                    r_lm = (rh.get("last_modified") or "").strip()
                    k_lm = (kf.last_modified or "").strip()
                    if r_lm and k_lm and r_lm != k_lm:
                        return True
                    r_sz = int(rh.get("dosya_boyutu") or 0)
                    k_sz = int(kf.dosya_boyutu or 0)
                    if r_sz > 0 and k_sz > 0 and r_sz != k_sz:
                        return True
                return False

            pending_starts = [p for p in pdf_items if p["doc_type"] == "start_listesi" and _needs_processing(p)]
            pending_results = [p for p in pdf_items if p["doc_type"] == "sonuc_listesi" and _needs_processing(p)]

            # Yarış sırasına göre düzenle (Start listeleri sonuçlardan önce çözülür)
            pending_starts.sort(key=lambda x: int(x["yaris_no"]) if x["yaris_no"].isdigit() else 9999)
            pending_results.sort(key=lambda x: int(x["yaris_no"]) if x["yaris_no"].isdigit() else 9999)

            current_start_names = {p["filename"] for p in pdf_items if p["doc_type"] == "start_listesi"}
            current_result_names = {p["filename"] for p in pdf_items if p["doc_type"] == "sonuc_listesi"}
            all_start_count = len(current_start_names)
            all_result_count = len(current_result_names)

            removed_files_cnt, removed_results_cnt = self._cleanup_removed_files(
                yaris, known_files, current_start_names | current_result_names
            )

            def _count_processed_current():
                s_cnt = (
                    CanliYarisDosya.objects.filter(
                        canli_yaris=yaris, dosya_turu="START_LISTESI", durum="ISLENDI", dosya_adi__in=current_start_names
                    ).count()
                    if current_start_names
                    else 0
                )
                r_cnt = (
                    CanliYarisDosya.objects.filter(
                        canli_yaris=yaris, dosya_turu="SONUC_LISTESI", durum="ISLENDI", dosya_adi__in=current_result_names
                    ).count()
                    if current_result_names
                    else 0
                )
                return s_cnt, r_cnt

            # Yeni dosya yoksa: çok günlük yarış bitiş tarihi geçtiyse TAMAMLANDI'ya al, değilse sessizce çık
            if not pending_starts and not pending_results:
                islenen_start, islenen_sonuc = _count_processed_current()
                is_completed = _should_mark_meet_completed(
                    yaris, event, all_start_count, islenen_start, all_result_count, islenen_sonuc, has_errors=False
                )
                if is_completed and yaris.durum != "TAMAMLANDI":
                    yaris.durum = "TAMAMLANDI"
                    yaris.toplam_start_listesi = all_start_count
                    yaris.islenen_start_listesi = islenen_start
                    yaris.toplam_sonuc_listesi = all_result_count
                    yaris.islenen_sonuc_listesi = islenen_sonuc
                    yaris.eklenen_kayit_sayisi = YarisSonucu.objects.filter(event=event).count()
                    db_retry(lambda: yaris.save(update_fields=[
                        "durum", "toplam_start_listesi", "islenen_start_listesi",
                        "toplam_sonuc_listesi", "islenen_sonuc_listesi", "eklenen_kayit_sayisi",
                    ]))
                    logger.info(f"  [✔] #{yaris.id} Müsabaka bitiş tarihi geçtiği ve tüm dosyalar işlendiği için TAMAMLANDI olarak kapatıldı.")
                elif removed_files_cnt > 0:
                    yaris.durum = "TAMAMLANDI" if is_completed else "ISLENIYOR"
                    yaris.toplam_start_listesi = all_start_count
                    yaris.islenen_start_listesi = islenen_start
                    yaris.toplam_sonuc_listesi = all_result_count
                    yaris.islenen_sonuc_listesi = islenen_sonuc
                    yaris.eklenen_kayit_sayisi = YarisSonucu.objects.filter(event=event).count()
                    yaris.son_islem_tarihi = timezone.now()
                    db_retry(lambda: yaris.save(update_fields=[
                        "durum", "toplam_start_listesi", "islenen_start_listesi",
                        "toplam_sonuc_listesi", "islenen_sonuc_listesi", "eklenen_kayit_sayisi", "son_islem_tarihi",
                    ]))
                return stats

            logger.info(
                f"[*] #{yaris.id} ({yaris.musabaka_adi or yaris.canli_url}) - "
                f"Yeni Dosya Tespit Edildi: {len(pending_starts)} Start, {len(pending_results)} Sonuç"
            )

            all_pending_items = (
                [("start_listesi", it) for it in pending_starts]
                + [("sonuc_listesi", it) for it in pending_results]
            )
            prefetched_map = (
                self._prefetch_parsed_pdfs(all_pending_items, max_workers=4)
                if len(all_pending_items) > 1
                else {}
            )

            # 1. Start Listeleri
            for item in pending_starts:
                try:
                    added = self._process_single_pdf(
                        yaris,
                        event,
                        item,
                        "start_listesi",
                        prefetched=prefetched_map.get(("start_listesi", item["url"])),
                    )
                    stats["yeni_start"] += 1
                    stats["eklenen_kayit"] += added
                except Exception as exc:
                    err = f"StartList Hata ({item['filename']}): {exc}"
                    logger.error(f"  [!] {err}")
                    stats["hatalar"].append(err)

            # 2. Sonuç Listeleri
            for item in pending_results:
                try:
                    added = self._process_single_pdf(
                        yaris,
                        event,
                        item,
                        "sonuc_listesi",
                        prefetched=prefetched_map.get(("sonuc_listesi", item["url"])),
                    )
                    stats["yeni_sonuc"] += 1
                    stats["eklenen_kayit"] += added
                except Exception as exc:
                    err = f"ResultList Hata ({item['filename']}): {exc}"
                    logger.error(f"  [!] {err}")
                    stats["hatalar"].append(err)

            # İstatistikleri Güncelle
            islenen_start, islenen_sonuc = _count_processed_current()

            yaris.toplam_start_listesi = all_start_count
            yaris.islenen_start_listesi = islenen_start
            yaris.toplam_sonuc_listesi = all_result_count
            yaris.islenen_sonuc_listesi = islenen_sonuc
            yaris.eklenen_kayit_sayisi = YarisSonucu.objects.filter(event=event).count()
            yaris.son_islem_tarihi = timezone.now()

            if stats["hatalar"]:
                self._html_cache.pop(yaris.id, None)

            if _should_mark_meet_completed(
                yaris, event, all_start_count, islenen_start, all_result_count, islenen_sonuc,
                has_errors=bool(stats["hatalar"])
            ):
                yaris.durum = "TAMAMLANDI"
            else:
                yaris.durum = "ISLENIYOR"

            db_retry(lambda: yaris.save())
            logger.info(
                f"  [✔] #{yaris.id} Güncellendi: +{stats['eklenen_kayit']} kayıt eklendi. "
                f"(Start: {islenen_start}/{all_start_count}, Sonuç: {islenen_sonuc}/{all_result_count})"
            )

        except Exception as exc:
            err = f"Canlı Yarış İşleme Hatası: {exc}"
            logger.error(f"[!] {err}")
            stats["hatalar"].append(err)
            yaris.hata_mesaji = str(exc)[:500]
            try:
                db_retry(lambda: yaris.save(update_fields=["hata_mesaji"]))
            except Exception:
                pass

        return stats

    def _cleanup_removed_files(
        self,
        yaris: CanliYaris,
        known_files: Dict[str, CanliYarisDosya],
        current_names: set,
    ) -> Tuple[int, int]:
        """TYF canlı sayfasından kaldırılan eski StartList/ResultList dosyalarını ve bağlı kayıtlarını temizler."""
        if not current_names or not known_files:
            return 0, 0
        removed_names = [fname for fname in list(known_files.keys()) if fname not in current_names]
        if not removed_names:
            return 0, 0
        removed_ids = [known_files[fname].id for fname in removed_names]

        def _do_delete() -> Tuple[int, int]:
            with transaction.atomic():
                deleted_results, _ = YarisSonucu.objects.filter(canli_dosya_id__in=removed_ids).delete()
                deleted_files, _ = CanliYarisDosya.objects.filter(id__in=removed_ids).delete()
                return deleted_files, deleted_results

        deleted_files, deleted_results = db_retry(_do_delete)
        for fname in removed_names:
            known_files.pop(fname, None)
        logger.info(
            f"  [-] #{yaris.id} TYF sayfasından kaldırılan {deleted_files} eski dosya "
            f"ve {deleted_results} kayıt temizlendi."
        )
        return deleted_files, deleted_results

    def _download_and_parse_pdf(self, item: Dict[str, str], doc_type: str) -> Dict[str, Any]:
        """PDF'i indirip yerel PyMuPDF parser ile çözer (thread-safe, DB yazmaz)."""
        url = item["url"]
        resp = self.session.get(url, timeout=(6, 15))
        if resp.status_code != 200:
            raise RuntimeError(f"HTTP {resp.status_code}")

        pdf_bytes = resp.content
        file_size = len(pdf_bytes)
        etag = (resp.headers.get("ETag") or "").strip('"')
        last_modified = (resp.headers.get("Last-Modified") or "").strip()

        if doc_type == "start_listesi":
            parsed = LocalStartListParser().parse(pdf_bytes)
        else:
            parsed = LocalResultListParser().parse(pdf_bytes, unmask=False)

        return {
            "parsed": parsed,
            "file_size": file_size,
            "etag": etag,
            "last_modified": last_modified,
        }

    def _prefetch_parsed_pdfs(
        self,
        items: List[Tuple[str, Dict[str, str]]],
        max_workers: int = 8,
    ) -> Dict[Tuple[str, str], Dict[str, Any]]:
        """Birden fazla PDF'i paralel indirip ayrıştırır; DB kaydını ana iş parçacığına bırakır."""
        if not items:
            return {}
        t0 = time.perf_counter()
        results: Dict[Tuple[str, str], Dict[str, Any]] = {}
        workers = min(max_workers, len(items))

        def _worker(doc_t: str, it: Dict[str, str]):
            return (doc_t, it["url"]), self._download_and_parse_pdf(it, doc_t)

        with ThreadPoolExecutor(max_workers=workers) as executor:
            future_map = {
                executor.submit(_worker, doc_t, it): (doc_t, it["url"])
                for doc_t, it in items
            }
            for fut, key in future_map.items():
                try:
                    k, payload = fut.result()
                    results[k] = payload
                except Exception as exc:
                    results[key] = {"error": exc}
        elapsed = time.perf_counter() - t0
        logger.info(f"  [⚡] {len(items)} PDF {workers} paralel iş parçacığıyla {elapsed:.2f} sn'de indirilip ayrıştırıldı.")
        return results

    def _process_single_pdf(
        self,
        yaris: CanliYaris,
        event: Event,
        item: Dict[str, str],
        doc_type: str,
        prefetched: Optional[Dict[str, Any]] = None,
    ) -> int:
        filename = item["filename"]
        url = item["url"]
        logger.info(f"  [>] {filename} işleniyor ({doc_type})...")

        if prefetched is not None:
            if "error" in prefetched:
                raise prefetched["error"]
            data_pack = prefetched
        else:
            data_pack = self._download_and_parse_pdf(item, doc_type)

        parsed = data_pack["parsed"]
        file_size = data_pack["file_size"]
        etag = data_pack["etag"]
        last_modified = data_pack["last_modified"]
        is_school = is_school_meet(event.musabaka_adi)
        course = detect_course(event.musabaka_adi)

        if doc_type == "start_listesi":
            raw_swimmers = parsed.get("sporcular", [])
        else:
            raw_swimmers = parsed.get("sonuclar", [])

        cinsiyet = _normalize_gender(parsed.get("cinsiyet"))
        mesafe = parsed.get("mesafe")
        stil = parsed.get("stil")
        if parsed.get("sehir") and (not event.sehir or event.sehir.strip().upper() in ("LİVE", "LIVE")):
            c_raw = parsed["sehir"].strip().lower()
            first_up = "İ" if c_raw[0] == "i" else ("I" if c_raw[0] == "ı" else c_raw[0].upper())
            event.sehir = first_up + c_raw[1:]
            db_retry(lambda: event.save(update_fields=["sehir"]))
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
            "etag": etag,
            "last_modified": last_modified,
            "durum": "ISLENDI",
            "kayit_sayisi": len(raw_swimmers),
            "son_islem_tarihi": timezone.now(),
        }

        def _vis_chars(txt: str) -> str:
            return re.sub(r"[\*\s]+", "", normalize_tr(txt, keep_asterisks=True))

        counterpart_start_filename = (
            re.sub(r"^ResultList_", "StartList_", filename, flags=re.IGNORECASE)
            if doc_type == "sonuc_listesi"
            else None
        )

        def _narrow_cross_cands(cands, club_id, by, result_name: str = "", require_name_match: bool = False):
            if not cands:
                return None
            if len(cands) > 1 and counterpart_start_filename:
                filtered = [c for c in cands if (c[4].dosya_adi or "").lower() == counterpart_start_filename.lower()]
                if filtered:
                    cands = filtered
            if len(cands) > 1:
                filtered = [c for c in cands if c[4].derece == "Bekleniyor"]
                if filtered:
                    cands = filtered
            if len(cands) > 1 and club_id:
                filtered = [c for c in cands if c[2] == club_id]
                if filtered:
                    cands = filtered
            if len(cands) > 1 and by:
                filtered = [c for c in cands if c[3] == str(by)]
                if filtered:
                    cands = filtered
            if result_name and (len(cands) > 1 or require_name_match):
                from difflib import SequenceMatcher
                rv = _vis_chars(result_name)
                if rv:
                    scored = sorted(
                        [
                            (SequenceMatcher(None, rv, _vis_chars(c[1] or c[0].sporcu_adi)).ratio(), c)
                            for c in cands
                        ],
                        key=lambda x: x[0],
                        reverse=True,
                    )
                    if scored[0][0] >= 0.55 and (len(scored) == 1 or scored[0][0] - scored[1][0] >= 0.12):
                        return scored[0][1]
                    if require_name_match:
                        return None
            return cands[0] if len(cands) == 1 else None

        def _save_pdf_atomically() -> int:
            records_added = 0
            unmatched_skipped = 0
            seen_result_ids: List[int] = []
            seen_athlete_ids_in_pdf: set = set()
            has_startlist_for_race = False
            if len(self._club_cache) >= 1000:
                self._club_cache.clear()
            club_cache = self._club_cache
            to_update_map: Dict[int, YarisSonucu] = {}
            bulk_update_fields: set = set()
            to_create_objs: List[YarisSonucu] = []
            cross_unmasked = {}
            cross_by_lane = {}
            cross_by_masked = {}
            all_start_cands = []
            with transaction.atomic():
                dosya_obj, _ = CanliYarisDosya.objects.update_or_create(
                    canli_yaris=yaris,
                    dosya_adi=filename,
                    defaults=dosya_defaults
                )

                pre_qs = YarisSonucu.objects.filter(
                    event=event,
                    mesafe=mesafe,
                    stil=stil,
                    cinsiyet=cinsiyet,
                ).select_related("sporcu", "kulup", "sporcu__birincil_kulup")
                if yaris_no:
                    pre_qs = pre_qs.filter(yaris_no=yaris_no)
                if doc_type == "start_listesi":
                    res_counterpart = re.sub(r"^StartList_", "ResultList_", filename, flags=re.IGNORECASE)
                    pre_qs = pre_qs.filter(
                        Q(dosya_adi__iexact=filename)
                        | Q(dosya_adi__iexact=res_counterpart)
                        | Q(dosya_adi__isnull=True)
                        | Q(dosya_adi="")
                    )

                existing_by_athlete: Dict[int, YarisSonucu] = {}
                existing_unlaned_by_athlete: Dict[int, List[YarisSonucu]] = {}
                existing_by_lane_num: Dict[Tuple[int, int], YarisSonucu] = {}
                existing_by_lane: Dict[Tuple[str, int], YarisSonucu] = {}
                event_masked_athletes: Dict[Tuple[int, Any, str], List[Sporcu]] = {}
                if not is_bayrak:
                    masked_sp_ids = set(
                        YarisSonucu.objects.filter(
                            event=event,
                            sporcu__sporcu_adi__startswith="Maskeli sporcu",
                        ).values_list("sporcu_id", flat=True).distinct()
                    )
                    if masked_sp_ids:
                        for m_sp in Sporcu.objects.filter(id__in=masked_sp_ids).select_related("birincil_kulup"):
                            m_key_pool = (
                                m_sp.birincil_kulup_id or 0,
                                m_sp.dogum_yili,
                                (m_sp.cinsiyet or "").strip(),
                            )
                            event_masked_athletes.setdefault(m_key_pool, []).append(m_sp)
                fname_lower = filename.lower()
                counterpart_lower = counterpart_start_filename.lower() if counterpart_start_filename else ""
                result_counterpart_lower = (
                    re.sub(r"^startlist_", "resultlist_", fname_lower)
                    if doc_type == "start_listesi"
                    else ""
                )

                def _pre_row_sort_key(r: YarisSonucu):
                    rf = (r.dosya_adi or "").lower()
                    same_file = (
                        rf == fname_lower
                        or (counterpart_lower and rf == counterpart_lower)
                        or (result_counterpart_lower and rf == result_counterpart_lower)
                    )
                    return (0 if same_file else 1, 0 if r.derece == "Bekleniyor" else 1, -r.id)

                for row in sorted(pre_qs.order_by("-id"), key=_pre_row_sort_key):
                    if row.sporcu_id and row.sporcu_id not in existing_by_athlete:
                        existing_by_athlete[row.sporcu_id] = row
                    if row.sporcu_id and row.kulvar is None:
                        existing_unlaned_by_athlete.setdefault(row.sporcu_id, []).append(row)
                    s_num = None
                    if row.seri and row.kulvar is not None:
                        m_cs = re.search(r"\d+", str(row.seri))
                        if m_cs:
                            s_num = int(m_cs.group())
                            k_num = (s_num, row.kulvar)
                            if k_num not in existing_by_lane_num:
                                existing_by_lane_num[k_num] = row
                        k_str = (str(row.seri).strip(), row.kulvar)
                        if k_str not in existing_by_lane:
                            existing_by_lane[k_str] = row

                    if doc_type == "sonuc_listesi" and row.sporcu:
                        if row.kaynak_turu == "CANLI_START_LISTESI":
                            has_startlist_for_race = True
                        cand_tuple = (
                            row.sporcu,
                            row.sporcu_maskeli or "",
                            row.kulup_id,
                            str(row.sporcu.dogum_yili or ""),
                            row,
                        )
                        all_start_cands.append(cand_tuple)
                        if row.sporcu_maskeli:
                            m_key = normalize_tr(row.sporcu_maskeli, keep_asterisks=True)
                            if m_key:
                                cross_by_masked.setdefault(m_key, []).append(cand_tuple)
                        if row.kulvar:
                            if s_num and (s_num, row.kulvar) not in cross_unmasked:
                                cross_unmasked[(s_num, row.kulvar)] = (
                                    row.sporcu,
                                    row.sporcu_maskeli or "",
                                    row.kulup_id,
                                    row,
                                )
                            cross_by_lane.setdefault(row.kulvar, []).append(cand_tuple)

                for s in raw_swimmers:
                    raw_name = (s.get("sporcu") or "").strip()
                    if not raw_name:
                        continue

                    clean_name = clean_athlete_name_tags(raw_name)
                    # Kırpılmış parantez/etiket kalıntılarını temizle: "( Metehan", "(f5) Adem"
                    clean_name = re.sub(r"^(?:\([A-Za-z0-9]{1,4}\)\s*|\(\s+)", "", clean_name).strip()
                    birth_year = s.get("dogum_yili")
                    if birth_year is not None:
                        try:
                            by_int = int(str(birth_year).strip())
                            if 0 <= by_int <= 99:
                                by_int = (1900 + by_int) if by_int >= 30 else (2000 + by_int)
                            birth_year = by_int if 1920 <= by_int <= 2022 else None
                        except (TypeError, ValueError):
                            birth_year = None
                    durum_val = (s.get("durum") or "NORMAL").strip()
                    if durum_val.upper() == "DQ" or durum_val.upper().startswith("SW "):
                        durum_val = "DSQ"
                    if durum_val in ["DSQ", "DNS", "DNF", "EXH"] and clean_name:
                        clean_name = re.sub(r"\s*\(\d{1,2}:\d{2}\b.*$", "", clean_name).strip()
                        clean_name = re.sub(
                            r"\s+(?:[a-zçğıöşü]+ığından|atılmadığından|dokunmadan|dokunmayarak|hatalı\s+çıkış|erken\s+çıkış|starttan\s+sonra)\b.*$",
                            "",
                            clean_name,
                            flags=re.IGNORECASE,
                        ).strip()
                        clean_name = re.sub(
                            r"\s+(?:\d{1,2}(?:\s*[-–/]\s*\d{1,2})?\s*\+?\s*[Yy]a[sş](?:\s+ve\s+[üu]zeri)?|[Aa][cç][ıi]k\s*[Yy]a[sş])\s*$",
                            "",
                            clean_name,
                        ).strip()
                    raw_club = (s.get("kulup") or "").strip()
                    baraj_note = (s.get("notlar") or "").strip() if durum_val not in ["DSQ", "DNS", "DNF", "EXH"] else ""
                    if raw_club and "baraj" in raw_club.lower():
                        if not baraj_note:
                            baraj_note = raw_club
                        raw_club = ""
                    # Saf sayı ('0', '11'), yaş grubu ('11 yaş', '11-12 yaş') veya derece formatındaki ('1:45.20', 'NT') değerleri kulüp olarak kabul etme
                    _INVALID_CLUB_RE = re.compile(
                        r"^(?:\d{1,3}|"
                        r"\d{1,2}(?:\s*[-–/]\s*\d{1,2})?\s*\+?\s*ya[sş]|"
                        r"a[cç][ıi]k\s*ya[sş]|"
                        r"(?:\d{1,2}:)?\d{2}[.,]\d{2}|NT)$",
                        re.IGNORECASE,
                    )
                    if raw_club and _INVALID_CLUB_RE.match(raw_club):
                        raw_club = ""
                    clean_club_str = clean_club_name_tags(raw_club) if raw_club else ""
                    if clean_club_str and _INVALID_CLUB_RE.match(clean_club_str):
                        clean_club_str = ""
                    club_lookup_str = clean_club_str or raw_club

                    def _resolve_club_lazy():
                        if not club_lookup_str:
                            return None
                        ck_key = (club_lookup_str, is_school)
                        if ck_key in club_cache:
                            return club_cache[ck_key]
                        c_obj, _ = get_or_resolve_canonical_club(club_lookup_str, is_school=is_school)
                        club_cache[ck_key] = c_obj
                        return c_obj

                    # ResultList'te kulüp bilgisini baştan DB'den çözme; StartList zaten çözmüş durumda.
                    # Yalnızca StartList işlenirken (veya ResultList'te yeni/eksik kulüp gerektiğinde) çöz.
                    club = _resolve_club_lazy() if doc_type == "start_listesi" else None

                    seri_val = s.get("seri")
                    kulvar_val = s.get("kulvar")
                    derece_val = s.get("derece")
                    sira_val = s.get("sira")

                    seri_no = None
                    if seri_val:
                        m_s = re.search(r"\d+", str(seri_val))
                        if m_s:
                            seri_no = int(m_s.group())

                    athlete = None
                    matched_masked_sp = None
                    matched_start_mask = ""
                    matched_start_club = None
                    matched_start_row = None
                    # 1. StartList Çapraz Eşleşmesi:
                    #    a) Öncelikle StartList'teki maskeli isim anahtarıyla eşleştir
                    if "*" in clean_name and cross_by_masked:
                        m_key = normalize_tr(clean_name, keep_asterisks=True)
                        picked = _narrow_cross_cands(cross_by_masked.get(m_key), club.id if club else None, birth_year, clean_name)
                        if picked:
                            st_sp, st_mask, st_club_id, _, st_row = picked
                            matched_start_row = st_row
                            matched_start_club = matched_start_club or st_row.kulup
                            if st_sp and not st_sp.sporcu_adi.startswith("Maskeli sporcu"):
                                athlete = st_sp
                            elif st_sp:
                                matched_masked_sp = st_sp
                                matched_start_mask = st_mask or ""

                    #    b) Eşleşmezse (K/S) veya seri yoksa Kulvar + Kulüp/Yıl üzerinden dene
                    if not athlete:
                        if seri_no and kulvar_val and (seri_no, kulvar_val) in cross_unmasked:
                            st_sp, st_mask, st_club_id, st_row = cross_unmasked[(seri_no, kulvar_val)]
                            matched_start_row = matched_start_row or st_row
                            if not matched_start_club:
                                matched_start_club = st_row.kulup
                            if st_sp and not st_sp.sporcu_adi.startswith("Maskeli sporcu"):
                                athlete = st_sp
                            elif st_sp and not matched_masked_sp:
                                matched_masked_sp = st_sp
                                matched_start_mask = st_mask or ""
                        elif not seri_no and kulvar_val and kulvar_val in cross_by_lane:
                            picked = _narrow_cross_cands(cross_by_lane.get(kulvar_val), club.id if club else None, birth_year, clean_name)
                            if picked:
                                st_sp, st_mask, st_club_id, _, st_row = picked
                                matched_start_row = matched_start_row or st_row
                                if not matched_start_club:
                                    matched_start_club = st_row.kulup
                                if st_sp and not st_sp.sporcu_adi.startswith("Maskeli sporcu"):
                                    athlete = st_sp
                                elif st_sp and not matched_masked_sp:
                                    matched_masked_sp = st_sp
                                    matched_start_mask = st_mask or ""

                    #    c) Hâlâ eşleşmediyse (ör. DSQ/kulvar yok veya maske harfi kırpılmışsa) tüm StartList havuzunda ara
                    if not athlete and not matched_masked_sp and all_start_cands:
                        if not club and club_lookup_str:
                            club = _resolve_club_lazy()
                        picked = _narrow_cross_cands(
                            all_start_cands,
                            club.id if club else None,
                            birth_year,
                            clean_name,
                            require_name_match=True,
                        )
                        if picked:
                            st_sp, st_mask, st_club_id, _, st_row = picked
                            matched_start_row = matched_start_row or st_row
                            if not matched_start_club:
                                matched_start_club = st_row.kulup
                            if st_sp and not st_sp.sporcu_adi.startswith("Maskeli sporcu"):
                                athlete = st_sp
                            elif st_sp:
                                matched_masked_sp = st_sp
                                matched_start_mask = st_mask or ""

                    #    d) (Seri, Kulvar) mevcut DB kaydında zaten sporcu varsa doğrudan onu kullan
                    if not athlete and seri_no and kulvar_val is not None:
                        lane_row = existing_by_lane_num.get((seri_no, kulvar_val))
                        if lane_row and lane_row.sporcu:
                            matched_start_row = matched_start_row or lane_row
                            if not matched_start_club and lane_row.kulup:
                                matched_start_club = lane_row.kulup
                            if not lane_row.sporcu.sporcu_adi.startswith("Maskeli sporcu"):
                                athlete = lane_row.sporcu
                            elif not matched_masked_sp:
                                matched_masked_sp = lane_row.sporcu
                                matched_start_mask = lane_row.sporcu_maskeli or ""

                    # Sonuç listesinde kulüp boşsa (ör. EXH/DSQ) StartList'teki kulübü bellekten miras al
                    if not club and matched_start_club:
                        club = matched_start_club

                    # 2. Bayrak / Relay Takımı Eşleşmesi
                    if not athlete and not matched_masked_sp and (is_bayrak or "(tk)" in raw_name.lower()):
                        if not club and club_lookup_str:
                            club = _resolve_club_lazy()
                        team_name = clean_name or (club.kulup_adi if club else "Takım")
                        athlete = _resolve_or_create_relay_team(team_name, club=club)

                    # 3. Veritabanından Unmasking:
                    #    StartList'te zaten Maskeli sporcu olarak kayıtlıysa tekrar DB'ye gitme;
                    #    yalnızca StartList'te hiç yoksa (yedek/yeni) veya ResultList açık/daha net isim veriyorsa DB'de ara.
                    if not athlete and matched_masked_sp:
                        result_is_clearer = ("*" not in clean_name) or (
                            matched_start_mask and len(_vis_chars(clean_name)) > len(_vis_chars(matched_start_mask)) + 1
                        )
                        if not result_is_clearer:
                            athlete = matched_masked_sp

                    if not athlete and clean_name and "," not in clean_name:
                        found_id = self._cached_match_athlete(
                            clean_name,
                            birth_year=birth_year,
                            club_str=clean_club_str or raw_club,
                            gender=None if cinsiyet == "Karma" else cinsiyet,
                        )
                        if found_id:
                            athlete = Sporcu.objects.filter(id=found_id).select_related("birincil_kulup").first()

                    if not athlete and matched_masked_sp:
                        athlete = matched_masked_sp

                    # Sonuç listesinde kulüp hâlâ boşsa ve gerçek sporcu eşleştiyse birincil/aktif kulübünü kullan
                    if not club and athlete and not athlete.sporcu_adi.startswith("Maskeli sporcu"):
                        club = athlete.birincil_kulup or athlete.aktif_kulup()

                    # 4. Bulunamazsa Maskeli Sporcu Kaydı
                    if not athlete:
                        if not club and club_lookup_str:
                            club = _resolve_club_lazy()
                        resolved_clean = _predict_masked_name_from_dict(clean_name, cinsiyet) if ("*" in clean_name and not is_bayrak) else clean_name
                        sp_target_name = f"Maskeli sporcu ({resolved_clean})" if "*" in resolved_clean else (standardize_turkish_athlete_name(resolved_clean) or resolved_clean)

                        # 4a. Birebir aynı (sporcu_adi, dogum_yili) kaydı varsa (ve bu PDF içinde henüz atanmadıysa) kullan
                        exact_qs = Sporcu.objects.filter(sporcu_adi=sp_target_name, dogum_yili=birth_year)
                        cand_exact = (exact_qs.filter(birincil_kulup=club).first() if club else None) or exact_qs.first()
                        if cand_exact and (is_bayrak or cand_exact.id not in seen_athlete_ids_in_pdf):
                            athlete = cand_exact

                        # 4b. Aynı canlı yarışta (veya aynı kulüp+yaş+cinsiyet DB maskeli havuzunda tekil aday varsa) uyumlu mevcut Maskeli sporcu
                        if not athlete and "*" in clean_name and club and birth_year and not is_bayrak:
                            pool_key = (club.id, birth_year, (cinsiyet or "").strip())
                            pool_cands = [
                                m_sp for m_sp in event_masked_athletes.get(pool_key, [])
                                if m_sp.id not in seen_athlete_ids_in_pdf
                            ]
                            if pool_cands:
                                compat_cands = []
                                for m_sp in pool_cands:
                                    inner_mask = m_sp.sporcu_adi
                                    if inner_mask.startswith("Maskeli sporcu (") and inner_mask.endswith(")"):
                                        inner_mask = inner_mask[len("Maskeli sporcu ("):-1]
                                    ok, common_vis = _masked_names_compatibility(clean_name, inner_mask)
                                    if ok:
                                        compat_cands.append((common_vis, m_sp))
                                if len(compat_cands) == 1:
                                    athlete = compat_cands[0][1]
                                elif len(compat_cands) > 1:
                                    compat_cands.sort(key=lambda x: (-x[0], x[1].id))
                                    if compat_cands[0][0] > compat_cands[1][0]:
                                        athlete = compat_cands[0][1]

                            # 4b-ek: Event havuzunda yoksa DB'de aynı (kulüp, doğum yılı, cinsiyet) grubunda tekil uyumlu Maskeli ara
                            if not athlete:
                                db_pool = [
                                    m_sp for m_sp in Sporcu.objects.filter(
                                        sporcu_adi__startswith="Maskeli sporcu (",
                                        birincil_kulup=club,
                                        dogum_yili=birth_year,
                                        cinsiyet=(cinsiyet or "").strip(),
                                    )
                                    if m_sp.id not in seen_athlete_ids_in_pdf
                                ]
                                db_compat = []
                                for m_sp in db_pool:
                                    inner_mask = m_sp.sporcu_adi[len("Maskeli sporcu ("):-1] if m_sp.sporcu_adi.endswith(")") else m_sp.sporcu_adi
                                    ok, common_vis = _masked_names_compatibility(clean_name, inner_mask)
                                    if ok and common_vis >= 2:
                                        db_compat.append((common_vis, m_sp))
                                if len(db_compat) == 1:
                                    athlete = db_compat[0][1]
                                    event_masked_athletes.setdefault(pool_key, []).append(athlete)

                        # 4c. Hâlâ bulunamadıysa yeni Sporcu oluştur
                        if not athlete:
                            athlete = Sporcu.objects.create(
                                sporcu_adi=sp_target_name,
                                dogum_yili=birth_year,
                                cinsiyet=cinsiyet,
                                birincil_kulup=club,
                            )
                            if "*" in clean_name and club and birth_year and not is_bayrak:
                                pool_key = (club.id, birth_year, (cinsiyet or "").strip())
                                event_masked_athletes.setdefault(pool_key, []).append(athlete)

                    is_relay_entry = bool(is_bayrak or "(tk)" in raw_name.lower())
                    if athlete and not is_relay_entry:
                        seen_athlete_ids_in_pdf.add(athlete.id)

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
                            "ara_dereceler": s.get("ara_dereceler"),
                        }
                        if durum_val in ["DSQ", "DNS", "DNF", "EXH"]:
                            reason = s.get("notlar") or ""
                            defaults_dict["uyari_notu"] = f"{durum_val} - {reason}".strip(" -")
                        else:
                            defaults_dict["uyari_notu"] = ""
                            if baraj_note:
                                defaults_dict["baraj"] = baraj_note[:50]
                            elif yaris.barajlar and derece_sn and not is_bayrak:
                                eff_birth_year = birth_year or (athlete.dogum_yili if athlete else None)
                                passed_baraj = evaluate_baraj_for_result(
                                    yaris.barajlar,
                                    cinsiyet=cinsiyet,
                                    mesafe=mesafe,
                                    stil=stil,
                                    derece_saniye=derece_sn,
                                    birth_year=eff_birth_year,
                                    course=course,
                                )
                                defaults_dict["baraj"] = passed_baraj[:50] if passed_baraj else None

                    lookup_dict = {
                        "event": event,
                        "sporcu": athlete,
                        "mesafe": mesafe,
                        "stil": stil,
                        "cinsiyet": cinsiyet,
                    }
                    if yaris_no:
                        lookup_dict["yaris_no"] = yaris_no

                    existing = None
                    if not is_relay_entry:
                        existing = matched_start_row or existing_by_athlete.get(athlete.id)
                    if not existing and seri_val and kulvar_val is not None:
                        if seri_no is not None:
                            existing = existing_by_lane_num.get((seri_no, kulvar_val))
                        if not existing:
                            existing = existing_by_lane.get((str(seri_val).strip(), kulvar_val))
                    if not existing and is_relay_entry:
                        if kulvar_val is None:
                            unlaned_q = existing_unlaned_by_athlete.get(athlete.id)
                            if unlaned_q:
                                existing = unlaned_q.pop()
                            else:
                                existing = matched_start_row or existing_by_athlete.get(athlete.id)
                        else:
                            existing = matched_start_row

                    if doc_type == "sonuc_listesi":
                        if existing:
                            # StartList ana kaynaktır: mevcut kayıtta zaten dolu olan başlangıç bilgilerini ezme
                            if existing.kulup_id:
                                defaults_dict.pop("kulup", None)
                            elif not club and club_lookup_str:
                                defaults_dict["kulup"] = _resolve_club_lazy()
                            if existing.seri:
                                defaults_dict.pop("seri", None)
                            if existing.kulvar is not None:
                                defaults_dict.pop("kulvar", None)
                            if existing.yaris_no is not None:
                                defaults_dict.pop("yaris_no", None)
                            if existing.sporcu_maskeli:
                                defaults_dict.pop("sporcu_maskeli", None)
                        elif not club and club_lookup_str:
                            defaults_dict["kulup"] = _resolve_club_lazy()

                    if existing:
                        if existing.pk is None:
                            # Aynı PDF içinde henüz bulk_create edilmemiş satır: yalnızca bellekte güncelle
                            for k_f, v_f in defaults_dict.items():
                                setattr(existing, k_f, v_f)
                        elif doc_type == "start_listesi" and existing.kaynak_turu == "CANLI_SONUC":
                            # Mevcut sonuç derecesini StartList ile ezme; sadece eksik başlangıç bilgilerini tamamla
                            update_fields = []
                            if defaults_dict.get("giris_derecesi") and not existing.giris_derecesi:
                                existing.giris_derecesi = defaults_dict["giris_derecesi"]
                                update_fields.append("giris_derecesi")
                            if defaults_dict.get("kulup") and not existing.kulup_id:
                                existing.kulup = defaults_dict["kulup"]
                                update_fields.append("kulup")
                            if (
                                existing.sporcu
                                and existing.sporcu.sporcu_adi.startswith("Maskeli sporcu")
                                and athlete
                                and not athlete.sporcu_adi.startswith("Maskeli sporcu")
                            ):
                                existing.sporcu = athlete
                                update_fields.append("sporcu")
                            if update_fields:
                                to_update_map[existing.id] = existing
                                bulk_update_fields.update(update_fields)
                        else:
                            # Gerçek (maskesiz) sporcuyu asla yeni bir 'Maskeli sporcu' ile ezme
                            existing_is_masked = bool(existing.sporcu and existing.sporcu.sporcu_adi.startswith("Maskeli sporcu"))
                            new_is_masked = bool(athlete and athlete.sporcu_adi.startswith("Maskeli sporcu"))
                            dirty_fields: List[str] = []
                            if existing_is_masked and not new_is_masked:
                                existing.sporcu = athlete
                                dirty_fields.append("sporcu")
                            for k_f, v_f in defaults_dict.items():
                                if getattr(existing, k_f) != v_f:
                                    setattr(existing, k_f, v_f)
                                    dirty_fields.append(k_f)
                            if dirty_fields:
                                to_update_map[existing.id] = existing
                                bulk_update_fields.update(dirty_fields)
                        if existing.id:
                            seen_result_ids.append(existing.id)
                    else:
                        if doc_type == "sonuc_listesi" and has_startlist_for_race:
                            unmatched_skipped += 1
                            _log_unmatched_result_record({
                                "ts": timezone.now().isoformat(),
                                "event_id": event.id,
                                "yaris_id": yaris.id,
                                "filename": filename,
                                "yaris_no": yaris_no,
                                "mesafe": mesafe,
                                "stil": stil,
                                "cinsiyet": cinsiyet,
                                "durum": durum_val,
                                "seri": seri_val,
                                "kulvar": kulvar_val,
                                "raw_name": raw_name,
                                "clean_name": clean_name,
                                "dogum_yili": birth_year,
                                "raw_club": raw_club,
                                "derece": derece_val,
                                "notlar": s.get("notlar"),
                                "matched_athlete_id": athlete.id if athlete else None,
                                "matched_athlete_name": athlete.sporcu_adi if athlete else None,
                                "reason": "unmatched_with_startlist",
                            })
                            continue
                        create_kwargs = {**lookup_dict, **defaults_dict}
                        new_obj = YarisSonucu(**create_kwargs)
                        to_create_objs.append(new_obj)
                        if not is_relay_entry:
                            existing_by_athlete[new_obj.sporcu_id] = new_obj
                        if seri_no is not None and kulvar_val is not None:
                            existing_by_lane_num[(seri_no, kulvar_val)] = new_obj
                        if seri_val and kulvar_val is not None:
                            existing_by_lane[(str(seri_val).strip(), kulvar_val)] = new_obj
                        records_added += 1

                if to_update_map and bulk_update_fields:
                    YarisSonucu.objects.bulk_update(
                        list(to_update_map.values()),
                        list(bulk_update_fields),
                        batch_size=500,
                    )

                if to_create_objs:
                    created_objs = YarisSonucu.objects.bulk_create(to_create_objs, batch_size=500)
                    for co in created_objs:
                        if co.id:
                            seen_result_ids.append(co.id)

                if seen_result_ids:
                    stale_source = "CANLI_START_LISTESI" if doc_type == "start_listesi" else "CANLI_SONUC"
                    YarisSonucu.objects.filter(
                        canli_dosya=dosya_obj,
                        kaynak_turu=stale_source,
                    ).exclude(id__in=seen_result_ids).delete()

                if unmatched_skipped:
                    logger.warning(
                        f"  [!] {filename}: StartList dışı {unmatched_skipped} sonuç satırı eklenmedi "
                        f"(logs/unmatched_result_records.jsonl dosyasına kaydedildi)."
                    )

            return records_added

        return db_retry(_save_pdf_atomically)


# ==============================================================================
# SERVİS 0: YENİ TYF CANLI YARIŞ KEŞİF TARAYICISI
# ==============================================================================

DEFAULT_SCAN_FALLBACK_START = 1005900
DEFAULT_SCAN_WINDOW = 80
DEFAULT_SCAN_BACK_LOOK = 200


def _normalize_live_url(url: str) -> str:
    u = (url or "").strip()
    if u and not u.endswith("/"):
        u += "/"
    return u.lower()


def compute_auto_scan_range(
    year: Optional[int] = None,
    window: int = DEFAULT_SCAN_WINDOW,
    back_look: int = DEFAULT_SCAN_BACK_LOOK,
) -> Tuple[int, int, int, set]:
    """
    Veritabanındaki mevcut CanliYaris URL'lerinden en yüksek ID'yi bulup
    otomatik (year, start_id, end_id, known_urls) döner.
    """
    target_year = year or get_current_tr_time().year
    known_urls = set()
    max_id: Optional[int] = None
    id_re = re.compile(rf"canli\.tyf\.gov\.tr/live/{target_year}/(\d+)/?", re.IGNORECASE)

    for raw_url in CanliYaris.objects.values_list("canli_url", flat=True):
        if not raw_url:
            continue
        known_urls.add(_normalize_live_url(raw_url))
        m = id_re.search(raw_url)
        if m:
            val = int(m.group(1))
            if max_id is None or val > max_id:
                max_id = val

    if max_id is not None:
        start_id = max(1, max_id - back_look)
        end_id = max_id + window
    else:
        start_id = DEFAULT_SCAN_FALLBACK_START
        end_id = start_id + window

    return target_year, start_id, end_id, known_urls


def discover_new_live_meets(
    start_id: Optional[int] = None,
    end_id: Optional[int] = None,
    window: int = DEFAULT_SCAN_WINDOW,
    back_look: int = DEFAULT_SCAN_BACK_LOOK,
    workers: int = 20,
    timeout: float = 5.0,
    year: Optional[int] = None,
) -> List[str]:
    """
    canli.tyf.gov.tr/live/<year>/<id>/ aralığında yeni açılan (status 200) canlı yarışları
    paralel olarak tarar ve veritabanına (CanliYaris + Event) otomatik ekler.
    start_id / end_id verilmezse DB'deki en son ID'ye göre otomatik hesaplanır.
    """
    target_year, auto_start, auto_end, known_urls = compute_auto_scan_range(
        year=year, window=window, back_look=back_look
    )
    eff_start = start_id if start_id is not None else auto_start
    eff_end = end_id if end_id is not None else auto_end
    if eff_start > eff_end:
        return []

    base_tpl = f"https://canli.tyf.gov.tr/live/{target_year}/{{item_id}}/"
    candidate_ids = [
        item_id
        for item_id in range(eff_start, eff_end + 1)
        if _normalize_live_url(base_tpl.format(item_id=item_id)) not in known_urls
    ]
    if not candidate_ids:
        return []

    session = requests.Session()
    adapter = HTTPAdapter(pool_connections=workers, pool_maxsize=workers)
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    session.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    })

    def _probe(item_id: int) -> Optional[str]:
        url = base_tpl.format(item_id=item_id)
        try:
            with session.get(url, timeout=timeout, stream=True, allow_redirects=True, verify=False) as resp:
                if resp.status_code == 200:
                    return url
        except requests.RequestException:
            pass
        return None

    found_urls: List[str] = []
    try:
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = [executor.submit(_probe, iid) for iid in candidate_ids]
            for fut in as_completed(futures):
                u = fut.result()
                if u:
                    found_urls.append(u)
    finally:
        session.close()

    if not found_urls:
        return []

    found_urls.sort()
    engine = LocalLiveEngine()
    added_urls: List[str] = []

    for url in found_urls:
        try:
            meta, pdf_items = engine.fetch_meet_pdf_catalog(url)
            title = (meta.get("musabaka_adi") or "").strip()
            if not title and not pdf_items:
                continue

            sehir = (meta.get("sehir") or "").strip() or None
            tarih = (meta.get("tarih") or "").strip() or None
            start_d = meta.get("start_date") or ""
            end_d = meta.get("end_date") or ""

            event_obj = None
            if title:
                ev_qs = Event.objects.filter(musabaka_adi=title)
                if sehir:
                    ev_qs = ev_qs.filter(sehir__iexact=sehir)
                if start_d:
                    ev_qs = ev_qs.filter(yaris_tarihi_baslangic=start_d)
                event_obj = ev_qs.first()
                if not event_obj:
                    event_obj = db_retry(lambda: Event.objects.create(
                        musabaka_adi=title,
                        sehir=sehir,
                        yaris_tarihi_baslangic=start_d,
                        yaris_tarihi_bitis=end_d,
                        yaris_tarihi_ham=tarih or "",
                        kaynak_turu="CANLI_TAKIP",
                    ))

            if CanliYaris.objects.filter(canli_url=url).exists():
                continue

            db_retry(lambda: CanliYaris.objects.create(
                event=event_obj,
                canli_url=url,
                musabaka_adi=title or None,
                sehir=sehir,
                tarih=tarih,
                durum="ISLENIYOR",
            ))
            added_urls.append(url)
            logger.info(f"  [+] Yeni canlı yarış keşfedildi ve eklendi: {title} ({sehir or '-'}) -> {url}")
        except Exception as exc:
            logger.warning(f"  [!] Keşfedilen URL eklenemedi ({url}): {exc}")

    return added_urls


# ==============================================================================
# ÇOK GÜNLÜ YARIŞ TAMAMLANMA VE YENİDEN AÇMA MANTIĞI
# ==============================================================================

def _get_meet_date_bounds(yaris: CanliYaris, event: Optional[Event] = None) -> Tuple[str, str]:
    """Müsabakanın (baslangic_iso, bitis_iso) tarihlerini döndürür."""
    ev = event or yaris.event
    start_iso = (ev.yaris_tarihi_baslangic or "").strip() if ev else ""
    end_iso = (ev.yaris_tarihi_bitis or "").strip() if ev else ""

    if not start_iso or not end_iso:
        raw_date = (yaris.tarih or (ev.yaris_tarihi_ham if ev else "") or "").strip()
        if raw_date:
            p_start, p_end = parse_tr_date_range(raw_date)
            if not start_iso and p_start:
                start_iso = p_start
            if not end_iso and p_end:
                end_iso = p_end

    if not end_iso and start_iso:
        end_iso = start_iso
    return start_iso, end_iso


def _should_mark_meet_completed(
    yaris: CanliYaris,
    event: Optional[Event],
    all_start_count: int,
    islenen_start: int,
    all_result_count: int,
    islenen_sonuc: int,
    has_errors: bool = False,
) -> bool:
    """
    Çok günlük yarışlarda gün içinde yeni sonuç gelmediğinde erken TAMAMLANDI
    işaretlenmesini engeller. Bitiş tarihine kadar yarışı ISLENIYOR tutar.
    """
    if has_errors:
        return False
    if all_start_count > 0 and islenen_start < all_start_count:
        return False
    if all_result_count > 0 and islenen_sonuc < all_result_count:
        return False

    _, end_iso = _get_meet_date_bounds(yaris, event)
    now_tr = get_current_tr_time()
    today_date = now_tr.date()
    today_iso = today_date.isoformat()

    # Bitiş tarihinin üzerinden 2+ gün geçtiyse (iptal edilen yarış vb. yüzünden sonuç < start kalsa bile) kapat
    if end_iso:
        try:
            grace_end_iso = (datetime.strptime(end_iso, "%Y-%m-%d").date() + timedelta(days=2)).isoformat()
            if today_iso >= grace_end_iso:
                return True
        except ValueError:
            pass

        if today_iso < end_iso:
            return False
        if today_iso == end_iso and now_tr.hour < 20:
            return False

    if all_result_count <= 0:
        return False
    if all_start_count > 0 and islenen_sonuc < all_start_count:
        return False

    return True


def reopen_active_multiday_meets() -> int:
    """
    Çok günlük olup erken 'TAMAMLANDI' işaretlenmiş (bitiş tarihi henüz geçmemiş
    veya bugün yarış günü olan) müsabakaları tekrar 'ISLENIYOR' durumuna alır.
    """
    now_tr = get_current_tr_time()
    today_iso = now_tr.date().isoformat()
    reopened = 0

    completed_qs = CanliYaris.objects.filter(durum="TAMAMLANDI").select_related("event")
    for y in completed_qs:
        _, end_iso = _get_meet_date_bounds(y, y.event)
        should_reopen = False

        if end_iso:
            if today_iso < end_iso:
                should_reopen = True
            elif today_iso == end_iso and (
                now_tr.hour < 20
                or (y.toplam_start_listesi and y.islenen_sonuc_listesi < y.toplam_start_listesi)
            ):
                should_reopen = True
        elif y.son_islem_tarihi and (now_tr - y.son_islem_tarihi.astimezone(TR_TIMEZONE)).days <= 2:
            if y.toplam_start_listesi and y.islenen_sonuc_listesi < y.toplam_start_listesi:
                should_reopen = True

        if should_reopen:
            y.durum = "ISLENIYOR"
            db_retry(lambda obj=y: obj.save(update_fields=["durum"]))
            reopened += 1
            logger.info(
                f"  [↻] #{y.id} ({y.musabaka_adi or y.canli_url}) devam eden çok günlük yarış olduğu için "
                f"tekrar ISLENIYOR durumuna alındı (Bitiş: {end_iso or 'Bilinmiyor'})."
            )

    return reopened


# ==============================================================================
# SERVİS 1: SAATLİK CRON ORKESTRATÖRÜ
# ==============================================================================

def run_cron_orchestrator(
    start_hour: int = 8,
    end_hour: int = 20,
    poll_interval: int = DEFAULT_POLL_INTERVAL,
    discover: bool = True,
) -> None:
    """
    1. Servis: Her 5 dakikada bir çalışır.
    Çalışma saatleri (08:00 - 20:00) içinde önce yeni açılan TYF canlı yarışlarını keşfeder,
    ardından aktif canlı yarış varsa 5 sn'lik daemon'ı başlatır.
    """
    now = get_current_tr_time()
    logger.info(f"=== [Servis 1: Saatlik Cron Kontrolü Başladı] (Saat: {now.strftime('%H:%M:%S')}) ===")

    if not is_within_working_hours(start_hour=start_hour, end_hour=end_hour):
        logger.info(f"[*] Şu an saat {now.strftime('%H:%M')}. Çalışma saatleri dışındayız ({start_hour:02d}:00 - {end_hour:02d}:00). Çıkılıyor.")
        return

    if discover:
        try:
            newly_added = discover_new_live_meets()
            if newly_added:
                logger.info(f"[+] Otomatik tarama ile {len(newly_added)} yeni canlı yarış eklendi.")
        except Exception as exc:
            logger.warning(f"[!] Otomatik yarış keşif taraması uyarısı: {exc}")

    reopen_active_multiday_meets()

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
    reopen_active_multiday_meets()

    try:
        while True:
            now = get_current_tr_time()

            # Saat sınırını kontrol et (örn: 20:00'dan sonra kapan)
            if now.hour >= end_hour or now.hour < 8:
                logger.info(f"[*] Saat {now.strftime('%H:%M')}. Çalışma saatleri dışına çıkıldı. Daemon güvenle kapatılıyor.")
                break

            active_meets = list(
                CanliYaris.objects.filter(durum__in=["ISLENIYOR", "BEKLEMEDE", "BEKLIYOR"])
                .select_related("event")
                .order_by("-eklenen_kayit_sayisi", "-id")
            )
            if not active_meets:
                logger.info("[*] Takipte aktif canlı yarış kalmadı. Daemon güvenle kapatılıyor.")
                break

            due_meets = engine.filter_due_meets(active_meets, now.date().isoformat())
            if due_meets:
                catalogs = engine.prefetch_meet_catalogs(due_meets, max_workers=4)
                for yaris in due_meets:
                    if yaris.id in catalogs and catalogs[yaris.id] is None:
                        continue
                    engine.process_meet(yaris, force=False, prefetched_catalog=catalogs.get(yaris.id))

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
        yaris, created = db_retry(lambda: CanliYaris.objects.get_or_create(
            canli_url=url,
            defaults={"durum": "ISLENIYOR"}
        ))
        if not created and force:
            yaris.durum = "ISLENIYOR"
            db_retry(lambda: yaris.save(update_fields=["durum"]))
        return engine.process_meet(yaris, force=force)

    # Parametresiz çağrıda tüm aktif yarışları bir kez tara
    reopen_active_multiday_meets()
    active_meets = list(
        CanliYaris.objects.filter(durum__in=["ISLENIYOR", "BEKLEMEDE", "BEKLIYOR"])
        .select_related("event")
        .order_by("-eklenen_kayit_sayisi", "-id")
    )
    t_cat = time.perf_counter()
    catalogs = engine.prefetch_meet_catalogs(active_meets, max_workers=4)
    if active_meets:
        logger.info(f"[⚡] {len(active_meets)} yarış kataloğu {min(4, len(active_meets))} paralel iş parçacığıyla {time.perf_counter() - t_cat:.2f} sn'de çekildi.")
    results = []
    for y in active_meets:
        if y.id in catalogs and catalogs[y.id] is None:
            continue
        results.append(engine.process_meet(y, force=force, prefetched_catalog=catalogs.get(y.id)))
    return results


def deduplicate_live_results(event_id: Optional[int] = None) -> int:
    """
    Aynı (event, yaris_no/mesafe/stil/cinsiyet, seri, kulvar) için tekrar oluşmuş
    mükerrer YarisSonucu kayıtlarını temizler; gerçek (maskesiz) sporcuyu korur.
    """
    qs = YarisSonucu.objects.filter(
        seri__isnull=False,
        kulvar__isnull=False,
    ).exclude(seri="").select_related("sporcu")

    if event_id:
        qs = qs.filter(event_id=event_id)
    else:
        live_event_ids = list(CanliYaris.objects.exclude(event_id__isnull=True).values_list("event_id", flat=True))
        if not live_event_ids:
            return 0
        qs = qs.filter(event_id__in=live_event_ids)

    groups: Dict[tuple, List[YarisSonucu]] = {}
    for row in qs.iterator(chunk_size=500):
        m_s = re.search(r"\d+", str(row.seri or ""))
        seri_key = m_s.group() if m_s else str(row.seri or "").strip()
        key = (
            row.event_id,
            str(row.yaris_no or ""),
            row.mesafe,
            row.stil or "",
            row.cinsiyet or "",
            seri_key,
            row.kulvar,
        )
        groups.setdefault(key, []).append(row)

    to_delete: List[int] = []
    for key, rows in groups.items():
        if len(rows) <= 1:
            continue

        def _row_rank(r: YarisSonucu):
            sp_name = r.sporcu.sporcu_adi if r.sporcu else ""
            is_real = 1 if (sp_name and not sp_name.startswith("Maskeli sporcu")) else 0
            is_result = 1 if r.kaynak_turu == "CANLI_SONUC" else 0
            has_time = 1 if (r.derece_saniye is not None) else 0
            return (is_real, is_result, has_time, -r.id)

        rows_sorted = sorted(rows, key=_row_rank, reverse=True)
        for dup in rows_sorted[1:]:
            to_delete.append(dup.id)

    deleted_count = 0
    if to_delete:
        with transaction.atomic():
            for i in range(0, len(to_delete), 500):
                batch = to_delete[i:i + 500]
                cnt, _ = YarisSonucu.objects.filter(id__in=batch).delete()
                deleted_count += cnt

            orphan_cnt, _ = Sporcu.objects.filter(
                sporcu_adi__startswith="Maskeli sporcu",
                yaris_sonuclari__isnull=True,
            ).delete()
            if orphan_cnt:
                logger.info(f"[*] {orphan_cnt} sahipsiz 'Maskeli sporcu' kaydı temizlendi.")

    logger.info(f"[✔] Mükerrer temizliği tamamlandı: {deleted_count} tekrarlı sonuç satırı silindi.")
    return deleted_count


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
    parser.add_argument("--kesfet", action="store_true", help="Yeni canlı yarışları ileri ve geri tarayarak keşfet")
    parser.add_argument("--geri", type=int, default=DEFAULT_SCAN_BACK_LOOK, help=f"En yüksek ID'den geriye taranacak ID sayısı (varsayılan: {DEFAULT_SCAN_BACK_LOOK})")
    parser.add_argument("--ileri", type=int, default=DEFAULT_SCAN_WINDOW, help=f"En yüksek ID'den ileriye taranacak ID sayısı (varsayılan: {DEFAULT_SCAN_WINDOW})")
    parser.add_argument("--temizle", nargs="?", const=-1, type=int, help="Mükerrer seri/kulvar sonuçlarını temizle (isteğe bağlı Event ID)")

    args = parser.parse_args()

    if args.durdur:
        stop_daemon()
    elif args.durum:
        pid = get_running_daemon_pid()
        if pid:
            print(f"[+] 5 Saniyelik Canlı Takipçi AKTİF çalışıyor (PID: {pid}).")
        else:
            print("[-] Canlı Takipçi şu anda ÇALIŞMIYOR.")
    elif args.temizle is not None:
        ev_id = args.temizle if args.temizle > 0 else None
        deduplicate_live_results(event_id=ev_id)
    elif args.baslat:
        start_daemon_background(poll_interval=args.interval)
    elif args.kesfet:
        added = discover_new_live_meets(window=args.ileri, back_look=args.geri)
        print(f"[+] Keşif tamamlandı: {len(added)} yeni yarış eklendi (Geri: {args.geri}, İleri: {args.ileri}).")
    elif args.cron:
        run_cron_orchestrator(poll_interval=args.interval)
    elif args.daemon:
        run_daemon_worker(poll_interval=args.interval)
    else:
        run_local_live_worker(url=args.url, interval=args.interval, force=args.force)
