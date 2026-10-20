"""
src/parse_tyf_archive.py
Sorumluluk: output/txt/tyf_arsiv/ dizinindeki 297 adet TYF yarış metin dosyasındaki
tüm bireysel yüzücü sonuçlarını ve diskalifiye/yarış terk kayıtlarını ayrıştırmak,
zaman kontrollerini ve temizlemeleri uygulayarak CSV çıktılarını üretmek.
"""

from __future__ import annotations

import csv
import glob
import os
import re
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from typing import List, Dict, Any, Optional, Tuple

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.canonicalize_athletes import standardize_swimmer_name

PAGE_RE = re.compile(r"^===\s*SAYFA\s*(\d+)\s*/\s*(\d+)\s*===", re.I)
RACE_HEADER_RE = re.compile(r"^\s*(?:Yar[ıiIİ][şsSŞ]|Event)\s+(\d+)\b(.*)$", re.I)
TAG_RE = re.compile(r"\(?(?:Tk|Td|Fd|tk|td|fd|TK|TD|FD)\)?[\.\)]?\s*")
TIME_RE = re.compile(r"^(?:\d{1,2}:)?\d{2}\.\d{2}$")

STROKE_MAP = {
    "serbest": "Serbest", "freestyle": "Serbest",
    "sırt": "Sırtüstü", "backstroke": "Sırtüstü", "sirt": "Sırtüstü",
    "kurbağa": "Kurbağalama", "breaststroke": "Kurbağalama", "kurbaga": "Kurbağalama",
    "kelebek": "Kelebek", "butterfly": "Kelebek",
    "karışık": "Karışık", "medley": "Karışık", "karisik": "Karışık"
}

FOOTER_PATTERNS = [
    "Splash Meet Manager", "BAŞHAKEM", "BASHAKEM", "Hakem", "HAKEM",
    "FİLİZ ALPER", "YÜCEL YILMAZ", "HALDUN ÖZTAŞ", "NESLİHAN YILDIRAN",
    "Registered to", "Türkiye Yüzme Federasyonu", "Turkiye Yuzme Federasyonu"
]


def time_to_seconds(time_str: str) -> Optional[float]:
    """Yarış derecesini saniye cinsinden float değere dönüştürür."""
    if not time_str:
        return None
    t = time_str.strip().replace(",", ".")
    parts = t.split(":")
    try:
        if len(parts) == 1:
            return round(float(parts[0]), 2)
        elif len(parts) == 2:
            return round(int(parts[0]) * 60 + float(parts[1]), 2)
        elif len(parts) == 3:
            return round(int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2]), 2)
    except Exception:
        return None
    return None


def clean_tags(text: str) -> str:
    """Metindeki (Tk), (Td), (Fd) etiketlerini temizler."""
    t = TAG_RE.sub("", text)
    return re.sub(r"\s+", " ", t).strip()


def parse_swimmer_row(raw_line: str, prev_rank: str = "") -> Optional[Dict[str, Any]]:
    """Tek bir yüzücü sonuç satırını ayrıştırır."""
    l_str = raw_line.strip()
    if not l_str:
        return None

    # Diskalifiye ve terk satırları
    if re.match(r"^(?:disk\.|dsq\b|dq\b|yar[ıi]ş\s+terk|dnf\b)", l_str, re.I):
        return None

    # Ara zaman satırlarını atla (örn: 50m:  34.08 ...)
    # Ara zaman satırlarını atla (örn: 50m:  34.08 ..., Som: ...)
    if re.match(r"^(?:[5S]0m|\d{2,4}m|Som)\s*[:\.]", l_str, re.I):
        return None

    # Altbilgi ve başlık kontrolü
    for pat in FOOTER_PATTERNS:
        if pat in l_str:
            return None

    if re.match(r"^(?:S[ıi]ra|Rank)\b", l_str, re.I) or "Puanlar:" in l_str or "Points:" in l_str or "SEANSI" in l_str:
        return None
    if re.match(r"^\d+\s*yaş", l_str, re.I) or "yaşları arası" in l_str.lower():
        return None
    if "baraj" in l_str.lower() and ("geçti" in l_str.lower() or "gecti" in l_str.lower()):
        return None
    if ";" in l_str and (":" in l_str or "baraj" in l_str.lower() or "yzm" in l_str.lower()):
        return None
    if re.search(r"BİREYSEL\s+YZM|TÜRKİYE\s+REKORLAR", l_str, re.I):
        return None

    # Sıralı satır mı (1., 2., 10., td., vb. veya noktasız '10   Sena ERDEM')?
    m_rank = re.match(r"^(?P<sira>\d+|td|ykle|ykm)(?:\.|\s+)\s*(?P<rest>[A-ZÇĞİÖŞÜa-zçğıöşü\(].+)$", l_str, re.I)
    if m_rank:
        sira = m_rank.group("sira")
        content = m_rank.group("rest").strip()
        is_tied = False
    else:
        # Sıra numarası olmayan beraberlik (tied) satırı mı?
        sira = prev_rank
        content = l_str
        is_tied = True

    # İsim ve yaşın bitiştiği veya noktalama gürültüsü içeren durumlar
    # Derece içindeki ':' işaretinin bozulmaması için sadece harflerden sonraki yaş gürültüleri temizlenir
    content = re.sub(r'(?<=[A-Za-zçğıöşüÇĞİÖŞÜ])\s*[\,\:\;\_]\s*(\d{1,2}|1S)\b', r'   \1', content)
    content = re.sub(r'\b1S\b', '15', content)
    # OCR kaynaklı derece bitişmeleri: AcadeiS:05.58 -> Acadei   5:05.58
    content = re.sub(r'([A-Za-zçğıöşüÇĞİÖŞÜ])[sS]:(\d{2}\.\d{2})', r'\1   5:\2', content)
    # OCR kaynaklı derece bitişmeleri (harf veya tırnak/derece/boşluk sonrasında gelen zaman): Acade’3:06.26 / Spor 1:06.43 -> Acade   3:06.26
    content = re.sub(r'([A-Za-zçğıöşüÇĞİÖŞÜ])[\'’\"°\=\-\s]*((?:\d{1,2}:)?\d{2}\.\d{2})', r'\1   \2', content)
    # Derece sonrasındaki derece/tırnak sembollerini temizle (örn: 3:06.26° -> 3:06.26)
    content = re.sub(r'((?:\d{1,2}:)?\d{2}\.\d{2})[°\'’\"°]+', r'\1', content)
    # Puan sonundaki 'ibü' veya 'kulu' kirliliğini ayır (örn: 221ibü -> 221)
    content = re.sub(r'(\d{2,4})\s*[iıIİl]b[uü]', r'\1', content)
    # Bitiş derecesi ve puanı ayır (ara zamanların finish time ile karışmasını engeller): 3:06.26 221 -> 3:06.26   221
    content = re.sub(r'((?:\d{1,2}:)?\d{2}\.\d{2})\s+(\d{2,4})\b', r'\1   \2', content)

    m_concat = re.match(r"^([A-ZÇĞİÖŞÜa-zçğıöşü\s\.\(\)\'\-]+?[A-Za-zÇĞİÖŞÜçğıöşüÂÎÛâîû\.])(\d{1,2})\s+(.+)$", content)
    if m_concat:
        content = f"{m_concat.group(1)}  {m_concat.group(2)}  {m_concat.group(3)}"

    parts = [p.strip() for p in re.split(r"\s{2,}|\t+", content) if p.strip()]
    if not parts:
        return None

    # OCR çıktısında derece ve puan tek boşlukla birleşmişse ayır
    last = parts[-1]
    m_time = re.search(r'((?:\d{1,2}:)?\d{2}\.\d{2})', last)
    if m_time:
        t_val = m_time.group(1)
        after_t = last[m_time.end():]
        m_pts = re.search(r'\b(\d{2,4})\b', after_t)
        p_val = m_pts.group(1) if m_pts else None
        before_t = last[:m_time.start()].strip()
        if before_t:
            parts = parts[:-1] + [before_t, t_val]
        else:
            parts = parts[:-1] + [t_val]
        if p_val:
            parts.append(p_val)

    # İlk parça isim + tek boşluk + yaş içeriyorsa ayır
    if not is_tied:
        m_sp = re.match(r"^(.+?)\s+(\d{1,2})$", parts[0])
        if m_sp and len(parts) >= 2:
            parts = [m_sp.group(1), m_sp.group(2)] + parts[1:]

    sporcu = ""
    yas: Optional[str] = None

    if len(parts) >= 3 and re.match(r"^\d{1,2}$", parts[1]):
        sporcu = clean_tags(parts[0])
        yas = parts[1]
        rem = parts[2:]
    elif len(parts) >= 2 and not re.match(r"^\d{1,2}$", parts[1]):
        sporcu = clean_tags(parts[0])
        yas = None
        rem = parts[1:]
    else:
        return None

    sporcu = standardize_swimmer_name(sporcu)

    if not rem:
        return None

    # rem içinde derece (zaman) indeksini bul
    time_idx = -1
    for i, tok in enumerate(rem):
        if TIME_RE.match(tok):
            time_idx = i
            break

    if time_idx == -1:
        return None

    kulup = clean_tags(" ".join(rem[:time_idx]))
    if not kulup:
        return None

    derece = rem[time_idx]

    puan: Optional[str] = None
    after_time = rem[time_idx + 1:]
    if after_time:
        if re.match(r"^\d+$", after_time[0]):
            puan = after_time[0]

    return {
        "sira": sira,
        "sporcu": sporcu,
        "yas": yas,
        "kulup": kulup,
        "derece": derece,
        "puan": puan,
        "is_tied": is_tied,
        "ham_satir": l_str,
    }


def parse_dq_row(raw_line: str) -> Optional[Dict[str, Any]]:
    """Tek bir diskalifiye / yarış terk satırını ayrıştırır."""
    l_str = raw_line.strip()
    m_disk = re.match(r"^(?:disk\.|dsq\b|dq\b)\s+(.+)$", l_str, re.I)
    m_terk = re.match(r"^(?:yar[ıi]ş\s+terk|dnf\b)\s+(.+)$", l_str, re.I)

    if m_disk:
        rest = m_disk.group(1).strip()
        disk_val = "disk."
    elif m_terk:
        rest = m_terk.group(1).strip()
        disk_val = "yarış terk"
    else:
        return None

    # İsim ve yaşın bitiştiği durumlar
    m_concat = re.match(r"^([A-ZÇĞİÖŞÜa-zçğıöşü\s\.\(\)\'\-]+?[A-Za-zÇĞİÖŞÜçğıöşüÂÎÛâîû\.])(\d{1,2})\s+(.+)$", rest)
    if m_concat:
        rest = f"{m_concat.group(1)}  {m_concat.group(2)}  {m_concat.group(3)}"

    parts = [p.strip() for p in re.split(r"\s{2,}|\t+", rest) if p.strip()]
    if not parts:
        return None

    m_sp = re.match(r"^(.+?)\s+(\d{1,2})$", parts[0])
    if m_sp and len(parts) >= 2:
        parts = [m_sp.group(1), m_sp.group(2)] + parts[1:]

    sporcu = ""
    yas: Optional[str] = None

    if len(parts) >= 3 and re.match(r"^\d{1,2}$", parts[1]):
        sporcu = clean_tags(parts[0])
        yas = parts[1]
        rem = parts[2:]
    elif len(parts) >= 2 and re.match(r"^\d{1,2}$", parts[1]):
        sporcu = clean_tags(parts[0])
        yas = parts[1]
        rem = []
    elif len(parts) >= 2 and not re.match(r"^\d{1,2}$", parts[1]):
        sporcu = clean_tags(parts[0])
        yas = None
        rem = parts[1:]
    else:
        sporcu = clean_tags(parts[0])
        yas = None
        rem = []

    sporcu = standardize_swimmer_name(sporcu)

    kulup = ""
    zaman: Optional[str] = None
    gerekce_inline: Optional[str] = None

    if rem:
        if TIME_RE.match(rem[-1]):
            zaman = rem[-1]
            rem = rem[:-1]

        if rem and re.match(r"^(?:SW\s*\d|DQ|\d{1,2}\s*M)", rem[-1], re.I):
            gerekce_inline = rem[-1]
            rem = rem[:-1]

        kulup = clean_tags(" ".join(rem))

    return {
        "disk": disk_val,
        "sporcu": sporcu,
        "yas": yas or "",
        "kulup": kulup,
        "zaman": zaman or "",
        "gerekce_inline": gerekce_inline,
        "ham_satir": l_str,
    }


def parse_single_file(file_path: Path) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Tek bir metin dosyasındaki tüm sonuçları ve DQ'ları yarış bilgileriyle birlikte ayrıştırır."""
    fn = file_path.name
    try:
        lines = [line.strip() for line in open(file_path, encoding="utf-8", errors="ignore")]
    except Exception:
        return [], []

    swimmers: List[Dict[str, Any]] = []
    dqs: List[Dict[str, Any]] = []

    # Dosya düzeyinde müsabaka adı, şehir ve tarih tespiti
    meet_name = ""
    meet_city = ""
    meet_date = ""

    for l in lines[:30]:
        m_city_date = re.search(r"([A-Za-zÇĞİÖŞÜçğıöşü\s]+),\s*(\d{1,2}\.?\s*-\s*\d{1,2}\.\d{1,2}\.\d{2,4})", l)
        if m_city_date:
            meet_city = m_city_date.group(1).strip().title()
            meet_date = m_city_date.group(2).strip()
            continue
        if (
            not meet_name
            and len(l) > 5
            and not l.startswith("===")
            and not re.search(r"(?:seans|sayfa|splash|\bfina\b|rekor|sonuç|points:|puanlar:)", l, re.I)
            and not re.match(r"^(?:Yar[ıiIİ][şsSŞ]|Event)\s+\d+", l, re.I)
            and not re.search(r"\b\d+\s*x\s*\d+m?\b", l, re.I)
            and not re.match(r"^(?:Zaman|Sıra|Rank|Time)\b", l, re.I)
            and not re.search(r"/\s*[AB][1-4]\b", l)
        ):
            meet_name = l.strip()

    if not meet_name:
        meet_name = fn.replace(".txt", "").replace("-", " ").strip()

    curr_race_no = ""
    curr_gender = ""
    curr_dist = ""
    curr_stroke = ""
    curr_age_group = ""
    curr_page = 1
    in_indiv_race = False
    last_rank = ""
    prev_time_sec: Optional[float] = None

    idx = 0
    while idx < len(lines):
        l = lines[idx]

        m_p = PAGE_RE.match(l)
        if m_p:
            curr_page = int(m_p.group(1))
            idx += 1
            continue

        m_r = RACE_HEADER_RE.match(l)
        if m_r:
            curr_race_no = m_r.group(1)
            rest_h = m_r.group(2).strip()

            # Cinsiyet
            if re.search(r"\b(?:kızlar|bayanlar|kadınlar|women|girls|kız|bayan|kadın)\b", rest_h, re.I):
                curr_gender = "Kızlar"
            elif re.search(r"\b(?:erkekler|men|boys|erkek)\b", rest_h, re.I):
                curr_gender = "Erkekler"
            elif re.search(r"\b(?:karma|mixed)\b", rest_h, re.I):
                curr_gender = "Karma"
            else:
                curr_gender = ""

            # Mesafe
            m_dist = re.search(r"\b(\d+\s*x\s*\d+m?|\d+m)\b", rest_h, re.I)
            curr_dist = m_dist.group(1).lower().replace(" ", "") if m_dist else ""
            if curr_dist and not curr_dist.endswith("m"):
                curr_dist += "m"

            if curr_dist:
                in_indiv_race = ("x" not in curr_dist)
            else:
                in_indiv_race = True

            # Stil
            curr_stroke = ""
            rest_lower = rest_h.lower()
            for kw, canon_stil in STROKE_MAP.items():
                if kw in rest_lower:
                    curr_stroke = canon_stil
                    break

            # Yaş Grubu
            curr_age_group = ""
            m_ag = re.search(r"\b(\d+\s*-\s*\d+\s*yaş(?:ları\s*arası)?|\d+\s*yaş(?:\s*ve\s*büyükler)?|\d+\s*\+\s*yaş|açık|open)\b", rest_h, re.I)
            if m_ag:
                curr_age_group = m_ag.group(1).strip()
            elif re.search(r"\b\d+\s*yaş\b", rest_h, re.I):
                curr_age_group = re.search(r"\b\d+\s*yaş\b", rest_h, re.I).group(0)

            last_rank = ""
            prev_time_sec = None
            idx += 1
            continue

        if not curr_race_no:
            idx += 1
            continue

        # Alt başlıklar (Final A/B, Yaş Grubu, Açık vb.) zaman takibini sıfırlar
        if re.match(r"^(?:Final\s+[A-D]|(?:[A-D]\s+Final[ıi])|\d+\s*yaş|\d+\s*-\s*\d+\s*yaş|Açık|Prelim|Semi|Yarı\s+Final)\b", l, re.I):
            prev_time_sec = None
            last_rank = ""
            idx += 1
            continue

        # 1. Diskalifiye kontrolü
        parsed_dq = parse_dq_row(l)
        if parsed_dq:
            reason = parsed_dq["gerekce_inline"] or ""
            # Sonraki satırda gerekçe var mı kontrolü
            if idx + 1 < len(lines):
                nxt = lines[idx + 1].strip()
                if nxt and not PAGE_RE.match(nxt) and not RACE_HEADER_RE.match(nxt) and not parse_swimmer_row(nxt) and not parse_dq_row(nxt):
                    if any(kw in nxt.lower() for kw in ("sw ", "dönüş", "çıkış", "bitiriş", "yüzmesi gereken", "pozisyon", "hareketsizliğini", "ayak vuruşu", "kural", "zaman:")):
                        reason = f"{reason} {nxt}".strip()
                        idx += 1

            dqs.append({
                "Dosya Adı": fn,
                "Müsabaka Adı": meet_name,
                "Şehir": meet_city,
                "Tarih": meet_date,
                "Yarış No": curr_race_no,
                "Cinsiyet": curr_gender,
                "Mesafe": curr_dist,
                "Stil": curr_stroke,
                "Yaş Grubu": curr_age_group,
                "Sayfa No": curr_page,
                "Satır No": idx + 1,
                "Disk": parsed_dq["disk"],
                "Sporcu": parsed_dq["sporcu"],
                "Yaş": parsed_dq["yas"],
                "Kulüp": parsed_dq["kulup"],
                "Zaman": parsed_dq["zaman"],
                "Gerekçe": reason,
                "Bayrak Mı": "HAYIR" if in_indiv_race else "EVET",
                "Ham Satır": parsed_dq["ham_satir"]
            })
            idx += 1
            continue

        # 2. Bireysel yüzücü satırı kontrolü (bayrak yarışı değilse)
        if in_indiv_race:
            parsed_sw = parse_swimmer_row(l, prev_rank=last_rank)
            if parsed_sw:
                if parsed_sw["sira"]:
                    last_rank = parsed_sw["sira"]

                curr_sec = time_to_seconds(parsed_sw["derece"])
                sira_val = parsed_sw["sira"].strip().lower()
                rank_num = int(sira_val) if sira_val.isdigit() else None

                zaman_kontrol = "GEÇERLİ"
                uyari_notu = ""

                # Sıfırlama noktaları: 1. sıra, Final B (9. sıra), Final C (17. sıra) veya yeni seri
                if rank_num in (1, 9, 17, 25) or prev_time_sec is None:
                    zaman_kontrol = "GEÇERLİ"
                    prev_time_sec = curr_sec
                elif sira_val in ("td", "ykle", "ykm"):
                    zaman_kontrol = "TASNİF_DIŞI"
                    uyari_notu = "Tasnif dışı sporcu"
                    prev_time_sec = curr_sec
                elif curr_sec is not None and prev_time_sec is not None and curr_sec == prev_time_sec:
                    zaman_kontrol = "BERABERLİK"
                    prev_time_sec = curr_sec
                elif curr_sec is not None and prev_time_sec is not None and curr_sec > prev_time_sec:
                    zaman_kontrol = "GEÇERLİ"
                    prev_time_sec = curr_sec
                elif curr_sec is not None and prev_time_sec is not None and curr_sec < prev_time_sec:
                    zaman_kontrol = "ZAMAN_HATASI"
                    uyari_notu = f"Zaman bir önceki sporcudan daha kısa: {curr_sec}s < {prev_time_sec}s"
                    prev_time_sec = curr_sec

                baraj = False
                if idx + 1 < len(lines):
                    nxt = lines[idx + 1].lower()
                    if "baraj" in nxt and ("geçti" in nxt or "gecti" in nxt):
                        baraj = True
                        idx += 1

                swimmers.append({
                    "Dosya Adı": fn,
                    "Müsabaka Adı": meet_name,
                    "Şehir": meet_city,
                    "Tarih": meet_date,
                    "Yarış No": curr_race_no,
                    "Cinsiyet": curr_gender,
                    "Mesafe": curr_dist,
                    "Stil": curr_stroke,
                    "Yaş Grubu": curr_age_group,
                    "Sayfa No": curr_page,
                    "Satır No": idx + 1,
                    "Sıra": parsed_sw["sira"],
                    "Sporcu": parsed_sw["sporcu"],
                    "Yaş": parsed_sw["yas"] or "",
                    "Kulüp": parsed_sw["kulup"],
                    "Derece": parsed_sw["derece"],
                    "Derece (Saniye)": curr_sec if curr_sec is not None else "",
                    "Puan": parsed_sw["puan"] or "",
                    "Baraj": "EVET" if baraj else "HAYIR",
                    "Beraberlik Mi": "EVET" if parsed_sw["is_tied"] else "HAYIR",
                    "Zaman Kontrolü": zaman_kontrol,
                    "Uyarı Notu": uyari_notu,
                    "Ham Satır": parsed_sw["ham_satir"]
                })
                idx += 1
                continue

        idx += 1

    return swimmers, dqs


def parse_all_archive_files(
    txt_dirs: str | Path | List[str | Path] = "output/txt/tyf_arsiv",
    out_swimmers_csv: str | Path = "output/tyf_arsiv_bireysel_yuzucu_sonuclari.csv",
    out_dqs_csv: str | Path = "output/tyf_arsiv_diskalifiyeler.csv",
    workers: int = 8
):
    if isinstance(txt_dirs, (str, Path)):
        dirs_list = [Path(txt_dirs)]
    else:
        dirs_list = [Path(d) for d in txt_dirs]

    txt_files: List[Path] = []
    for d in dirs_list:
        txt_files.extend(sorted(list(d.glob("*.txt"))))

    print(f"Ayrıştırılacak metin dosyası sayısı: {len(txt_files)} (Taranan dizinler: {[str(d) for d in dirs_list]})")

    t0 = time.perf_counter()
    all_swimmers: List[Dict[str, Any]] = []
    all_dqs: List[Dict[str, Any]] = []

    with ProcessPoolExecutor(max_workers=workers) as executor:
        results = executor.map(parse_single_file, txt_files)
        for i, (sws, dqs) in enumerate(results, 1):
            all_swimmers.extend(sws)
            all_dqs.extend(dqs)
            if i % 50 == 0 or i == len(txt_files):
                print(f"[{i}/{len(txt_files)}] dosyaları işlendi... (Toplam yüzücü: {len(all_swimmers)}, DQ: {len(all_dqs)})")

    elapsed = time.perf_counter() - t0

    # CSV Kaydetme
    os.makedirs(os.path.dirname(str(out_swimmers_csv)), exist_ok=True)
    if all_swimmers:
        with open(out_swimmers_csv, "w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(all_swimmers[0].keys()))
            writer.writeheader()
            writer.writerows(all_swimmers)

    if all_dqs:
        with open(out_dqs_csv, "w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(all_dqs[0].keys()))
            writer.writeheader()
            writer.writerows(all_dqs)

    print("\n" + "=" * 65)
    print("           TYF ARŞİVİ PARSE ÖZET RAPORU           ")
    print("=" * 65)
    print(f" İşlenen Toplam Dosya Sayısı     : {len(txt_files):6d}")
    print(f" Toplam Bireysel Yüzücü Sonucu   : {len(all_swimmers):6d}")
    print(f" Toplam Diskalifiye / Terk Kaydı : {len(all_dqs):6d}")
    print(f" Toplam İşlem Süresi             : {elapsed:.2f} saniye")
    print(f" Çıktı Yüzücü CSV                : {out_swimmers_csv}")
    print(f" Çıktı DQ CSV                    : {out_dqs_csv}")
    print("=" * 65)


if __name__ == "__main__":
    parse_all_archive_files()
