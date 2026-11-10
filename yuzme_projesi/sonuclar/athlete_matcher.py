# -*- coding: utf-8 -*-
"""
athlete_matcher.py
==================
Gelen istekteki sporcu adı, doğum yılı / doğum tarihi ve kulüp bilgisine göre
veritabanındaki Sporcu kayıtlarıyla eşleştirme yapar.

1. Tam Eşleşme (Exact Match): Ad-soyad ve doğum yılı tam uyuştuğunda doğrudan sporcu ID'si döner.
2. Muhtemel Eşleşmeler (Probable Matches): Tam eşleşme yoksa RapidFuzz benzerlik oranına göre
   en yüksek puanlı muhtemel adayları liste halinde döner.
"""

from __future__ import annotations
import re
from typing import Dict, Any, List, Optional
from django.db.models import Q
from .models import Sporcu

try:
    from rapidfuzz import fuzz
except ImportError:
    fuzz = None


def clean_athlete_name_tags(name: Optional[str]) -> str:
    """
    Sporcu adında bulunan (fd), (tk), (td), (f5), ferdi, tasnif dışı vb.
    parantez içi veya ek etiketleri ve baştaki/sondaki artık karakterleri temizler.
    Maskeli (* içeren) veya normal tüm isimlerde güvenle çalışır, yıldızları korur.
    """
    if not name:
        return ""
    s = str(name).strip()
    # 1. Parantez veya köşeli parantez içindeki tipik etiketler:
    # (fd), (tk), (td), (f1)-(f9), (t1)-(t9), (ferdi), (tasnif dışı), (okul) vb.
    s = re.sub(
        r'\s*[\(\[]\s*(?:[FfTt][DdKk0-9]|FERD[İI]|TASN[İI]F\s*DI[ŞS][Iİ]|OKUL|KUL[ÜU]P)[^\)\]]*[\)\]]',
        ' ',
        s,
        flags=re.IGNORECASE
    )
    # 2. Baştaki tek parantez veya artık işaretler: örn: "( Metehan İŞLER" -> "Metehan İŞLER" (yıldızlar korunur)
    s = re.sub(r'^\s*[\(\[\{\<\-\+\/\\.,:;~_]\s*', '', s)
    # 3. Kelime başında veya sonunda bağımsız kalan FD/TK/TD etiketleri
    s = re.sub(r'^\s*(?:[FfTt][DdKk])\b[\.\)]?\s*', ' ', s, flags=re.IGNORECASE)
    s = re.sub(r'\s*\b(?:[FfTt][DdKk])[\.\)]?\s*$', ' ', s, flags=re.IGNORECASE)
    # 4. Sondaki artık parantez veya işaretler (yıldızlar korunur)
    s = re.sub(r'\s*[\)\]\}\>\-\+\/\\.,:;~_]\s*$', '', s)
    # 5. Çift boşlukları temizle
    return re.sub(r'\s+', ' ', s).strip()


def normalize_tr(s: Optional[str], keep_asterisks: bool = False) -> str:
    """Türkçe karakterleri ve noktalama işaretlerini eşleştirme için normalize eder."""
    if not s:
        return ""
    mapping = {
        'İ': 'I', 'ı': 'I', 'I': 'I', 'i': 'I',
        'Ş': 'S', 'ş': 'S',
        'Ğ': 'G', 'ğ': 'G',
        'Ü': 'U', 'ü': 'U',
        'Ö': 'O', 'ö': 'O',
        'Ç': 'C', 'ç': 'C'
    }
    cleaned = ''.join(mapping.get(c, c) for c in str(s).strip().upper())
    pattern = r'[^A-Z0-9\s\*]' if keep_asterisks else r'[^A-Z0-9\s]'
    cleaned = re.sub(pattern, ' ', cleaned)
    return re.sub(r'\s+', ' ', cleaned).strip()


def token_1to1_match(m_tok: str, c_tok: str) -> bool:
    """
    1-e-1 (birebir karakter) maskeli token eşleştirmesi.
    Her '*' tam olarak 1 karaktere denk gelir.
    Örn: 'D***Z' -> 5 harf, 'DENIZ' -> 5 harf => True
         'D***Z' -> 'DERYA' (son harf Z değil) => False
         'D***Z' -> 'DENIZHAN' (uzunluk 8 != 5) => False
    """
    if len(m_tok) != len(c_tok):
        return False
    for m_c, c_c in zip(m_tok, c_tok):
        if m_c == '*':
            continue
        if m_c != c_c:
            return False
    return True


def match_masked_athlete_exact(
    masked_name: str,
    birth_year: Any = None,
    gender: Optional[str] = None,
    club: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Maskeli (*'lı) sporcu adını veritabanındaki kayıtlarla '1 yıldız = 1 harf'
    deterministik kuralıyla eşleştirir.
    """
    clean_masked = clean_athlete_name_tags(masked_name)
    if not clean_masked:
        return {
            "durum": "gecersiz_istek",
            "sonuc": "yok",
            "bulunan_id": None,
            "sporcu": None,
            "muhtemel_eslesmeler": [],
            "mesaj": "Geçerli bir sporcu adı belirtilmelidir.",
            "sorgu": {"ad": masked_name, "dogum_yili": birth_year, "kulup": club, "cinsiyet": gender}
        }

    target_year = parse_year(birth_year)
    norm_club = normalize_tr(club) if club else None

    target_gender = None
    if gender:
        g = str(gender).strip().upper()
        if g.startswith("E") or "BOY" in g or "MALE" in g or "MEN" in g:
            target_gender = "ERKEK"
        elif g.startswith("K") or "GIRL" in g or "FEMALE" in g or "WOMEN" in g:
            target_gender = "KADIN"

    sorgu_info = {
        "ad": masked_name.strip(),
        "temiz_ad": clean_masked,
        "dogum_yili": target_year,
        "kulup": club.strip() if club else None,
        "cinsiyet": target_gender
    }

    norm_m_tokens = [normalize_tr(w, keep_asterisks=True) for w in clean_masked.split() if w]
    if not norm_m_tokens:
        return {
            "durum": "bulunamadi",
            "sonuc": "yok",
            "bulunan_id": None,
            "sporcu": None,
            "muhtemel_eslesmeler": [],
            "sorgu": sorgu_info
        }

    def _search_in_pool(year_filter, gender_filter):
        cand_qs = Sporcu.objects.exclude(sporcu_adi__startswith="Maskeli sporcu").select_related('birincil_kulup').prefetch_related('kulup_tarihcesi__kulup')
        if year_filter:
            cand_qs = cand_qs.filter(Q(dogum_yili=year_filter) | Q(yas_dogum_yili=str(year_filter)[-2:]))
        if gender_filter:
            cand_qs = cand_qs.filter(Q(cinsiyet__iexact=gender_filter) | Q(cinsiyet__isnull=True) | Q(cinsiyet=""))

        matches = []
        for cand in cand_qs:
            cand_clean = clean_athlete_name_tags(cand.sporcu_adi)
            norm_c_tokens = [normalize_tr(w) for w in cand_clean.split() if w]
            if not norm_c_tokens:
                continue

            # Senaryo 1: Token sayısı birebir aynı (Örn: 'D***Z K**T' vs 'DENIZ KURT')
            is_match = False
            if len(norm_m_tokens) == len(norm_c_tokens):
                if all(token_1to1_match(mt, ct) for mt, ct in zip(norm_m_tokens, norm_c_tokens)):
                    is_match = True
            # Senaryo 2: Maskeli listede 2 isim varken veritabanında sporcunun birden fazla ilk adı olabilir
            # (Örn: 'M**** K**A' vs 'MEHMET CAN KAYA')
            elif len(norm_m_tokens) == 2 and len(norm_c_tokens) >= 3:
                if token_1to1_match(norm_m_tokens[0], norm_c_tokens[0]) and token_1to1_match(norm_m_tokens[-1], norm_c_tokens[-1]):
                    is_match = True

            if is_match:
                matches.append(cand)
        return matches

    matched_cands = _search_in_pool(target_year, target_gender)

    # Hedef yılda bulunamadıysa ve hedef yıl belirtilmişse +-1 yıl toleransı ile tekrar dene
    if not matched_cands and target_year:
        for alt_year in [target_year - 1, target_year + 1]:
            matched_cands = _search_in_pool(alt_year, target_gender)
            if matched_cands:
                break

    if len(matched_cands) == 1:
        sp = matched_cands[0]
        return {
            "durum": "basarili",
            "sonuc": "tam_eslesme",
            "bulunan_id": sp.id,
            "sporcu": _serialize_sporcu(sp, 100.0),
            "muhtemel_eslesmeler": [],
            "sorgu": sorgu_info
        }
    elif len(matched_cands) > 1:
        # Birden fazla aday varsa kulüp filtresi uygula
        if norm_club:
            club_matched = []
            for sp in matched_cands:
                cand_clubs = [normalize_tr(sp.birincil_kulup.kulup_adi)] if sp.birincil_kulup else []
                cand_clubs.extend([normalize_tr(h.kulup.kulup_adi) for h in sp.kulup_tarihcesi.all()])
                if any(c and (norm_club in c or c in norm_club) for c in cand_clubs):
                    club_matched.append(sp)
            if len(club_matched) == 1:
                sp = club_matched[0]
                return {
                    "durum": "basarili",
                    "sonuc": "tam_eslesme",
                    "bulunan_id": sp.id,
                    "sporcu": _serialize_sporcu(sp, 100.0),
                    "muhtemel_eslesmeler": [],
                    "sorgu": sorgu_info
                }
            elif len(club_matched) > 1:
                matched_cands = club_matched

        return {
            "durum": "basarili",
            "sonuc": "muhtemel_eslesmeler",
            "bulunan_id": None,
            "sporcu": None,
            "muhtemel_eslesmeler": [_serialize_sporcu(s, 95.0) for s in matched_cands],
            "sorgu": sorgu_info
        }

    return {
        "durum": "bulunamadi",
        "sonuc": "yok",
        "bulunan_id": None,
        "sporcu": None,
        "muhtemel_eslesmeler": [],
        "mesaj": "1-e-1 maskeli desen ile eşleşen sporcu bulunamadı.",
        "sorgu": sorgu_info
    }


def parse_year(val: Any) -> Optional[int]:
    """
    Tarih veya yıl girdisinden 4 basamaklı geçerli doğum yılını çıkarır.
    Örn: '2007', 2007, '07', '24.04.2007', '2007-04-24' -> 2007
    """
    if not val:
        return None
    s = str(val).strip()
    # 4 haneli yıl (1950 - 2035)
    m_full = re.search(r'\b(19\d{2}|20\d{2})\b', s)
    if m_full:
        return int(m_full.group(1))
    # 2 haneli doğum yılı ('07', '11' vb.)
    m_2dig = re.search(r'\b(\d{2})\b', s)
    if m_2dig:
        y = int(m_2dig.group(1))
        return 2000 + y if y <= 35 else 1900 + y
    return None


def match_athlete(
    name: str,
    birth_year_or_date: Any = None,
    club: Optional[str] = None,
    gender: Optional[str] = None,
    limit: int = 10
) -> Dict[str, Any]:
    """
    Sporcu adı ve doğum bilgisine göre arama ve eşleştirme yapar.
    
    Dönüş Formatı:
    {
        "durum": "basarili" | "bulunamadi" | "gecersiz_istek",
        "sonuc": "tam_eslesme" | "muhtemel_eslesmeler" | "yok",
        "bulunan_id": int | None,
        "sporcu": { ... } | None,
        "muhtemel_eslesmeler": [ { ... }, ... ],
        "sorgu": { "ad": ..., "dogum_yili": ..., "kulup": ..., "cinsiyet": ... }
    }
    """
    # 0. Aşama: İsimdeki (FD), (TK), (TD), ferdi vb. etiketleri temizle
    clean_name = clean_athlete_name_tags(name)
    if not clean_name or len(clean_name.strip()) < 2:
        return {
            "durum": "gecersiz_istek",
            "sonuc": "yok",
            "bulunan_id": None,
            "sporcu": None,
            "muhtemel_eslesmeler": [],
            "mesaj": "Geçerli bir sporcu adı belirtilmelidir.",
            "sorgu": {"ad": name, "temiz_ad": clean_name, "dogum_yili": birth_year_or_date, "kulup": club, "cinsiyet": gender}
        }

    # Eğer isimde '*' maskesi varsa 1-e-1 deterministik eşleştiriciye yönlendir
    if '*' in clean_name:
        return match_masked_athlete_exact(
            masked_name=clean_name,
            birth_year=birth_year_or_date,
            gender=gender,
            club=club,
        )

    norm_input = normalize_tr(clean_name)
    target_year = parse_year(birth_year_or_date)
    norm_club = normalize_tr(club) if club else None

    target_gender = None
    if gender:
        g = str(gender).strip().upper()
        if g.startswith("E") or "BOY" in g or "MALE" in g or "MEN" in g:
            target_gender = "ERKEK"
        elif g.startswith("K") or "GIRL" in g or "FEMALE" in g or "WOMEN" in g:
            target_gender = "KADIN"

    sorgu_info = {
        "ad": name.strip(),
        "temiz_ad": clean_name,
        "normalize_ad": norm_input,
        "dogum_yili": target_year,
        "kulup": club.strip() if club else None,
        "cinsiyet": target_gender
    }

    # ---------------------------------------------------------
    # 1. Aşama: Tam Eşleşme (Exact Match) Arama
    # ---------------------------------------------------------
    exact_qs = Sporcu.objects.select_related('birincil_kulup')
    if target_gender:
        exact_qs = exact_qs.filter(Q(cinsiyet__iexact=target_gender) | Q(cinsiyet__isnull=True) | Q(cinsiyet=""))
    if target_year:
        exact_qs = exact_qs.filter(
            Q(dogum_yili=target_year) | Q(yas_dogum_yili=str(target_year)[-2:])
        )

    # İsim birebir aynı mı? (Büyük/küçük harf ve Türkçe harf duyarsız)
    exact_matches = list(exact_qs.filter(Q(sporcu_adi__iexact=clean_name) | Q(sporcu_adi__iexact=name.strip())))
    if not exact_matches:
        # Türkçe normalize isim veya kelime sırası bağımsız tam eşleşme kontrolü
        tokens = [t for t in norm_input.split() if len(t) >= 2]
        if tokens:
            cand_token_filter = Q()
            for tok in tokens:
                cand_token_filter |= Q(sporcu_adi__icontains=tok)
            for sp in exact_qs.filter(cand_token_filter)[:100]:
                sp_clean = clean_athlete_name_tags(sp.sporcu_adi)
                sp_norm = normalize_tr(sp_clean)
                if sp_norm == norm_input or sorted(sp_norm.split()) == sorted(tokens):
                    if sp not in exact_matches:
                        exact_matches.append(sp)

    # Doğum yılı +-1 toleransı ve kulüp geçmişi ile tam isim eşleşmesi kontrolü
    if not exact_matches and target_year and norm_club:
        tol_filter = Q(dogum_yili__in=[target_year, target_year - 1, target_year + 1]) | Q(yas_dogum_yili=str(target_year)[-2:])
        if target_gender:
            tol_filter &= (Q(cinsiyet__iexact=target_gender) | Q(cinsiyet__isnull=True) | Q(cinsiyet=""))
        cand_tol = list(Sporcu.objects.filter(tol_filter, Q(sporcu_adi__iexact=clean_name) | Q(sporcu_adi__iexact=name.strip())).select_related('birincil_kulup'))
        if not cand_tol and tokens:
            cand_tol = list(Sporcu.objects.filter(tol_filter, sporcu_adi__iexact=" ".join(tokens)).select_related('birincil_kulup'))
        for sp in cand_tol:
            cand_clubs = [normalize_tr(sp.birincil_kulup.kulup_adi)] if sp.birincil_kulup else []
            cand_clubs.extend([normalize_tr(h.kulup.kulup_adi) for h in sp.kulup_tarihcesi.all()])
            if any(c and (norm_club in c or c in norm_club) for c in cand_clubs):
                exact_matches.append(sp)

    if len(exact_matches) == 1:
        sp = exact_matches[0]
        return {
            "durum": "basarili",
            "sonuc": "tam_eslesme",
            "bulunan_id": sp.id,
            "sporcu": _serialize_sporcu(sp),
            "muhtemel_eslesmeler": [],
            "sorgu": sorgu_info
        }
    elif len(exact_matches) > 1:
        # Aynı isim ve doğum yılında birden fazla sporcu varsa kulüp veya okul ile filtrele
        if norm_club:
            for sp in exact_matches:
                aktif_k = sp.aktif_kulup()
                k_norm = normalize_tr(aktif_k.kulup_adi) if aktif_k else ""
                okul_norm = normalize_tr(sp.okul()) if sp.okul() else ""
                cand_clubs = [k_norm, okul_norm]
                cand_clubs.extend([normalize_tr(h.kulup.kulup_adi) for h in sp.kulup_tarihcesi.all()])
                if any(c and (norm_club in c or c in norm_club) for c in cand_clubs):
                    return {
                        "durum": "basarili",
                        "sonuc": "tam_eslesme",
                        "bulunan_id": sp.id,
                        "sporcu": _serialize_sporcu(sp),
                        "muhtemel_eslesmeler": [],
                        "sorgu": sorgu_info
                    }
        # Kulüp uyuşmadıysa muhtemel olarak hepsini sun
        return {
            "durum": "basarili",
            "sonuc": "muhtemel_eslesmeler",
            "bulunan_id": None,
            "sporcu": None,
            "muhtemel_eslesmeler": [_serialize_sporcu(s, 99.0) for s in exact_matches],
            "sorgu": sorgu_info
        }

    # ---------------------------------------------------------
    # 2. Aşama: Muhtemel Adaylar (Fuzzy / Probable Matches) Arama
    # ---------------------------------------------------------
    tokens = [t for t in norm_input.split() if len(t) >= 2]
    cand_filter = Q()
    if target_year:
        # Hedef yıl veya +-1 yıl toleransı
        cand_filter &= (
            Q(dogum_yili__in=[target_year, target_year - 1, target_year + 1]) |
            Q(yas_dogum_yili=str(target_year)[-2:])
        )
    if target_gender:
        cand_filter &= (Q(cinsiyet__iexact=target_gender) | Q(cinsiyet__isnull=True) | Q(cinsiyet=""))

    # Aday havuzu önceliklendirme: Önce TÜM tokenları içerenleri al
    pool_qs = []
    if len(tokens) >= 2:
        all_tokens_filter = Q()
        for tok in tokens:
            all_tokens_filter &= Q(sporcu_adi__icontains=tok)
        pool_qs.extend(list(Sporcu.objects.filter(cand_filter & all_tokens_filter).select_related('birincil_kulup')[:100]))

    if len(pool_qs) < 50 and tokens:
        exist_ids = {p.id for p in pool_qs}
        partial_filter = Q()
        for tok in tokens:
            partial_filter |= Q(sporcu_adi__icontains=tok)
        extra = Sporcu.objects.filter(cand_filter & partial_filter).exclude(id__in=exist_ids).select_related('birincil_kulup')[:150]
        pool_qs.extend(list(extra))

    scored_candidates: List[Dict[str, Any]] = []

    for sp in pool_qs:
        cand_norm = normalize_tr(sp.sporcu_adi)
        if not cand_norm:
            continue

        # Cinsiyet zıtlığı kontrolü
        if target_gender and sp.cinsiyet:
            sp_gen = sp.cinsiyet.strip().upper()
            if sp_gen and sp_gen != target_gender:
                continue

        # İlk ad ve soyad benzerliği ayrımı (Farklı ilk adları kesinlikle engelle)
        c_tokens = cand_norm.split()
        if len(tokens) >= 2 and len(c_tokens) >= 2:
            first_in = ' '.join(tokens[:-1])
            first_cand = ' '.join(c_tokens[:-1])
            sur_in = tokens[-1]
            sur_cand = c_tokens[-1]

            f_ratio = fuzz.ratio(first_in, first_cand) if fuzz else 100
            s_ratio = fuzz.ratio(sur_in, sur_cand) if fuzz else 100

            # İlk adlar tamamen farklıysa (Örn: Ömer vs Merve) -> kesinlikle elenir
            if f_ratio < 70.0 and not (first_in in first_cand or first_cand in first_in):
                continue
            # Soyadlar tamamen farklıysa -> elenir
            if s_ratio < 70.0:
                continue

        if fuzz:
            r_sort = fuzz.token_sort_ratio(norm_input, cand_norm)
            r_ratio = fuzz.ratio(norm_input, cand_norm)
            score = max(r_sort, r_ratio)
        else:
            # Fallback (difflib)
            import difflib
            score = difflib.SequenceMatcher(None, norm_input, cand_norm).ratio() * 100

        # Doğum yılı ve kulüp bonusları sadece temel ad benzerliği yüksekse (>= 75) eklenir
        if score >= 75.0:
            if target_year and sp.dogum_yili == target_year:
                score += 5
            elif target_year and sp.dogum_yili in [target_year - 1, target_year + 1]:
                score += 2

            if norm_club:
                cand_clubs = [normalize_tr(sp.birincil_kulup.kulup_adi)] if sp.birincil_kulup else []
                cand_clubs.extend([normalize_tr(h.kulup.kulup_adi) for h in sp.kulup_tarihcesi.all()])
                if any(c and (norm_club in c or c in norm_club) for c in cand_clubs):
                    score += 8

        score = min(round(float(score), 1), 99.5)

        # %50 üzeri benzerlik barajı
        if score >= 50.0:
            scored_candidates.append(_serialize_sporcu(sp, score))

    scored_candidates.sort(key=lambda x: x.get("benzerlik_orani", 0), reverse=True)
    top_candidates = scored_candidates[:limit]

    # Eğer en üstteki aday %98+ ve doğum yılı tam uyuyorsa tam eşleşme say
    if top_candidates and top_candidates[0].get("benzerlik_orani", 0) >= 97.0 and target_year:
        top_sp_data = top_candidates[0]
        if top_sp_data.get("dogum_yili") == target_year:
            return {
                "durum": "basarili",
                "sonuc": "tam_eslesme",
                "bulunan_id": top_sp_data["id"],
                "sporcu": top_sp_data,
                "muhtemel_eslesmeler": [],
                "sorgu": sorgu_info
            }

    if top_candidates:
        return {
            "durum": "basarili",
            "sonuc": "muhtemel_eslesmeler",
            "bulunan_id": None,
            "sporcu": None,
            "muhtemel_eslesmeler": top_candidates,
            "sorgu": sorgu_info
        }

    return {
        "durum": "bulunamadi",
        "sonuc": "yok",
        "bulunan_id": None,
        "sporcu": None,
        "muhtemel_eslesmeler": [],
        "mesaj": "Veritabanında eşleşen veya benzer sporcu bulunamadı.",
        "sorgu": sorgu_info
    }


def _serialize_sporcu(sp: Sporcu, benzerlik: Optional[float] = None) -> Dict[str, Any]:
    """Sporcu nesnesini JSON uyumlu sözlüğe dönüştürür."""
    aktif_k = sp.aktif_kulup()
    okul_adi = sp.okul()
    data = {
        "id": sp.id,
        "sporcu_adi": sp.sporcu_adi,
        "dogum_yili": sp.dogum_yili,
        "yas_dogum_yili": sp.yas_dogum_yili,
        "cinsiyet": sp.cinsiyet,
        "kulup": aktif_k.kulup_adi if aktif_k else (sp.birincil_kulup.kulup_adi if sp.birincil_kulup else "Kulüpsüz / Ferdi"),
        "okul": okul_adi,
        "toplam_yaris_sayisi": sp.toplam_yaris_sayisi,
        "son_yaris_tarihi": sp.son_yaris_tarihi,
        "profil_url": f"/sporcular/{sp.id}/"
    }
    if benzerlik is not None:
        data["benzerlik_orani"] = benzerlik
    return data

