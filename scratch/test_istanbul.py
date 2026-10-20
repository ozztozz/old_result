#!/usr/bin/env python3
import urllib.request
import ssl
import re
import fitz

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

url = 'https://canli.tyf.gov.tr/istanbul/cs-1005380/'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})

with urllib.request.urlopen(req, context=ctx) as r:
    html = r.read().decode('utf-8', errors='ignore')

title = re.search(r'<title>(.*?)</title>', html, re.I)
print('Title:', title.group(1) if title else 'No title')

pdf_links = re.findall(r'href=[\'"]([^\'"]+\.pdf)[\'"]', html, re.I)
print(f'Total PDF links: {len(pdf_links)}')

start_lists = [p for p in pdf_links if 'startlist' in p.lower()]
result_lists = [p for p in pdf_links if 'resultlist' in p.lower()]

print(f'Start lists count: {len(start_lists)}')
print(f'Result lists count: {len(result_lists)}')

for r in result_lists[:5]:
    print('Sample Result PDF:', r)

