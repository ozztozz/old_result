import urllib.request
import re

url = 'https://gemini.google.com/share/31039f0c9189?social_preview=true'
headers = {
    'User-Agent': 'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)'
}
req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req) as resp:
        content = resp.read().decode('utf-8', errors='ignore')
        with open('social_preview.html', 'w', encoding='utf-8') as f:
            f.write(content)
        print("Length:", len(content))
        # Find all meta tags
        for m in re.findall(r'<meta[^>]*>', content):
            if any(k in m for k in ['title', 'description', 'og:', 'twitter:']):
                print(m)
except Exception as e:
    print("Error:", e)

