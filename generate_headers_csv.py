"""
Generate Comprehensive Page & Event Headers CSV
===============================================
Her bir PDF sayfasındaki yarış başlıklarını (Yeni Yarış, Devam Başlığı, Başlıksız Taşma)
ve sonuç başlangıç satırlarını deterministik olarak ayrıştırarak denetim CSV'si üretir.
"""

import csv
import glob
import os
import re
from pathlib import Path
from typing import Dict, List

PAGE_RE = re.compile(r"^===\s*SAYFA\s*(\d+)\s*/\s*(\d+)\s*===")

SESSION_RE = re.compile(
    r"^\s*(\d+\s*-\s*[\d\.]+\s*GÜN\s+[A-ZÇĞİÖŞÜ\s]+SEANSI)"
    r"(?:\s{2,}|\t+)?([0-9\.\s:\-]+)?$",
    re.I,
)

EVENT_HEADER_RE = re.compile(
    r"^\s*Yar[ıiIİ][şsSŞ]\s+(\d+)\s*(?:,\s*|(?:\s{2,}|\t+))"
    r"([A-ZÇĞİÖŞÜa-zçğıöşü\s,]+?)(?:,\s*|(?:\s{2,}|\t+))"
    r"(\d+\s*x\s*\d+m|\d+m)\s+"
    r"([A-Za-zÇĞİÖŞÜçğıöşü\s]+?)"
    r"(?:(?:,\s*|(?:\s{2,}|\t+))([0-9\s\-+a-zçğıöşüA-ZÇĞİÖŞÜ]+))?$",
    re.I,
)

RUNNING_EVENT_RE = re.compile(
    r"^\s*Yar[ıiIİ][şsSŞ]\s+(\d+),\s*"
    r"([A-ZÇĞİÖŞÜa-zçğıöşü\s]+?),\s*"
    r"(\d+\s*x\s*\d+m|\d+m)\s+"
    r"([A-Za-zÇĞİÖŞÜçğıöşü\s]+?)"
    r"(?:,\s*(.+?))?$",
    re.I,
)

EVENT_DATE_RESULTS_RE = re.compile(
    r"^\s*(\d{1,2}\.\d{1,2}\.\d{4})(?:\s*-\s*([0-9:]+))?\s+Sonu[çc]lar\s*$",
    re.I,
)

TABLE_HEADER_RE = re.compile(
    r"^\s*S[ıi]ra\s+(YB|Yaş|Age|Time|Zaman|Derece|Sporcu)\b", re.I
)

RESULT_START_RE = re.compile(
    r"^(?:\d+\.\s+|\(Fd\)|\(Tk\)|\(Td\)|td\.|disk\.|terk\.|DNS)", re.I
)

AGE_SUBHEADER_RE = re.compile(
    r"^\s*(\d{1,2}(?:\s*-\s*\d{1,2})?\s*(?:yaş[a-z]*|yaşları arası|yaş ve büyükler|yaş ve üzeri))\s*$",
    re.I,
)

KNOWN_CITIES = {
    "ANKARA", "İSTANBUL", "İZMİR", "BURSA", "ANTALYA", "TRABZON", "EDİRNE",
    "GAZİANTEP", "KONYA", "MERSİN", "SAMSUN", "KOCAELİ", "ADANA", "KAYSERİ", "ESKİŞEHİR"
}


def is_city_line(line: str) -> bool:
    """Satırın şehir ve tarih satırı olup olmadığını doğrular."""
    if not line:
        return False
    u = line.strip().upper()
    if u.startswith("YARIŞ") or u.startswith("YARIS") or "SEANSI" in u or "SONUÇLAR" in u or "SONUCLAR" in u:
        return False
    if u.startswith("SIRA") or u.startswith("PUANLAR"):
        return False
    for c in KNOWN_CITIES:
        if u.startswith(c):
            return True
    if re.search(r"\d{1,2}[\.-]\s*(?:\d{1,2}[\.-]\s*)?\d{4}", line) and "," in line:
        return True
    return False


def is_spillover_start(line: str) -> bool:
    """Sayfa başındaki satırın önceki sayfadan taşan sonuç/DQ satırı olup olmadığını kontrol eder."""
    if not line:
        return False
    if RESULT_START_RE.match(line):
        return True
    spill_prefixes = [
        "SW ", "(Zaman:", "yapılmadığından", "veya her", "baş su", "vuruşu",
        "BİTİRİŞTE", "SIRTÜSTÜ", "mayo"
    ]
    return any(line.startswith(p) for p in spill_prefixes)


def parse_file_headers(file_path: str) -> List[Dict[str, str]]:
    fn = os.path.basename(file_path)
    lines = [l.strip() for l in open(file_path, encoding="utf-8")]
    total_lines = len(lines)

    doc_meet_name = ""
    doc_location = "ANKARA"  # Klasör ankara olduğu için varsayılan
    doc_date_range = ""
    doc_current_session = ""
    doc_current_event_no = ""
    doc_current_event_desc = ""

    page_records = []

    i = 0
    while i < total_lines:
        line = lines[i]
        m_page = PAGE_RE.match(line)
        if not m_page:
            i += 1
            continue

        p_num = int(m_page.group(1))
        p_total = int(m_page.group(2))
        i += 1

        # Sayfa satırlarını sonraki sayfa ayracına kadar topla
        page_lines = []
        while i < total_lines and not PAGE_RE.match(lines[i]):
            page_lines.append((i + 1, lines[i]))
            i += 1

        # Boş satırları ve sayfa altı hakem / Splash satırlarını filtrele
        meaningful = [
            (lno, l) for lno, l in page_lines
            if l and not any(k in l for k in ["Splash Meet Manager", "BAŞHAKEM", "Registered to Turkiye"])
        ]
        if not meaningful:
            continue

        idx = 0
        first_lno, first_l = meaningful[0]

        # 1. Başlıksız taşma sayfası kontrolü
        is_spill = is_spillover_start(first_l)
        if is_spill:
            page_records.append({
                "Dosya": fn,
                "Sayfa No": p_num,
                "Toplam Sayfa": p_total,
                "Müsabaka Adı": doc_meet_name,
                "Şehir": doc_location,
                "Tarih": doc_date_range,
                "Seans": doc_current_session,
                "Yarış No": doc_current_event_no,
                "Yarış Tanımı": doc_current_event_desc,
                "Başlık Tipi": "BAŞLIKSIZ_TAŞMA",
                "Yarış Satır No": "",
                "Tablo Başlığı": "",
                "Sütun Tipi": "",
                "Sonuç Başlangıç Satır No": first_lno,
                "İlk Sonuç Satırı Örneği": first_l,
                "Durum Notu": "HEADERLESS_PAGE",
            })
            # Bu taşma sayfasında daha sonra yeni bir yarış başlıyor mu kontrol et
            while idx < len(meaningful):
                cur_lno, cur_l = meaningful[idx]
                if EVENT_HEADER_RE.match(cur_l):
                    break
                idx += 1

        if not is_spill:
            p_meet = first_l
            if not doc_meet_name:
                doc_meet_name = p_meet
            idx += 1

            p_city = doc_location
            p_dates = doc_date_range

            # Sayfa üst bilgileri: Şehir, Tarih, Seans
            while idx < len(meaningful):
                cur_lno, cur_l = meaningful[idx]
                if is_city_line(cur_l):
                    parts = cur_l.split(",", 1)
                    p_city = parts[0].strip()
                    p_dates = parts[1].strip() if len(parts) > 1 else ""
                    if p_city:
                        doc_location = p_city
                    if not doc_date_range and p_dates:
                        doc_date_range = p_dates
                    idx += 1
                    continue
                m_s = SESSION_RE.match(cur_l)
                if m_s:
                    sess_txt = m_s.group(1).strip()
                    if m_s.group(2):
                        sess_txt += f" ({m_s.group(2).strip()})"
                    doc_current_session = sess_txt
                    idx += 1
                    continue
                break

        # 2. Sayfadaki tüm yarış bloklarını ayrıştır
        while idx < len(meaningful):
            cur_lno, cur_l = meaningful[idx]
            m_run = RUNNING_EVENT_RE.match(cur_l)
            m_new = EVENT_HEADER_RE.match(cur_l)

            if m_run or m_new:
                ev_type = "DEVAM_BAŞLIĞI" if m_run else "YENİ_YARIŞ"
                m = m_run or m_new
                ev_no = m.group(1)
                ev_desc = f"{m.group(2)}, {m.group(3)} {m.group(4)}"
                if m.group(5):
                    ev_desc += f", {m.group(5)}"
                doc_current_event_no = ev_no
                doc_current_event_desc = ev_desc
                hdr_lno = cur_lno
                idx += 1

                tbl_hdr = ""
                col_type = ""
                res_lno = None
                res_sample = ""

                while idx < len(meaningful):
                    sub_lno, sub_l = meaningful[idx]
                    # Sıradaki yeni bir yarış başlığına geldiysek dur
                    if RUNNING_EVENT_RE.match(sub_l) or EVENT_HEADER_RE.match(sub_l):
                        break

                    # Tarih / Sonuçlar satırı kontrolü
                    m_date = EVENT_DATE_RESULTS_RE.match(sub_l)
                    if m_date:
                        if not doc_date_range:
                            doc_date_range = m_date.group(1)
                        idx += 1
                        continue

                    # Baraj satırları kontrolü
                    if re.search(r"katılım barajları|Puanlar:|[AB][1-4]\b|.*BARAJI?\b", sub_l, re.I):
                        idx += 1
                        continue

                    # Tablo Başlığı kontrolü (Sıra YB ...)
                    m_th = TABLE_HEADER_RE.match(sub_l)
                    if m_th:
                        tbl_hdr = sub_l
                        col_word = m_th.group(1).lower()
                        col_type = (
                            "YAŞ / AGE" if col_word in ["yaş", "age"]
                            else ("TIME (D.YILI YOK)" if col_word == "time" else "YB (DOĞUM YILI)")
                        )
                        idx += 1
                        # Tablo başlığından sonraki ilk satır sonuç başlangıcıdır
                        if idx < len(meaningful):
                            res_lno = meaningful[idx][0]
                            res_sample = meaningful[idx][1]
                        break

                    # Tablo başlığı basılmamış ama doğrudan sporcu veya alt yaş grubu gelmişse
                    m_res = RESULT_START_RE.match(sub_l)
                    m_age = AGE_SUBHEADER_RE.match(sub_l)
                    if m_res or m_age or sub_l.startswith("SW ") or sub_l.startswith("(Zaman:"):
                        res_lno = sub_lno
                        res_sample = sub_l
                        break

                    idx += 1

                note = "OK"
                if not tbl_hdr:
                    note = "DEVAM_TABLOSUZ"
                elif not res_lno:
                    note = "BAŞLIK_SAYFA_SONUNDA"

                page_records.append({
                    "Dosya": fn,
                    "Sayfa No": p_num,
                    "Toplam Sayfa": p_total,
                    "Müsabaka Adı": doc_meet_name,
                    "Şehir": doc_location,
                    "Tarih": doc_date_range,
                    "Seans": doc_current_session,
                    "Yarış No": ev_no,
                    "Yarış Tanımı": ev_desc,
                    "Başlık Tipi": ev_type,
                    "Yarış Satır No": hdr_lno,
                    "Tablo Başlığı": tbl_hdr,
                    "Sütun Tipi": col_type,
                    "Sonuç Başlangıç Satır No": res_lno or "",
                    "İlk Sonuç Satırı Örneği": res_sample,
                    "Durum Notu": note,
                })
            else:
                idx += 1

    return page_records


def generate_all_headers_csv(output_csv: str = "output/sayfa_basliklari.csv"):
    files = sorted([
        f for f in glob.glob("output/txt/ankara/*.txt")
        if not os.path.basename(f).replace(".txt", "").isdigit()
    ])
    print(f"[*] {len(files)} dosya taranıyor...")

    all_records = []
    for f in files:
        records = parse_file_headers(f)
        all_records.extend(records)

    out_p = Path(output_csv)
    out_p.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = [
        "Dosya",
        "Sayfa No",
        "Toplam Sayfa",
        "Müsabaka Adı",
        "Şehir",
        "Tarih",
        "Seans",
        "Yarış No",
        "Yarış Tanımı",
        "Başlık Tipi",
        "Yarış Satır No",
        "Tablo Başlığı",
        "Sütun Tipi",
        "Sonuç Başlangıç Satır No",
        "İlk Sonuç Satırı Örneği",
        "Durum Notu",
    ]

    with open(out_p, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(all_records)

    print(f"[+] Başarıyla kaydedildi: {out_p} ({len(all_records):,} başlık kaydı)")


if __name__ == "__main__":
    generate_all_headers_csv()
