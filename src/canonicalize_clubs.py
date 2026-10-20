"""
src/canonicalize_clubs.py
Sorumluluk: 42 sonuç dosyasındaki tüm kulüp ve okul isimlerini analiz ederek;
kısaltmaları, kesik/yarım kalan isimleri, ek varyasyonlarını (Derneği/Spor Kulübü/S.K.),
büyük/küçük harf ve imla farklarını deterministik olarak tekilleştirmek (Entity Resolution),
kanonik kulüp referansını üretmek ve sonuç tablolarını güncellemek.
"""

from __future__ import annotations

import csv
import json
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Dict, List, Any, Tuple

# Proje kök dizinini ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# Kapsamlı Kanonik Kulüp Eşleştirme Sözlüğü
# Ham Metin -> Standart Kanonik İsim
CLUB_CANONICAL_MAP: Dict[str, str] = {
    # V.A.M.O.S
    "Vamos Spor Kulübü": "V.A.M.O.S",

    # Keçiören Belediyesi Bağlum Spor Kulübü
    "Keçiören Belediyesi Bağlum Spor Kulubü": "Keçiören Belediyesi Bağlum Spor Kulübü",
    "Keçiören Belediyesi Bağlum Spo": "Keçiören Belediyesi Bağlum Spor Kulübü",
    "Keçiören Belediyesi Bağlum Spor Kulubü W1015": "Keçiören Belediyesi Bağlum Spor Kulübü",

    # Ted Ankara Kolejliler Spor Kulübü
    "Ted Ankara Kolejliler Spor Kul": "Ted Ankara Kolejliler Spor Kulübü",

    # Nesibe Aydın Gençlik Ve Spor Kulübü
    "Nesibe Aydın Gençlik Ve Spor K": "Nesibe Aydın Gençlik Ve Spor Kulübü",
    "Nesibe Aydın Spor Kulübü": "Nesibe Aydın Gençlik Ve Spor Kulübü",
    "Nesibe Aydın Okulları Yıldızlar Kampüsü": "Nesibe Aydın Okulları",

    # ODTÜ Spor Kulübü
    "Odtü Spor Kulübü": "ODTÜ Spor Kulübü",
    "Orta Doğu Teknik Üniversitesi Spor Kulübü": "ODTÜ Spor Kulübü",

    # Zafer Koleji Spor Kulübü
    "Zafer Koleji Spor Kulübü Derneği": "Zafer Koleji Spor Kulübü",
    "Zafer Koleji Spor Kulübü Derne": "Zafer Koleji Spor Kulübü",
    "Zafer Koleji": "Zafer Koleji Spor Kulübü",

    # Ankara Üniversitesi Su Sporları Kulübü
    "Ankara Üniversitesi Su Sporları Kulübü Derneği": "Ankara Üniversitesi Su Sporları Kulübü",

    # Ankara Üniversitesi Spor Kulübü
    "Ankara Üniversitesi Spor Kulüb": "Ankara Üniversitesi Spor Kulübü",

    # Ankara Yüzme Kulübü Spor Kulübü
    "Ankara Yüzme Kulübü": "Ankara Yüzme Kulübü Spor Kulübü",

    # Hacettepeliler Spor Kulübü
    "Hacettepeliler": "Hacettepeliler Spor Kulübü",

    # Beştepe Koleji Spor Kulübü
    "Beştepe Koleji": "Beştepe Koleji Spor Kulübü",

    # Yenimahalle Belediyesi Spor Kulübü
    "Yenimahalle Belediyesi S.K": "Yenimahalle Belediyesi Spor Kulübü",
    "Yenimahalle Belediyesi S.K.": "Yenimahalle Belediyesi Spor Kulübü",

    # Orka Swim Team Spor Kulübü
    "Orka Swim Team": "Orka Swim Team Spor Kulübü",

    # Dört Mevsim Spor Kulübü
    "Dört Mevsim Spor Kulübü Derneği": "Dört Mevsim Spor Kulübü",
    "Dört Mevsim Spor Kulübü Derneğ": "Dört Mevsim Spor Kulübü",

    # Sınav Koleji Spor Kulübü
    "Sınav Koleji": "Sınav Koleji Spor Kulübü",

    # Ankara Enerji Yüzme Spor Kulübü
    "Ankara Enerji Yüzme Spor Kulübü Dernegi": "Ankara Enerji Yüzme Spor Kulübü",
    "Ankara Enerji Yüzme Spor Kulüb": "Ankara Enerji Yüzme Spor Kulübü",
    "ANKARA ENERJİ YÜZME S.K.": "Ankara Enerji Yüzme Spor Kulübü",

    # Ankara Yüzme Akademisi Spor Kulübü
    "Ankara Yüzme Akademisi Gençlik": "Ankara Yüzme Akademisi Spor Kulübü",
    "Ankara Yüzme Akademisi Gençlik Geliştirme Spor Kulübü Derneği": "Ankara Yüzme Akademisi Spor Kulübü",
    "Spor Kulübü Ankara Yüzme Akademisi Spor Kulübü": "Ankara Yüzme Akademisi Spor Kulübü",

    # Ankara GSM Spor Kulübü
    "Ankara Gsm Spor Kulubu": "Ankara Gsm Spor Kulübü",

    # Rota Spor Kulübü
    "Rota": "Rota Spor Kulübü",

    # Anka Spor Gelişim Spor Kulübü
    "Anka Spor Gelişim Kulübü": "Anka Spor Gelişim Spor Kulübü",

    # Sınav Eğitim Kültür Gençlik Ve Spor Kulübü Derneği
    "Sınav Eğitim Kültür Gençlik Ve": "Sınav Eğitim Kültür Gençlik Ve Spor Kulübü Derneği",

    # Petrol Ofisi Spor Kulübü
    "Petrol Ofisi": "Petrol Ofisi Spor Kulübü",

    # Ankara Kurt Yüzme Tenis Jimnastik İhtisas Spor Kulübü
    "Ankara Kurt Yüzme Tenis Jimnas": "Ankara Kurt Yüzme Tenis Jimnastik İhtisas Spor Kulübü",
    "Ankara Kurt Yüzme Tenis Jimnastik Ihtisas Kulübü Derneği": "Ankara Kurt Yüzme Tenis Jimnastik İhtisas Spor Kulübü",

    # Ankara Gençlik Hizmetleri Gençlik Ve Spor Kulübü Derneği
    "Ankara Gençlik Hizmetleri Genç": "Ankara Gençlik Hizmetleri Gençlik Ve Spor Kulübü Derneği",

    # My Sun Spor Kulübü
    "My Sun": "My Sun Spor Kulübü",

    # Aykon Spor Kulübü
    "Aykon Performans Spor Kulübü Derneği": "Aykon Spor Kulübü",

    # Okul ve Kolej Standartlaştırmaları
    "Özel Ankara Abc Ilkokulu": "Özel Ankara ABC İlkokulu",
    "Özel Ankara ABC Ilkokulu": "Özel Ankara ABC İlkokulu",
    "IDV. Özel Bilkent Lisesi": "İDV Özel Bilkent Lisesi",
    "Idv. Özel Bilkent Lisesi": "İDV Özel Bilkent Lisesi",
    "Mehmet Akif Inan Ilkokulu": "Mehmet Akif İnan İlkokulu",
    "Hacı Bektaş-ı Veli Ortaokulu": "Hacı Bektaş Veli Ortaokulu",
    "Gaziosmanpaşa Ortaokulu": "Gazi Osman Paşa Ortaokulu",
    "Ağa Ceylan Ilkokulu": "Ağa Ceylan İlkokulu",
    "Hüseyin Güllüoğlu Orta Okulu": "Hüseyin Güllüoğlu Ortaokulu",
    "Özel Yükselen Koleji Ilkokul": "Özel Yükselen Koleji İlkokulu",
    "Özel Çankaya Bilişim Ilkokul": "Özel Çankaya Bilişim İlkokulu",
    "Eryaman Okyanus Koleji": "Özel Eryaman Okyanus Koleji",
    "Ankara Uğur Anadolu Lisesi": "Özel Ankara Uğur Anadolu Lisesi",
    "Ovacık Sınav Koleji": "Özel Ovacık Sınav Koleji",
    "Özel Çankaya Bahçeşehir Koleji": "Özel Çankaya Bahçeşehir Koleji 50.Yıl İlkokulu",
    "Özel Çankaya Bahçeşehir Koleji 50.Yıl Ilkokulu": "Özel Çankaya Bahçeşehir Koleji 50.Yıl İlkokulu",
    "Özel Metod Koleji": "Özel Metod Koleji Ortaokulu",
    "Tema Koleji": "Özel Tema Koleji İlkokulu",
    "Özel Tema Koleji Ilkokulu": "Özel Tema Koleji İlkokulu",
    "Özel Tema Koleji (Balgat Şube)": "Özel Tema Koleji İlkokulu",
}


def get_canonical_club(raw_club: str) -> str:
    """Verilen ham kulüp adının kanonik karşılığını döndürür."""
    c = raw_club.strip()
    return CLUB_CANONICAL_MAP.get(c, c)


def build_club_canonical_reference(
    swimmer_csv: str | Path = "output/bireysel_yuzucu_sonuclari.csv",
    dq_csv: str | Path = "output/diskalifiyeler.csv",
    out_map_csv: str | Path = "output/reference/kulup_tekillestirme_haritasi.csv",
    out_canon_json: str | Path = "output/reference/canonical_clubs.json"
) -> Dict[str, Any]:
    """Tüm veri kümesindeki kulüpleri tarar, haritayı ve JSON referansını oluşturur."""
    os.makedirs(os.path.dirname(str(out_map_csv)), exist_ok=True)

    raw_counts = Counter()
    with open(swimmer_csv, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            c = r["Kulüp"].strip()
            if c:
                raw_counts[c] += 1

    with open(dq_csv, encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            if r.get("Bayrak Mı") == "EVET":
                continue
            c = r["Kulüp"].strip()
            if c:
                raw_counts[c] += 1

    # Kanonik eşleştirme haritası CSV
    map_rows = []
    canonical_clusters = defaultdict(lambda: {"count": 0, "variants": Counter()})

    for raw, cnt in raw_counts.most_common():
        canon = get_canonical_club(raw)
        canonical_clusters[canon]["count"] += cnt
        canonical_clusters[canon]["variants"][raw] += cnt
        map_rows.append({
            "Ham Kulüp Adı": raw,
            "Kanonik Kulüp Adı": canon,
            "Değişti Mi": "EVET" if raw != canon else "HAYIR",
            "Kullanım Sayısı": cnt,
        })

    with open(out_map_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["Ham Kulüp Adı", "Kanonik Kulüp Adı", "Değişti Mi", "Kullanım Sayısı"])
        writer.writeheader()
        writer.writerows(map_rows)

    # JSON referansı (Kanonik isim, toplam sayı ve varyasyonlar)
    json_data = []
    for canon, data in sorted(canonical_clusters.items(), key=lambda x: -x[1]["count"]):
        json_data.append({
            "canonical_club": canon,
            "total_count": data["count"],
            "variants_count": len(data["variants"]),
            "variants": [
                {"raw_name": v, "count": c}
                for v, c in data["variants"].most_common()
            ]
        })

    with open(out_canon_json, "w", encoding="utf-8") as f:
        json.dump(json_data, f, ensure_ascii=False, indent=2)

    return {
        "raw_club_count": len(raw_counts),
        "canonical_club_count": len(canonical_clusters),
        "mapped_variants_count": len(CLUB_CANONICAL_MAP),
        "affected_rows_count": sum(cnt for raw, cnt in raw_counts.items() if raw in CLUB_CANONICAL_MAP),
        "out_map_csv": out_map_csv,
        "out_canon_json": out_canon_json,
    }


def apply_canonical_clubs_to_datasets(
    swimmer_csv: str | Path = "output/bireysel_yuzucu_sonuclari.csv",
    dq_csv: str | Path = "output/diskalifiyeler.csv"
) -> Tuple[int, int]:
    """Bireysel yüzücü sonuçları ve diskalifiye dosyalarındaki kulüp adlarını kanonik karşılıklarıyla günceller."""
    # 1. Swimmers
    with open(swimmer_csv, encoding="utf-8-sig") as f:
        swimmer_rows = list(csv.DictReader(f))
        swimmer_fields = list(swimmer_rows[0].keys())

    updated_swimmers = 0
    for r in swimmer_rows:
        raw_c = r["Kulüp"].strip()
        canon_c = get_canonical_club(raw_c)
        if raw_c != canon_c:
            r["Kulüp"] = canon_c
            updated_swimmers += 1

    with open(swimmer_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=swimmer_fields)
        writer.writeheader()
        writer.writerows(swimmer_rows)

    # JSON eşleniğini de güncelle
    swimmer_json = str(swimmer_csv).replace(".csv", ".json")
    if os.path.exists(swimmer_json):
        with open(swimmer_json, "w", encoding="utf-8") as f:
            json.dump(swimmer_rows, f, ensure_ascii=False, indent=2)

    # 2. Disqualifications
    with open(dq_csv, encoding="utf-8-sig") as f:
        dq_rows = list(csv.DictReader(f))
        dq_fields = list(dq_rows[0].keys())

    updated_dqs = 0
    for r in dq_rows:
        raw_c = r["Kulüp"].strip()
        canon_c = get_canonical_club(raw_c)
        if raw_c != canon_c:
            r["Kulüp"] = canon_c
            updated_dqs += 1

    with open(dq_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=dq_fields)
        writer.writeheader()
        writer.writerows(dq_rows)

    dq_json = str(dq_csv).replace(".csv", ".json")
    if os.path.exists(dq_json):
        with open(dq_json, "w", encoding="utf-8") as f:
            json.dump(dq_rows, f, ensure_ascii=False, indent=2)

    return updated_swimmers, updated_dqs


if __name__ == "__main__":
    print("Kulüp tekilleştirme ve kanonikleştirme süreci başlatılıyor...")
    ref_info = build_club_canonical_reference()

    print("\n" + "=" * 65)
    print("             KULÜP TEKİLLEŞTİRME ÖZET RAPORU            ")
    print("=" * 65)
    print(f" Başlangıçtaki Ham Farklı Kulüp Sayısı     : {ref_info['raw_club_count']:5d}")
    print(f" Tanımlanan Kanonik Eşleştirme Kuralı      : {ref_info['mapped_variants_count']:5d}")
    print(f" Tekilleştirme Sonrası Kanonik Kulüp Sayısı: {ref_info['canonical_club_count']:5d}")
    print(f" Etkilenen / Birleştirilen Toplam Kayıt    : {ref_info['affected_rows_count']:5d}")
    print("=" * 65)

    up_sw, up_dq = apply_canonical_clubs_to_datasets()
    print(f"\n[BAŞARILI] Veri setleri kanonik kulüp adlarıyla güncellendi:")
    print(f"  - Bireysel yüzücü satırlarında güncellenen kulüp sayısı: {up_sw}")
    print(f"  - Diskalifiye satırlarında güncellenen kulüp sayısı   : {up_dq}")
    print(f"\nHarita CSV : {ref_info['out_map_csv']}")
    print(f"Kanonik JSON: {ref_info['out_canon_json']}")

