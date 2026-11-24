# -*- coding: utf-8 -*-
"""
merge_duplicate_clubs.py
========================
Mükerrer kulüp kayıtlarını güvenli şekilde birleştirir:
  1. Kısaltmalı kulüpler (S.K., GSK, YSK) ile tam adlı karşılıklarını birleştirir.
  2. Aynı ilde bulunan ve yalnızca unvan/ek farkı olan resmi kulüpleri
     (`Spor Kulübü`, `Gençlik Ve Spor Kulübü`, `Derneği`, `Belediye Spor` / `Belediyespor`)
     birleştirir (`okul_mu=0` ve `len(kök) >= 3`).

Kullanım:
    python scripts/merge_duplicate_clubs.py --dry-run
    python scripts/merge_duplicate_clubs.py
"""

import argparse
from collections import defaultdict
import os
import re
import sys
import unicodedata

import django

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
YUZME_APP_DIR = os.path.join(ROOT_DIR, "yuzme_projesi")
if YUZME_APP_DIR not in sys.path:
    sys.path.insert(0, YUZME_APP_DIR)

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "yuzme_projesi.settings")
django.setup()

from django.db import transaction
from django.db.models import Q
from sonuclar.models import Kulup, Sporcu, SporcuKulupTarihce, YarisSonucu
from sonuclar.sqlite_tr import tr_fold


def clean_and_expand_club_name(name: str) -> str:
    if not name:
        return ""
    text = name.strip()
    text = re.sub(r"[\s\.]*\bS[\.\s]*K[\.\s]*$", " Spor Kulübü", text, flags=re.IGNORECASE)
    text = re.sub(r"[\s\.]*\bGSK[\.\s]*$", " Gençlik ve Spor Kulübü", text, flags=re.IGNORECASE)
    text = re.sub(r"[\s\.]*\bYSK[\.\s]*$", " Yüzme Spor Kulübü", text, flags=re.IGNORECASE)
    text = re.sub(r"\bS[\.\s]*K[\.\s]*\b", " Spor Kulübü ", text, flags=re.IGNORECASE)
    text = re.sub(r"\bG[\.\s]*S[\.\s]*K[\.\s]*\b", " Gençlik ve Spor Kulübü ", text, flags=re.IGNORECASE)
    text = re.sub(r"\s+", " ", text).strip()
    text = text.rstrip(". ")
    return text


def safe_club_stem(name: str) -> str:
    """Ek/unvan kelimelerini temizleyerek güvenli kulüp kökünü döner."""
    s = unicodedata.normalize("NFC", name or "").replace("\u0307", "")
    s = tr_fold(s)
    s = re.sub(r"[.\-,/()]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"\bbelediye\s+spor\b", "belediyespor", s)
    for w in ("genclik", "ve", "spor", "kulubu", "kulup", "dernegi", "dernek", "sk", "gsk", "ysk"):
        s = re.sub(r"\b" + w + r"\b", "", s)
    return re.sub(r"\s+", " ", s).strip()


def _merge_club_into(source: Kulup, canonical: Kulup, dry_run: bool = False) -> tuple:
    """`source` kulübünü `canonical` kulübüne taşır ve siler."""
    ys_count = YarisSonucu.objects.filter(kulup=source).count()
    sp_count = Sporcu.objects.filter(birincil_kulup=source).count()

    if dry_run:
        return ys_count, sp_count

    with transaction.atomic():
        for th in SporcuKulupTarihce.objects.filter(kulup=source):
            existing_th = SporcuKulupTarihce.objects.filter(
                sporcu_id=th.sporcu_id,
                kulup=canonical,
            ).first()
            if existing_th:
                YarisSonucu.objects.filter(sporcu_kulup_tarihce=th).update(
                    sporcu_kulup_tarihce=existing_th,
                    kulup=canonical,
                )
                existing_th.toplam_yaris_sayisi = (existing_th.toplam_yaris_sayisi or 0) + (th.toplam_yaris_sayisi or 0)
                if th.ilk_yaris_tarihi and (not existing_th.ilk_yaris_tarihi or th.ilk_yaris_tarihi < existing_th.ilk_yaris_tarihi):
                    existing_th.ilk_yaris_tarihi = th.ilk_yaris_tarihi
                if th.son_yaris_tarihi and (not existing_th.son_yaris_tarihi or th.son_yaris_tarihi > existing_th.son_yaris_tarihi):
                    existing_th.son_yaris_tarihi = th.son_yaris_tarihi
                if th.aktif_kulup_mu:
                    existing_th.aktif_kulup_mu = 1
                existing_th.save(
                    update_fields=[
                        "toplam_yaris_sayisi",
                        "ilk_yaris_tarihi",
                        "son_yaris_tarihi",
                        "aktif_kulup_mu",
                    ]
                )
                th.delete()
            else:
                th.kulup = canonical
                th.save(update_fields=["kulup"])

        ys_updated = YarisSonucu.objects.filter(kulup=source).update(kulup=canonical)
        sp_updated = Sporcu.objects.filter(birincil_kulup=source).update(birincil_kulup=canonical)

        canonical.toplam_sporcu_sayisi = Sporcu.objects.filter(birincil_kulup=canonical).count()
        canonical.toplam_yaris_sayisi = YarisSonucu.objects.filter(kulup=canonical).count()
        if source.ilk_yaris_tarihi and (not canonical.ilk_yaris_tarihi or source.ilk_yaris_tarihi < canonical.ilk_yaris_tarihi):
            canonical.ilk_yaris_tarihi = source.ilk_yaris_tarihi
        if source.son_yaris_tarihi and (not canonical.son_yaris_tarihi or source.son_yaris_tarihi > canonical.son_yaris_tarihi):
            canonical.son_yaris_tarihi = source.son_yaris_tarihi
        canonical.save(
            update_fields=[
                "toplam_sporcu_sayisi",
                "toplam_yaris_sayisi",
                "ilk_yaris_tarihi",
                "son_yaris_tarihi",
            ]
        )

        source.delete()
        return ys_updated, sp_updated


def run_club_merge(dry_run: bool = False):
    merged_count = 0
    total_races_moved = 0
    total_athletes_moved = 0

    # 1. Aşama: Kısaltmalı kulüpler (S.K., GSK)
    sk_kulupler = list(Kulup.objects.filter(kulup_adi__iregex=r"(\bS\.?K\.?\b|\bGSK\b)"))
    for k in sk_kulupler:
        expanded = clean_and_expand_club_name(k.kulup_adi)
        canonical = (
            Kulup.objects.filter(
                Q(kulup_adi__iexact=expanded) | Q(kulup_adi__iexact=f"{expanded} Derneği")
            )
            .exclude(id=k.id)
            .first()
        )
        if not canonical:
            continue
        ys_u, sp_u = _merge_club_into(k, canonical, dry_run=dry_run)
        total_races_moved += ys_u
        total_athletes_moved += sp_u
        merged_count += 1
        print(f"  [KISALTMA] ID={k.id} '{k.kulup_adi}' ({ys_u} yarış) ===> ID={canonical.id} '{canonical.kulup_adi}'")

    # 2. Aşama: Aynı il + aynı güvenli kök (okul_mu=0)
    official_clubs = list(Kulup.objects.filter(okul_mu=0).order_by("-toplam_yaris_sayisi", "id"))
    groups = defaultdict(list)
    for k in official_clubs:
        st = safe_club_stem(k.kulup_adi)
        if not st or len(st) < 3 or st.isdigit():
            continue
        groups[(st, k.il or "")].append(k)

    for (st, il), club_list in sorted(groups.items(), key=lambda x: -sum(c.toplam_yaris_sayisi or 0 for c in x[1])):
        if len(club_list) < 2:
            continue
        # En çok yarışı olanı (eşitlikte 'Kulübü' içeren / en düşük id) ana kulüp seç
        club_list.sort(
            key=lambda c: (
                -(c.toplam_yaris_sayisi or 0),
                0 if "kulübü" in (c.kulup_adi or "").lower() else 1,
                c.id,
            )
        )
        canonical = club_list[0]
        for dup in club_list[1:]:
            ys_u, sp_u = _merge_club_into(dup, canonical, dry_run=dry_run)
            total_races_moved += ys_u
            total_athletes_moved += sp_u
            merged_count += 1
            print(f"  [AYNI İL: {il or '-'}] ID={dup.id} '{dup.kulup_adi}' ({ys_u} yarış) ===> ID={canonical.id} '{canonical.kulup_adi}'")

    mode = "DRY-RUN" if dry_run else "TAMAMLANDI"
    print(f"\n[+] İŞLEM {mode}:")
    print(f"    - Birleştirilen mükerrer kulüp: {merged_count}")
    print(f"    - Aktarılan yarış sonucu      : {total_races_moved}")
    print(f"    - Aktarılan sporcu            : {total_athletes_moved}")


def main():
    parser = argparse.ArgumentParser(description="Mükerrer kulüpleri güvenli şekilde birleştirir.")
    parser.add_argument("--dry-run", action="store_true", help="Değişiklik yapmadan önizleme gösterir")
    args = parser.parse_args()
    run_club_merge(dry_run=args.dry_run)


if __name__ == "__main__":
    main()
