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


def normalize_tr(s: Optional[str]) -> str:
    """Türkçe karakterleri ve noktalama işaretlerini eşleştirme için normalize eder."""
    if not s:
        return ""
    mapping = {
        'İ': 'I', 'ı': 'i', 'I': 'I', 'i': 'i',
        'Ş': 'S', 'ş': 's',
        'Ğ': 'G', 'ğ': 'g',
        'Ü': 'U', 'ü': 'u',
        'Ö': 'O', 'ö': 'o',
        'Ç': 'C', 'ç': 'c'
    }
    cleaned = ''.join(mapping.get(c, c) for c in str(s).strip().upper())
    cleaned = re.sub(r'[^A-Z0-9\s]', ' ', cleaned)
    return re.sub(r'\s+', ' ', cleaned).strip()


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
    if not name or len(name.strip()) < 2:
        return {
            "durum": "gecersiz_istek",
            "sonuc": "yok",
            "bulunan_id": None,
            "sporcu": None,
            "muhtemel_eslesmeler": [],
            "mesaj": "Geçerli bir sporcu adı belirtilmelidir.",
            "sorgu": {"ad": name, "dogum_yili": birth_year_or_date, "kulup": club, "cinsiyet": gender}
        }

    norm_input = normalize_tr(name)
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
    exact_matches = list(exact_qs.filter(sporcu_adi__iexact=name.strip()))
    if not exact_matches:
        # Türkçe normalize isim veya kelime sırası bağımsız tam eşleşme kontrolü
        tokens = [t for t in norm_input.split() if len(t) >= 2]
        if tokens:
            cand_token_filter = Q()
            for tok in tokens:
                cand_token_filter |= Q(sporcu_adi__icontains=tok)
            for sp in exact_qs.filter(cand_token_filter)[:100]:
                sp_norm = normalize_tr(sp.sporcu_adi)
                if sp_norm == norm_input or sorted(sp_norm.split()) == sorted(tokens):
                    if sp not in exact_matches:
                        exact_matches.append(sp)

    # Doğum yılı +-1 toleransı ve kulüp geçmişi ile tam isim eşleşmesi kontrolü
    if not exact_matches and target_year and norm_club:
        tol_filter = Q(dogum_yili__in=[target_year, target_year - 1, target_year + 1]) | Q(yas_dogum_yili=str(target_year)[-2:])
        if target_gender:
            tol_filter &= (Q(cinsiyet__iexact=target_gender) | Q(cinsiyet__isnull=True) | Q(cinsiyet=""))
        cand_tol = list(Sporcu.objects.filter(tol_filter, sporcu_adi__iexact=name.strip()).select_related('birincil_kulup'))
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

