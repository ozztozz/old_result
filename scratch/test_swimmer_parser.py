import glob
import re
import os
from pathlib import Path
from typing import Optional, Dict, Any, List

files = sorted(glob.glob("output/txt/ankara/*.txt"))

PAGE_RE = re.compile(r"^===\s*SAYFA\s*(\d+)\s*/\s*(\d+)\s*===", re.I)

RACE_HEADER_RE = re.compile(
    r"^\s*Yar[ıiIİ][şsSŞ]\s+(\d+)\s*(?:,\s*|(?:\s{2,}|\t+))"
    r"([A-ZÇĞİÖŞÜa-zçğıöşü\s,]+?)(?:,\s*|(?:\s{2,}|\t+))"
    r"(\d+\s*x\s*\d+m|\d+m)\s+"
    r"([A-Za-zÇĞİÖŞÜçğıöşü\s]+?)(?:(?:,\s*|(?:\s{2,}|\t+))([0-9\s\-+a-zçğıöşüA-ZÇĞİÖŞÜ]+))?$",
    re.I,
)

TAG_RE = re.compile(r"\((?:Tk|Td|Fd|tk|td|fd|TK|TD|FD)\)\s*")

def clean_tags(text: str) -> str:
    """Metindeki (Tk), (Td), (Fd) etiketlerini temizler."""
    t = TAG_RE.sub("", text)
    return re.sub(r"\s+", " ", t).strip()

TIME_RE = re.compile(r"^(?:\d{1,2}:)?\d{2}\.\d{2}$")

def parse_swimmer_row(raw_line: str, prev_rank: str = "") -> Optional[Dict[str, Any]]:
    """Tek bir yüzücü satırını deterministik olarak ayrıştırır."""
    l_str = raw_line.strip()
    if not l_str:
        return None

    # Disk veya terk satırları bireysel sonuç değil (ayrı katmanda parse edildi)
    if re.match(r"^disk\.\s+", l_str, re.I) or re.match(r"^yar[ıi]ş\s+terk\s+", l_str, re.I):
        return None

    # Ara zaman satırlarını atla (50m:  34.08 ...)
    if re.match(r"^\d{2,4}m:\s+", l_str, re.I):
        return None

    # Sıralı satır mı (1., 2., 10., td. vb.)?
    m_rank = re.match(r"^(?P<sira>\d+|td|ykle|ykm)\.\s+(?P<rest>.+)$", l_str, re.I)
    if m_rank:
        sira = m_rank.group("sira")
        content = m_rank.group("rest").strip()
        is_tied = False
    else:
        # Sıra numarası olmayan (beraberlik / tied) satır mı?
        sira = prev_rank
        content = l_str
        is_tied = True

    # İsim ve 2 haneli yaşın bitiştiği durumlar (örn: SOLAKOĞLU14 -> SOLAKOĞLU  14)
    m_concat = re.match(r"^([A-ZÇĞİÖŞÜa-zçğıöşü\s\.\(\)\'\-]+?[A-Za-zÇĞİÖŞÜçğıöşüÂÎÛâîû\.])(\d{1,2})\s+(.+)$", content)
    if m_concat:
        content = f"{m_concat.group(1)}  {m_concat.group(2)}  {m_concat.group(3)}"

    parts = [p.strip() for p in re.split(r"\s{2,}|\t+", content) if p.strip()]
    if not parts:
        return None

    # parts[0] içinde isim + tek boşluk + yaş kalmışsa
    m_sp = re.match(r"^(.+?)\s+(\d{1,2})$", parts[0])
    if m_sp and len(parts) >= 2 and not is_tied:
        parts = [m_sp.group(1), m_sp.group(2)] + parts[1:]

    # Geçerli bir yüzücü satırı en az: İsim, Yaş, Kulüp, Zaman içermelidir (en az 4 parça)
    # Veya Yaş kolonu olmayan yarışlarda: İsim, Kulüp, Zaman (en az 3 parça)
    sporcu = ""
    yas = ""
    kulup = ""
    derece = ""
    puan = ""

    if len(parts) >= 3 and re.match(r"^\d{1,2}$", parts[1]):
        sporcu = clean_tags(parts[0])
        yas = parts[1]
        rem = parts[2:]
    elif len(parts) >= 2 and not re.match(r"^\d{1,2}$", parts[1]):
        # Yaş kolonu olmayan okul yarışları
        sporcu = clean_tags(parts[0])
        yas = ""
        rem = parts[1:]
    else:
        return None

    if not rem:
        return None

    # rem içinde derece (zaman) ve puanı bul
    # Örnek rem: ['Orka Swim Team', '5:10.26', '436']
    # Örnek rem: ['Aren Atletıcs Spor Kulübü', '1:31.57', '222', '42.80', '48.77']
    # Örnek rem: ['Orka Swim Team', '1:15.00']
    time_idx = -1
    for i, tok in enumerate(rem):
        # Time format (33.82, 1:15.00, 10:43.70)
        if TIME_RE.match(tok):
            time_idx = i
            break

    if time_idx == -1:
        # Geçerli bir bitiriş derecesi yoksa bu bir yüzücü sonuç satırı değildir
        return None

    kulup = clean_tags(" ".join(rem[:time_idx]))
    derece = rem[time_idx]

    after_time = rem[time_idx + 1:]
    if after_time:
        # İlk belirteç tam sayı ise FINA/AQUA puanıdır
        if re.match(r"^\d+$", after_time[0]):
            puan = after_time[0]

    return {
        "sira": sira,
        "sporcu": sporcu,
        "yas": yas,
        "kulup": kulup,
        "derece": derece,
        "puan": puan,
        "is_tied": is_tied,
        "ham_satir": l_str,
    }

# Test cases
test_cases = [
    "1.  Zeynep Duru YARDIMCI           14   Orka Swim Team            5:10.26  436",
    "10.  Özüm ÖZBEY            14   Orka Swim Team            1:15.00  327",
    "10.  Özüm ÖZBEY            14   Orka Swim Team            1:15.00",
    "Ilke Berk AĞBUĞA            07   Aykon Spor Kulübü            58.42  517",
    "td.  (Td) Alisa Dora AÇIK            12   Ted Ankara Koleji Vakfı Özel Ortaokulu  1:27.36  284",
    "1.  (Fd) Ali Mete KOÇAK       11   Atatürk Ortaokulu            1:09.99  400         33.53    36.46",
    "2.  Yağız Ali FIRATLI          11   (Tk) Ted Ankara Koleji Vakfı Özel Ortaokulu  1:13.14  351         34.81    38.33",
    "1.  Ece DEMİR            15   Aren Atletıcs Spor Kulübü        1:31.57  222         42.80    48.77",
]

for tc in test_cases:
    res = parse_swimmer_row(tc, prev_rank="25")
    print(f"[{res['sira']}] {res['sporcu']} | Yaş: {res['yas']} | Kulüp: {res['kulup']} | Derece: {res['derece']} | Puan: {res['puan']}")

