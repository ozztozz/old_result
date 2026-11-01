# -*- coding: utf-8 -*-
import os
import sys
import argparse

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
import django
import re

# Dinamik ortam algılama (Yerel Windows / Sunucu Ubuntu)
current_dir = os.path.dirname(os.path.abspath(__file__))
local_app_dir = os.path.join(current_dir, 'yuzme_projesi')

if os.path.exists(local_app_dir):
    sys.path.insert(0, local_app_dir)
elif os.path.exists('/home/ubuntu/app/yuzme_projesi'):
    sys.path.insert(0, '/home/ubuntu/app/yuzme_projesi')

sys.path.insert(0, current_dir)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'yuzme_projesi.settings')
django.setup()

from django.db import transaction
from django.db.models import Q
from sonuclar.models import Sporcu, YarisSonucu, CanliYaris
from google_cloud_runner.main import resolve_masked_athlete, normalize_masked_name


def run_backfill(event_id=None, dry_run=False):
    """
    Mevcut veritabanındaki tüm maskeli sporcu ve yarış sonuçlarını yeni wildcard/LIKE
    algoritmasıyla tarayarak gerçek sporcularla eşleştirir.
    """
    qs = YarisSonucu.objects.select_related('sporcu', 'kulup', 'event')
    if event_id:
        qs = qs.filter(event_id=event_id)

    # Maskeli olan tüm YarisSonucu kayıtlarını kapsamlı filtrele
    filter_q = (
        Q(sporcu__sporcu_adi__startswith='Maskeli sporcu') |
        Q(sporcu__sporcu_adi__contains='*') |
        (Q(sporcu_maskeli__isnull=False) & Q(sporcu_maskeli__contains='*'))
    )
    masked_results = list(qs.filter(filter_q).distinct())
    print(f"[*] Toplam incelenecek maskeli YarisSonucu kaydı: {len(masked_results)} (Event: {event_id or 'TÜMÜ'}, Dry-Run: {dry_run})")

    if not masked_results:
        print("[!] Eşleştirilecek maskeli kayıt bulunamadı.")
        return

    # Aday önbelleği (dogum_yili, cinsiyet, norm_masked)
    candidate_cache = {}

    def get_candidates(yb, gender, raw_masked=None):
        norm_masked = normalize_masked_name(raw_masked) if raw_masked else ""
        key = (yb, (gender or '')[:1].upper(), norm_masked)
        if key in candidate_cache:
            return candidate_cache[key]

        c_qs = Sporcu.objects.exclude(sporcu_adi__startswith='Maskeli sporcu').select_related('birincil_kulup')
        if yb:
            c_qs = c_qs.filter(dogum_yili=yb)

        # SQL LIKE / Wildcard ile 40.000 sporcuyu birkaç adaya indir
        if norm_masked:
            m_tokens = norm_masked.split()
            if m_tokens:
                q_like = Q()
                first_tok = m_tokens[0].rstrip('.').replace('*', '')
                if len(first_tok) >= 2:
                    q_like &= Q(sporcu_adi__icontains=first_tok)
                elif len(first_tok) == 1:
                    q_like &= (Q(sporcu_adi__istartswith=first_tok) | Q(sporcu_adi__icontains=f" {first_tok}"))

                last_tok = m_tokens[-1].rstrip('.').replace('*', '')
                if last_tok:
                    q_like &= Q(sporcu_adi__icontains=last_tok[0])
                c_qs = c_qs.filter(q_like)

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
        if not raw_masked and ys.sporcu:
            # "Maskeli sporcu (Ad Soyad)" kalıbından çek
            raw_masked = ys.sporcu.sporcu_adi.replace('Maskeli sporcu (', '').rstrip(')')

        yb = ys.sporcu.dogum_yili if ys.sporcu else None
        if not yb and ys.yas_grubu:
            m_y = re.search(r'\b(19\d{2}|20\d{2})\b', str(ys.yas_grubu))
            if m_y:
                yb = int(m_y.group(1))
        if not yb and ys.event and ys.event.musabaka_adi:
            m_y = re.search(r'\b(19\d{2}|20\d{2})\b', str(ys.event.musabaka_adi))
            if m_y:
                yb = int(m_y.group(1))

        club_name = ys.kulup.kulup_adi if ys.kulup else ''
        gender = ys.cinsiyet or (ys.sporcu.cinsiyet if ys.sporcu else '')

        cands = get_candidates(yb, gender, raw_masked=raw_masked)
        resolution = resolve_masked_athlete(raw_masked, cands, birth_year=yb, club=club_name)

        if resolution.get('durum') == 'eslesti':
            matched_id = resolution['aday']['id']
            matched_name = resolution['aday']['sporcu_adi']
            if ys.sporcu:
                orphan_sporcu_ids.add(ys.sporcu.id)

            if not dry_run:
                ys.sporcu_id = matched_id
                if not ys.sporcu_maskeli:
                    ys.sporcu_maskeli = raw_masked
                ys.save(update_fields=['sporcu', 'sporcu_maskeli'])

            resolved_count += 1
            print(f"  [+] #{ys.id} ({ys.yaris_no or 'Yarış'}): '{raw_masked}' -> {matched_name} (ID: {matched_id}, Skor: {resolution['skor']})")
        else:
            unresolved_count += 1

    print(f"\n[+] Eşleştirme Tamamlandı! Başarılı: {resolved_count}, Eşleşemeyen: {unresolved_count}")

    # Boşta kalan (hiçbir YarisSonucu tarafından kullanılmayan) 'Maskeli sporcu' kayıtlarını temizle
    if not dry_run and orphan_sporcu_ids:
        deleted_athletes = 0
        for s_id in orphan_sporcu_ids:
            if not YarisSonucu.objects.filter(sporcu_id=s_id).exists():
                Sporcu.objects.filter(id=s_id).delete()
                deleted_athletes += 1
        print(f"[+] Temizlenen hayalet sporcu kaydı: {deleted_athletes}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Mevcut maskeli sporcu kayıtlarını gerçek sporcularla eşleştirir.")
    parser.add_argument('--event', type=int, default=None, help="Yalnızca belirtilen event_id için çalıştır (örn: --event 688)")
    parser.add_argument('--dry-run', action='store_true', help="Veritabanını değiştirmeden simülasyon yapar")
    args = parser.parse_args()

    # Event ID verilmemişse ve varsayılan olarak test edilmek isteniyorsa
    run_backfill(event_id=args.event, dry_run=args.dry_run)
