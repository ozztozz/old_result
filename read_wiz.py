import json
with open('wiz_data.json', 'r', encoding='utf-8') as f:
    text = f.read()

import re
keys = re.findall(r'"([^"]+)":', text)
print("Keys count:", len(keys))
for k in keys[:30]:
    print("Key:", k)

