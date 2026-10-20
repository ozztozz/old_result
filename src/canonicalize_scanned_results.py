"""
src/canonicalize_scanned_results.py
Sorumluluk: Taranmış/OCR kaynaklı yüzücü sonuçlarındaki (output/tyf_scanned_bireysel_yuzucu_sonuclari_raw.csv)
hatalı sporcu ve kulüp isimlerini, yapışan yaşları ve OCR gürültülerini temizlemek;
YALNIZCA metin tabanlı temiz veri setinden üretilen kanonik referans tablolarıyla (output/reference/)
ve rapidfuzz kütüphanesini kullanarak çapraz kontrol edip doğrulamak ve düzeltmek.
"""

from __future__ import annotations

import csv
import os
import re
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple
from rapidfuzz import fuzz

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.build_canonical_reference import (
    AthleteRef,
    get_club_core,
    load_canonical_reference,
    norm,
    normalize_comma_name,
    standardize_swimmer_name,
)

FERDI_TOKENS: Set[str] = {
    "peni", "egdi", "eğdi", "pere", "jrerdi", "kerdi", "erdi", "ferd", "terdi",
    "ergi", "fergi", "fercl", "rerdi", "ferdl", "terd", "1erdi", "ierdi",
    "irem", "ire", "lrerdi", "ireri", "ireli", "kergi", "kerği", "herd"
}

KNOWN_NUM_PREFIXES = (
    "09orcas", "09egitim", "39yuzme", "26porsuk", "1922salihli",
    "1986yesilova", "1954hendek", "135yuzme", "9eylul", "23nisan", "32net"
)

OCR_NOISE_PREFIX_TOKENS = {
    "as", "if", "hm", "id", "al", "fd", "ft", "dd", "mm", "m4", "m2", "m3", "m5",
    "a5", "a4", "a3", "a2", "a8", "1s", "ii", "1i2", "i2"
}

OCR_AGE_MAP = {
    "m4": "14", "mm": "14", "m2": "12", "m3": "13", "m5": "15",
    "a5": "15", "a4": "14", "a3": "13", "a2": "12", "a8": "08",
    "138": "13", "44": "14", "43": "13", "as": "15", "1s": "15",
    "id": "11", "al": "11", "4": "14"
}


def should_replace_candidate(
    clean_sp: str,
    sp_cnt: int,
    in_ref_sp: bool,
    cand: str,
    cand_cnt: int,
    in_ref_cand: bool
) -> bool:
    """
    Dosya içi bağlamda iki alternatif sporcu ismi arasında hangisinin daha doğru olduğunu belirler.
    Asla daha yüksek frekanstaki veya referanstaki doğru ismi bir OCR hatasıyla değiştirmez.
    """
    # 1. Kanonik referans kontrolü (Referansta olan kazanır)
    if in_ref_cand and not in_ref_sp:
        return True
    if in_ref_sp and not in_ref_cand:
        return False

    # 2. Karşılaşma sıklığı (Meet dosyasında dominant olan resmi isimdir)
    if cand_cnt > sp_cnt:
        return True
    if cand_cnt < sp_cnt:
        return False

    # 3. Bilinen bariz OCR hatası kontrolü (ii vs ü/u)
    if "ii" in clean_sp.lower() and "ii" not in cand.lower():
        return True

    # 4. Türkçe karakter zenginliği
    tr = set("çğıöşüÇĞİÖŞÜ")
    tr_cand = sum(1 for c in cand if c in tr)
    tr_sp = sum(1 for c in clean_sp if c in tr)
    if tr_cand > tr_sp:
        return True

    # 5. Kelime yapısı: Eğer biri birleşik (TEOBAYLAM) diğeri ayrıysa (Teo BAYLAM), ayrı olan kazanır
    cand_words = cand.split()
    sp_words = clean_sp.split()
    if len(cand_words) > len(sp_words) and all(w[0].isupper() for w in cand_words):
        return True

    return False


def clean_raw_ocr_swimmer_name(raw_name: str, current_age: str, ham_line: str = "") -> Tuple[Optional[str], str]:
    """
    Sporcu adındaki yapışan yaşları, sembolleri (©, Oo vb.) ve ara zaman gürültülerini temizler.
    Dönüş: (temizlenmiş_isim, güncellenmiş_yaş) veya (None, None) [eğer satır yüzücü değilse].
    """
    s = raw_name.strip()
    if not s:
        return None, current_age

    # 1. Rekor banner satırları, başlık/etkinlik tarihleri veya şehir adları elenir
    if re.search(r"T[ÜU]RK[İI]YE\s+REKORLAR", s, re.I) or (ham_line and re.search(r"T[ÜU]RK[İI]YE\s+REKORLAR", ham_line, re.I)):
        return None, current_age
    if ham_line and re.search(r"\b\d{1,2}\.?\s*-\s*\d{1,2}\.\d{2}\.\d{2,4}\b", ham_line):
        return None, current_age
    if s.lower() in ("antalya", "trabzon", "edirne", "istanbul", "bursa", "ankara", "izmir", "kayseri"):
        return None, current_age

    # 2. Ara zaman satırları elenir (5om, 5om:, Som, 3283 vb.)
    if re.match(r"^(?:[5S]0m|[5S]om|\d{2,4}m)\b", s, re.I) or re.match(r"^\d{2,4}\s*[:\.]", s):
        return None, current_age
    if re.match(r"^\d{4}\s+\d{4}$", s):
        return None, current_age

    # 3. Baştaki sıra numarası ve Fd/Tk/Td etiket temizliği (örn: '4. ElalSCAN' -> 'ElalSCAN', 'Fd) Kaan Berk' -> 'Kaan Berk')
    s = re.sub(r"^\d{1,3}[\.\s]+", "", s).strip()
    s = re.sub(r"^(?:\(?[TtFf][kKdD]\)?[\.\)]?\s*)+", "", s).strip()

    # 4. Bitişen isim-soyadı ayırma (örn: 'ElalSCAN' -> 'Ela lSCAN', 'KaanAKCA' -> 'Kaan AKCA')
    s = re.sub(r"([a-zçğıöşü])([A-ZÇĞİÖŞÜ]|l[A-ZÇĞİÖŞÜ])", r"\1 \2", s).strip()
    # Soyadı başında 'l' varsa 'İ' yap (örn: 'lSCAN' -> 'İSCAN')
    s = re.sub(r"\bl(?=[A-ZÇĞİÖŞÜ])", "İ", s).strip()

    # 5. İsim sonuna yapışan yaş ve OCR lekeleri: 'Oo 15', 'OoOo(15', '(o 14', ' 12'
    extracted_age = current_age
    m_age = re.search(r"\s+(?:[oO©®—~«»\"“”(|_=\+\*\.\:\;]+\s*)*(\d{1,2})$", s)
    if m_age:
        age_str = m_age.group(1)
        if len(age_str) == 2:
            if not extracted_age or len(extracted_age) < 2:
                extracted_age = age_str
        s = s[:m_age.start()].strip()

    # 6. Sona yapışan tek harf/sembol/Oo gürültüleri: '... ©', '... de', '... F', '... Oo o'
    s = re.sub(r"\s+[Ff]$", "", s).strip()
    s = re.sub(r"\s+(?:[oO©®—~«»\"“”\'’(|_=\+\*\.\:\;]+\s*)+$", "", s).strip()
    s = re.sub(r"[©®~|=_«»\"“”]+", "", s).strip()
    s = re.sub(r"[\.,:;_\-\+\*\/\(\)\[\]]+$", "", s).strip()
    # Hatalı ALTİ... kökünü ALTI...'ya düzelt (örn: ALTİNTOP -> ALTINTOP, ÖZALTİN -> ÖZALTIN)
    s = re.sub(r"ALTİ", "ALTI", s)
    s = re.sub(r"\s+", " ", s).strip()

    if not s or s.isdigit():
        return None, extracted_age

    return s, extracted_age


def clean_raw_ocr_club(raw_kl: str, current_age: str) -> Tuple[str, str]:
    """
    Kulüp sütunundaki leke, yapışan yaş veya bitiş derecelerini temizler.
    Numaralı kulüplerdeki yapışan yaşları ve 'Ferdi' varyasyonlarını ayıklar.
    """
    kl = raw_kl.strip()
    extracted_age = current_age

    # 1. Bitiş derecelerini ve zaman/puan artıklarını temizle
    kl = re.sub(r"[\s\'’\"°\=\-]+\d{1,2}:\d{2}\.\d{2}.*$", "", kl).strip()
    kl = re.sub(r"(?<=[a-zA-ZçğıöşüÇĞİÖŞÜ])[\s\'’\"°\=\-]*\d{1,2}\.\d{2}\b.*$", "", kl).strip()
    kl = re.sub(r"\b\d{2,4}\s*[iıIİl]b[uü].*$", "", kl).strip()

    # Bitişen kelimeleri ayır (Örn: 'SuSporKulübü' -> 'Su Spor Kulübü', 'IbbSporKulübü' -> 'Ibb Spor Kulübü')
    kl = re.sub(r"([a-zçğıöşü])([A-ZÇĞİÖŞÜ])", r"\1 \2", kl).strip()

    # 2. 3-haneli yapışan yaş lekesi (Örn: '138 SuSporKulübü', ', 138 SuSporKulübü', 'o 138 IbbSporKulübü')
    norm_kl = norm(kl)
    if not any(norm_kl.startswith(kc) for kc in KNOWN_NUM_PREFIXES):
        m_3dig = re.match(r"^(?:[\s\W_]*[A-Za-zçÇ\.\=\#\:\_\-\,\(\)\>\|\s]{1,3})?\s*(1[0-9])[85sS]\s*(.*)$", kl)
        if m_3dig:
            if not extracted_age or len(extracted_age) < 2:
                extracted_age = m_3dig.group(1)
            cand_club = m_3dig.group(2).strip()
            cand_club = re.sub(r"([a-zçğıöşü])([A-ZÇĞİÖŞÜ])", r"\1 \2", cand_club).strip()
            kl = cand_club

    # 3. Ferdi kontrolü
    is_ferdi = bool(
        re.search(r"\b(?:[jJlLiI1fF]?[rR]?[eE][rR]?[dD][iI1l]|jrerdi|lrerdi|ker[d|g|ğ]i|ire[m|li|r]?|ireri|peni|pere|herd|egdi|eğdi)\b", kl, re.I)
    )

    # 4. Numaralı kulüplere yapışan yaş (Örn: '10 09 Orcas...', '11 39 Yuzme...', '12 09Orcas...', '_ İ2 09 Orcas...')
    m_num = re.match(r"^[\s\W_]*([a-zA-Z0-9İıçğıöşüÇĞIÖŞÜ#]{1,3})[\s\W_]+(\d{2}\s*[a-zA-Z].*)$", kl)
    if m_num:
        cand_age = m_num.group(1).translate(str.maketrans("İıIl", "1111"))
        cand_rest = m_num.group(2).strip()
        norm_rest = norm(cand_rest)
        if any(norm_rest.startswith(kc) for kc in KNOWN_NUM_PREFIXES):
            if re.match(r"^\d{2}$", cand_age):
                if not extracted_age:
                    extracted_age = cand_age
            kl = cand_rest

    # Boşluksuz '12 09Orcas...'
    m_orcas = re.match(r"^[\s\W_]*(\d{2})[\s\W_]*(09\s*orcas.*)$", kl, re.I)
    if m_orcas:
        if not extracted_age:
            extracted_age = m_orcas.group(1)
        kl = m_orcas.group(2)

    # 5. Başa kaçan seri/kulvar/leke + 2 haneli yaş + kulüp adı
    # Örnek: '2 10 Örnek Kolej Spor Kulübü', 'N 14 Toroslar Yüzme Spor Kulübü', '. 15 SuSporKulübü'
    m_age_club = re.match(r"^(?:[\W_]*\d{1}\s+)?\s*(?:[A-Za-zçÇ\.\=\#\:\_\-\,\(\)\>\|\s]{1,4})?\s*(\d{2})\s+([A-Za-zçğıöşüÇĞİÖŞÜ].*)$", kl)
    if m_age_club:
        cand_age = m_age_club.group(1)
        cand_club = m_age_club.group(2).strip()
        norm_kl = norm(kl)
        if not any(norm_kl.startswith(kc) for kc in KNOWN_NUM_PREFIXES):
            if cand_age == "44":
                cand_age = "14"
            elif cand_age == "43":
                cand_age = "13"
            if not extracted_age or len(extracted_age) < 2:
                extracted_age = cand_age
            kl = cand_club

    # 6. Özel OCR yaş sembolleri (M4 -> 14, M2 -> 12, A8 -> 08, A5 -> 15, A4 -> 14, a3 -> 13, 138 -> 13, MM -> 14, 44 -> 14, 43 -> 13)
    kl_clean = re.sub(r"^(?:[çÇoONn\d\.\,\=\-\_\#\(\)]\s*)+", "", kl).strip()
    m_ocr = re.match(r"^([A-Za-z0-9#]{1,3})[\s\W_]+(.*)$", kl_clean)
    if m_ocr:
        tok = m_ocr.group(1).lower().replace("#", "")
        rest = m_ocr.group(2).strip()
        if tok in OCR_AGE_MAP:
            if not extracted_age or len(extracted_age) < 2:
                extracted_age = OCR_AGE_MAP[tok]
            kl = rest

    # 7. Baştaki ve sondaki genel sembol/leke temizliği
    kl = re.sub(r"^[\W_]+", "", kl).strip()
    m_noise = re.match(r"^([\w#]{1,3})\s+(.*)$", kl)
    if m_noise:
        tok = m_noise.group(1).lower().replace("i", "i").replace("ı", "i")
        rest = re.sub(r"^[\W_]+", "", m_noise.group(2)).strip()
        n_full = norm(kl)
        if not any(n_full.startswith(kc) for kc in KNOWN_NUM_PREFIXES):
            # Yalnızca sembol içeren veya bilinen OCR lekesi olan tokenlar temizlenir (Su, FB, GS, TED vb. korunur)
            if any(ch.isdigit() or ch in "#()[]_.,<>" for ch in m_noise.group(1)) or tok in OCR_NOISE_PREFIX_TOKENS or len(tok) == 1:
                if len(rest) >= 3 or is_ferdi:
                    kl = rest

    kl = re.sub(r"^[\W_]+", "", kl).strip()
    kl = re.sub(r"[\W_]+$", "", kl).strip()
    kl = re.sub(r"\s+\d{1,2}$", "", kl).strip()
    kl = re.sub(r"\s+", " ", kl).strip()

    if is_ferdi:
        kl = "Ferdi"

    return kl, extracted_age


def canonicalize_club(
    cleaned_kl: str,
    athlete_name: str,
    ref_clubs: Dict[str, str],
    ref_cores: Dict[str, str],
    ref_athletes: Dict[str, List[AthleteRef]],
    club_cache: Dict[str, str]
) -> str:
    """
    Kulüp adını referans veritabanıyla (ref_clubs, ref_cores) ve sporcu profiliyle
    çapraz kontrol ederek en doğru resmi adına dönüştürür.
    """
    n_kl = norm(cleaned_kl)
    if not n_kl:
        return cleaned_kl

    if n_kl in club_cache:
        return club_cache[n_kl]

    # 1. Ferdi kontrolü
    if n_kl in FERDI_TOKENS:
        club_cache[n_kl] = "Ferdi"
        return "Ferdi"

    # 2. Tam Normalize Eşleşme (Exact Normalized Match)
    if n_kl in ref_clubs:
        res = ref_clubs[n_kl]
        club_cache[n_kl] = res
        return res

    # 3. Çekirdek İsim Eşleşmesi (Core Match: 'fatihkarakurtalphaacadei' vs 'fatihkarakurtalphaacademy')
    core_kl = get_club_core(cleaned_kl)
    if core_kl in ref_cores:
        res = ref_cores[core_kl]
        club_cache[n_kl] = res
        return res

    # 4. Çekirdek Benzerlik Eşleşmesi (Core Fuzzy Match with RapidFuzz >= 75)
    best_cand = None
    best_sim = 0.0
    for c_core, c_club in ref_cores.items():
        if c_core and core_kl and (c_core[0].isdigit() != core_kl[0].isdigit()):
            continue
        if c_core and core_kl and c_core[0].isdigit() and core_kl[0].isdigit():
            r1 = re.match(r"^\d+", c_core)
            r2 = re.match(r"^\d+", core_kl)
            if r1 and r2 and r1.group(0) != r2.group(0):
                continue
        r = fuzz.ratio(core_kl, c_core)
        if r > best_sim:
            best_sim = r
            best_cand = c_club

    if best_cand and best_sim >= 75.0:
        club_cache[n_kl] = best_cand
        return best_cand

    # 5. Tam Normalize Benzerlik Eşleşmesi (Full Norm Fuzzy Match with RapidFuzz >= 75)
    for r_norm, r_club in ref_clubs.items():
        if r_norm and n_kl and (r_norm[0].isdigit() != n_kl[0].isdigit()):
            continue
        if r_norm and n_kl and r_norm[0].isdigit() and n_kl[0].isdigit():
            r1 = re.match(r"^\d+", r_norm)
            r2 = re.match(r"^\d+", n_kl)
            if r1 and r2 and r1.group(0) != r2.group(0):
                continue
        r = fuzz.ratio(n_kl, r_norm)
        if r > best_sim:
            best_sim = r
            best_cand = r_club

    if best_cand and best_sim >= 75.0:
        club_cache[n_kl] = best_cand
        return best_cand

    # 6. Sporcunun bilinen kanonik kulüp profiliyle doğrudan doğrulama
    if athlete_name:
        n_sp = norm(athlete_name)
        if n_sp in ref_athletes:
            for ath in ref_athletes[n_sp]:
                for c_club in ath.all_clubs:
                    if c_club:
                        n_cand = norm(c_club)
                        if fuzz.ratio(n_kl, n_cand) >= 50.0 or n_cand in n_kl or n_kl in n_cand:
                            club_cache[n_kl] = c_club
                            return c_club

    club_cache[n_kl] = cleaned_kl
    return cleaned_kl


def canonicalize_scanned_dataset(
    scanned_csv: str | Path | List[str | Path] = "output/taranmis_bireysel_yuzucu_sonuclari_raw.csv",
    out_cleaned_csv: str | Path = "output/taranmis_bireysel_yuzucu_sonuclari.csv",
    out_report_csv: str | Path = "output/reference/scanned_sporcu_duzeltme_raporu.csv"
):
    """Taranmış yüzücü verisini metin tabanlı referans veritabanıyla çapraz kontrol ederek düzeltir."""
    if isinstance(scanned_csv, (str, Path)):
        csv_list = [Path(scanned_csv)]
    else:
        csv_list = [Path(p) for p in scanned_csv]

    rows: List[Dict[str, Any]] = []
    for cp in csv_list:
        if cp.exists():
            with open(cp, encoding="utf-8-sig") as f:
                rows.extend(list(csv.DictReader(f)))

    # YALNIZCA metin tabanlı temiz veriden üretilen kanonik referansları yükle
    ref_clubs, ref_cores, ref_athletes, athletes_by_club, athletes_by_first_name, athletes_by_surname = load_canonical_reference()

    club_cache: Dict[str, str] = {}

    print(f"\nİncelenecek taranmış ham yüzücü satırı sayısı: {len(rows)}")

    # 1. Aşama: Dosya içi bilinen yüksek güvenilirlikli sporcuları ve yaşları topla
    file_team_athletes = defaultdict(lambda: Counter())
    file_swimmer_ages = defaultdict(Counter)

    for r in rows:
        fn = r["Dosya Adı"]
        ham = r.get("Ham Satır", "")
        sp, yb = clean_raw_ocr_swimmer_name(r["Sporcu"], r["Yaş"], ham)
        if sp is None:
            continue
        kl, yb = clean_raw_ocr_club(r["Kulüp"], yb)
        canon_kl = canonicalize_club(kl, sp, ref_clubs, ref_cores, ref_athletes, club_cache)
        if sp:
            n_sp = norm(sp)
            if yb and len(yb) == 2 and yb.isdigit():
                file_swimmer_ages[(fn, n_sp)][yb] += 1
            if n_sp in ref_athletes:
                canon_ref = ref_athletes[n_sp][0].canonical_name
                file_team_athletes[(fn, yb, norm(canon_kl))][canon_ref] += 1
            else:
                file_team_athletes[(fn, yb, norm(canon_kl))][standardize_swimmer_name(sp)] += 1

    valid_rows: List[Dict[str, Any]] = []
    audit_report: List[Dict[str, Any]] = []

    dropped_count = 0
    exact_matched = 0
    team_fuzzy_matched = 0
    pool_fuzzy_matched = 0
    ocr_char_matched = 0
    file_context_matched = 0
    trailing_word_matched = 0
    cleaned_only = 0
    club_cleaned_count = 0
    age_recovered_count = 0

    for r in rows:
        raw_sp = r["Sporcu"]
        raw_yb = r["Yaş"]
        raw_kl = r["Kulüp"]
        fn = r["Dosya Adı"]
        ham = r.get("Ham Satır", "")

        # 1. Ad ve yaş ön temizliği
        clean_sp, clean_yb = clean_raw_ocr_swimmer_name(raw_sp, raw_yb, ham)
        if clean_sp is None:
            dropped_count += 1
            continue

        # 2. Kulüp ve yaş ön temizliği
        clean_kl, clean_yb = clean_raw_ocr_club(raw_kl, clean_yb)

        # 3. KULÜP KANONİK EŞLEŞTİRMESİ (ÖNCE KULÜP DÜZELTİLİR)
        canon_kl = canonicalize_club(clean_kl, clean_sp, ref_clubs, ref_cores, ref_athletes, club_cache)
        if canon_kl != raw_kl:
            club_cleaned_count += 1

        # 4. SPORCU ADI KANONİK EŞLEŞTİRMESİ (REFERANS TABLOSU + BENZERLİK ARAMASI)
        norm_sp = norm(clean_sp)
        match_type = "ORIJINAL"
        matched_name = clean_sp

        # 4a. Tam Normalize Referans Eşleşmesi (Exact Normalized Reference Match)
        if norm_sp in ref_athletes:
            candidates = ref_athletes[norm_sp]
            best_cand = None
            # Önce kulüp eşleşmesi kontrol et (Kullanıcı kuralı: sporcunun takımı doğrulanır)
            if canon_kl:
                n_ckl = norm(canon_kl)
                for ath in candidates:
                    for c_club in ath.all_clubs:
                        if c_club and (norm(c_club) == n_ckl or fuzz.ratio(norm(c_club), n_ckl) >= 75.0):
                            best_cand = ath.canonical_name
                            match_type = "TAM_REFERANS_KULUP_ONAYLI"
                            break
                    if best_cand:
                        break

            # Kulüp tutmadıysa yaş kontrol et
            if not best_cand:
                for ath in candidates:
                    if clean_yb and ath.age == clean_yb:
                        best_cand = ath.canonical_name
                        match_type = "TAM_REFERANS_YAS_ONAYLI"
                        break

            # Hiçbiri tutmadıysa en yüksek yarış sayısına sahip profili seç
            if not best_cand:
                best_cand = max(candidates, key=lambda a: a.race_count).canonical_name
                match_type = "TAM_REFERANS_ESLESMESI"

            matched_name = best_cand
            exact_matched += 1

        # 4b. Takım İçi Benzerlik Eşleşmesi (Kullanıcı Kuralı 4 & 5: Takım içi RapidFuzz arama)
        if match_type == "ORIJINAL" and canon_kl:
            n_canon_kl = norm(canon_kl)
            if n_canon_kl in athletes_by_club:
                best_team_cand = None
                best_team_r = 0.0
                for ath in athletes_by_club[n_canon_kl]:
                    r_sim = fuzz.ratio(norm_sp, norm(ath.canonical_name))
                    threshold = 70.0 if (clean_yb and ath.age == clean_yb) else 78.0
                    if r_sim >= threshold and r_sim > best_team_r:
                        best_team_r = r_sim
                        best_team_cand = ath.canonical_name
                if best_team_cand:
                    matched_name = best_team_cand
                    match_type = f"TAKIM_ICI_BENZERLIK_{best_team_r:.0f}"
                    team_fuzzy_matched += 1

        # 4c. Dosya İçi Bağlam Eşleşmesi (Aynı dosya, aynı kulüp ve yaşta taranan sporcular)
        # Örnek 1: 'Alp TEOBAYLAM' <-> 'Alp Teo BAYLAM' (Birleşik kelime düzeltmesi)
        # Örnek 2: 'Elif Özt OPRAK' <-> 'Elif ÖZTOPRAK' (Bölünmüş soyadı düzeltmesi)
        # Örnek 3: 'Riizgar AGAOGLU' <-> 'Rüzgar AĞAOĞLU' (OCR leke/harf düzeltmesi)
        # Örnek 4: 'Ahmet Emir ln ©' <-> 'Ahmet Emir BAŞKONYALI' (Kırpılmış soyadı düzeltmesi)
        if match_type == "ORIJINAL":
            team_key = (fn, clean_yb, norm(canon_kl))
            if team_key in file_team_athletes:
                cands_map = file_team_athletes[team_key]
                sp_words = clean_sp.split()
                clean_sp_std = standardize_swimmer_name(clean_sp)
                sp_cnt = cands_map.get(clean_sp_std, 1)
                in_ref_sp = (norm_sp in ref_athletes)
                matching_candidates = []

                # A. Tam normalize eşleşme (kelime bölünmesi veya birleşmesi)
                for cand, cnt in cands_map.items():
                    if norm(cand) == norm_sp and cand != clean_sp:
                        cand_words = cand.split()
                        if len(cand_words) < 2 or len(cand_words[-1]) <= 2:
                            continue
                        in_ref_cand = (norm(cand) in ref_athletes)
                        if should_replace_candidate(clean_sp, sp_cnt, in_ref_sp, cand, cnt, in_ref_cand):
                            matching_candidates = [cand]
                            break

                # B. Takım ve dosya içi yüksek benzerlik (rapidfuzz >= 80)
                if not matching_candidates:
                    best_cand = None
                    best_sc = 0.0
                    for cand, cnt in cands_map.items():
                        if norm(cand) == norm_sp:
                            continue
                        cand_words = cand.split()
                        if len(cand_words) < 2 or len(cand_words[-1]) <= 2:
                            continue
                        sc = fuzz.ratio(norm_sp, norm(cand))
                        if sc >= 80.0 and sc > best_sc:
                            in_ref_cand = (norm(cand) in ref_athletes)
                            if should_replace_candidate(clean_sp, sp_cnt, in_ref_sp, cand, cnt, in_ref_cand):
                                best_sc = sc
                                best_cand = cand
                    if best_cand:
                        matching_candidates = [best_cand]

                # C. İlk isimler aynı, soyadı kırpılmış veya lekeye dönüşmüş
                if not matching_candidates:
                    if len(sp_words) >= 2:
                        surname_is_junk = len(sp_words[-1]) <= 2 or not sp_words[-1].isupper()
                        first_names_str = " ".join(sp_words[:-1])

                        for cand, cnt in cands_map.items():
                            if norm(cand) == norm_sp:
                                continue
                            cand_words = cand.split()
                            if len(cand_words) < 2 or len(cand_words[-1]) <= 2:
                                continue

                            cand_first = " ".join(cand_words[:-1])
                            cand_surname = cand_words[-1]
                            raw_surname = sp_words[-1]
                            in_ref_cand = (norm(cand) in ref_athletes)

                            if surname_is_junk and norm(cand_first) == norm(first_names_str):
                                if should_replace_candidate(clean_sp, sp_cnt, in_ref_sp, cand, cnt, in_ref_cand):
                                    matching_candidates.append(cand)
                            elif norm(cand_first) == norm(first_names_str) and fuzz.ratio(cand_surname.lower(), raw_surname.lower()) >= 75.0:
                                if should_replace_candidate(clean_sp, sp_cnt, in_ref_sp, cand, cnt, in_ref_cand):
                                    matching_candidates.append(cand)

                    elif len(sp_words) == 1:
                        norm_single = norm(clean_sp)
                        for cand, cnt in cands_map.items():
                            if norm(cand) == norm_single:
                                continue
                            cand_words = cand.split()
                            if len(cand_words) < 2 or len(cand_words[-1]) <= 2:
                                continue
                            in_ref_cand = (norm(cand) in ref_athletes)
                            if norm(cand) == norm_single or fuzz.ratio(norm(cand), norm_single) >= 75.0:
                                if should_replace_candidate(clean_sp, sp_cnt, in_ref_sp, cand, cnt, in_ref_cand):
                                    matching_candidates.append(cand)

                if len(matching_candidates) == 1:
                    resolved = matching_candidates[0]
                    # Kanonik referansta daha doğru yazımı varsa yükselt
                    if norm(resolved) in ref_athletes:
                        resolved = ref_athletes[norm(resolved)][0].canonical_name
                    matched_name = resolved
                    match_type = "DOSYA_BAGLAM_ESLESMESI"
                    file_context_matched += 1

        # 4d. Genel Referans Havuzunda İlk İsim / Soyadı İndeksinden Arama + Kulüp Onayı
        if match_type == "ORIJINAL":
            words = clean_sp.split()
            # Eğer soyadı 1-2 harflik leke ise (örn: 'ln'), genel havuzdan tek harfli isimlerle eşleşme engellenir
            if words and len(words[-1]) > 2:
                cand_pool: List[AthleteRef] = []
                cand_pool.extend(athletes_by_first_name.get(norm(words[0]), []))
                cand_pool.extend(athletes_by_surname.get(norm(words[-1]), []))

                best_pool_cand = None
                best_pool_r = 0.0
                n_canon_kl = norm(canon_kl) if canon_kl else ""

                for ath in cand_pool:
                    has_club = any(norm(c) == n_canon_kl or fuzz.ratio(n_canon_kl, norm(c)) >= 75.0 for c in ath.all_clubs) if n_canon_kl else False
                    r_sim = fuzz.ratio(norm_sp, norm(ath.canonical_name))

                    # Eşik belirleme: Kulüp onaylı ise 75, yaş tutuyorsa 80, aksi takdirde 85
                    if has_club:
                        threshold = 75.0
                    elif clean_yb and ath.age == clean_yb:
                        threshold = 80.0
                    else:
                        threshold = 85.0

                    if r_sim >= threshold and r_sim > best_pool_r:
                        best_pool_r = r_sim
                        best_pool_cand = ath.canonical_name

                if best_pool_cand:
                    matched_name = best_pool_cand
                    match_type = f"HAVUZ_BENZERLIK_{best_pool_r:.0f}"
                    pool_fuzzy_matched += 1

        # 4g. Referans Harici Standartlaştırma (Formatlama)
        if match_type == "ORIJINAL":
            canon_attempt = standardize_swimmer_name(clean_sp)
            if canon_attempt != clean_sp:
                matched_name = canon_attempt
                match_type = "STANDARTLASMA"
                cleaned_only += 1

        # 5. Eksik veya Tek Haneli Yaş Kurtarma
        if not clean_yb or len(clean_yb) < 2 or not clean_yb.isdigit():
            n_matched = norm(matched_name)
            # Dosya içi diğer yarışlardan kontrol et
            if (fn, n_matched) in file_swimmer_ages:
                clean_yb = file_swimmer_ages[(fn, n_matched)].most_common(1)[0][0]
                age_recovered_count += 1
            # Referans profilinden kontrol et (kulüp eşleşmesi öncelikli)
            elif n_matched in ref_athletes:
                for ath in ref_athletes[n_matched]:
                    if ath.age and len(ath.age) == 2 and ath.age.isdigit():
                        if not canon_kl or any(norm(c) == norm(canon_kl) for c in ath.all_clubs):
                            clean_yb = ath.age
                            age_recovered_count += 1
                            break

        r["Sporcu"] = matched_name
        r["Yaş"] = clean_yb
        r["Kulüp"] = canon_kl

        if matched_name != raw_sp or clean_yb != raw_yb or canon_kl != raw_kl:
            audit_report.append({
                "Dosya Adı": fn,
                "Ham Sporcu": raw_sp,
                "Düzeltilmiş Sporcu": matched_name,
                "Ham Yaş": raw_yb,
                "Düzeltilmiş Yaş": clean_yb,
                "Ham Kulüp": raw_kl,
                "Düzeltilmiş Kulüp": canon_kl,
                "Sporcu Eşleşme Yöntemi": match_type
            })

        valid_rows.append(r)

    # Güncellenmiş CSV'yi kaydet
    fieldnames = list(valid_rows[0].keys())
    os.makedirs(os.path.dirname(str(out_cleaned_csv)), exist_ok=True)
    with open(out_cleaned_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(valid_rows)

    # Denetim raporunu kaydet
    os.makedirs(os.path.dirname(str(out_report_csv)), exist_ok=True)
    if audit_report:
        with open(out_report_csv, "w", encoding="utf-8-sig", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(audit_report[0].keys()))
            writer.writeheader()
            writer.writerows(audit_report)

    print("\n" + "=" * 65)
    print("      TARANMIŞ VERİ SETİ SPORCU VE KULÜP DOĞRULAMA RAPORU     ")
    print("=" * 65)
    print(f" Toplam İşlenen Satır          : {len(rows):6d}")
    print(f" Elenen Ara Zaman / Geçersiz   : {dropped_count:6d}")
    print(f" Geçerli Yüzücü Sonucu         : {len(valid_rows):6d}")
    print(f" Tam Referans Eşleşmesi        : {exact_matched:6d}")
    print(f" Takım İçi Benzerlik Eşleşmesi : {team_fuzzy_matched:6d}")
    print(f" Havuz Benzerlik Eşleşmesi     : {pool_fuzzy_matched:6d}")
    print(f" OCR Harf Değişimi Eşleşmesi   : {ocr_char_matched:6d}")
    print(f" Sona Yapışan Kelime Temizliği : {trailing_word_matched:6d}")
    print(f" Dosya İçi Bağlam Düzeltmesi   : {file_context_matched:6d}")
    print(f" Temizlenen / Standartlaşan    : {cleaned_only:6d}")
    print(f" Düzeltilen Kulüp Sayısı       : {club_cleaned_count:6d}")
    print(f" Kurtarılan Yaş Sayısı         : {age_recovered_count:6d}")
    print(f" Toplam Değişen / Düzelen Satır: {len(audit_report):6d}")
    print(f" Çıktı CSV                     : {out_cleaned_csv}")
    print(f" Denetim Raporu CSV            : {out_report_csv}")
    print("=" * 65)


if __name__ == "__main__":
    canonicalize_scanned_dataset()
