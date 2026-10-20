import csv, os, re, sys, time
from collections import defaultdict, Counter
from pathlib import Path
from rapidfuzz import fuzz

sys.stdout.reconfigure(encoding="utf-8")

TR_NORM_MAP = str.maketrans("çğıöşüÇĞİÖŞÜ", "cgiosuCGIOSU")

def norm(s: str) -> str:
    if not s: return ""
    clean = s.translate(TR_NORM_MAP).lower()
    return re.sub(r"[^a-z0-9]", "", clean)

def get_club_core(s: str) -> str:
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

# Suffix cleaning & standardizing
def clean_club_text_suffix(s: str) -> str:
    c = s.strip()
    c = re.sub(r"\s+S\.?\s*K\.?$", " Spor Kulübü", c, flags=re.I)
    c = re.sub(r"\s+Sk\.?$", " Spor Kulübü", c, flags=re.I)
    c = re.sub(r"\bKulubü\b", "Kulübü", c)
    c = re.sub(r"\bKulubu\b", "Kulübü", c)
    c = re.sub(r"\bDernegi\b", "Derneği", c)
    c = re.sub(r"\s+", " ", c).strip()
    return c

print("Loading metin_tabanli dataset for reference testing...")
t0 = time.perf_counter()

# Step 1: Load ONLY text-based results
raw_swimmers = []
with open("output/metin_tabanli_bireysel_yuzucu_sonuclari.csv", encoding="utf-8-sig") as f:
    for r in csv.DictReader(f):
        raw_swimmers.append(r)

print(f"Loaded {len(raw_swimmers):,} text records in {time.perf_counter() - t0:.2f}s")

# Count raw clubs
raw_club_counts = Counter()
for r in raw_swimmers:
    kl = r.get("Kulüp", "").strip()
    if kl and len(re.findall(r"[a-zA-ZçğıöşüÇĞİÖŞÜ]", kl)) >= 3:
        if not any(ch in kl for ch in (':', ';', '/')) and not re.search(r'(?:baraj|rekor|25m|50m)', kl, re.I):
            raw_club_counts[kl] += 1

# Normalize & cluster clubs
cleaned_club_counts = Counter()
club_to_cleaned = {}
for kl, cnt in raw_club_counts.items():
    c = clean_club_text_suffix(kl)
    club_to_cleaned[kl] = c
    cleaned_club_counts[c] += cnt

# Group by core
core_to_candidates = defaultdict(Counter)
for c, cnt in cleaned_club_counts.items():
    core = get_club_core(c)
    core_to_candidates[core][c] += cnt

# Determine dominant canonical name for each core
core_to_canonical = {}
for core, cand_counts in core_to_candidates.items():
    # Prefer names with 'Spor Kulübü' or highest count
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

# Mapping raw club -> final canonical club
raw_to_canonical_club = {}
for raw_kl in raw_club_counts:
    cleaned = club_to_cleaned[raw_kl]
    core = get_club_core(cleaned)
    raw_to_canonical_club[raw_kl] = core_to_canonical.get(core, cleaned)

canonical_club_counts = Counter(raw_to_canonical_club.values())
print(f"Step 1 Complete: {len(raw_club_counts):,} raw clubs unified into {len(canonical_club_counts):,} canonical clubs.")

# Step 2 & 3: Athletes from text data, mapped to Step 1's canonical club
athletes_profiles = defaultdict(lambda: {"names": Counter(), "clubs": Counter(), "birth_years": Counter(), "count": 0})

for r in raw_swimmers:
    sp = r.get("Sporcu", "").strip()
    yb = r.get("Yaş", "").strip()
    raw_kl = r.get("Kulüp", "").strip()
    if sp:
        canon_kl = raw_to_canonical_club.get(raw_kl, raw_kl)
        n_sp = norm(sp)
        ath = athletes_profiles[(n_sp, yb)]
        ath["names"][sp] += 1
        if canon_kl:
            ath["clubs"][canon_kl] += 1
        if yb:
            ath["birth_years"][yb] += 1
        ath["count"] += 1

print(f"Step 2 & 3 Complete: {len(athletes_profiles):,} unique athlete profiles generated with canonical clubs.")

# Test fuzzy swimmer matching with rapidfuzz
ref_athletes_by_club = defaultdict(list)
ref_athletes = defaultdict(list)
for (n_sp, yb), data in athletes_profiles.items():
    best_name = data["names"].most_common(1)[0][0]
    best_club = data["clubs"].most_common(1)[0][0] if data["clubs"] else ""
    entry = (best_name, yb, best_club)
    ref_athletes[n_sp].append(entry)
    if best_club:
        ref_athletes_by_club[norm(best_club)].append(entry)

print(f"Built athlete index by club for {len(ref_athletes_by_club):,} clubs.")

# Test OCR typo case using rapidfuzz
test_ocr_cases = [
    ("Rabia TUNG", "12", "Fatih Karakurt Alpha Academy Spor Kulübü"),
    ("Serenay Tuğçe GULOKSUZ", "14", "Ferdi"),
    ("Falih Karakurt Alpha Acade", "13", "Fatih Karakurt Alpha Academy Spor Kulübü"),
    ("Omer BAYDAR", "13", "Fatih Karakurt Alpha Academy Spor Kulübü")
]

print("\n--- Testing RapidFuzz Matching ---")
for raw_sp, yb, target_club in test_ocr_cases:
    n_sp = norm(raw_sp)
    n_club = norm(target_club)
    # Search within club athletes
    best_cand = None
    best_score = 0
    if n_club in ref_athletes_by_club:
        for c_sp, c_yb, c_kl in ref_athletes_by_club[n_club]:
            score = fuzz.ratio(n_sp, norm(c_sp))
            if score > best_score:
                best_score = score
                best_cand = c_sp
    print(f"Query: {raw_sp:25} in {target_club[:25]} -> Best Match: {best_cand} (Score: {best_score})")

