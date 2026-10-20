#!/usr/bin/env python3
import sys
sys.path.insert(0, 'src')
from tyf_live_worker import fetch_url, parse_start_list_pdf, parse_result_list_pdf, post_to_django

base = 'https://canli.tyf.gov.tr/istanbul/cs-1005380/'
url_start = base + 'canli/StartList_1.pdf'
url_res = base + 'canli/ResultList_1.pdf'
api_url = 'http://127.0.0.1:8000/api/canli-aktar/'

print('1. Downloading and Parsing StartList_1 (Text PDF)...')
start_bytes = fetch_url(url_start)
start_payload = parse_start_list_pdf(start_bytes)
start_payload['dosya_adi'] = 'canli/StartList_1.pdf'
print(f"   Start list extracted: {len(start_payload['kayitlar'])} swimmers")
post_to_django(api_url, start_payload)

print('\n2. Downloading and OCR Scanning ResultList_1 (Scanned Image PDF)...')
res_bytes = fetch_url(url_res)
res_payload = parse_result_list_pdf(res_bytes, start_payload['kayitlar'])
res_payload['dosya_adi'] = 'canli/ResultList_1.pdf'
res_payload['musabaka_adi'] = start_payload.get('musabaka_adi')
res_payload['yaris_no'] = '1'
res_payload['sehir'] = start_payload.get('sehir')
res_payload['cinsiyet'] = start_payload.get('cinsiyet')
res_payload['mesafe'] = start_payload.get('mesafe')
res_payload['stil'] = start_payload.get('stil')
print(f"   OCR Result list extracted and matched: {len(res_payload['kayitlar'])} swimmers")
post_to_django(api_url, res_payload)

