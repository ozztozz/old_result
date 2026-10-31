import re
import json

with open('gemini_share.html', 'r', encoding='utf-8') as f:
    html = f.read()

# Gemini share pages embed data in JSON-like structures
# Let's search for conversation turns
with open('extracted_conversation.txt', 'w', encoding='utf-8') as out:
    # Look for all script contents
    scripts = re.findall(r'<script[^>]*>(.*?)</script>', html, re.DOTALL)
    for s in scripts:
        if 'c_' in s or 'AF_initDataCallback' in s:
            # find all long strings
            raw_strings = re.findall(r'"((?:[^"\\]|\\.)*)"', s)
            for rs in raw_strings:
                if len(rs) > 40:
                    try:
                        decoded = rs.encode('utf-8').decode('unicode_escape')
                    except Exception:
                        decoded = rs
                    if any(k in decoded.lower() for k in ['yüzme', 'yarış', 'ekran', 'tasarım', 'sporcu', 'sayfa', 'flutt', 'flutter', 'dart', 'baraj', 'kulvar', 'seri', 'tyf', 'sonuç']):
                        out.write(decoded + '\n----------------------------------------\n')

print("Extraction completed.")

