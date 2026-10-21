#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
create_swimming_database.py
===========================
Master yüzücü sonuçları (tum_bireysel_yuzucu_sonuclari_master.csv) veri setini
akıllı yaş/doğum yılı hesaplama algoritması ile tekilleştirip ilişkisel
SQLite veritabanına aktarır.

Tekilleştirme Mantığı:
1. Sporcu adı öncelikle tekil varsayılarak yarışları toplanır.
2. Yarış tarihi (yıl) ve yarışın yaş grubundan yararlanılarak sporcunun gerçek doğum yılı hesaplanır.
3. Fiziksel yaş kısıtı (en az 7 yaş) uygulanarak YB (Doğum yılı son 2 hanesi) ve Yaş (müsabaka anındaki yaş) ayrıştırılır.
4. Doğum yılı kümeleri (±1 yıl doğum günü toleransı) oluşturularak aynı ada sahip farklı kişiler (adaçlar) ayrıştırılır, aynı kişinin farklı yaşlardaki yarışları tek profilde birleştirilir.
"""

import os
import sys
import csv
import re
import sqlite3
import time
from collections import defaultdict, Counter
from typing import Dict, Tuple, Optional, List, Set, Any

MASTER_CSV_PATH = "output/tum_bireysel_yuzucu_sonuclari_master.csv"
DB_PATH = "output/yuzme_veritabani.db"

CITY_HEADERS = {
    'İSTANBUL', 'ISTANBUL', 'ANKARA', 'GAZİANTEP', 'GAZIANTEP', 'İZMİR', 'IZMIR',
    'BURSA', 'TRABZON', 'EDİRNE', 'EDIRNE', 'ANTALYA', 'KAYSERİ', 'KAYSERI',
    'SAMSUN', 'KOCAELİ', 'KOCAELI', 'MERSİN', 'MERSIN', 'ADANA', 'ALANYA',
    'ÇANAKKALE', 'CANAKKALE', 'ISPARTA', 'KARABÜK', 'KARABUK', 'NİĞDE', 'NIGDE',
    'BALIKESİR', 'BALIKESIR', 'GEBZE', 'DENİZLİ', 'DENIZLI', 'SAKARYA', 'MALATYA'
}

FILE_DATE_MAP: Dict[str, Tuple[str, str]] = {
    '1766388051.txt': ('2025-12-20', '2025-12-20'),
    '1766996971.txt': ('2025-12-24', '2025-12-28'),
    '1773055987.txt': ('2026-02-25', '2026-03-02'),
    '2-3-MART-2019-OKULSPORLARI-GENCLER-GRUP-MUSABAKALARI---ANTALYA---ALANYA-TUM-SONUCLAR.txt': ('2019-03-02', '2019-03-03'),
    '2011-nisan-turkiyesampiyonasi-istanbul.txt': ('2011-04-06', '2011-04-10'),
    '2020-OKULSPORLARI-YUZME-YILDIZLAR-GRUP-YARISMALARI.txt': ('2020-02-29', '2020-03-02'),
    'ANALIG-FINAL-3103-242017_1.txt': ('2017-03-31', '2017-04-02'),
    'BOLGE-KARMALARI-ISPARTA--SONUCLAR.txt': ('2018-10-13', '2018-10-14'),
    'BOLGEKARMAANKARASONUC.txt': ('2019-11-30', '2019-12-01'),
    'GAZIANTEP-OKUL-YILDIZ-GRUP.txt': ('2020-02-29', '2020-03-02'),
    'MERSIN-TOPLU-SONUC.txt': ('2026-07-03', '2026-07-05'),
    'Musabaka-Sonu-Toplu-Sonuc.txt': ('2018-05-13', '2018-05-13'),
    'Okul-Sporlari-Kucukler-Il-Birinciligi-Sonuc-Listesi.txt': ('2023-04-12', '2023-04-14'),
    'Okul-Sporlari-Kucukler-Yuzme-Il-Birinciligi-Sonuc-Listesi.txt': ('2024-02-07', '2024-02-07'),
    'Okul-Sporlari-Minikler-B-Yuzme-Il-Birinciligi-Sonuc-Listesi.txt': ('2023-05-10', '2023-05-10'),
    'SONUCPUAN.txt': ('2023-12-20', '2023-12-24'),
    'Sonuclar-Minikler-B.txt': ('2024-06-07', '2024-06-07'),
    'TOPLU-SONUC-merged.txt': ('2025-08-04', '2025-08-09'),
    'TOPLU-SONUCLAR.txt': ('2019-10-18', '2019-10-18'),
    'TUM-SONUC-5.txt': ('2017-06-02', '2017-06-04'),
    'TYF-10-11-12-YAS-UGL-MUSABAKASI-TOPLU-SONUCLAR-BALIKESIR.txt': ('2026-07-03', '2026-07-05'),
    'Yaris-Sonuclari.txt': ('2020-02-29', '2020-03-02'),
    'toplu-sonuc2811-0112.txt': ('2024-11-28', '2024-12-01'),
    'tr-sampiyonasi.txt': ('2022-12-25', '2022-12-29')
}

FILE_MEET_NAME_MAP: Dict[str, str] = {
    '1764667479.txt': 'Türkiye Yüzme Federasyonu Vedia Nil Apak Anısına Arena 11-12 Yaş Ulusal Gelişim Ligi Türkiye Finali',
    '182212.txt': 'Türkiye Turkcell Kısa Kulvar Bireysel Açık Yaş ve Gençler Yüzme Şampiyonası',
    '2014-1416mart-anadoluyildizlariyarifinalmusabakasonuc.txt': 'Anadolu Yıldızları Çanakkale Yarı Final Müsabakaları',
    '2014-mayis-anadoluyildilarifinal-SAKARYA.txt': 'Anadolu Yıldızları Final Yarışı (Sakarya)',
    '2016-29-31ocak-sampiyonkulaclar-marmaris.txt': 'Şampiyon Kulaçlar (Olimpik Kulaçlar Kış Final) Müsabakası (Marmaris)',
    '2016-olimpikkulaclarfinal-gazinatep.txt': '23 Nisan Çocuk Şenlikleri - Olimpik Kulaçlar Yaz Final Müsabakası (Gaziantep)',
    '2017-temmuz-11-12yasturkiyefinali-bursa.txt': '11-12 Yaş Ulusal Gelişim Projesi Türkiye Finali (Bursa 2017)',
    '20241220-kisa-kulvar.txt': 'Türkiye Turkcell Kısa Kulvar Açık Yaş ve Gençler Yüzme Şampiyonası (İstanbul 2020)',
    '3-6-AGUSTOS-toplu-sonuc.txt': 'Türkiye Turkcell Açık Yaş Yaz Yüzme Şampiyonası (İstanbul 2019)',
    'ANALIG-KAYSERI-SONUCLARI.txt': 'Analig Kayseri Yarı Final Müsabakaları',
    'ANALIG-TUM-SONUCLAR-canakkale.txt': 'Analig Çanakkale Yarı Final Müsabakaları',
    'bursa12-yas-final.txt': 'TYF 12 Yaş Ulusal Gelişim Projesi Ligi Final Müsabakası (Bursa 2024)',
    'denizli.txt': 'TYF 12 Yaş Ulusal Gelişim Projesi Ligi Final Müsabakası (Denizli 2023)',
    'edirne.txt': 'TYF 12 Yaş Ulusal Gelişim Projesi Ligi Final Müsabakası (Edirne 2021)',
    'gaziantep24281221_1.txt': 'Türkiye Turkcell Kısa Kulvar Açık Yaş ve Gençler Yüzme Şampiyonası (Gaziantep 2021)',
    'mersin12-yas-final.txt': 'TYF 12 Yaş Ulusal Gelişim Projesi Ligi Final Müsabakası (Mersin 2022)',
    'nigde-sonuc.txt': 'Analig Niğde Yarı Final Müsabakaları',
    'SAMSUN-TOTAL-SONUC.txt': 'TYF 11 Yaş Ulusal Gelişim Projesi Ligi Final Müsabakası (Samsun 2022)',
    'samsun.txt': 'TYF 11 Yaş Ulusal Gelişim Projesi Ligi Final Müsabakası (Samsun 2023)',
    'samsun11-yas-fianl.txt': 'TYF 11 Yaş Ulusal Gelişim Projesi Ligi Final Müsabakası (Samsun 2024)',
    'TEKIRDAG-ANALIG-YILDIZLAR-LIGI-YARI-FINAL-TOPLU-SONUCLARI.txt': 'Tekirdağ Analig Yıldızlar Ligi Yarı Final Müsabakaları',
    'TOPLU-SONUCLAR-PDF.txt': '2018-2019 Sezonu Analig Yıldızlar Ligi Yarı Finali Yüzme Müsabakaları (Elazığ)',
    'TOTAL-SONUC_1.txt': '11-12 Yaş Ulusal Gelişim Projesi Türkiye Finali (Bursa)',
    'trabzon.txt': 'TYF 11 Yaş Ulusal Gelişim Projesi Ligi Final Müsabakası (Trabzon 2021)',
    'TUM-SEANSLAR-SONUC-LISTESI-ordu.txt': 'Anadolu Yıldızlar Ligi Yarı Final Müsabakası (Ordu)',
    'TUM-SEANSLAR-SONUC-LISTESI-ordu_1.txt': 'Anadolu Yıldızlar Ligi Yarı Final Müsabakası (Ordu)',
    'YILDIZLAR-TURKIYE-FINALI-TOPLU-SONUCLAR.txt': 'Yıldızlar Türkiye Finali (Kocaeli 2018)'
}


def clean_meet_name(fname: str, raw_m: str) -> str:
    """Yarış 1... veya Event 1... gibi etkinlik başlıklarını gerçek müsabaka adıyla değiştirir."""
    if fname in FILE_MEET_NAME_MAP:
        return FILE_MEET_NAME_MAP[fname]
    m_clean = raw_m.strip()
    if re.match(r'^(?:Yar[ıiIİ][şsSŞ]|Event)\s+\d+', m_clean, re.I) or '4 x' in m_clean:
        base = fname.replace('.txt', '').replace('-', ' ').replace('_', ' ').strip()
        return base.title()
    return m_clean


TR_NORM_MAP = str.maketrans("çğıöşüÇĞİÖŞÜ", "cgiosuCGIOSU")


def norm(s: str) -> str:
    """Türkçe karakterleri ve boşlukları arındırarak karşılaştırma anahtarı üretir."""
    if not s:
        return ""
    clean = s.translate(TR_NORM_MAP).lower()
    return re.sub(r"[^a-z0-9]", "", clean)


def is_school_team(club_name: str) -> bool:
    """
    Bir kulüp adının resmi yüzme spor kulübü mü yoksa okul müsabakası (MEB)
    temsili mi olduğunu belirler.
    """
    if not club_name:
        return False
    name = club_name.strip()
    name_lower = name.lower()

    if name_lower == 'ferdi':
        return False

    has_club_suffix = bool(re.search(
        r'(?:spor\s*kul[uü]b[uü]|(?:\b|[_\s])sk\b|(?:\b|[_\s])gsk\b|(?:\b|[_\s])skd\b|y[uü]zme\s*kul[uü]b[uü]|ihtisas|derne[gğ]i|belediye\s*spor|belediyespor|kolejliler)',
        name_lower
    ))
    if has_club_suffix:
        return False

    has_school_word = bool(re.search(
        r'(?:ilkokul|ortaokul|lise|imam\s*hatip|i\.?[oö]\.?okulu|kolej|okullar[ıi]|anaokul|bilsen|bilsem|kamp[uü]s)',
        name_lower
    ))
    if has_school_word:
        return True

    if re.search(r'(?:okulu|lisesi|koleji)$', name_lower):
        return True

    return False


def clean_swimmer_name_raw(s: str) -> str:
    """Okul etiketleri, virgüller ve yaygın OCR kalıplarını temizler."""
    if not s:
        return ""
    c = re.sub(r"\(?(?:Tk|Td|Fd|tk|td|fd|TK|TD|FD)\)?[\.\)]?\s*", "", s).strip()
    c = re.sub(r"ALTİ", "ALTI", c)
    if "," in c:
        parts = [p.strip() for p in c.split(",") if p.strip()]
        if len(parts) == 2:
            c = f"{parts[1]} {parts[0]}"
    return c


def sorted_words_norm(s: str) -> str:
    """Kelimelerin sırasından bağımsız olarak sıralı normalize anahtar döner."""
    c = clean_swimmer_name_raw(s)
    words = [norm(w) for w in c.split() if norm(w)]
    return " ".join(sorted(words)) if words else norm(c)


def score_swimmer_name(name: str, freq: int) -> tuple:
    """İsim varyasyonları arasından en doğru resmi yazımı seçer."""
    tr_chars = set("çğıöşüÇĞİÖŞÜ")
    words = name.split()

    is_standard_casing = 0
    if len(words) >= 2:
        if words[-1].isupper() and not words[0].isupper():
            is_standard_casing = 10
        elif words[-1].isupper():
            is_standard_casing = 5

    tr_score = sum(2 for c in name if c in tr_chars)
    return (is_standard_casing, tr_score, freq, len(name))


def is_valid_result_row(r: dict) -> bool:
    """Başlık, şehir bandı, baraj süreleri gibi yarış dışı satırları eler."""
    sp = r.get("Sporcu", "").strip()
    kl = r.get("Kulüp", "").strip()
    ham = r.get("Ham Satır", "").strip()

    if not sp or not kl:
        return False

    # 1. Sporcu adı kontrolleri
    # Gerçek isimlerde yer almayacak karakterler (baraj/tablo parçaları)
    if any(c in sp for c in [':', '/', '=', '+', '%', '$', '<', '>', '_', '|', ';', '@', '*', '?', '\\']):
        return False
    # Süre formatı (örn: 10:46.19 veya 12: 10:46)
    if re.search(r'\d+[:\.]\d{2}', sp):
        return False
    # Baraj seviyesi kodları (A1, A2, A3, A4, B1, B2)
    if re.search(r'\b[AB][1-4]\b', sp, re.I):
        return False
    # Yaş desenleri (örn: '12 YAŞ', 'YAŞ 12', '19 +')
    if re.search(r'\b\d{1,2}\s*YAŞ\b', sp, re.I) or re.search(r'\bYAŞ\s*\d{1,2}\b', sp, re.I) or re.search(r'\b\d{1,2}\s*\+\b', sp):
        return False
    # Rakamla veya mesafe koduyla başlayan isim olamaz (örn: '19 +', '50m', '100m')
    if re.match(r'^\d+', sp) or re.match(r'^\d+m\b', sp, re.I):
        return False
    # En az iki kelimeden oluşmalı
    if len(sp.split()) < 2:
        return False
    # Şehir başlıkları
    if sp.upper() in CITY_HEADERS:
        return False

    # 2. Kulüp adı kontrolleri
    if any(c in kl for c in [':', '=', '<', '>', '%', '$', ';']) or kl.startswith('/'):
        return False
    if re.search(r'\b[AB][1-4]\b', kl, re.I) and any(c in kl for c in [':', '.', '/', '=']):
        return False
    # Kulüp kısaltmaları: En az 3 karakter veya bilinen 2 karakterli kulüpler ('FB', 'GS', 'SK')
    if re.match(r'^\d+\.\s*-\s*$', kl) or (len(kl) < 3 and kl not in ('FB', 'GS', 'SK')):
        return False

    # 3. Baraj ve standart anahtar kelimeleri
    ham_upper = ham.upper()
    kl_upper = kl.upper()
    sp_upper = sp.upper()
    if any(k in ham_upper or k in kl_upper or k in sp_upper for k in [
        'KATILIM BARAJI', 'MİLLİ TAKIM BARAJI', 'MILLI TAKIM BARAJI', 
        'BARAJI GEÇTİ', 'BARAJINI GEÇTİ', 'STANDARTLARI'
    ]):
        return False

    return True


def parse_date_range(date_str: str, fname: str) -> Tuple[Optional[str], Optional[str]]:
    """Tarih metnini ve dosya adını kullanarak (başlangıç, bitiş) ISO tarihini döner."""
    if not date_str or not date_str.strip():
        return FILE_DATE_MAP.get(fname, (None, None))

    s = date_str.strip()

    m = re.match(r'^(\d{1,2})\.\s*-\s*(\d{1,2})\.(\d{1,2})\.(\d{4})$', s)
    if m:
        d1, d2, m2, y = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
        return f'{y:04d}-{m2:02d}-{d1:02d}', f'{y:04d}-{m2:02d}-{d2:02d}'

    m = re.match(r'^(\d{1,2})-(\d{1,2})\.(\d{1,2})\.(\d{4})$', s)
    if m:
        d1, d2, m2, y = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
        return f'{y:04d}-{m2:02d}-{d1:02d}', f'{y:04d}-{m2:02d}-{d2:02d}'

    m = re.match(r'^(\d{1,2})\.(\d{1,2})\.\s*-\s*(\d{1,2})\.(\d{1,2})\.(\d{4})$', s)
    if m:
        d1, m1, d2, m2, y = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5))
        return f'{y:04d}-{m1:02d}-{d1:02d}', f'{y:04d}-{m2:02d}-{d2:02d}'

    m = re.match(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$', s)
    if m:
        d, m_val, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
        return f'{y:04d}-{m_val:02d}-{d:02d}', f'{y:04d}-{m_val:02d}-{d:02d}'

    return FILE_DATE_MAP.get(fname, (None, None))


def build_file_column_semantics() -> Dict[str, str]:
    """
    output/txt/ altındaki dosyaların tablo başlığını tarayarak
    sütunun 'YB' (Doğum Yılı) mi yoksa 'AGE' (Yaş) mı olduğunu tespit eder.
    """
    import glob
    semantics = {}
    for p in glob.glob('output/txt/**/*.txt', recursive=True):
        fname = os.path.basename(p)
        with open(p, encoding='utf-8', errors='ignore') as f:
            for _ in range(500):
                line = f.readline()
                if not line:
                    break
                if any(w in line for w in ['Sıra', 'Rank', 'S.N.', 'Sira']):
                    words = [w.strip() for w in line.split()]
                    if any(w.upper() in ('YB', 'Y.B.', 'DOĞUM', 'YOB', 'D.YILI') for w in words):
                        semantics[fname] = 'YB'
                        break
                    elif any(w.lower() in ('yaş', 'yas', 'age') for w in words):
                        semantics[fname] = 'AGE'
                        break
    return semantics


def deduce_birth_year(raw_v: str, meet_year: Optional[int], yg: str = '', fname: str = '', file_semantics: Dict[str, str] = None) -> Optional[int]:
    """
    Yarış yılı, ham değer, yaş grubu ve dosya başlık semantiğini kullanarak yüzücünün doğum yılını hesaplar.
    """
    if not raw_v or not raw_v.isdigit():
        return None
    val = int(raw_v)

    # 4 haneli doğum yılı (örn: 1998, 2005)
    if 1900 <= val <= 2026:
        return val

    # 2 haneli >= 50: (örn: 98 -> 1998, 85 -> 1985)
    if 50 <= val <= 99:
        return 1900 + val

    # 2 haneli < 7: (örn: 00..06 -> 2000..2006, 0-6 yaş arası müsabaka yüzücüsü olamayacağından doğum yılıdır)
    if 0 <= val < 7:
        return 2000 + val

    # val 7 ile 49 arasında:
    # 1. Dosya başlığında sütunun AGE (Yaş) veya YB olduğu biliniyorsa:
    if file_semantics:
        f_sem = file_semantics.get(fname)
        if f_sem == 'AGE' and meet_year:
            return meet_year - val
        if f_sem == 'YB':
            return 2000 + val

    if not meet_year:
        return 2000 + val if val <= 26 else None

    # 2. Müsabaka yaş grubunda aralık varsa (örn: '13 - 15 yaşları arası', '11 - 12 yaş'):
    m_range = re.search(r'(\d{1,2})\s*-\s*(\d{1,2})\s*yaş', yg)
    if m_range:
        min_a, max_a = int(m_range.group(1)), int(m_range.group(2))
        # Eğer val [min_a, max_a] aralığındaysa val kesinlikle yaştır
        if min_a <= val <= max_a:
            return meet_year - val
        # Eğer (meet_year - (2000 + val)) aralıktaysa val doğum yılıdır
        age_if_yb = meet_year - (2000 + val)
        if min_a <= age_if_yb <= max_a:
            return 2000 + val

    # 3. Tekli yaş grubu (örn: '10 yaş', '14 yaş'):
    yg_match = re.search(r'(\d{1,2})\s*yaş', yg)
    if yg_match:
        yg_age = int(yg_match.group(1))
        if val == yg_age:
            return meet_year - val
        if (meet_year - (2000 + val)) == yg_age:
            return 2000 + val

    # 4. Fiziksel Yaş Kuralı: Bir yüzücü yarışta en az 7 yaşında olmalıdır.
    age_if_birth_year = meet_year - (2000 + val)
    if age_if_birth_year < 7:
        if 7 <= val <= 45:
            return meet_year - val

    # 5. Gelecek tarih kuralı: yarış yılı < 2000+val ise henüz doğmamış olamaz, yaştır
    if meet_year < 2000 + val:
        return meet_year - val

    # Varsayılan: Son yıllarda Meet Manager YB sütununu (2000+val) kullanır.
    return 2000 + val


def build_database():
    start_time = time.time()
    print("=" * 70)
    print("      TÜRKİYE YÜZME FEDERASYONU VERİTABANI OLUŞTURULUYOR")
    print("   (Akıllı Yaş & Doğum Yılı Hesaplamalı Tekilleştirme Motoru)")
    print("=" * 70)
    print(f"Kaynak Veri Seti : {MASTER_CSV_PATH}")
    print(f"Hedef Veritabanı : {DB_PATH}")

    if not os.path.exists(MASTER_CSV_PATH):
        print(f"[-] Hata: {MASTER_CSV_PATH} bulunamadı!")
        sys.exit(1)

    # -------------------------------------------------------------------------
    # ADIM 1: CSV Okuma ve Filtreleme
    # -------------------------------------------------------------------------
    print("\n>>> ADIM 1: Master sonuçlar yükleniyor ve temizleniyor...")
    
    raw_rows = []
    with open(MASTER_CSV_PATH, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for r in reader:
            raw_rows.append(r)

    rows = [r for r in raw_rows if is_valid_result_row(r)]
    filtered_cnt = len(raw_rows) - len(rows)
    print(f"[+] Toplam {len(raw_rows):,} satırdan {len(rows):,} geçerli yarış sonucu seçildi ({filtered_cnt:,} başlık/baraj satırı elendi) ({time.time() - start_time:.2f}s).")

    # -------------------------------------------------------------------------
    # ADIM 2: Kulüpler Tablosu Hazırlığı
    # -------------------------------------------------------------------------
    print("\n>>> ADIM 2: Kulüpler (Takımlar) listesi ve istatistikleri hazırlanıyor...")
    
    club_stats = defaultdict(lambda: {
        "swimmer_names": set(),
        "race_count": 0,
        "okul_races": 0,
        "fed_races": 0,
        "min_date": "9999-99-99",
        "max_date": "0000-00-00"
    })

    for r in rows:
        kl = r.get("Kulüp", "").strip()
        sp = r.get("Sporcu", "").strip()
        t_raw = r.get("Tarih", "").strip()
        fname = r.get("Dosya Adı", "").strip()

        if not kl:
            continue

        d1, d2 = parse_date_range(t_raw, fname)
        start_d = d1 or "1900-01-01"
        end_d = d2 or start_d

        cs = club_stats[kl]
        cs["race_count"] += 1
        m_adi = r.get("Müsabaka Adı", "").lower()
        if "okul spor" in m_adi or "okulspor" in m_adi or "okullar" in m_adi:
            cs["okul_races"] += 1
        else:
            cs["fed_races"] += 1

        if sp:
            cs["swimmer_names"].add(sp)

        if start_d != "1900-01-01":
            if start_d < cs["min_date"]:
                cs["min_date"] = start_d
            if end_d > cs["max_date"]:
                cs["max_date"] = end_d

    sorted_clubs = sorted(club_stats.keys())
    club_id_map: Dict[str, int] = {}
    club_insert_rows = []

    for c_id, kl in enumerate(sorted_clubs, start=1):
        club_id_map[kl] = c_id
        cs = club_stats[kl]
        min_d = cs["min_date"] if cs["min_date"] != "9999-99-99" else None
        max_d = cs["max_date"] if cs["max_date"] != "0000-00-00" else None

        in_school_meet = (cs["okul_races"] > 0)
        has_school_kw = is_school_team(kl)
        has_sk = bool(re.search(r'(?:spor\s*kul[uü]b[uü]|(?:\b|[_\s])sk\b|(?:\b|[_\s])gsk\b|(?:\b|[_\s])skd\b|y[uü]zme\s*kul[uü]b[uü]|ihtisas|derne[gğ]i|belediye\s*spor|belediyespor|kolejliler)', kl.lower()))
        if kl.lower() == 'ferdi':
            okul_mu = 0
        elif in_school_meet:
            okul_mu = 0 if (has_sk and cs["fed_races"] > cs["okul_races"] and cs["fed_races"] >= 50) else 1
        elif has_school_kw and not has_sk:
            okul_mu = 1
        else:
            okul_mu = 0

        club_insert_rows.append((
            c_id,
            kl,
            len(cs["swimmer_names"]),
            cs["race_count"],
            min_d,
            max_d,
            okul_mu
        ))

    print(f"[+] Toplam {len(club_insert_rows):,} benzersiz kulüp hazırlandı.")

    # -------------------------------------------------------------------------
    # ADIM 3: Sporcuları İsme ve Yarış Tarihinden Hesaplanan Doğum Yılına Göre Tekilleştirme
    # -------------------------------------------------------------------------
    print("\n>>> ADIM 3: Sporcular isme göre toplanıp yarış tarihlerinden doğum yılları hesaplanıyor...")

    file_semantics = build_file_column_semantics()
    print(f"[+] {len(file_semantics)} dosyanın tablo başlık semantiği (YB / Yaş) tespit edildi.")

    # 1. Tüm benzersiz isimler arasında Türkçe karakter ve kelime sırası varyasyonlarını bağla (Union-Find)
    unique_sp_names = list(set(r.get("Sporcu", "").strip() for r in rows if r.get("Sporcu", "").strip()))
    parent = {n: n for n in unique_sp_names}

    def find(i):
        path = []
        while parent[i] != i:
            path.append(i)
            i = parent[i]
        for p in path:
            parent[p] = i
        return i

    def union(i, j):
        root_i = find(i)
        root_j = find(j)
        if root_i != root_j:
            parent[root_i] = root_j

    seen_norm = {}
    seen_sorted = {}

    for name in unique_sp_names:
        cname = clean_swimmer_name_raw(name)
        n_key = norm(cname)
        s_key = sorted_words_norm(cname)

        if n_key in seen_norm:
            union(name, seen_norm[n_key])
        else:
            seen_norm[n_key] = name

        if s_key in seen_sorted:
            union(name, seen_sorted[s_key])
        else:
            seen_sorted[s_key] = name

    # 2. Her sporcu adının yarışlarını topla
    name_races = defaultdict(list)
    for r_idx, r in enumerate(rows):
        sp = r.get("Sporcu", "").strip()
        raw_yas = r.get("Yaş", "").strip()
        t_raw = r.get("Tarih", "").strip()
        fname = r.get("Dosya Adı", "").strip()
        yg = r.get("Yaş Grubu", "").strip()

        d1, d2 = parse_date_range(t_raw, fname)
        meet_yr = int(d1[:4]) if (d1 and len(d1) >= 4 and d1[:4].isdigit()) else None

        deduced_by = deduce_birth_year(raw_yas, meet_yr, yg, fname, file_semantics)
        
        grp_root = find(sp)
        name_races[grp_root].append({
            'row_idx': r_idx,
            'raw_row': r,
            'sp_name': sp,
            'meet_yr': meet_yr,
            'd1': d1,
            'd2': d2,
            'deduced_by': deduced_by
        })

    print(f"[+] Toplam {len(unique_sp_names):,} benzersiz isim {len(name_races):,} kanonik sporcu adına tekilleştirildi.")

    # 3. Her sporcu adı için doğum yılı kümeleme (Clustering) yap
    athlete_profiles = []
    row_to_athlete_id = {}
    ath_counter = 1

    for grp_root, r_items in name_races.items():
        by_counts = Counter(item['deduced_by'] for item in r_items if item['deduced_by'])

        if not by_counts:
            # Doğum yılı bilgisi hiç olmayan sporcu
            clusters = [{'center': None, 'items': r_items}]
        else:
            # En çok tekrar eden yıllara göre sırala
            sorted_years = [y for y, _ in by_counts.most_common()]
            clusters = [] # list of dict: {'center': y, 'years': set(), 'items': []}

            for yr in sorted_years:
                matched = False
                for c in clusters:
                    if c['center'] is not None and abs(c['center'] - yr) <= 1:
                        c['years'].add(yr)
                        matched = True
                        break
                if not matched:
                    clusters.append({'center': yr, 'years': {yr}, 'items': []})

            # Her yarışı en yakın doğum yılı kümesine ata
            for item in r_items:
                r_by = item['deduced_by']
                if r_by:
                    best_c = min(clusters, key=lambda c: abs(c['center'] - r_by) if c['center'] is not None else 999)
                    best_c['items'].append(item)
                else:
                    # Bu yarışta yaş belirtilmemişse en büyük kümeye bağla
                    clusters[0]['items'].append(item)

            # Aykırı Ufak Kümeleri Birleştirme (Outlier Cleanup):
            # Eğer bir kümede sadece 1-3 yarış varsa ve ana kümeye sadece 2 yıl uzaklıktaysa,
            # bu doğum günü veya OCR kaymasıdır, ana profille birleştir.
            if len(clusters) > 1 and clusters[0]['center'] is not None:
                main_c = clusters[0]
                merged_clusters = [main_c]
                for c in clusters[1:]:
                    if c['center'] is not None and len(c['items']) <= 3 and abs(c['center'] - main_c['center']) <= 2:
                        main_c['items'].extend(c['items'])
                    else:
                        merged_clusters.append(c)
                clusters = merged_clusters

        for c in clusters:
            if not c['items']:
                continue
            ath_id = ath_counter
            ath_counter += 1

            for itm in c['items']:
                row_to_athlete_id[itm['row_idx']] = ath_id

            # Kümedeki en doğru Türkçe imlaya ve formata sahip ismi seç
            cluster_name_counts = Counter(itm['sp_name'] for itm in c['items'])
            best_name = max(
                cluster_name_counts.keys(),
                key=lambda n: score_swimmer_name(n, cluster_name_counts[n])
            )

            athlete_profiles.append({
                'id': ath_id,
                'name': best_name,
                'birth_year': c['center'],
                'items': c['items']
            })

    print(f"[+] Akıllı tekilleştirme sonucu {len(athlete_profiles):,} tekil sporcu profili oluşturuldu.")

    # 3. Her profil için istatistikleri çıkar
    athlete_insert_rows = []
    for p in athlete_profiles:
        a_id = p['id']
        sp_name = p['name']
        by = p['birth_year']
        p_items = p['items']

        club_counts = Counter()
        gender_counts = Counter()
        min_date = "9999-99-99"
        max_date = "0000-00-00"

        for itm in p_items:
            r = itm['raw_row']
            kl = r.get("Kulüp", "").strip()
            cins = r.get("Cinsiyet", "").strip()
            d1 = itm['d1']
            d2 = itm['d2']

            if kl:
                club_counts[kl] += 1
            if cins:
                gender_counts[cins] += 1

            if d1 and d1 != "1900-01-01":
                if d1 < min_date:
                    min_date = d1
                max_d = d2 or d1
                if max_d > max_date:
                    max_date = max_d

        erkek_cnt = gender_counts.get("Erkekler", 0)
        kiz_cnt = gender_counts.get("Kızlar", 0) + gender_counts.get("Bayanlar", 0) + gender_counts.get("Kadınlar", 0)
        if erkek_cnt > kiz_cnt:
            gender = "ERKEK"
        elif kiz_cnt > erkek_cnt:
            gender = "KADIN"
        else:
            gender = "BELİRTİLMEMİŞ"

        # Okul takımlarını resmi spor kulüplerinden ayır:
        # Eğer sporcunun resmi kulüp yarışları varsa birincil kulüp resmi kulüpler arasından seçilir.
        real_clubs = [c for c in p_clubs if not is_school_team(c)]
        if real_clubs:
            real_club_counts = Counter(real_clubs)
            top_club = real_club_counts.most_common(1)[0][0]
        else:
            top_club = club_counts.most_common(1)[0][0] if club_counts else ""
        top_club_id = club_id_map.get(top_club)

        min_d_str = min_date if min_date != "9999-99-99" else None
        max_d_str = max_date if max_date != "0000-00-00" else None
        by_str = str(by) if by else ""

        athlete_insert_rows.append((
            a_id,
            sp_name,
            by,
            by_str,
            gender,
            top_club_id,
            len(p_items),
            min_d_str,
            max_d_str
        ))

    # -------------------------------------------------------------------------
    # ADIM 4: Sporcu - Kulüp Tarihçe Tablosu (Transfer Süreci)
    # -------------------------------------------------------------------------
    print("\n>>> ADIM 4: Sporcu - Takım yarış tarihçesi ve transfer süreçleri hesaplanıyor...")

    history_dict = defaultdict(lambda: {
        "races": 0,
        "min_date": "9999-99-99",
        "max_date": "0000-00-00"
    })

    for r_idx, r in enumerate(rows):
        a_id = row_to_athlete_id[r_idx]
        kl = r.get("Kulüp", "").strip()
        c_id = club_id_map.get(kl)
        if not c_id:
            continue

        t_raw = r.get("Tarih", "").strip()
        fname = r.get("Dosya Adı", "").strip()
        d1, d2 = parse_date_range(t_raw, fname)
        start_d = d1 or "1900-01-01"
        end_d = d2 or start_d

        h = history_dict[(a_id, c_id)]
        h["races"] += 1
        if start_d != "1900-01-01":
            if start_d < h["min_date"]:
                h["min_date"] = start_d
            if end_d > h["max_date"]:
                h["max_date"] = end_d

    athlete_histories: Dict[int, List[Tuple[int, dict]]] = defaultdict(list)
    for (a_id, c_id), hdata in history_dict.items():
        athlete_histories[a_id].append((c_id, hdata))

    history_insert_rows = []
    history_id_map: Dict[Tuple[int, int], int] = {}
    h_counter = 1

    id_to_club_map = {cid: cname for cname, cid in club_id_map.items()}

    for a_id, clist in athlete_histories.items():
        clist_sorted = sorted(clist, key=lambda item: (item[1]["min_date"], item[1]["max_date"]))
        # Okul olmayanlar arasından en son yarışılan kulübü aktif seç
        non_school_clist = [item for item in clist if not is_school_team(id_to_club_map.get(item[0], ""))]
        if non_school_clist:
            latest_c_id = max(non_school_clist, key=lambda item: item[1]["max_date"])[0]
        else:
            latest_c_id = max(clist, key=lambda item: item[1]["max_date"])[0]

        for order_idx, (c_id, hdata) in enumerate(clist_sorted, start=1):
            history_id_map[(a_id, c_id)] = h_counter
            min_d = hdata["min_date"] if hdata["min_date"] != "9999-99-99" else None
            max_d = hdata["max_date"] if hdata["max_date"] != "0000-00-00" else None
            is_active = 1 if c_id == latest_c_id else 0

            history_insert_rows.append((
                h_counter,
                a_id,
                c_id,
                min_d,
                max_d,
                hdata["races"],
                order_idx,
                is_active
            ))
            h_counter += 1

    print(f"[+] Toplam {len(history_insert_rows):,} adet sporcu-kulüp tarihçe kaydı oluşturuldu.")

    # -------------------------------------------------------------------------
    # ADIM 5: Yarış Sonuçları Tablosu Hazırlığı
    # -------------------------------------------------------------------------
    print("\n>>> ADIM 5: Yarış sonuçları hesaplanan yaş ve ilişkisel anahtarlarla bağlanıyor...")

    # Profil id -> birth_year haritası
    athlete_by_map = {p['id']: p['birth_year'] for p in athlete_profiles}

    results_insert_rows = []
    for r_idx, r in enumerate(rows, start=1):
        actual_idx = r_idx - 1
        a_id = row_to_athlete_id[actual_idx]
        kl = r.get("Kulüp", "").strip()
        c_id = club_id_map.get(kl)
        h_id = history_id_map.get((a_id, c_id)) if (a_id and c_id) else None

        t_raw = r.get("Tarih", "").strip()
        fname = r.get("Dosya Adı", "").strip()
        d1, d2 = parse_date_range(t_raw, fname)

        # Hesaplanan Yarış Yaşı:
        by_val = athlete_by_map.get(a_id)
        hesaplanan_yas = None
        if by_val and d1 and len(d1) >= 4 and d1[:4].isdigit():
            m_yr = int(d1[:4])
            if m_yr >= by_val:
                hesaplanan_yas = m_yr - by_val

        # Sayısal alan dönüşümleri
        sec_val = None
        try:
            raw_sec = r.get("Derece (Saniye)", "").strip()
            if raw_sec:
                sec_val = float(raw_sec)
        except Exception:
            sec_val = None

        puan_val = None
        try:
            raw_puan = r.get("Puan", "").strip()
            if raw_puan:
                puan_val = int(raw_puan)
        except Exception:
            puan_val = None

        sayfa_no = None
        try:
            raw_s = r.get("Sayfa No", "").strip()
            if raw_s:
                sayfa_no = int(raw_s)
        except Exception:
            sayfa_no = None

        satir_no = None
        try:
            raw_sat = r.get("Satır No", "").strip()
            if raw_sat:
                satir_no = int(raw_sat)
        except Exception:
            satir_no = None

        mesafe_val = None
        try:
            raw_m = re.sub(r"[^\d]", "", r.get("Mesafe", ""))
            if raw_m:
                mesafe_val = int(raw_m)
        except Exception:
            mesafe_val = None

        results_insert_rows.append((
            r_idx,
            a_id,
            c_id,
            h_id,
            r.get("Kaynak Türü", "").strip() or ("IL_TEMSILCILIGI" if "_" in fname else ("TARANMIS_OCR" if re.match(r"^17\d{8}\.txt$", fname) else "METIN_PDF")),
            fname,
            sayfa_no,
            satir_no,
            clean_meet_name(fname, r.get("Müsabaka Adı", "")),
            r.get("Şehir", "").strip(),
            t_raw,
            d1,
            d2,
            r.get("Yarış No", "").strip(),
            r.get("Cinsiyet", "").strip(),
            mesafe_val,
            r.get("Stil", "").strip(),
            r.get("Yaş Grubu", "").strip(),
            r.get("Yaş", "").strip(),
            hesaplanan_yas,
            r.get("Sıra", "").strip(),
            r.get("Derece", "").strip(),
            sec_val,
            puan_val,
            r.get("Baraj", "").strip(),
            r.get("Beraberlik Mi", "").strip(),
            r.get("Zaman Kontrolü", "").strip(),
            r.get("Uyarı Notu", "").strip(),
            r.get("Ham Satır", "").strip()
        ))

    # -------------------------------------------------------------------------
    # ADIM 6: SQLite Veritabanını Oluşturma ve Toplu Kayıt
    # -------------------------------------------------------------------------
    print("\n>>> ADIM 6: SQLite veritabanı oluşturuluyor ve veriler yazılıyor...")

    if os.path.exists(DB_PATH):
        try:
            os.remove(DB_PATH)
        except Exception as e:
            print(f"[!] Eski veritabanı silinemedi: {e}")

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    cur.execute("PRAGMA journal_mode = OFF;")
    cur.execute("PRAGMA synchronous = 0;")
    cur.execute("PRAGMA cache_size = 100000;")
    cur.execute("PRAGMA temp_store = MEMORY;")

    # Tablo 1: kulupler
    cur.execute("""
    CREATE TABLE kulupler (
        id INTEGER PRIMARY KEY,
        kulup_adi TEXT NOT NULL UNIQUE,
        toplam_sporcu_sayisi INTEGER DEFAULT 0,
        toplam_yaris_sayisi INTEGER DEFAULT 0,
        ilk_yaris_tarihi TEXT,
        son_yaris_tarihi TEXT,
        okul_mu INTEGER DEFAULT 0
    );
    """)

    # Tablo 2: sporcular
    cur.execute("""
    CREATE TABLE sporcular (
        id INTEGER PRIMARY KEY,
        sporcu_adi TEXT NOT NULL,
        dogum_yili INTEGER,
        yas_dogum_yili TEXT,
        cinsiyet TEXT,
        birincil_kulup_id INTEGER REFERENCES kulupler(id),
        toplam_yaris_sayisi INTEGER DEFAULT 0,
        ilk_yaris_tarihi TEXT,
        son_yaris_tarihi TEXT
    );
    """)

    # Tablo 3: sporcu_kulup_tarihce
    cur.execute("""
    CREATE TABLE sporcu_kulup_tarihce (
        id INTEGER PRIMARY KEY,
        sporcu_id INTEGER NOT NULL REFERENCES sporcular(id),
        kulup_id INTEGER NOT NULL REFERENCES kulupler(id),
        ilk_yaris_tarihi TEXT,
        son_yaris_tarihi TEXT,
        toplam_yaris_sayisi INTEGER DEFAULT 0,
        donem_sirasi INTEGER DEFAULT 1,
        aktif_kulup_mu INTEGER DEFAULT 0,
        UNIQUE(sporcu_id, kulup_id)
    );
    """)

    # Tablo 4: yaris_sonuclari
    cur.execute("""
    CREATE TABLE yaris_sonuclari (
        id INTEGER PRIMARY KEY,
        sporcu_id INTEGER NOT NULL REFERENCES sporcular(id),
        kulup_id INTEGER REFERENCES kulupler(id),
        sporcu_kulup_tarihce_id INTEGER REFERENCES sporcu_kulup_tarihce(id),
        kaynak_turu TEXT,
        dosya_adi TEXT,
        sayfa_no INTEGER,
        satir_no INTEGER,
        musabaka_adi TEXT,
        sehir TEXT,
        yaris_tarihi_ham TEXT,
        yaris_tarihi_baslangic TEXT,
        yaris_tarihi_bitis TEXT,
        yaris_no TEXT,
        cinsiyet TEXT,
        mesafe INTEGER,
        stil TEXT,
        yas_grubu TEXT,
        sporcu_yas TEXT,
        hesaplanan_yas INTEGER,
        sira TEXT,
        derece TEXT,
        derece_saniye REAL,
        puan INTEGER,
        baraj TEXT,
        beraberlik_mi TEXT,
        zaman_kontrolu TEXT,
        uyari_notu TEXT,
        ham_satir TEXT
    );
    """)

    print("[+] Tablolar oluşturuldu. Toplu veri aktarımı başlatılıyor...")

    cur.executemany("""
    INSERT INTO kulupler (id, kulup_adi, toplam_sporcu_sayisi, toplam_yaris_sayisi, ilk_yaris_tarihi, son_yaris_tarihi, okul_mu)
    VALUES (?, ?, ?, ?, ?, ?, ?);
    """, club_insert_rows)
    print(f"  -> {len(club_insert_rows):,} kulüp eklendi.")

    cur.executemany("""
    INSERT INTO sporcular (id, sporcu_adi, dogum_yili, yas_dogum_yili, cinsiyet, birincil_kulup_id, toplam_yaris_sayisi, ilk_yaris_tarihi, son_yaris_tarihi)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
    """, athlete_insert_rows)
    print(f"  -> {len(athlete_insert_rows):,} tekil sporcu eklendi.")

    cur.executemany("""
    INSERT INTO sporcu_kulup_tarihce (id, sporcu_id, kulup_id, ilk_yaris_tarihi, son_yaris_tarihi, toplam_yaris_sayisi, donem_sirasi, aktif_kulup_mu)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    """, history_insert_rows)
    print(f"  -> {len(history_insert_rows):,} sporcu-kulüp tarihçesi eklendi.")

    batch_size = 50000
    for i in range(0, len(results_insert_rows), batch_size):
        batch = results_insert_rows[i:i + batch_size]
        cur.executemany("""
        INSERT INTO yaris_sonuclari (
            id, sporcu_id, kulup_id, sporcu_kulup_tarihce_id, kaynak_turu, dosya_adi, sayfa_no, satir_no,
            musabaka_adi, sehir, yaris_tarihi_ham, yaris_tarihi_baslangic, yaris_tarihi_bitis, yaris_no,
            cinsiyet, mesafe, stil, yas_grubu, sporcu_yas, hesaplanan_yas, sira, derece, derece_saniye, puan, baraj,
            beraberlik_mi, zaman_kontrolu, uyari_notu, ham_satir
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, batch)
        print(f"  -> {min(i + batch_size, len(results_insert_rows)):,} / {len(results_insert_rows):,} yarış sonucu yazıldı...")

    conn.commit()

    # -------------------------------------------------------------------------
    # ADIM 7: İndekslerin Oluşturulması
    # -------------------------------------------------------------------------
    print("\n>>> ADIM 7: Sorgu hızlandırıcı indeksler inşa ediliyor...")
    indexes = [
        "CREATE INDEX idx_kulupler_ad ON kulupler(kulup_adi);",
        "CREATE INDEX idx_kulupler_okul_mu ON kulupler(okul_mu);",
        "CREATE INDEX idx_sporcular_ad ON sporcular(sporcu_adi);",
        "CREATE INDEX idx_sporcular_dogum_yili ON sporcular(dogum_yili);",
        "CREATE INDEX idx_sporcular_birincil_kulup ON sporcular(birincil_kulup_id);",
        "CREATE INDEX idx_tarihce_sporcu ON sporcu_kulup_tarihce(sporcu_id);",
        "CREATE INDEX idx_tarihce_kulup ON sporcu_kulup_tarihce(kulup_id);",
        "CREATE INDEX idx_tarihce_tarih ON sporcu_kulup_tarihce(ilk_yaris_tarihi, son_yaris_tarihi);",
        "CREATE INDEX idx_sonuclar_sporcu ON yaris_sonuclari(sporcu_id);",
        "CREATE INDEX idx_sonuclar_kulup ON yaris_sonuclari(kulup_id);",
        "CREATE INDEX idx_sonuclar_tarihce ON yaris_sonuclari(sporcu_kulup_tarihce_id);",
        "CREATE INDEX idx_sonuclar_tarih ON yaris_sonuclari(yaris_tarihi_baslangic);",
        "CREATE INDEX idx_sonuclar_stil_mesafe ON yaris_sonuclari(stil, mesafe);"
    ]
    for idx_sql in indexes:
        cur.execute(idx_sql)

    conn.commit()
    conn.close()

    db_size_mb = os.path.getsize(DB_PATH) / (1024 * 1024)
    elapsed = time.time() - start_time

    print("=" * 70)
    print("      VERİTABANI AKTARIMI BAŞARIYLA TAMAMLANDI")
    print("=" * 70)
    print(f" SQLite Dosyası         : {DB_PATH} ({db_size_mb:.2f} MB)")
    print(f" Kulüpler Sayısı         : {len(club_insert_rows):,}")
    print(f" Tekil Sporcular Sayısı  : {len(athlete_insert_rows):,}")
    print(f" Tarihçe Kayıt Sayısı    : {len(history_insert_rows):,}")
    print(f" Yarış Sonuçları Sayısı  : {len(results_insert_rows):,}")
    print(f" Toplam İşlem Süresi     : {elapsed:.2f} saniye")
    print("=" * 70)


if __name__ == "__main__":
    build_database()
