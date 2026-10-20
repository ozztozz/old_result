#!/usr/bin/env python3
import urllib.request
import ssl
import io
import fitz
import pytesseract
import re
import difflib
from PIL import Image

pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

import sys
sys.path.insert(0, 'src')
from tyf_live_worker import parse_start_list_pdf, normalize_tr

url_start = 'https://canli.tyf.gov.tr/istanbul/cs-1005380/canli/StartList_1.pdf'
start_payload = parse_start_list_pdf(urllib.request.urlopen(url_start, context=ctx).read())
start_entries = start_payload['kayitlar']
print(f"Start list entries: {len(start_entries)}")

candidates_map = {e['sporcu']: e for e in start_entries}
candidates = list(candidates_map.keys())

def match_ocr_line(line_prefix, candidates):
    p_norm = normalize_tr(line_prefix)
    p_norm = re.sub(r'^\d+[\.\s]+', '', p_norm).strip()
    
    # 1. Exact startswith
    for c in candidates:
        c_norm = normalize_tr(c)
        if p_norm.startswith(c_norm):
            return c
            
    # 2. Fuzzy match across first N words
    words = p_norm.split()
    best_c, best_score = None, 0.0
    for c in candidates:
        c_norm = normalize_tr(c)
        c_len = len(c_norm.split())
        line_part = ' '.join(words[:c_len])
        score = difflib.SequenceMatcher(None, line_part, c_norm).ratio()
        if score > best_score:
            best_score = score
            best_c = c
            
    if best_score >= 0.70:
        return best_c
    return None

url_res = 'https://canli.tyf.gov.tr/istanbul/cs-1005380/canli/ResultList_1.pdf'
doc = fitz.open(stream=urllib.request.urlopen(url_res, context=ctx).read(), filetype='pdf')
print(f"Scanned Result PDF pages: {len(doc)}")

ocr_swimmers = []
for pno, page in enumerate(doc):
    pix = page.get_pixmap(dpi=300)
    img = Image.open(io.BytesIO(pix.tobytes('png')))
    text = pytesseract.image_to_string(img, lang='tur', config='--psm 6')
    for line in text.splitlines():
        line = line.strip()
        m_time = re.search(r'((?:\d+:)?\d{2}\.\d{2})(?:\s+(\d+))?$', line)
        if m_time:
            time_val = m_time.group(1)
            pts_val = m_time.group(2)
            prefix = line[:m_time.start()].strip()
            
            m_rank = re.match(r'^(\d+)[\.\s]+', prefix)
            rank_val = m_rank.group(1) if m_rank else None
            
            matched_name = match_ocr_line(prefix, candidates)
            if matched_name:
                st = candidates_map[matched_name]
                ocr_swimmers.append({
                    'rank': rank_val,
                    'sporcu': matched_name,
                    'kulup': st.get('kulup'),
                    'time': time_val,
                    'points': pts_val,
                    'seri': st.get('seri'),
                    'kulvar': st.get('kulvar'),
                    'giris_derecesi': st.get('giris_derecesi')
                })

print(f"\nToplam Start Listesi ile Eşleşen OCR Sporcusu: {len(ocr_swimmers)}")
for s in ocr_swimmers[:25]:
    print(f"  Sıra {str(s['rank']):>3}: {s['sporcu']:30} ({s['kulup']}) -> Derece: {s['time']} (Giriş: {s['giris_derecesi']}, K: {s['kulvar']})")

