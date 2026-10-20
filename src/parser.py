"""
src/parser.py
Sorumluluk: Metne dönüştürülmüş yüzme sonuç belgelerini (.txt) ayrıştırarak
src/models.py içindeki Pydantic modellerine (MeetInfo, EventInfo, SwimmerResultEntry,
RelayResultEntry, UnparsedLine) dönüştürmek.

Desteklenen Özellikler:
1. Bireysel Yarışlar:
   - Sıra, sporcu adı/soyadı, doğum yılı, kulüp, derece (dakika:saniye ve saniye cinsinden),
     FINA/AQUA puanları, katılım türü (Ferdi/Takım/Takım Dışı).
   - "KATILIM BARAJINI GEÇTİ" ve baraj durumları (qualified=True).
   - Satırdaki ara süreler (row_times) ve 400m+ split süreleri (splits: 50m, 100m, 200m...).
   - Diskalifiye (disk./DQ) durumları, kural kodları (SW 4.4 vb.), nedenleri ve saati.
2. Bayrak Yarışları (Relay):
   - Takım adı, kulüp, derece, puan ve bayrak takımındaki yüzücüler (RelaySwimmer).
3. Müsabaka ve Seans Meta Verileri:
   - Müsabaka adı, şehri, tarih aralığı, seans adı, yarış numarası, stil, mesafe, cinsiyet, yaş grubu.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Ensure project root is in sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.models import (
    EventInfo,
    MeetInfo,
    RelayResultEntry,
    RelaySwimmer,
    SwimmerResultEntry,
    UnparsedLine,
)

# --- REGEX KALIPLARI ---

# Sayfa ayracı (pdf_reader tarafından eklenir)
PAGE_SEPARATOR_RE = re.compile(r"^===\s*SAYFA\s+(\d+)\s*/\s*(\d+)\s*===$")

# Seans başlığı (Örn: "1 - 1. GÜN SABAH SEANSI            22.03.2025 - 9:30")
SESSION_RE = re.compile(
    r"^\s*(\d+\s*-\s*[\d\.]+\s*GÜN\s+[A-ZÇĞİÖŞÜ\s]+SEANSI)"
    r"(?:\s{2,}|\t+)?([0-9\.\s:\-]+)?$",
    re.I,
)

# Yarış Başlığı (Örn: "Yarış 1    Kızlar, 100m Serbest    10 yaş" veya "Yarış 14, Kızlar, 4 x 50m Serbest")
EVENT_HEADER_RE = re.compile(
    r"^\s*Yar[ıiIİ][şsSŞ]\s+(\d+)\s*(?:,\s*|(?:\s{2,}|\t+))"
    r"([A-ZÇĞİÖŞÜa-zçğıöşü\s,]+?)(?:,\s*|(?:\s{2,}|\t+))"
    r"(\d+\s*x\s*\d+m|\d+m)\s+"
    r"([A-Za-zÇĞİÖŞÜçğıöşü\s]+?)"
    r"(?:(?:,\s*|(?:\s{2,}|\t+))([0-9\s\-+a-zçğıöşüA-ZÇĞİÖŞÜ]+))?$",
    re.I,
)

# Alt Yaş Grubu Başlığı (Örn: "10 yaş", "11 - 12 yaşları arası", "14 yaş ve büyükler")
AGE_SUBHEADER_RE = re.compile(
    r"^\s*(\d{1,2}(?:\s*-\s*\d{1,2})?\s*(?:yaş[a-z]*|yaşları arası|yaş ve büyükler|yaş ve üzeri))\s*$",
    re.I,
)

# Sayfa devam yarış başlığı (Örn: "Yarış 1, Kızlar, 100m Serbest, 10 yaş" veya "Yarış 4, Erkekler, 100m Serbest")
RUNNING_EVENT_RE = re.compile(
    r"^\s*Yar[ıiIİ][şsSŞ]\s+(\d+),\s*"
    r"([A-ZÇĞİÖŞÜa-zçğıöşü\s]+?),\s*"
    r"(\d+\s*x\s*\d+m|\d+m)\s+"
    r"([A-Za-zÇĞİÖŞÜçğıöşü\s]+?)"
    r"(?:,\s*(.+?))?$",
    re.I,
)

# Yarış Tarihi ve Sonuçlar satırı (Örn: "22.03.2025            Sonuçlar" veya "14.10.2022 - 9:30   Sonuçlar")
EVENT_DATE_RESULTS_RE = re.compile(
    r"^\s*(\d{1,2}\.\d{1,2}\.\d{4})(?:\s*-\s*([0-9:]+))?\s+Sonu[çc]lar\s*$",
    re.I,
)

# Baraj geçme bildirimi
QUALIFIED_RE = re.compile(
    r"(?:KATILIM\s+)?BARAJI(?:NI)?\s+GEÇTİ|BARAJ\s+GEÇTİ", re.I
)

# Diskalifiye Kuralı (Örn: "SW 4.4 - Yüzücü çıkış sinyalinden önce... (Zaman: 09:42)")
DQ_RULE_RE = re.compile(
    r"^\s*(SW\s+[0-9.]+)\s*-\s*(.*?)(?:\s+DQ)?(?:\s*\(Zaman:\s*([0-9:]*)\))?$",
    re.I,
)

# Uzun mesafe splitleri (Örn: "50m: 35.85 35.85 100m: 1:16.60 40.75 ...")
SPLIT_RE = re.compile(r"(\d+m):\s*([0-9:.]+)")

# Atlanacak gürültü satırları
IGNORE_LINE_RE = re.compile(
    r"^(?:Splash Meet Manager|Registered to|BAŞHAKEM|Puanlar:|Sıra\s+YB|"
    r"Sıra\s+Time|Sıra\s+Sporcu|Zaman\s+Derece|Sonuçlar|"
    r"[A-ZÇĞİÖŞÜ\s]+\s+BAŞHAKEM|.*katılım barajları|.*MİLLİ TAKIM|.*BÖLGE KARMALARI|"
    r"[AB][1-4]\b|^[AB]\s+BARAJI\b|.*BARAJI?\b|"
    r"DUVARI\s+\d+\s*M)",
    re.I,
)


def time_to_seconds(time_str: Optional[str]) -> Optional[float]:
    """'1:17.22' veya '35.01' formatındaki dereceyi saniye cinsinden float değere çevirir."""
    if not time_str:
        return None
    time_str = time_str.strip()
    try:
        if ":" in time_str:
            parts = time_str.split(":")
            if len(parts) == 2:
                mins, secs = parts
                return round(int(mins) * 60 + float(secs), 2)
            elif len(parts) == 3:
                hrs, mins, secs = parts
                return round(int(hrs) * 3600 + int(mins) * 60 + float(secs), 2)
        return round(float(time_str), 2)
    except Exception:
        return None


def normalize_birth_year(by_str: str) -> int:
    """'15' -> 2015, '09' -> 2009, '98' -> 1998, '2015' -> 2015"""
    by = int(by_str.strip())
    if len(by_str.strip()) <= 2:
        return (1900 + by) if by > 35 else (2000 + by)
    return by


def map_gender(text: str) -> str:
    """'Kızlar' / 'Bayanlar' -> 'F', 'Erkekler' -> 'M', 'Karma'/'Mix' -> 'X'"""
    t = text.lower()
    if any(k in t for k in ["kız", "bayan", "kadın"]):
        return "F"
    if "erkek" in t:
        return "M"
    if any(k in t for k in ["karma", "mix"]):
        return "X"
    return "X"


def map_stroke(text: str) -> str:
    t = text.lower()
    if "serbest" in t:
        return "Serbest"
    if "sırt" in t:
        return "Sırtüstü"
    if "kurbağa" in t:
        return "Kurbağalama"
    if "kelebek" in t:
        return "Kelebek"
    if "karışık" in t:
        return "Karışık"
    return text.strip()


class SwimmingResultsParser:
    """Tek bir yüzme yarış sonuç dosyasını ayrıştıran sınıf."""

    def __init__(self, file_path: Path):
        self.file_path = file_path
        self.file_name = file_path.name
        self.meet_info = MeetInfo()
        self.current_session = ""
        self.current_event: Optional[EventInfo] = None
        self.active_age_group = ""

        self.swimmer_entries: List[SwimmerResultEntry] = []
        self.relay_entries: List[RelayResultEntry] = []
        self.unparsed_lines: List[UnparsedLine] = []

        self.current_page: int = 1
        self.total_pages: int = 1
        self.page_section: str = "OUTSIDE"
        self.header_step: int = 0
        self.current_referees: List[str] = []

        self._last_swimmer_entry: Optional[SwimmerResultEntry] = None
        self._last_relay_entry: Optional[RelayResultEntry] = None
        self.col_is_age: bool = False

    def _extract_meet_year(self) -> int:
        """Müsabaka tarihi veya adından 4 haneli müsabaka yılını çeker."""
        for src in [self.meet_info.date_range, self.current_session, self.meet_info.name]:
            m = re.search(r"\b(20\d{2})\b", src or "")
            if m:
                return int(m.group(1))
        return 2024

    def parse(self) -> Tuple[MeetInfo, List[SwimmerResultEntry], List[RelayResultEntry], List[UnparsedLine]]:
        lines = self.file_path.read_text(encoding="utf-8").splitlines()
        line_idx = 0
        total_lines = len(lines)

        while line_idx < total_lines:
            raw_line = lines[line_idx]
            line = raw_line.strip()
            line_no = line_idx + 1
            line_idx += 1

            if not line:
                continue

            # 1. Sayfa Ayracı (=== SAYFA X / Y ===)
            m_page = PAGE_SEPARATOR_RE.match(line)
            if m_page:
                self.current_page = int(m_page.group(1))
                self.total_pages = int(m_page.group(2))
                self.page_section = "PAGE_HEADER"
                self.header_step = 0
                continue

            # 2. Sayfa Üstbilgisi (PAGE_HEADER)
            if self.page_section == "PAGE_HEADER":
                if self.header_step == 0:
                    # Başlık Kontrolü: Doğrudan sonuç/DQ ile başlayan taşma sayfası mı?
                    is_result_or_dq = bool(
                        re.match(r"^(?:SW\s+\d|\(Zaman:|disk\.|terk\.|DNS|\d+\.|\(Fd\)|\(Tk\)|\(Td\)|td\.)", line, re.I)
                    )
                    if is_result_or_dq or (self.meet_info.name and line != self.meet_info.name and not line.startswith("Yarış")):
                        # Başlıksız taşma sayfası: Sonuç gövdesine devret, satırı tüketme
                        self.page_section = "RESULTS_BODY"
                    else:
                        if not self.meet_info.name:
                            self.meet_info.name = line
                        self.header_step = 1
                        continue

                if self.header_step == 1:
                    # Şehir ve Tarih Aralığı (Sadece gerçek şehir satırı ise tüket)
                    u = line.strip().upper()
                    is_city = False
                    if not (u.startswith("YARIŞ") or u.startswith("YARIS") or "SEANSI" in u or "SONUÇLAR" in u or "SONUCLAR" in u or u.startswith("SIRA")):
                        if any(u.startswith(c) for c in ["ANKARA", "İSTANBUL", "İZMİR", "BURSA", "ANTALYA", "TRABZON"]):
                            is_city = True
                        elif re.search(r"\d{1,2}[\.-]\s*(?:\d{1,2}[\.-]\s*)?\d{4}", line) and "," in line:
                            is_city = True

                    if is_city:
                        if not self.meet_info.location:
                            if "," in line and any(c.isdigit() for c in line):
                                parts = line.split(",", 1)
                                self.meet_info.location = parts[0].strip()
                                self.meet_info.date_range = parts[1].strip()
                            else:
                                self.meet_info.location = line.strip()
                        self.header_step = 2
                        continue
                    else:
                        if not self.meet_info.location:
                            self.meet_info.location = "ANKARA"
                        self.header_step = 2
                        # Satırı tüketme, doğrudan adım 2'ye (aşağıya) devam et

                if self.header_step == 2:
                    m_session = SESSION_RE.match(line)
                    if m_session:
                        self.current_session = m_session.group(1).strip()
                        if m_session.group(2):
                            self.current_session += f" ({m_session.group(2).strip()})"
                        continue

                    m_run = RUNNING_EVENT_RE.match(line)
                    if m_run:
                        if m_run.group(5):
                            self.active_age_group = m_run.group(5).strip()
                        continue

                    m_ev = EVENT_HEADER_RE.match(line)
                    if m_ev:
                        race_no = m_ev.group(1)
                        gender_str = m_ev.group(2)
                        dist_str = m_ev.group(3)
                        stroke_str = m_ev.group(4)
                        age_str = (m_ev.group(5) or "").strip()

                        is_relay = "x" in dist_str.lower()
                        relay_count = None
                        distance = 0
                        if is_relay:
                            r_match = re.search(r"(\d+)\s*x\s*(\d+)m", dist_str, re.I)
                            if r_match:
                                relay_count = int(r_match.group(1))
                                distance = int(r_match.group(2))
                        else:
                            d_match = re.search(r"(\d+)m", dist_str, re.I)
                            if d_match:
                                distance = int(d_match.group(1))

                        self.current_event = EventInfo(
                            session=self.current_session,
                            race_number=race_no,
                            gender=map_gender(gender_str),
                            distance=distance,
                            stroke=map_stroke(stroke_str),
                            age_group=age_str,
                            is_relay=is_relay,
                            relay_count=relay_count,
                            page_number=self.current_page,
                        )
                        self.active_age_group = age_str
                        self._last_swimmer_entry = None
                        self._last_relay_entry = None
                        self.col_is_age = False
                        continue

                    m_date = EVENT_DATE_RESULTS_RE.match(line)
                    if m_date:
                        if self.current_event:
                            self.current_event.event_date = m_date.group(1)
                            if m_date.group(2):
                                self.current_event.event_time = m_date.group(2)
                        continue

                    if re.search(r"Sıra\s+(?:Yaş|Age)\b", line, re.I):
                        self.col_is_age = True
                        self.page_section = "RESULTS_BODY"
                        continue
                    elif re.search(r"Sıra\s+(?:YB|Time|Zaman|Derece|Sporcu)\b", line, re.I):
                        self.col_is_age = False
                        self.page_section = "RESULTS_BODY"
                        continue

                    if re.search(r"katılım barajları|Puanlar:|[AB][1-4]\b|.*BARAJI?\b", line, re.I):
                        continue

                    # Gövdeye devret
                    self.page_section = "RESULTS_BODY"

            # 3. Sayfa Altbilgisi (PAGE_FOOTER) Kontrolü
            # 3.1. Hakem isimleri satırı (sonraki satırda BAŞHAKEM varsa)
            if line_idx < total_lines and re.search(r"\bBAŞHAKEM\b", lines[line_idx], re.I):
                if re.match(r"^[A-ZÇĞİÖŞÜ\s]{3,}$", line) and not any(c.isdigit() for c in line):
                    self.page_section = "PAGE_FOOTER"
                    self.current_referees = [n.strip() for n in re.split(r"\s{2,}|\t+", line) if n.strip()]
                    continue

            # 3.2. BAŞHAKEM satırı
            if re.search(r"\bBAŞHAKEM\b", line, re.I):
                self.page_section = "PAGE_FOOTER"
                continue

            # 3.3. Splash Meet Manager altbilgisi
            if re.search(r"Splash Meet Manager", line, re.I):
                self.page_section = "PAGE_FOOTER"
                continue

            # 3.4. Eğer PAGE_FOOTER state'indeysek, sonraki sayfaya kadar olan satırlar altbilgidir
            if self.page_section == "PAGE_FOOTER":
                continue

            # 5. Alt Yaş Grubu Başlığı (Örn: "10 yaş")
            m_age = AGE_SUBHEADER_RE.match(line)
            if m_age and self.current_event and not line.isdigit():
                self.active_age_group = m_age.group(1).strip()
                continue

            # 6. Baraj Geçme Bildirimi ("KATILIM BARAJINI GEÇTİ")
            if QUALIFIED_RE.search(line):
                if self._last_swimmer_entry:
                    self._last_swimmer_entry.qualified = True
                continue

            # 7. Diskalifiye Kural Satırı (SW 4.4 vb.)
            m_dq = DQ_RULE_RE.match(line)
            if m_dq:
                if self._last_swimmer_entry:
                    self._last_swimmer_entry.dq_rule = m_dq.group(1).strip()
                    self._last_swimmer_entry.dq_reason = m_dq.group(2).strip()
                    if m_dq.group(3):
                        self._last_swimmer_entry.dq_clock = m_dq.group(3).strip()
                elif self._last_relay_entry:
                    self._last_relay_entry.dq_rule = m_dq.group(1).strip()
                    self._last_relay_entry.dq_reason = m_dq.group(2).strip()
                continue

            # 7.1. Diskalifiye Açıklama Devam Satırı (Örn: "bağlantısı kaybolduğundan (Zaman: 17:35), 2/3")
            if (self._last_relay_entry and self._last_relay_entry.status == "DQ" and not self._last_relay_entry.swimmers) or \
               (self._last_swimmer_entry and self._last_swimmer_entry.status == "DQ"):
                if re.search(r"\(Zaman:\s*[0-9:]*\)|,\s*\d+/\d+|platformuyla|dokunmadan|ayrıldığı|kural|hareket|bozduğundan|duvar|metre|\b\d+\s*m\b|dönüş|bitiriş|çıkış", line, re.I):
                    target = self._last_relay_entry if (self.current_event and self.current_event.is_relay) else self._last_swimmer_entry
                    if target:
                        target.dq_reason = (target.dq_reason + " " + line).strip()
                        m_clk = re.search(r"\(Zaman:\s*([0-9:]+)\)", line)
                        if m_clk and hasattr(target, "dq_clock"):
                            target.dq_clock = m_clk.group(1).strip()
                        continue

            # 8. 400m+ Split Süreleri Satırı
            if ":" in line and SPLIT_RE.search(line):
                splits_found = SPLIT_RE.findall(line)
                if splits_found and self._last_swimmer_entry:
                    for sp_dist, sp_time in splits_found:
                        self._last_swimmer_entry.splits[sp_dist] = sp_time
                    continue

            # 8.1. Sütun Başlığı Tespiti: Sıra Yaş/Age mi yoksa Sıra YB mi?
            if re.search(r"Sıra\s+(?:Yaş|Age)\b", line, re.I):
                self.col_is_age = True
                continue
            elif re.search(r"Sıra\s+YB\b", line, re.I):
                self.col_is_age = False
                continue

            # 9. Göz Ardı Edilecek Başlık/Altbilgi Satırları
            if IGNORE_LINE_RE.match(line):
                continue

            # 10. Sonuç Satırı Ayrıştırma (Bireysel veya Bayrak)
            if self.current_event and self.current_event.is_relay:
                parsed_relay = self._parse_relay_row(line)
                if parsed_relay:
                    self.relay_entries.append(parsed_relay)
                    self._last_relay_entry = parsed_relay
                    self._last_swimmer_entry = None
                    continue

                # Bayrak yüzücüleri satırı mı? (Örn: "Nil Nehir ÖZDEMİR 9 Duru TÜMERDEM 9")
                if self._last_relay_entry and len(self._last_relay_entry.swimmers) < (self._last_relay_entry.relay_count or 4):
                    relay_swimmers = self._parse_relay_swimmers_line(line)
                    if relay_swimmers:
                        self._last_relay_entry.swimmers.extend(relay_swimmers)
                        continue

            elif self.current_event:
                parsed_swimmer = self._parse_swimmer_row(line)
                if parsed_swimmer:
                    self.swimmer_entries.append(parsed_swimmer)
                    self._last_swimmer_entry = parsed_swimmer
                    self._last_relay_entry = None
                    continue

            # 11. Ayrıştırılamayan Satır Kaydı
            # Eğer satır çok kısa değilse ve bilinen bir ara metin değilse unparsed olarak kaydet
            if len(line) > 5 and not line.startswith("==="):
                self.unparsed_lines.append(
                    UnparsedLine(
                        file_name=self.file_name,
                        line_number=line_no,
                        raw_text=line,
                        reason="Kural dışı veya eşleşmeyen satır formatı",
                        meet_name=self.meet_info.name,
                        session=self.current_session,
                        event_title=f"Yarış {self.current_event.race_number}" if self.current_event else "",
                    )
                )

        return self.meet_info, self.swimmer_entries, self.relay_entries, self.unparsed_lines

    def _estimate_birth_year(self) -> int:
        """Doğum yılı sütunu olmayan yarışlarda yılı müsabaka yılı ve yaştan tahmin eder."""
        meet_year = None
        m_year = re.search(r"\b(20\d{2})\b", (self.meet_info.date_range or "") + " " + (self.meet_info.name or ""))
        if m_year:
            meet_year = int(m_year.group(1))

        age_text = self.active_age_group or (self.current_event.age_group if self.current_event else "")
        m_age = re.search(r"\b(\d{1,2})\s*yaş", age_text, re.I)
        if m_age and meet_year:
            return meet_year - int(m_age.group(1))
        return meet_year or 2000

    def _parse_swimmer_row(self, line: str) -> Optional[SwimmerResultEntry]:
        """Bireysel sporcu sonuç satırını ayrıştırır."""
        work_line = line
        status = "OK"
        rank: Optional[int] = None
        part_type: Optional[str] = None

        # Durum tespiti (disk. / terk. / yarış terk / DNS / DNF / td. vb.)
        if re.match(r"^(?:disk\.|DQ|DISK)\b", work_line, re.I):
            status = "DQ"
            work_line = re.sub(r"^(?:disk\.|DQ|DISK)\s*", "", work_line, flags=re.I)
        elif re.match(r"^(?:yar[ıi]ş[ıi]?\s*terk|terk\.?|DNF)\b", work_line, re.I):
            status = "DNF"
            work_line = re.sub(r"^(?:yar[ıi]ş[ıi]?\s*terk|terk\.?|DNF)\s*", "", work_line, flags=re.I)
        elif re.match(r"^(?:DNS|yar[ıi]ş[a-z\s]*girmedi|start\s*almad[ıi])\b", work_line, re.I):
            status = "DNS"
            work_line = re.sub(r"^(?:DNS|yar[ıi]ş[a-z\s]*girmedi|start\s*almad[ıi])\s*", "", work_line, flags=re.I)
        elif re.match(r"^(?:td\.|TD\.)\s*", work_line, re.I):
            part_type = "Takım Dışı"
            work_line = re.sub(r"^(?:td\.|TD\.)\s*", "", work_line, flags=re.I)
        else:
            # Normal sıralı satır (Örn: "1. " veya "(Fd) 1. ")
            m_rank = re.match(r"^(?:\((Fd|Tk|Td)\)\s*)?(\d+)\.\s*", work_line, re.I)
            if m_rank:
                if m_rank.group(1):
                    code = m_rank.group(1).lower()
                    part_type = "Ferdi" if code == "fd" else ("Takım" if code == "tk" else "Takım Dışı")
                rank = int(m_rank.group(2))
                work_line = work_line[m_rank.end() :]
            else:
                # Splash Meet Manager'da aynı dereceyi paylaşan (berabere kalan) sporcuların sıra no'su
                # boş bırakılır. Bu sporcular önceki sporcunun sırasını devralır.
                rank = self._last_swimmer_entry.rank if self._last_swimmer_entry else None

        # Sporcu adının önündeki katılım türü kontrolü: "(Fd) Serenay ..."
        m_pt = re.match(r"^\((Fd|Tk|Td)\)\s*", work_line, re.I)
        if m_pt:
            code = m_pt.group(1).lower()
            part_type = "Ferdi" if code == "fd" else ("Takım" if code == "tk" else "Takım Dışı")
            work_line = work_line[m_pt.end() :]

        # Derece ve Puan içeren tam satır eşleşmesi
        # Örn: "Eda ERTÜRK 15 Ankara Üniversitesi Spor Kulübü 1:17.22 300"
        # veya derece olmayabilir (Diskalifiye): "Selmin ULUDAĞ 15 Ankara Enerji Yüzme Spor Kulübü"
        full_pattern = re.compile(
            r"^([A-ZÇĞİÖŞÜa-zçğıöşü\s\.\'\-]+?)"          # İsim
            r"(\d{1,4})\s+"                               # Doğum Yılı
            r"(?:\((Fd|Tk|Td)\)\s*)?"                     # Kulüp önündeki katılım türü
            r"(.+?)"                                      # Kulüp
            r"(?:\s+(\d{1,2}:\d{2}\.\d{2}|\d{1,2}\.\d{2}))?"  # Derece (opsiyonel)
            r"(?:\s+(\d+|-))?"                            # Puan (opsiyonel)
            r"((?:\s+\d{1,2}(?::\d{2})?\.\d{2})*)\s*$",  # Satırdaki ara süreler
            re.I,
        )
        m = full_pattern.match(work_line)
        if not m:
            # Fallback: Doğum yılı sütunu olmayan yarış listeleri (Örn: 14-16-Ekim-2022)
            # Örn: "Beril ÇAĞRI    Ted Ankara Kolejliler Spor Kulübü    30.12  485"
            no_by_pattern = re.compile(
                r"^([A-ZÇĞİÖŞÜa-zçğıöşü\s\.\'\-]+?)\s{2,}"
                r"(.+?)\s+"
                r"(\d{1,2}:\d{2}\.\d{2}|\d{1,2}\.\d{2})"
                r"(?:\s+(\d+|-))?"
                r"((?:\s+\d{1,2}(?::\d{2})?\.\d{2})*)\s*$",
                re.I,
            )
            m2 = no_by_pattern.match(work_line)
            if not m2:
                return None

            name_raw = m2.group(1).strip()
            birth_year = self._estimate_birth_year()
            club_raw = m2.group(2).strip()
            time_txt = m2.group(3)
            pts_str = m2.group(4)
            points = int(pts_str) if (pts_str and pts_str.isdigit()) else None
            trailing = (m2.group(5) or "").strip()
            row_times = trailing.split() if trailing else []
            clean_club = re.sub(r"^\((?:Fd|Tk|Td)\)\s*", "", club_raw, flags=re.I).strip()
        else:
            name_raw = m.group(1).strip()
            by_raw = m.group(2)
            if self.col_is_age:
                meet_yr = self._extract_meet_year()
                birth_year = meet_yr - int(by_raw)
            else:
                birth_year = normalize_birth_year(by_raw)

            if m.group(3) and not part_type:
                code = m.group(3).lower()
                part_type = "Ferdi" if code == "fd" else ("Takım" if code == "tk" else "Takım Dışı")

            club_raw = m.group(4).strip()
            time_txt = m.group(5)
            pts_str = m.group(6)
            points = int(pts_str) if (pts_str and pts_str.isdigit()) else None

            trailing = (m.group(7) or "").strip()
            row_times = trailing.split() if trailing else []
            clean_club = re.sub(r"^\((?:Fd|Tk|Td)\)\s*", "", club_raw, flags=re.I).strip()

        # Doğrulama: Sporcu adı en az 2 kelimeden oluşmalı, tek harf veya başlık olmamalı
        if len(name_raw.split()) < 2 or len(name_raw) < 3 or (birth_year and (birth_year < 1980 or birth_year > 2025)):
            return None

        ev = self.current_event
        return SwimmerResultEntry(
            meet_name=self.meet_info.name,
            meet_location=self.meet_info.location,
            meet_date=self.meet_info.date_range,
            page_number=self.current_page,
            session=ev.session if ev else self.current_session,
            race_number=ev.race_number if ev else "",
            gender=ev.gender if ev else "",
            distance=ev.distance if ev else 0,
            stroke=ev.stroke if ev else "",
            age_group=self.active_age_group or (ev.age_group if ev else ""),
            rank=rank,
            name=name_raw,
            name_raw=name_raw,
            birth_year=birth_year,
            club=clean_club,
            club_raw=club_raw,
            participation_type=part_type,
            time_txt=time_txt,
            time_sec=time_to_seconds(time_txt),
            points=points,
            status=status,
            row_times=row_times,
        )

    def _parse_relay_row(self, line: str) -> Optional[RelayResultEntry]:
        """Bayrak takımı sonuç satırını ayrıştırır (Örn: '1. Zafer Koleji 1  Zafer Koleji  2:44.24  202')."""
        work_line = line.strip()
        status = "OK"
        rank: Optional[int] = None

        if re.match(r"^(?:disk\.|DQ|DISK)\b", work_line, re.I):
            status = "DQ"
            work_line = re.sub(r"^(?:disk\.|DQ|DISK)\s*", "", work_line, flags=re.I)
        elif re.match(r"^(?:yar[ıi]ş[ıi]?\s*terk|terk\.?|DNF)\b", work_line, re.I):
            status = "DNF"
            work_line = re.sub(r"^(?:yar[ıi]ş[ıi]?\s*terk|terk\.?|DNF)\s*", "", work_line, flags=re.I)
        elif re.match(r"^(?:DNS|yar[ıi]ş[a-z\s]*girmedi|start\s*almad[ıi])\b", work_line, re.I):
            status = "DNS"
            work_line = re.sub(r"^(?:DNS|yar[ıi]ş[a-z\s]*girmedi|start\s*almad[ıi])\s*", "", work_line, flags=re.I)
        else:
            # Sıra zorunludur: Örn: "1.  " veya "(Tk) 1.  "
            m_rank = re.match(r"^(?:\((?:Fd|Tk|Td)\)\s*)?(\d+)\.\s*", work_line, re.I)
            if not m_rank:
                return None
            rank = int(m_rank.group(1))
            work_line = work_line[m_rank.end():]

        # work_line sonundaki derece ve puanı bul:
        # Örn: "Aykon Spor Kulübü            Aykon Spor Kulübü            4:38.77  365"
        # veya DQ ise derece olmayabilir: "Ted Ankara Kolejliler Spor Kulübü         Ted Ankara Kolejliler Spor Kulübü"
        m_time = re.search(r"(\d{1,2}:\d{2}\.\d{2}|\d{1,2}\.\d{2})(?:\s+(\d+|-))?\s*$", work_line)
        if m_time:
            time_txt = m_time.group(1)
            pts_str = m_time.group(2)
            points = int(pts_str) if (pts_str and pts_str.isdigit()) else None
            names_part = work_line[:m_time.start()].strip()
        else:
            if status == "OK":
                return None  # Derecesi olmayan ve DQ/DNS olmayan satır bayrak takımı olamaz
            time_txt = None
            points = None
            names_part = work_line.strip()

        # Takım adı ve kulüp adını ayrıştır
        parts = re.split(r"\s{2,}|\t+", names_part)
        team_name = parts[0].strip() if parts else names_part
        club = parts[1].strip() if len(parts) >= 2 else team_name

        team_name = re.sub(r"^\((?:Fd|Tk|Td)\)\s*", "", team_name, flags=re.I).strip()
        club = re.sub(r"^\((?:Fd|Tk|Td)\)\s*", "", club, flags=re.I).strip()

        ev = self.current_event
        return RelayResultEntry(
            meet_name=self.meet_info.name,
            meet_location=self.meet_info.location,
            meet_date=self.meet_info.date_range,
            page_number=self.current_page,
            session=ev.session if ev else self.current_session,
            race_number=ev.race_number if ev else "",
            gender=ev.gender if ev else "X",
            relay_count=ev.relay_count or 4 if ev else 4,
            distance=ev.distance if ev else 50,
            stroke=ev.stroke if ev else "Serbest",
            age_group=self.active_age_group or (ev.age_group if ev else ""),
            rank=rank,
            team_name=team_name,
            club=club,
            time_txt=time_txt,
            time_sec=time_to_seconds(time_txt),
            points=points,
            status=status,
        )

    def _parse_relay_swimmers_line(self, line: str) -> List[RelaySwimmer]:
        """
        Bayrak takımındaki yüzücüleri satırdan çıkarır.
        3 farklı format desteklenir:
        1. Virgülle ayrılmış liste: 'Ada Arya REYHAN, Nil ÇIRACIOĞLU, Emir Berk ARPACI, Demir OĞUZ'
        2. Çift kolonlu (İsim + Doğum Yılı + Süre): 'Naz Çiçek TOSUN 15 59.36  Elif Naz ÜNAL 15 0.00'
        3. Çift kolonlu (İsim + Split/Reaksiyon Süreleri): 'Ilay TAŞGIN 33.78 1:10.32  Ateş KARALLI 0.00 17.00 1:16.70'
        """
        line_str = line.strip()
        if not line_str:
            return []

        # 1. Format: Virgülle ayrılmış liste (Genellikle diskalifiye bayrak takımları altında yer alır)
        if "," in line_str and not any(char.isdigit() for char in line_str):
            names = [n.strip() for n in line_str.split(",") if len(n.strip()) >= 3]
            if len(names) >= 2:
                return [
                    RelaySwimmer(name=n, name_raw=n, birth_year=None, split_time=None)
                    for n in names
                ]

        # 2 & 3. Format: İki kolonlu yüzücü isimleri ve süreleri
        name_pattern = re.compile(
            r"(?:\((?:Fd|Tk|Td)\)\s*)?([A-ZÇĞİÖŞÜ][a-zçğıöşüA-ZÇĞİÖŞÜ\.\'\-]+(?:[ \t][A-ZÇĞİÖŞÜa-zçğıöşü\.\'\-]+)+)"
        )
        matches = list(name_pattern.finditer(line_str))
        if not matches:
            return []

        swimmers: List[RelaySwimmer] = []
        for i, m in enumerate(matches):
            name = m.group(1).strip()
            if re.match(r"^(?:Zaman|Derece|Sıra|Sayfa|Splash|Registered|BAŞHAKEM)", name, re.I):
                continue

            start = m.end()
            end = matches[i + 1].start() if i + 1 < len(matches) else len(line_str)
            tail = line_str[start:end].strip()

            tokens = tail.split()
            birth_year = None
            times = []
            for tok in tokens:
                if tok.isdigit() and len(tok) <= 2:
                    birth_year = normalize_birth_year(tok)
                elif "." in tok or ":" in tok:
                    times.append(tok)

            valid_times = [t for t in times if t != "0.00"]
            split_time = valid_times[-1] if valid_times else (times[-1] if times else None)

            swimmers.append(
                RelaySwimmer(
                    name=name,
                    name_raw=name,
                    birth_year=birth_year,
                    split_time=split_time,
                )
            )

        return swimmers


def parse_file(file_path: str | Path) -> Tuple[MeetInfo, List[SwimmerResultEntry], List[RelayResultEntry], List[UnparsedLine]]:
    """Tek bir .txt dosyasını ayrıştırır."""
    parser = SwimmingResultsParser(Path(file_path))
    return parser.parse()


def parse_directory(
    txt_dir: str | Path = "output/txt/ankara",
    output_json_path: Optional[str | Path] = None,
) -> Dict[str, dict]:
    """Klasördeki tüm .txt sonuç belgelerini ayrıştırır ve özet çıkarır."""
    txt_path = Path(txt_dir)
    txt_files = sorted(txt_path.glob("*.txt"))

    all_data = {}
    total_swimmers = 0
    total_relays = 0
    total_unparsed = 0

    t0 = time.perf_counter()
    for idx, txt_file in enumerate(txt_files, start=1):
        meet, swimmers, relays, unparsed = parse_file(txt_file)
        total_swimmers += len(swimmers)
        total_relays += len(relays)
        total_unparsed += len(unparsed)

        all_data[txt_file.stem] = {
            "meet": meet.model_dump(),
            "swimmer_count": len(swimmers),
            "relay_count": len(relays),
            "unparsed_count": len(unparsed),
            "swimmers": [s.model_dump() for s in swimmers],
            "relays": [r.model_dump() for r in relays],
        }

        print(
            f"[{idx:02d}/{len(txt_files):02d}] {txt_file.name[:45]:45s} | "
            f"Sporcu: {len(swimmers):4d} | Bayrak: {len(relays):2d} | Atlanan: {len(unparsed):3d}"
        )

    elapsed = time.perf_counter() - t0
    print(
        f"\nİşlem Tamamlandı! ({elapsed:.2f}s)\n"
        f"Toplam Dosya  : {len(txt_files)}\n"
        f"Toplam Sporcu : {total_swimmers:,}\n"
        f"Toplam Bayrak : {total_relays:,}\n"
        f"Toplam Atlanan: {total_unparsed:,}"
    )

    if output_json_path:
        out_p = Path(output_json_path)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        out_p.write_text(json.dumps(all_data, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"JSON çıktısı kaydedildi: {out_p}")

    return all_data


def main() -> None:
    arg_parser = argparse.ArgumentParser(
        description="Yüzme yarış sonuç metin belgelerini yapılandırılmış verilere ayrıştırır."
    )
    arg_parser.add_argument(
        "--input-dir",
        default="output/txt/ankara",
        help="Ayrıştırılacak .txt belgelerinin bulunduğu klasör",
    )
    arg_parser.add_argument(
        "--output-json",
        default="output/parsed_results.json",
        help="Ayrıştırılan verilerin kaydedileceği JSON dosyası",
    )
    args = arg_parser.parse_args()

    parse_directory(args.input_dir, args.output_json)


if __name__ == "__main__":
    main()
