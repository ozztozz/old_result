import re

with open('gemini_share.html', 'r', encoding='utf-8') as f:
    html = f.read()

# Let's search for batchexecute or rpc ids or share endpoints
endpoints = re.findall(r'https?://[^\s"\'<>]+', html)
gemini_endpoints = [e for e in set(endpoints) if 'google' in e and ('bard' in e or 'gemini' in e or 'batchexecute' in e or 'share' in e or 'rpc' in e)]
for e in gemini_endpoints:
    print(e)

