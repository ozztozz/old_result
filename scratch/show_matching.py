import os
import sys

sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'yuzme_projesi'))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'yuzme_projesi.settings')

import django
django.setup()

from sonuclar.models import YarisSonucu, CanliYarisDosya

print("=" * 80)
print("GEMINI EŞLEŞTİRME VE CANLI YARIŞ VERİ ANALİZİ (Müsabaka ID: 582)")
print("=" * 80)

for y_no in ['1', '2', '3']:
    qs = YarisSonucu.objects.filter(event_id=582, yaris_no=y_no).select_related('sporcu', 'kulup')
    sonuclar = qs.filter(kaynak_turu='CANLI_SONUC')
    bekleyenler = qs.filter(kaynak_turu='CANLI_START_LISTESI')
    
    print(f"\n--- YARIŞ NO: {y_no} ---")
    print(f"Toplam Kayıt       : {qs.count()}")
    print(f"Sonuçlanan (CANLI) : {sonuclar.count()} (Derecesi girilmiş, sıra ve puanı olanlar)")
    print(f"Hala Bekleyen (DNS): {bekleyenler.count()} (Start listesinde olup sonuç listesinde yer almayanlar)")
    
    print("\n[+] Eşleşen ve Güncellenen İlk 5 Örnek:")
    for r in sonuclar[:5]:
        kulup_ad = r.kulup.kulup_adi if r.kulup else "Ferdi"
        print(f"  • ID #{r.id:<7} | Sıra: {r.sira or '-':<3} | Sporcu: {r.sporcu.sporcu_adi:<25} | "
              f"Seri: {r.seri or '-':<2} Kulvar: {r.kulvar or '-':<2} | "
              f"Giriş: {r.giris_derecesi or '-':<8} -> Derece: {r.derece:<8} | Puan: {r.puan or '-'}")

    if bekleyenler.exists():
        print("\n[-] Start Listesinde Olup Sonuçta Çıkmayanlar (DNS / Yüzmeyenler) (İlk 3 Örnek):")
        for r in bekleyenler[:3]:
            kulup_ad = r.kulup.kulup_adi if r.kulup else "Ferdi"
            print(f"  • ID #{r.id:<7} | Durum: {r.derece:<10} | Sporcu: {r.sporcu.sporcu_adi:<25} | "
                  f"Seri: {r.seri or '-':<2} Kulvar: {r.kulvar or '-':<2} | Giriş: {r.giris_derecesi or '-'}")

