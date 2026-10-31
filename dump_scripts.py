import re

with open('gemini_share.html', 'r', encoding='utf-8') as f:
    html = f.read()

# Let's see what scripts or variables exist
scripts = re.findall(r'<script[^>]*>(.*?)</script>', html, re.DOTALL)
print(f"Total script tags: {len(scripts)}")

with open('scripts_dump.txt', 'w', encoding='utf-8') as out:
    for idx, s in enumerate(scripts):
        out.write(f"=== SCRIPT {idx} (len {len(s)}) ===\n")
        out.write(s[:500] + "\n...\n" + s[-300:] + "\n\n")

# Check for AF_initDataCallback
for idx, s in enumerate(scripts):
    if 'AF_initDataCallback' in s:
        with open(f'af_script_{idx}.txt', 'w', encoding='utf-8') as f_af:
            f_af.write(s)
        print(f"Wrote af_script_{idx}.txt (len {len(s)})")

if 'HatpsaliEnNz' in html:
    print("Found token HatpsaliEnNz in html!")
else:
    print("Token HatpsaliEnNz NOT in html!")

