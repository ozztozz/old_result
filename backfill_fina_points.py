# -*- coding: utf-8 -*-
"""
backfill_fina_points.py
=======================
Veritabanında tamamlanmış derecesi (derece_saniye > 0) olan ancak
puanı boş (NULL veya 0) kalmış tüm yarışlar için resmi FINA / World Aquatics
puanlarını hesaplayıp toplu günceller.
"""

import os
import sys
import time
import django

sys.path.insert(0, '/home/ubuntu/app/yuzme_projesi')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'yuzme_projesi.settings')
django.setup()

from django.db.models import Q
from sonuclar.models import YarisSonucu
from sonuclar.fina_calculator import calculate_fina_points, detect_course

def run_fina_backfill(event_id=None, batch_size=2000):
    qs = YarisSonucu.objects.filter(
        derece_saniye__gt=0
    ).filter(
        Q(puan__isnull=True) | Q(puan=0)
    ).select_related('event')

    if event_id:
        qs = qs.filter(event_id=event_id)

    total_count = qs.count()
    print(f"[*] Puanı hesaplanacak toplam yarış sonucu: {total_count}")
    if total_count == 0:
        print("[+] Güncellenecek kayıt bulunamadı.")
        return

    updated_count = 0
    skipped_count = 0
    batch = []

    course_cache = {}

    for ys in qs.iterator(chunk_size=batch_size):
        m_adi = ys.event.musabaka_adi if ys.event else ""
        if m_adi not in course_cache:
            course_cache[m_adi] = detect_course(m_adi)
        course = course_cache[m_adi]

        pts = calculate_fina_points(
            cinsiyet=ys.cinsiyet,
            mesafe=ys.mesafe,
            stil=ys.stil,
            derece_saniye=ys.derece_saniye,
            course=course
        )

        if pts is not None and pts > 0:
            ys.puan = pts
            batch.append(ys)
            updated_count += 1
        else:
            skipped_count += 1

        if len(batch) >= batch_size:
            for retry in range(5):
                try:
                    YarisSonucu.objects.bulk_update(batch, ['puan'])
                    break
                except Exception as e:
                    if 'locked' in str(e).lower() and retry < 4:
                        time.sleep(1 + retry)
                    else:
                        raise
            print(f"  [>] {updated_count} / {total_count} kayıt güncellendi...")
            batch.clear()

    if batch:
        for retry in range(5):
            try:
                YarisSonucu.objects.bulk_update(batch, ['puan'])
                break
            except Exception as e:
                if 'locked' in str(e).lower() and retry < 4:
                    time.sleep(1 + retry)
                else:
                    raise
        print(f"  [>] {updated_count} / {total_count} kayıt güncellendi...")
        batch.clear()

    print(f"\n[+] FINA HESAPLAMA TAMAMLANDI:")
    print(f"    - Başarıyla hesaplanan ve güncellenen: {updated_count}")
    print(f"    - Hesaplanamayan (desteklenmeyen branş/bayrak vb.): {skipped_count}")

if __name__ == '__main__':
    event_arg = None
    if len(sys.argv) > 1 and sys.argv[1].isdigit():
        event_arg = int(sys.argv[1])
    run_fina_backfill(event_id=event_arg)
