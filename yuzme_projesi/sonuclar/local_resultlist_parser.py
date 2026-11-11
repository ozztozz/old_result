# -*- coding: utf-8 -*-
"""
local_resultlist_parser.py
==========================
Yerel (Local) PDF Sonuç Listesi (ResultList) Ayrıştırıcı.
Gemini veya harici yapay zeka API'si kullanmadan tamamen yerel PyMuPDF (fitz)
ve koordinat-blok kurallarıyla TYF ve Okul Sporları Sonuç Listesi PDF'lerini parse eder.

Özellikler:
- Okul Sporları ve TYF Sonuç Listesi formatlarını tam destekler.
- Sıra, Kulvar/Seri (K/S), Doğum Yılı, Maskeli Sporcu Adı, Kulüp, Derece ve FINA puanlarını eksiksiz çıkarır.
- DSQ (Diskalifiye), DNS (Yarışa Başlamadı), DNF (Terk), EXH (Değerlendirme Dışı) durumlarını ayrıştırır.
- Sayfa bölünmelerinden etkilenmez, çok sayfalı yarış sonuçlarını bir bütün olarak toplar.
- Opsiyonel olarak yerel veritabanından 'unmasking' (maske kaldırma) yaparak gerçek sporcu adını eşleştirir.
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

logger = logging.getLogger("local_resultlist_parser")
if not logger.handlers:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter("[%(levelname)s] %(message)s"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)


class LocalResultListParser:
    """
    Yerel Sonuç Listesi (ResultList) PDF Ayrıştırıcı.
    """

    RE_TIME = re.compile(r"^(?:(\d{1,2}):)?(\d{2})[.,](\d{2})$")
    RE_KS = re.compile(r"^(\d+)/(\d+)$")
    RE_YEAR = re.compile(r"^(19\d\d|20\d\d|\d{2})$")
    RE_DATE = re.compile(r"(\d{2}[./-]\d{2}[./-]\d{4})")
    RE_EVENT_INFO = re.compile(
        r"(Erkekler|Kadınlar|Bayanlar|Men|Women|Boys|Girls)\s*,?\s*(\d+)\s*m\s+([A-Za-zçğıöşüÇĞİÖŞÜ]+)",
        re.IGNORECASE,
    )
    RE_STATUS = re.compile(r"\b(DSQ|DNS|DNF|EXH)\b", re.IGNORECASE)

    def __init__(self):
        if fitz is None:
            raise ImportError("PyMuPDF (fitz) kütüphanesi gereklidir.")

    def parse(self, pdf_source: Union[str, bytes], unmask: bool = False) -> Dict[str, Any]:
        """
        Sonuç listesi PDF'ini yerel olarak ayrıştırır.
        """
        if isinstance(pdf_source, bytes):
            doc = fitz.open(stream=pdf_source, filetype="pdf")
        elif isinstance(pdf_source, str) and os.path.exists(pdf_source):
            doc = fitz.open(pdf_source)
        else:
            raise ValueError(f"Geçersiz PDF kaynağı: {pdf_source}")

        try:
            total_pages = len(doc)
            header_info = self._extract_header(doc)
            header_info["toplam_sayfa"] = total_pages

            sonuclar: List[Dict[str, Any]] = []

            for pno in range(total_pages):
                page = doc[pno]
                page_results = self._parse_page_results(page, pno + 1)
                sonuclar.extend(page_results)

            # Sıralamaya göre düzenle (önce derece alanlar, sonra DSQ/DNS/DNF/EXH)
            sonuclar.sort(key=lambda x: (0 if x["sira"] is not None else 1, x["sira"] or 9999))

            # Opsiyonel Unmasking
            if unmask:
                self._apply_unmasking(sonuclar, header_info.get("cinsiyet"))

            return {
                "tur": "sonuc_listesi",
                "musabaka_adi": header_info.get("musabaka_adi"),
                "tarih": header_info.get("tarih"),
                "yaris": header_info.get("yaris"),
                "cinsiyet": header_info.get("cinsiyet"),
                "mesafe": header_info.get("mesafe"),
                "stil": header_info.get("stil"),
                "yas_grubu": header_info.get("yas_grubu"),
                "toplam_sayfa": total_pages,
                "toplam_sonuc": len(sonuclar),
                "derece_alanlar": len([s for s in sonuclar if s["durum"] == "OK"]),
                "dsq_dns_sayisi": len([s for s in sonuclar if s["durum"] != "OK"]),
                "sonuclar": sonuclar,
            }
        finally:
            doc.close()

    def _extract_header(self, doc: fitz.Document) -> Dict[str, Any]:
        info: Dict[str, Any] = {
            "musabaka_adi": None,
            "tarih": None,
            "yaris": None,
            "cinsiyet": None,
            "mesafe": None,
            "stil": None,
            "yas_grubu": None,
        }

        if len(doc) == 0:
            return info

        p1 = doc[0]
        blocks = p1.get_text("blocks")
        lines = [b[4].strip() for b in blocks[:10] if b[4].strip()]

        for l in lines:
            if not info["musabaka_adi"] and len(l) > 5 and not self.RE_DATE.search(l) and "Sonuçlar" not in l:
                info["musabaka_adi"] = l.replace("\n", " ").strip()

            if not info["tarih"]:
                m_dt = self.RE_DATE.search(l)
                if m_dt:
                    info["tarih"] = m_dt.group(1)

            if not info["yaris"]:
                m_ev = self.RE_EVENT_INFO.search(l)
                if m_ev:
                    info["cinsiyet"] = "Erkek" if m_ev.group(1).lower().startswith(("erkek", "men", "boy")) else "Kadın"
                    info["mesafe"] = int(m_ev.group(2))
                    info["stil"] = m_ev.group(3)
                    info["yaris"] = f"{info['cinsiyet']} {info['mesafe']}m {info['stil']}"

            if "Baraj" in l and not info["yas_grubu"]:
                info["yas_grubu"] = l.replace("\n", " ").strip()

        return info

    def _parse_page_results(self, page: fitz.Page, page_no: int) -> List[Dict[str, Any]]:
        blocks = page.get_text("blocks")
        results: List[Dict[str, Any]] = []

        athlete_blocks = []
        dsq_blocks = []
        right_blocks = [b for b in blocks if b[0] > 400]

        for b in blocks:
            txt = b[4].strip()
            lines = [l.strip() for l in txt.split("\n") if l.strip()]
            if not lines:
                continue

            # Alt bilgi kontrolü
            if "Türkiye Yüzme Federasyonu" in txt or re.match(r"^Sayfa\s+\d+/\d+$", txt):
                continue

            # DSQ / DNS / DNF / EXH blokları
            if any(txt.startswith(k) or f"\n{k}" in txt for k in ["DSQ", "DNS", "DNF", "EXH"]):
                dsq_blocks.append((b, lines))
                continue

            # Normal Sporcu Satırı (Sol Kolon x0 < 100 ve ilk satır Sıra sayısı)
            if b[0] < 100 and re.match(r"^\d+$", lines[0]) and len(lines) >= 3:
                if self.RE_KS.match(lines[1]) or (len(lines) > 2 and self.RE_KS.match(lines[2])):
                    athlete_blocks.append((b, lines))

        # 1. Normal Derece Alan Sporcuları Ayrıştır
        for ab, lines in athlete_blocks:
            sira = int(lines[0])
            ks_match = None
            d_yili = None
            rem_start = 1

            if self.RE_KS.match(lines[1]):
                ks_match = lines[1]
                rem_start = 2
                if len(lines) > 2 and self.RE_YEAR.match(lines[2]):
                    d_yili = lines[2]
                    rem_start = 3
            elif len(lines) > 2 and self.RE_KS.match(lines[2]):
                d_yili = lines[1]
                ks_match = lines[2]
                rem_start = 3

            rem_lines = lines[rem_start:]

            # Baraj notu ayıkla
            baraj = None
            if rem_lines and ("Baraj" in rem_lines[-1] or "Barajı" in rem_lines[-1]):
                baraj = rem_lines.pop()

            # Kulüp adı genellikle son satırdır
            club = rem_lines.pop() if rem_lines else None

            # Kalan parçalar sporcu adıdır (satır kırılmalarını düzgün bağla)
            athlete_parts = []
            for rl in rem_lines:
                rl = rl.strip()
                if not athlete_parts:
                    athlete_parts.append(rl)
                elif rl.startswith("*") and athlete_parts[-1].endswith("*"):
                    athlete_parts[-1] += rl
                elif len(rl) == 1 and rl == "*":
                    athlete_parts[-1] += rl
                else:
                    athlete_parts.append(rl)

            athlete_name = " ".join(athlete_parts).strip()
            athlete_name = re.sub(r"\s+", " ", athlete_name)

            # Eşleşen Dereceyi Sağ Kolondan Bul (Aynı y0 koordinatına en yakın blok)
            best_rb = None
            min_dy = 999.0
            for rb in right_blocks:
                dy = abs(rb[1] - ab[1])
                if dy < min_dy and dy < 15:
                    min_dy = dy
                    best_rb = rb

            derece = None
            fina_puan = None

            if best_rb:
                rb_lines = [l.strip() for l in best_rb[4].split("\n") if l.strip()]
                for l in rb_lines:
                    # '50m 23.84' gibi ara zamanları atla, saf dereceyi yakala
                    if self.RE_TIME.match(l):
                        derece = l
                        break
                if not derece and rb_lines:
                    derece = rb_lines[0]

                # Fina puanı var mı (dereceden sonraki tam sayı)
                for l in rb_lines:
                    if re.match(r"^\d{2,4}$", l) and l != d_yili:
                        try:
                            fina_puan = int(l)
                            break
                        except ValueError:
                            pass

            kulvar, seri = ks_match.split("/") if ks_match else (None, None)

            results.append({
                "sira": sira,
                "kulvar": int(kulvar) if kulvar else None,
                "seri": int(seri) if seri else None,
                "dogum_yili": d_yili,
                "sporcu": athlete_name,
                "kulup": club,
                "derece": derece,
                "puan": fina_puan,
                "durum": "OK",
                "notlar": baraj,
                "sayfa": page_no,
            })

        # 2. DSQ / DNS / DNF / EXH Ayrıştır
        for db, lines in dsq_blocks:
            full_txt = " ".join(lines)
            tokens = re.split(r"(?<=\))\s*(?=(?:DSQ|DNS|DNF|EXH)\b)|(?<=[a-zçğıöşü])\s+(?=(?:DSQ|DNS|DNF|EXH)\b)", full_txt, flags=re.IGNORECASE)

            for token in tokens:
                token = token.strip()
                if not token:
                    continue
                m_st = re.match(r"^(DSQ|DNS|DNF|EXH)\s+(.*)", token, re.IGNORECASE)
                if m_st:
                    status = m_st.group(1).upper()
                    rest = m_st.group(2).strip()

                    # Sebep / Açıklama parantezini ayır
                    reason = None
                    m_reason = re.search(r"\(([^)]+)\)$", rest)
                    if m_reason:
                        reason = m_reason.group(1)
                        rest = rest[:m_reason.start()].strip()

                    results.append({
                        "sira": None,
                        "kulvar": None,
                        "seri": None,
                        "dogum_yili": None,
                        "sporcu": rest,
                        "kulup": None,
                        "derece": None,
                        "puan": None,
                        "durum": status,
                        "notlar": reason,
                        "sayfa": page_no,
                    })

        return results

    def _apply_unmasking(self, sonuclar: List[Dict[str, Any]], gender: Optional[str]):
        """
        athlete_matcher ile veritabanından sporcu unmasking işlemi yapar.
        """
        try:
            current_dir = os.path.dirname(os.path.abspath(__file__))
            proj_dir = os.path.dirname(current_dir)
            if proj_dir not in sys.path:
                sys.path.insert(0, proj_dir)

            import django
            from django.apps import apps
            if not apps.ready:
                os.environ.setdefault("DJANGO_SETTINGS_MODULE", "yuzme_projesi.settings")
                django.setup()

            from sonuclar.athlete_matcher import match_athlete
        except Exception as exc:
            logger.warning(f"athlete_matcher yüklenemedi, unmasking atlandı: {exc}")
            return

        for s in sonuclar:
            if not s.get("sporcu"):
                continue
            # Doğum yılı yoksa (örn: DSQ / EXH satırları) tam DB taramasından kaçınmak için atla
            if not s.get("dogum_yili"):
                s["unmasked"] = False
                s["cozulen_ad"] = None
                s["sporcu_id"] = None
                s["eslesme_durumu"] = "dogum_yili_yok"
                continue

            m = match_athlete(
                name=s["sporcu"],
                birth_year_or_date=s.get("dogum_yili"),
                club=s.get("kulup"),
                gender=gender,
            )
            is_exact = (m.get("sonuc") == "tam_eslesme")
            s["unmasked"] = is_exact
            s["cozulen_ad"] = m.get("sporcu", {}).get("sporcu_adi") if is_exact else None
            s["sporcu_id"] = m.get("bulunan_id")
            s["eslesme_durumu"] = m.get("sonuc")


def parse_resultlist_pdf(pdf_source: Union[str, bytes], unmask: bool = False) -> Dict[str, Any]:
    """
    Kullanım kolaylığı sağlayan sarmalayıcı fonksiyon.
    """
    parser = LocalResultListParser()
    return parser.parse(pdf_source, unmask=unmask)


if __name__ == "__main__":
    target = r"C:\Users\OZDEN\Desktop\ResultList_1080.pdf"
    do_unmask = True

    if len(sys.argv) > 1:
        target = sys.argv[1]
    if "--no-unmask" in sys.argv:
        do_unmask = False

    print("=" * 80)
    print(f"AYRIŞTIRILIYOR (ResultList): {target}")
    print(f"Unmasking Aktif: {do_unmask}")
    print("=" * 80)

    parser = LocalResultListParser()
    res = parser.parse(target, unmask=do_unmask)

    print(f"Müsabaka    : {res['musabaka_adi']}")
    print(f"Tarih       : {res['tarih']}")
    print(f"Yarış       : {res['yaris']}")
    print(f"Toplam Sayfa: {res['toplam_sayfa']}")
    print(f"Toplam Sonuç: {res['toplam_sonuc']} (Derece Alan: {res['derece_alanlar']}, DSQ/DNS: {res['dsq_dns_sayisi']})")
    print("-" * 80)

    for item in res["sonuclar"][:25]:
        sira = f"{item['sira']:2d}." if item['sira'] is not None else f"[{item['durum']}]"
        ks = f"K{item['kulvar']}/S{item['seri']}" if item['kulvar'] else "   -   "
        dy = item['dogum_yili'] or "----"
        derece = item['derece'] or "--:--"
        sporcu = item['sporcu']
        cozulen = f"-> {item['cozulen_ad']}" if item.get('cozulen_ad') else ""
        print(f"{sira:<5} {ks:<8} {dy:<6} {derece:<8} {sporcu:<25} {cozulen}")

    if len(res["sonuclar"]) > 25:
        print(f"... ({len(res['sonuclar']) - 25} sporcu daha var)")

    if res["dsq_dns_sayisi"] > 0:
        print("\n--- Diskalifiye / Özel Durumlar ---")
        for item in [s for s in res["sonuclar"] if s["durum"] != "OK"]:
            print(f"[{item['durum']}] {item['sporcu']} (Not: {item['notlar']})")
