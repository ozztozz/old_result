# -*- coding: utf-8 -*-
"""
fix_canli_data_quality.py
=========================
Canlı yarış kayıtlarındaki (ve ilgili kulüp/sporcu tablolarındaki) bilinen
parser kaynaklı veri kalitesi sorunlarını güvenli şekilde temizler:
  1. Saf sayı ('0', '11', vb.) veya zaman formatındaki ('1:45.20', 'NT') sahte kulüpleri temizler.
  2. CANLI_SONUC kayıtlarında kulup_id=NULL olanları (ör. EXH/DSQ) eşleşen CANLI_START_LISTESI kulübüyle doldurur.
  3. Standart dışı 'DQ' / 'SW ...' derecelerini 'DSQ' olarak normalize eder.
  4. Sporcu adlarındaki '(f5) ', '( ' gibi ön ek kalıntılarını temizler.

Varsayılan olarak dry-run (önizleme) çalışır. Değişiklik uygulamak için --apply verin.
"""

import argparse
import os
import re
import sqlite3
import sys
import unicodedata

RE_BAD_CLUB = re.compile(
    r"^(?:\d{1,3}|\d{1,2}(?:\s*[-–/]\s*\d{1,2})?\s*\+?\s*ya[sş]|a[cç][ıi]k\s*ya[sş]|(?:\d{1,2}:)?\d{2}[.,]\d{2}|NT)$",
    re.IGNORECASE,
)
RE_SPORCU_PREFIX = re.compile(r"^(?:\([A-Za-z0-9]{1,4}\)\s*|\(\s+)")
RE_TRAILING_2D_YEAR = re.compile(r"^(.+?[^\d\s])\s*(\d{2})$")
RE_TK_CLUB = re.compile(r"^\(Tk\)\s+(.+)$", re.IGNORECASE)

CHOPPED_PREFIX_MAP = {
    "ed ": "Ted ",
    "enerbahçe ": "Fenerbahçe ",
    "atih ": "Fatih ",
    "aroz ": "Faroz ",
    "emel ": "Temel ",
}


def _merge_or_rename_sporcu(cur: sqlite3.Cursor, sid: int, new_name: str, new_dy):
    if new_dy is not None:
        existing = cur.execute(
            "SELECT id FROM sporcular WHERE sporcu_adi = ? AND dogum_yili = ? AND id != ?",
            (new_name, new_dy, sid),
        ).fetchone()
    else:
        existing = cur.execute(
            "SELECT id FROM sporcular WHERE sporcu_adi = ? AND dogum_yili IS NULL AND id != ?",
            (new_name, sid),
        ).fetchone()

    if existing:
        target_sid = existing[0]
        cur.execute("UPDATE yaris_sonuclari SET sporcu_id = ? WHERE sporcu_id = ?", (target_sid, sid))
        cur.execute("DELETE FROM sporcu_kulup_tarihce WHERE sporcu_id = ?", (sid,))
        cur.execute("DELETE FROM sporcular WHERE id = ?", (sid,))
        return "merged"
    cur.execute(
        "UPDATE sporcular SET sporcu_adi = ?, dogum_yili = ? WHERE id = ?",
        (new_name, new_dy, sid),
    )
    return "renamed"


def _merge_or_rename_club(cur: sqlite3.Cursor, cid: int, new_name: str):
    existing = cur.execute(
        "SELECT id FROM kulupler WHERE kulup_adi = ? AND id != ?",
        (new_name, cid),
    ).fetchone()
    if existing:
        target_cid = existing[0]
        cur.execute("UPDATE yaris_sonuclari SET kulup_id = ? WHERE kulup_id = ?", (target_cid, cid))
        cur.execute("UPDATE sporcular SET birincil_kulup_id = ? WHERE birincil_kulup_id = ?", (target_cid, cid))
        cur.execute("DELETE FROM sporcu_kulup_tarihce WHERE kulup_id = ?", (cid,))
        cur.execute("DELETE FROM kulupler WHERE id = ?", (cid,))
        return "merged"
    cur.execute("UPDATE kulupler SET kulup_adi = ? WHERE id = ?", (new_name, cid))
    return "renamed"


def run_repair(db_path: str, apply: bool = False) -> None:
    if not os.path.exists(db_path):
        print(f"[HATA] Veritabanı bulunamadı: {db_path}")
        sys.exit(1)

    conn = sqlite3.connect(db_path, timeout=60)
    conn.execute("PRAGMA busy_timeout=60000;")
    cur = conn.cursor()

    print(f"[*] Hedef DB: {db_path} | Mod: {'APPLY (YAZMA)' if apply else 'DRY-RUN (ÖNİZLEME)'}")

    # 1. Sahte kulüpler ('0', '11', '1:45.20', 'NT')
    bad_clubs = []
    for cid, cname in cur.execute("SELECT id, kulup_adi FROM kulupler").fetchall():
        c = (cname or "").strip()
        if c and RE_BAD_CLUB.match(c):
            ys_cnt = cur.execute("SELECT COUNT(*) FROM yaris_sonuclari WHERE kulup_id=?", (cid,)).fetchone()[0]
            bad_clubs.append((cid, cname, ys_cnt))

    print(f"\n[1] Sahte kulüp kayıtları: {len(bad_clubs)} kulüp")
    for cid, cname, ys_cnt in bad_clubs[:20]:
        print(f"    - id={cid} '{cname}' ({ys_cnt} yarış sonucu)")

    # 2. CANLI_SONUC kulup_id IS NULL -> CANLI_START_LISTESI üzerinden tamamlama
    null_club_res = cur.execute(
        """
        SELECT r.id, sl.kulup_id
        FROM yaris_sonuclari r
        JOIN yaris_sonuclari sl
          ON sl.event_id = r.event_id
         AND sl.sporcu_id = r.sporcu_id
         AND COALESCE(sl.mesafe, -1) = COALESCE(r.mesafe, -1)
         AND COALESCE(sl.stil, '') = COALESCE(r.stil, '')
        WHERE r.kaynak_turu = 'CANLI_SONUC'
          AND r.kulup_id IS NULL
          AND sl.kaynak_turu = 'CANLI_START_LISTESI'
          AND sl.kulup_id IS NOT NULL
        """
    ).fetchall()
    # Tekilleştir (aynı r.id için birden fazla satır varsa ilkini al)
    inherit_map = {}
    for rid, sl_cid in null_club_res:
        if rid not in inherit_map:
            inherit_map[rid] = sl_cid
    print(f"\n[2] CANLI_START_LISTESI'nden kulüp miras alınabilecek CANLI_SONUC kaydı: {len(inherit_map)}")

    # 3. Standart dışı DQ / SW / S.W / Disk. dereceleri
    dq_sw_rows = cur.execute(
        """
        SELECT id, derece, uyari_notu
        FROM yaris_sonuclari
        WHERE kaynak_turu = 'CANLI_SONUC'
          AND (
            UPPER(TRIM(derece)) = 'DQ'
            OR UPPER(TRIM(derece)) LIKE 'SW%'
            OR UPPER(TRIM(derece)) LIKE 'S.W%'
            OR UPPER(TRIM(derece)) LIKE 'DISK%'
          )
        """
    ).fetchall()
    print(f"\n[3] 'DQ' / 'SW ...' -> 'DSQ' normalize edilecek kayıt: {len(dq_sw_rows)}")
    for r in dq_sw_rows[:10]:
        print(f"    - id={r[0]} derece='{r[1]}' uyari_notu='{r[2]}'")

    # 4. Sporcu adındaki '(f5) ', '( ' ön ek kalıntıları
    prefix_sporcular = []
    for sid, sname, sdy in cur.execute(
        "SELECT id, sporcu_adi, dogum_yili FROM sporcular WHERE sporcu_adi LIKE '(%' AND sporcu_adi NOT LIKE 'Maskeli%'"
    ).fetchall():
        cleaned = RE_SPORCU_PREFIX.sub("", sname).strip()
        if cleaned and cleaned != sname:
            prefix_sporcular.append((sid, sname, cleaned, sdy))
    print(f"\n[4] Ön ek temizlenecek sporcu kaydı: {len(prefix_sporcular)}")
    for sid, old_n, new_n, sdy in prefix_sporcular[:15]:
        print(f"    - id={sid} (dy={sdy}): '{old_n}' -> '{new_n}'")

    # 5. '(Tk) ...' ön ekli kulüpler
    tk_clubs = []
    for cid, cname in cur.execute("SELECT id, kulup_adi FROM kulupler WHERE kulup_adi LIKE '(Tk)%'").fetchall():
        m_tk = RE_TK_CLUB.match(cname.strip())
        if m_tk:
            tk_clubs.append((cid, cname, m_tk.group(1).strip()))
    print(f"\n[5] '(Tk)' ön ekli kulüp: {len(tk_clubs)}")
    for cid, old_c, new_c in tk_clubs[:10]:
        print(f"    - id={cid}: '{old_c}' -> '{new_c}'")

    # 6. Sonunda 2 haneli doğum yılı yapışmış sporcular (ör: TAVUKÇUOĞLU09)
    trailing_yr_sp = []
    for sid, sname, sdy in cur.execute(
        "SELECT id, sporcu_adi, dogum_yili FROM sporcular WHERE sporcu_adi NOT LIKE 'Maskeli%' AND sporcu_adi GLOB '*[0-9][0-9]'"
    ).fetchall():
        m_ty = RE_TRAILING_2D_YEAR.match(sname.strip())
        if m_ty:
            yr2 = int(m_ty.group(2))
            full_yr = (1900 + yr2) if yr2 >= 40 else (2000 + yr2)
            target_dy = sdy if sdy is not None else full_yr
            trailing_yr_sp.append((sid, sname, m_ty.group(1).strip(), target_dy))
    print(f"\n[6] Sonunda 2 haneli doğum yılı yapışmış sporcu: {len(trailing_yr_sp)}")
    for sid, old_n, new_n, tdy in trailing_yr_sp[:10]:
        print(f"    - id={sid}: '{old_n}' -> '{new_n}' (dy={tdy})")

    # 7. İlk harfi (T/F) kesilmiş küçük harfli sporcu/takım adları
    chopped_sp = []
    for sid, sname, sdy in cur.execute(
        "SELECT id, sporcu_adi, dogum_yili FROM sporcular WHERE sporcu_adi NOT LIKE 'Maskeli%' AND GLOB('[a-zçğıöşü]*', sporcu_adi)"
    ).fetchall():
        for low_p, fixed_p in CHOPPED_PREFIX_MAP.items():
            if sname.startswith(low_p):
                chopped_sp.append((sid, sname, fixed_p + sname[len(low_p):], sdy))
                break
    print(f"\n[7] İlk harfi (T/F) kesilmiş sporcu/takım kaydı: {len(chopped_sp)}")
    for sid, old_n, new_n, sdy in chopped_sp[:10]:
        print(f"    - id={sid}: '{old_n}' -> '{new_n}'")

    # 8. CANLI_* kayıtlarında cinsiyet normalizasyonu
    gender_counts = cur.execute(
        """
        SELECT cinsiyet, COUNT(*)
        FROM yaris_sonuclari
        WHERE kaynak_turu LIKE 'CANLI%'
          AND cinsiyet IS NOT NULL
          AND cinsiyet NOT IN ('Erkek', 'Kadın', 'Karma')
        GROUP BY cinsiyet
        """
    ).fetchall()
    print(f"\n[8] CANLI_* cinsiyet normalize edilecek gruplar: {gender_counts}")

    # 9. İmkansız doğum yılı (< 1920 veya > 2022, ör. 2026)
    bad_dy_cnt = cur.execute(
        "SELECT COUNT(*) FROM sporcular WHERE dogum_yili IS NOT NULL AND (dogum_yili < 1920 OR dogum_yili > 2022)"
    ).fetchone()[0]
    print(f"\n[9] İmkansız doğum yılı (<1920 veya >2022 -> NULL): {bad_dy_cnt}")

    # 10. sporcular.cinsiyet normalizasyonu
    sp_gender_cnt = cur.execute(
        "SELECT COUNT(*) FROM sporcular WHERE cinsiyet IS NOT NULL AND cinsiyet != '' AND cinsiyet NOT IN ('ERKEK', 'KADIN', 'BELİRTİLMEMİŞ')"
    ).fetchone()[0]
    print(f"\n[10] sporcular.cinsiyet standardize edilecek kayıt: {sp_gender_cnt}")

    # 11. events.sehir & events.musabaka_adi (LİVE, combining dot i̇, büyük/küçük harf, UTF-8 mojibake)
    def _fix_mojibake(txt: str) -> str:
        if not txt or not any(ch in txt for ch in ("Ã", "Ä", "Å", "â")):
            return txt
        try:
            return txt.encode("latin1").decode("utf-8")
        except Exception:
            return txt

    def _tr_title(txt: str) -> str:
        s = unicodedata.normalize("NFC", txt.strip())
        # Türkçe i/İ doğru dönüşümü
        words = []
        for w in s.split():
            low = w.replace("İ", "i").replace("I", "ı").lower()
            first = low[0]
            first_up = "İ" if first == "i" else ("I" if first == "ı" else first.upper())
            words.append(first_up + low[1:])
        return " ".join(words)

    KNOWN_CITIES = ("ANKARA", "İSTANBUL", "ISTANBUL", "İZMİR", "IZMIR", "ISPARTA", "BURSA", "ANTALYA", "DENİZLİ", "ESKİŞEHİR", "TRABZON", "MERSİN", "SAMSUN", "KOCAELİ", "KAYSERİ", "KONYA", "GAZİANTEP", "EDİRNE", "SİVAS", "MUĞLA")
    event_updates = []
    for eid, esehir, emus in cur.execute("SELECT id, sehir, musabaka_adi FROM events").fetchall():
        new_mus = _fix_mojibake(emus or "")
        new_seh = unicodedata.normalize("NFC", (esehir or "").strip())
        if new_seh.upper() in ("LİVE", "LIVE"):
            new_seh = ""
            upper_m = new_mus.upper()
            for kc in KNOWN_CITIES:
                if upper_m.startswith(kc):
                    new_seh = _tr_title(kc)
                    break
        elif new_seh:
            # Sadece farklı yazım/combining dot varsa normalize et (çok kelimeli özel ifadeleri koruyarak)
            norm_seh = _tr_title(new_seh)
            if norm_seh != (esehir or ""):
                new_seh = norm_seh
        if new_mus != (emus or "") or new_seh != (esehir or ""):
            event_updates.append((eid, esehir, new_seh, emus, new_mus))
    print(f"\n[11] events (sehir / musabaka_adi) düzeltilecek kayıt: {len(event_updates)}")
    for eid, os_s, ns_s, om, nm in event_updates[:12]:
        print(f"    - id={eid}: sehir='{os_s}'->'{ns_s}' | musabaka='{om[:40]}'->'{nm[:40]}'")

    if not apply:
        print("\n[!] Dry-run tamamlandı. Uygulamak için --apply parametresi ile çalıştırın.")
        conn.close()
        return

    # --- APPLY ---
    try:
        conn.execute("BEGIN")

        # 1) Sahte kulüpleri temizle
        bad_club_ids = [cid for cid, _, _ in bad_clubs]
        if bad_club_ids:
            placeholders = ",".join("?" * len(bad_club_ids))
            cur.execute(
                f"UPDATE yaris_sonuclari SET kulup_id = NULL WHERE kulup_id IN ({placeholders})",
                bad_club_ids,
            )
            cur.execute(
                f"UPDATE sporcular SET birincil_kulup_id = NULL WHERE birincil_kulup_id IN ({placeholders})",
                bad_club_ids,
            )
            cur.execute(
                f"DELETE FROM sporcu_kulup_tarihce WHERE kulup_id IN ({placeholders})",
                bad_club_ids,
            )
            cur.execute(
                f"DELETE FROM kulupler WHERE id IN ({placeholders})",
                bad_club_ids,
            )

        # 2) Kulüp mirası (sahte kulüp temizlendikten sonra silinmemiş kulüpler için uygula)
        bad_set = set(bad_club_ids)
        inherited_count = 0
        for rid, sl_cid in inherit_map.items():
            if sl_cid not in bad_set:
                cur.execute("UPDATE yaris_sonuclari SET kulup_id = ? WHERE id = ?", (sl_cid, rid))
                inherited_count += 1

        # 3) DQ / SW / S.W / Disk. -> DSQ
        for rid, old_deg, old_note in dq_sw_rows:
            old_deg_s = (old_deg or "").strip()
            new_note = old_note or ""
            if (old_deg_s.upper().startswith(("SW", "S.W")) or "DISK" in old_deg_s.upper()) and old_deg_s not in new_note:
                new_note = f"DSQ - {old_deg_s}" if not new_note else f"{new_note} ({old_deg_s})"
            elif not new_note:
                new_note = "DSQ"
            cur.execute(
                "UPDATE yaris_sonuclari SET derece = 'DSQ', derece_saniye = NULL, uyari_notu = ? WHERE id = ?",
                (new_note, rid),
            )

        # 4) Sporcu ön ek temizliği (aynı ad + doğum yılı varsa birleştir, yoksa güncelle)
        merged_sp = 0
        renamed_sp = 0
        for sid, old_n, new_n, sdy in prefix_sporcular:
            res = _merge_or_rename_sporcu(cur, sid, new_n, sdy)
            if res == "merged":
                merged_sp += 1
            else:
                renamed_sp += 1

        # 5) '(Tk)' ön ekli kulüpleri birleştir/temizle
        tk_merged = 0
        tk_renamed = 0
        for cid, old_c, new_c in tk_clubs:
            res = _merge_or_rename_club(cur, cid, new_c)
            if res == "merged":
                tk_merged += 1
            else:
                tk_renamed += 1

        # 6) Sonunda 2 haneli doğum yılı yapışmış sporcular
        yr_merged = 0
        yr_renamed = 0
        for sid, old_n, new_n, tdy in trailing_yr_sp:
            res = _merge_or_rename_sporcu(cur, sid, new_n, tdy)
            if res == "merged":
                yr_merged += 1
            else:
                yr_renamed += 1

        # 7) İlk harfi (T/F) kesilmiş sporcu/takım adları
        chopped_merged = 0
        chopped_renamed = 0
        for sid, old_n, new_n, sdy in chopped_sp:
            res = _merge_or_rename_sporcu(cur, sid, new_n, sdy)
            if res == "merged":
                chopped_merged += 1
            else:
                chopped_renamed += 1

        # 8) CANLI_* cinsiyet normalizasyonu
        cur.execute(
            "UPDATE yaris_sonuclari SET cinsiyet = 'Erkek' WHERE kaynak_turu LIKE 'CANLI%' AND LOWER(cinsiyet) IN ('erkekler', 'erkek', 'men', 'boys')"
        )
        cur.execute(
            "UPDATE yaris_sonuclari SET cinsiyet = 'Kadın' WHERE kaynak_turu LIKE 'CANLI%' AND LOWER(cinsiyet) IN ('kadınlar', 'kadinlar', 'kızlar', 'kizlar', 'bayanlar', 'kadın', 'kadin', 'women', 'girls')"
        )
        cur.execute(
            "UPDATE yaris_sonuclari SET cinsiyet = 'Karma' WHERE kaynak_turu LIKE 'CANLI%' AND LOWER(cinsiyet) IN ('karma', 'mix')"
        )
        cur.execute(
            "UPDATE yaris_sonuclari SET cinsiyet = NULL WHERE kaynak_turu LIKE 'CANLI%' AND cinsiyet IS NOT NULL AND cinsiyet NOT IN ('Erkek', 'Kadın', 'Karma')"
        )

        # 9) İmkansız doğum yılı (<1920 veya >2022)
        cur.execute(
            "UPDATE sporcular SET dogum_yili = NULL WHERE dogum_yili IS NOT NULL AND (dogum_yili < 1920 OR dogum_yili > 2022)"
        )

        # 10) sporcular.cinsiyet normalizasyonu
        cur.execute(
            "UPDATE sporcular SET cinsiyet = 'ERKEK' WHERE LOWER(cinsiyet) IN ('erkek', 'erkekler', 'men', 'boys') AND cinsiyet != 'ERKEK'"
        )
        cur.execute(
            "UPDATE sporcular SET cinsiyet = 'KADIN' WHERE LOWER(cinsiyet) IN ('kadın', 'kadin', 'kadınlar', 'kadinlar', 'kızlar', 'kizlar', 'bayanlar', 'women', 'girls') AND cinsiyet != 'KADIN'"
        )
        cur.execute(
            "UPDATE sporcular SET cinsiyet = NULL WHERE cinsiyet IS NOT NULL AND cinsiyet != '' AND cinsiyet NOT IN ('ERKEK', 'KADIN', 'BELİRTİLMEMİŞ')"
        )

        # 11) events.sehir & events.musabaka_adi & canli_yarislar.sehir
        for eid, _, ns_s, _, nm in event_updates:
            cur.execute(
                "UPDATE events SET sehir = ?, musabaka_adi = ? WHERE id = ?",
                (ns_s, nm, eid),
            )
        cur.execute(
            """
            UPDATE canli_yarislar
            SET sehir = (
                SELECT e.sehir FROM events e
                WHERE e.id = canli_yarislar.event_id
                  AND e.sehir IS NOT NULL
                  AND UPPER(TRIM(e.sehir)) NOT IN ('LİVE', 'LIVE', '')
            )
            WHERE UPPER(TRIM(COALESCE(sehir, ''))) IN ('LİVE', 'LIVE')
            """
        )

        conn.commit()
        print(
            f"\n[OK] Güncelleme tamamlandı: {len(bad_club_ids)} sahte kulüp silindi, "
            f"{inherited_count} kulüp miras alındı, {len(dq_sw_rows)} DQ/SW->DSQ düzeltildi, "
            f"{renamed_sp}+{merged_sp} ön ek, {tk_renamed}+{tk_merged} (Tk) kulüp, "
            f"{yr_renamed}+{yr_merged} yapışık doğum yılı, {chopped_renamed}+{chopped_merged} kesik harf düzeltildi."
        )
    except Exception as exc:
        conn.rollback()
        print(f"[HATA] İşlem geri alındı: {exc}")
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="database/yuzme_server_copy.db")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    run_repair(args.db, apply=args.apply)
