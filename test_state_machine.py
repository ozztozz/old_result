import glob
import os
import re

files = sorted(glob.glob("output/txt/ankara/*.txt"))

PAGE_RE = re.compile(r"^===\s*SAYFA\s*(\d+)\s*/\s*(\d+)\s*===")
SPLASH_RE = re.compile(r"Splash Meet Manager", re.I)
BASHAKEM_RE = re.compile(r"\bBAŞHAKEM\b", re.I)

total_pages = 0
header_lines_identified = 0
footer_lines_identified = 0

for f in files:
    fn = os.path.basename(f)
    if fn.replace(".txt", "").isdigit():
        continue

    lines = [l.strip() for l in open(f, encoding="utf-8")]
    i = 0
    while i < len(lines):
        line = lines[i]
        m_page = PAGE_RE.match(line)
        if m_page:
            p_num = int(m_page.group(1))
            total_pages += 1
            i += 1
            # Sayfa Başlığı: İlk 2 anlamlı satır (Müsabaka adı ve Şehir/Tarih)
            h_count = 0
            while i < len(lines) and h_count < 2:
                if lines[i]:
                    header_lines_identified += 1
                    h_count += 1
                i += 1
            continue

        # Hakem ve Altbilgi Kontrolü
        if BASHAKEM_RE.search(line):
            footer_lines_identified += 1
            # Önceki satır hakem ismi mi?
            if i > 0 and lines[i - 1]:
                prev = lines[i - 1]
                if re.match(r"^[A-ZÇĞİÖŞÜ\s]+$", prev) and not any(c.isdigit() for c in prev):
                    footer_lines_identified += 1
            i += 1
            continue

        if SPLASH_RE.search(line):
            footer_lines_identified += 1
            i += 1
            continue

        i += 1

print(f"Toplam Sayfa          : {total_pages:,}")
print(f"Tanınan Başlık Satırı : {header_lines_identified:,}")
print(f"Tanınan Altbilgi Satırı: {footer_lines_identified:,}")
print(f"Toplam Yapısal Satır  : {header_lines_identified + footer_lines_identified:,}")

