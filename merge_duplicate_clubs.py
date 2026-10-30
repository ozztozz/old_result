# -*- coding: utf-8 -*-
import os
import sys
import django
import re

sys.path.insert(0, '/home/ubuntu/app/yuzme_projesi')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'yuzme_projesi.settings')
django.setup()

from django.db import transaction
from django.db.models import Q
from sonuclar.models import Kulup, YarisSonucu, Sporcu, SporcuKulupTarihce

def clean_and_expand_club_name(name: str) -> str:
    if not name:
        return ""
    text = name.strip()
    text = re.sub(r'[\s\.]*\bS[\.\s]*K[\.\s]*$', ' Spor Kulübü', text, flags=re.IGNORECASE)
    text = re.sub(r'[\s\.]*\bGSK[\.\s]*$', ' Gençlik ve Spor Kulübü', text, flags=re.IGNORECASE)
    text = re.sub(r'[\s\.]*\bYSK[\.\s]*$', ' Yüzme Spor Kulübü', text, flags=re.IGNORECASE)
    text = re.sub(r'\bS[\.\s]*K[\.\s]*\b', ' Spor Kulübü ', text, flags=re.IGNORECASE)
    text = re.sub(r'\bG[\.\s]*S[\.\s]*K[\.\s]*\b', ' Gençlik ve Spor Kulübü ', text, flags=re.IGNORECASE)
    text = re.sub(r'\s+', ' ', text).strip()
    text = text.rstrip('. ')
    return text

def run_club_merge():
    sk_kulupler = list(Kulup.objects.filter(kulup_adi__iregex=r'(\bS\.?K\.?\b|\bGSK\b)'))
    print(f"[*] Toplam incelenecek kısaltmalı kulüp sayısı: {len(sk_kulupler)}")

    merged_count = 0
    total_races_moved = 0
    total_athletes_moved = 0

    for k in sk_kulupler:
        expanded = clean_and_expand_club_name(k.kulup_adi)
        canonical = Kulup.objects.filter(
            Q(kulup_adi__iexact=expanded) | Q(kulup_adi__iexact=f"{expanded} Derneği")
        ).exclude(id=k.id).first()

        if not canonical:
            continue

        with transaction.atomic():
            # 1. Yarış Sonuçlarını Taşı
            ys_updated = YarisSonucu.objects.filter(kulup=k).update(kulup=canonical)
            total_races_moved += ys_updated

            # 2. Sporcuları Taşı
            sp_updated = Sporcu.objects.filter(birincil_kulup=k).update(birincil_kulup=canonical)
            total_athletes_moved += sp_updated

            # 3. Kulüp Tarihçelerini Düzenle
            for th in SporcuKulupTarihce.objects.filter(kulup=k):
                # Aynı sporcunun ana kulüpte aynı dönem kaydı var mı?
                existing_th = SporcuKulupTarihce.objects.filter(
                    sporcu_id=th.sporcu_id,
                    kulup=canonical,
                    donem_sirasi=th.donem_sirasi
                ).first()
                if existing_th:
                    th.delete()
                else:
                    th.kulup = canonical
                    th.save(update_fields=['kulup'])

            # 4. Ana Kulüp İstatistiklerini Güncelle
            canonical.toplam_sporcu_sayisi = Sporcu.objects.filter(birincil_kulup=canonical).count()
            canonical.save(update_fields=['toplam_sporcu_sayisi'])

            # 5. Kısaltmalı mükerrer kulüp kaydını sil
            old_name = k.kulup_adi
            old_id = k.id
            k.delete()
            merged_count += 1
            print(f"  [+] BİRLEŞTİRİLDİ: ID={old_id} '{old_name}' ({ys_updated} yarış, {sp_updated} sporcu) ===> ID={canonical.id} '{canonical.kulup_adi}'")

    print(f"\n[+] İŞLEM TAMAMLANDI:")
    print(f"    - Birleştirilen ve silinen mükerrer kulüp: {merged_count}")
    print(f"    - Aktarılan yarış sonucu: {total_races_moved}")
    print(f"    - Aktarılan sporcu: {total_athletes_moved}")

if __name__ == '__main__':
    run_club_merge()
