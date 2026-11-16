# -*- coding: utf-8 -*-
"""
unmask_canli_athletes.py
========================
CANLI_START_LISTESI ve CANLI_SONUC kayıtlarında 'Maskeli sporcu (...)' olarak
kalan sporcuları `sonuclar.athlete_matcher.match_athlete` ile eşleştirip
gerçek sporcu kayıtlarına bağlar.

Varsayılan olarak dry-run çalışır; uygulamak için --apply verin.
"""

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "yuzme_projesi"))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "yuzme_projesi.settings")

import django
django.setup()

from django.conf import settings
from django.db import connections, transaction
from sonuclar.models import YarisSonucu, Sporcu
from sonuclar.athlete_matcher import match_athlete


def run_unmask(db_path: str, apply: bool = False) -> None:
    abs_db = os.path.abspath(db_path)
    if not os.path.exists(abs_db):
        print(f"[HATA] DB bulunamadı: {abs_db}")
        sys.exit(1)

    settings.DATABASES["default"]["NAME"] = abs_db
    connections["default"].close()

    qs = (
        YarisSonucu.objects.filter(
            kaynak_turu__in=["CANLI_START_LISTESI", "CANLI_SONUC"],
            sporcu__sporcu_adi__startswith="Maskeli sporcu (",
        )
        .select_related("sporcu", "kulup")
    )

    total = qs.count()
    print(f"[*] Hedef DB: {abs_db} | Mod: {'APPLY' if apply else 'DRY-RUN'}")
    print(f"[*] Toplam maskeli CANLI kaydı: {total}")

    cache = {}
    updates = []  # (ys_id, target_sporcu_id, raw_masked)
    sample_matches = []

    for ys in qs.iterator(chunk_size=500):
        sp = ys.sporcu
        m = re.match(r"^Maskeli sporcu \((.+)\)$", sp.sporcu_adi)
        if not m:
            continue
        raw_masked = m.group(1).strip()
        if not raw_masked or "," in raw_masked:
            continue

        club_name = ys.kulup.kulup_adi if ys.kulup else (sp.birincil_kulup.kulup_adi if sp.birincil_kulup else None)
        gender = None if (ys.cinsiyet or "").lower() == "karma" else (ys.cinsiyet or sp.cinsiyet)
        key = (raw_masked, sp.dogum_yili, club_name, gender)

        if key not in cache:
            res = match_athlete(
                raw_masked,
                birth_year_or_date=sp.dogum_yili,
                club=club_name,
                gender=gender,
            )
            bid = res.get("bulunan_id")
            if bid and bid != sp.id:
                target_sp = res.get("sporcu") or {}
                cache[key] = (bid, target_sp.get("sporcu_adi", ""))
            else:
                cache[key] = None

        hit = cache[key]
        if hit:
            target_id, target_name = hit
            updates.append((ys.id, target_id, raw_masked))
            if len(sample_matches) < 15:
                sample_matches.append((raw_masked, sp.dogum_yili, club_name, "->", target_name))

    print(f"[*] Eşleşen CANLI kaydı: {len(updates)} / {total}")
    for sm in sample_matches:
        print("   ", sm)

    if not apply:
        print("\n[!] Dry-run tamamlandı. Uygulamak için --apply verin.")
        return

    with transaction.atomic():
        for ys_id, target_id, raw_masked in updates:
            YarisSonucu.objects.filter(id=ys_id).update(
                sporcu_id=target_id,
                sporcu_maskeli=raw_masked,
            )
    print(f"[OK] {len(updates)} CANLI kaydının maskesi kaldırıldı!")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--db", default="database/yuzme_server_copy.db")
    p.add_argument("--apply", action="store_true")
    args = p.parse_args()
    run_unmask(args.db, apply=args.apply)
