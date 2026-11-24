# -*- coding: utf-8 -*-
"""
merge_abbreviated_athletes.py
=============================
Az yarışlı (`toplam_yaris_sayisi <= 10`) kısaltmalı (`S. ÖKSÜZOĞLU`) veya eksik orta adlı
(`Naz KAHVECİOĞLU`) sporcuları, Soyad + Doğum Yılı + Cinsiyet + Baş Harf/İlk Ad + Ortak Kulüp
kriterleriyle kesin tekil (1-e-1) eşleşen ana sporcu kayıtlarına birleştirir.

Belirsiz (birden fazla adayı olan) veya kulübü/yaşı/cinsiyeti çelişen kayıtlara dokunmaz.

Kullanım:
    python scripts/merge_abbreviated_athletes.py --dry-run
    python scripts/merge_abbreviated_athletes.py --db /home/ubuntu/app/database/yuzme_veritabani.db
"""

import argparse
from collections import defaultdict
import os
import sqlite3
import sys

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
YUZME_APP_DIR = os.path.join(ROOT_DIR, "yuzme_projesi")
if YUZME_APP_DIR not in sys.path:
    sys.path.insert(0, YUZME_APP_DIR)

from sonuclar.sqlite_tr import tr_fold


def resolve_default_db_path() -> str:
    candidates = [
        os.path.join(ROOT_DIR, "database", "yuzme_veritabani.db"),
        os.path.join(YUZME_APP_DIR, "yuzme_veritabani.db"),
        "/home/ubuntu/app/database/yuzme_veritabani.db",
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return candidates[0]


def find_abbreviated_merge_plans(cur: sqlite3.Cursor, max_races: int = 10) -> tuple:
    all_sp = cur.execute(
        """
        SELECT s.id, s.sporcu_adi, s.dogum_yili, s.cinsiyet, s.birincil_kulup_id,
               COALESCE(s.toplam_yaris_sayisi, 0)
        FROM sporcular s
        WHERE s.sporcu_adi IS NOT NULL
          AND s.sporcu_adi NOT LIKE 'Maskeli sporcu%'
        """
    ).fetchall()

    tarihce_clubs = defaultdict(set)
    for sp_id, k_id in cur.execute("SELECT sporcu_id, kulup_id FROM sporcu_kulup_tarihce").fetchall():
        tarihce_clubs[sp_id].add(k_id)

    full_by_key = defaultdict(list)
    abbrev_candidates = []
    all_by_key = defaultdict(list)

    for sid, name, dy, cins, kid, yaris in all_sp:
        parts = (name or "").strip().split()
        if len(parts) < 2 or not dy or not cins:
            continue
        key = (tr_fold(parts[-1]), dy, tr_fold(cins))
        all_by_key[key].append((sid, name, dy, cins, kid, yaris, parts))
        has_initial = any(len(p.rstrip(".")) == 1 for p in parts[:-1])
        if has_initial:
            abbrev_candidates.append((sid, name, dy, cins, kid, yaris, parts))
        else:
            full_by_key[key].append((sid, name, dy, cins, kid, yaris, parts))

    merge_plans = []
    ambiguous = []
    seen_sources = set()

    # 1. Baş harfi kısaltmalı sporcular (ör. S. ÖKSÜZOĞLU -> Sebahat Deren ÖKSÜZOĞLU)
    for sid, name, dy, cins, kid, yaris, parts in abbrev_candidates:
        if yaris > max_races:
            continue
        key = (tr_fold(parts[-1]), dy, tr_fold(cins))
        cands = full_by_key.get(key, [])
        if not cands:
            continue

        sp_clubs = set(tarihce_clubs.get(sid, set()))
        if kid:
            sp_clubs.add(kid)

        initials = [tr_fold(p.rstrip(".")) for p in parts[:-1]]
        matched = []
        for c_sid, c_name, c_dy, c_cins, c_kid, c_yaris, c_parts in cands:
            if c_sid == sid:
                continue
            c_first_initials = [tr_fold(cp[0]) for cp in c_parts[:-1]]
            if len(initials) == 1:
                if not c_first_initials or c_first_initials[0] != initials[0]:
                    continue
            else:
                if c_first_initials[: len(initials)] != initials:
                    continue
            c_clubs = set(tarihce_clubs.get(c_sid, set()))
            if c_kid:
                c_clubs.add(c_kid)
            if sp_clubs and c_clubs and (sp_clubs & c_clubs):
                matched.append((c_sid, c_name, c_dy, c_cins, c_kid, c_yaris))

        if len(matched) == 1:
            seen_sources.add(sid)
            merge_plans.append(("KISALTMA", (sid, name, dy, cins, kid, yaris), matched[0]))
        elif len(matched) > 1:
            ambiguous.append(((sid, name, dy, cins, yaris), matched))

    # 2. Eksik orta adlı sporcular (ör. Naz KAHVECİOĞLU -> Naz Duru KAHVECİOĞLU)
    for key, group in all_by_key.items():
        if len(group) < 2:
            continue
        for sid, name, dy, cins, kid, yaris, parts in group:
            if sid in seen_sources or yaris > max_races or len(parts) != 2:
                continue
            if any(len(p.rstrip(".")) == 1 for p in parts[:-1]):
                continue
            first_f = tr_fold(parts[0])
            sp_clubs = set(tarihce_clubs.get(sid, set()))
            if kid:
                sp_clubs.add(kid)

            matched = []
            for c_sid, c_name, c_dy, c_cins, c_kid, c_yaris, c_parts in group:
                if c_sid == sid or len(c_parts) < 3 or c_yaris <= yaris:
                    continue
                if tr_fold(c_parts[0]) != first_f:
                    continue
                c_clubs = set(tarihce_clubs.get(c_sid, set()))
                if c_kid:
                    c_clubs.add(c_kid)
                if sp_clubs and c_clubs and (sp_clubs & c_clubs):
                    matched.append((c_sid, c_name, c_dy, c_cins, c_kid, c_yaris))

            if len(matched) == 1:
                seen_sources.add(sid)
                merge_plans.append(("ORTA_AD", (sid, name, dy, cins, kid, yaris), matched[0]))
            elif len(matched) > 1:
                ambiguous.append(((sid, name, dy, cins, yaris), matched))

    return merge_plans, ambiguous


def run_merge(db_path: str, dry_run: bool = False, max_races: int = 10) -> dict:
    if not os.path.exists(db_path):
        raise FileNotFoundError(f"Veritabanı bulunamadı: {db_path}")

    conn = sqlite3.connect(db_path, timeout=60)
    conn.execute("PRAGMA busy_timeout=60000;")
    try:
        cur = conn.cursor()
        merge_plans, ambiguous = find_abbreviated_merge_plans(cur, max_races=max_races)

        moved_races = 0
        deleted_athletes = 0
        touched_keepers = set()

        if not dry_run:
            for kind, src, dst in merge_plans:
                src_id = src[0]
                dst_id = dst[0]

                # Kulüp tarihçelerini taşı / birleştir
                src_th_rows = cur.execute(
                    "SELECT id, kulup_id, ilk_yaris_tarihi, son_yaris_tarihi, toplam_yaris_sayisi, aktif_kulup_mu "
                    "FROM sporcu_kulup_tarihce WHERE sporcu_id = ?",
                    (src_id,),
                ).fetchall()
                for th_id, k_id, ilk_t, son_t, t_cnt, aktif in src_th_rows:
                    existing = cur.execute(
                        "SELECT id, ilk_yaris_tarihi, son_yaris_tarihi, toplam_yaris_sayisi, aktif_kulup_mu "
                        "FROM sporcu_kulup_tarihce WHERE sporcu_id = ? AND kulup_id = ?",
                        (dst_id, k_id),
                    ).fetchone()
                    if existing:
                        ex_id, ex_ilk, ex_son, ex_cnt, ex_aktif = existing
                        cur.execute(
                            "UPDATE yaris_sonuclari SET sporcu_kulup_tarihce_id = ? WHERE sporcu_kulup_tarihce_id = ?",
                            (ex_id, th_id),
                        )
                        new_ilk = min([t for t in (ex_ilk, ilk_t) if t], default=None)
                        new_son = max([t for t in (ex_son, son_t) if t], default=None)
                        cur.execute(
                            "UPDATE sporcu_kulup_tarihce SET ilk_yaris_tarihi = ?, son_yaris_tarihi = ?, "
                            "toplam_yaris_sayisi = ?, aktif_kulup_mu = ? WHERE id = ?",
                            (new_ilk, new_son, (ex_cnt or 0) + (t_cnt or 0), 1 if (ex_aktif or aktif) else 0, ex_id),
                        )
                        cur.execute("DELETE FROM sporcu_kulup_tarihce WHERE id = ?", (th_id,))
                    else:
                        cur.execute("UPDATE sporcu_kulup_tarihce SET sporcu_id = ? WHERE id = ?", (dst_id, th_id))

                cur.execute("UPDATE yaris_sonuclari SET sporcu_id = ? WHERE sporcu_id = ?", (dst_id, src_id))
                moved_races += cur.rowcount

                cur.execute("DELETE FROM sporcular WHERE id = ?", (src_id,))
                deleted_athletes += 1
                touched_keepers.add(dst_id)

            for dst_id in touched_keepers:
                cnt, ilk_d, son_d = cur.execute(
                    """
                    SELECT COUNT(*), MIN(e.yaris_tarihi_baslangic), MAX(e.yaris_tarihi_baslangic)
                    FROM yaris_sonuclari ys
                    LEFT JOIN events e ON ys.event_id = e.id
                    WHERE ys.sporcu_id = ?
                    """,
                    (dst_id,),
                ).fetchone()
                cur.execute(
                    "UPDATE sporcular SET toplam_yaris_sayisi = ?, ilk_yaris_tarihi = COALESCE(?, ilk_yaris_tarihi), "
                    "son_yaris_tarihi = COALESCE(?, son_yaris_tarihi) WHERE id = ?",
                    (cnt, ilk_d, son_d, dst_id),
                )

            conn.commit()

        return {
            "db_path": db_path,
            "dry_run": dry_run,
            "planned_count": len(merge_plans),
            "ambiguous_count": len(ambiguous),
            "deleted_athletes": deleted_athletes,
            "moved_races": moved_races,
            "plans": merge_plans,
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser(description="Kısaltmalı ve eksik orta adlı tekil eşleşen sporcuları birleştirir.")
    parser.add_argument("--db", default=resolve_default_db_path(), help="SQLite veritabanı yolu")
    parser.add_argument("--dry-run", action="store_true", help="Değişiklik yapmadan önizleme gösterir")
    parser.add_argument("--max-races", type=int, default=10, help="Maksimum yarış sayısı filtresi (varsayılan: 10)")
    args = parser.parse_args()

    stats = run_merge(args.db, dry_run=args.dry_run, max_races=args.max_races)
    mode = "DRY-RUN" if stats["dry_run"] else "UYGULANDI"
    print(f"[{mode}] Veritabanı: {stats['db_path']}")
    print(f"  - Tekil birleştirme planı : {stats['planned_count']}")
    print(f"  - Belirsiz (atlanan)      : {stats['ambiguous_count']}")
    if not stats["dry_run"]:
        print(f"  - Silinen mükerrer sporcu : {stats['deleted_athletes']}")
        print(f"  - Aktarılan yarış sonucu  : {stats['moved_races']}")


if __name__ == "__main__":
    main()
