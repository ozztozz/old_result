import csv

user_athletes = [
    'Atlas SEYHAN', 'Beren DUMAN', 'Murat MEMOĞLU', 'Hira DEMİRKAYA',
    'Umut Ege DOĞRU', 'Ömer NADİROĞLU', 'Melis Ada KESKİNER', 'Aybars KARPUZ',
    'Defne ERSU', 'Duru KAYA', 'Mete ÇOBANOĞLU', 'Ahmet Emir GEVREK',
    'Defne IŞIKER', 'Mehmet Aras DALGIÇ', 'Ege YILMAZ', 'Ayşe Selen YİĞİTER',
    'Defne BİLGEN', 'Rüzgar ARİĞ', 'Dersu Senem ALTUNDAĞ', 'Elfin TÜRKER',
    'Ada ÇALIŞIR', 'Simay Mina KARABIÇAK', 'Elif Beyza ŞAKRAK', 'Ali Tuna AVCI',
    'Ali Çınar BİLGİN'
]

targets = {a.upper(): a for a in user_athletes}

with open('output/tyf_scanned_bireysel_yuzucu_sonuclari.csv', encoding='utf-8-sig') as f:
    rows = list(csv.DictReader(f))

seen = set()
for r in rows:
    sp_upper = r['Sporcu'].upper()
    for t_upper, orig in targets.items():
        if t_upper in sp_upper and t_upper not in seen:
            print(f"{r['Dosya Adı']:15} | {r['Sporcu']:28} | Yaş: {r['Yaş']:>2} | {r['Kulüp']}")
            seen.add(t_upper)

missing = set(targets.keys()) - seen
if missing:
    print("Missing:", missing)
else:
    print("\nALL 25 USER ATHLETES FOUND AND VERIFIED!")

