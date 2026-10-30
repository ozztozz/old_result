# -*- coding: utf-8 -*-
import os
import sys
import django
import re

sys.path.insert(0, '/home/ubuntu/app/yuzme_projesi')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'yuzme_projesi.settings')
django.setup()

from django.db import transaction
from sonuclar.models import Sporcu, YarisSonucu, CanliYaris
from google_cloud_runner.main import resolve_masked_athlete

def run_backfill(event_id=None):
    qs = YarisSonucu.objects.select_related('sporcu', 'kulup', 'event')
    if event_id:
        qs = qs.filter(event_id=event_id)
    
    # Sadece Maskeli sporcu olanları seç
    masked_results = list(qs.filter(sporcu__sporcu_adi__startswith='Maskeli sporcu'))
    print(f"[*] Toplam incelenecek maskeli YarisSonucu kaydı: {len(masked_results)}")

    # Aday önbelleği (dogum_yili, cinsiyet)
    candidate_cache = {}
    def get_candidates(yb, gender):
        key = (yb, (gender or '')[:1].upper())
        if key in candidate_cache:
            return candidate_cache[key]
        c_qs = Sporcu.objects.exclude(sporcu_adi__startswith='Maskeli sporcu').select_related('birincil_kulup')
        if yb:
            c_qs = c_qs.filter(dogum_yili=yb)
        cand_list = []
        for sp in c_qs:
            sp_gender = (sp.cinsiyet or '').strip().upper()
            if gender and sp_gender and not sp_gender.startswith(str(gender)[:1].upper()):
                continue
            cand_list.append({
                'id': sp.id,
                'sporcu': sp.sporcu_adi,
                'sporcu_adi': sp.sporcu_adi,
                'dogum_yili': sp.dogum_yili,
                'kulup': sp.birincil_kulup.kulup_adi if sp.birincil_kulup else '',
            })
        candidate_cache[key] = cand_list
        return cand_list

    resolved_count = 0
    unresolved_count = 0
    orphan_sporcu_ids = set()

    for ys in masked_results:
        raw_masked = ys.sporcu_maskeli
        if not raw_masked:
            # "Maskeli sporcu (Ad Soyad)" kalıbından çek
            raw_masked = ys.sporcu.sporcu_adi.replace('Maskeli sporcu (', '').rstrip(')')
        
        yb = ys.sporcu.dogum_yili
        if not yb and ys.yas_grubu:
            m_y = re.search(r'\b(19\d{2}|20\d{2})\b', str(ys.yas_grubu))
            if m_y:
                yb = int(m_y.group(1))
        if not yb and ys.event and ys.event.musabaka_adi:
            m_y = re.search(r'\b(19\d{2}|20\d{2})\b', str(ys.event.musabaka_adi))
            if m_y:
                yb = int(m_y.group(1))

        club_name = ys.kulup.kulup_adi if ys.kulup else ''
        gender = ys.cinsiyet or ys.sporcu.cinsiyet

        cands = get_candidates(yb, gender)
        resolution = resolve_masked_athlete(raw_masked, cands, birth_year=yb, club=club_name)

        if resolution.get('durum') == 'eslesti':
            matched_id = resolution['aday']['id']
            matched_name = resolution['aday']['sporcu_adi']
            old_sporcu = ys.sporcu
            orphan_sporcu_ids.add(old_sporcu.id)
            
            ys.sporcu_id = matched_id
            if not ys.sporcu_maskeli:
                ys.sporcu_maskeli = raw_masked
            ys.save(update_fields=['sporcu', 'sporcu_maskeli'])
            resolved_count += 1
            print(f"  [+] #{ys.id} ({ys.yaris_no}): '{raw_masked}' -> {matched_name} (ID: {matched_id}, Skor: {resolution['skor']})")
        else:
            unresolved_count += 1

    print(f"\n[+] Eşleştirme Tamamlandı! Başarılı: {resolved_count}, Eşleşemeyen: {unresolved_count}")

    # Boşta kalan (hiçbir YarisSonucu tarafından kullanılmayan) 'Maskeli sporcu' kayıtlarını temizle
    deleted_athletes = 0
    for s_id in orphan_sporcu_ids:
        if not YarisSonucu.objects.filter(sporcu_id=s_id).exists():
            Sporcu.objects.filter(id=s_id).delete()
            deleted_athletes += 1

    print(f"[+] Temizlenen hayalet sporcu kaydı: {deleted_athletes}")

if __name__ == '__main__':
    run_backfill(event_id=688)
