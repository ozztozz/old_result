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

# Sadece bizim 'uyumsuz ara zaman' diyerek DQ yaptığımız 306 kaydı çekiyoruz
cur.execute("""
    SELECT id, mesafe, stil, ham_satir, uyari_notu
    FROM yaris_sonuclari
    WHERE uyari_notu LIKE '%uyumsuz ara zaman%'
""")
rows = cur.fetchall()
print(f"Toplam incelenecek 'uyumsuz ara zaman' kaydı: {len(rows)}")

rescued_updates = []
still_invalid = []

for r in rows:
    rid, mes, stl, ham, uyari = r
    
    # Satır başındaki sıra numarası
    sira_match = re.match(r'^\s*(\d{1,3})\s+[A-Za-zÇĞİÖŞÜçğıöşü\(]', ham or '')
    sira = sira_match.group(1) if sira_match else None
    
    # Ham satırdaki tüm potansiyel dereceleri bul
    # Örn: '2:21.44n375' -> t_str='2:21.44', pts=375
    # Örn: '5:03.54 1466bı' -> t_str='5:03.54'
    found = None
    
    # 1. Dakika:Saniye arayışı (200m, 400m, 800m, 1500m ve 100m için)
    for m in re.finditer(r'(?<!\d)(\d{1,2}:[0-5]\d\.\d{2})(?:[^\d\s]*(\d{2,4}))?', ham or ''):
        t_str = m.group(1)
        pts = int(m.group(2)) if m.group(2) else None
        sec = time_to_sec(t_str)
        if is_realistic(sec, mes):
            found = (t_str, sec, pts, sira)
            break
            
    # 2. 50m için sadece Saniye arayışı
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
    else:
        still_invalid.append((rid, mes, ham))

print(f"Gerçek bitiş derecesi kurtarılan: {len(rescued_updates)} adet")
print(f"Hala geçersiz/DQ kalan: {len(still_invalid)} adet")

# 470590 kontrolü
check_470590 = [u for u in rescued_updates if u[4] == 470590]
print("470590 kurtarıldı mı:", check_470590)

print("\n--- İlk 10 Kurtarılan Örnek ---")
for u in rescued_updates[:10]:
    print(f"ID {u[4]}: Derece={u[0]} ({u[1]}s), Puan={u[2]}, Sıra={u[3]}")

if still_invalid:
    print("\n--- Kalan Örnekler ---")
    for s in still_invalid[:5]:
        print(f"ID {s[0]} ({s[1]}m): {s[2]}")

