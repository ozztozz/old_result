import sqlite3
import re

db_path = r'c:\Users\OZDEN\Desktop\old_result\database\yuzme_veritabani.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

def time_to_sec(t_str):
    if not t_str:
        return None
    s = t_str.strip()
    # 1:30.67 or 18.75 or 2:05.12
    m_min = re.match(r'^(\d+):(\d{2}(?:\.\d+)?)$', s)
    if m_min:
        return int(m_min.group(1)) * 60 + float(m_min.group(2))
    m_sec = re.match(r'^(\d+(?:\.\d+)?)$', s)
    if m_sec:
        return float(m_sec.group(1))
    return None

def extract_time_from_raw(raw):
    if not raw:
        return None
    # Sonda veya boşluklardan sonra 1:23.45 veya 23.45 formatları
    # Typ: 1:30.67, 18.75, 2:15.34
    matches = re.findall(r'\b(?:\d+:)?\d{1,2}\.\d{2}\b', raw)
    return matches

cur.execute("""
    SELECT id, dosya_adi, yaris_no, cinsiyet, mesafe, stil, yas_grubu, sira, derece, derece_saniye, ham_satir, uyari_notu
    FROM yaris_sonuclari
    WHERE zaman_kontrolu = 'ZAMAN_HATASI'
""")
rows = cur.fetchall()
print(f"Total ZAMAN_HATASI records: {len(rows)}")

ham_matches_derece = 0
ham_differs_derece = 0
invalid_time_in_ham = 0
diff_examples = []
match_examples = []

for r in rows:
    rid, dosya, yno, cns, mes, stl, yas_g, sira, derece, d_sec, ham, uyari = r
    times_in_ham = extract_time_from_raw(ham)
    
    # Ham satırdaki derecelerden biri bizim `derece` ile tam veya yaklaşık uyuşuyor mu?
    if not times_in_ham:
        invalid_time_in_ham += 1
    elif derece in times_in_ham:
        ham_matches_derece += 1
        if len(match_examples) < 10:
            match_examples.append((rid, derece, ham, uyari))
    else:
        # Ham satırdaki son zaman derece mi?
        ham_differs_derece += 1
        if len(diff_examples) < 10:
            diff_examples.append((rid, derece, times_in_ham, ham, uyari))

print(f"\nAnalysis:")
print(f"  - Ham satırda derece birebir MEVCUT (Zaman aslında DOĞRU): {ham_matches_derece} ({ham_matches_derece/len(rows)*100:.1f}%)")
print(f"  - Ham satırdaki zamanlar derece ile farklı: {ham_differs_derece} ({ham_differs_derece/len(rows)*100:.1f}%)")
print(f"  - Ham satırda hiçbir zaman formatı bulunamadı: {invalid_time_in_ham}")

print("\n--- Örnekler (Ham satırda derece birebir olanlar - Zamanı Doğru Olanlar) ---")
for ex in match_examples[:5]:
    print(f"ID {ex[0]}: Derece='{ex[1]}' | Uyari='{ex[3]}'")
    print(f"   Ham: '{ex[2]}'")

if diff_examples:
    print("\n--- Örnekler (Ham satır ile derece uyuşmayanlar) ---")
    for ex in diff_examples[:5]:
        print(f"ID {ex[0]}: Derece='{ex[1]}' vs Ham Zamanlar={ex[2]} | Uyari='{ex[4]}'")
        print(f"   Ham: '{ex[3]}'")

