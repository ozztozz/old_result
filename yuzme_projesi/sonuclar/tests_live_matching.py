# -*- coding: utf-8 -*-
from unittest.mock import patch
from django.db import connection
from django.test import TransactionTestCase
from sonuclar.models import Event, CanliYaris, CanliYarisDosya, Kulup, Sporcu, SporcuKulupTarihce, YarisSonucu
from sonuclar.local_live_engine import LocalLiveEngine


class StartResultMatchingTests(TransactionTestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        existing_tables = set(connection.introspection.table_names())
        unmanaged_models = [Kulup, Sporcu, Event, SporcuKulupTarihce, CanliYaris, CanliYarisDosya, YarisSonucu]
        with connection.cursor() as cur:
            cur.execute("PRAGMA foreign_keys = OFF;")
        try:
            with connection.schema_editor() as schema_editor:
                for model in unmanaged_models:
                    if model._meta.db_table not in existing_tables:
                        model._meta.managed = True
                        schema_editor.create_model(model)
                        model._meta.managed = False
        finally:
            with connection.cursor() as cur:
                cur.execute("PRAGMA foreign_keys = ON;")

    def setUp(self):
        self.club_ank = Kulup.objects.create(kulup_adi="Ankara Üniversitesi S.K.")
        self.club_nova = Kulup.objects.create(kulup_adi="Nova Akademi Spor Kulübü")

        self.sp_elif = Sporcu.objects.create(
            sporcu_adi="Elif Öykü BOSTAN",
            dogum_yili=2018,
            cinsiyet="Kadın",
            birincil_kulup=self.club_ank,
        )
        self.sp_zeynep = Sporcu.objects.create(
            sporcu_adi="Zeynep KAYA",
            dogum_yili=2018,
            cinsiyet="Kadın",
            birincil_kulup=self.club_nova,
        )
        self.sp_zehra = Sporcu.objects.create(
            sporcu_adi="Zehra KAYA",
            dogum_yili=2018,
            cinsiyet="Kadın",
            birincil_kulup=self.club_nova,
        )
        self.sp_mert = Sporcu.objects.create(
            sporcu_adi="Mert YILMAZ",
            dogum_yili=2018,
            cinsiyet="Kadın",
            birincil_kulup=self.club_nova,
        )

        self.event = Event.objects.create(
            musabaka_adi="ANKARA 8 YAŞ TEST MÜSABAKASI",
            sehir="Ankara",
            yaris_tarihi_baslangic="2026-11-21",
            yaris_tarihi_bitis="2026-11-21",
            kaynak_turu="CANLI_TAKIP",
        )
        self.yaris = CanliYaris.objects.create(
            event=self.event,
            canli_url="https://canli.tyf.gov.tr/live/2026/9999999/",
            musabaka_adi=self.event.musabaka_adi,
            durum="ISLENIYOR",
        )
        self.engine = LocalLiveEngine()

    def _run_prefetched(self, filename, doc_type, yaris_no, swimmers):
        item = {
            "filename": filename,
            "url": f"https://canli.tyf.gov.tr/live/2026/9999999/{filename}?v=1",
            "doc_type": doc_type,
            "yaris_no": str(yaris_no),
        }
        key = "sporcular" if doc_type == "start_listesi" else "sonuclar"
        prefetched = {
            "parsed": {
                "cinsiyet": "Kadınlar",
                "mesafe": 50,
                "stil": "Sırtüstü",
                "yas_grubu": "8 Yaş",
                "yaris_no": str(yaris_no),
                key: swimmers,
            },
            "file_size": 12345,
            "etag": "etag-1",
            "last_modified": "Sat, 21 Nov 2026 10:00:00 GMT",
        }
        return self.engine._process_single_pdf(self.yaris, self.event, item, doc_type, prefetched=prefetched)

    def test_result_links_directly_to_startlist_without_db_rematch(self):
        # 1. StartList:
        #    - Kulvar 7: Elif Öykü BOSTAN (DB'de çözülecek)
        #    - Kulvar 2: A** *e*i* (DB'de yok -> Maskeli sporcu olarak kalacak)
        #    - Kulvar 5: Z*** K** (çok kapalı -> Maskeli sporcu kalacak)
        #    - Kulvar 6: D**u A*d*n (DSQ senaryosu için kulüplü StartList kaydı)
        start_swimmers = [
            {"seri": "1", "kulvar": 7, "sporcu": "Elif Ö**ü B*s*a*", "dogum_yili": 2018, "kulup": "Ankara Üniversitesi S.K.", "giris_derecesi": "46.00"},
            {"seri": "1", "kulvar": 2, "sporcu": "A** *e*i*", "dogum_yili": 2018, "kulup": "Ankara Üniversitesi S.K.", "giris_derecesi": "49.00"},
            {"seri": "1", "kulvar": 5, "sporcu": "**** K**", "dogum_yili": 2018, "kulup": "Nova Akademi Spor Kulübü", "giris_derecesi": "50.00"},
            {"seri": "1", "kulvar": 6, "sporcu": "D**u A*d*n", "dogum_yili": 2018, "kulup": "Nova Akademi Spor Kulübü", "giris_derecesi": "51.00"},
        ]
        self._run_prefetched("StartList_1316.pdf", "start_listesi", "3", start_swimmers)
        self.assertEqual(YarisSonucu.objects.filter(event=self.event).count(), 4)

        # 2. ResultList (1. Yayın):
        #    - Kulvar 7 ve 2 yeni rastgele maskeyle geliyor -> DB match_athlete ÇAĞRILMAMALI!
        #    - Kulvar 5 açık isimle ('Zeynep KAYA') geliyor -> DB match_athlete çağrılıp yükseltilmeli!
        #    - Kulvar 4 (Seri 2): StartList'te olmayan yedek sporcu ('Mert YILMAZ') -> DB match_athlete çağrılmalı!
        #    - Kulvar/Seri yok (DSQ): 'D**u A*d*n' kulüp bilgisi olmadan geliyor -> StartList'ten kulübü miras almalı!
        result_swimmers_1 = [
            {"seri": "1", "kulvar": 7, "sporcu": "E**f **k* *o*t*n", "dogum_yili": 2018, "kulup": "Ankara Üniversitesi S.K.", "derece": "45.77", "sira": "1"},
            {"seri": "1", "kulvar": 2, "sporcu": "A*i **m*r", "dogum_yili": 2018, "kulup": "Ankara Üniversitesi S.K.", "derece": "48.10", "sira": "2"},
            {"seri": "1", "kulvar": 5, "sporcu": "Zeynep KAYA", "dogum_yili": 2018, "kulup": "Nova Akademi Spor Kulübü", "derece": "49.50", "sira": "3"},
            {"seri": "2", "kulvar": 4, "sporcu": "Mert YILMAZ", "dogum_yili": 2018, "kulup": "Nova Akademi Spor Kulübü", "derece": "50.12", "sira": "4"},
            {"seri": None, "kulvar": None, "sporcu": "D**u A*d*n", "dogum_yili": 2018, "kulup": "", "durum": "DSQ", "notlar": "SW 6.4", "sira": "DSQ"},
        ]

        with patch("sonuclar.local_live_engine.match_athlete", wraps=self.engine._cached_match_athlete) as _:
            pass

        with patch.object(self.engine, "_cached_match_athlete", wraps=self.engine._cached_match_athlete) as spy_match:
            self._run_prefetched("ResultList_1316.pdf", "sonuc_listesi", "3", result_swimmers_1)
            called_names = [call.args[0] for call in spy_match.call_args_list]
            # Kulvar 7 (Elif), Kulvar 2 (A** *e*i*) ve DSQ (D**u A*d*n) için DB match_athlete ÇAĞRILMAMALI!
            self.assertNotIn("E**f **k* *o*t*n", called_names)
            self.assertNotIn("A*i **m*r", called_names)
            self.assertNotIn("D**u A*d*n", called_names)
            # Yalnızca açık isim veren Zeynep KAYA ve yedek Mert YILMAZ için çağrılmalı
            self.assertIn("Zeynep KAYA", called_names)
            self.assertIn("Mert YILMAZ", called_names)

        # Toplam 5 satır olmalı (4 StartList + 1 yeni yedek Mert YILMAZ), 0 mükerrer!
        self.assertEqual(YarisSonucu.objects.filter(event=self.event).count(), 5)

        r7 = YarisSonucu.objects.get(event=self.event, seri="1", kulvar=7)
        self.assertEqual(r7.sporcu_id, self.sp_elif.id)
        self.assertEqual(r7.derece, "45.77")
        self.assertEqual(r7.kaynak_turu, "CANLI_SONUC")

        r5 = YarisSonucu.objects.get(event=self.event, seri="1", kulvar=5)
        self.assertEqual(r5.sporcu_id, self.sp_zeynep.id)
        self.assertEqual(r5.derece, "49.50")

        r2 = YarisSonucu.objects.get(event=self.event, seri="1", kulvar=2)
        self.assertTrue(r2.sporcu.sporcu_adi.startswith("Maskeli sporcu"))
        self.assertEqual(r2.derece, "48.10")

        r_dsq = YarisSonucu.objects.get(event=self.event, derece="DSQ")
        self.assertEqual(r_dsq.kulup_id, self.club_nova.id)

        # 3. ResultList (2. Güncelleme — tamamen farklı rastgele maskelerle tekrar yayın):
        #    Hiçbir DB match_athlete çağrısı olmamalı ve satır sayısı yine 5 kalmalı!
        result_swimmers_2 = [
            {"seri": "1", "kulvar": 7, "sporcu": "*l*f O*k* B***n", "dogum_yili": 2018, "kulup": "Ankara Üniversitesi S.K.", "derece": "45.77", "sira": "1"},
            {"seri": "1", "kulvar": 2, "sporcu": "*li D***r", "dogum_yili": 2018, "kulup": "Ankara Üniversitesi S.K.", "derece": "48.10", "sira": "2"},
            {"seri": "1", "kulvar": 5, "sporcu": "Z*yn*p K*Y*", "dogum_yili": 2018, "kulup": "Nova Akademi Spor Kulübü", "derece": "49.50", "sira": "3"},
            {"seri": "2", "kulvar": 4, "sporcu": "M*rt Y*LM*Z", "dogum_yili": 2018, "kulup": "Nova Akademi Spor Kulübü", "derece": "50.12", "sira": "4"},
            {"seri": None, "kulvar": None, "sporcu": "D**u A*d*n", "dogum_yili": 2018, "kulup": "", "durum": "DSQ", "notlar": "SW 6.4", "sira": "DSQ"},
        ]
        with patch.object(self.engine, "_cached_match_athlete", wraps=self.engine._cached_match_athlete) as spy_match_2:
            self._run_prefetched("ResultList_1316.pdf", "sonuc_listesi", "3", result_swimmers_2)
            self.assertEqual(spy_match_2.call_count, 0)

        self.assertEqual(YarisSonucu.objects.filter(event=self.event).count(), 5)
        self.assertEqual(YarisSonucu.objects.get(event=self.event, seri="1", kulvar=7).sporcu_id, self.sp_elif.id)
        self.assertEqual(YarisSonucu.objects.get(event=self.event, seri="1", kulvar=5).sporcu_id, self.sp_zeynep.id)
