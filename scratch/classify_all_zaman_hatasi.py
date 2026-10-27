import sqlite3
import re
import os

db_path = r'c:\Users\OZDEN\Desktop\old_result\database\yuzme_veritabani.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

def time_to_sec(t_str):
    if not t_str:
        return None
    s = t_str.strip()
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

# Dosyaların indexlerini önceden önbelleğe al
txt_cache = {}
def get_file_lines(filename):
    if filename in txt_cache:
        return txt_cache[filename]
    # dosya yolunu ara
    for root, dirs, files in os.walk(r'c:\Users\OZDEN\Desktop\old_result\output\txt'):
        if filename in files:
            p = os.path.join(root, filename)
            try:
                with open(p, 'r', encoding='utf-8', errors='ignore') as f:
                    txt_cache[filename] = f.readlines()
                    return txt_cache[filename]
            except:
                pass
    txt_cache[filename] = []
    return []

def check_dq_in_file(filename, ham_satir):
    lines = get_file_lines(filename)
    if not lines or not ham_satir:
        return False, ""
    
    ham_clean = re.sub(r'\s+', ' ', ham_satir.strip())
    # İlk 15-20 karakter ile satırı bul
    sample = ham_clean[:25]
    for i, line in enumerate(lines):
        line_clean = re.sub(r'\s+', ' ', line.strip())
        if sample in line_clean:
            # sonraki 1-3 satıra bak
            for look in range(1, 4):
                if i + look < len(lines):
                    next_line = lines[i + look].strip()
                    if re.search(r'\b(DQ|diskalifiye|disk\.|SW\s+\d|terk)\b', next_line, re.I):
                        return True, next_line
            break
    return False, ""

cur.execute("""
    SELECT id, dosya_adi, yaris_no, mesafe, stil, derece, derece_saniye, ham_satir, uyari_notu
    FROM yaris_sonuclari
    WHERE zaman_kontrolu = 'ZAMAN_HATASI'
""")
rows = cur.fetchall()

dq_group = []
ocr_fixed_group = []
valid_as_is_group = []
unresolved_group = []

for idx, r in enumerate(rows):
    rid, dosya, yno, mes, stl, cur_der, cur_sec, ham, uyari = r
    
    # 1. Dosyada hemen altında DQ var mı?
    is_dq, dq_reason = check_dq_in_file(dosya, ham)
    if is_dq:
        dq_group.append((rid, cur_der, dq_reason, ham))
        continue
        
    # 2. Mesafe ile derece bariz uyumsuz mu? (Örn 200m'de 18.75s veya 400m'de 1:15s)
    sec = time_to_sec(cur_der)
    if sec and not is_realistic(sec, mes):
        # Eğer gerçekçi değilse ve ham satırda 200m'ye uygun süre yoksa muhtemelen terk/DQ
        # Ham satırdaki sürelere bak
        # A) OCR eksik dakika mı? (örn 100m'de :15.67 -> 1:15.67)
        m_colon = re.search(r'[:!]\s*(\d{2}\.\d{2})', ham or '')
        if m_colon:
            cand = f"1:{m_colon.group(1)}"
            cand_sec = time_to_sec(cand)
            if is_realistic(cand_sec, mes):
                ocr_fixed_group.append((rid, cur_der, cand, cand_sec, "OCR colon düzeltme"))
                continue
        # B) Yapışık dakika mı? (örn 100m'de 115.67 -> 1:15.67)
        m_concat = re.search(r'(?<!\d)([1-4])([0-5]\d\.\d{2})(?!\d)', ham or '')
        if m_concat:
            cand = f"{m_concat.group(1)}:{m_concat.group(2)}"
            cand_sec = time_to_sec(cand)
            if is_realistic(cand_sec, mes):
                ocr_fixed_group.append((rid, cur_der, cand, cand_sec, "Yapışık dakika düzeltme"))
                continue
                
        # Eğer hala gerçekçi değilse bu bir DQ/ara zamandır
        dq_group.append((rid, cur_der, f"Mesafe ({mes}m) ile gerçekçi olmayan süre ({cur_der}) - Ara zaman/Terk", ham))
        continue

    # 3. OCR düzeltmesi gerekiyor mu?
    if cur_der and not is_realistic(sec, mes):
        # OCR dene
        pass
    else:
        # Derece zaten ham satırda var ve mesafe ile gerçekçi
        valid_as_is_group.append((rid, cur_der, sec, ham))

print("=== KAPSAMLI SINIFLANDIRMA SONUÇLARI ===")
print(f"Toplam İncelenen Kayıt: {len(rows)}")
print(f"1. GEÇERLİ OLANLAR (Derece ZATEN Doğru): {len(valid_as_is_group)} adet (%{len(valid_as_is_group)/len(rows)*100:.1f})")
print(f"2. OCR DÜZELTİLECEKLER (Derece 1:xx.xx olarak onarılacak): {len(ocr_fixed_group)} adet (%{len(ocr_fixed_group)/len(rows)*100:.1f})")
print(f"3. DİSKALİFİYE / TERK OLANLAR (Tasnif Dışı / DQ yapılacak): {len(dq_group)} adet (%{len(dq_group)/len(rows)*100:.1f})")

print("\n--- Örnek DQ / Terk Kayıtları (İlk 5) ---")
for d in dq_group[:5]:
    print(f"ID {d[0]}: Derece='{d[1]}' | Neden='{d[2]}'")
    print(f"   Ham: '{d[3]}'")

print("\n--- Örnek OCR Düzeltilen Kayıtlar (İlk 5) ---")
for o in ocr_fixed_group[:5]:
    print(f"ID {o[0]}: Eski='{o[1]}' -> Yeni='{o[2]}' ({o[3]}s) | {o[4]}")

