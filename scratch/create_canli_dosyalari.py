import sqlite3

conn = sqlite3.connect('output/yuzme_veritabani.db')
cur = conn.cursor()

# 1. Create canli_yaris_dosyalari table
cur.execute('''
CREATE TABLE IF NOT EXISTS canli_yaris_dosyalari (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id INTEGER REFERENCES events(id),
    canli_yaris_id INTEGER REFERENCES canli_yarislar(id),
    dosya_adi TEXT NOT NULL,
    dosya_url TEXT,
    dosya_turu TEXT,
    yaris_no TEXT,
    mesafe INTEGER,
    stil TEXT,
    cinsiyet TEXT,
    yas_grubu TEXT,
    etag TEXT,
    last_modified TEXT,
    content_hash TEXT,
    dosya_boyutu INTEGER,
    durum TEXT DEFAULT 'BEKLIYOR',
    kayit_sayisi INTEGER DEFAULT 0,
    hata_mesaji TEXT,
    son_kontrol_tarihi DATETIME,
    son_islem_tarihi DATETIME,
    olusturulma_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP,
    guncellenme_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP
);
''')

# Create indexes
cur.execute('CREATE INDEX IF NOT EXISTS idx_canli_dosya_event ON canli_yaris_dosyalari(event_id);')
cur.execute('CREATE INDEX IF NOT EXISTS idx_canli_dosya_adi ON canli_yaris_dosyalari(dosya_adi);')
cur.execute('CREATE INDEX IF NOT EXISTS idx_canli_dosya_yaris_no ON canli_yaris_dosyalari(event_id, yaris_no);')
cur.execute('CREATE INDEX IF NOT EXISTS idx_canli_dosya_hash ON canli_yaris_dosyalari(content_hash);')

# 2. Add canli_dosya_id to yaris_sonuclari if not exists
cur.execute('PRAGMA table_info(yaris_sonuclari);')
cols = [r[1] for r in cur.fetchall()]
if 'canli_dosya_id' not in cols:
    cur.execute('ALTER TABLE yaris_sonuclari ADD COLUMN canli_dosya_id INTEGER REFERENCES canli_yaris_dosyalari(id);')
    cur.execute('CREATE INDEX IF NOT EXISTS idx_sonuclar_canli_dosya ON yaris_sonuclari(canli_dosya_id);')
    print("Column canli_dosya_id added to yaris_sonuclari.")
else:
    print("Column canli_dosya_id already exists in yaris_sonuclari.")

conn.commit()
print("canli_yaris_dosyalari table and indexes created successfully.")
conn.close()

