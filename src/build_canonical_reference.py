"""
src/build_canonical_reference.py
Sorumluluk:
1. YALNIZCA metin tabanlı temiz PDF sonuçlarından (output/metin_tabanli_bireysel_yuzucu_sonuclari.csv)
   kulüp isimlerini toplayıp, tüm temizleme ve birleştirme kurallarını uygulayarak KANONİK KULÜP REFERANS TABLOSU oluşturmak.
   (OCR dosyaları KESİNLİKLE bu aşamaya dahil edilmez).
2. Metin tabanlı sonuçlardan sporcu isimlerini virgül, okul etiketleri ve büyük/küçük harf kurallarıyla standartlaştırmak.
3. Sporcuları ilk adımda üretilen KANONİK KULÜP isimleriyle eşleştirmek ve sporcunun temsil ettiği tüm kulüpleri indekslemek.
4. Taranmış OCR verilerini doğrulamak ve düzeltmek için hızlı erişim sağlayan `load_canonical_reference()` fonksiyonunu sunmak.
"""

from __future__ import annotations

import csv
import json
import os
import re
import sys
import time
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

TR_NORM_MAP = str.maketrans("çğıöşüÇĞİÖŞÜ", "cgiosuCGIOSU")

TAG_RE = re.compile(r"\(?(?:Tk|Td|Fd|tk|td|fd|TK|TD|FD)\)?[\.\)]?\s*")


@dataclass
class AthleteRef:
    canonical_name: str
    age: str
    primary_club: str
    all_clubs: Set[str] = field(default_factory=set)
    race_count: int = 0


def norm(s: str) -> str:
    """Metni karşılaştırma için küçük harfli ve Türkçe karaktersiz hale getirir."""
    if not s:
        return ""
    clean = s.translate(TR_NORM_MAP).lower()
    return re.sub(r"[^a-z0-9]", "", clean)


def normalize_comma_name(raw_name: str) -> str:
    """
    Virgül içeren isimleri (Meet Manager / Avrupa formatı) standart 'İlk İsim(ler) SOYADI' formatına çevirir.
    Örnek:
    'Çınar, KÖYSÜREN' -> 'Çınar KÖYSÜREN'
    'Deniz Uras, AĞARDAN' -> 'Deniz Uras AĞARDAN'
    'TOMEV, Marko' -> 'Marko TOMEV'
    'KAVDIR, AYŞE SELİN' -> 'AYŞE SELİN KAVDIR'
    """
    if not raw_name or "," not in raw_name:
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


def standardize_swimmer_name(name: str) -> str:
    """
    Sporcu adını standart 'İlk İsim(ler) SOYADI' formatına çevirir.
    Okul etiketlerini (Fd, Tk vb.) ve virgülleri temizler.
    """
    if not name:
        return ""
    # 1. Virgül normalizasyonu
    if "," in name:
        name = normalize_comma_name(name)
    # 2. Okul etiketi temizliği
    name = TAG_RE.sub("", name).strip()
    # 3. Hatalı ALTİ... kökünü ALTI...'ya düzelt (örn: ALTİNTOP -> ALTINTOP, ÖZALTİN -> ÖZALTIN)
    name = re.sub(r"ALTİ", "ALTI", name)
    words = name.split()
    if not words:
        return ""
    if len(words) == 1:
        return words[0].upper()

    # İlk isimler Title Case, son kelime (soyadı) UPPERCASE
    first_names = [w.capitalize() if not w.isupper() else w.capitalize() for w in words[:-1]]
    last_name = words[-1].upper()
    return f"{' '.join(first_names)} {last_name}"


def get_club_core(s: str) -> str:
    """Kulüp adının genel eklerini temizleyerek ayırt edici çekirdeğini döner."""
    n = norm(s)
    for suf in [
        "genclikvesporkulubudernegi", "genclikvesporkulubu", "gencliksporkulubu",
        "yuzmesporkulubu", "susporlarigenclikvesporkulubu", "susporlarisporkulubu",
        "ihtisassporkulubu", "jimnastiksporkulubu", "sporkulubudernegi", "sporkulubu",
        "sporkulub", "sporkulul", "yuzmekulubu", "yuzmethtisas", "yuzmeihtisas",
        "kulubudernegi", "kulubu", "dernegi", "sk"
    ]:
        if n.endswith(suf) and len(n) > len(suf) + 2:
            return n[:-len(suf)]
    return n


def clean_club_text_suffix(s: str) -> str:
    """Metin tabanlı dosyalardaki kulüp kısaltmalarını ve imla varyasyonlarını standartlaştırır."""
    c = s.strip()
    c = re.sub(r"\s+S\.?\s*K\.?$", " Spor Kulübü", c, flags=re.I)
    c = re.sub(r"\s+Sk\.?$", " Spor Kulübü", c, flags=re.I)
    c = re.sub(r"\bKulubü\b", "Kulübü", c)
    c = re.sub(r"\bKulubu\b", "Kulübü", c)
    c = re.sub(r"\bDernegi\b", "Derneği", c)
    c = re.sub(r"\s+", " ", c).strip()
    return c


def build_canonical_reference(
    text_results_csv: str = "output/metin_tabanli_bireysel_yuzucu_sonuclari.csv",
    output_dir: str = "output/reference"
) -> Tuple[Dict[str, str], Dict[str, str], Dict[str, List[AthleteRef]]]:
    """
    SADECE metin tabanlı temiz veri setini işleyerek kanonik referans tablolarını üretir.
    OCR verileri bu sürece ASLA dahil edilmez.
    """
    t0 = time.perf_counter()
    out_path = Path(output_dir)
    out_path.mkdir(parents=True, exist_ok=True)

    print("=" * 70)
    print("      KANONİK REFERANS VERİTABANI OLUŞTURULUYOR (YALNIZCA METİN PDF)   ")
    print("=" * 70)
    print(f"Kaynak Metin Veri Seti: {text_results_csv}")

    if not os.path.exists(text_results_csv):
        raise FileNotFoundError(f"Metin tabanlı sonuç dosyası bulunamadı: {text_results_csv}")

    raw_swimmers = []
    with open(text_results_csv, encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for r in reader:
            raw_swimmers.append(r)

    print(f"[+] {len(raw_swimmers):,} adet metin tabanlı yarış kaydı yüklendi ({time.perf_counter() - t0:.2f}s).")

    # -------------------------------------------------------------------------
    # ADIM 1: Kulüp İsimlerinin Temizlenmesi, Birleştirilmesi ve Referans Tablosu
    # -------------------------------------------------------------------------
    print("\n>>> ADIM 1: Metin tabanlı kulüp isimleri kanonikleştiriliyor...")
    raw_club_counts = Counter()
    for r in raw_swimmers:
        kl = r.get("Kulüp", "").strip()
        if not kl:
            continue
        # Filtreleme: Baraj, rekor, tarih, tekil harf gibi gürültüleri dışarıda bırak
        if len(re.findall(r"[a-zA-ZçğıöşüÇĞİÖŞÜ]", kl)) < 3:
            continue
        if any(ch in kl for ch in (':', ';', '/')) or re.search(r'(?:baraj|rekor|25m|50m|bireysel yzm|türkiye rekorlar)', kl, re.I):
            continue
        raw_club_counts[kl] += 1

    # Ek standardizasyonu
    cleaned_club_counts = Counter()
    club_to_cleaned = {}
    for kl, cnt in raw_club_counts.items():
        c = clean_club_text_suffix(kl)
        club_to_cleaned[kl] = c
        cleaned_club_counts[c] += cnt

    # Çekirdek (Core) bazında gruplama
    core_to_candidates = defaultdict(Counter)
    for c, cnt in cleaned_club_counts.items():
        core = get_club_core(c)
        core_to_candidates[core][c] += cnt

    # Her çekirdek için en doğru resmi kanonik ismi seç
    core_to_canonical = {}
    for core, cand_counts in core_to_candidates.items():
        candidates_ranked = sorted(
            cand_counts.items(),
            key=lambda item: (
                1 if "Spor Kulübü" in item[0] else 0,
                item[1],
                len(item[0])
            ),
            reverse=True
        )
        core_to_canonical[core] = candidates_ranked[0][0]

    # Ham isimden nihai kanonik isme eşleme
    raw_to_canonical_club = {}
    for raw_kl in raw_club_counts:
        cleaned = club_to_cleaned[raw_kl]
        core = get_club_core(cleaned)
        raw_to_canonical_club[raw_kl] = core_to_canonical.get(core, cleaned)

    canonical_club_totals = Counter()
    canonical_club_aliases = defaultdict(set)
    for raw_kl, cnt in raw_club_counts.items():
        canon = raw_to_canonical_club[raw_kl]
        canonical_club_totals[canon] += cnt
        if raw_kl != canon:
            canonical_club_aliases[canon].add(raw_kl)

    # Kulüp referans CSV'sini yaz
    club_ref_csv = out_path / "canonical_clubs_reference.csv"
    with open(club_ref_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Kanonik Kulüp Adı", "Toplam Sonuç Sayısı", "Farklı Metin Varyasyonları"])
        for canon, cnt in canonical_club_totals.most_common():
            aliases_str = "; ".join(sorted(canonical_club_aliases[canon]))
            writer.writerow([canon, cnt, aliases_str])

    # Kulüp JSON haritaları
    club_ref_json = out_path / "canonical_clubs.json"
    club_export_data = {
        "raw_to_canonical": raw_to_canonical_club,
        "core_to_canonical": core_to_canonical,
        "canonical_clubs": list(canonical_club_totals.keys())
    }
    with open(club_ref_json, "w", encoding="utf-8") as f:
        json.dump(club_export_data, f, ensure_ascii=False, indent=2)

    print(f"[+] Adım 1 Tamamlandı: {len(raw_club_counts):,} ham kulüp ismi -> {len(canonical_club_totals):,} resmi kanonik kulübe dönüştürüldü.")

    # -------------------------------------------------------------------------
    # ADIM 2 & 3: Sporcu İsimlerinin Temizlenmesi ve Kanonik Kulüplerle Eşleştirilmesi
    # -------------------------------------------------------------------------
    print("\n>>> ADIM 2 & 3: Sporcular standartlaştırılıyor ve kanonik kulüpleriyle ilişkilendiriliyor...")
    athlete_profiles = defaultdict(lambda: {
        "names": Counter(),
        "clubs": Counter(),
        "birth_years": Counter(),
        "race_count": 0
    })

    for r in raw_swimmers:
        raw_sp = r.get("Sporcu", "").strip()
        raw_yb = r.get("Yaş", "").strip()
        raw_kl = r.get("Kulüp", "").strip()

        if not raw_sp or raw_sp.isdigit() or re.match(r"^[5sS]om", raw_sp, re.I):
            continue

        # Baraj veya yarış dışı başlık satırlarını ele
        if any(c in raw_sp for c in [':', '/', '=', '+', '%', '$', '<', '>', '_', '|', ';', '@', '*', '?', '\\']):
            continue
        if re.search(r'\d+[:\.]\d{2}', raw_sp) or re.search(r'\b[AB][1-4]\b', raw_sp, re.I):
            continue
        if re.search(r'\b\d{1,2}\s*YAŞ\b', raw_sp, re.I) or re.search(r'\bYAŞ\s*\d{1,2}\b', raw_sp, re.I) or re.search(r'\b\d{1,2}\s*\+\b', raw_sp):
            continue
        if re.match(r'^\d+', raw_sp):
            continue

        # Sporcu adını standartlaştır (virgül ve okul etiketleri arındırılır)
        std_sp = standardize_swimmer_name(raw_sp)
        if not std_sp:
            continue
        if std_sp.lower() in ("antalya", "trabzon", "edirne", "istanbul", "bursa", "ankara", "izmir", "kayseri"):
            continue
        if len(std_sp.split()) < 2:
            continue

        # Kulübü 1. adımdaki kanonik kulüple eşleştir
        canon_kl = raw_to_canonical_club.get(raw_kl, clean_club_text_suffix(raw_kl) if raw_kl else "")

        key = (norm(std_sp), raw_yb)
        ath = athlete_profiles[key]
        ath["names"][std_sp] += 1
        if canon_kl:
            ath["clubs"][canon_kl] += 1
        if raw_yb:
            ath["birth_years"][raw_yb] += 1
        ath["race_count"] += 1

    # Sporcu nesnelerini oluştur
    # ref_athletes: norm(isim) -> list of AthleteRef
    ref_athletes: Dict[str, List[AthleteRef]] = defaultdict(list)
    athlete_ref_rows = []

    tr_chars = set("çğıöşüÇĞİÖŞÜ")
    for (n_name, yb), data in athlete_profiles.items():
        # En doğru Türkçe imlayı ve en yüksek frekansı seç
        best_name = max(
            data["names"].keys(),
            key=lambda name: (
                sum(1 for c in name if c in tr_chars),
                data["names"][name],
                len(name)
            )
        )
        primary_club = data["clubs"].most_common(1)[0][0] if data["clubs"] else ""
        all_clubs_set = set(data["clubs"].keys())
        r_cnt = data["race_count"]

        ath_ref = AthleteRef(
            canonical_name=best_name,
            age=yb,
            primary_club=primary_club,
            all_clubs=all_clubs_set,
            race_count=r_cnt
        )
        ref_athletes[n_name].append(ath_ref)

        athlete_ref_rows.append({
            "Sporcu Adı": best_name,
            "Yaş / Doğum Yılı": yb,
            "Birincil Kulüp": primary_club,
            "Temsil Ettiği Tüm Kulüpler": "; ".join(sorted(all_clubs_set)),
            "Toplam Yarış Sayısı": r_cnt
        })

    # Sporcu referans CSV'sini yaz
    ath_ref_csv = out_path / "canonical_athletes_reference.csv"
    with open(ath_ref_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "Sporcu Adı", "Yaş / Doğum Yılı", "Birincil Kulüp",
            "Temsil Ettiği Tüm Kulüpler", "Toplam Yarış Sayısı"
        ])
        writer.writeheader()
        writer.writerows(athlete_ref_rows)

    # Sporcu referans JSON'ı yaz
    ath_ref_json = out_path / "canonical_swimmers.json"
    athletes_json_dict = {}
    for n_name, entries in ref_athletes.items():
        athletes_json_dict[n_name] = [
            {
                "canonical_name": e.canonical_name,
                "age": e.age,
                "primary_club": e.primary_club,
                "all_clubs": list(e.all_clubs),
                "race_count": e.race_count
            }
            for e in entries
        ]
    with open(ath_ref_json, "w", encoding="utf-8") as f:
        json.dump(athletes_json_dict, f, ensure_ascii=False, indent=2)

    total_el = time.perf_counter() - t0
    print(f"[+] Adım 2 & 3 Tamamlandı: {len(athlete_profiles):,} benzersiz sporcu profili kanonik kulüpleriyle oluşturuldu.")
    print(f"[+] Tüm referans tabloları kaydedildi: {output_dir} ({total_el:.2f}s)")

    # Metin tabanlı veri setini kanonik referansla güncelle
    canonicalize_text_dataset(text_results_csv)

    return raw_to_canonical_club, core_to_canonical, ref_athletes


def canonicalize_text_dataset(
    csv_path: str = "output/metin_tabanli_bireysel_yuzucu_sonuclari.csv"
):
    """
    Metin tabanlı yarış sonuçlarındaki sporcu ve kulüp adlarını
    kanonik referans tablolarıyla eşleştirerek tekilleştirir ve günceller.
    """
    if not os.path.exists(csv_path):
        return

    ref_clubs, ref_cores, ref_athletes, _, _, _ = load_canonical_reference()

    rows = []
    upgraded_sp = 0
    upgraded_kl = 0

    with open(csv_path, encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        fieldnames = list(reader.fieldnames)
        for r in reader:
            sp = r.get("Sporcu", "").strip()
            kl = r.get("Kulüp", "").strip()

            n_sp = norm(sp)
            if n_sp in ref_athletes:
                canon_sp = ref_athletes[n_sp][0].canonical_name
                if canon_sp != sp:
                    upgraded_sp += 1
                r["Sporcu"] = canon_sp
            else:
                r["Sporcu"] = standardize_swimmer_name(sp)

            n_kl = norm(kl)
            if n_kl in ref_clubs:
                canon_kl = ref_clubs[n_kl]
                if canon_kl != kl:
                    upgraded_kl += 1
                r["Kulüp"] = canon_kl

            rows.append(r)

    with open(csv_path, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"[+] Metin tabanlı veri seti kanonikleştirildi: {upgraded_sp:,} sporcu ve {upgraded_kl:,} kulüp adı resmi formuna yükseltildi.")


def load_canonical_reference(reference_dir: str = "output/reference"):
    """
    Kanonik referans tablolarını diskten yükler veya yoksa oluşturur.
    Taranmış OCR doğrulaması için optimize edilmiş indeksleri döner.
    """
    ref_path = Path(reference_dir)
    clubs_json = ref_path / "canonical_clubs.json"
    swimmers_json = ref_path / "canonical_swimmers.json"

    if not clubs_json.exists() or not swimmers_json.exists():
        build_canonical_reference(output_dir=reference_dir)

    with open(clubs_json, encoding="utf-8") as f:
        c_data = json.load(f)

    with open(swimmers_json, encoding="utf-8") as f:
        s_data = json.load(f)

    # 1. Kulüp Normalizasyon Haritaları
    raw_to_canon = c_data["raw_to_canonical"]
    core_to_canon = c_data["core_to_canonical"]

    ref_clubs: Dict[str, str] = {}
    for raw_kl, canon_kl in raw_to_canon.items():
        ref_clubs[norm(raw_kl)] = canon_kl
        ref_clubs[norm(canon_kl)] = canon_kl

    ref_cores: Dict[str, str] = {}
    for core, canon_kl in core_to_canon.items():
        ref_cores[core] = canon_kl

    # 2. Sporcu ve Takım İndeksleri
    ref_athletes: Dict[str, List[AthleteRef]] = defaultdict(list)
    athletes_by_club: Dict[str, List[AthleteRef]] = defaultdict(list)
    athletes_by_first_name: Dict[str, List[AthleteRef]] = defaultdict(list)
    athletes_by_surname: Dict[str, List[AthleteRef]] = defaultdict(list)

    for n_name, entries_raw in s_data.items():
        for e in entries_raw:
            ath = AthleteRef(
                canonical_name=e["canonical_name"],
                age=e["age"],
                primary_club=e["primary_club"],
                all_clubs=set(e["all_clubs"]),
                race_count=e["race_count"]
            )
            ref_athletes[n_name].append(ath)

            # Sporcunun temsil ettiği TÜM kulüplere indeksle
            for kl in ath.all_clubs:
                if kl:
                    athletes_by_club[norm(kl)].append(ath)

            words = ath.canonical_name.split()
            if len(words) >= 2:
                athletes_by_first_name[norm(words[0])].append(ath)
                athletes_by_surname[norm(words[-1])].append(ath)

    return ref_clubs, ref_cores, ref_athletes, athletes_by_club, athletes_by_first_name, athletes_by_surname


if __name__ == "__main__":
    build_canonical_reference()

