# -*- coding: utf-8 -*-
"""
TYF Faaliyet Takvimi, Reglaman ve Milli Takım Kriterleri Günlük Tarama Modülü.

- Ana faaliyet takvimi sayfasını ve Milli Takım Seçme Kriterleri sayfasını tarar.
- PDF belgelerini SHA-256 hash ile kontrol eder; yalnız yeni/değişenleri işler.
- Belgeleri Django MEDIA_ROOT altında yerel olarak saklar.
- Gemini ile belgeyi sınıflandırır, yaş/tarih/yer/özet bilgilerini çıkarır.
- Takvim ve Reglamanları `Event` tablosuna (yaş grubu ve havuz bilgisiyle) işler.
- Baraj tablolarını `local_baraj_parser` (+ Gemini fallback) ile okuyup `BarajKurali` tablosuna kaydeder.
"""

import hashlib
import json
import logging
import os
import re
import time
from datetime import datetime, timezone as dt_timezone
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urljoin, urlparse

import fitz  # PyMuPDF
import requests
from bs4 import BeautifulSoup
from django.core.files.base import ContentFile
from django.db import transaction
from django.utils import timezone

from sonuclar.local_baraj_parser import parse_baraj_pdf_bytes
from sonuclar.models import BarajKurali, Event, TyfBelge

logger = logging.getLogger(__name__)

DEFAULT_TAKVIM_URL = "https://www.tyf.gov.tr/haber/2026-2027-sezonu-yuzme-faaliyet-takvimi-yayinda.html"

TURKISH_MONTHS = {
    "ocak": 1, "subat": 2, "şubat": 2, "mart": 3, "nisan": 4,
    "mayis": 5, "mayıs": 5, "haziran": 6, "temmuz": 7,
    "agustos": 8, "ağustos": 8, "eylul": 9, "eylül": 9,
    "ekim": 10, "kasim": 11, "kasım": 11, "aralik": 12, "aralık": 12,
}

GEMINI_DOC_PROMPT = """Sen Türkiye Yüzme Federasyonu (TYF) belgelerini analiz eden bir asistansın.
Verilen PDF metnini incele ve yalnızca aşağıdaki JSON şemasında yanıt ver:
{
  "belge_turu": "TAKVIM | REGLAMAN | MILLI_TAKIM | DUYURU",
  "baslik": "Belgenin tam resmi adı",
  "tarih_metni": "Belgedeki tarih aralığı (ör. 26-29 Kasım 2026)",
  "baslangic_tarihi": "YYYY-MM-DD veya null",
  "bitis_tarihi": "YYYY-MM-DD veya null",
  "il": "Sadece il/şehir adı (ör. Ankara, Antalya, Edirne, İller veya Pekin/Çin) veya null",
  "yer_havuz": "Varsa tesis/havuz adı (ör. Keçiören Etlik Olimpik Yüzme Havuzu) veya null",
  "sehir_yer": "İl ve varsa tesis birleşimi (ör. Ankara - Keçiören Etlik Olimpik Yüzme Havuzu) veya null",
  "havuz": "25m | 50m | 25m/50m | null",
  "yas_grubu": "Katılım yaşı / doğum yılları özeti (ör. 11-12 Yaş (2015-2014)) veya null",
  "min_yas": null,
  "max_yas": null,
  "baraj_var_mi": true,
  "baraj_gecerlilik_metni": "Reglamandaki 'Baraj Geçerlilik Tarihi' metni (ör. 01 Eylül 2025 - 20 Aralık 2026) veya null",
  "baraj_gecerlilik_baslangic": "Baraj geçerlilik başlangıç tarihi (YYYY-MM-DD) veya null",
  "baraj_gecerlilik_bitis": "Baraj geçerlilik bitiş tarihi (YYYY-MM-DD) veya null",
  "onemli_notlar": ["Son liste bildirim tarihi", "Max bireysel yarış sayısı", "Diğer kritik kural"],
  "haber_ozeti": "Mobil uygulama haber bandında gösterilecek 2-3 cümlelik net, bilgilendirici Türkçe özet."
}
Not: min_yas ve max_yas tam sayı (ör. 11, 12) veya açık uçlu ise biri null olabilir."""


def _fold_tr(text: str) -> str:
    if not text:
        return ""
    return text.translate(str.maketrans({
        "ç": "c", "Ç": "c", "ğ": "g", "Ğ": "g",
        "ı": "i", "İ": "i", "I": "i", "ö": "o", "Ö": "o",
        "ş": "s", "Ş": "s", "ü": "u", "Ü": "u",
    })).lower().strip()


def _extract_min_max_age(text: Optional[str]) -> Tuple[Optional[int], Optional[int]]:
    if not text:
        return None, None
    cleaned = re.sub(r"\b(?:19|20)\d{2}\+?", "", str(text))
    m_plus = re.search(r"(?<!\d)(\d{1,2})\s*\+", cleaned)
    nums = [int(x) for x in re.findall(r"(?<!\d)(\d{1,2})(?!\d)", cleaned) if 4 <= int(x) <= 99]
    if m_plus and not nums:
        return int(m_plus.group(1)), None
    if nums:
        lo, hi = min(nums), max(nums)
        if m_plus:
            return lo, None
        return lo, hi
    return None, None


def parse_turkish_date_range(date_text: str) -> Tuple[Optional[str], Optional[str]]:
    """
    Örnekler:
      '1 EKİM - 31 ARALIK 2026' -> ('2026-10-01', '2026-12-31')
      '26-29 KASIM 2026' -> ('2026-11-26', '2026-11-29')
      '28 ŞUBAT - 2 MART 2027' -> ('2027-02-28', '2027-03-02')
    """
    if not date_text:
        return None, None
    s = " ".join(str(date_text).replace("–", "-").replace("—", "-").split())
    folded = _fold_tr(s)

    year_matches = re.findall(r"\b(20\d{2})\b", folded)
    default_year = int(year_matches[-1]) if year_matches else None
    if not default_year:
        return None, None

    # '26-29 kasim 2026'
    m_same_month = re.search(
        r"\b(\d{1,2})\s*-\s*(\d{1,2})\s+([a-z]+)\s+(20\d{2})\b", folded
    )
    if m_same_month:
        d1, d2, mon_str, yr = int(m_same_month.group(1)), int(m_same_month.group(2)), m_same_month.group(3), int(m_same_month.group(4))
        mon = TURKISH_MONTHS.get(mon_str)
        if mon:
            try:
                return f"{yr:04d}-{mon:02d}-{d1:02d}", f"{yr:04d}-{mon:02d}-{d2:02d}"
            except ValueError:
                pass

    # '1 ekim - 31 aralik 2026' veya '28 aralik 2026 - 2 ocak 2027'
    m_two = re.search(
        r"\b(\d{1,2})\s+([a-z]+)(?:\s+(20\d{2}))?\s*-\s*(\d{1,2})\s+([a-z]+)\s+(20\d{2})\b",
        folded,
    )
    if m_two:
        d1, mon1_s, yr1_s, d2, mon2_s, yr2_s = m_two.groups()
        mon1 = TURKISH_MONTHS.get(mon1_s)
        mon2 = TURKISH_MONTHS.get(mon2_s)
        yr2 = int(yr2_s)
        yr1 = int(yr1_s) if yr1_s else (yr2 - 1 if (mon1 and mon2 and mon1 > mon2) else yr2)
        if mon1 and mon2:
            return f"{yr1:04d}-{mon1:02d}-{int(d1):02d}", f"{yr2:04d}-{mon2:02d}-{int(d2):02d}"

    # Tek gün: '15 kasim 2026'
    m_single = re.search(r"\b(\d{1,2})\s+([a-z]+)\s+(20\d{2})\b", folded)
    if m_single:
        d1, mon_s, yr = int(m_single.group(1)), m_single.group(2), int(m_single.group(3))
        mon = TURKISH_MONTHS.get(mon_s)
        if mon:
            iso = f"{yr:04d}-{mon:02d}-{d1:02d}"
            return iso, iso

    return None, None


def _get_gemini_client():
    api_key = (os.environ.get("GEMINI_API_KEY") or os.environ.get("GEMINI_API_KEY_2") or "").strip().strip("'\"")
    if not api_key:
        try:
            from dotenv import load_dotenv
            base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            for cand in (os.path.join(base_dir, ".env"), os.path.join(os.path.dirname(base_dir), ".env")):
                if os.path.exists(cand):
                    load_dotenv(cand, override=False)
            api_key = (os.environ.get("GEMINI_API_KEY") or os.environ.get("GEMINI_API_KEY_2") or "").strip().strip("'\"")
        except Exception:
            pass
    if not api_key:
        return None
    from google import genai
    return genai.Client(api_key=api_key)


def _extract_revizyon(link_text: str, url: str) -> Optional[str]:
    m = re.search(r"(Revize\s*[\d.\-]+)", link_text, re.IGNORECASE)
    if m:
        return m.group(1).strip()
    m_url = re.search(r"(Revize[-_]*[\d.\-]+)", url, re.IGNORECASE)
    if m_url:
        return m_url.group(1).replace("-", " ").strip()
    return None


def discover_tyf_calendar_documents(
    takvim_url: str = DEFAULT_TAKVIM_URL,
    include_milli_takim: bool = True,
    timeout: int = 20,
) -> List[Dict[str, str]]:
    """
    Ana takvim sayfasındaki (ve istenirse Milli Takım Kriterleri alt sayfasındaki)
    güncel sezon PDF linklerini döndürür.
    """
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    resp = requests.get(takvim_url, headers=headers, timeout=timeout)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")

    anchor = soup.find("a", href=lambda h: h and ("faaliyet-takvimi" in h.lower() or "regleman" in h.lower() or ".pdf" in h.lower()))
    container = anchor.find_parent(["div", "article", "section"]) if anchor else soup.body
    while container and len(container.get_text(strip=True)) < 200 and container.parent:
        container = container.find_parent(["div", "article", "section"]) or container

    docs: List[Dict[str, str]] = []
    seen_urls = set()
    milli_takim_page_url: Optional[str] = None

    for a in (container or soup).find_all("a", href=True):
        href = urljoin(takvim_url, a["href"].strip())
        txt = " ".join(a.get_text(" ", strip=True).split())
        txt_fold = _fold_tr(txt)

        if "milli-takim-secme-ve-secilme-kriterleri" in href.lower():
            milli_takim_page_url = href
            continue

        if ".pdf" not in href.lower():
            continue

        # Geçmiş sezonları ve ilgisiz dilekçeleri hariç tut
        if any(old in txt for old in ("2025-2026", "2024-2025", "2023-2024", "2022-2023", "2021-2022", "2020-2021")):
            continue
        if "vize-odeme-iptal" in href.lower():
            continue

        if href not in seen_urls:
            seen_urls.add(href)
            docs.append({
                "kaynak_sayfa": takvim_url,
                "kaynak_url": href,
                "link_baslik": txt,
                "revizyon_etiketi": _extract_revizyon(txt, href) or "",
                "on_tur": "TAKVIM" if "faaliyet-takvimi" in href.lower() or "faaliyet takvimi" in txt_fold else "REGLAMAN",
            })

    if include_milli_takim and milli_takim_page_url:
        try:
            mr = requests.get(milli_takim_page_url, headers=headers, timeout=timeout)
            mr.raise_for_status()
            msoup = BeautifulSoup(mr.text, "html.parser")
            for a in msoup.find_all("a", href=True):
                href = urljoin(milli_takim_page_url, a["href"].strip())
                txt = " ".join(a.get_text(" ", strip=True).split())
                if ".pdf" not in href.lower():
                    continue
                if "2027" not in txt and "2027" not in href:
                    continue
                if href not in seen_urls:
                    seen_urls.add(href)
                    docs.append({
                        "kaynak_sayfa": milli_takim_page_url,
                        "kaynak_url": href,
                        "link_baslik": txt,
                        "revizyon_etiketi": _extract_revizyon(txt, href) or "",
                        "on_tur": "MILLI_TAKIM",
                    })
        except Exception as exc:
            logger.warning(f"Milli Takım Kriterleri sayfası taranamadı: {exc}")

    return docs


def analyze_pdf_with_gemini(pdf_bytes: bytes, fallback_title: str = "") -> Dict[str, Any]:
    client = _get_gemini_client()
    if client is None:
        return {}

    from google.genai import types
    model = os.environ.get("GEMINI_MODEL", "gemini-flash-lite-latest")

    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    try:
        full_text = "\n".join(f"--- SAYFA {i + 1} ---\n{p.get_text('text')}" for i, p in enumerate(doc))
    finally:
        doc.close()

    if not full_text.strip():
        return {}

    for attempt in range(3):
        try:
            resp = client.models.generate_content(
                model=model,
                contents=[GEMINI_DOC_PROMPT, f"BELGE BAĞLANTI BAŞLIĞI: {fallback_title}\n\nPDF METNİ:\n{full_text[:18000]}"],
                config=types.GenerateContentConfig(response_mime_type="application/json", temperature=0.0),
            )
            data = json.loads((resp.text or "").strip())
            return data if isinstance(data, dict) else {}
        except Exception as exc:
            err = str(exc)
            if any(tok in err for tok in ("503", "UNAVAILABLE", "429", "RESOURCE_EXHAUSTED")) and attempt < 2:
                time.sleep(2 * (attempt + 1))
                continue
            logger.warning(f"Gemini belge analiz hatası ({fallback_title}): {exc}")
            return {}
    return {}


def _normalize_havuz(raw: Optional[str]) -> Optional[str]:
    if not raw:
        return None
    s = _fold_tr(str(raw))
    has_25 = "25" in s or "kisa" in s
    has_50 = "50" in s or "uzun" in s
    if has_25 and has_50:
        return "25m/50m"
    if has_25:
        return "25m"
    if has_50:
        return "50m"
    return None


def _upsert_event(
    *,
    musabaka_adi: str,
    sehir: Optional[str] = None,
    tarih_ham: Optional[str] = None,
    baslangic: Optional[str] = None,
    bitis: Optional[str] = None,
    kaynak_turu: str = "TYF_TAKVIM",
    yas_grubu: Optional[str] = None,
    min_yas: Optional[int] = None,
    max_yas: Optional[int] = None,
    havuz: Optional[str] = None,
) -> Event:
    """
    Aynı isim + başlangıç tarihli müsabaka varsa günceller (sonuç istatistiklerini bozmadan),
    yoksa yeni `Event` oluşturur.
    """
    name_clean = " ".join(musabaka_adi.split())[:500]
    qs = Event.objects.filter(musabaka_adi__iexact=name_clean)
    if baslangic:
        qs_exact = qs.filter(yaris_tarihi_baslangic=baslangic)
        ev = qs_exact.first() or qs.filter(yaris_tarihi_baslangic__isnull=True).first()
    else:
        ev = qs.first()

    if ev is None:
        return Event.objects.create(
            musabaka_adi=name_clean,
            sehir=(sehir or "")[:100] or None,
            yaris_tarihi_ham=(tarih_ham or "")[:100] or None,
            yaris_tarihi_baslangic=baslangic,
            yaris_tarihi_bitis=bitis,
            kaynak_turu=kaynak_turu,
            yas_grubu=(yas_grubu or "")[:255] or None,
            min_yas=min_yas,
            max_yas=max_yas,
            havuz=havuz,
        )

    changed = False
    updates = {
        "sehir": (sehir or "")[:100] or None,
        "yaris_tarihi_ham": (tarih_ham or "")[:100] or None,
        "yaris_tarihi_baslangic": baslangic,
        "yaris_tarihi_bitis": bitis,
        "yas_grubu": (yas_grubu or "")[:255] or None,
        "min_yas": min_yas,
        "max_yas": max_yas,
        "havuz": havuz,
    }
    for field, val in updates.items():
        if val is not None and getattr(ev, field) != val:
            setattr(ev, field, val)
            changed = True
    if not ev.kaynak_turu:
        ev.kaynak_turu = kaynak_turu
        changed = True
    if changed:
        ev.save()
    return ev


def _import_takvim_pdf_events(pdf_bytes: bytes) -> int:
    """Faaliyet Takvimi PDF tablosundaki satırları `Event` tablosuna aktarır."""
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    count = 0
    try:
        for page in doc:
            tabs = page.find_tables()
            if not tabs or not tabs.tables:
                continue
            for table in tabs.tables:
                for row in table.extract():
                    cells = [" ".join(str(c).split()) if c else "" for c in row]
                    if not any(cells):
                        continue
                    joined_fold = _fold_tr(" ".join(cells))
                    if "musabaka" in joined_fold and "tarih" in joined_fold:
                        continue
                    if "faaliyet takvimi" in joined_fold:
                        continue

                    # Sütunlar: [TARİH(0 veya 0+1), MÜSABAKA ADI, 25/50M, KATEGORİ, YER]
                    non_empty = [c for c in cells if c]
                    if len(non_empty) < 3:
                        continue

                    # PyMuPDF bazen ilk sütunu 2 parçaya böler: ['1EK', 'İM - 31 ARALIK 2026', ...]
                    if len(cells) >= 6 and cells[0] and cells[1] and not re.search(r"20\d{2}", cells[0]) and re.search(r"20\d{2}", cells[1]):
                        tarih_ham = f"{cells[0]}{cells[1]}".strip()
                        rest = cells[2:]
                    else:
                        tarih_ham = cells[0] or cells[1]
                        rest = cells[1:] if cells[0] else cells[2:]

                    musabaka_adi = rest[0] if len(rest) > 0 else ""
                    havuz_raw = rest[1] if len(rest) > 1 else ""
                    kategori = rest[2] if len(rest) > 2 else ""
                    yer = rest[3] if len(rest) > 3 else ""

                    if not musabaka_adi or len(musabaka_adi) < 4:
                        continue

                    baslangic, bitis = parse_turkish_date_range(tarih_ham)
                    min_yas, max_yas = _extract_min_max_age(kategori)
                    _upsert_event(
                        musabaka_adi=musabaka_adi,
                        sehir=yer or None,
                        tarih_ham=tarih_ham,
                        baslangic=baslangic,
                        bitis=bitis,
                        kaynak_turu="TYF_TAKVIM",
                        yas_grubu=kategori or None,
                        min_yas=min_yas,
                        max_yas=max_yas,
                        havuz=_normalize_havuz(havuz_raw),
                    )
                    count += 1
    finally:
        doc.close()
    return count


def sync_tyf_calendar(
    takvim_url: str = DEFAULT_TAKVIM_URL,
    include_milli_takim: bool = True,
    force: bool = False,
    skip_gemini: bool = False,
) -> Dict[str, Any]:
    """Tüm sayfayı tarar; yeni/değişen belgeleri indirip işler."""
    docs = discover_tyf_calendar_documents(
        takvim_url=takvim_url,
        include_milli_takim=include_milli_takim,
    )
    stats = {
        "discovered": len(docs),
        "processed": 0,
        "skipped_unchanged": 0,
        "takvim_events": 0,
        "baraj_rules": 0,
        "errors": [],
    }
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}

    for item in docs:
        url = item["kaynak_url"]
        try:
            resp = requests.get(url, headers=headers, timeout=30)
            resp.raise_for_status()
            pdf_bytes = resp.content
            content_hash = hashlib.sha256(pdf_bytes).hexdigest()
            etag = resp.headers.get("ETag", "")[:150]
            last_mod = resp.headers.get("Last-Modified", "")[:100]

            belge = TyfBelge.objects.filter(kaynak_url=url).first()
            if (
                belge is not None
                and not force
                and belge.content_hash == content_hash
                and belge.yerel_dosya
            ):
                belge.son_kontrol_tarihi = timezone.now()
                belge.save(update_fields=["son_kontrol_tarihi"])
                stats["skipped_unchanged"] += 1
                continue

            gdata = {} if skip_gemini else analyze_pdf_with_gemini(pdf_bytes, fallback_title=item["link_baslik"])
            belge_turu = gdata.get("belge_turu") or item["on_tur"]
            if belge_turu not in ("TAKVIM", "REGLAMAN", "MILLI_TAKIM", "DUYURU"):
                belge_turu = item["on_tur"]

            baslik = (gdata.get("baslik") or item["link_baslik"] or os.path.basename(urlparse(url).path))[:500]
            yas_grubu = gdata.get("yas_grubu")
            min_yas = gdata.get("min_yas")
            max_yas = gdata.get("max_yas")
            if min_yas is None and max_yas is None and yas_grubu:
                min_yas, max_yas = _extract_min_max_age(yas_grubu)

            havuz = _normalize_havuz(gdata.get("havuz"))
            baslangic = gdata.get("baslangic_tarihi")
            bitis = gdata.get("bitis_tarihi")
            tarih_metni = gdata.get("tarih_metni")
            il_adi = (gdata.get("il") or "").strip()
            yer_havuz = (gdata.get("yer_havuz") or "").strip()
            sehir_yer = (gdata.get("sehir_yer") or "").strip()
            if not sehir_yer and (il_adi or yer_havuz):
                sehir_yer = " - ".join(x for x in (il_adi, yer_havuz) if x)

            if not baslangic:
                baslangic, bitis = parse_turkish_date_range(item["link_baslik"])

            event_obj: Optional[Event] = None
            if belge_turu == "REGLAMAN":
                event_obj = _upsert_event(
                    musabaka_adi=baslik,
                    sehir=il_adi or sehir_yer or None,
                    tarih_ham=tarih_metni,
                    baslangic=baslangic,
                    bitis=bitis,
                    kaynak_turu="TYF_REGLAMAN",
                    yas_grubu=yas_grubu,
                    min_yas=min_yas,
                    max_yas=max_yas,
                    havuz=havuz,
                )

            with transaction.atomic():
                if belge is None:
                    belge = TyfBelge(kaynak_url=url)
                belge.belge_turu = belge_turu
                belge.baslik = baslik
                belge.revizyon_etiketi = item["revizyon_etiketi"] or None
                belge.kaynak_sayfa = item["kaynak_sayfa"]
                belge.tarih_metni = (tarih_metni or "")[:150] or None
                belge.baslangic_tarihi = baslangic
                belge.bitis_tarihi = bitis
                belge.sehir_yer = (sehir_yer or "")[:200] or None
                belge.havuz = havuz
                belge.yas_grubu = (yas_grubu or "")[:255] or None
                belge.min_yas = min_yas
                belge.max_yas = max_yas
                belge.ozet = gdata.get("haber_ozeti") or item["link_baslik"]
                belge.onemli_notlar = gdata.get("onemli_notlar") or []
                belge.baraj_gecerlilik_metni = (gdata.get("baraj_gecerlilik_metni") or "")[:150] or None
                belge.baraj_gecerlilik_baslangic = (gdata.get("baraj_gecerlilik_baslangic") or "")[:20] or None
                belge.baraj_gecerlilik_bitis = (gdata.get("baraj_gecerlilik_bitis") or "")[:20] or None
                belge.gemini_json = gdata
                belge.event = event_obj
                belge.etag = etag or None
                belge.last_modified = last_mod or None
                belge.content_hash = content_hash
                belge.son_kontrol_tarihi = timezone.now()

                filename = os.path.basename(urlparse(url).path) or f"belge_{content_hash[:8]}.pdf"
                belge.yerel_dosya.save(filename, ContentFile(pdf_bytes), save=False)
                belge.save()

                if belge_turu == "TAKVIM":
                    stats["takvim_events"] += _import_takvim_pdf_events(pdf_bytes)

                # Baraj ayrıştırma
                baraj_res = parse_baraj_pdf_bytes(
                    pdf_bytes,
                    kaynak_url=url,
                    use_gemini_fallback=(not skip_gemini),
                    include_harcirah=True,
                )
                baraj_entries = baraj_res.get("barajlar") or []
                belge.baraj_kurallari.all().delete()
                if baraj_entries:
                    baraj_adi = (baraj_res.get("baraj_adi") or baslik)[:300]
                    objs = []
                    for b in baraj_entries:
                        sure_sn = float(b["sure_saniye"])
                        objs.append(BarajKurali(
                            belge=belge,
                            event=event_obj,
                            baraj_adi=baraj_adi,
                            baraj_turu=b.get("baraj_turu") or "Katılım Barajı",
                            havuz=b.get("havuz"),
                            cinsiyet=b["cinsiyet"],
                            yas_etiketi=b.get("yas_etiketi") or "",
                            dogum_yillari=b.get("dogum_yillari") or [],
                            max_dogum_yili=b.get("max_dogum_yili"),
                            min_yas=b.get("min_yas"),
                            max_yas=b.get("max_yas"),
                            mesafe=int(b["mesafe"]),
                            stil=b["stil"],
                            sure=b["sure"],
                            sure_saniye=sure_sn,
                            sure_cs=int(round(sure_sn * 100)),
                        ))
                    BarajKurali.objects.bulk_create(objs)
                    stats["baraj_rules"] += len(objs)

            stats["processed"] += 1
        except Exception as exc:
            logger.exception(f"Belge işlenirken hata ({url}): {exc}")
            stats["errors"].append(f"{url}: {exc}")

    return stats
