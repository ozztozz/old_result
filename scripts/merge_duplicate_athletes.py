# -*- coding: utf-8 -*-
"""
merge_duplicate_athletes.py
===========================
Aynı normalize ada (büyük/küçük harf farkı) ve aynı doğum yılına sahip
çift `Sporcu` kayıtlarını (ör. 'Boran Kaya BAYDURCAN' & 'Boran Kaya Baydurcan')
tekilleştirir.

- 'Maskeli sporcu (...)' kayıtlarına dokunmaz.
- Cinsiyeti çelişenleri (biri ERKEK diğeri KADIN) birleştirmez.
- En çok yarışı olan (eşitlikte birincil kulübü dolu / en düşük ID) kaydı korur.
- Varsayılan olarak dry-run çalışır; uygulamak için `--apply` verin.
"""

import argparse
import os
import sqlite3
import sys
import unicodedata


def normalize_tr_name(s: str) -> str:
    if not s:
        return ""
    s = unicodedata.normalize("NFC", s).replace("\u0307", "")
    tr_map = str.maketrans({
        "İ": "i", "I": "i", "ı": "i",
        "Ş": "s", "ş": "s",
        "Ğ": "g", "ğ": "g",
        "Ü": "u", "ü": "u",
        "Ö": "o", "ö": "o",
        "Ç": "c", "ç": "c",
    })
    return " ".join(s.translate(tr_map).lower().split())


def _gender_norm(g: str) -> str:
    if not g:
        return ""
    u = g.strip().upper()
    if u in ("ERKEK", "E", "MEN", "BOY"):
        return "ERKEK"
    if u in ("KADIN", "KADİN", "K", "BAYAN", "WOMEN", "GIRL"):
        return "KADIN"
    return ""


def run_merge(db_path: str, apply: bool = False) -> None:
    if not os.path.exists(db_path):
        print(f"[HATA] DB bulunamadı: {db_path}")
        sys.exit(1)

    conn = sqlite3.connect(db_path, timeout=60)
    conn.execute("PRAGMA busy_timeout=60000;")
    cur = conn.cursor()

    rows = cur.execute(
        """
        SELECT s.id, s.sporcu_adi, s.dogum_yili, s.cinsiyet, s.birincil_kulup_id,
               COALESCE(s.toplam_yaris_sayisi, 0),
               (SELECT COUNT(*) FROM yaris_sonuclari y WHERE y.sporcu_id = s.id) as real_cnt
        FROM sporcular s
        WHERE s.dogum_yili IS NOT NULL
          AND s.sporcu_adi IS NOT NULL
          AND s.sporcu_adi NOT LIKE 'Maskeli sporcu%'
        """
    ).fetchall()

    groups = {}
    for sid, name, dy, gender, club_id, total_cnt, real_cnt in rows:
        key = (normalize_tr_name(name), dy)
        if not key[0]:
            continue
        groups.setdefault(key, []).append({
            "id": sid,
            "name": name,
            "dy": dy,
            "gender": _gender_norm(gender),
            "club_id": club_id,
            "real_cnt": real_cnt,
            "total_cnt": total_cnt,
        })

    merge_plans = []
    for key, items in groups.items():
        if len(items) < 2:
            continue
        genders = {it["gender"] for it in items if it["gender"]}
        if len(genders) > 1:
            continue
        # En çok gerçek sonucu olan -> birincil kulübü olan -> en düşük id
        items.sort(key=lambda x: (-x["real_cnt"], 0 if x["club_id"] else 1, x["id"]))
        keeper = items[0]
        dups = items[1:]
        merge_plans.append((keeper, dups))

    total_dups = sum(len(d) for _, d in merge_plans)
    print(f"[*] Mod: {'APPLY' if apply else 'DRY-RUN'} | Grup: {len(merge_plans)} | Silinecek çift sporcu: {total_dups}")
    for keeper, dups in merge_plans[:15]:
        dup_desc = ", ".join(f"{d['id']}:{d['name']}({d['real_cnt']})" for d in dups)
        print(f"    KEEP {keeper['id']}:{keeper['name']} (dy={keeper['dy']}, races={keeper['real_cnt']}) <- {dup_desc}")

    if not apply or not merge_plans:
        conn.close()
        return

    merged_rows = 0
    deleted_athletes = 0
    try:
        for keeper, dups in merge_plans:
            kid = keeper["id"]
            for d in dups:
                did = d["id"]
                cur.execute("UPDATE yaris_sonuclari SET sporcu_id = ? WHERE sporcu_id = ?", (kid, did))
                merged_rows += cur.rowcount
                if not keeper["club_id"] and d["club_id"]:
                    cur.execute("UPDATE sporcular SET birincil_kulup_id = ? WHERE id = ?", (d["club_id"], kid))
                    keeper["club_id"] = d["club_id"]
                cur.execute("DELETE FROM sporcu_kulup_tarihce WHERE sporcu_id = ?", (did,))
                cur.execute("DELETE FROM sporcular WHERE id = ?", (did,))
                deleted_athletes += 1
            new_cnt = cur.execute("SELECT COUNT(*) FROM yaris_sonuclari WHERE sporcu_id = ?", (kid,)).fetchone()[0]
            cur.execute("UPDATE sporcular SET toplam_yaris_sayisi = ? WHERE id = ?", (new_cnt, kid))

        conn.commit()
        print(f"[OK] {deleted_athletes} çift sporcu silindi, {merged_rows} yarış sonucu ana kayda aktarıldı.")
    except Exception as exc:
        conn.rollback()
        print(f"[HATA] Geri alındı: {exc}")
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--db", default="database/yuzme_server_copy.db")
    p.add_argument("--apply", action="store_true")
    args = p.parse_args()
    run_merge(args.db, apply=args.apply)
