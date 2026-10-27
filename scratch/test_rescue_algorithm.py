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

def extract_swimmer_data_from_ham(ham, mesafe):
    """
    Ham satırdan gerçek Bitiş Derecesini, Puanını ve Sırasını ayıklar.
    """
    if not ham:
        return None
        
    # Satır başındaki sıra numarası (örn: '14   Çağan...' veya '31   Derin...')
    sira_match = re.match(r'^\s*(\d{1,3})\s+[A-Za-zÇĞİÖŞÜçğıöşü\(]', ham)
    sira = sira_match.group(1) if sira_match else None
    
    # 1. Öncelik: Kulüp sonrasındaki bitiş derecesi + puan kombinasyonu
    # Örn: '2:21.44n375', '3:05.29V315', '2:57.6843579ı', '1:09.13'
    # Bitiş derecesi genelde ilk gelen büyük zamandır (ara zamanlar arkasından gelir)
    times = []
    
    # regex: dakika:saniye.salise (örn 2:21.44 veya 5:03.54)
    for m in re.finditer(r'(?<!\d)(\d{1,2}:[0-5]\d\.\d{2})(?:[^\d\s]*(\d{2,4}))?', ham):
        t_str = m.group(1)
        pts = int(m.group(2)) if m.group(2) else None
        sec = time_to_sec(t_str)
        times.append((t_str, sec, pts, m.start()))

    # 50m için sadece saniye.salise (örn 29.87, 45.42)
    if mesafe == 50 or not times:
        for m in re.finditer(r'(?<!\d)([2-9]\d\.\d{2})(?:[^\d\s]*(\d{2,4}))?', ham):
            t_str = m.group(1)
            pts = int(m.group(2)) if m.group(2) else None
            sec = time_to_sec(t_str)
            times.append((t_str, sec, pts, m.start()))
            
    # Mesafe ile uyumlu olan ilk dereceyi al (çünkü bitiş derecesi ara zamanlardan ÖNCE yazılır!)
    for t_str, sec, pts, pos in times:
        if is_realistic(sec, mesafe):
            return {
                "derece": t_str,
                "derece_saniye": sec,
                "puan": pts,
                "sira": sira
            }
            
    return None

# Test edelim
cur.execute("""
    SELECT id, mesafe, stil, ham_satir, uyari_notu
    FROM yaris_sonuclari
    WHERE (uyari_notu LIKE '%uyumsuz ara zaman%' OR uyari_notu LIKE '%Diskalifiye/Terk%')
""")
rows = cur.fetchall()

success_count = 0
true_dq_count = 0
failed_count = 0

sample_rescues = []

for r in rows:
    rid, mes, stl, ham, uyari = r
    
    # Eğer dosyada gerçekten DQ varsa
    if 'Diskalifiye/Terk: SW' in uyari or 'Diskalifiye/Terk: DQ' in uyari or 'Diskalifiye/Terk: disk' in uyari:
        true_dq_count += 1
        continue
        
    extracted = extract_swimmer_data_from_ham(ham, mes)
    if extracted:
        success_count += 1
        if len(sample_rescues) < 15:
            sample_rescues.append((rid, mes, stl, extracted, ham))
    else:
        failed_count += 1

print(f"Toplam İncelenen: {len(rows)}")
print(f"1. KURTARILAN GERÇEK YARIŞLAR: {success_count}")
print(f"2. GERÇEK DQ / TERK OLANLAR: {true_dq_count}")
print(f"3. Belirlenemeyen: {failed_count}")

print("\n--- Örnek Kurtarılan Kayıtlar ---")
for sr in sample_rescues:
    ext = sr[3]
    print(f"ID {sr[0]} ({sr[1]}m {sr[2]}): Sıra={ext['sira']} | Derece={ext['derece']} ({ext['derece_saniye']}s) | Puan={ext['puan']}")
    print(f"   Ham: '{sr[4]}'")

