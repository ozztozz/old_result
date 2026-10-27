import sqlite3
import re

db_path = r'c:\Users\OZDEN\Desktop\old_result\database\yuzme_veritabani.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("""
    SELECT id, mesafe, stil, derece, derece_saniye, ham_satir, uyari_notu 
    FROM yaris_sonuclari 
    WHERE zaman_kontrolu = 'ZAMAN_HATASI'
""")
rows = cur.fetchall()

def parse_clean_time_from_ham(ham, mesafe, current_derece):
    """
    Ham satırdan en mantıklı ve doğru yüzme derecesini çıkarır.
    """
    if not ham:
        return current_derece, None

    # 1. Standart M:SS.ms veya SS.ms formatları (örn: 1:30.67, 2:15.40, 28.50)
    std_times = re.findall(r'(?<!\d)(?:([1-9]\d?):)?([0-5]\d\.\d{2})(?!\d)', ham)
    # std_times her biri (dakika, saniye) tuple'ı döner
    
    # 2. Eğer mevcut derece zaten ham satırda tam olarak varsa:
    if current_derece and re.search(r'(?<!\d)' + re.escape(current_derece) + r'(?!\d)', ham):
        # Mesafe ile uyumlu mu kontrol et (örn 50m için 18.75s veya 32.50s çok normal)
        # 100m için 1:15.66 normal
        # Ama 100m veya 200m için 03.88s veya 07.50s gibi saçma bir şey varsa OCR bozulması olabilir
        sec = None
        if ':' in current_derece:
            parts = current_derece.split(':')
            sec = int(parts[0]) * 60 + float(parts[1])
        else:
            try:
                sec = float(current_derece)
            except:
                pass
        
        # Eğer mesafe >= 100 ve sec < 20 ise bu muhtemelen OCR hatası (örn 1:07.50 yerine 07.50)
        is_suspicious_short = False
        if mesafe and sec:
            if mesafe >= 100 and sec < 35: # 100 metrede 35 saniyeden kısa olamaz (dünya rekoru 46s)
                is_suspicious_short = True
            elif mesafe >= 200 and sec < 80:
                is_suspicious_short = True
            elif mesafe >= 400 and sec < 180:
                is_suspicious_short = True

        if not is_suspicious_short:
            return current_derece, "DERECE_DOGRULANDI"

    # 3. OCR Bozulmalarını Düzelt:
    # A) '118.58' -> '1:18.58', '233.71' -> '2:33.71', '104.73' -> '1:04.73', '110.55' -> '1:10.55'
    # Format: 1[0-5][0-9]\.[0-9]{2} veya 2[0-5][0-9]\.[0-9]{2}
    ocr_min_sec = re.findall(r'(?<!\d)([1-9])([0-5]\d\.\d{2})', ham)
    if ocr_min_sec:
        for m, s in ocr_min_sec:
            cand = f"{m}:{s}"
            # cand ham satırda yapışık mıydı? (örn 118.58)
            if f"{m}{s}" in ham.replace(" ", "") or f"{m}:{s}" in ham:
                return cand, f"OCR_DUZELTME ({m}{s} -> {cand})"

    # B) ':07.50' veya '! :07.50' veya 'Sport:03.88' -> '1:07.50', '1:03.88'
    ocr_colon = re.findall(r'[:!]\s*(0[0-9]\.\d{2}|[1-5]\d\.\d{2})', ham)
    if ocr_colon:
        # Genelde 1:xx.xx olur
        cand = f"1:{ocr_colon[0]}"
        return cand, f"OCR_COLON_DUZELTME (:{ocr_colon[0]} -> {cand})"

    # C) Standart sürelerden mesafeye en uygun olanı seç
    valid_candidates = []
    for m, s in std_times:
        t_str = f"{m}:{s}" if m else s
        sec = int(m)*60 + float(s) if m else float(s)
        # Mantıklı yüzme süresi mi?
        if mesafe:
            if mesafe == 50 and (20 <= sec <= 90):
                valid_candidates.append((t_str, sec))
            elif mesafe == 100 and (45 <= sec <= 200):
                valid_candidates.append((t_str, sec))
            elif mesafe == 200 and (100 <= sec <= 400):
                valid_candidates.append((t_str, sec))
            elif mesafe == 400 and (220 <= sec <= 800):
                valid_candidates.append((t_str, sec))
            elif mesafe >= 800 and (480 <= sec <= 2000):
                valid_candidates.append((t_str, sec))
        else:
            if 20 <= sec <= 1500:
                valid_candidates.append((t_str, sec))

    if valid_candidates:
        # Genelde sondaki veya mesafeye en uyan
        return valid_candidates[0][0], "STANDART_REGEX_BULUNDU"

    return current_derece, "DEGISTIRILMEDI"

# Test et
results = {}
fixes = []
for r in rows:
    rid, mes, stl, cur_der, cur_sec, ham, uyari = r
    new_der, note = parse_clean_time_from_ham(ham, mes, cur_der)
    results[note] = results.get(note, 0) + 1
    if new_der != cur_der:
        fixes.append((rid, mes, cur_der, new_der, note, ham))

print("Results distribution:")
for k, v in sorted(results.items(), key=lambda x: -x[1]):
    print(f"  {k}: {v}")

print(f"\nTotal fixes where Derece changes: {len(fixes)}")
print("Sample fixes:")
for f in fixes[:15]:
    print(f"ID {f[0]} ({f[1]}m): '{f[2]}' -> '{f[3]}' [{f[4]}]")
    print(f"   Ham: '{f[5]}'")

