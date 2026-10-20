"""
src/canonicalize_athletes.py
Sorumluluk: Kulüp tekilleştirmesi tamamlanmış veri üzerinde;
1. Sporcu isimlerini Türk Yüzme Federasyonu standart formatına
   (Title Case İlk İsimler + BÜYÜK HARF SOYADI, Türkçe İ/I düzeltmesi) dönüştürmek,
2. İsim varyasyonlarını (büyük/küçük harf, imla, çift boşluk) tekilleştirmek,
3. (İsim, Doğum Yılı) bazında birincil kulüp ve temsil edilen tüm kulüp/okul
   dağılımını hesaplayarak Kanonik Sporcu Veritabanını oluşturmak,
4. 'output/canonical_athletes.csv', 'output/reference/canonical_swimmers.json'
   ve harita dosyalarını üretmek,
5. 'output/bireysel_yuzucu_sonuclari.csv' ve 'output/diskalifiyeler.csv' dosyalarını
   kanonik sporcu isimleriyle güncellemek.
"""

from __future__ import annotations

import csv
import json
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Dict, List, Any, Tuple

# Proje kök dizinini ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

TURKISH_UPPER_MAP = {'i': 'İ', 'ı': 'I', 'ç': 'Ç', 'ğ': 'Ğ', 'ö': 'Ö', 'ş': 'Ş', 'ü': 'Ü'}
TURKISH_LOWER_MAP = {'İ': 'i', 'I': 'ı', 'Ç': 'ç', 'Ğ': 'ğ', 'Ö': 'ö', 'Ş': 'ş', 'Ü': 'ü'}

# Baş harfi ASCII 'I' olarak yazılmış fakat Türkçede 'İ' olması gereken yaygın ilk isimler
DOTTED_I_FIRST_NAMES_TITLE = {
    'ibrahim': 'İbrahim', 'idil': 'İdil', 'idris': 'İdris', 'ihsan': 'İhsan',
    'ikbal': 'İkbal', 'iklim': 'İklim', 'ikra': 'İkra', 'ikrasu': 'İkrasu',
    'ilay': 'İlay', 'ilayda': 'İlayda', 'ilbey': 'İlbey', 'ilgar': 'İlgar',
    'ilhami': 'İlhami', 'ilhan': 'İlhan', 'ilimsu': 'İlimsu', 'ilkay': 'İlkay',
    'ilke': 'İlke', 'ilker': 'İlker', 'ilkim': 'İlkim', 'ilkin': 'İlkin',
    'ilsu': 'İlsu', 'ilter': 'İlter', 'ilyada': 'İlyada', 'ilyas': 'İlyas',
    'imay': 'İmay', 'inal': 'İnal', 'inan': 'İnan', 'inanc': 'İnanç',
    'inci': 'İnci', 'insirah': 'İnşirah', 'ipek': 'İpek', 'irem': 'İrem',
    'irena': 'İrena', 'irfan': 'İrfan', 'irfanefe': 'İrfan Efe', 'iris': 'İris',
    'isa': 'İsa', 'ishak': 'İshak', 'iskender': 'İskender', 'islam': 'İslam',
    'ismail': 'İsmail', 'ismet': 'İsmet', 'isra': 'İsra', 'izzet': 'İzzet'
}

# Baş harfi ASCII 'I' veya imla hatasıyla yazılmış fakat Türkçede 'İ' veya 'İŞ' ile başlayan soyadları
DOTTED_I_SURNAMES = {
    'ibi': 'İBİ', 'ide': 'İDE', 'idiz': 'İDİZ', 'ikinci': 'İKİNCİ',
    'ildemir': 'İLDEMİR', 'iler': 'İLER', 'ileri': 'İLERİ', 'ilhan': 'İLHAN',
    'ilkbahar': 'İLKBAHAR', 'ilkhan': 'İLKHAN', 'ilter': 'İLTER', 'ilce': 'İLÇE',
    'ilcisulu': 'İLÇİSULU', 'imam': 'İMAM', 'imamoglu': 'İMAMOĞLU', 'iman': 'İMAN',
    'imer': 'İMER', 'inalkac': 'İNALKAÇ', 'inan': 'İNAN', 'inanc': 'İNANÇ',
    'ince': 'İNCE', 'incesu': 'İNCESU', 'incetahtaci': 'İNCETAHTACI', 'inci': 'İNCİ',
    'ipbuken': 'İPBÜKEN', 'ipek': 'İPEK', 'ipkin': 'İPKİN', 'irengun': 'İRENGÜN',
    'irgun': 'İRGÜN', 'iskender': 'İSKENDER', 'ismayil': 'İSMAYİL', 'ismail': 'İSMAİL',
    'ispanoglu': 'İSPANOĞLU', 'iyidogan': 'İYİDOĞAN', 'iyimaya': 'İYİMAYA', 'izgi': 'İZGİ',
    'isler': 'İŞLER', 'isleyen': 'İŞLEYEN', 'isleyici': 'İŞLEYİCİ', 'isman': 'İŞMAN',
    'istemiz': 'İŞTEMİZ', 'isten': 'İŞTEN', 'iscan': 'İŞCAN', 'iseri': 'İŞERİ',
    'iske': 'İŞKE', 'isli': 'İŞLİ', 'isme': 'İŞME'
}

# PDF / OCR dönüştürmesinde ilk isim kısmı kırpılmış satırların dosya bağlamında doğrulanmış isimleri
TRUNCATED_NAME_FIXES = {
    "(. KESKİN": "Mustafa Rüzgar KESKİN",
    "(. AKDOĞAN": "Ismail Engin AKDOĞAN",
    "(. COŞKUN": "Mustafa Selim COŞKUN",
    "(. DEMİRYÜREK": "Dağhan Emir DEMİRYÜREK",
    "(. ARDAHANLIOĞLU": "Kerem ARDAHANLIOĞLU",
    "(. DOYĞUN": "Ahmet Furkan DOYĞUN",
    "(. AKKAYA": "Timaf Voseps AKKAYA",
    "(. GÖÇEBAKAN": "Bayram Alper GÖÇEBAKAN",
    "(. KARSAVURANOĞLU": "Ali Emir KARSAVURANOĞLU",
    "(. GÜRGAN": "Ramazan Timurhan GÜRGAN",
    "(. YOĞURTCUOĞLU": "Kaya YOĞURTCUOĞLU",
    "(. ALTINKAYA": "Mustafa Yağız ALTINKAYA",
    "(. DEĞİRMENCİ": "Ahmet Eren DEĞİRMENCİ",
    "(. SAPMAZTÜRK": "Mustafa Arda SAPMAZTÜRK",
    "(. KARAHANOĞULLARI": "Gülşen Naz KARAHANOĞULLARI",
}


def normalize_lookup(w: str) -> str:
    """ASCII I/ı/İ karmaşasını ve Türkçe karakterleri arama için sadeleştirir."""
    res = []
    for ch in w:
        if ch in ('I', 'ı', 'İ', 'i'):
            res.append('i')
        elif ch in ('Ç', 'ç'):
            res.append('c')
        elif ch in ('Ğ', 'ğ'):
            res.append('g')
        elif ch in ('Ö', 'ö'):
            res.append('o')
        elif ch in ('Ş', 'ş'):
            res.append('s')
        elif ch in ('Ü', 'ü'):
            res.append('u')
        else:
            res.append(ch.lower())
    return "".join(res)


def tr_upper(s: str) -> str:
    """Türkçe karakter kurallarına uygun büyük harf dönüşümü."""
    return "".join(TURKISH_UPPER_MAP.get(ch, ch.upper()) for ch in s)


def tr_lower(s: str) -> str:
    """Türkçe karakter kurallarına uygun küçük harf dönüşümü."""
    return "".join(TURKISH_LOWER_MAP.get(ch, ch.lower()) for ch in s)


def tr_title_word(w: str) -> str:
    """Kelimenin ilk harfini büyük, kalanını küçük harfe çevirir."""
    if not w:
        return ""
    norm = normalize_lookup(w)
    if norm in DOTTED_I_FIRST_NAMES_TITLE:
        return DOTTED_I_FIRST_NAMES_TITLE[norm]
    first = tr_upper(w[0])
    rest = tr_lower(w[1:])
    return first + rest


def tr_surname_word(w: str) -> str:
    """Soyadı kelimesini Türkçeye uygun biçimde tamamı büyük harf yapar."""
    if not w:
        return ""
    norm = normalize_lookup(w)
    if norm in DOTTED_I_SURNAMES:
        return DOTTED_I_SURNAMES[norm]
    return tr_upper(w)


def normalize_comma_name(raw_name: str) -> str:
    """
    Virgül içeren isimleri (Meet Manager / Avrupa formatı) standart 'İlk İsim(ler) SOYADI' formatına çevirir.
    Örnek:
    'Çınar, KÖYSÜREN' -> 'Çınar KÖYSÜREN'
    'Deniz Uras, AĞARDAN' -> 'Deniz Uras AĞARDAN'
    'TOMEV, Marko' -> 'Marko TOMEV'
    'KAVDIR, AYŞE SELİN' -> 'AYŞE SELİN KAVDIR'
    """
    if "," not in raw_name:
        return raw_name
    parts = [p.strip() for p in raw_name.split(",") if p.strip()]
    if len(parts) == 2:
        p0, p1 = parts[0], parts[1]
        # Durum 1: İlk isim(ler), SOYADI (Örn: 'Çınar, KÖYSÜREN', 'Deniz Uras, AĞARDAN')
        if not p0.isupper() and p1.isupper():
            return f"{p0} {p1}"
        # Durum 2: SOYADI, İlk İsim(ler) (Örn: 'ÖRER, Sude', 'TOMEV, Marko')
        elif p0.isupper() and not p1.isupper():
            return f"{p1} {p0}"
        # Durum 3: SOYADI, İLK İSİM(LER) (Örn: 'KAVDIR, AYŞE SELİN', 'YILMAZ, IRMAK')
        elif p0.isupper() and p1.isupper():
            return f"{p1} {p0}"
        # Durum 4: Diğer / Her ikisi de küçük/title (Örn: 'Demir, Ali')
        else:
            return f"{p1} {p0}"
    return raw_name.replace(",", " ")


def standardize_swimmer_name(raw_name: str) -> str:
    """Sporcu adını standart kanonik formata çevirir:
    İlk İsim(ler): Baş Harfi Büyük, Gerisi Küçük (Title Case)
    Soyadı: TAMAMI BÜYÜK HARF
    """
    if "," in raw_name:
        raw_name = normalize_comma_name(raw_name)

    clean = re.sub(r"\s+", " ", raw_name).strip()
    if clean in TRUNCATED_NAME_FIXES:
        clean = TRUNCATED_NAME_FIXES[clean]
    clean = re.sub(r"^\(\.\s*", "", clean).strip()
    clean = re.sub(r"^(?:\(?[TtFf][kKdD]\)?[\.\)]?\s*)+", "", clean).strip()
    clean = re.sub(r"ALTİ", "ALTI", clean)

    words = clean.split()
    if not words:
        return clean
    if len(words) == 1:
        return tr_title_word(words[0])

    first_names = [tr_title_word(w) for w in words[:-1]]
    surname = tr_surname_word(words[-1])
    return " ".join(first_names + [surname])


def build_canonical_athletes(
    swimmer_csv: str | Path = "output/bireysel_yuzucu_sonuclari.csv",
    dq_csv: str | Path = "output/diskalifiyeler.csv",
    out_canonical_csv: str | Path = "output/canonical_athletes.csv",
    out_swimmers_json: str | Path = "output/reference/canonical_swimmers.json",
    out_map_csv: str | Path = "output/reference/sporcu_tekillestirme_haritasi.csv"
) -> Dict[str, Any]:
    """Kanonik sporcu veri tabanını oluşturur ve harita dosyalarını kaydeder."""
    os.makedirs(os.path.dirname(str(out_swimmers_json)), exist_ok=True)
    os.makedirs(os.path.dirname(str(out_canonical_csv)), exist_ok=True)

    with open(swimmer_csv, encoding="utf-8-sig") as f:
        swimmers = list(csv.DictReader(f))

    with open(dq_csv, encoding="utf-8-sig") as f:
        dqs = list(csv.DictReader(f))

    # İsim tekilleştirme haritası: raw_name -> canonical_name
    name_map = {}
    name_variants_counter = defaultdict(Counter)

    for r in swimmers:
        raw = r["Sporcu"].strip()
        canon = standardize_swimmer_name(raw)
        name_map[raw] = canon
        name_variants_counter[canon][raw] += 1

    for r in dqs:
        if r.get("Bayrak Mı") == "EVET":
            continue
        raw = r["Sporcu"].strip()
        canon = standardize_swimmer_name(raw)
        name_map[raw] = canon
        name_variants_counter[canon][raw] += 1

    # Sporcu Kimliği: (Kanonik İsim, Doğum Yılı / Yaş)
    athlete_profiles = defaultdict(lambda: {
        "clubs": Counter(),
        "files": set(),
        "race_count": 0,
        "dq_count": 0,
        "raw_names": Counter()
    })

    for r in swimmers:
        raw_name = r["Sporcu"].strip()
        canon_name = standardize_swimmer_name(raw_name)
        yb = r["Yaş"].strip()
        club = r["Kulüp"].strip()
        fn = r["Dosya Adı"].strip()

        key = (canon_name, yb)
        profile = athlete_profiles[key]
        profile["race_count"] += 1
        profile["clubs"][club] += 1
        profile["files"].add(fn)
        profile["raw_names"][raw_name] += 1

    for r in dqs:
        if r.get("Bayrak Mı") == "EVET":
            continue
        raw_name = r["Sporcu"].strip()
        canon_name = standardize_swimmer_name(raw_name)
        yb = r.get("Yaş", "").strip()
        club = r["Kulüp"].strip()
        fn = r["Dosya Adı"].strip()

        key = (canon_name, yb)
        profile = athlete_profiles[key]
        profile["dq_count"] += 1
        profile["clubs"][club] += 1
        profile["files"].add(fn)
        profile["raw_names"][raw_name] += 1

    # 1. output/canonical_athletes.csv
    canon_rows = []
    json_data = []

    for (name, yb), data in sorted(athlete_profiles.items(), key=lambda x: -x[1]["race_count"]):
        # Birincil Kulüp: En çok yarışılan kulüp
        primary_club = data["clubs"].most_common(1)[0][0] if data["clubs"] else "Ferdi"

        # Temsil edilen kurumlar
        clubs_str = "; ".join(f"{c} ({cnt})" for c, cnt in data["clubs"].most_common())

        canon_rows.append({
            "Sporcu Adı": name,
            "Doğum Yılı / Yaş": yb,
            "Birincil Kulüp": primary_club,
            "Toplam Yarış Sayısı": data["race_count"],
            "Diskalifiye Sayısı": data["dq_count"],
            "Temsil Ettiği Kulüpler ve Okullar": clubs_str,
            "Katıldığı Dosya Sayısı": len(data["files"])
        })

        json_data.append({
            "name": name,
            "birth_year": yb,
            "primary_club": primary_club,
            "total_races": data["race_count"],
            "total_dqs": data["dq_count"],
            "files_count": len(data["files"]),
            "clubs": [{"club": c, "count": cnt} for c, cnt in data["clubs"].most_common()],
            "name_variants": [{"variant": v, "count": cnt} for v, cnt in data["raw_names"].most_common()]
        })

    with open(out_canonical_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "Sporcu Adı", "Doğum Yılı / Yaş", "Birincil Kulüp",
            "Toplam Yarış Sayısı", "Diskalifiye Sayısı",
            "Temsil Ettiği Kulüpler ve Okullar", "Katıldığı Dosya Sayısı"
        ])
        writer.writeheader()
        writer.writerows(canon_rows)

    with open(out_swimmers_json, "w", encoding="utf-8") as f:
        json.dump(json_data, f, ensure_ascii=False, indent=2)

    # 2. output/reference/sporcu_tekillestirme_haritasi.csv
    map_rows = []
    for canon_name, variants in sorted(name_variants_counter.items(), key=lambda x: -sum(x[1].values())):
        for raw_name, cnt in variants.most_common():
            map_rows.append({
                "Ham Sporcu Adı": raw_name,
                "Kanonik Sporcu Adı": canon_name,
                "Değişti Mi": "EVET" if raw_name != canon_name else "HAYIR",
                "Kullanım Sayısı": cnt
            })

    with open(out_map_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["Ham Sporcu Adı", "Kanonik Sporcu Adı", "Değişti Mi", "Kullanım Sayısı"])
        writer.writeheader()
        writer.writerows(map_rows)

    return {
        "total_swimmers_processed": len(swimmers),
        "raw_names_count": len(name_map),
        "canonical_names_count": len(name_variants_counter),
        "canonical_athletes_count": len(athlete_profiles),
        "unified_name_clusters": sum(1 for v in name_variants_counter.values() if len(v) > 1),
        "out_canonical_csv": out_canonical_csv,
        "out_swimmers_json": out_swimmers_json,
        "out_map_csv": out_map_csv
    }


def apply_canonical_athletes_to_datasets(
    swimmer_csv: str | Path = "output/bireysel_yuzucu_sonuclari.csv",
    dq_csv: str | Path = "output/diskalifiyeler.csv"
) -> Tuple[int, int]:
    """Bireysel yüzücü ve diskalifiye dosyalarındaki sporcu isimlerini kanonik adlarıyla günceller."""
    # 1. Swimmers
    with open(swimmer_csv, encoding="utf-8-sig") as f:
        swimmer_rows = list(csv.DictReader(f))
        swimmer_fields = list(swimmer_rows[0].keys())

    updated_swimmers = 0
    for r in swimmer_rows:
        raw_name = r["Sporcu"].strip()
        canon_name = standardize_swimmer_name(raw_name)
        if raw_name != canon_name:
            r["Sporcu"] = canon_name
            updated_swimmers += 1

    with open(swimmer_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=swimmer_fields)
        writer.writeheader()
        writer.writerows(swimmer_rows)

    swimmer_json = str(swimmer_csv).replace(".csv", ".json")
    if os.path.exists(swimmer_json):
        with open(swimmer_json, "w", encoding="utf-8") as f:
            json.dump(swimmer_rows, f, ensure_ascii=False, indent=2)

    # 2. Disqualifications
    with open(dq_csv, encoding="utf-8-sig") as f:
        dq_rows = list(csv.DictReader(f))
        dq_fields = list(dq_rows[0].keys())

    updated_dqs = 0
    for r in dq_rows:
        if r.get("Bayrak Mı") == "EVET":
            continue
        raw_name = r["Sporcu"].strip()
        canon_name = standardize_swimmer_name(raw_name)
        if raw_name != canon_name:
            r["Sporcu"] = canon_name
            updated_dqs += 1

    with open(dq_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=dq_fields)
        writer.writeheader()
        writer.writerows(dq_rows)

    dq_json = str(dq_csv).replace(".csv", ".json")
    if os.path.exists(dq_json):
        with open(dq_json, "w", encoding="utf-8") as f:
            json.dump(dq_rows, f, ensure_ascii=False, indent=2)

    return updated_swimmers, updated_dqs


if __name__ == "__main__":
    print("Sporcu tekilleştirme ve kanonikleştirme süreci başlatılıyor...")
    info = build_canonical_athletes()

    print("\n" + "=" * 65)
    print("            SPORCU TEKİLLEŞTİRME ÖZET RAPORU            ")
    print("=" * 65)
    print(f" İncelenen Bireysel Sonuç Kaydı Sayısı     : {info['total_swimmers_processed']:5d}")
    print(f" Başlangıçtaki Ham Farklı Sporcu İsimleri  : {info['raw_names_count']:5d}")
    print(f" Tekilleştirilmiş Kanonik İsim Sayısı      : {info['canonical_names_count']:5d}")
    print(f" Birleştirilen Farklı İsim Varyasyonu      : {info['unified_name_clusters']:5d}")
    print(f" (İsim, Doğum Yılı) Bazlı Tekil Sporcu     : {info['canonical_athletes_count']:5d}")
    print("=" * 65)

    up_sw, up_dq = apply_canonical_athletes_to_datasets()
    print(f"\n[BAŞARILI] Veri setleri kanonik sporcu isimleriyle güncellendi:")
    print(f"  - Yüzücü sonuçlarında güncellenen sporcu adı sayısı : {up_sw}")
    print(f"  - Diskalifiyelerde güncellenen sporcu adı sayısı   : {up_dq}")
    print(f"\nKanonik Sporcular CSV: {info['out_canonical_csv']}")
    print(f"Kanonik Sporcular JSON: {info['out_swimmers_json']}")
    print(f"İsim Haritası CSV     : {info['out_map_csv']}")
