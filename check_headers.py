import glob
import os
import re

files = sorted(glob.glob("output/txt/ankara/*.txt"))
page_re = re.compile(r"^===\s*SAYFA\s*(\d+)\s*/\s*(\d+)\s*===")

total_pages = 0
standard_pages = 0
variations = []

for f in files:
    fn = os.path.basename(f)
    if fn.replace(".txt", "").isdigit():
        continue
    lines = [l.strip() for l in open(f, encoding="utf-8")]
    for i, l in enumerate(lines):
        m = page_re.match(l)
        if m:
            total_pages += 1
            p_num = int(m.group(1))
            total_p = int(m.group(2))
            # Next 3 non-empty lines
            nxt = [lines[k] for k in range(i + 1, min(i + 15, len(lines))) if lines[k]][:4]
            # Standard: Line 1 = Meet Title, Line 2 = Location + Date
            if len(nxt) >= 2 and ("," in nxt[1] or any(c.isdigit() for c in nxt[1])):
                standard_pages += 1
            else:
                variations.append((fn, p_num, nxt))

print(f"Toplam Sayfa: {total_pages}")
print(f"Standart Başlık (Yarış Adı + Şehir/Tarih): {standard_pages}")
print(f"Farklı Başlık Sayısı: {len(variations)}")
if variations:
    print("\nÖrnek Farklı Başlıklar:")
    for v in variations[:8]:
        print(f"  {v[0]} (Sayfa {v[1]}): {v[2]}")

