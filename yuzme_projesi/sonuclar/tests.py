# -*- coding: utf-8 -*-
import json
from django.test import TestCase, Client
from django.urls import reverse
from django.db import connection
from .models import Kulup, Sporcu, SporcuKulupTarihce, YarisSonucu


class SporcuApiTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        with connection.cursor() as cur:
            cur.execute("""
            CREATE TABLE IF NOT EXISTS kulupler (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kulup_adi TEXT NOT NULL UNIQUE,
                toplam_sporcu_sayisi INTEGER DEFAULT 0,
                toplam_yaris_sayisi INTEGER DEFAULT 0,
                ilk_yaris_tarihi TEXT,
                son_yaris_tarihi TEXT,
                okul_mu INTEGER DEFAULT 0
            );
            """)
            cur.execute("""
            CREATE TABLE IF NOT EXISTS sporcular (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sporcu_adi TEXT NOT NULL,
                dogum_yili INTEGER,
                yas_dogum_yili TEXT,
                cinsiyet TEXT,
                birincil_kulup_id INTEGER REFERENCES kulupler(id),
                toplam_yaris_sayisi INTEGER DEFAULT 0,
                ilk_yaris_tarihi TEXT,
                son_yaris_tarihi TEXT
            );
            """)
            cur.execute("""
            CREATE TABLE IF NOT EXISTS sporcu_kulup_tarihce (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sporcu_id INTEGER NOT NULL REFERENCES sporcular(id),
                kulup_id INTEGER NOT NULL REFERENCES kulupler(id),
                ilk_yaris_tarihi TEXT,
                son_yaris_tarihi TEXT,
                toplam_yaris_sayisi INTEGER DEFAULT 0,
                donem_sirasi INTEGER DEFAULT 1,
                aktif_kulup_mu INTEGER DEFAULT 0
            );
            """)
            cur.execute("""
            CREATE TABLE IF NOT EXISTS yaris_sonuclari (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sporcu_id INTEGER NOT NULL REFERENCES sporcular(id),
                kulup_id INTEGER REFERENCES kulupler(id),
                sporcu_kulup_tarihce_id INTEGER REFERENCES sporcu_kulup_tarihce(id),
                kaynak_turu TEXT,
                dosya_adi TEXT,
                sayfa_no INTEGER,
                satir_no INTEGER,
                musabaka_adi TEXT,
                sehir TEXT,
                yaris_tarihi_ham TEXT,
                yaris_tarihi_baslangic TEXT,
                yaris_tarihi_bitis TEXT,
                yaris_no TEXT,
                cinsiyet TEXT,
                mesafe INTEGER,
                stil TEXT,
                yas_grubu TEXT,
                sporcu_yas TEXT,
                hesaplanan_yas INTEGER,
                sira TEXT,
                derece TEXT,
                derece_saniye REAL,
                puan INTEGER,
                baraj TEXT,
                beraberlik_mi TEXT,
                zaman_kontrolu TEXT,
                uyari_notu TEXT,
                ham_satir TEXT,
                kulvar INTEGER,
                seri TEXT,
                giris_derecesi TEXT
            );
            """)

    def setUp(self):
        self.client = Client()
        self.kulup = Kulup.objects.create(kulup_adi="Test Spor Kulübü", okul_mu=0)
        self.okul = Kulup.objects.create(kulup_adi="Test Ortaokulu", okul_mu=1)

        self.sporcu = Sporcu.objects.create(
            sporcu_adi="Ahmet YILMAZ",
            dogum_yili=2012,
            yas_dogum_yili="2012",
            cinsiyet="ERKEK",
            birincil_kulup=self.kulup,
            toplam_yaris_sayisi=2
        )

        self.tarihce_kulup = SporcuKulupTarihce.objects.create(
            sporcu=self.sporcu,
            kulup=self.kulup,
            aktif_kulup_mu=1,
            toplam_yaris_sayisi=1,
            donem_sirasi=1
        )

        self.tarihce_okul = SporcuKulupTarihce.objects.create(
            sporcu=self.sporcu,
            kulup=self.okul,
            aktif_kulup_mu=0,
            toplam_yaris_sayisi=1,
            donem_sirasi=2
        )

        self.yaris1 = YarisSonucu.objects.create(
            sporcu=self.sporcu,
            kulup=self.kulup,
            sporcu_kulup_tarihce=self.tarihce_kulup,
            musabaka_adi="TYF 11-12 Yaş Müsabakası",
            sehir="Ankara",
            yaris_tarihi_baslangic="2024-03-10",
            yaris_no="1",
            mesafe=50,
            stil="Serbest",
            derece="29.50",
            derece_saniye=29.50,
            puan=350,
            sira="1"
        )

        self.cinar = Sporcu.objects.create(
            sporcu_adi="Çınar KÖYSÜREN",
            dogum_yili=2014,
            yas_dogum_yili="2014",
            cinsiyet="ERKEK",
            birincil_kulup=self.kulup,
            toplam_yaris_sayisi=1
        )

        self.yaris2 = YarisSonucu.objects.create(
            sporcu=self.sporcu,
            kulup=self.okul,
            sporcu_kulup_tarihce=self.tarihce_okul,
            musabaka_adi="Okul Sporları Yıldızlar İl Birinciliği",
            sehir="Ankara",
            yaris_tarihi_baslangic="2024-05-15",
            yaris_no="2",
            mesafe=100,
            stil="Serbest",
            derece="1:05.20",
            derece_saniye=65.20,
            puan=380,
            sira="2"
        )

        # 50m Serbest ikinci yarış (daha yavaş derece)
        self.yaris3 = YarisSonucu.objects.create(
            sporcu=self.sporcu,
            kulup=self.kulup,
            sporcu_kulup_tarihce=self.tarihce_kulup,
            musabaka_adi="TYF Vize Müsabakası",
            sehir="Ankara",
            yaris_tarihi_baslangic="2024-01-20",
            yaris_no="3",
            mesafe=50,
            stil="Serbest",
            derece="31.20",
            derece_saniye=31.20,
            puan=310,
            sira="5"
        )

    def test_api_sporcu_sonuclari_url_path(self):
        url = reverse('sonuclar:api_sporcu_sonuclari', kwargs={'sporcu_id': self.sporcu.id})
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(set(data.keys()), {'en_iyi_derece', 'sonuclar'})
        self.assertEqual(len(data['en_iyi_derece']), 2)
        self.assertEqual(len(data['sonuclar']), 2)

    def test_api_sporcu_sonuclari_query_param(self):
        url = reverse('sonuclar:api_sporcu_sonuclari_query')
        response = self.client.get(f"{url}?sporcu_id={self.sporcu.id}&kategori=Serbest&mesafe=50")
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(set(data.keys()), {'en_iyi_derece', 'sonuclar'})
        self.assertEqual(len(data['sonuclar']), 2)
        self.assertEqual(data['en_iyi_derece']['derece'], "29.50")
        self.assertEqual(data['en_iyi_derece']['mesafe'], 50)
        self.assertTrue(any(s['kisisel_en_iyi_mi'] for s in data['sonuclar']))

    def test_api_kategori_ve_mesafe_url_path(self):
        """URL yolunda /api/sporcular/<id>/sonuclar/<kategori>/<mesafe>/ testi."""
        url = reverse('sonuclar:api_sporcu_kategori_mesafe_sonuclari', kwargs={
            'sporcu_id': self.sporcu.id,
            'kategori': 'Serbest',
            'mesafe': 50
        })
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(set(data.keys()), {'en_iyi_derece', 'sonuclar'})
        self.assertEqual(len(data['sonuclar']), 2)
        self.assertEqual(data['en_iyi_derece']['derece'], "29.50")

    def test_sporcu_detay_html_filtreleme(self):
        """Sporcu detay HTML sayfasında kategori ve mesafe filtreleme testi."""
        url = reverse('sonuclar:sporcu_detay', kwargs={'pk': self.sporcu.id})
        response = self.client.get(f"{url}?kategori=Serbest&mesafe=50")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.context['total_races'], 2)
        self.assertEqual(response.context['secilen_kategori'], 'Serbest')
        self.assertEqual(response.context['secilen_mesafe'], 50)

    def test_api_sporcu_sonuclari_post_json(self):
        url = reverse('sonuclar:api_sporcu_sonuclari_query')
        response = self.client.post(
            url,
            data=json.dumps({'id': self.sporcu.id, 'kategori': 'Serbest', 'mesafe': 100}),
            content_type='application/json'
        )
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(set(data.keys()), {'en_iyi_derece', 'sonuclar'})
        self.assertEqual(data['en_iyi_derece']['mesafe'], 100)
        self.assertEqual(len(data['sonuclar']), 1)

    def test_api_sporcu_sonuclari_not_found(self):
        url = reverse('sonuclar:api_sporcu_sonuclari', kwargs={'sporcu_id': 999999})
        response = self.client.get(url)
        self.assertEqual(response.status_code, 404)
        data = response.json()
        self.assertEqual(data['durum'], 'bulunamadi')

    def test_api_sporcu_sonuclari_missing_id(self):
        url = reverse('sonuclar:api_sporcu_sonuclari_query')
        response = self.client.get(url)
        self.assertEqual(response.status_code, 400)
        data = response.json()
        self.assertEqual(data['durum'], 'gecersiz_istek')

    def test_turkish_character_and_casing_search(self):
        """Türkçe karakter ve büyük/küçük harf duyarsız arama ve eşleştirme testi."""
        from sonuclar.athlete_matcher import match_athlete

        # 1. Küçük harf Türkçe ile arama: "çınar köysüren"
        m1 = match_athlete("çınar köysüren")
        self.assertEqual(m1["durum"], "basarili")
        self.assertEqual(m1["bulunan_id"], self.cinar.id)

        # 2. ASCII küçük harf ile arama: "cinar koysuren"
        m2 = match_athlete("cinar koysuren")
        self.assertEqual(m2["durum"], "basarili")
        self.assertEqual(m2["bulunan_id"], self.cinar.id)

        # 3. Büyük harf Türkçe ile arama: "ÇINAR KÖYSÜREN"
        m3 = match_athlete("ÇINAR KÖYSÜREN")
        self.assertEqual(m3["durum"], "basarili")
        self.assertEqual(m3["bulunan_id"], self.cinar.id)

        # 4. İsim ve soyisim sırası ters girildiğinde: "köysüren çınar"
        m4 = match_athlete("köysüren çınar")
        self.assertEqual(m4["durum"], "basarili")
        self.assertEqual(m4["bulunan_id"], self.cinar.id)

        # 5. ORM icontains sorgusu üzerinden test
        qs_tr = Sporcu.objects.filter(sporcu_adi__icontains="çınar köysüren")
        self.assertIn(self.cinar, qs_tr)

        qs_ascii = Sporcu.objects.filter(sporcu_adi__icontains="cinar koysuren")
        self.assertIn(self.cinar, qs_ascii)

        qs_upper = Sporcu.objects.filter(sporcu_adi__icontains="ÇINAR KÖYSÜREN")
        self.assertIn(self.cinar, qs_upper)
