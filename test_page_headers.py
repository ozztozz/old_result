"""
Page Header Parser and Tester
==============================
Sadece sayfa başlıklarını (PAGE_HEADER) bir durum makinesi (State Machine)
ile ayrıştırır, doğrular ve sonuçları raporlar.
"""

import glob
import json
import os
import re
from dataclasses import dataclass, asdict
from typing import Optional, List, Dict

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
    r"^\s*Sıra\s+(YB|Yaş|Age|Time|Zaman|Derece|Sporcu)\b", re.I
)


@dataclass
class ParsedPageHeader:
    file_name: str
    page_number: int
    total_pages: int
    meet_name: str
    location: str
    date_range: str
    session: Optional[str] = None
    event_no: Optional[str] = None
    event_desc: Optional[str] = None
    event_type: Optional[str] = None  # "NEW_EVENT" veya "CONTINUATION"
    event_date: Optional[str] = None
    event_time: Optional[str] = None
    table_column_mode: Optional[str] = None  # "YB" veya "AGE"
    header_lines_consumed: int = 0
    is_valid: bool = False
    warning: Optional[str] = None


def parse_page_headers_from_file(file_path: str) -> List[ParsedPageHeader]:
    fn = os.path.basename(file_path)
    lines = [l.strip() for l in open(file_path, encoding="utf-8")]
    total_lines = len(lines)

    headers: List[ParsedPageHeader] = []
    
    # Dosya düzeyinde bilinenler (sayfalardan devralınan state)
    doc_meet_name = ""
    doc_location = ""
    doc_date_range = ""
    doc_current_session = ""
    doc_current_event_no = ""
    doc_current_event_desc = ""

    i = 0
    while i < total_lines:
        line = lines[i]
        m_page = PAGE_RE.match(line)
        if not m_page:
            i += 1
            continue

        p_num = int(m_page.group(1))
        p_total = int(m_page.group(2))
        start_idx = i
        i += 1

        # Sayfa Başlığı Ayrıştırma Durum Makinesi
        # 0: Müsabaka Adı Bekleniyor
        # 1: Şehir / Tarih Bekleniyor
        # 2: Detaylar (Seans, Yarış, Tablo Başlığı)
        header_step = 0
        
        page_meet = ""
        page_loc = ""
        page_dates = ""
        page_session = None
        page_ev_no = None
        page_ev_desc = None
        page_ev_type = None
        page_ev_date = None
        page_ev_time = None
        page_col_mode = None
        warning = None

        while i < total_lines:
            cur_line = lines[i]
            # Eğer yeni bir sayfa ayracına denk geldiysek bu sayfa bitti demektir
            if PAGE_RE.match(cur_line):
                break

            if not cur_line:
                i += 1
                continue

            if header_step == 0:
                # Sayfa Başlığı Kontrolü: Bu sayfa bir başlıkla mı başlıyor yoksa önceki sayfadan sarkan sonuç/DQ ile mi?
                is_result_or_dq = bool(
                    re.match(r"^(?:SW\s+\d|\(Zaman:|disk\.|terk\.|DNS|\d+\.|\(Fd\)|\(Tk\)|\(Td\)|td\.)", cur_line, re.I)
                )

                if is_result_or_dq or (doc_meet_name and cur_line != doc_meet_name and not cur_line.startswith("Yarış")):
                    # Bu sayfanın başında üstbilgi yok! Doğrudan sonuç/DQ gövdesiyle başlıyor.
                    # Müsabaka ve şehir bilgileri önceki sayfadan devralınır.
                    page_meet = doc_meet_name
                    page_loc = doc_location
                    page_dates = doc_date_range
                    warning = "HEADERLESS_PAGE"
                    break

                page_meet = cur_line
                if not doc_meet_name:
                    doc_meet_name = page_meet
                header_step = 1
                i += 1
                continue

            elif header_step == 1:
                # 2. Satır: Şehir ve Tarih Aralığı (Sadece gerçek şehir satırı ise tüket)
                u = cur_line.strip().upper()
                is_city = False
                if not (u.startswith("YARIŞ") or u.startswith("YARIS") or "SEANSI" in u or "SONUÇLAR" in u or "SONUCLAR" in u or u.startswith("SIRA")):
                    if any(u.startswith(c) for c in ["ANKARA", "İSTANBUL", "İZMİR", "BURSA", "ANTALYA", "TRABZON"]):
                        is_city = True
                    elif re.search(r"\d{1,2}[\.-]\s*(?:\d{1,2}[\.-]\s*)?\d{4}", cur_line) and "," in cur_line:
                        is_city = True

                if is_city:
                    if "," in cur_line:
                        parts = cur_line.split(",", 1)
                        page_loc = parts[0].strip()
                        page_dates = parts[1].strip()
                    else:
                        page_loc = cur_line.strip()
                        page_dates = doc_date_range

                    if not doc_location:
                        doc_location = page_loc
                    if not doc_date_range and page_dates:
                        doc_date_range = page_dates
                    i += 1
                else:
                    page_loc = doc_location or "ANKARA"
                    page_dates = doc_date_range

                header_step = 2
                continue

            elif header_step == 2:
                # 3. Adım: Başlık Detayları
                m_sess = SESSION_RE.match(cur_line)
                if m_sess:
                    page_session = m_sess.group(1).strip()
                    if m_sess.group(2):
                        page_session += f" ({m_sess.group(2).strip()})"
                    doc_current_session = page_session
                    i += 1
                    continue

                m_run = RUNNING_EVENT_RE.match(cur_line)
                if m_run:
                    page_ev_no = m_run.group(1)
                    page_ev_desc = f"{m_run.group(2)}, {m_run.group(3)} {m_run.group(4)}"
                    if m_run.group(5):
                        page_ev_desc += f", {m_run.group(5)}"
                    page_ev_type = "CONTINUATION"
                    doc_current_event_no = page_ev_no
                    doc_current_event_desc = page_ev_desc
                    i += 1
                    continue

                m_ev = EVENT_HEADER_RE.match(cur_line)
                if m_ev:
                    page_ev_no = m_ev.group(1)
                    page_ev_desc = f"{m_ev.group(2)}, {m_ev.group(3)} {m_ev.group(4)}"
                    if m_ev.group(5):
                        page_ev_desc += f", {m_ev.group(5)}"
                    page_ev_type = "NEW_EVENT"
                    doc_current_event_no = page_ev_no
                    doc_current_event_desc = page_ev_desc
                    i += 1
                    continue

                m_date = EVENT_DATE_RESULTS_RE.match(cur_line)
                if m_date:
                    page_ev_date = m_date.group(1)
                    if m_date.group(2):
                        page_ev_time = m_date.group(2)
                    i += 1
                    continue

                # Baraj ve Puan standartları
                if re.search(r"katılım barajları|Puanlar:|[AB][1-4]\b|.*BARAJI?\b", cur_line, re.I):
                    i += 1
                    continue

                # Tablo Sütun Başlığı
                m_tbl = TABLE_HEADER_RE.match(cur_line)
                if m_tbl:
                    col_word = m_tbl.group(1).lower()
                    page_col_mode = "AGE" if col_word in ["yaş", "age"] else "YB"
                    i += 1
                    # Tablo başlığı görüldüğünde sayfa başlığı tamamlanmıştır!
                    break

                # Alt yaş grubu başlığı (Örn: "11 yaş")
                if re.match(r"^\d{1,2}(?:\s*-\s*\d{1,2})?\s*(?:yaş.*)?$", cur_line, re.I):
                    i += 1
                    continue

                # Eğer bir sonuç satırına (1. İsim veya disk. vb.) geldiysek başlık bitmiştir
                if re.match(r"^(?:\d+\.|disk\.|terk\.|DNS|\(Fd\)|\(Tk\)|\(Td\)|td\.)", cur_line, re.I):
                    break

                # Bilinmeyen bir satırsa başlık bitti varsayıp gövdeye geç
                break

        consumed = i - start_idx
        is_valid = bool(page_meet and (page_loc or doc_location))

        header_obj = ParsedPageHeader(
            file_name=fn,
            page_number=p_num,
            total_pages=p_total,
            meet_name=page_meet or doc_meet_name,
            location=page_loc or doc_location,
            date_range=page_dates or doc_date_range,
            session=page_session or doc_current_session,
            event_no=page_ev_no or doc_current_event_no,
            event_desc=page_ev_desc or doc_current_event_desc,
            event_type=page_ev_type or ("CONTINUATION" if doc_current_event_no else None),
            event_date=page_ev_date,
            event_time=page_ev_time,
            table_column_mode=page_col_mode,
            header_lines_consumed=consumed,
            is_valid=is_valid,
            warning=warning,
        )
        headers.append(header_obj)

    return headers


def main():
    files = sorted(glob.glob("output/txt/ankara/*.txt"))
    native_files = [f for f in files if not os.path.basename(f).replace(".txt", "").isdigit()]

    print(f"[*] Toplam {len(native_files)} metin tabanlı yarış dosyası inceleniyor...\n")

    total_pages = 0
    valid_pages = 0
    new_event_pages = 0
    continuation_pages = 0
    age_col_pages = 0
    yb_col_pages = 0

    all_parsed_headers = []

    for f in native_files:
        p_headers = parse_page_headers_from_file(f)
        total_pages += len(p_headers)
        for h in p_headers:
            all_parsed_headers.append(h)
            if h.is_valid:
                valid_pages += 1
            if h.event_type == "NEW_EVENT":
                new_event_pages += 1
            elif h.event_type == "CONTINUATION":
                continuation_pages += 1
            if h.table_column_mode == "AGE":
                age_col_pages += 1
            elif h.table_column_mode == "YB":
                yb_col_pages += 1

    print("==========================================================")
    print("           SAYFA BAŞLIKLARI AYRIŞTIRMA ÖZETİ              ")
    print("==========================================================")
    print(f"İncelenen Dosya Sayısı     : {len(native_files):,}")
    print(f"Toplam Sayfa Sayısı        : {total_pages:,}")
    print(f"Başarıyla Ayrıştırılan     : {valid_pages:,} (%{valid_pages/total_pages*100:.2f})")
    print(f"Yeni Yarış Başlatan Sayfa  : {new_event_pages:,}")
    print(f"Önceki Yarışı Sürdüren     : {continuation_pages:,}")
    print(f"YB Sütunlu Sayfalar        : {yb_col_pages:,}")
    print(f"Yaş/Age Sütunlu Sayfalar   : {age_col_pages:,}")
    print("==========================================================\n")

    # Kullanıcının sorduğu spesifik dosyalardan örnekler göster
    target_examples = [
        "10-Yas-Ankara-Il-Baraj-Gecme-Musabakasi-Sonuc-Listesi.txt",
        "Okul-Sporlari-Etimesgut-2-Kume-Sonuc.txt",
        "14-16-Ekim-2022-Ankara-3-Vize-Sonuclari.txt"
    ]

    for target in target_examples:
        print(f"--- ÖRNEK DOSYA: {target} ---")
        ex_headers = [h for h in all_parsed_headers if h.file_name == target]
        for h in ex_headers[:5]:
            ev_str = f"Yarış {h.event_no}: {h.event_desc}" if h.event_no else "Yarış Bilgisi Yok"
            sess_str = f" | {h.session}" if h.session else ""
            col_str = f" | Sütun: {h.table_column_mode}" if h.table_column_mode else ""
            print(f"  Sayfa {h.page_number:2d}/{h.total_pages:2d} -> [{h.event_type or 'START':12s}] {h.meet_name} ({h.location}, {h.date_range}){sess_str}")
            print(f"             Detay: {ev_str}{col_str}")
        print()


if __name__ == "__main__":
    main()
