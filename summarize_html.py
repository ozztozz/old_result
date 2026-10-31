import re
from bs4 import BeautifulSoup

with open('gemini_share.html', 'r', encoding='utf-8') as f:
    html = f.read()

soup = BeautifulSoup(html, 'html.parser')

with open('html_summary.txt', 'w', encoding='utf-8') as out:
    out.write(f"Title: {soup.title}\n")
    # write all text content
    text = soup.get_text(separator='\n')
    lines = [line.strip() for line in text.splitlines() if len(line.strip()) > 10]
    out.write(f"Total lines > 10 chars: {len(lines)}\n\n")
    for l in lines[:200]:
        out.write(l + '\n')

print("Summary written.")

