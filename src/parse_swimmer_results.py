"""
src/parse_swimmer_results.py
Sorumluluk: Bireysel yarışlardaki (bayrak yarışları hariç) tüm yüzücü sonuç satırlarını
(sıralı ve beraberlik/tied satırları dahil) ayrıştırmak, (Tk), (Td), (Fd) etiketlerini
temizlemek, baraj geçme bilgilerini eşleştirmek ve SwimmerResultLine modeliyle doğrulamak.
"""

from __future__ import annotations

import csv
import glob
import json
import os
import re
import sys
from pathlib import Path
from typing import List, Dict, Any, Optional

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.models import SwimmerResultLine
from src.canonicalize_athletes import standardize_swimmer_name

PAGE_RE = re.compile(r"^===\s*SAYFA\s*(\d+)\s*/\s*(\d+)\s*===", re.I)

RACE_HEADER_RE = re.compile(
    r"^\s*Yar[ıiIİ][şsSŞ]\s+(\d+)\s*(?:,\s*|(?:\s{2,}|\t+))"
    r"([A-ZÇĞİÖŞÜa-zçğıöşü\s,]+?)(?:,\s*|(?:\s{2,}|\t+))"
    r"(\d+\s*x\s*\d+m|\d+m)\s+"
    r"([A-Za-zÇĞİÖŞÜçğıöşü\s]+?)"
    r"(?:(?:,\s*|(?:\s{2,}|\t+))([0-9\s\-+a-zçğıöşüA-ZÇĞİÖŞÜ]+))?$",
    re.I,
)

TAG_RE = re.compile(r"\((?:Tk|Td|Fd|tk|td|fd|TK|TD|FD)\)\s*")
TIME_RE = re.compile(r"^(?:\d{1,2}:)?\d{2}\.\d{2}$")

FOOTER_NAMES = {
    "ALİ SERCAN SEVER", "ERGUN SAVAN", "KEZBAN ALGİL", "FİLİZ ALPER",
    "FULYA TİLLİOĞLU", "YÜCEL YILMAZ", "HALDUN ÖZTAŞ", "D.KEMAL KARADENİZ",
    "NESLİHAN YILDIRAN", "SERENA VURAL", "KEMAL KARADENİZ"
}


def time_to_seconds(time_str: str) -> Optional[float]:
    """Yarış derecesini (örn: '54.03', '1:15.00', '16:23.70') saniye cinsinden float değere dönüştürür."""
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

    # Diskalifiye ve terk satırları bu katmanın konusu değildir
    if re.match(r"^disk\.\s+", l_str, re.I) or re.match(r"^yar[ıi]ş\s+terk\s+", l_str, re.I):
        return None

    # Ara zaman satırlarını atla (örn: 50m:  34.08 ...)
    if re.match(r"^\d{2,4}m:\s+", l_str, re.I):
        return None

    # Altbilgi ve başlık kontrolü
    if "Splash Meet Manager" in l_str or "BAŞHAKEM" in l_str or any(ref in l_str for ref in FOOTER_NAMES):
        return None
    if re.match(r"^S[ıi]ra\b", l_str, re.I) or l_str.startswith("Puanlar:") or "SEANSI" in l_str:
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

    # OCR ve metin çıktısında derece ve puan tek boşlukla birleşmişse ayır
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


def parse_swimmers_from_file(file_path: str | Path) -> List[SwimmerResultLine]:
    """Bir metin dosyasındaki tüm bireysel yüzücü sonuçlarını ayrıştırır."""
    file_path = Path(file_path)
    fn = file_path.name
    lines = [line.strip() for line in open(file_path, encoding="utf-8")]

    swimmers: List[SwimmerResultLine] = []
    curr_race_no = ""
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
        if m_r and idx + 1 < len(lines) and "sonuçlar" in lines[idx + 1].lower():
            curr_race_no = m_r.group(1)
            dist = m_r.group(3)
            # Bayrak yarışı mı kontrolü (4 x 50m vb.)
            in_indiv_race = ("x" not in dist.lower())
            last_rank = ""
            prev_time_sec = None
            idx += 1
            continue

        if not in_indiv_race or not curr_race_no:
            idx += 1
            continue

        # Yüzücü satırı çözümlemeyi dene
        parsed = parse_swimmer_row(l, prev_rank=last_rank)
        if parsed:
            if parsed["sira"]:
                last_rank = parsed["sira"]

            # Dereceyi saniye seviyesine çevir
            curr_sec = time_to_seconds(parsed["derece"])
            sira_val = parsed["sira"].strip().lower()
            rank_num = int(sira_val) if sira_val.isdigit() else None

            # Önceki satır ile zaman uyumluluk kontrolü (Eşit veya daha uzun olma kontrolü)
            zaman_kontrol = "GEÇERLİ"
            uyari_notu: Optional[str] = None

            if rank_num == 1 or prev_time_sec is None:
                zaman_kontrol = "GEÇERLİ"
                prev_time_sec = curr_sec
            elif sira_val in ("td", "ykle", "ykm"):
                zaman_kontrol = "TASNİF_DIŞI"
                uyari_notu = "Tasnif dışı sporcu"
                prev_time_sec = curr_sec
            elif parsed["is_tied"] or (curr_sec is not None and curr_sec == prev_time_sec):
                zaman_kontrol = "BERABERLİK"
                prev_time_sec = curr_sec
            elif curr_sec is not None and prev_time_sec is not None and curr_sec >= prev_time_sec:
                zaman_kontrol = "GEÇERLİ"
                prev_time_sec = curr_sec
            elif curr_sec is not None and prev_time_sec is not None and curr_sec < prev_time_sec:
                zaman_kontrol = "ZAMAN_HATASI"
                uyari_notu = f"Zaman bir önceki sporcudan daha kısa: {curr_sec}s < {prev_time_sec}s"
                prev_time_sec = curr_sec

            # Alt satırlarda (1-3 satır içinde) baraj geçme bilgisi var mı kontrol et
            baraj_info: Optional[str] = None
            cur_look = idx + 1
            while cur_look < len(lines) and cur_look <= idx + 3:
                cand = lines[cur_look]
                if not cand or cand.startswith("==="):
                    cur_look += 1
                    continue
                # Başka bir yüzücüye denk geldiysek dur
                if re.match(r"^(?:\d+\.|td\.|disk\.|ykle\.|ykm\.)\s+", cand) or re.match(r"^yar[ıi]ş\s+terk\s+", cand, re.I):
                    break
                if RACE_HEADER_RE.match(cand) and cur_look + 1 < len(lines) and "sonuçlar" in lines[cur_look + 1].lower():
                    break
                if "baraj" in cand.lower() and ("geçti" in cand.lower() or "gecti" in cand.lower()):
                    baraj_info = cand.strip()
                    break
                cur_look += 1

            item = SwimmerResultLine(
                dosya_adi=fn,
                yaris_no=curr_race_no,
                sayfa_no=curr_page,
                satir_no=idx + 1,
                sira=parsed["sira"],
                sporcu=parsed["sporcu"],
                yas=parsed["yas"],
                kulup=parsed["kulup"],
                derece=parsed["derece"],
                derece_sn=curr_sec,
                puan=parsed["puan"],
                baraj=baraj_info,
                is_tied=parsed["is_tied"],
                zaman_kontrol=zaman_kontrol,
                uyari_notu=uyari_notu,
                ham_satir=l,
            )
            swimmers.append(item)

        idx += 1

    return swimmers


def parse_all_swimmers(directory: str | Path) -> List[SwimmerResultLine]:
    """Tüm txt dosyalarındaki bireysel yüzücü sonuçlarını toplar."""
    files = sorted(glob.glob(os.path.join(str(directory), "*.txt")))
    all_swimmers: List[SwimmerResultLine] = []
    for f in files:
        all_swimmers.extend(parse_swimmers_from_file(f))
    return all_swimmers


def save_results(results: List[SwimmerResultLine], out_csv: str, out_json: str) -> None:
    """Sonuçları CSV ve JSON formatında kaydeder."""
    os.makedirs(os.path.dirname(out_csv), exist_ok=True)

    # JSON kaydı
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump([r.model_dump() for r in results], f, ensure_ascii=False, indent=2)

    # CSV kaydı (Excel uyumlu UTF-8 BOM ile)
    fieldnames = [
        "Dosya Adı",
        "Yarış No",
        "Sayfa No",
        "Satır No",
        "Sıra",
        "Sporcu",
        "Yaş",
        "Kulüp",
        "Derece",
        "Derece (Saniye)",
        "Puan",
        "Baraj",
        "Beraberlik Mi",
        "Zaman Kontrolü",
        "Uyarı Notu",
        "Ham Satır",
    ]

    with open(out_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in results:
            writer.writerow({
                "Dosya Adı": r.dosya_adi,
                "Yarış No": r.yaris_no,
                "Sayfa No": r.sayfa_no,
                "Satır No": r.satir_no,
                "Sıra": r.sira,
                "Sporcu": r.sporcu,
                "Yaş": r.yas or "",
                "Kulüp": r.kulup,
                "Derece": r.derece,
                "Derece (Saniye)": f"{r.derece_sn:.2f}" if r.derece_sn is not None else "",
                "Puan": r.puan or "",
                "Baraj": r.baraj or "",
                "Beraberlik Mi": "EVET" if r.is_tied else "HAYIR",
                "Zaman Kontrolü": r.zaman_kontrol,
                "Uyarı Notu": r.uyari_notu or "",
                "Ham Satır": r.ham_satir,
            })


if __name__ == "__main__":
    txt_dir = Path("output/txt/ankara")
    swimmers = parse_all_swimmers(txt_dir)
    print(f"Toplam parse edilen bireysel yüzücü sonucu: {len(swimmers)}")

    tied_count = sum(1 for s in swimmers if s.is_tied)
    baraj_count = sum(1 for s in swimmers if s.baraj)
    valid_count = sum(1 for s in swimmers if s.zaman_kontrol == "GEÇERLİ")
    tie_status_count = sum(1 for s in swimmers if s.zaman_kontrol == "BERABERLİK")
    td_status_count = sum(1 for s in swimmers if s.zaman_kontrol == "TASNİF_DIŞI")
    error_count = sum(1 for s in swimmers if s.zaman_kontrol == "ZAMAN_HATASI")

    print(f"  - Beraberlik (sırasız) satırları: {tied_count}")
    print(f"  - Baraj geçenler: {baraj_count}")
    print("\nZaman Uyumluluk Kontrolü Sonuçları:")
    print(f"  - GEÇERLİ (Zaman artan/uyumlu) : {valid_count}")
    print(f"  - BERABERLİK (Eşit zaman)     : {tie_status_count}")
    print(f"  - TASNİF DIŞI (td./ykle.)     : {td_status_count}")
    print(f"  - ZAMAN HATASI (Azalan zaman) : {error_count}")

    out_csv = "output/bireysel_yuzucu_sonuclari.csv"
    out_json = "output/bireysel_yuzucu_sonuclari.json"
    save_results(swimmers, out_csv, out_json)
    print(f"\nCSV kaydedildi: {out_csv}")
    print(f"JSON kaydedildi: {out_json}")

