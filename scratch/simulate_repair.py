import sqlite3
import re

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

def is_realistic_time(sec, mesafe):
    if not sec or not mesafe:
        return True
    # Yüzme dünya/türkiye sınırları ve çocuk yaş grupları toleransı:
    if mesafe == 50:
        return 19.0 <= sec <= 120.0
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

cur.execute("""
    SELECT id, mesafe, stil, derece, derece_saniye, ham_satir, uyari_notu
    FROM yaris_sonuclari
    WHERE zaman_kontrolu = 'ZAMAN_HATASI'
""")
rows = cur.fetchall()

valid_as_is = []
fixed_records = []
unfixable_or_manual = []

for r in rows:
    rid, mes, stl, cur_der, cur_sec, ham, uyari = r
    
    # 1. Mevcut derece ham satırda birebir geçiyor ve mesafe ile gerçekçi mi?
    sec = time_to_sec(cur_der)
    if sec and is_realistic_time(sec, mes):
        # Ham satırda cur_der izole olarak var mı?
        # örn: ' 1:30.67' veya ' 18.75'
        if re.search(r'(?<!\d)' + re.escape(cur_der) + r'(?!\d)', ham or ''):
            valid_as_is.append((rid, cur_der, sec, "Mevcut derece doğru ve ham satırda teyit edildi."))
            continue

    # 2. Ham satırda OCR bozulması var mı?
    # Örnek A: 'Kulult:12.59' veya ':07.50' veya '! :07.50'
    m_colon = re.search(r'[:!]\s*(\d{2}\.\d{2})', ham or '')
    if m_colon:
        cand = f"1:{m_colon.group(1)}"
        cand_sec = time_to_sec(cand)
        if cand_sec and is_realistic_time(cand_sec, mes):
            fixed_records.append((rid, cur_der, cand, cand_sec, f"OCR eksik dakika düzeltildi ({m_colon.group(0)} -> {cand})"))
            continue

    # Örnek B: '110.55' (1:10.55) veya '233.71' (2:33.71) yapışık dakika
    m_concat = re.search(r'(?<!\d)([1-4])([0-5]\d\.\d{2})(?!\d)', ham or '')
    if m_concat:
        cand = f"{m_concat.group(1)}:{m_concat.group(2)}"
        cand_sec = time_to_sec(cand)
        if cand_sec and is_realistic_time(cand_sec, mes):
            fixed_records.append((rid, cur_der, cand, cand_sec, f"Yapışık dakika ayrıldı ({m_concat.group(0)} -> {cand})"))
            continue

    # Örnek C: Ham satırdaki standart zamanlardan mesafeye en uygun olanı bul
    std_times = re.findall(r'(?<!\d)(?:([1-9]\d?):)?([0-5]\d\.\d{2})(?!\d)', ham or '')
    found_alt = False
    for m, s in std_times:
        cand = f"{m}:{s}" if m else s
        cand_sec = time_to_sec(cand)
        if cand_sec and is_realistic_time(cand_sec, mes):
            fixed_records.append((rid, cur_der, cand, cand_sec, f"Ham satırdan mesafeye uygun derece seçildi ({cand})"))
            found_alt = True
            break
            
    if not found_alt:
        unfixable_or_manual.append((rid, mes, cur_der, ham, uyari))

print("=== SİMÜLASYON SONUÇLARI ===")
print(f"Toplam ZAMAN_HATASI: {len(rows)}")
print(f"1. Derecesi ZATEN DOĞRU olanlar (GEÇERLİ yapılacak): {len(valid_as_is)} adet (%{len(valid_as_is)/len(rows)*100:.1f})")
print(f"2. Ham satırdan düzeltilen dereceler (GEÇERLİ yapılacak): {len(fixed_records)} adet (%{len(fixed_records)/len(rows)*100:.1f})")
print(f"3. Düzeltilemeyen / Manuel kontrol gerekenler: {len(unfixable_or_manual)} adet (%{len(unfixable_or_manual)/len(rows)*100:.1f})")

if fixed_records:
    print("\n--- Örnek Düzeltilen Dereceler (İlk 10) ---")
    for f in fixed_records[:10]:
        print(f"ID {f[0]}: Eski='{f[1]}' -> Yeni='{f[2]}' ({f[3]}s) | {f[4]}")

if unfixable_or_manual:
    print("\n--- Kalan / Manuel Kayıtlar (İlk 10) ---")
    for u in unfixable_or_manual[:10]:
        print(f"ID {u[0]} ({u[1]}m): Derece='{u[2]}' | Uyari='{u[4]}'")
        print(f"   Ham: '{u[3]}'")

