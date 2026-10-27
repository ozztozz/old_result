# -*- coding: utf-8 -*-
"""
scripts/rescue_split_time_rows.py
=================================
İlk parser tarafından ara zamanı (split time) yanlışlıkla derece olarak alınan
ancak ham satırında gerçek bitiş derecesi bulunan (örn ID 470590 Çağan Yusuf TUNÇ 2:21.44)
kayıtları kurtarıp GEÇERLİ yapar.
"""

import os
import re
import sqlite3
from typing import Optional

def time_to_sec(t_str: Optional[str]) -> Optional[float]:
    if not t_str:
        return None
    s = str(t_str).strip()
    m_min = re.match(r'^(\d+):(\d{2}(?:\.\d+)?)$', s)
    if m_min:
        return round(int(m_min.group(1)) * 60 + float(m_min.group(2)), 2)
    m_sec = re.match(r'^(\d+(?:\.\d+)?)$', s)
    if m_sec:
        return round(float(m_sec.group(1)), 2)
    return None

def is_realistic(sec: Optional[float], mesafe: Optional[int]) -> bool:
    if not sec or not mesafe:
        return True
    if mesafe == 50:
        return 20.0 <= sec <= 120.0
    elif mesafe == 100:
        return 44.0 <= sec <= 240.0
    elif mesafe == 200:
        return 95.0 <= sec <= 480.0
    elif mesafe == 400:
        return 210.0 <= sec <= 900.0
    elif mesafe == 800:
        return 450.0 <= sec <= 1800.0
    elif mesafe == 1500:
        return 850.0 <= sec <= 3600.0
    return True

def apply_rescue(db_path: str, dry_run: bool = False):
    if not os.path.exists(db_path):
        return
        
    print(f"\nİşlenen Veritabanı: {db_path}")
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    
    cur.execute("""
        SELECT id, mesafe, stil, ham_satir, uyari_notu
        FROM yaris_sonuclari
        WHERE uyari_notu LIKE '%uyumsuz ara zaman%'
    """)
    rows = cur.fetchall()
    print(f"Toplam incelenen 'uyumsuz ara zaman' kaydı: {len(rows)}")
    
    rescued_updates = []
    
    for r in rows:
        rid, mes, stl, ham, uyari = r
        
        # Sıra numarası (satır başında)
        sira_match = re.match(r'^\s*(\d{1,3})\s+[A-Za-zÇĞİÖŞÜçğıöşü\(]', ham or '')
        sira = sira_match.group(1) if sira_match else None
        
        found = None
        
        # 1. Dakika:Saniye arayışı (200m, 400m, 800m, 1500m ve 100m)
        for m in re.finditer(r'(?<!\d)(\d{1,2}:[0-5]\d\.\d{2})(?:[^\d\s]*(\d{2,4}))?', ham or ''):
            t_str = m.group(1)
            pts = int(m.group(2)) if m.group(2) else None
            sec = time_to_sec(t_str)
            if is_realistic(sec, mes):
                found = (t_str, sec, pts, sira)
                break
                
        # 2. 50m için Saniye arayışı
        if not found and mes == 50:
            for m in re.finditer(r'(?<!\d)([2-9]\d\.\d{2})(?:[^\d\s]*(\d{2,4}))?', ham or ''):
                t_str = m.group(1)
                pts = int(m.group(2)) if m.group(2) else None
                sec = time_to_sec(t_str)
                if is_realistic(sec, mes):
                    found = (t_str, sec, pts, sira)
                    break
                    
        if found:
            t_str, sec, pts, sr = found
            rescued_updates.append((t_str, sec, pts, sr, rid))
            
    print(f"Gerçek bitiş derecesi kurtarılan: {len(rescued_updates)} adet")
    
    # 470590 kontrolü
    for u in rescued_updates:
        if u[4] == 470590:
            print(f"[470590 TEYİT] Derece={u[0]} ({u[1]}s), Puan={u[2]}, Sıra={u[3]}")
            
    if dry_run:
        print("[DRY RUN] Güncelleme yapılmadı.")
        conn.close()
        return
        
    print("Veritabanı güncelleniyor...")
    for t_str, sec, pts, sr, rid in rescued_updates:
        if sr and pts:
            cur.execute("""
                UPDATE yaris_sonuclari
                SET derece = ?, derece_saniye = ?, puan = ?, sira = ?, zaman_kontrolu = 'GEÇERLİ', uyari_notu = NULL
                WHERE id = ?
            """, (t_str, sec, pts, sr, rid))
        elif sr:
            cur.execute("""
                UPDATE yaris_sonuclari
                SET derece = ?, derece_saniye = ?, sira = ?, zaman_kontrolu = 'GEÇERLİ', uyari_notu = NULL
                WHERE id = ?
            """, (t_str, sec, sr, rid))
        else:
            cur.execute("""
                UPDATE yaris_sonuclari
                SET derece = ?, derece_saniye = ?, zaman_kontrolu = 'GEÇERLİ', uyari_notu = NULL
                WHERE id = ?
            """, (t_str, sec, rid))
            
    conn.commit()
    conn.close()
    print(f"[BAŞARILI] {len(rescued_updates)} kayıt veritabanında güncellendi!")

if __name__ == "__main__":
    import sys
    dry = "--apply" not in sys.argv
    if dry:
        print("Dry run modunda çalıştırılıyor (Uygulamak için: python scripts/rescue_split_time_rows.py --apply)")
    
    dbs = [
        os.path.join(os.path.dirname(__file__), "..", "database", "yuzme_veritabani.db"),
        os.path.join(os.path.dirname(__file__), "..", "output", "yuzme_veritabani.db"),
    ]
    for db in dbs:
        apply_rescue(db, dry_run=dry)

