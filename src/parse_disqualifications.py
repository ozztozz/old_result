"""
src/parse_disqualifications.py
Sorumluluk: Metin belgelerindeki tüm diskalifiye ('disk.') ve yarış terk ('yarış terk')
kayıtlarını deterministik olarak ayrıştırıp DisqualificationMetadata modeliyle doğrulamak,
CSV ve JSON çıktılarını üretmek.
"""

from __future__ import annotations

import csv
import glob
import json
import os
import re
import sys
from pathlib import Path
from typing import List, Dict, Any, Optional

# Proje kökünü sys.path'e ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.models import DisqualificationMetadata

PAGE_RE = re.compile(r"^===\s*SAYFA\s*(\d+)\s*/\s*(\d+)\s*===", re.I)

RACE_HEADER_RE = re.compile(
    r"^\s*Yar[ıiIİ][şsSŞ]\s+(\d+)\s*(?:,\s*|(?:\s{2,}|\t+))"
    r"([A-ZÇĞİÖŞÜa-zçğıöşü\s,]+?)(?:,\s*|(?:\s{2,}|\t+))"
    r"(\d+\s*x\s*\d+m|\d+m)\s+"
    r"([A-Za-zÇĞİÖŞÜçğıöşü\s]+?)"
    r"(?:(?:,\s*|(?:\s{2,}|\t+))([0-9\s\-+a-zçğıöşüA-ZÇĞİÖŞÜ]+))?$",
    re.I,
)

TURKISH_CHARS = r"A-Za-zÇĞİÖŞÜçğıöşüÂÎÛâîû"
TAG_RE = re.compile(r"\((?:Tk|Td|Fd|tk|td|fd|TK|TD|FD)\)\s*")


def clean_tags(text: str) -> str:
    """Metindeki (Tk), (Td), (Fd) etiketlerini temizler."""
    t = TAG_RE.sub("", text)
    return re.sub(r"\s+", " ", t).strip()

PATTERN_WITH_AGE = re.compile(
    rf"^(?P<prefix>disk\.|yar[ıi]ş\s+terk)\s+"
    rf"(?P<sporcu>[{TURKISH_CHARS}0-9\s\.\(\)\'\-]+?)"
    rf"(?:\s+|\t+|(?<=[{TURKISH_CHARS}\.]))"
    rf"(?P<yas>\d{{1,2}})"
    rf"\s+"
    rf"(?P<kulup>.+?)"
    rf"(?:\s{{2,}}|\t+|$)"
    rf"(?P<rem>(?:\d{{1,2}}:)?\d{{2}}\.\d{{2}}.*|[sS][wW0-9\.\s]+)?\s*$",
    re.I,
)

PATTERN_NO_AGE = re.compile(
    rf"^(?P<prefix>disk\.|yar[ıi]ş\s+terk)\s+"
    rf"(?P<sporcu>[{TURKISH_CHARS}0-9\s\.\(\)\'\-]+?)"
    rf"(?:\s{{2,}}|\t+)"
    rf"(?P<kulup>[{TURKISH_CHARS}0-9\s\.\(\)\'\-]+?)"
    rf"(?:\s{{2,}}|\t+|$)"
    rf"(?P<rem>(?:\d{{1,2}}:)?\d{{2}}\.\d{{2}}.*|[sS][wW0-9\.\s]+)?\s*$",
    re.I,
)

FOOTER_NAMES = {
    "ALİ SERCAN SEVER", "ERGUN SAVAN", "KEZBAN ALGİL", "FİLİZ ALPER",
    "FULYA TİLLİOĞLU", "YÜCEL YILMAZ", "HALDUN ÖZTAŞ", "D.KEMAL KARADENİZ",
    "NESLİHAN YILDIRAN", "SERENA VURAL", "KEMAL KARADENİZ"
}


def is_trailing_token(tok: str) -> bool:
    """Belirtecin bitiş sütunlarına (SW kodu, zaman, ara zaman veya RT) ait olup olmadığını belirler."""
    t = tok.strip()
    if not t:
        return False
    # SW kural kodları (SW7.1, SW6,5, SW4.4, SW6.4, SW41, S1013, SW.8., vb.)
    if re.match(r"^[sS][wW0-9\.,]+$", t) or re.match(r"^[sS]10\d+$", t):
        return True
    # Derece, ara zaman veya reaksiyon süresi (0.01, 54.03, 1:00.94, 2:59.51)
    if re.match(r"^(?:\d{1,2}:)?\d{1,2}[\.,]\d{2}$", t):
        return True
    return False


def parse_dq_first_line(raw_line: str) -> Dict[str, Any]:
    """İlk satırdan sporcu, yaş, kulüp, zaman ve bayrak durumunu deterministik olarak çıkarır."""
    l_str = raw_line.strip()
    is_terk = bool(re.match(r"^yar[ıi]ş\s+terk\s+", l_str, re.I))
    content = re.sub(r"^(?:disk\.|yar[ıi]ş\s+terk)\s+", "", l_str, flags=re.I).strip()

    # İsim ve 2 haneli yaşın bitişik çıktığı durumları ayır (örn: SAYAROĞLU14 -> SAYAROĞLU  14)
    m_concat = re.match(r"^([A-ZÇĞİÖŞÜa-zçğıöşü\s\.\(\)\'\-]+?[A-Za-zÇĞİÖŞÜçğıöşüÂÎÛâîû\.])(\d{1,2})\s+(.+)$", content)
    if m_concat:
        content = f"{m_concat.group(1)}  {m_concat.group(2)}  {m_concat.group(3)}"

    # 2 veya daha fazla boşluğa göre ana bloklara böl
    parts = [p.strip() for p in re.split(r"\s{2,}|\t+", content) if p.strip()]

    # İlk parça isim + tek boşluk + yaş içeriyorsa ayır (örn: 'Yağız Umut KELALİOĞLU 14')
    if parts:
        m_sp = re.match(r"^(.+?)\s+(\d{1,2})$", parts[0])
        if m_sp and len(parts) >= 2:
            parts = [m_sp.group(1), m_sp.group(2)] + parts[1:]

    sporcu = parts[0] if parts else ""
    if len(parts) >= 2 and re.match(r"^\d{1,2}$", parts[1]):
        yas: Optional[str] = parts[1]
        rem_parts = parts[2:]
    else:
        yas = None
        rem_parts = parts[1:]

    # Kalan parçalardan kulüp adı ve bitiş belirteçlerini (SW kodu, zaman, ara zaman) ayıkla
    club_parts: List[str] = []
    trailing_parts: List[str] = []
    found_trailing = False

    for p in rem_parts:
        sub_tokens = p.split()
        if not found_trailing:
            if sub_tokens and is_trailing_token(sub_tokens[0]):
                found_trailing = True
                trailing_parts.extend(sub_tokens)
            else:
                c_words = []
                for st in sub_tokens:
                    if is_trailing_token(st):
                        found_trailing = True
                        trailing_parts.append(st)
                    elif not found_trailing:
                        c_words.append(st)
                    else:
                        trailing_parts.append(st)
                if c_words:
                    club_parts.append(" ".join(c_words))
        else:
            trailing_parts.extend(sub_tokens)

    kulup = " ".join(club_parts).strip()

    # Sporcu veya Kulüp adının sonuna bitişik yapışmış SW kodu veya derece varsa ayır
    inline_code = ""
    m_touch_sw_sp = re.search(r"([A-Za-zÇĞİÖŞÜçğıöşüÂÎÛâîû\)])(SW\s*[0-9\.,]+)$", sporcu, re.I)
    if m_touch_sw_sp:
        inline_code = m_touch_sw_sp.group(2).strip()
        sporcu = sporcu[:m_touch_sw_sp.start(2)].strip()

    m_touch_sw = re.search(r"([A-Za-zÇĞİÖŞÜçğıöşüÂÎÛâîû\)])(SW\s*[0-9\.,]+)$", kulup, re.I)
    if m_touch_sw:
        inline_code = m_touch_sw.group(2).strip()
        kulup = kulup[:m_touch_sw.start(2)].strip()

    m_touch_time = re.search(r"([A-Za-zÇĞİÖŞÜçğıöşüÂÎÛâîû\)])((?:\d{1,2}:)?\d{2}[\.,]\d{2})$", kulup)
    if m_touch_time:
        t_val = m_touch_time.group(2).strip()
        kulup = kulup[:m_touch_time.start(2)].strip()
        trailing_parts.append(t_val)

    # Trailing belirteçlerini zaman ve SW kodu olarak sınıflandır
    times_found: List[str] = []
    for tp in trailing_parts:
        if re.match(r"^[sS][wW0-9\.,]+$", tp) or re.match(r"^[sS]10\d+$", tp):
            if not inline_code:
                inline_code = tp
        elif re.match(r"^(?:\d{1,2}:)?\d{1,2}[\.,]\d{2}$", tp):
            times_found.append(tp)

    zaman = ""
    if times_found:
        # 0.01 gibi reaksiyon süresi varsa asıl bitiriş derecesini seç
        if len(times_found) > 1 and times_found[0] in ["0.01", "0.00"]:
            zaman = times_found[1]
        else:
            zaman = times_found[0]

    # Bayrak takımı tespiti
    bayrak_mi = any(w in sporcu.lower() for w in ["kulübü", "ortaokul", "koleji", "ilkokulu", "derneği", "lisesi", "takım"]) and (sporcu == kulup or not kulup)
    if bayrak_mi and not kulup:
        kulup = sporcu

    return {
        "is_terk": is_terk,
        "sporcu": clean_tags(sporcu),
        "yas": yas,
        "kulup": clean_tags(kulup),
        "zaman": zaman,
        "inline_code": inline_code,
        "bayrak_mi": bayrak_mi,
    }


def parse_disqualifications_from_file(file_path: str | Path) -> List[DisqualificationMetadata]:
    """Tek bir sonuç dosyasındaki tüm DQ ve yarış terk kayıtlarını ayrıştırır."""
    file_path = Path(file_path)
    fn = file_path.name
    lines = [line.strip() for line in open(file_path, encoding="utf-8")]

    dqs: List[DisqualificationMetadata] = []
    curr_race_no = ""
    curr_page = 1

    idx = 0
    while idx < len(lines):
        l = lines[idx]

        m_p = PAGE_RE.match(l)
        if m_p:
            curr_page = int(m_p.group(1))
            idx += 1
            continue

        m_r = RACE_HEADER_RE.match(l)
        if m_r and idx + 1 < len(lines) and "sonuçlar" in lines[idx + 1].lower():
            curr_race_no = m_r.group(1)
            idx += 1
            continue

        is_disk = bool(re.match(r"^disk\.\s+", l, re.I))
        is_terk = bool(re.match(r"^yar[ıi]ş\s+terk\s+", l, re.I))

        if is_disk or is_terk:
            parsed_first = parse_dq_first_line(l)

            # Gerekçe satırlarını topla
            reason_parts: List[str] = []

            if is_terk:
                # Kullanıcı yönergesi: "gerekçesi yarış terk olsun"
                # Bir sonraki satırda mesafe notu (örn: '50 M', '50m') varsa ekle
                cur = idx + 1
                dist_note = ""
                if cur < len(lines) and re.match(r"^\d{1,3}\s*[mM](?:\.?de)?$", lines[cur]):
                    dist_note = f" ({lines[cur]})"
                    cur += 1
                final_gerekce = "yarış terk" + dist_note
            else:
                cur = idx + 1
                while cur < len(lines):
                    nl = lines[cur]
                    if not nl:
                        cur += 1
                        continue

                    # Sayfa sonu, altbilgi (Splash/Başhakem) veya sonraki yarış/sporcuya denk gelince dur
                    if nl.startswith("===") or "Splash Meet Manager" in nl or "BAŞHAKEM" in nl:
                        break
                    if any(ref in nl for ref in FOOTER_NAMES):
                        break
                    if re.match(r"^(?:\d+\.|td\.|disk\.|ykle\.|ykm\.)\s+", nl) or re.match(r"^yar[ıi]ş\s+terk\s+", nl, re.I):
                        break
                    if RACE_HEADER_RE.match(nl) and cur + 1 < len(lines) and "sonuçlar" in lines[cur + 1].lower():
                        break
                    if "SEANSI" in nl or "ANKARA," in nl or "BİRİNCİLİĞİ" in nl or "MÜSABAKASI" in nl:
                        break
                    if re.match(r"^\d+\s*yaş", nl, re.I) or "yaşları arası" in nl.lower():
                        break
                    if re.match(r"^S[ıi]ra", nl, re.I):
                        break

                    reason_parts.append(nl)
                    cur += 1
                    if len(reason_parts) >= 3:
                        break

                raw_gerekce = " ".join(reason_parts).strip()
                # Boş (Zaman: ) temizliği
                raw_gerekce = re.sub(r"\(Zaman:\s*\)", "", raw_gerekce).strip()
                # Çoklu boşlukları teke indir
                raw_gerekce = re.sub(r"\s+", " ", raw_gerekce)

                # Inline SW kodu (örn: SW7.1) varsa gerekçe ile birleştir
                inline_code = parsed_first.get("inline_code", "")
                if inline_code:
                    if not raw_gerekce:
                        final_gerekce = inline_code
                    elif raw_gerekce.upper().startswith("SW"):
                        final_gerekce = raw_gerekce
                    else:
                        final_gerekce = f"{inline_code} - {raw_gerekce}"
                else:
                    final_gerekce = raw_gerekce if raw_gerekce else "SW belirtilmemiş"

            item = DisqualificationMetadata(
                dosya_adi=fn,
                yaris_no=curr_race_no,
                sayfa_no=curr_page,
                satir_no=idx + 1,
                disk="evet",
                sporcu=parsed_first["sporcu"],
                yas=parsed_first["yas"],
                kulup=parsed_first["kulup"],
                gerekce=final_gerekce,
                zaman=parsed_first["zaman"] if parsed_first["zaman"] else None,
                bayrak_mi=parsed_first["bayrak_mi"],
                ham_satir=l,
            )
            dqs.append(item)
            idx = cur
            continue

        idx += 1

    return dqs


def parse_all_disqualifications(directory: str | Path) -> List[DisqualificationMetadata]:
    """Tüm txt dosyalarındaki DQ kayıtlarını toplar."""
    files = sorted(glob.glob(os.path.join(str(directory), "*.txt")))
    all_dqs: List[DisqualificationMetadata] = []
    for f in files:
        all_dqs.extend(parse_disqualifications_from_file(f))
    return all_dqs


def save_results(results: List[DisqualificationMetadata], out_csv: str, out_json: str) -> None:
    """Sonuçları CSV ve JSON formatında diske kaydeder."""
    os.makedirs(os.path.dirname(out_csv), exist_ok=True)

    # JSON kaydı
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump([r.model_dump() for r in results], f, ensure_ascii=False, indent=2)

    # CSV kaydı (Excel uyumlu UTF-8 BOM ile)
    fieldnames = [
        "Dosya Adı",
        "Yarış No",
        "Sayfa No",
        "Satır No",
        "Disk",
        "Sporcu",
        "Yaş",
        "Kulüp",
        "Zaman",
        "Gerekçe",
        "Bayrak Mı",
        "Ham Satır",
    ]

    with open(out_csv, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in results:
            writer.writerow({
                "Dosya Adı": r.dosya_adi,
                "Yarış No": r.yaris_no,
                "Sayfa No": r.sayfa_no,
                "Satır No": r.satir_no,
                "Disk": r.disk,
                "Sporcu": r.sporcu,
                "Yaş": r.yas or "",
                "Kulüp": r.kulup,
                "Zaman": r.zaman or "",
                "Gerekçe": r.gerekce,
                "Bayrak Mı": "EVET" if r.bayrak_mi else "HAYIR",
                "Ham Satır": r.ham_satir,
            })


if __name__ == "__main__":
    txt_dir = Path("output/txt/ankara")
    dqs = parse_all_disqualifications(txt_dir)
    print(f"Toplam DQ / Terk kaydı: {len(dqs)}")

    indiv = [d for d in dqs if not d.bayrak_mi]
    relay = [d for d in dqs if d.bayrak_mi]
    print(f"  - Bireysel: {len(indiv)}")
    print(f"  - Bayrak / Takım: {len(relay)}")

    out_csv = "output/diskalifiyeler.csv"
    out_json = "output/diskalifiyeler.json"
    save_results(dqs, out_csv, out_json)
    print(f"CSV kaydedildi: {out_csv}")
    print(f"JSON kaydedildi: {out_json}")

