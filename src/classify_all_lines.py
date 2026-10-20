"""
src/classify_all_lines.py
Sorumluluk: 42 sonuç metin dosyasındaki 109.153 satırın her birini tek tek semantik
kategorilerine göre deterministik olarak sınıflandırmak, atlanan/sınıflandırılamayan
satırları raporlamak ve 'output/tum_satirlar_siniflandirma.csv' dosyasını üretmek.
"""

from __future__ import annotations

import csv
import glob
import os
import re
import sys
from collections import Counter
from pathlib import Path
from typing import List, Dict, Any, Tuple

# Proje kök dizinini ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

PAGE_RE = re.compile(r"^===\s*SAYFA\s*(\d+)\s*/\s*(\d+)\s*===", re.I)

RACE_HEADER_RE = re.compile(
    r"^\s*Yar[ıiIİ][şsSŞ]\s+(\d+)\s*(?:,\s*|(?:\s{2,}|\t+))"
    r"([A-ZÇĞİÖŞÜa-zçğıöşü\s,]+?)(?:,\s*|(?:\s{2,}|\t+))"
    r"(\d+\s*x\s*\d+m|\d+m)\s+"
    r"([A-Za-zÇĞİÖŞÜçğıöşü\s]+?)"
    r"(?:(?:,\s*|(?:\s{2,}|\t+))([0-9\s\-+a-zçğıöşüA-ZÇĞİÖŞÜ]+))?$",
    re.I,
)

RACE_CONT_RE = re.compile(
    r"^\s*Yar[ıiIİ][şsSŞ]\s+(\d+)\s*,\s*"
    r"([A-ZÇĞİÖŞÜa-zçğıöşü\s,]+?),\s*"
    r"(\d+\s*x\s*\d+m|\d+m)\s+"
    r"([A-Za-zÇĞİÖŞÜçğıöşü\s]+)"
    r"(?:,\s*([0-9\s\-+a-zçğıöşüA-ZÇĞİÖŞÜ]+))?$",
    re.I,
)

FOOTER_NAMES = {
    "ALİ SERCAN SEVER", "ERGUN SAVAN", "KEZBAN ALGİL", "FİLİZ ALPER",
    "FULYA TİLLİOĞLU", "YÜCEL YILMAZ", "HALDUN ÖZTAŞ", "D.KEMAL KARADENİZ",
    "NESLİHAN YILDIRAN", "SERENA VURAL", "KEMAL KARADENİZ",
    "FATİH KUTAY AKPINAR", "SERBAY ŞAFAK GÖKÇİMEN", "FATIH KUTAY AKPINAR", "SERBAY SAFAK GOKCIMEN"
}

SPLIT_RE = re.compile(r"^\s*(?:\d{2,4}m:\s*|\d{2,4}m\s+)", re.I)
BARAJ_GECME_RE = re.compile(
    r"(?:baraj[ıiİI]n?[ıiİI]?\s*ge[çc]t[iıİI]|baraj[ıiİI]\s*ge[çc]t[iıİI]|"
    r"katilim\s*baraji\s*ge[çc]t[iıİI]|har[çc]\s*baraj[ıiİI]n?[ıiİI]?\s*ge[çc]t[iıİI]|"
    r"\bbaraj\s+ge[çc]t[iıİI]\b)",
    re.I,
)
TIME_RE = re.compile(r"^(?:\d{1,2}:)?\d{2}\.\d{2}$")
AGE_SUB_RE = re.compile(r"^\s*(?:\d{1,2}|\d{1,2}\s*-\s*\d{1,2})\s*yaş(?:ları\s*arası)?\s*$|^\s*(?:\d{1,2}\s*yaş\s*ve\s*büyükler|Açık)\s*$", re.I)
TABLE_HEADER_RE = re.compile(r"^\s*S[ıi]ra\b.*(?:Derece|Zaman)", re.I)
DNF_DISTANCE_RE = re.compile(r"^(?:\d{2,4}\s*[mM]|\d{2,4}\.\s*Metre)\s*$", re.I)


def classify_single_file(file_path: str | Path) -> List[Dict[str, Any]]:
    """Tek bir dosyadaki tüm satırları sırayla analiz edip sınıflandırır."""
    file_path = Path(file_path)
    fn = file_path.name
    lines = [l.rstrip("\r\n") for l in open(file_path, encoding="utf-8")]

    results: List[Dict[str, Any]] = []
    curr_page = 0
    in_relay = False
    in_dq = False
    in_race_header = False
    lines_since_page = 0
    page_header_lines_seen = 0

    for idx, raw_line in enumerate(lines):
        l = raw_line.strip()
        line_no = idx + 1
        category = ""
        status = "OK"

        # 1. BOS_SATIR
        if not l:
            category = "BOS_SATIR"
            results.append({
                "Dosya Adı": fn,
                "Sayfa No": curr_page,
                "Satır No": line_no,
                "Kategori": category,
                "Durum": status,
                "Ham Satır": raw_line,
            })
            continue

        # 2. SAYFA_BASLANGICI
        m_p = PAGE_RE.match(l)
        if m_p:
            curr_page = int(m_p.group(1))
            lines_since_page = 0
            page_header_lines_seen = 0
            in_race_header = False
            category = "SAYFA_BASLANGICI"
            results.append({
                "Dosya Adı": fn,
                "Sayfa No": curr_page,
                "Satır No": line_no,
                "Kategori": category,
                "Durum": status,
                "Ham Satır": raw_line,
            })
            continue

        lines_since_page += 1

        # 3. SAYFA_ALTBILGISI_SPLASH
        if "Splash Meet Manager" in l:
            category = "SAYFA_ALTBILGISI_SPLASH"
            in_dq = False
            in_race_header = False

        # 4. SAYFA_ALTBILGISI_HAKEM
        elif "BAŞHAKEM" in l or any(ref in l for ref in FOOTER_NAMES) or l == "HAKEM" or re.match(r"^HAKEM\s+", l):
            category = "SAYFA_ALTBILGISI_HAKEM"
            in_dq = False
            in_race_header = False

        # 5. SEANS_BASLIGI
        elif re.match(r"^\s*\d+\s*-\s*\d+\.\s*GÜN\s+.*SEANSI", l, re.I) or (re.search(r"\bSEANSI\b", l) and not re.search(r"Yar[ıi]ş", l)):
            category = "SEANS_BASLIGI"
            in_dq = False
            in_race_header = False

        # 6. YARIS_BASLIGI (Yeni Yarış)
        elif RACE_HEADER_RE.match(l) and idx + 1 < len(lines) and "sonuçlar" in lines[idx + 1].lower():
            category = "YARIS_BASLIGI"
            m_r = RACE_HEADER_RE.match(l)
            dist = m_r.group(3)
            in_relay = ("x" in dist.lower())
            in_dq = False
            in_race_header = True

        # 7. YARIS_DEVAM_BASLIGI
        elif RACE_CONT_RE.match(l) or (RACE_HEADER_RE.match(l) and not (idx + 1 < len(lines) and "sonuçlar" in lines[idx + 1].lower())):
            category = "YARIS_DEVAM_BASLIGI"
            m_rc = RACE_CONT_RE.match(l)
            if m_rc:
                dist = m_rc.group(3)
                in_relay = ("x" in dist.lower())
            else:
                m_r = RACE_HEADER_RE.match(l)
                if m_r:
                    dist = m_r.group(3)
                    in_relay = ("x" in dist.lower())
            in_dq = False
            in_race_header = False

        # 8. YARIS_TARIH_SONUC
        elif re.search(r"Sonu[çc]lar\s*$", l, re.I) and (re.search(r"\d{1,2}[\./]\d{1,2}[\./]\d{4}", l) or l.lower() == "sonuçlar"):
            category = "YARIS_TARIH_SONUC"
            in_dq = False
            in_race_header = True

        # 9. PUAN_SISTEMI
        elif l.startswith("Puanlar:") or l.startswith("Puanlar :"):
            category = "PUAN_SISTEMI"
            in_dq = False

        # 10. TABLO_BASLIGI
        elif TABLE_HEADER_RE.match(l):
            category = "TABLO_BASLIGI"
            in_dq = False
            in_race_header = False

        # 11. BARAJ_KRITERI_TABLOSU (Yarış başlığında tanımlanan baraj tablosu)
        elif in_race_header and not BARAJ_GECME_RE.search(l):
            category = "BARAJ_KRITERI_TABLOSU"

        elif (re.search(r"\b(?:A1|A2|A3|A4|B1|B2)\s*:", l) or
              re.search(r"kat[ıi]l[ıi]m\s*barajlar[ıi]\s*:", l, re.I) or
              re.search(r"^\s*BARAJ\s*:", l, re.I) or
              re.search(r"Milli\s+Tak[ıi]m\s+Baraj[ıi]", l, re.I) or
              re.search(r"KUL[UÜ]PLERARASI", l, re.I)) and not BARAJ_GECME_RE.search(l):
            category = "BARAJ_KRITERI_TABLOSU"

        # 12. YAS_GRUBU_ALT_BASLIGI
        elif AGE_SUB_RE.match(l):
            category = "YAS_GRUBU_ALT_BASLIGI"
            in_dq = False

        # 13. ARA_ZAMAN_DETAYI
        elif SPLIT_RE.match(l):
            category = "ARA_ZAMAN_DETAYI"
            in_dq = False

        # 14. DISKALIFIYE (İlk satır)
        elif re.match(r"^disk\.\s+", l, re.I):
            category = "DISKALIFIYE"
            in_dq = True

        # 15. YARIS_TERK (İlk satır)
        elif re.match(r"^yar[ıi]ş\s+terk\s+", l, re.I):
            category = "YARIS_TERK"
            in_dq = True

        # 16. YARIS_TERK_MESAFESI
        elif DNF_DISTANCE_RE.match(l):
            category = "YARIS_TERK_MESAFESI"

        else:
            # 17. SAYFA ÜST BİLGİSİ (Müsabaka Adı & Şehir/Tarih)
            is_dq_rule = bool(re.search(r"\bSW\s*[\d\.,]+", l, re.I) or re.search(r"\(Zaman:\s*", l, re.I))
            is_swimmer_start = bool(re.match(r"^(?:\d+|td|ykle|ykm)\.\s+", l, re.I))

            if lines_since_page <= 3 and page_header_lines_seen < 2 and not is_dq_rule and not is_swimmer_start:
                if any(k in l.upper() for k in ["ANKARA", "TÜRKİYE", "2024", "2025", "2023"]) and page_header_lines_seen == 1:
                    category = "SAYFA_UST_BILGISI_YER_TARIH"
                    page_header_lines_seen += 1
                    in_dq = False
                elif page_header_lines_seen == 0 and not in_dq:
                    category = "SAYFA_UST_BILGISI_MUSABAKA_ADI"
                    page_header_lines_seen += 1
                    in_dq = False

            # 18. DISKALIFIYE_GEREKCESI (Kural açıklamaları, zaman ve devam satırları)
            if not category and (in_dq or is_dq_rule):
                m_rank = re.match(r"^(?:\d+|td|ykle|ykm)\.\s+", l, re.I)
                tokens = [t.strip() for t in re.split(r"\s{2,}|\t+", l) if t.strip()]
                has_time = any(TIME_RE.match(t) for t in tokens)

                if (m_rank and has_time) or (has_time and len(tokens) >= 3 and re.match(r"^\d{1,2}$", tokens[1])):
                    in_dq = False
                else:
                    category = "DISKALIFIYE_GEREKCESI"
                    in_dq = True

            # 19. BARAJ_GECME_BILGISI (Bireysel yüzücü altında)
            if not category and BARAJ_GECME_RE.search(l):
                category = "BARAJ_GECME_BILGISI"
                in_dq = False

            # 20. BAYRAK YARIŞI SATIRLARI
            if not category and in_relay:
                tokens = [t.strip() for t in re.split(r"\s{2,}|\t+", l) if t.strip()]
                has_time = any(TIME_RE.match(t) for t in tokens)
                if has_time or re.match(r"^\d+\.\s+", l):
                    category = "BAYRAK_TAKIMI_SONUCU"
                else:
                    category = "BAYRAK_YUZUCULERI_DETAYI"
                in_dq = False

            # 21. BİREYSEL YÜZÜCÜ SONUÇLARI
            if not category:
                tokens = [t.strip() for t in re.split(r"\s{2,}|\t+", l) if t.strip()]
                has_time = any(TIME_RE.match(t) for t in tokens)
                m_rank = re.match(r"^(?:\d+|td|ykle|ykm)\.\s+", l, re.I)

                if m_rank and has_time:
                    category = "BIREYSEL_YUZUCU_SONUCU"
                    in_dq = False
                elif has_time and len(tokens) >= 2:
                    category = "BIREYSEL_YUZUCU_BERABERLIK"
                    in_dq = False

            # 22. ATLANAN_SATIR
            if not category:
                category = "ATLANAN_SATIR"
                status = "ATLANDI"

        results.append({
            "Dosya Adı": fn,
            "Sayfa No": curr_page,
            "Satır No": line_no,
            "Kategori": category,
            "Durum": status,
            "Ham Satır": raw_line,
        })

    return results


def classify_all_files(directory: str | Path, output_csv: str | Path) -> Tuple[List[Dict[str, Any]], Counter]:
    """Tüm txt dosyalarını sınıflandırıp CSV olarak kaydeder."""
    files = sorted(glob.glob(os.path.join(str(directory), "*.txt")))
    all_classified: List[Dict[str, Any]] = []
    category_counts = Counter()

    print(f"Toplam {len(files)} dosya taranıyor...")
    for f in files:
        file_results = classify_single_file(f)
        all_classified.extend(file_results)
        for r in file_results:
            category_counts[r["Kategori"]] += 1

    # CSV Kaydı (Excel uyumlu utf-8-sig)
    os.makedirs(os.path.dirname(str(output_csv)), exist_ok=True)
    fieldnames = ["Dosya Adı", "Sayfa No", "Satır No", "Kategori", "Durum", "Ham Satır"]

    print(f"CSV kaydediliyor: {output_csv}...")
    with open(output_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(all_classified)

    return all_classified, category_counts


if __name__ == "__main__":
    txt_dir = Path("output/txt/ankara")
    out_csv = Path("output/tum_satirlar_siniflandirma.csv")

    results, counts = classify_all_files(txt_dir, out_csv)
    total_lines = len(results)
    skipped_count = counts.get("ATLANAN_SATIR", 0)

    print("\n" + "=" * 65)
    print("           TÜM SATIRLARIN SINIFLANDIRMA ÖZETİ           ")
    print("=" * 65)
    for cat, count in counts.most_common():
        pct = (count / total_lines) * 100
        print(f" {cat:32}: {count:6d} ({pct:6.2f}%)")
    print("-" * 65)
    print(f" TOPLAM SATIR SAYISI             : {total_lines:6d} (100.00%)")
    print(f" ATLANAN / TANIMSIZ SATIRLAR      : {skipped_count:6d} ({(skipped_count/total_lines)*100:6.2f}%)")
    print("=" * 65)
    print(f"CSV başarıyla üretildi: {out_csv}")

