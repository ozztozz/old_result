import os
import sys
sys.path.append(os.path.abspath('.'))

import sqlite3
from google_cloud_runner.main import check_file_already_processed

conn = sqlite3.connect('output/yuzme_veritabani.db')
c = conn.cursor()
c.execute("SELECT content_hash, etag FROM canli_yaris_dosyalari WHERE dosya_adi='ResultList_1.pdf'")
row = c.fetchone()
print("DB hash & etag:", row)

meta = {"content_hash": row[0], "etag": row[1]}
django_url = "http://127.0.0.1:8000/api/canli-aktar/"
is_done_and_unchanged = check_file_already_processed(django_url, 4, "ResultList_1.pdf", meta)
print("Check ResultList_1.pdf with identical hash (should be True):", is_done_and_unchanged)

meta_changed = {"content_hash": "different-hash", "etag": "different-etag"}
is_done_and_unchanged_2 = check_file_already_processed(django_url, 4, "ResultList_1.pdf", meta_changed)
print("Check ResultList_1.pdf with different hash (should be False):", is_done_and_unchanged_2)
