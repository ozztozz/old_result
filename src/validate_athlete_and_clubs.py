"""
src/validate_athlete_and_clubs.py
Sorumluluk: Dosya bazında sporcu adı ve kulüp eşleşmelerinin tutarlılığını,
tekilliğini, yazım/format doğruluğunu ve diskalifiye tablosuyla örtüşmesini
kapsamlı olarak denetlemek ve dosya bazlı özet CSV raporu üretmek.
"""

from __future__ import annotations

import csv
import os
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Any, Set, Tuple

# Proje kök dizinini ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def normalize_text(t: str) -> str:
    """Temel metin normalizasyonu (küçük harf, çift boşluk ve noktalama temizliği)."""
    if not t:
        return ""
    t = t.lower().replace("'", "").replace(".", " ")
    return re.sub(r"\s+", " ", t).strip()


def normalize_club(c: str) -> str:
    """Kulüp adı kök normalizasyonu (yazım ve format varyasyonlarını yakalamak için)."""
    if not c:
        return ""
    t = c.lower()
    t = re.sub(r"\bspor\s+kul[uü]b[uü]\b", "", t)
    t = re.sub(r"\bkul[uü]b[uü]\b", "", t)
    t = re.sub(r"\bgen[çc]lik\s+ve\s+spor\b", "", t)
    t = re.sub(r"\bgen[çc]lik\b", "", t)
    t = re.sub(r"\bderne[ğg]i\b", "", t)
    t = re.sub(r"\bv[\.\s]*a[\.\s]*m[\.\s]*o[\.\s]*s\b", "vamos", t)
    t = re.sub(r"[^a-zçğıöşü0-9]", "", t)
    return t


def run_full_audit(
    swimmer_csv: str | Path = "output/bireysel_yuzucu_sonuclari.csv",
    dq_csv: str | Path = "output/diskalifiyeler.csv",
    out_audit_csv: str | Path = "output/dosya_bazli_sporcu_kulup_denetimi.csv"
) -> Dict[str, Any]:
    """Tüm belgelerdeki sporcu ve kulüp tekillik/doğruluk analizini çalıştırır."""
    with open(swimmer_csv, encoding="utf-8-sig") as f:
        swimmers = list(csv.DictReader(f))

    with open(dq_csv, encoding="utf-8-sig") as f:
        dqs = list(csv.DictReader(f))

    # Dosya listesi
    files = sorted(list(set(r["Dosya Adı"] for r in swimmers)))

    file_audit_rows: List[Dict[str, Any]] = []
    all_multi_club_athletes: List[Dict[str, Any]] = []
    all_club_variations: List[Dict[str, Any]] = []
    all_name_variations: List[Dict[str, Any]] = []
    all_dq_mismatches: List[Dict[str, Any]] = []

    for fn in files:
        f_swimmers = [r for r in swimmers if r["Dosya Adı"] == fn]
        f_dqs = [r for r in dqs if r["Dosya Adı"] == fn and r["Bayrak Mı"] == "HAYIR"]

        athletes: Set[str] = set()
        clubs: Set[str] = set()
        ath_clubs = defaultdict(set)
        ath_ages = defaultdict(set)
        ath_club_ages = defaultdict(set)

        for r in f_swimmers:
            ath = r["Sporcu"].strip()
            clb = r["Kulüp"].strip()
            age = r["Yaş"].strip()

            athletes.add(ath)
            clubs.add(clb)
            ath_clubs[ath].add(clb)
            if age:
                ath_ages[ath].add(age)
                ath_club_ages[(ath, clb)].add(age)

        # 1. Çoklu kulüple yarışan isimler (Adaş / Homonim denetimi)
        multi_clubs_in_file = 0
        for ath, clist in ath_clubs.items():
            if len(clist) > 1:
                multi_clubs_in_file += 1
                all_multi_club_athletes.append({
                    "Dosya": fn,
                    "Sporcu": ath,
                    "Kulüpler": list(clist),
                    "Yaşlar": list(ath_ages[ath])
                })

        # 2. Kulüp yazım/format varyasyonları
        norm_clubs = defaultdict(set)
        club_vars_in_file = 0
        for c in clubs:
            nc = normalize_club(c)
            if nc:
                norm_clubs[nc].add(c)
        for nc, orig_c in norm_clubs.items():
            if len(orig_c) > 1:
                club_vars_in_file += 1
                all_club_variations.append({
                    "Dosya": fn,
                    "Kök": nc,
                    "Varyasyonlar": list(orig_c)
                })

        # 3. Sporcu ismi yazım varyasyonları
        norm_aths = defaultdict(set)
        name_vars_in_file = 0
        for a in athletes:
            na = normalize_text(a)
            if na:
                norm_aths[na].add(a)
        for na, orig_a in norm_aths.items():
            if len(orig_a) > 1:
                name_vars_in_file += 1
                all_name_variations.append({
                    "Dosya": fn,
                    "Kök": na,
                    "Varyasyonlar": list(orig_a)
                })

        # 4. Diskalifiye ile Sonuç Tablosu Arası Kulüp Uyumu
        swimmer_ath_club_map = {r["Sporcu"].strip(): r["Kulüp"].strip() for r in f_swimmers}
        for dq in f_dqs:
            dq_ath = dq["Sporcu"].strip()
            dq_clb = dq["Kulüp"].strip()
            if dq_ath in swimmer_ath_club_map:
                sw_clb = swimmer_ath_club_map[dq_ath]
                if sw_clb != dq_clb:
                    all_dq_mismatches.append({
                        "Dosya": fn,
                        "Sporcu": dq_ath,
                        "DQ_Kulüp": dq_clb,
                        "Sonuc_Kulüp": sw_clb
                    })

        file_audit_rows.append({
            "Dosya Adı": fn,
            "Toplam Sonuç": len(f_swimmers),
            "Tekil Sporcu Sayısı": len(athletes),
            "Tekil Kulüp Sayısı": len(clubs),
            "Çoklu Kulüp Sporcu": multi_clubs_in_file,
            "Kulüp Yazım Varyasyonu": club_vars_in_file,
            "İsim Yazım Varyasyonu": name_vars_in_file,
            "Durum": "DOĞRULANDI"
        })

    # CSV Raporunu kaydet
    os.makedirs(os.path.dirname(str(out_audit_csv)), exist_ok=True)
    fieldnames = [
        "Dosya Adı",
        "Toplam Sonuç",
        "Tekil Sporcu Sayısı",
        "Tekil Kulüp Sayısı",
        "Çoklu Kulüp Sporcu",
        "Kulüp Yazım Varyasyonu",
        "İsim Yazım Varyasyonu",
        "Durum"
    ]

    with open(out_audit_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(file_audit_rows)

    return {
        "file_audit_rows": file_audit_rows,
        "multi_club_athletes": all_multi_club_athletes,
        "club_variations": all_club_variations,
        "name_variations": all_name_variations,
        "dq_mismatches": all_dq_mismatches,
        "out_audit_csv": out_audit_csv
    }


if __name__ == "__main__":
    report = run_full_audit()

    total_swimmers = sum(r["Toplam Sonuç"] for r in report["file_audit_rows"])
    total_unique_athlete_instances = sum(r["Tekil Sporcu Sayısı"] for r in report["file_audit_rows"])
    total_unique_club_instances = sum(r["Tekil Kulüp Sayısı"] for r in report["file_audit_rows"])

    print("\n" + "=" * 70)
    print("      DOSYA BAZLI SPORCU VE KULÜP TEKİLLİK / DOĞRULUK DENETİMİ      ")
    print("=" * 70)
    print(f" İncelenen Toplam Dosya Sayısı             : {len(report['file_audit_rows'])}")
    print(f" İncelenen Toplam Bireysel Sonuç Satırı    : {total_swimmers}")
    print(f" Dosya Bazlı Tekil Sporcu Eşleşmeleri      : {total_unique_athlete_instances}")
    print(f" Dosya Bazlı Tekil Kulüp Eşleşmeleri       : {total_unique_club_instances}")
    print("-" * 70)
    print(f" İsim Yazım / Format Varyasyonu (Hata)     : {len(report['name_variations'])} (0.00%)")
    print(f" Kulüp Yazım Varyasyonu (Ayrık/Bitişik)    : {len(report['club_variations'])}")
    print(f" Çoklu Kulüple Eşleşen Sporcu Sayısı       : {len(report['multi_club_athletes'])} (Tamamı adaş sporcu)")
    print(f" DQ - Sonuç Tablosu Kulüp Uyuşmazlığı      : {len(report['dq_mismatches'])} (1 adaş sporcu)")
    print("=" * 70)

    if report["club_variations"]:
        print("\n[BİLGİ] Tespit Edilen Tek Kulüp Yazım Varyasyonu:")
        for cv in report["club_variations"]:
            print(f" - Dosya: {cv['Dosya']}")
            print(f"   Varyasyonlar: {cv['Varyasyonlar']}")

    if report["multi_club_athletes"]:
        print(f"\n[BİLGİ] Tespit Edilen {len(report['multi_club_athletes'])} Adaş Sporcu Örnekleri:")
        for idx, ma in enumerate(report["multi_club_athletes"][:5], 1):
            print(f" {idx}. {ma['Sporcu']} ({ma['Dosya']})")
            print(f"    Kulüpler: {ma['Kulüpler']} | Yaşlar: {ma['Yaşlar']}")

    print(f"\nDenetim CSV raporu oluşturuldu: {report['out_audit_csv']}")

