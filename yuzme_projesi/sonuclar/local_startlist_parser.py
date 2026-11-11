# -*- coding: utf-8 -*-
"""
local_startlist_parser.py
=========================
Yerel (Local) PDF Start Listesi Ayrıştırıcı.
Gemini veya harici yapay zeka API'si kullanmadan tamamen yerel PyMuPDF (fitz)
ve regex tabanlı kurallarla TYF ve Okul Sporları Start Listesi PDF'lerini parse eder.

Özellikler:
- Okul Sporları ve TYF Splash Meet Manager formatlarını destekler.
- Sayfa bölünmelerinde serilerin kesilmesini (sayfa 1'de başlayan serinin sayfa 2'de devam etmesi) çözer.
- Maskelenmiş sporcu isimlerini (ör. '(Fd) *o**k **e *onb**cı'), kulvar, seri, kulüp ve giriş derecesini eksiksiz çıkarır.
- Mevcut hiçbir modülü (live_engine vb.) değiştirmez; bağımsız çalışır.
"""

import os
import sys
import re
import json
import logging
from typing import Dict, List, Any, Optional, Union

try:
    import fitz  # PyMuPDF
except ImportError:
    fitz = None

logger = logging.getLogger("local_startlist_parser")
if not logger.handlers:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter("[%(levelname)s] %(message)s"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)


class LocalStartListParser:
    """
    Yerel Start Listesi PDF Ayrıştırıcı.
    """

    # Regex Tanımları
    RE_SERI = re.compile(r"^\s*Seri\s+(\d+)(?:\s*(?:/|of)\s*(\d+))?", re.IGNORECASE)
    RE_TABLE_HEADER = re.compile(r"^(Kulvar|Sporcu|D\.Yılı|Kulüp|Giriş|YB|Sıra|Lane|Heat)$", re.IGNORECASE)
    RE_PAGE_FOOTER = re.compile(
        r"^(Sayfa\s+\d+/\d+|Türkiye Yüzme Federasyonu|Bu dosya.*oluşturuldu\.?|Splash Meet Manager.*|Registered to.*)$",
        re.IGNORECASE,
    )
    RE_TIME = re.compile(r"^(?:(\d{1,2}):)?(\d{2})[.,](\d{2})$|^NT$", re.IGNORECASE)
    RE_YEAR = re.compile(r"^(19\d\d|20\d\d|\d{2})$")
    RE_LANE_ONLY = re.compile(r"^([1-9]|10)$")
    RE_LANE_AND_NAME = re.compile(r"^([1-9]|10)\s+(.+)$")
    RE_DATE = re.compile(r"(\d{2}[./-]\d{2}[./-]\d{4})")
    RE_EVENT_INFO = re.compile(
        r"(Erkekler|Kadınlar|Bayanlar|Men|Women|Boys|Girls)\s*,?\s*(\d+)\s*m\s+([A-Za-zçğıöşüÇĞİÖŞÜ]+)",
        re.IGNORECASE,
    )

    def __init__(self):
        if fitz is None:
            raise ImportError("PyMuPDF (fitz) kütüphanesi yüklü değil. 'pip install pymupdf' gereklidir.")

    def parse(self, pdf_source: Union[str, bytes]) -> Dict[str, Any]:
        """
        PDF dosya yolunu veya byte verisini ayrıştırıp yapılandırılmış dict döner.
        """
        if isinstance(pdf_source, bytes):
            doc = fitz.open(stream=pdf_source, filetype="pdf")
        elif isinstance(pdf_source, str) and os.path.exists(pdf_source):
            doc = fitz.open(pdf_source)
        else:
            raise ValueError(f"Geçersiz PDF kaynağı: {pdf_source}")

        try:
            total_pages = len(doc)
            page_lines_list: List[List[str]] = []

            for pno in range(total_pages):
                page = doc[pno]
                # Satırları temizle ve boş satırları ele
                raw_text = page.get_text("text")
                lines = [l.strip() for l in raw_text.splitlines() if l.strip()]
                page_lines_list.append(lines)

            # 1. Başlık Bilgilerini Çıkar
            header_info = self._extract_header_info(page_lines_list)
            header_info["toplam_sayfa"] = total_pages

            # 2. Seriler ve Sporcuları Çıkar
            swimmers = self._extract_swimmers(page_lines_list, header_info)

            # 3. Serilere göre grupla
            series_dict: Dict[str, List[Dict[str, Any]]] = {}
            for s in swimmers:
                s_key = s["seri"] or "Bilinmeyen Seri"
                if s_key not in series_dict:
                    series_dict[s_key] = []
                series_dict[s_key].append(s)

            return {
                "musabaka_adi": header_info.get("musabaka_adi"),
                "tarih": header_info.get("tarih"),
                "yaris": header_info.get("yaris"),
                "cinsiyet": header_info.get("cinsiyet"),
                "mesafe": header_info.get("mesafe"),
                "stil": header_info.get("stil"),
                "toplam_sayfa": total_pages,
                "toplam_seri": len(series_dict),
                "toplam_sporcu": len(swimmers),
                "seriler": series_dict,
                "sporcular": swimmers,
            }
        finally:
            doc.close()

    def _extract_header_info(self, page_lines_list: List[List[str]]) -> Dict[str, Any]:
        """
        İlk sayfanın tepe satırlarından müsabaka adı, tarih ve yarış bilgilerini çıkarır.
        """
        info: Dict[str, Any] = {
            "musabaka_adi": None,
            "tarih": None,
            "yaris": None,
            "cinsiyet": None,
            "mesafe": None,
            "stil": None,
        }

        if not page_lines_list:
            return info

        p1_lines = page_lines_list[0]

        # Müsabaka adı genellikle 1. veya 2. satırdadır
        for i in range(min(5, len(p1_lines))):
            l = p1_lines[i]
            if "Splash Meet Manager" in l or "Registered to" in l:
                continue
            if not info["musabaka_adi"] and len(l) > 5 and not self.RE_DATE.search(l):
                info["musabaka_adi"] = l
                break

        # Tarih ve Yarış tespiti (ilk 20 satırı tara)
        for l in p1_lines[:25]:
            # Tarih
            if not info["tarih"]:
                m_dt = self.RE_DATE.search(l)
                if m_dt:
                    info["tarih"] = m_dt.group(1)

            # Yarış adı
            if not info["yaris"]:
                m_ev = self.RE_EVENT_INFO.search(l)
                if m_ev:
                    info["cinsiyet"] = "Erkek" if m_ev.group(1).lower().startswith(("erkek", "men", "boy")) else "Kadın"
                    info["mesafe"] = int(m_ev.group(2))
                    info["stil"] = m_ev.group(3)
                    info["yaris"] = f"{info['cinsiyet']} {info['mesafe']}m {info['stil']}"

        return info

    def _extract_swimmers(
        self,
        page_lines_list: List[List[str]],
        header_info: Dict[str, Any]
    ) -> List[Dict[str, Any]]:
        """
        Tüm sayfaları sırayla gezip seri ve kulvar sporcularını toplar.
        Sayfa geçişlerinde seri devamlılığını korur.
        """
        swimmers: List[Dict[str, Any]] = []
        current_seri: Optional[str] = None
        current_seri_no: Optional[int] = None
        toplam_seri: Optional[int] = None

        for page_idx, lines in enumerate(page_lines_list):
            pno = page_idx + 1
            idx = 0
            n_lines = len(lines)

            while idx < n_lines:
                line = lines[idx]

                # Alt bilgi / Sayfa numarası satırlarını atla
                if self.RE_PAGE_FOOTER.match(line):
                    idx += 1
                    continue

                # İlk sayfa başlık satırlarını atla
                if pno == 1 and idx < 10:
                    if (
                        line == header_info.get("musabaka_adi")
                        or "Start Listesi" in line
                        or "Start listesi" in line
                        or (header_info.get("yaris") and line in header_info.get("yaris"))
                    ):
                        idx += 1
                        continue

                # Seri Başlığı kontrolü (Örn: "Seri 1/9" veya "Seri 1 of 31")
                m_seri = self.RE_SERI.match(line)
                if m_seri:
                    current_seri_no = int(m_seri.group(1))
                    if m_seri.group(2):
                        toplam_seri = int(m_seri.group(2))
                        current_seri = f"Seri {current_seri_no}/{toplam_seri}"
                    else:
                        current_seri = f"Seri {current_seri_no}"
                    idx += 1
                    continue

                # Tablo Başlığı kontrolü (Kulvar, Sporcu, D.Yılı, Kulüp, Giriş)
                if self.RE_TABLE_HEADER.match(line):
                    idx += 1
                    continue

                # SPORCU SATIRI KONTROLÜ
                # Tip 1: Okul Sporları Formatı (Kulvar tek başına ayrı bir satırda: "1", "2"..)
                if self.RE_LANE_ONLY.match(line):
                    lane = int(line)
                    idx += 1
                    if idx >= n_lines:
                        break

                    athlete_name = lines[idx]

                    # Doğum yılı satırı
                    idx += 1
                    birth_year = None
                    if idx < n_lines and self.RE_YEAR.match(lines[idx]):
                        birth_year = lines[idx]
                        idx += 1

                    # Kulüp satırı
                    club = None
                    if (
                        idx < n_lines
                        and not self.RE_LANE_ONLY.match(lines[idx])
                        and not self.RE_SERI.match(lines[idx])
                        and not self.RE_PAGE_FOOTER.match(lines[idx])
                        and not self.RE_TABLE_HEADER.match(lines[idx])
                    ):
                        club = lines[idx]
                        idx += 1

                    # Giriş derecesi (opsiyonel)
                    entry_time = None
                    if idx < n_lines and self.RE_TIME.match(lines[idx]):
                        entry_time = lines[idx]
                        idx += 1

                    swimmers.append({
                        "seri": current_seri,
                        "kulvar": lane,
                        "sporcu": athlete_name,
                        "dogum_yili": birth_year,
                        "kulup": club,
                        "giris_derecesi": entry_time,
                    })
                    continue

                # Tip 2: Splash Meet Manager Formatı ("1 Arda MUTLU" -> Kulvar ve Ad aynı satırda)
                m_lane_name = self.RE_LANE_AND_NAME.match(line)
                if m_lane_name:
                    lane = int(m_lane_name.group(1))
                    athlete_name = m_lane_name.group(2).strip()

                    # Doğum Yılı satırı
                    idx += 1
                    birth_year = None
                    if idx < n_lines and self.RE_YEAR.match(lines[idx]):
                        birth_year = lines[idx]
                        idx += 1

                    # Kulüp satırı
                    club = None
                    if (
                        idx < n_lines
                        and not self.RE_LANE_ONLY.match(lines[idx])
                        and not self.RE_LANE_AND_NAME.match(lines[idx])
                        and not self.RE_SERI.match(lines[idx])
                        and not self.RE_PAGE_FOOTER.match(lines[idx])
                    ):
                        club = lines[idx]
                        idx += 1

                    # Giriş derecesi
                    entry_time = None
                    if idx < n_lines and self.RE_TIME.match(lines[idx]):
                        entry_time = lines[idx]
                        idx += 1

                    swimmers.append({
                        "seri": current_seri,
                        "kulvar": lane,
                        "sporcu": athlete_name,
                        "dogum_yili": birth_year,
                        "kulup": club,
                        "giris_derecesi": entry_time,
                    })
                    continue

                idx += 1

        return swimmers


def parse_startlist_pdf(pdf_path_or_bytes: Union[str, bytes]) -> Dict[str, Any]:
    """
    Kullanım kolaylığı için yardımcı fonksiyon.
    """
    parser = LocalStartListParser()
    return parser.parse(pdf_path_or_bytes)


if __name__ == "__main__":
    import argparse

    # Argüman parse veya varsayılan dosya
    target_pdf = r"C:\Users\OZDEN\Desktop\StartList_1080.pdf"
    if len(sys.argv) > 1:
        target_pdf = sys.argv[1]

    print(f"[*] Ayrıştırılıyor: {target_pdf}\n")
    parser = LocalStartListParser()
    result = parser.parse(target_pdf)

    print("=" * 70)
    print(f"Müsabaka Adı : {result['musabaka_adi']}")
    print(f"Tarih        : {result['tarih']}")
    print(f"Yarış        : {result['yaris']} ({result['cinsiyet']}, {result['mesafe']}m {result['stil']})")
    print(f"Toplam Sayfa : {result['toplam_sayfa']}")
    print(f"Toplam Seri  : {result['toplam_seri']}")
    print(f"Toplam Sporcu: {result['toplam_sporcu']}")
    print("=" * 70)

    for seri_adi, sporcular in result["seriler"].items():
        print(f"\n--- {seri_adi} ({len(sporcular)} Sporcu) ---")
        for sp in sporcular:
            kulvar = sp["kulvar"]
            sporcu = sp["sporcu"]
            dy = sp["dogum_yili"] or "----"
            kulup = sp["kulup"] or "-"
            derece = sp["giris_derecesi"] or "--:--"
            print(f"  Kulvar {kulvar:2d} | {sporcu:30s} | {dy} | {derece:7s} | {kulup}")
