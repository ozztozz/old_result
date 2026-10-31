with open('gemini_share.html', 'r', encoding='utf-8') as f:
    html = f.read()

import re
matches = re.findall(r'window\.WIZ_global_data\s*=\s*(\{.*?\});', html)
if matches:
    print("Found WIZ_global_data!")
    with open('wiz_data.json', 'w', encoding='utf-8') as out:
        out.write(matches[0])
else:
    print("No WIZ_global_data found.")

