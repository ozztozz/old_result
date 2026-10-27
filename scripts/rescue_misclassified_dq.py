# -*- coding: utf-8 -*-
"""
scripts/rescue_misclassified_dq.py
==================================
Yanlışlıkla DQ / TASNİF_DIŞI yapılan ancak ham satırında gerçek bitiş derecesi (ve puanı/sırası)
mevcut olan sporcuları kurtarır ve GEÇERLİ yapar.
Örnek: ID 470590 (Çağan Yusuf TUNÇ) -> 200m Serbest derecesi 2:21.44, Puan: 375, Sıra: 14.
"""

import os
import re
import sqlite3
from typing import Optional, Dict, Any

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

def extract_correct_swimmer_result(ham: str, mesafe: int) -> Optional[Dict[str, Any]]:
    if not ham:
        return None
        
    # Sıra numarası (satır başında 1-3 haneli sayı)
    sira_match = re.match(r'^\s*(\d{1,3})\s+[A-Za-zÇĞİÖŞÜçğıöşü\(]', ham)
    sira = sira_match.group(1) if sira_match else None
    
    # 1. Dakika:Saniye formatı (örn 2:21.44n375 veya 1:09.13)
    # Bitiş derecesi daima ara zamanlardan önce yer alır!
    times = []
    for m in re.finditer(r'(?<!\d)(\d{1,2}:[0-5]\d\.\d{2})(?:[^\d\s]*(\d{2,4}))?', ham):
        t_str = m.group(1)
        pts = int(m.group(2)) if m.group(2) else None
        sec = time_to_sec(t_str)
        times.append((t_str, sec, pts, m.start()))
        
    # 50m yarışları için sadece saniye.salise (örn 29.87, 45.42)
    if mesafe == 50 or not times:
        for m in re.finditer(r'(?<!\d)([2-9]\d\.\d{2})(?:[^\d\s]*(\d{2,4}))?', ham):
            t_str = m.group(1)
            pts = int(m.group(2)) if m.group(2) else None
            sec = time_to_sec(t_str)
            times.append((t_str, sec, pts, m.start()))

    # Mesafe ile uyumlu olan ilk zamanı bul (bitiş derecesi)
    for t_str, sec, pts, pos in times:
        if is_realistic(sec, mesafe):
            return {
                "derece": t_str,
                "derece_saniye": sec,
                "puan": pts,
                "sira": sira
            }
            
    return None

def rescue_database(db_path: str, dry_run: bool = False):
    if not os.path.exists(db_path):
        return
        
    print(f"\nİncelenen Veritabanı: {db_path}")
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    
    # Uyarı notunda DQ/Terk veya uyumsuz ara zaman yazan kayıtları al
    cur.execute("""
        SELECT id, mesafe, stil, ham_satir, uyari_notu, sira, derece, puan
        FROM yaris_sonuclari
        WHERE zaman_kontrolu = 'TASNİF_DIŞI'
    """)
    rows = cur.fetchall()
    print(f"Toplam incelenen TASNİF_DIŞI kayıt sayısı: {len(rows)}")
    
    rescued = []
    remained_dq = 0
    
    for r in rows:
        rid, mes, stl, ham, uyari, old_sira, old_der, old_puan = r
        
        # Gerçekten dosyada DQ açıklaması olanları atla
        if uyari and ('Diskalifiye/Terk: SW' in uyari or 'Diskalifiye/Terk: DQ' in uyari or 'Diskalifiye/Terk: disk' in uyari):
            remained_dq += 1
            continue
            
        data = extract_correct_swimmer_result(ham, mes)
        if data:
            rescued.append((rid, mes, stl, data, ham))
        else:
            remained_dq += 1
            
    print(f"1. Kurtarılacak (Gerçek Derecesi Bulunan) Kayıt Sayısı: {len(rescued)}")
    print(f"2. Gerçek Diskalifiye / Terk Olarak Kalacak Kayıt Sayısı: {remained_dq}")
    
    # 470590 örneğini kontrol et
    sample_470590 = [x for x in rescued if x[0] == 470590]
    if sample_470590:
        d = sample_470590[0][3]
        print(f"\n[ÖZEL KONTROL] ID 470590: Derece={d['derece']} ({d['derece_saniye']}s), Puan={d['puan']}, Sıra={d['sira']}")
        
    if dry_run:
        print("[DRY RUN] Güncelleme yapılmadı.")
        conn.close()
        return
        
    print("\nVeritabanı güncelleniyor...")
    for rid, mes, stl, d, ham in rescued:
        if d['sira'] and d['puan']:
            cur.execute("""
                UPDATE yaris_sonuclari
                SET derece = ?, derece_saniye = ?, puan = ?, sira = ?, zaman_kontrolu = 'GEÇERLİ', uyari_notu = 'Ham satırdan gerçek bitiş derecesi kurtarıldı'
                WHERE id = ?
            """, (d['derece'], d['derece_saniye'], d['puan'], d['sira'], rid))
        elif d['sira']:
            cur.execute("""
                UPDATE yaris_sonuclari
                SET derece = ?, derece_saniye = ?, sira = ?, zaman_kontrolu = 'GEÇERLİ', uyari_notu = 'Ham satırdan gerçek bitiş derecesi kurtarıldı'
                WHERE id = ?
            """, (d['derece'], d['derece_saniye'], d['sira'], rid))
        else:
            cur.execute("""
                UPDATE yaris_sonuclari
                SET derece = ?, derece_saniye = ?, zaman_kontrolu = 'GEÇERLİ', uyari_notu = 'Ham satırdan gerçek bitiş derecesi kurtarıldı'
                WHERE id = ?
            """, (d['derece'], d['derece_saniye'], rid))
            
    conn.commit()
    conn.close()
    print(f"[BAŞARILI] {len(rescued)} kayıt başarıyla kurtarılıp GEÇERLİ yapıldı!")

if __name__ == "__main__":
    import sys
    dry = "--apply" not in sys.argv
    if dry:
        print("Dry run modu (Uygulamak için: python scripts/rescue_misclassified_dq.py --apply)")
        
    dbs = [
        os.path.join(os.path.dirname(__file__), "..", "database", "yuzme_veritabani.db"),
        os.path.join(os.path.dirname(__file__), "..", "output", "yuzme_veritabani.db"),
    ]
    for db in dbs:
        rescue_database(db, dry_run=dry)
