# -*- coding: utf-8 -*-
"""
local_resultlist_parser.py
==========================
Yerel (Local) PDF Sonuç Listesi (ResultList) Ayrıştırıcı.
Gemini veya harici yapay zeka API'si kullanmadan tamamen yerel PyMuPDF (fitz)
ve regex tabanlı kurallarla TYF ve Okul Sporları Sonuç Listesi PDF'lerini parse eder.

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
    Yerel Sonuç Listesi (ResultList) PDF Ayrıştırıcı (Regex Tabanlı).
    """

    RE_TIME = re.compile(r"^(?:(\d{1,2}):)?(\d{2})[.,](\d{2})$")
    RE_KS = re.compile(r"^(\d+)/(\d+)$")
    RE_INT = re.compile(r"^\d+$")
    RE_YEAR = re.compile(r"^(19\d\d|20\d\d|\d{2})$")
    RE_YEAR_PREFIX = re.compile(r"^(19\d\d|20\d\d)([A-Za-zçğıöşüÇĞİÖŞÜ*].*)$")
    RE_DATE = re.compile(r"(\d{2}[./-]\d{2}[./-]\d{4})")
    RE_EVENT_INFO = re.compile(
        r"(Erkekler|Kadınlar|Bayanlar|Men|Women|Boys|Girls)\s*,?\s*(\d+\s*x\s*\d+|\d+)\s*m\s+([A-Za-zçğıöşüÇĞİÖŞÜ]+)(?:\s+(Bayrak|Relay))?",
        re.IGNORECASE,
    )
    RE_TABLE_HEADER = re.compile(
        r"^(Sıra|Kulvar|K/S|Sporcu|D\.Yılı|Kulüp|Derece|Fina|Rank|Lane|Heat|Time|Pts)$",
        re.IGNORECASE,
    )
    RE_PAGE_FOOTER = re.compile(
        r"^(Sayfa\s+\d+/\d+|Türkiye Yüzme Federasyonu|Bu dosya.*oluşturuldu\.?|Splash Meet Manager.*|Registered to.*)$",
        re.IGNORECASE,
    )
    RE_SPLIT_LINE = re.compile(
        r"^\d+\s*m\s+(?:(?:\d{1,2}:)?\d{2}[.,]\d{2})\b",
        re.IGNORECASE,
    )
    RE_STATUS_START = re.compile(r"^(DSQ|DNS|DNF|EXH)\s+(.+)$", re.IGNORECASE)

    def __init__(self):
        if fitz is None:
            raise ImportError("PyMuPDF (fitz) kütüphanesi gereklidir.")

    def parse(self, pdf_source: Union[str, bytes], unmask: bool = False) -> Dict[str, Any]:
        """
        Sonuç listesi PDF'ini yerel olarak düz metin + regex ile ayrıştırır.
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
                raw_text = doc[pno].get_text("text")
                lines = [l.strip() for l in raw_text.splitlines() if l.strip()]
                page_lines_list.append(lines)

            header_info = self._extract_header(page_lines_list)
            header_info["toplam_sayfa"] = total_pages

            sonuclar = self._extract_results(page_lines_list, header_info)

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

    def _extract_header(self, page_lines_list: List[List[str]]) -> Dict[str, Any]:
        info: Dict[str, Any] = {
            "musabaka_adi": None,
            "tarih": None,
            "yaris": None,
            "cinsiyet": None,
            "mesafe": None,
            "stil": None,
            "yas_grubu": None,
        }

        if not page_lines_list:
            return info

        for l in page_lines_list[0][:15]:
            if "Splash Meet Manager" in l or "Registered to" in l:
                continue

            if not info["musabaka_adi"] and len(l) > 5 and not self.RE_DATE.search(l) and "Sonuçlar" not in l:
                info["musabaka_adi"] = l

            if not info["tarih"]:
                m_dt = self.RE_DATE.search(l)
                if m_dt:
                    info["tarih"] = m_dt.group(1)

            if not info["yaris"]:
                m_ev = self.RE_EVENT_INFO.search(l)
                if m_ev:
                    info["cinsiyet"] = "Erkek" if m_ev.group(1).lower().startswith(("erkek", "men", "boy")) else "Kadın"
                    dist_str = m_ev.group(2).replace(" ", "")
                    if "x" in dist_str.lower():
                        nums = [int(n) for n in re.findall(r"\d+", dist_str)]
                        info["mesafe"] = nums[0] * nums[1] if len(nums) >= 2 else 400
                        raw_stil = m_ev.group(3).capitalize()
                        info["stil"] = f"{raw_stil} Bayrak" if "Bayrak" not in raw_stil else raw_stil
                    else:
                        info["mesafe"] = int(dist_str)
                        raw_stil = m_ev.group(3).capitalize()
                        if m_ev.group(4) or "bayrak" in l.lower():
                            info["stil"] = f"{raw_stil} Bayrak" if "Bayrak" not in raw_stil else raw_stil
                        else:
                            info["stil"] = raw_stil
                    info["yaris"] = f"{info['cinsiyet']} {info['mesafe']}m {info['stil']}"

            if "baraj" in l.lower() and not info["yas_grubu"] and not self.RE_TABLE_HEADER.match(l):
                info["yas_grubu"] = l

        return info

    def _is_header_or_noise(self, line: str, header_info: Dict[str, Any]) -> bool:
        return (
            line == header_info.get("musabaka_adi")
            or line == header_info.get("yas_grubu")
            or line == header_info.get("yaris")
            or "Sonuçlar" in line
            or bool(self.RE_EVENT_INFO.search(line))
        )

    @staticmethod
    def _join_athlete_parts(parts: List[str]) -> str:
        athlete_parts: List[str] = []
        for rl in parts:
            rl = rl.strip()
            if not rl:
                continue
            if not athlete_parts:
                athlete_parts.append(rl)
            elif rl.startswith("*") and athlete_parts[-1].endswith("*"):
                athlete_parts[-1] += rl
            elif rl == "*":
                athlete_parts[-1] += rl
            else:
                athlete_parts.append(rl)
        return re.sub(r"\s+", " ", " ".join(athlete_parts)).strip()

    def _parse_dsq_block(self, full_txt: str, page_no: int) -> List[Dict[str, Any]]:
        results: List[Dict[str, Any]] = []
        tokens = re.split(
            r"(?<=\))\s*(?=(?:DSQ|DNS|DNF|EXH)\b)|(?<=[a-zçğıöşü])\s+(?=(?:DSQ|DNS|DNF|EXH)\b)",
            full_txt,
            flags=re.IGNORECASE,
        )
        for token in tokens:
            token = token.strip()
            if not token:
                continue
            m_st = re.match(r"^(DSQ|DNS|DNF|EXH)\s+(.*)", token, re.IGNORECASE)
            if not m_st:
                continue
            status = m_st.group(1).upper()
            rest = m_st.group(2).strip()

            reason = None
            m_reason = re.search(
                r"\((?:\d{1,2}:\d{2}\s*-\s*)?(?:SW\b|sw\b|KURBAĞALAMA|SERBEST|KELEBEK|SIRT|Bayrak|Takım).*\)$",
                rest,
                flags=re.DOTALL | re.IGNORECASE,
            )
            if not m_reason:
                m_reason = re.search(
                    r"\([^)]*?(?:yaptığından|dokunmadan|ihlal|SW)[^)]*?\)$",
                    rest,
                    flags=re.DOTALL | re.IGNORECASE,
                )
            if not m_reason:
                m_reason = re.search(r"\(([^)]+)\)$", rest)
            if m_reason:
                reason = rest[m_reason.start():].strip("() ")
                rest = rest[:m_reason.start()].strip()

            results.append({
                "sira": None,
                "kulvar": None,
                "seri": None,
                "dogum_yili": None,
                "sporcu": rest,
                "kulup": rest if "(Tk)" in rest else None,
                "derece": None,
                "puan": None,
                "durum": status,
                "notlar": reason,
                "sayfa": page_no,
            })
        return results

    def _extract_results(
        self,
        page_lines_list: List[List[str]],
        header_info: Dict[str, Any],
    ) -> List[Dict[str, Any]]:
        results: List[Dict[str, Any]] = []
        stil_lower = (header_info.get("stil") or "").lower()
        is_relay = "bayrak" in stil_lower or "relay" in stil_lower

        for page_idx, lines in enumerate(page_lines_list):
            pno = page_idx + 1
            idx = 0
            n_lines = len(lines)

            while idx < n_lines:
                line = lines[idx]

                if self.RE_PAGE_FOOTER.match(line) or self.RE_TABLE_HEADER.match(line) or self.RE_SPLIT_LINE.match(line):
                    idx += 1
                    continue

                if pno == 1 and idx < 10 and self._is_header_or_noise(line, header_info):
                    idx += 1
                    continue

                # 1. DSQ / DNS / DNF / EXH satırları
                if self.RE_STATUS_START.match(line):
                    dsq_lines = [line]
                    idx += 1
                    while idx < n_lines:
                        nxt = lines[idx]
                        if (
                            self.RE_PAGE_FOOTER.match(nxt)
                            or self.RE_STATUS_START.match(nxt)
                            or self.RE_INT.match(nxt)
                        ):
                            break
                        dsq_lines.append(nxt)
                        idx += 1
                    results.extend(self._parse_dsq_block(" ".join(dsq_lines), pno))
                    continue

                # 2. Sıra numarası ile başlayan sonuç satırı
                if self.RE_INT.match(line):
                    sira = int(line)

                    # 2a. Bayrak (Relay) Sonucu: Sıra -> Kulvar (veya K/S) -> Derece -> Kulüp -> Takım Sporcuları
                    if is_relay and idx + 2 < n_lines:
                        nxt1 = lines[idx + 1]
                        nxt2 = lines[idx + 2]
                        if (self.RE_INT.match(nxt1) or self.RE_KS.match(nxt1)) and self.RE_TIME.match(nxt2):
                            if self.RE_KS.match(nxt1):
                                k_str, s_str = nxt1.split("/")
                                kulvar = int(k_str)
                                seri = int(s_str)
                            else:
                                kulvar = int(nxt1)
                                seri = 1
                            derece = nxt2
                            idx += 3

                            club = ""
                            if (
                                idx < n_lines
                                and not self.RE_INT.match(lines[idx])
                                and not self.RE_STATUS_START.match(lines[idx])
                                and not self.RE_PAGE_FOOTER.match(lines[idx])
                            ):
                                club = lines[idx]
                                idx += 1

                            fina_puan = None
                            if idx < n_lines and re.match(r"^\d{2,4}$", lines[idx]):
                                fina_puan = int(lines[idx])
                                idx += 1

                            swimmer_notes: List[str] = []
                            while idx < n_lines:
                                nxt = lines[idx]
                                if (
                                    self.RE_PAGE_FOOTER.match(nxt)
                                    or self.RE_STATUS_START.match(nxt)
                                    or self.RE_TABLE_HEADER.match(nxt)
                                    or self.RE_INT.match(nxt)
                                ):
                                    break
                                swimmer_notes.append(nxt)
                                idx += 1

                            results.append({
                                "sira": sira,
                                "kulvar": kulvar,
                                "seri": seri,
                                "dogum_yili": None,
                                "sporcu": club,
                                "kulup": club,
                                "derece": derece,
                                "puan": fina_puan,
                                "durum": "OK",
                                "notlar": " ".join(swimmer_notes).strip(),
                                "sayfa": pno,
                            })
                            continue

                    # 2b. Bireysel Sporcu Sonucu: Sıra -> (K/S veya Kulvar) -> (D.Yılı) -> Sporcu -> Kulüp -> [Baraj] -> Derece
                    if idx + 2 < n_lines:
                        nxt1 = lines[idx + 1]
                        nxt2 = lines[idx + 2]

                        kulvar: Optional[int] = None
                        seri: Optional[int] = None
                        d_yili: Optional[str] = None
                        prefixed_name_part: Optional[str] = None
                        cur = idx + 1

                        if self.RE_KS.match(nxt1):
                            k_str, s_str = nxt1.split("/")
                            kulvar, seri = int(k_str), int(s_str)
                            cur = idx + 2
                            if cur < n_lines:
                                if self.RE_YEAR.match(lines[cur]):
                                    d_yili = lines[cur]
                                    cur += 1
                                else:
                                    m_yp = self.RE_YEAR_PREFIX.match(lines[cur])
                                    if m_yp:
                                        d_yili = m_yp.group(1)
                                        prefixed_name_part = m_yp.group(2).strip()
                                        cur += 1
                        elif self.RE_YEAR.match(nxt1) and self.RE_KS.match(nxt2):
                            d_yili = nxt1
                            k_str, s_str = nxt2.split("/")
                            kulvar, seri = int(k_str), int(s_str)
                            cur = idx + 3
                        elif self.RE_INT.match(nxt1) and 1 <= int(nxt1) <= 10:
                            if self.RE_YEAR.match(nxt2):
                                kulvar = int(nxt1)
                                d_yili = nxt2
                                cur = idx + 3
                            else:
                                m_yp = self.RE_YEAR_PREFIX.match(nxt2)
                                if m_yp:
                                    kulvar = int(nxt1)
                                    d_yili = m_yp.group(1)
                                    prefixed_name_part = m_yp.group(2).strip()
                                    cur = idx + 3

                        if kulvar is not None:
                            # Derece satırına kadar olan satırları topla
                            mid_lines: List[str] = [prefixed_name_part] if prefixed_name_part else []
                            scan = cur
                            derece = None
                            while scan < n_lines:
                                sl = lines[scan]
                                if self.RE_TIME.match(sl):
                                    derece = sl
                                    scan += 1
                                    break
                                if (
                                    self.RE_PAGE_FOOTER.match(sl)
                                    or self.RE_STATUS_START.match(sl)
                                    or self.RE_TABLE_HEADER.match(sl)
                                ):
                                    break
                                # Yeni bir sporcu satırına geçildiğini fark edersek dur
                                if self.RE_INT.match(sl) and scan + 1 < n_lines and (
                                    self.RE_KS.match(lines[scan + 1])
                                    or (self.RE_INT.match(lines[scan + 1]) and scan + 2 < n_lines and self.RE_YEAR.match(lines[scan + 2]))
                                ):
                                    break
                                mid_lines.append(sl)
                                scan += 1

                            if derece is not None:
                                baraj_parts: List[str] = []
                                while mid_lines and "baraj" in mid_lines[-1].lower():
                                    baraj_parts.insert(0, mid_lines.pop())
                                    # Eğer "BARAJI" tek başına alt satıra taşmışsa üstündeki devam satırını da al
                                    if (
                                        baraj_parts[0].strip().lower() in ("barajı", "baraj", "baraji", "katılım barajı")
                                        and mid_lines
                                        and not any(k in mid_lines[-1].lower() for k in ("kulübü", "kulubu", "s.k", "sk", "belediyesi", "koleji", "derneği"))
                                    ):
                                        baraj_parts.insert(0, mid_lines.pop())
                                baraj = " ".join(baraj_parts).strip() or None

                                club = mid_lines.pop() if mid_lines else None
                                if club and "baraj" in club.lower():
                                    baraj = f"{baraj} {club}".strip() if baraj else club
                                    club = mid_lines.pop() if mid_lines else None
                                athlete_name = self._join_athlete_parts(mid_lines)

                                # Opsiyonel FINA puanı (dereceden sonra gelen 2-4 haneli tam sayı)
                                fina_puan = None
                                if scan < n_lines and re.match(r"^\d{2,4}$", lines[scan]) and lines[scan] != d_yili:
                                    # Sonraki satır yeni bir sporcu değilse FINA puanıdır
                                    is_next_rank = (
                                        scan + 1 < n_lines
                                        and (
                                            self.RE_KS.match(lines[scan + 1])
                                            or (self.RE_INT.match(lines[scan + 1]) and scan + 2 < n_lines and self.RE_YEAR.match(lines[scan + 2]))
                                        )
                                    )
                                    if not is_next_rank:
                                        fina_puan = int(lines[scan])
                                        scan += 1

                                # Ara zaman (split) satırlarını atla
                                while scan < n_lines and self.RE_SPLIT_LINE.match(lines[scan]):
                                    scan += 1

                                results.append({
                                    "sira": sira,
                                    "kulvar": kulvar,
                                    "seri": seri,
                                    "dogum_yili": d_yili,
                                    "sporcu": athlete_name,
                                    "kulup": club,
                                    "derece": derece,
                                    "puan": fina_puan,
                                    "durum": "OK",
                                    "notlar": baraj,
                                    "sayfa": pno,
                                })
                                idx = scan
                                continue

                idx += 1

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
