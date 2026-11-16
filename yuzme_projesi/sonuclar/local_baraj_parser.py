"""
TYF Reglaman PDF Baraj Ayrıştırıcı ve Sonuç Baraj Kontrol Modülü.

Reglaman PDF dosyalarındaki (50m Uzun Kulvar / 25m Kısa Kulvar Katılım ve
Harcırah Barajları gibi) cinsiyet ve yaş/doğum yılına göre düzenlenmiş baraj
tablolarını PyMuPDF (`fitz`) ile okuyup JSON yapısına dönüştürür.
Ardından canlı yarış sonuçlarındaki derecelerin ilgili barajı geçip geçmediğini
kontrol eder.
"""

import json
import logging
import os
import re
from datetime import datetime, timezone as dt_timezone
from typing import Any, Dict, List, Optional, Tuple

import fitz  # PyMuPDF
import requests

logger = logging.getLogger(__name__)

STIL_MAP = {
    "serbest": "Serbest",
    "sirtustu": "Sırtüstü",
    "sirt": "Sırtüstü",
    "kurbagalama": "Kurbağalama",
    "kurbaga": "Kurbağalama",
    "kelebek": "Kelebek",
    "karisik": "Karışık",
}


def _fold_tr(text: str) -> str:
    if not text:
        return ""
    replacements = str.maketrans({
        "ç": "c", "Ç": "c",
        "ğ": "g", "Ğ": "g",
        "ı": "i", "İ": "i", "I": "i",
        "ö": "o", "Ö": "o",
        "ş": "s", "Ş": "s",
        "ü": "u", "Ü": "u",
    })
    return text.translate(replacements).lower().strip()


def _parse_time_to_seconds(time_str: Optional[str]) -> Optional[float]:
    if not time_str:
        return None
    s = str(time_str).strip().replace(",", ".")
    if not s or not re.search(r"\d", s):
        return None
    # Formatlar: MM:SS.cc, SS.cc, HH:MM:SS.cc
    m_min = re.match(r"^(\d{1,2}):(\d{2}\.\d{1,2})$", s)
    if m_min:
        try:
            return round(int(m_min.group(1)) * 60 + float(m_min.group(2)), 2)
        except ValueError:
            return None
    m_sec = re.match(r"^(\d{1,3}\.\d{1,2})$", s)
    if m_sec:
        try:
            return round(float(m_sec.group(1)), 2)
        except ValueError:
            return None
    return None


def _normalize_stil(raw_stil: str) -> Optional[str]:
    folded = _fold_tr(raw_stil)
    for key, val in STIL_MAP.items():
        if key in folded:
            return val
    return None


def _parse_event_cell(cell_text: Optional[str]) -> Optional[Tuple[int, str]]:
    """Örn: '50 m\\nSerbest' -> (50, 'Serbest')"""
    if not cell_text:
        return None
    cleaned = " ".join(str(cell_text).split())
    m = re.match(r"^(\d{2,4})\s*m?\s+(.+)$", cleaned, re.IGNORECASE)
    if not m:
        return None
    mesafe = int(m.group(1))
    stil = _normalize_stil(m.group(2))
    if not stil:
        return None
    return mesafe, stil


def _parse_age_header(cell_text: Optional[str]) -> Optional[Dict[str, Any]]:
    """
    Yaş / doğum yılı başlık hücresini çözümler.
    Örnekler:
      '19+ YAŞ\\n2008+' -> yas_etiketi='19+ YAŞ', max_dogum_yili=2008, min_yas=19
      '18-17-16\\nYAŞ\\n2009\\n2010\\n2011' -> yas_etiketi='16-18 YAŞ', dogum_yillari=[2009, 2010, 2011], min_yas=16, max_yas=18
      '15 YAŞ\\n2012' -> yas_etiketi='15 YAŞ', dogum_yillari=[2012], min_yas=15, max_yas=15
    """
    if not cell_text:
        return None
    raw = " ".join(str(cell_text).split())
    if not raw:
        return None

    # 4 haneli yılları çıkar
    max_dogum_yili: Optional[int] = None
    min_dogum_yili: Optional[int] = None
    dogum_yillari: List[int] = []

    m_year_plus = re.search(r"\b((?:19|20)\d{2})\s*\+", raw)
    if m_year_plus:
        max_dogum_yili = int(m_year_plus.group(1))
    else:
        years = [int(y) for y in re.findall(r"\b((?:19|20)\d{2})\b", raw)]
        if years:
            dogum_yillari = sorted(set(years))

    # Yaş bilgilerini çıkar (4 haneli yılları çıkardıktan sonra kalan sayılar)
    raw_no_years = re.sub(r"\b(?:19|20)\d{2}\+?", "", raw)
    min_yas: Optional[int] = None
    max_yas: Optional[int] = None
    yas_etiketi = ""

    m_age_plus = re.search(r"\b(\d{1,2})\s*\+", raw_no_years)
    if m_age_plus:
        min_yas = int(m_age_plus.group(1))
        yas_etiketi = f"{min_yas}+ YAŞ"
    else:
        age_nums = [int(a) for a in re.findall(r"\b(\d{1,2})\b", raw_no_years)]
        if age_nums:
            min_yas = min(age_nums)
            max_yas = max(age_nums)
            if min_yas == max_yas:
                yas_etiketi = f"{min_yas} YAŞ"
            else:
                yas_etiketi = f"{min_yas}-{max_yas} YAŞ"

    if not yas_etiketi and dogum_yillari:
        yas_etiketi = "/".join(str(y) for y in dogum_yillari)
    elif not yas_etiketi and max_dogum_yili:
        yas_etiketi = f"{max_dogum_yili}+"

    if not dogum_yillari and max_dogum_yili is None and min_yas is None:
        return None

    return {
        "yas_etiketi": yas_etiketi,
        "dogum_yillari": dogum_yillari,
        "max_dogum_yili": max_dogum_yili,
        "min_dogum_yili": min_dogum_yili,
        "min_yas": min_yas,
        "max_yas": max_yas,
    }


def _detect_table_meta(title_text: str, page_text: str) -> Tuple[str, Optional[str], str]:
    """Başlıktan (baraj_adi, havuz, baraj_turu) bilgisini çıkarır."""
    title_folded = _fold_tr(title_text)
    page_folded = _fold_tr(page_text)

    havuz: Optional[str] = None
    for src in (title_folded, page_folded):
        if "kisa kulvar" in src or "25m" in src or "25 m" in src:
            havuz = "25m"
            break
        if "uzun kulvar" in src or "50m" in src or "50 m" in src:
            havuz = "50m"
            break

    combined_folded = f"{title_folded}\n{page_folded}"
    baraj_turu = "Baraj"
    if "harcirah" in combined_folded:
        baraj_turu = "Harcırah Barajı"
    elif "katilim" in combined_folded:
        baraj_turu = "Katılım Barajı"
    elif "milli takim" in combined_folded:
        baraj_turu = "Milli Takım Barajı"

    lines = [ln.strip() for ln in title_text.splitlines() if ln.strip()]
    baraj_adi = " - ".join(lines) if lines else baraj_turu
    return baraj_adi, havuz, baraj_turu


def _get_gemini_client_for_baraj():
    """Ortam değişkenlerinden veya .env dosyasından Gemini Client döndürür."""
    api_key = (os.environ.get("GEMINI_API_KEY") or os.environ.get("GEMINI_API_KEY_2") or "").strip().strip("'\"")
    if not api_key:
        try:
            from dotenv import load_dotenv
            base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            for candidate in (os.path.join(base_dir, ".env"), os.path.join(os.path.dirname(base_dir), ".env")):
                if os.path.exists(candidate):
                    load_dotenv(candidate)
            api_key = (os.environ.get("GEMINI_API_KEY") or os.environ.get("GEMINI_API_KEY_2") or "").strip().strip("'\"")
        except Exception:
            pass
    if not api_key:
        return None
    from google import genai
    return genai.Client(api_key=api_key)


_GEMINI_BARAJ_PROMPT = """Bu görselde Türkiye Yüzme Federasyonu (TYF) müsabaka reglamanına ait baraj tablosu varsa SADECE KATILIM BARAJLARINI JSON formatında çıkar.
(Harcırah Barajı tablosu varsa onu dahil etme; yalnızca Katılım Barajlarını çıkar. Görselde baraj tablosu yoksa {"baraj_adi": "", "barajlar": []} döndür.)

Kurallar:
- havuz: "50m" (Uzun Kulvar / 50M) veya "25m" (Kısa Kulvar / 25M). Belirtilmemişse null.
- baraj_turu: "Katılım Barajı"
- cinsiyet: "Erkek" veya "Kadın"
- yas_etiketi: ör. "11 YAŞ", "12 YAŞ", "13 YAŞ", "16-18 YAŞ", "19+ YAŞ"
- dogum_yillari: tam sayı listesi (ör. [2015] veya [2009, 2010, 2011]). Eğer "2008+" gibi açık uçluysa [] bırak ve max_dogum_yili: 2008 yaz.
- max_dogum_yili: "2008+" gibi bir üst sınır varsa tam sayı (2008), yoksa null.
- min_yas, max_yas: tam sayı veya null.
- mesafe: tam sayı (50, 100, 200, 400, 800, 1500)
- stil: Yalnızca şu 5 değerden biri: "Serbest", "Sırtüstü", "Kurbağalama", "Kelebek", "Karışık"
- sure: Görseldeki derece metni (ör. "00:32,99", "01:11,99")

Çıktı formatı:
{
  "baraj_adi": "Tablo başlığı",
  "barajlar": [
    {
      "havuz": "50m",
      "baraj_turu": "Katılım Barajı",
      "cinsiyet": "Erkek",
      "yas_etiketi": "11 YAŞ",
      "dogum_yillari": [2015],
      "max_dogum_yili": null,
      "min_yas": 11,
      "max_yas": 11,
      "mesafe": 50,
      "stil": "Serbest",
      "sure": "00:32,99"
    }
  ]
}"""


def _parse_baraj_pages_with_gemini(
    image_pages: List[bytes],
    kaynak_url: str = "",
) -> Dict[str, Any]:
    """Metin tablosu bulunamayan görsel baraj sayfalarını Gemini Vision ile ayrıştırır."""
    if not image_pages:
        return {}
    client = _get_gemini_client_for_baraj()
    if client is None:
        logger.warning("Görsel baraj sayfası tespit edildi ancak GEMINI_API_KEY tanımlı değil.")
        return {}

    from google.genai import types
    model = os.environ.get("GEMINI_MODEL", "gemini-flash-lite-latest")

    all_entries: List[Dict[str, Any]] = []
    baraj_adi = ""

    for png_bytes in image_pages:
        try:
            resp = client.models.generate_content(
                model=model,
                contents=[
                    types.Part.from_bytes(data=png_bytes, mime_type="image/png"),
                    _GEMINI_BARAJ_PROMPT,
                ],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    temperature=0.0,
                ),
            )
            raw_json = (resp.text or "").strip()
            if not raw_json:
                continue
            parsed = json.loads(raw_json)
            if not isinstance(parsed, dict):
                continue
            if not baraj_adi and parsed.get("baraj_adi"):
                baraj_adi = str(parsed["baraj_adi"]).strip()
            for item in parsed.get("barajlar") or []:
                if not isinstance(item, dict):
                    continue
                tur = str(item.get("baraj_turu") or "Katılım Barajı").strip()
                if "harcirah" in _fold_tr(tur):
                    continue
                g_fold = _fold_tr(str(item.get("cinsiyet") or ""))
                if "erkek" in g_fold:
                    cinsiyet = "Erkek"
                elif "kadin" in g_fold or "bayan" in g_fold or "kiz" in g_fold:
                    cinsiyet = "Kadın"
                else:
                    continue
                stil = _normalize_stil(str(item.get("stil") or ""))
                if not stil:
                    continue
                try:
                    mesafe = int(item.get("mesafe"))
                except (TypeError, ValueError):
                    continue
                sure_str = str(item.get("sure") or "").strip()
                sure_sn = _parse_time_to_seconds(sure_str)
                if sure_sn is None:
                    continue

                havuz_raw = _fold_tr(str(item.get("havuz") or ""))
                havuz: Optional[str] = None
                if "25" in havuz_raw or "kisa" in havuz_raw:
                    havuz = "25m"
                elif "50" in havuz_raw or "uzun" in havuz_raw:
                    havuz = "50m"

                dogum_yillari = []
                for y in item.get("dogum_yillari") or []:
                    try:
                        dogum_yillari.append(int(y))
                    except (TypeError, ValueError):
                        pass

                max_dy = item.get("max_dogum_yili")
                try:
                    max_dy = int(max_dy) if max_dy is not None else None
                except (TypeError, ValueError):
                    max_dy = None

                min_yas = item.get("min_yas")
                max_yas = item.get("max_yas")
                try:
                    min_yas = int(min_yas) if min_yas is not None else None
                except (TypeError, ValueError):
                    min_yas = None
                try:
                    max_yas = int(max_yas) if max_yas is not None else None
                except (TypeError, ValueError):
                    max_yas = None

                all_entries.append({
                    "havuz": havuz,
                    "baraj_turu": "Katılım Barajı" if "katilim" in _fold_tr(tur) else tur,
                    "cinsiyet": cinsiyet,
                    "yas_etiketi": str(item.get("yas_etiketi") or "").strip(),
                    "dogum_yillari": sorted(set(dogum_yillari)),
                    "max_dogum_yili": max_dy,
                    "min_yas": min_yas,
                    "max_yas": max_yas,
                    "mesafe": mesafe,
                    "stil": stil,
                    "sure": sure_str,
                    "sure_saniye": sure_sn,
                })
        except Exception as exc:
            logger.warning(f"Gemini görsel baraj ayrıştırma hatası: {exc}")

    if not all_entries:
        return {}

    return {
        "baraj_adi": baraj_adi or "Reglaman Barajları (Görsel)",
        "kaynak_url": kaynak_url or "",
        "guncellenme": datetime.now(dt_timezone.utc).isoformat(),
        "barajlar": all_entries,
    }


def parse_baraj_pdf_bytes(
    pdf_bytes: bytes,
    kaynak_url: str = "",
    use_gemini_fallback: bool = True,
) -> Dict[str, Any]:
    """
    PDF baytlarından baraj tablolarını ayrıştırır ve standart JSON sözlüğü döndürür.
    Metin tabanlı tablo bulunamazsa görsel sayfalar için Gemini Vision fallback kullanır.
    Baraj tablosu bulunamazsa boş sözlük `{}` döner.
    """
    if not pdf_bytes:
        return {}
    try:
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    except Exception as exc:
        logger.warning(f"Baraj PDF açılamadı: {exc}")
        return {}
    entries: List[Dict[str, Any]] = []
    baraj_adi_candidates: List[str] = []
    candidate_image_pages: List[bytes] = []

    try:
        for page in doc:
            page_text = page.get_text("text") or ""
            has_baraj_text = "baraj" in _fold_tr(page_text)
            is_image_page = len(page_text.strip()) < 150 and len(page.get_images()) > 0
            if is_image_page or has_baraj_text:
                # Görsel fallback gerekirse kullanılmak üzere aday sayfayı hazırla
                if is_image_page:
                    candidate_image_pages.append(page.get_pixmap(dpi=200).tobytes("png"))

            if not has_baraj_text:
                continue

            tabs = page.find_tables()
            if not tabs or not tabs.tables:
                continue

            for table in tabs.tables:
                rows = table.extract()
                if not rows or len(rows) < 4:
                    continue

                # Başlık, cinsiyet ve yaş satırlarını bul
                gender_row_idx: Optional[int] = None
                age_row_idx: Optional[int] = None
                title_lines: List[str] = []

                for idx, row in enumerate(rows[:6]):
                    row_joined = " ".join(str(c) for c in row if c)
                    row_folded = _fold_tr(row_joined)
                    if gender_row_idx is None and ("erkek" in row_folded or "kadin" in row_folded or "bayan" in row_folded):
                        # Bu satır cinsiyet satırı mı yoksa hem başlık hem cinsiyet mi?
                        non_empty = [c for c in row if c and str(c).strip()]
                        if len(non_empty) >= 2:
                            gender_row_idx = idx
                            continue
                    if gender_row_idx is not None and age_row_idx is None:
                        if "yas" in row_folded or re.search(r"\b(?:19|20)\d{2}\b", row_folded):
                            age_row_idx = idx
                            break
                    if gender_row_idx is None:
                        title_lines.extend(str(c).strip() for c in row if c and str(c).strip())

                if gender_row_idx is None or age_row_idx is None:
                    continue

                title_text = "\n".join(title_lines)
                baraj_adi, havuz, baraj_turu = _detect_table_meta(title_text, page_text)
                if baraj_turu == "Harcırah Barajı":
                    continue
                if baraj_adi and baraj_adi not in baraj_adi_candidates:
                    baraj_adi_candidates.append(baraj_adi)

                gender_row = rows[gender_row_idx]
                age_row = rows[age_row_idx]
                num_cols = len(age_row)

                # Sütunlara göre cinsiyet haritası çıkar (merged hücrelerde None'ları ileri doldur)
                col_gender: Dict[int, str] = {}
                event_col_idx: Optional[int] = None
                current_gender: Optional[str] = None

                for c_idx in range(num_cols):
                    g_cell = gender_row[c_idx] if c_idx < len(gender_row) else None
                    g_fold = _fold_tr(str(g_cell or ""))
                    if "erkek" in g_fold and "kadin" in g_fold:
                        # Orta branş sütunu ('ERKEK-KADIN 50M')
                        event_col_idx = c_idx
                        current_gender = None
                        continue
                    elif "erkek" in g_fold:
                        current_gender = "Erkek"
                    elif "kadin" in g_fold or "bayan" in g_fold:
                        current_gender = "Kadın"

                    if current_gender:
                        col_gender[c_idx] = current_gender

                # Eğer cinsiyet satırından orta sütun bulunamadıysa yaş satırında None olan sütunu bul
                if event_col_idx is None:
                    for c_idx in range(num_cols):
                        if age_row[c_idx] is None:
                            event_col_idx = c_idx
                            break

                # Her veri sütunu için yaş bilgisini çözümle
                col_age: Dict[int, Dict[str, Any]] = {}
                for c_idx in range(num_cols):
                    if c_idx == event_col_idx or c_idx not in col_gender:
                        continue
                    age_meta = _parse_age_header(age_row[c_idx])
                    if age_meta:
                        col_age[c_idx] = age_meta

                if not col_age:
                    continue

                # Veri satırlarını oku
                for r_idx in range(age_row_idx + 1, len(rows)):
                    row = rows[r_idx]
                    if len(row) < num_cols:
                        continue

                    # Branş hücresini bul
                    ev_info: Optional[Tuple[int, str]] = None
                    if event_col_idx is not None:
                        ev_info = _parse_event_cell(row[event_col_idx])
                    if ev_info is None:
                        for c_idx, cell in enumerate(row):
                            if c_idx not in col_age:
                                ev_info = _parse_event_cell(cell)
                                if ev_info:
                                    break
                    if not ev_info:
                        continue

                    mesafe, stil = ev_info
                    for c_idx, age_meta in col_age.items():
                        sure_raw = row[c_idx]
                        sure_sn = _parse_time_to_seconds(sure_raw)
                        if sure_sn is None:
                            continue

                        sure_str = " ".join(str(sure_raw).split())
                        entries.append({
                            "havuz": havuz,
                            "baraj_turu": baraj_turu,
                            "cinsiyet": col_gender[c_idx],
                            "yas_etiketi": age_meta["yas_etiketi"],
                            "dogum_yillari": age_meta["dogum_yillari"],
                            "max_dogum_yili": age_meta["max_dogum_yili"],
                            "min_yas": age_meta["min_yas"],
                            "max_yas": age_meta["max_yas"],
                            "mesafe": mesafe,
                            "stil": stil,
                            "sure": sure_str,
                            "sure_saniye": sure_sn,
                        })
    finally:
        doc.close()

    if not entries:
        if use_gemini_fallback and candidate_image_pages:
            return _parse_baraj_pages_with_gemini(candidate_image_pages, kaynak_url=kaynak_url)
        return {}

    return {
        "baraj_adi": baraj_adi_candidates[0] if baraj_adi_candidates else "Reglaman Barajları",
        "kaynak_url": kaynak_url or "",
        "guncellenme": datetime.now(dt_timezone.utc).isoformat(),
        "barajlar": entries,
    }


def fetch_and_parse_reglaman_barajlar(reglaman_url: str, timeout: int = 15) -> Dict[str, Any]:
    """Reglaman PDF URL'sini indirip barajları ayrıştırır."""
    if not reglaman_url:
        return {}
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    resp = requests.get(reglaman_url, headers=headers, timeout=timeout, verify=False)
    if resp.status_code != 200:
        raise RuntimeError(f"Reglaman PDF indirilemedi (HTTP {resp.status_code})")
    return parse_baraj_pdf_bytes(resp.content, kaynak_url=reglaman_url)


def evaluate_baraj_for_result(
    barajlar_data: Optional[Dict[str, Any]],
    *,
    cinsiyet: Optional[str],
    mesafe: Optional[int],
    stil: Optional[str],
    derece_saniye: Optional[float],
    birth_year: Optional[int] = None,
    yas: Optional[int] = None,
    course: Optional[str] = None,
) -> Optional[str]:
    """
    Bir yarış sonucunun kayıtlı barajları geçip geçmediğini kontrol eder.
    Geçilen en yüksek seviye barajın adını (ör. 'Harcırah Barajı' veya 'Katılım Barajı')
    döndürür; geçilmediyse veya eşleşen baraj yoksa None döndürür.
    """
    if not barajlar_data or not isinstance(barajlar_data, dict):
        return None
    rules = barajlar_data.get("barajlar")
    if not rules or not isinstance(rules, list):
        return None
    if derece_saniye is None or derece_saniye <= 0:
        return None
    if not cinsiyet or not mesafe or not stil:
        return None

    target_gender = _fold_tr(cinsiyet)
    if "erkek" in target_gender:
        target_gender = "erkek"
    elif "kadin" in target_gender or "bayan" in target_gender or "kiz" in target_gender:
        target_gender = "kadin"
    else:
        return None

    target_stil = _normalize_stil(stil)
    if not target_stil:
        return None

    target_havuz: Optional[str] = None
    if course:
        c_up = str(course).upper()
        if c_up in ("LCM", "50M", "50"):
            target_havuz = "50m"
        elif c_up in ("SCM", "25M", "25"):
            target_havuz = "25m"

    passed: List[Tuple[float, str]] = []
    for rule in rules:
        r_havuz = rule.get("havuz")
        if target_havuz and r_havuz and r_havuz != target_havuz:
            continue

        r_gender = _fold_tr(str(rule.get("cinsiyet") or ""))
        if r_gender != target_gender:
            continue

        if rule.get("mesafe") != int(mesafe):
            continue

        if rule.get("stil") != target_stil:
            continue

        # Yaş / Doğum yılı eşleşmesi
        dogum_yillari = rule.get("dogum_yillari") or []
        max_dogum_yili = rule.get("max_dogum_yili")
        min_yas = rule.get("min_yas")
        max_yas = rule.get("max_yas")

        age_match = False
        if birth_year is not None:
            if dogum_yillari and birth_year in dogum_yillari:
                age_match = True
            elif max_dogum_yili is not None and birth_year <= max_dogum_yili:
                age_match = True
        elif yas is not None:
            if (min_yas is None or yas >= min_yas) and (max_yas is None or yas <= max_yas):
                age_match = True

        if not age_match:
            continue

        sure_sn = rule.get("sure_saniye")
        if sure_sn is not None and derece_saniye <= float(sure_sn):
            passed.append((float(sure_sn), str(rule.get("baraj_turu") or "Barajı Geçti")))

    if not passed:
        return None

    # Birden fazla baraj geçildiyse Katılım Barajı'nı önceliklendir
    for _, tur in passed:
        if "katılım" in tur.lower() or "katilim" in tur.lower():
            return tur[:50]
    passed.sort(key=lambda x: x[0])
    return passed[0][1][:50]
