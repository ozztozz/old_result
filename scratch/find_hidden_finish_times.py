import sqlite3
import re

db_path = r'c:\Users\OZDEN\Desktop\old_result\database\yuzme_veritabani.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

def time_to_sec(t_str):
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

def is_realistic(sec, mesafe):
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

# Az önce değiştirdiğimiz ve uyarı notunda 'Mesafe (...) ile uyumsuz ara zaman' yazan kayıtları çekelim
cur.execute("""
    SELECT id, dosya_adi, mesafe, stil, ham_satir, uyari_notu
    FROM yaris_sonuclari
    WHERE uyari_notu LIKE '%uyumsuz ara zaman%' OR uyari_notu LIKE '%Diskalifiye/Terk%'
""")
rows = cur.fetchall()
print(f"Toplam incelenecek kayıt: {len(rows)}")

actually_has_valid_finish_time = []
true_dq = []

for r in rows:
    rid, dosya, mes, stl, ham, uyari = r
    
    # Gerçekten diskalifiye mi?
    is_true_dq = 'Diskalifiye/Terk: SW' in uyari or 'Diskalifiye/Terk: DQ' in uyari or 'Diskalifiye/Terk: disk' in uyari
    
    # Ham satırda herhangi bir yerde [dakika:]saniye.salise var mı?
    # Örnek: '2:21.44n375' -> '2:21.44'
    all_time_patterns = re.findall(r'(?<!\d)(\d{1,2}:[0-5]\d\.\d{2})(?:[a-zA-ZçğıöşüÇĞİÖŞÜ]+(\d{2,4}))?', ham or '')
    
    found_finish = None
    found_pts = None
    
    for t_str, pts in all_time_patterns:
        t_sec = time_to_sec(t_str)
        if is_realistic(t_sec, mes):
            found_finish = t_str
            found_pts = int(pts) if pts else None
            break
            
    # Eğer dakika:saniye yoksa ve 50m ise normal SS.ms var mı?
    if not found_finish and mes == 50:
        sec_patterns = re.findall(r'(?<!\d)([2-9]\d\.\d{2})(?:[a-zA-ZçğıöşüÇĞİÖŞÜ]+(\d{2,4}))?', ham or '')
        for t_str, pts in sec_patterns:
            t_sec = time_to_sec(t_str)
            if is_realistic(t_sec, mes):
                found_finish = t_str
                found_pts = int(pts) if pts else None
                break

    if found_finish and not is_true_dq:
        # Satır başındaki sıra numarasını da al
        m_sira = re.match(r'^\s*(\d{1,3})\b', ham or '')
        sira_num = m_sira.group(1) if m_sira else None
        actually_has_valid_finish_time.append((rid, mes, stl, found_finish, found_pts, sira_num, ham))
    else:
        true_dq.append((rid, mes, ham, uyari))

print(f"\n1. Ham satırında GERÇEK BİTİŞ DERECESİ gizlenmiş olanlar: {len(actually_has_valid_finish_time)} adet!")
print(f"2. Gerçekten Diskalifiye / Terk olanlar: {len(true_dq)} adet")

print("\n--- Örnek Kurtarılacak Gerçek Dereceler (İlk 15) ---")
for x in actually_has_valid_finish_time[:15]:
    print(f"ID {x[0]} ({x[1]}m {x[2]}): Sıra={x[5]} | Gerçek Derece={x[3]} | Puan={x[4]}")
    print(f"   Ham: '{x[6]}'")

