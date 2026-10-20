import re
import sys
from pathlib import Path
from rapidfuzz import fuzz

sys.path.insert(0, r'c:\Users\OZDEN\Desktop\old_result')

from src.build_canonical_reference import load_canonical_reference, norm, get_club_core

ref_clubs, ref_cores, ref_athletes, athletes_by_club, athletes_by_first_name, athletes_by_surname = load_canonical_reference()

OCR_NOISE_PREFIX_TOKENS = {
    'as', 'if', 'hm', 'id', 'al', 'fd', 'ft', 'dd', 'mm', 'm4', 'm2', 'm3', 'm5',
    'a5', 'a4', 'a3', 'a2', 'a8', '1s', 'ii', '1i2', 'i2'
}

KNOWN_NUM_PREFIXES = (
    '09orcas', '09egitim', '39yuzme', '26porsuk', '1922salihli',
    '1986yesilova', '1954hendek', '135yuzme', '9eylul', '23nisan', '32net'
)

FERDI_TOKENS = {
    'peni', 'egdi', 'eğdi', 'pere', 'jrerdi', 'kerdi', 'erdi', 'ferd', 'terdi',
    'ergi', 'fergi', 'fercl', 'rerdi', 'ferdl', 'terd', '1erdi', 'ierdi',
    'irem', 'ire', 'lrerdi', 'ireri', 'ireli', 'kergi', 'kerği', 'herd'
}

def clean_test_club(raw_kl: str):
    kl = raw_kl.strip()
    kl = re.sub(r"[\s\'\’\"°\=\-]+\d{1,2}:\d{2}\.\d{2}.*$", "", kl).strip()
    kl = re.sub(r"(?<=[a-zA-ZçğıöşüÇĞİÖŞÜ])[\s\'\’\"°\=\-]*\d{1,2}\.\d{2}\b.*$", "", kl).strip()
    kl = re.sub(r"\b\d{2,4}\s*[iıIİl]b[uü].*$", "", kl).strip()
    kl = re.sub(r"([a-zçğıöşü])([A-ZÇĞİÖŞÜ])", r"\1 \2", kl).strip()

    is_ferdi = bool(re.search(r"\b(?:[jJlLiI1fF]?[rR]?[eE][rR]?[dD][iI1l]|jrerdi|lrerdi|ker[d|g|ğ]i|ire[m|li|r]?|ireri|peni|pere|herd|egdi|eğdi)\b", kl, re.I))

    # 3-digit stuck age: e.g. 138 SuSporKulübü
    m_3dig = re.match(r"^(?:[^\w\s]{0,3})?\s*(1[0-9])[85sS]\s*(.*)$", kl)
    if m_3dig:
        cand_club = m_3dig.group(2).strip()
        cand_club = re.sub(r"([a-zçğıöşü])([A-ZÇĞİÖŞÜ])", r"\1 \2", cand_club).strip()
        kl = cand_club

    # Strip leading non-alphanumeric punctuation
    kl = re.sub(r"^[^\w]+", "", kl).strip()

    # Numarali kulup
    m_num = re.match(r"^([\w#]{1,3})\s+(\d{2}\s*[a-zA-Z].*)$", kl)
    if m_num:
        cand_rest = m_num.group(2).strip()
        if any(norm(cand_rest).startswith(kc) for kc in KNOWN_NUM_PREFIXES):
            kl = cand_rest

    # Strip leading noise token (as, #4, İf, HM, İ2, 4, etc.)
    m_noise = re.match(r"^([\w#]{1,3})\s+(.*)$", kl)
    if m_noise:
        tok = m_noise.group(1).lower().replace("i", "i").replace("ı", "i")
        rest = m_noise.group(2).strip()
        n_full = norm(kl)
        if not any(n_full.startswith(kc) for kc in KNOWN_NUM_PREFIXES):
            if any(ch.isdigit() or ch in "#()[]_.,<>" for ch in m_noise.group(1)) or tok in OCR_NOISE_PREFIX_TOKENS or len(tok) == 1:
                if len(rest) >= 3 or is_ferdi:
                    kl = rest

    kl = re.sub(r"^[^\w]+", "", kl).strip()
    kl = re.sub(r"[^\w]+$", "", kl).strip()
    kl = re.sub(r"\s+\d{1,2}$", "", kl).strip()
    kl = re.sub(r"\s+", " ", kl).strip()

    if is_ferdi:
        return "Ferdi"
    return kl

def canon_test(raw_kl: str):
    cleaned = clean_test_club(raw_kl)
    if cleaned == "Ferdi":
        return "Ferdi"
    n_kl = norm(cleaned)
    if n_kl in FERDI_TOKENS:
        return "Ferdi"
    if n_kl in ref_clubs:
        return ref_clubs[n_kl]
    core = get_club_core(cleaned)
    if core in ref_cores:
        return ref_cores[core]
    best_c = None
    best_s = 0.0
    for c_core, c_kl in ref_cores.items():
        s = fuzz.ratio(core, c_core)
        if s > best_s:
            best_s = s
            best_c = c_kl
    if best_c and best_s >= 75.0:
        return best_c
    return cleaned

test_cases = [
    '_ as Marlin Yüzme Spor Kulübü',
    '#4 “Uşak Royal Spor Kulübü',
    '_ İf Ardeşen Olimpik Spor Kulübü',
    '_ İf Alanya Deniz Aslanları Spor Kulübü',
    '_ HM Ornek Kolej Spor Kulübü',
    '_ İ2 Anabilim Spor Kulübü',
    '_ fd peni',
    '_ ft eğdi',
    '_ ‘dd ‘Pars Su Sporları Gençlik Ve Spor Kulüb',
    ', (4 VAMOS',
    ', (4 V.A.M.O.S',
    '_ As Ted Ankara Kolejliler Spor Kulübü',
    '_ 1İ2 Yildirim Belediyesi Jimnastik Spor Kulul',
    '_ İ2 09 Orcas Spor Kulubu',
    '_ İ2 Antalya Faroz Spor Kulubu',
    '_ İ2 Bodrum Yuzme thtisas',
    '_ İf Afyonkarahisar Elit Genclik Ve Spor Kulul',
    '138 SuSporKulübü'
]

for tc in test_cases:
    print(f"{tc:46} -> {canon_test(tc)}")
