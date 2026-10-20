"""
Clean Reference Data Builder
============================
42 temiz metin tabanlı PDF çıktısını ayrıştırarak:
1. Kanonik sporcu veri tabanını (output/canonical_athletes.csv & output/reference/canonical_swimmers.json)
2. Kanonik kulüp veri tabanını (output/reference/canonical_clubs.json)
3. Bireysel ve bayrak yarış sonuçlarını (output/swimmer_results_clean.csv & output/relay_results.csv)
4. Atlanan satırlar denetim listesini (output/unparsed_lines.csv)
oluşturur ve günceller.
"""

import csv
import glob
import json
import os
import shutil
import time
from collections import Counter, defaultdict
from pathlib import Path

from src.parser import parse_file


def build_all(txt_dir: str = "output/txt/ankara", output_dir: str = "output"):
    txt_path = Path(txt_dir)
    out_path = Path(output_dir)
    ref_path = out_path / "reference"
    ref_path.mkdir(parents=True, exist_ok=True)

    # Sadece metin tabanlı temiz PDF'lerin çıktıları (sayısal OCR isimleri hariç)
    native_txt_files = [
        f for f in sorted(txt_path.glob("*.txt"))
        if not f.stem.isdigit()
    ]

    print(f"[*] {len(native_txt_files)} adet temiz metin belgesi işleniyor...")

    all_swimmers = []
    all_relays = []
    all_unparsed = []

    club_counter = Counter()
    # Sporcu anahtarı: (İsim, Doğum Yılı) -> Sporcu kimliği (Kulüp veya yaşa göre değil!)
    athletes = defaultdict(lambda: {
        "clubs": Counter(),
        "files": set(),
        "races": 0,
        "first_year": 9999,
        "last_year": 0,
        "distances": set(),
        "strokes": set(),
    })

    t0 = time.perf_counter()

    for idx, fpath in enumerate(native_txt_files, start=1):
        fn = fpath.name
        meet, swimmers, relays, unparsed = parse_file(fpath)

        for s in swimmers:
            all_swimmers.append((fn, s))
            c_name = " ".join(s.name.split())
            key = (c_name, s.birth_year)
            ath = athletes[key]
            ath["clubs"][s.club] += 1
            ath["files"].add(fn)
            ath["races"] += 1
            if s.distance:
                ath["distances"].add(s.distance)
            if s.stroke:
                ath["strokes"].add(s.stroke)

            if s.club:
                club_counter[s.club] += 1

        for r in relays:
            all_relays.append((fn, r))
            if r.club:
                club_counter[r.club] += 1

        for u in unparsed:
            all_unparsed.append((fn, u))

    elapsed = time.perf_counter() - t0
    print(f"[+] Ayrıştırma tamamlandı! ({elapsed:.2f}s)")
    print(f"    - Bireysel Yarış Sonucu : {len(all_swimmers):,}")
    print(f"    - Bayrak Yarış Sonucu   : {len(all_relays):,}")
    print(f"    - Benzersiz Sporcu      : {len(athletes):,}")
    print(f"    - Benzersiz Kulüp/Okul  : {len(club_counter):,}")
    print(f"    - Atlanan Satır         : {len(all_unparsed):,}")

    # 1. Kanonik Sporcular CSV
    canon_ath_file = out_path / "canonical_athletes.csv"
    with open(canon_ath_file, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "Sporcu Adı",
            "Doğum Yılı",
            "Birincil Kulüp",
            "Toplam Yarış Sayısı",
            "Temsil Ettiği Kulüpler ve Okullar",
            "Katıldığı Dosya Sayısı",
        ])
        for (name, by), data in sorted(athletes.items(), key=lambda x: -x[1]["races"]):
            primary_club = data["clubs"].most_common(1)[0][0] if data["clubs"] else "Bilinmiyor"
            all_clubs_str = "; ".join([f"{c} ({cnt})" for c, cnt in data["clubs"].most_common()])
            w.writerow([
                name,
                by,
                primary_club,
                data["races"],
                all_clubs_str,
                len(data["files"]),
            ])
    print(f"[+] Kanonik sporcu CSV kaydedildi: {canon_ath_file}")

    # 2. Kanonik Sporcular JSON Referansı
    canon_swimmer_json = ref_path / "canonical_swimmers.json"
    swimmer_list = []
    for (name, by), data in sorted(athletes.items(), key=lambda x: -x[1]["races"]):
        primary_club = data["clubs"].most_common(1)[0][0] if data["clubs"] else "Bilinmiyor"
        swimmer_list.append({
            "name": name,
            "birth_year": by,
            "primary_club": primary_club,
            "race_count": data["races"],
            "clubs": dict(data["clubs"]),
        })
    canon_swimmer_json.write_text(json.dumps(swimmer_list, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[+] Kanonik sporcu JSON referansı kaydedildi: {canon_swimmer_json}")

    # 3. Kanonik Kulüpler JSON Referansı
    canon_clubs_json = ref_path / "canonical_clubs.json"
    club_list = [{"club": c, "count": cnt} for c, cnt in club_counter.most_common()]
    canon_clubs_json.write_text(json.dumps(club_list, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[+] Kanonik kulüp JSON referansı kaydedildi: {canon_clubs_json}")

    # 4. Bireysel Yarış Sonuçları CSV (Excel kilidine karşı güvenli yazım)
    swimmer_csv_clean = out_path / "swimmer_results_clean.csv"
    swimmer_csv_main = out_path / "swimmer_results.csv"

    def write_swimmer_rows(f):
        w = csv.writer(f)
        w.writerow([
            "Dosya", "Müsabaka Adı", "Şehir", "Tarih", "Seans", "Yarış No",
            "Cinsiyet", "Mesafe", "Stil", "Yaş Grubu", "Sıra", "Sporcu Adı",
            "Doğum Yılı", "Kulüp", "Katılım Türü", "Derece", "Saniye",
            "Puan", "Baraj Geçti", "Durum", "DQ Kural", "DQ Neden", "DQ Saat",
            "Ara Süreler",
        ])
        for fn, s in all_swimmers:
            w.writerow([
                fn, s.meet_name, s.meet_location, s.meet_date, s.session, s.race_number,
                s.gender, s.distance, s.stroke, s.age_group, s.rank or "", s.name,
                s.birth_year or "", s.club, s.participation_type or "",
                s.time_txt or "", s.time_sec or "", s.points or "",
                "EVET" if s.qualified else "HAYIR", s.status,
                s.dq_rule or "", s.dq_reason or "", s.dq_clock or "",
                " ".join(s.row_times),
            ])

    with open(swimmer_csv_clean, "w", encoding="utf-8-sig", newline="") as f:
        write_swimmer_rows(f)
    print(f"[+] Temiz bireysel sonuçlar kaydedildi: {swimmer_csv_clean}")

    try:
        with open(swimmer_csv_main, "w", encoding="utf-8-sig", newline="") as f:
            write_swimmer_rows(f)
        print(f"[+] Ana bireysel sonuçlar güncellendi: {swimmer_csv_main}")
    except PermissionError:
        print(f"[!] {swimmer_csv_main} kullanıcı tarafından açık (Excel vb.), temiz kopya {swimmer_csv_clean} olarak korundu.")

    # 5. Bayrak Yarış Sonuçları CSV
    relay_csv = out_path / "relay_results.csv"
    with open(relay_csv, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "Dosya", "Müsabaka Adı", "Şehir", "Tarih", "Seans", "Yarış No",
            "Cinsiyet", "Takım Kişi", "Mesafe", "Stil", "Yaş Grubu", "Sıra",
            "Takım Adı", "Kulüp", "Derece", "Saniye", "Puan", "Durum",
            "DQ Kural", "DQ Neden", "Yüzücüler",
        ])
        for fn, r in all_relays:
            sw_str = "; ".join([
                f"{sw.name} ({sw.birth_year or '?'}) [{sw.split_time or '-'}]"
                for sw in r.swimmers
            ]) if r.swimmers else ""
            w.writerow([
                fn, r.meet_name, r.meet_location, r.meet_date, r.session, r.race_number,
                r.gender, r.relay_count, r.distance, r.stroke, r.age_group, r.rank or "",
                r.team_name, r.club, r.time_txt or "", r.time_sec or "", r.points or "",
                r.status, r.dq_rule or "", r.dq_reason or "", sw_str,
            ])
    print(f"[+] Bayrak sonuçları kaydedildi: {relay_csv}")

    # 6. Atlanan Satırlar CSV
    unparsed_csv = out_path / "unparsed_lines.csv"
    with open(unparsed_csv, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Dosya", "Satır No", "Satır İçeriği", "Neden", "Müsabaka", "Seans", "Kategori"])
        for fn, u in all_unparsed:
            w.writerow([fn, u.line_number, u.raw_text, u.reason, u.meet_name, u.session, u.event_title])
    print(f"[+] Atlanan satırlar kaydedildi: {unparsed_csv}")


if __name__ == "__main__":
    build_all()
