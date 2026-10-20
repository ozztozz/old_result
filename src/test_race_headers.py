import glob
import re

STROKE_MAP = {
    'serbest': 'Serbest', 'freestyle': 'Serbest',
    'sırt': 'Sırtüstü', 'backstroke': 'Sırtüstü', 'sirt': 'Sırtüstü',
    'kurbağa': 'Kurbağalama', 'breaststroke': 'Kurbağalama', 'kurbaga': 'Kurbağalama',
    'kelebek': 'Kelebek', 'butterfly': 'Kelebek',
    'karışık': 'Karışık', 'medley': 'Karışık', 'karisik': 'Karışık'
}

def parse_race_header(line: str):
    m_no = re.match(r'^\s*(?:Yar[ıiIİ][şsSŞ]|Event)\s+(\d+)\b(.*)$', line, re.I)
    if not m_no:
        return None
    r_no = m_no.group(1)
    rest = m_no.group(2).strip()

    # Cinsiyet
    cinsiyet = ''
    if re.search(r'\b(?:kızlar|bayanlar|kadınlar|women|girls|kız|bayan|kadın)\b', rest, re.I):
        cinsiyet = 'Kızlar'
    elif re.search(r'\b(?:erkekler|men|boys|erkek)\b', rest, re.I):
        cinsiyet = 'Erkekler'
    elif re.search(r'\b(?:karma|mixed)\b', rest, re.I):
        cinsiyet = 'Karma'

    # Mesafe
    m_dist = re.search(r'\b(\d+\s*x\s*\d+m?|\d+m)\b', rest, re.I)
    mesafe = m_dist.group(1).lower().replace(' ', '') if m_dist else ''
    if mesafe and not mesafe.endswith('m'):
        mesafe += 'm'

    # Stil
    stil = ''
    rest_lower = rest.lower()
    for kw, canon_stil in STROKE_MAP.items():
        if kw in rest_lower:
            stil = canon_stil
            break

    # Yaş grubu
    yas_grubu = ''
    m_age = re.search(r'\b(\d+\s*-\s*\d+\s*yaş(?:ları\s*arası)?|\d+\s*yaş(?:\s*ve\s*büyükler)?|\d+\s*\+\s*yaş|açık|open)\b', rest, re.I)
    if m_age:
        yas_grubu = m_age.group(1).strip()
    elif re.search(r'\b\d+\s*yaş\b', rest, re.I):
        yas_grubu = re.search(r'\b\d+\s*yaş\b', rest, re.I).group(0)

    return {
        'yaris_no': r_no,
        'cinsiyet': cinsiyet,
        'mesafe': mesafe,
        'stil': stil,
        'yas_grubu': yas_grubu,
        'ham_baslik': line.strip()
    }

files = glob.glob('output/txt/ankara/*.txt')[:3] + glob.glob('output/txt/tyf_arsiv/*.txt')[:3]
count = 0
for f in files:
    for l in open(f, encoding='utf-8', errors='ignore'):
        parsed = parse_race_header(l)
        if parsed:
            print(f"{parsed['yaris_no']:2s} | {parsed['cinsiyet']:8s} | {parsed['mesafe']:7s} | {parsed['stil']:12s} | {parsed['yas_grubu']:22s} | {parsed['ham_baslik'][:35]}")
            count += 1
            if count >= 15:
                break
    if count >= 15:
        break

