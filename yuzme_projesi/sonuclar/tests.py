# -*- coding: utf-8 -*-
import json
from django.test import TestCase, Client
from django.urls import reverse
from django.db import connection
from .models import Kulup, Sporcu, SporcuKulupTarihce, YarisSonucu, CanliYaris, Event, CanliYarisDosya


class SporcuApiTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        with connection.cursor() as cur:
            cur.execute("""
            CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                musabaka_adi TEXT NOT NULL,
                sehir TEXT,
                yaris_tarihi_ham TEXT,
                yaris_tarihi_baslangic TEXT,
                yaris_tarihi_bitis TEXT,
                kaynak_turu TEXT,
                toplam_yaris_sayisi INTEGER DEFAULT 0,
                toplam_sporcu_sayisi INTEGER DEFAULT 0,
                olusturulma_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP,
                guncellenme_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """)
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
            CREATE TABLE IF NOT EXISTS canli_yaris_dosyalari (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id INTEGER REFERENCES events(id),
                canli_yaris_id INTEGER REFERENCES canli_yarislar(id),
                dosya_adi TEXT NOT NULL,
                dosya_url TEXT,
                dosya_turu TEXT,
                yaris_no TEXT,
                mesafe INTEGER,
                stil TEXT,
                cinsiyet TEXT,
                yas_grubu TEXT,
                etag TEXT,
                last_modified TEXT,
                content_hash TEXT,
                dosya_boyutu INTEGER,
                durum TEXT DEFAULT 'BEKLIYOR',
                kayit_sayisi INTEGER DEFAULT 0,
                hata_mesaji TEXT,
                son_kontrol_tarihi DATETIME,
                son_islem_tarihi DATETIME,
                olusturulma_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP,
                guncellenme_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """)
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
                event_id INTEGER REFERENCES events(id),
                canli_dosya_id INTEGER REFERENCES canli_yaris_dosyalari(id),
                sporcu_id INTEGER NOT NULL REFERENCES sporcular(id),
                kulup_id INTEGER REFERENCES kulupler(id),
                sporcu_kulup_tarihce_id INTEGER REFERENCES sporcu_kulup_tarihce(id),
                kaynak_turu TEXT,
                dosya_adi TEXT,
                sayfa_no INTEGER,
                satir_no INTEGER,
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
                giris_derecesi TEXT,
                sporcu_maskeli TEXT
            );
            """)
            cur.execute("""
            CREATE TABLE IF NOT EXISTS yaris_sonuclari (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id INTEGER REFERENCES events(id),
                canli_dosya_id INTEGER REFERENCES canli_yaris_dosyalari(id),
                sporcu_id INTEGER NOT NULL REFERENCES sporcular(id),
                kulup_id INTEGER REFERENCES kulupler(id),
                sporcu_kulup_tarihce_id INTEGER REFERENCES sporcu_kulup_tarihce(id),
                kaynak_turu TEXT,
                dosya_adi TEXT,
                sayfa_no INTEGER,
                satir_no INTEGER,
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
                giris_derecesi TEXT,
                sporcu_maskeli TEXT
            );
            """)
            cur.execute("""
            CREATE TABLE IF NOT EXISTS canli_yarislar (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id INTEGER REFERENCES events(id),
                musabaka_adi TEXT,
                sehir TEXT,
                tarih TEXT,
                canli_url TEXT NOT NULL,
                reglaman_linki TEXT,
                barajlar TEXT,
                durum TEXT DEFAULT 'BEKLIYOR',
                toplam_start_listesi INTEGER DEFAULT 0,
                islenen_start_listesi INTEGER DEFAULT 0,
                toplam_sonuc_listesi INTEGER DEFAULT 0,
                islenen_sonuc_listesi INTEGER DEFAULT 0,
                eklenen_kayit_sayisi INTEGER DEFAULT 0,
                hata_mesaji TEXT,
                son_islem_tarihi TEXT,
                olusturulma_tarihi TEXT,
                guncellenme_tarihi TEXT
            );
            """)
            cur.execute("""
            CREATE TABLE IF NOT EXISTS canli_yaris_dosyalari (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id INTEGER REFERENCES events(id),
                canli_yaris_id INTEGER REFERENCES canli_yarislar(id),
                dosya_adi TEXT NOT NULL,
                dosya_url TEXT,
                dosya_turu TEXT,
                yaris_no TEXT,
                mesafe INTEGER,
                stil TEXT,
                cinsiyet TEXT,
                yas_grubu TEXT,
                etag TEXT,
                last_modified TEXT,
                content_hash TEXT,
                dosya_boyutu INTEGER,
                durum TEXT DEFAULT 'BEKLIYOR',
                kayit_sayisi INTEGER DEFAULT 0,
                hata_mesaji TEXT,
                son_kontrol_tarihi DATETIME,
                son_islem_tarihi DATETIME,
                olusturulma_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP,
                guncellenme_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """)
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
                event_id INTEGER REFERENCES events(id),
                canli_dosya_id INTEGER REFERENCES canli_yaris_dosyalari(id),
                sporcu_id INTEGER NOT NULL REFERENCES sporcular(id),
                kulup_id INTEGER REFERENCES kulupler(id),
                sporcu_kulup_tarihce_id INTEGER REFERENCES sporcu_kulup_tarihce(id),
                kaynak_turu TEXT,
                dosya_adi TEXT,
                sayfa_no INTEGER,
                satir_no INTEGER,
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
                giris_derecesi TEXT,
                sporcu_maskeli TEXT
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

        self.event1 = Event.objects.create(
            musabaka_adi="TYF 11-12 Yaş Müsabakası",
            sehir="Ankara",
            yaris_tarihi_baslangic="2024-03-10"
        )
        self.yaris1 = YarisSonucu.objects.create(
            event=self.event1,
            sporcu=self.sporcu,
            kulup=self.kulup,
            sporcu_kulup_tarihce=self.tarihce_kulup,
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

        self.event2 = Event.objects.create(
            musabaka_adi="Okul Sporları Yıldızlar İl Birinciliği",
            sehir="Ankara",
            yaris_tarihi_baslangic="2024-05-15"
        )
        self.yaris2 = YarisSonucu.objects.create(
            event=self.event2,
            sporcu=self.sporcu,
            kulup=self.okul,
            sporcu_kulup_tarihce=self.tarihce_okul,
            yaris_no="2",
            mesafe=100,
            stil="Serbest",
            derece="1:05.20",
            derece_saniye=65.20,
            puan=380,
            sira="2"
        )

        # 50m Serbest ikinci yarış (daha yavaş derece)
        self.event3 = Event.objects.create(
            musabaka_adi="TYF Vize Müsabakası",
            sehir="Ankara",
            yaris_tarihi_baslangic="2024-01-20"
        )
        self.yaris3 = YarisSonucu.objects.create(
            event=self.event3,
            sporcu=self.sporcu,
            kulup=self.kulup,
            sporcu_kulup_tarihce=self.tarihce_kulup,
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
        # Değerlendirme metrikleri kontrolü
        self.assertIn('degerlendirme', response.context)
        deg = response.context['degerlendirme']
        self.assertEqual(deg['toplam_yaris'], 3)
        self.assertGreater(deg['toplam_puan'], 0)
        self.assertIn('best_race', deg)
        self.assertIn('stil_list', deg)
        self.assertContains(response, "Performans Notu:")
        self.assertContains(response, "Kürsü & Madalya Vitrini")
        self.assertContains(response, "Fark / Gelişim")

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

    def test_athlete_matcher_omer_kaya_vs_merve_kayak(self):
        """Ömer KAYA'nın Merve KAYAK ile asla eşleşmemesi ve cinsiyet / ad koruması testi."""
        from sonuclar.athlete_matcher import match_athlete

        merve = Sporcu.objects.create(
            sporcu_adi="Merve KAYAK",
            dogum_yili=2014,
            yas_dogum_yili="2014",
            cinsiyet="KADIN",
            birincil_kulup=self.kulup
        )
        omer = Sporcu.objects.create(
            sporcu_adi="Ömer KAYA",
            dogum_yili=2015,
            yas_dogum_yili="2015",
            cinsiyet="ERKEK",
            birincil_kulup=self.kulup
        )

        # 1. Erkek cinsiyeti ve Ömer, KAYA sorgusu Merve KAYAK ile eşleşmemeli
        res = match_athlete(name="Ömer, KAYA", birth_year_or_date=14, club=self.kulup.kulup_adi, gender="ERKEK")
        self.assertEqual(res["durum"], "basarili")
        self.assertNotEqual(res.get("bulunan_id"), merve.id)
        # Muhtemel eşleşmelerde de kadın sporcu bulunmamalı
        matched_ids = [m["id"] for m in res.get("muhtemel_eslesmeler", [])]
        self.assertNotIn(merve.id, matched_ids)
        # Kulübü ve adı tutan Ömer KAYA bulunmalı
        self.assertEqual(res.get("bulunan_id"), omer.id)

    def test_clean_athlete_name_tags(self):
        """(FD), (TK), (TD), ferdi vb. etiketlerin ve artık karakterlerin temizlenme testi."""
        from sonuclar.athlete_matcher import clean_athlete_name_tags

        test_cases = [
            ("ALİ VELİ (FD)", "ALİ VELİ"),
            ("(TK) AYŞE YILMAZ", "AYŞE YILMAZ"),
            ("D***Z K**T (fd)", "D***Z K**T"),
            ("M*** K*** (TK)", "M*** K***"),
            ("CAN ÖZ (FD.)", "CAN ÖZ"),
            ("BERK YILMAZ [TK]", "BERK YILMAZ"),
            ("EMİR ASLAN (ferdi)", "EMİR ASLAN"),
            ("DENİZ KAYA (TD)", "DENİZ KAYA"),
            ("D***Z K**T", "D***Z K**T"),
            ("ÖMER KAYA FD", "ÖMER KAYA"),
            ("TK CANSU DEMİR", "CANSU DEMİR"),
            ("( Metehan İŞLER", "Metehan İŞLER"),
            ("(f5) Mehmet P'lat SARI", "Mehmet P'lat SARI"),
            ("(F) *s* ***ü ü*k", "*s* ***ü ü*k"),
            ("(Fd) *r*r *u*a ** s**", "*r*r *u*a ** s**"),
            ("(F) *z*r *er** *alda *ur*az", "*z*r *er** *alda *ur*az"),
            ("F***N YILMAZ", "F***N YILMAZ"),
        ]
        for raw, expected in test_cases:
            self.assertEqual(clean_athlete_name_tags(raw), expected)

    def test_clean_club_name_tags(self):
        """Kulüp isimlerindeki (FD), (TK), (TD), ferdi vb. etiketlerin temizlenme testi."""
        from sonuclar.athlete_matcher import clean_club_name_tags

        test_cases = [
            ("ANKARA DSİ SPOR KULÜBÜ (TK)", "ANKARA DSİ SPOR KULÜBÜ"),
            ("ANKARA DSİ SPOR KULÜBÜ (FD)", "ANKARA DSİ SPOR KULÜBÜ"),
            ("(TK) ANKARA DSİ SPOR KULÜBÜ", "ANKARA DSİ SPOR KULÜBÜ"),
            ("(FD) ANKARA DSİ SPOR KULÜBÜ", "ANKARA DSİ SPOR KULÜBÜ"),
            ("(Tk) Istek Ankara Okulları", "Istek Ankara Okulları"),
            ("(F) Özel Arı Okulları", "Özel Arı Okulları"),
            ("Özel Ankara Abc Anadolu Lisesi (A)", "Özel Ankara Abc Anadolu Lisesi"),
            ("ÖZEL ÇANKAYA FEN LİSESİ (TK)", "ÖZEL ÇANKAYA FEN LİSESİ"),
            ("TED ANKARA KOLEJLİLER [TK]", "TED ANKARA KOLEJLİLER"),
            ("GALATASARAY SPOR KULÜBÜ - TK", "GALATASARAY SPOR KULÜBÜ"),
            ("FENERBAHÇE SPOR KULÜBÜ / FD", "FENERBAHÇE SPOR KULÜBÜ"),
            ("ENKA SPOR KULÜBÜ (TD)", "ENKA SPOR KULÜBÜ"),
            ("BURSA BÜYÜKŞEHİR BLD (FERDİ)", "BURSA BÜYÜKŞEHİR BLD"),
            ("İZMİR YÜZME (TASNİF DIŞI)", "İZMİR YÜZME"),
            ("ANKARA DSİ SPOR KULÜBÜ (TK-1)", "ANKARA DSİ SPOR KULÜBÜ"),
            ("İSTANBUL ÇEVRE KULÜBÜ (OKUL)", "İSTANBUL ÇEVRE KULÜBÜ"),
        ]
        for raw, expected in test_cases:
            self.assertEqual(clean_club_name_tags(raw), expected)

    def test_masked_athlete_exact_1to1_matching(self):
        """Her '*' tek harf olacak şekilde 1-e-1 maskeli sporcu eşleştirme testi."""
        from sonuclar.athlete_matcher import match_athlete

        deniz = Sporcu.objects.create(
            sporcu_adi="Deniz KURT",
            dogum_yili=2012,
            yas_dogum_yili="2012",
            cinsiyet="ERKEK",
            birincil_kulup=self.kulup
        )
        denizhan = Sporcu.objects.create(
            sporcu_adi="Denizhan KURT",
            dogum_yili=2012,
            yas_dogum_yili="2012",
            cinsiyet="ERKEK",
            birincil_kulup=self.kulup
        )
        ali = Sporcu.objects.create(
            sporcu_adi="Ali KAYA",
            dogum_yili=2012,
            yas_dogum_yili="2012",
            cinsiyet="ERKEK",
            birincil_kulup=self.kulup
        )

        # 1. 'D***Z K**T (FD)' (5 harf + 4 harf) Deniz KURT ile eşleşmeli, Denizhan (8 harf) ile eşleşmemeli!
        res1 = match_athlete("D***Z K**T (FD)", birth_year_or_date=2012, gender="ERKEK")
        self.assertEqual(res1["durum"], "basarili")
        self.assertEqual(res1["sonuc"], "tam_eslesme")
        self.assertEqual(res1["bulunan_id"], deniz.id)

        # 2. 'D******N K**T' (8 harf + 4 harf) Denizhan KURT ile eşleşmeli!
        res2 = match_athlete("D******N K**T", birth_year_or_date=2012, gender="ERKEK")
        self.assertEqual(res2["durum"], "basarili")
        self.assertEqual(res2["sonuc"], "tam_eslesme")
        self.assertEqual(res2["bulunan_id"], denizhan.id)

        # 3. '(TK) A** K**A' Ali KAYA ile eşleşmeli
        res3 = match_athlete("(TK) A** K**A", birth_year_or_date=2012, gender="ERKEK")
        self.assertEqual(res3["durum"], "basarili")
        self.assertEqual(res3["sonuc"], "tam_eslesme")
        self.assertEqual(res3["bulunan_id"], ali.id)

        # 4. 'Hanzade **o**n' (Türkçe karakter Ğ toleransı ile) Hanzade DOĞAN ile eşleşmeli
        hanzade = Sporcu.objects.create(
            sporcu_adi="Hanzade DOĞAN",
            dogum_yili=2011,
            yas_dogum_yili="2011",
            cinsiyet="KADIN",
            birincil_kulup=self.kulup
        )
        res4 = match_athlete("Hanzade **o**n", birth_year_or_date=2011, gender="KADIN")
        self.assertEqual(res4["durum"], "basarili")
        self.assertEqual(res4["sonuc"], "tam_eslesme")
        self.assertEqual(res4["bulunan_id"], hanzade.id)

    def test_api_canli_aktar_matching_and_deduplication(self):
        """GitHub Action start ve sonuç aktarımı, sporcu eşleştirmesi ve mükerrerlik koruması testi."""
        url = reverse('sonuclar:api_canli_aktar')

        # 1. Aşama: Start Listesi Gönderimi
        start_payload = {
            "tur": "start_listesi",
            "musabaka_adi": "TYF Bölge Müsabakası",
            "sehir": "Ankara",
            "yaris_tarihi_baslangic": "2026-05-01",
            "yaris_no": "10",
            "cinsiyet": "Erkek",
            "mesafe": 50,
            "stil": "Serbest",
            "kayitlar": [
                {
                    "seri": "Seri 3",
                    "kulvar": 4,
                    "sporcu": "cinar koysuren",  # OCR veya küçük harf varyasyonu (Ahmet / Çınar eşleşmesi)
                    "dogum_yili": "14",
                    "kulup": "Gazi Üniversitesi Spor Kulübü",  # Yeni Kulüp
                    "giris_derecesi": "32.50"
                }
            ]
        }

        resp1 = self.client.post(url, data=json.dumps(start_payload), content_type='application/json')
        self.assertEqual(resp1.status_code, 200)
        data1 = resp1.json()
        self.assertEqual(data1['durum'], 'basarili')
        self.assertEqual(data1['istatistikler']['eslesen_sporcu_sayisi'], 1)  # Çınar eşleşti
        self.assertEqual(data1['istatistikler']['yeni_kulup_sayisi'], 1)      # Yeni kulüp eklendi
        self.assertEqual(data1['istatistikler']['eklenen_sonuc_sayisi'], 1)    # 1 start kaydı eklendi

        # Kaydın "Bekleniyor" olarak eklendiğini doğrula
        yaris = YarisSonucu.objects.get(sporcu=self.cinar, event__musabaka_adi="TYF Bölge Müsabakası", mesafe=50, stil="Serbest")
        self.assertEqual(yaris.derece, "Bekleniyor")
        self.assertEqual(yaris.kulvar, 4)

        # 2. Aşama: Yarış Sonucu Gönderimi (Start Listesindeki kaydı güncellemeli, mükerrer yaratmamalı)
        result_payload = {
            "tur": "sonuc_listesi",
            "musabaka_adi": "TYF Bölge Müsabakası",
            "sehir": "Ankara",
            "yaris_tarihi_baslangic": "2026-05-01",
            "yaris_no": "10",
            "cinsiyet": "Erkek",
            "mesafe": 50,
            "stil": "Serbest",
            "kayitlar": [
                {
                    "sira": "1",
                    "sporcu": "Çınar KÖYSÜREN",
                    "dogum_yili": 2014,
                    "kulup": "Gazi Üniversitesi Spor Kulübü",
                    "derece": "31.90",
                    "puan": 290
                }
            ]
        }

        resp2 = self.client.post(url, data=json.dumps(result_payload), content_type='application/json')
        self.assertEqual(resp2.status_code, 200)
        data2 = resp2.json()
        self.assertEqual(data2['istatistikler']['guncellenen_sonuc_sayisi'], 1)  # Start -> Sonuç güncellendi
        self.assertEqual(data2['istatistikler']['eklenen_sonuc_sayisi'], 0)      # Yeni kayıt OLUŞMADI (Mükerrerlik engellendi)

        yaris.refresh_from_db()
        self.assertEqual(yaris.derece, "31.90")
        self.assertEqual(yaris.puan, 290)
        self.assertEqual(yaris.sira, "1")

        # Toplam yarış sayısının sadece 1 kez arttığını doğrula
        self.assertEqual(YarisSonucu.objects.filter(sporcu=self.cinar, event__musabaka_adi="TYF Bölge Müsabakası").count(), 1)

        # 3. Aşama: Aynı Sonucun Tekrar Gönderilmesi (GitHub Actions tekrar çalıştığında)
        resp3 = self.client.post(url, data=json.dumps(result_payload), content_type='application/json')
        self.assertEqual(resp3.status_code, 200)
        data3 = resp3.json()
        self.assertEqual(data3['istatistikler']['mukerrer_atlanilan_sayisi'], 1) # Birebir aynı olduğu için atlandı
        self.assertEqual(data3['istatistikler']['eklenen_sonuc_sayisi'], 0)
        self.assertEqual(data3['istatistikler']['guncellenen_sonuc_sayisi'], 0)

        # 4. Aşama: Tamamen Yeni Bir Sporcu Geldiğinde
        new_swimmer_payload = {
            "tur": "sonuc_listesi",
            "musabaka_adi": "Okul Sporları İl Seçmesi",
            "yaris_tarihi_baslangic": "2026-05-10",
            "mesafe": 100,
            "stil": "Kurbağalama",
            "kayitlar": [
                {
                    "sira": "3",
                    "sporcu": "Bora KORKMAZ",
                    "dogum_yili": "2013",
                    "kulup": "Özel Ankara İlkokulu",
                    "derece": "1:25.40",
                    "puan": 240
                }
            ]
        }
        resp4 = self.client.post(url, data=json.dumps(new_swimmer_payload), content_type='application/json')
        self.assertEqual(resp4.status_code, 200)
        data4 = resp4.json()
        self.assertEqual(data4['istatistikler']['yeni_sporcu_sayisi'], 1)
        self.assertEqual(data4['istatistikler']['yeni_kulup_sayisi'], 1)
        self.assertEqual(data4['istatistikler']['eklenen_sonuc_sayisi'], 1)

        # Yeni sporcu ve okul kaydının oluştuğunu doğrula
        bora = Sporcu.objects.get(sporcu_adi="Bora KORKMAZ")
        self.assertEqual(bora.dogum_yili, 2013)
        self.assertEqual(bora.okul(), "Özel Ankara İlkokulu")

    def test_event_modeli_ve_yaris_iliskisi(self):
        """Event modeli oluşturma ve YarisSonucu ilişkisi testi."""
        event = Event.objects.create(
            musabaka_adi="İstanbul İl Baraj Geçme Müsabakası",
            sehir="İstanbul",
            yaris_tarihi_baslangic="2026-06-01",
            kaynak_turu="METIN_PDF"
        )
        self.assertIsNotNone(event.id)
        self.assertEqual(str(event), "İstanbul İl Baraj Geçme Müsabakası (İstanbul / 2026-06-01)")

        sporcu = Sporcu.objects.create(sporcu_adi="Deniz Aktaş", dogum_yili=2012)
        yaris = YarisSonucu.objects.create(
            event=event,
            sporcu=sporcu,
            mesafe=100,
            stil="Serbest",
            derece="1:02.15"
        )
        self.assertEqual(yaris.event.id, event.id)
        self.assertEqual(yaris.musabaka_adi, "İstanbul İl Baraj Geçme Müsabakası")
        self.assertEqual(yaris.sehir, "İstanbul")

    def test_canli_dosya_ve_id_ile_sonuc_guncelleme(self):
        """Start listesindeki id üzerinden doğrudan sonuç güncelleme ve dosya takibi testi."""
        event = Event.objects.create(
            musabaka_adi="Canlı Test Müsabakası",
            sehir="İzmir",
            yaris_tarihi_baslangic="2026-06-15"
        )
        canli_yaris = CanliYaris.objects.create(
            event=event,
            musabaka_adi="Canlı Test Müsabakası",
            canli_url="https://canli.tyf.gov.tr/izmir/cs-9999/"
        )

        # 1. Start listesi aktarımı
        start_payload = {
            "tur": "start_listesi",
            "canli_yaris_id": canli_yaris.id,
            "musabaka_adi": event.musabaka_adi,
            "dosya_adi": "StartList_1.pdf",
            "dosya_url": "https://canli.tyf.gov.tr/izmir/cs-9999/StartList_1.pdf",
            "etag": "w/123456",
            "last_modified": "Mon, 15 Jun 2026 09:00:00 GMT",
            "content_hash": "a1b2c3d4e5f67890",
            "yaris_no": "1",
            "mesafe": 50,
            "stil": "Serbest",
            "kayitlar": [
                {
                    "seri": "2",
                    "kulvar": 3,
                    "sporcu": self.sporcu.sporcu_adi,
                    "dogum_yili": self.sporcu.dogum_yili,
                    "kulup": self.kulup.kulup_adi,
                    "giris_derecesi": "29.80"
                }
            ]
        }
        res_start = self.client.post(reverse('sonuclar:api_canli_aktar'), data=json.dumps(start_payload), content_type='application/json')
        self.assertEqual(res_start.status_code, 200)

        # Start kaydını kontrol et
        yaris_kaydi = YarisSonucu.objects.filter(event=event, yaris_no="1", sporcu=self.sporcu).first()
        self.assertIsNotNone(yaris_kaydi)
        self.assertEqual(yaris_kaydi.derece, "Bekleniyor")
        self.assertIsNotNone(yaris_kaydi.canli_dosya)
        self.assertEqual(yaris_kaydi.canli_dosya.dosya_adi, "StartList_1.pdf")
        self.assertEqual(yaris_kaydi.canli_dosya.content_hash, "a1b2c3d4e5f67890")

        # 2. Start listesi sporcularını çeken API'yi test et
        res_swimmers = self.client.get(reverse('sonuclar:api_canli_startlist_sporculari') + f"?event_id={event.id}&yaris_no=1")
        self.assertEqual(res_swimmers.status_code, 200)
        swimmers_data = res_swimmers.json()
        self.assertEqual(swimmers_data["durum"], "basarili")
        self.assertEqual(len(swimmers_data["sporcular"]), 1)
        target_swimmer_id = swimmers_data["sporcular"][0]["id"]
        self.assertEqual(target_swimmer_id, yaris_kaydi.id)

        # 3. Dosya kontrol API'sini test et
        res_check = self.client.get(reverse('sonuclar:api_canli_dosya_kontrol') + f"?event_id={event.id}&dosya_adi=StartList_1.pdf")
        self.assertEqual(res_check.status_code, 200)
        check_data = res_check.json()
        self.assertTrue(check_data["islendi_mi"])
        self.assertEqual(check_data["content_hash"], "a1b2c3d4e5f67890")

        # 4. Sonuç listesi aktarımı (Gemini'nin bulduğu ID ile doğrudan güncelleme + yeni yedek sporcu)
        result_payload = {
            "tur": "sonuc_listesi",
            "canli_yaris_id": canli_yaris.id,
            "musabaka_adi": event.musabaka_adi,
            "dosya_adi": "ResultList_1.pdf",
            "dosya_url": "https://canli.tyf.gov.tr/izmir/cs-9999/ResultList_1.pdf",
            "etag": "w/987654",
            "last_modified": "Mon, 15 Jun 2026 11:30:00 GMT",
            "content_hash": "f6e5d4c3b2a10000",
            "yaris_no": "1",
            "mesafe": 50,
            "stil": "Serbest",
            "kayitlar": [
                {
                    "id": target_swimmer_id,  # DOĞRUDAN START KAYDININ ID'Sİ
                    "sira": "1",
                    "derece": "28.15",
                    "puan": 410,
                    "baraj": "A2"
                }
            ],
            "yeni_sporcular": [
                {
                    "sira": "2",
                    "sporcu": "Yeni Yüzücü",
                    "dogum_yili": "2013",
                    "kulup": self.kulup.kulup_adi,
                    "derece": "28.90",
                    "puan": 380
                }
            ]
        }
        res_result = self.client.post(reverse('sonuclar:api_canli_aktar'), data=json.dumps(result_payload), content_type='application/json')
        self.assertEqual(res_result.status_code, 200)

        # Mevcut kaydın güncellendiğini doğrula
        yaris_kaydi.refresh_from_db()
        self.assertEqual(yaris_kaydi.derece, "28.15")
        self.assertEqual(yaris_kaydi.sira, "1")
        self.assertEqual(yaris_kaydi.puan, 410)
        self.assertEqual(yaris_kaydi.kaynak_turu, "CANLI_SONUC")
        self.assertEqual(yaris_kaydi.dosya_adi, "ResultList_1.pdf")
        self.assertEqual(yaris_kaydi.canli_dosya.dosya_adi, "ResultList_1.pdf")

        # Yedek/yeni sporcunun da eklendiğini doğrula
        yeni_sonuc = YarisSonucu.objects.filter(event=event, yaris_no="1", sporcu__sporcu_adi__iexact="Yeni Yüzücü").first()
        self.assertIsNotNone(yeni_sonuc)
        self.assertEqual(yeni_sonuc.derece, "28.90")
        self.assertEqual(yeni_sonuc.sira, "2")


class CanliYarisTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        with connection.cursor() as cur:
            cur.execute("""
            CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                musabaka_adi TEXT NOT NULL,
                sehir TEXT,
                yaris_tarihi_ham TEXT,
                yaris_tarihi_baslangic TEXT,
                yaris_tarihi_bitis TEXT,
                kaynak_turu TEXT,
                toplam_yaris_sayisi INTEGER DEFAULT 0,
                toplam_sporcu_sayisi INTEGER DEFAULT 0,
                olusturulma_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP,
                guncellenme_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """)
            cur.execute("""
            CREATE TABLE IF NOT EXISTS canli_yarislar (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id INTEGER REFERENCES events(id),
                musabaka_adi TEXT,
                sehir TEXT,
                tarih TEXT,
                canli_url TEXT NOT NULL,
                reglaman_linki TEXT,
                barajlar TEXT,
                durum TEXT DEFAULT 'BEKLIYOR',
                toplam_start_listesi INTEGER DEFAULT 0,
                islenen_start_listesi INTEGER DEFAULT 0,
                toplam_sonuc_listesi INTEGER DEFAULT 0,
                islenen_sonuc_listesi INTEGER DEFAULT 0,
                eklenen_kayit_sayisi INTEGER DEFAULT 0,
                hata_mesaji TEXT,
                son_islem_tarihi TEXT,
                olusturulma_tarihi TEXT,
                guncellenme_tarihi TEXT
            );
            """)
            cur.execute("""
            CREATE TABLE IF NOT EXISTS canli_yaris_dosyalari (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id INTEGER REFERENCES events(id),
                canli_yaris_id INTEGER REFERENCES canli_yarislar(id),
                dosya_adi TEXT NOT NULL,
                dosya_url TEXT,
                dosya_turu TEXT,
                yaris_no TEXT,
                mesafe INTEGER,
                stil TEXT,
                cinsiyet TEXT,
                yas_grubu TEXT,
                etag TEXT,
                last_modified TEXT,
                content_hash TEXT,
                dosya_boyutu INTEGER,
                durum TEXT DEFAULT 'BEKLIYOR',
                kayit_sayisi INTEGER DEFAULT 0,
                hata_mesaji TEXT,
                son_kontrol_tarihi DATETIME,
                son_islem_tarihi DATETIME,
                olusturulma_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP,
                guncellenme_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """)
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
                event_id INTEGER REFERENCES events(id),
                canli_dosya_id INTEGER REFERENCES canli_yaris_dosyalari(id),
                sporcu_id INTEGER NOT NULL REFERENCES sporcular(id),
                kulup_id INTEGER REFERENCES kulupler(id),
                sporcu_kulup_tarihce_id INTEGER REFERENCES sporcu_kulup_tarihce(id),
                kaynak_turu TEXT,
                dosya_adi TEXT,
                sayfa_no INTEGER,
                satir_no INTEGER,
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
                giris_derecesi TEXT,
                sporcu_maskeli TEXT
            );
            """)

    def setUp(self):
        self.client = Client()

    def test_canli_yaris_ekleme_ve_listeleme(self):
        """Kullanıcının canlı yarış eklemesi ve sayfada listelenmesi testi."""
        res_get = self.client.get(reverse('sonuclar:canli_yaris_listesi'))
        self.assertEqual(res_get.status_code, 200)

        # Yeni yarış post et
        test_url = "https://canli.tyf.gov.tr/istanbul/cs-1005380/"
        res_post = self.client.post(reverse('sonuclar:canli_yaris_listesi'), {
            'canli_url': test_url,
            'musabaka_adi': 'Test Müsabakası'
        }, follow=True)
        self.assertEqual(res_post.status_code, 200)

        # Veritabanında kontrol et
        yaris = CanliYaris.objects.filter(canli_url=test_url).first()
        self.assertIsNotNone(yaris)
        self.assertEqual(yaris.durum, 'BEKLIYOR')

        # Silme testi
        res_del = self.client.post(reverse('sonuclar:canli_yaris_sil', args=[yaris.id]), follow=True)
        self.assertEqual(res_del.status_code, 200)
        self.assertFalse(CanliYaris.objects.filter(id=yaris.id).exists())

    def test_canli_yaris_sil_ile_dosya_ve_sonuclarin_silinmesi(self):
        """Canlı yarış silindiğinde bağlı dosyalar, sonuçlar ve tekil event kaydının silinmesi testi."""
        event = Event.objects.create(
            musabaka_adi="Silinecek Canlı Yarış Müsabakası",
            sehir="İzmir",
            kaynak_turu="CANLI_TAKIP"
        )
        canli = CanliYaris.objects.create(
            event=event,
            musabaka_adi=event.musabaka_adi,
            canli_url="https://canli.tyf.gov.tr/izmir/cs-999/",
            durum="TAMAMLANDI"
        )
        dosya = CanliYarisDosya.objects.create(
            event=event,
            canli_yaris=canli,
            dosya_adi="ResultList_1.pdf",
            dosya_turu="SONUC_LISTESI"
        )
        kulup = Kulup.objects.create(kulup_adi="Silme Test Kulübü", toplam_yaris_sayisi=1)
        sporcu = Sporcu.objects.create(
            sporcu_adi="Silme Test Sporcusu",
            birincil_kulup=kulup,
            toplam_yaris_sayisi=1
        )
        sonuc = YarisSonucu.objects.create(
            event=event,
            canli_dosya=dosya,
            sporcu=sporcu,
            kulup=kulup,
            kaynak_turu="CANLI_SONUC",
            dosya_adi="ResultList_1.pdf",
            mesafe=50,
            stil="Serbest",
            derece="25.50"
        )

        self.assertEqual(CanliYaris.objects.filter(id=canli.id).count(), 1)
        self.assertEqual(CanliYarisDosya.objects.filter(id=dosya.id).count(), 1)
        self.assertEqual(YarisSonucu.objects.filter(id=sonuc.id).count(), 1)
        self.assertEqual(Event.objects.filter(id=event.id).count(), 1)

        # POST ile silme çağrısı yap
        res = self.client.post(reverse('sonuclar:canli_yaris_sil', args=[canli.id]), follow=True)
        self.assertEqual(res.status_code, 200)

        # Canlı yarış, dosya, sonuç ve ilgili tekil event silinmiş olmalı
        self.assertFalse(CanliYaris.objects.filter(id=canli.id).exists())
        self.assertFalse(CanliYarisDosya.objects.filter(id=dosya.id).exists())
        self.assertFalse(YarisSonucu.objects.filter(id=sonuc.id).exists())
        self.assertFalse(Event.objects.filter(id=event.id).exists())

        # Sporcu ve kulüp sayaçları güncellenmiş olmalı
        sporcu.refresh_from_db()
        kulup.refresh_from_db()
        self.assertEqual(sporcu.toplam_yaris_sayisi, 0)
        self.assertEqual(kulup.toplam_yaris_sayisi, 0)

    def test_api_canli_yaris_ekle_ve_bekleyen_kontrol(self):
        """TYF tarayıcısı ile gelen yarışların API üzerinden eklenmesi ve bekleyen yarış kontrolü."""
        test_url = "https://canli.tyf.gov.tr/ankara/cs-261026/"
        payload = {
            "canli_url": test_url,
            "musabaka_adi": "Ankara TYF Il Temsilciligi Canli Yaris",
            "sehir": "Ankara",
            "tarih": "26-28 KASIM 2026"
        }
        # 1. API üzerinden yarış ekle
        res = self.client.post(
            reverse('sonuclar:api_canli_yaris_ekle'),
            data=json.dumps(payload),
            content_type="application/json"
        )
        self.assertEqual(res.status_code, 201)
        data = res.json()
        self.assertEqual(data.get("durum"), "basarili")
        self.assertTrue(data.get("yeni_kayit"))

        # Tekrar aynı URL eklenirse yeni_kayit False olmalı
        res_dup = self.client.post(
            reverse('sonuclar:api_canli_yaris_ekle'),
            data=json.dumps(payload),
            content_type="application/json"
        )
        self.assertEqual(res_dup.status_code, 200)
        self.assertFalse(res_dup.json().get("yeni_kayit"))

        # 2. Bekleyen yarışları tekil endpoint (/api/canli-bekleyen-yaris/) üzerinden sorgula
        res_bekleyen = self.client.get(reverse('sonuclar:api_canli_bekleyen_yaris'))
        self.assertEqual(res_bekleyen.status_code, 200)
        bekleyen_data = res_bekleyen.json()
        self.assertIn("yarislar", bekleyen_data)
        urls = [y["canli_url"] for y in bekleyen_data["yarislar"]]
        self.assertIn(test_url, urls)

        # 3. Değerlendirme testi
        from sonuclar.live_engine import evaluate_single_meet
        should_run, reason = evaluate_single_meet(bekleyen_data["yarislar"][0])
        self.assertTrue(should_run)
        self.assertTrue("Start listeleri" in reason)


class MusabakaAnalizTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        with connection.cursor() as cur:
            cur.execute("""
            CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                musabaka_adi TEXT NOT NULL,
                sehir TEXT,
                yaris_tarihi_ham TEXT,
                yaris_tarihi_baslangic TEXT,
                yaris_tarihi_bitis TEXT,
                kaynak_turu TEXT,
                toplam_yaris_sayisi INTEGER DEFAULT 0,
                toplam_sporcu_sayisi INTEGER DEFAULT 0,
                olusturulma_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP,
                guncellenme_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """)
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
            CREATE TABLE IF NOT EXISTS yaris_sonuclari (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id INTEGER REFERENCES events(id),
                canli_dosya_id INTEGER,
                sporcu_id INTEGER NOT NULL REFERENCES sporcular(id),
                kulup_id INTEGER REFERENCES kulupler(id),
                sporcu_kulup_tarihce_id INTEGER,
                kaynak_turu TEXT,
                dosya_adi TEXT,
                sayfa_no INTEGER,
                satir_no INTEGER,
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
                giris_derecesi TEXT,
                sporcu_maskeli TEXT
            );
            """)

    def setUp(self):
        self.client = Client()
        self.event = Event.objects.create(
            musabaka_adi="Test Analiz Müsabakası",
            sehir="İstanbul",
            yaris_tarihi_baslangic="2026-05-10"
        )
        self.kulup1 = Kulup.objects.create(kulup_adi="Fenerbahçe")
        self.kulup2 = Kulup.objects.create(kulup_adi="Galatasaray")
        self.sporcu1 = Sporcu.objects.create(sporcu_adi="Ahmet Yılmaz", dogum_yili=2010, cinsiyet="Erkek", birincil_kulup=self.kulup1)
        self.sporcu2 = Sporcu.objects.create(sporcu_adi="Ayşe Demir", dogum_yili=2011, cinsiyet="Kadın", birincil_kulup=self.kulup2)

        # Yarış sonuçları
        YarisSonucu.objects.create(
            event=self.event,
            sporcu=self.sporcu1,
            kulup=self.kulup1,
            yaris_no="1",
            mesafe=50,
            stil="Serbest",
            cinsiyet="Erkek",
            giris_derecesi="26.00",
            derece="25.50",
            derece_saniye=25.50,
            sira="1",
            puan=600,
            baraj="EVET"
        )
        YarisSonucu.objects.create(
            event=self.event,
            sporcu=self.sporcu2,
            kulup=self.kulup2,
            yaris_no="2",
            mesafe=100,
            stil="Sırtüstü",
            cinsiyet="Kadın",
            giris_derecesi="1:04.00",
            derece="1:05.20",
            derece_saniye=65.20,
            sira="1",
            puan=550,
            baraj="EVET"
        )

    def test_musabaka_analiz_genel(self):
        """Müsabaka analiz sayfasının genel özet ile 200 dönmesi ve metriklerin doğrulanması."""
        url = reverse('sonuclar:musabaka_analiz', args=[self.event.id])
        res = self.client.get(url)
        self.assertEqual(res.status_code, 200)
        self.assertContains(res, "Test Analiz Müsabakası")
        self.assertEqual(res.context['toplam_puan'], 1150)
        self.assertEqual(res.context['toplam_derece'], 2)
        self.assertEqual(res.context['toplam_sporcu'], 2)
        self.assertEqual(res.context['toplam_kulup'], 2)
        self.assertEqual(len(res.context['club_rankings']), 2)
        # 1. kulüp Fenerbahçe olmalı (600 puan)
        self.assertEqual(res.context['club_rankings'][0]['kulup__kulup_adi'], "Fenerbahçe")
        # Giriş vs Çıkış Analizi
        self.assertTrue(res.context['has_giris_analizi'])
        self.assertEqual(res.context['toplam_karsilastirilan'], 2)
        self.assertEqual(res.context['gelistiren_count'], 1)
        self.assertEqual(res.context['gerileyen_count'], 1)
        self.assertEqual(res.context['gelisim_orani'], 50.0)
        self.assertEqual(len(res.context['en_cok_gelistirenler']), 1)
        self.assertEqual(res.context['en_cok_gelistirenler'][0]['fark'], -0.5)

    def test_musabaka_analiz_yaris_filtresi(self):
        """Tekil yarış filtresinin (yaris_no=1) doğru çalışması ve kürsünün gelmesi."""
        url = reverse('sonuclar:musabaka_analiz', args=[self.event.id])
        res = self.client.get(url, {'yaris_no': '1'})
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.context['secili_yaris_no'], '1')
        self.assertEqual(res.context['toplam_puan'], 600)
        self.assertEqual(len(res.context['yaris_podium']), 1)
        self.assertEqual(res.context['yaris_podium'][0].sporcu.sporcu_adi, "Ahmet Yılmaz")

    def test_musabaka_analiz_htmx_partial(self):
        """HTMX isteğinde sadece partial içeriğin dönmesi."""
        url = reverse('sonuclar:musabaka_analiz', args=[self.event.id])
        res = self.client.get(url, HTTP_HX_REQUEST='true')
        self.assertEqual(res.status_code, 200)
        self.assertTemplateUsed(res, 'sonuclar/partials/musabaka_analiz_content.html')

    def test_musabaka_kulup_modal(self):
        """Takıma tıklandığında kulüp müsabaka analiz modalının başarıyla dönmesi."""
        url = reverse('sonuclar:musabaka_kulup_modal', args=[self.event.id, self.kulup1.id])
        res = self.client.get(url, HTTP_HX_REQUEST='true')
        self.assertEqual(res.status_code, 200)
        self.assertTemplateUsed(res, 'sonuclar/partials/kulup_musabaka_modal.html')
        self.assertEqual(res.context['kulup'].kulup_adi, "Fenerbahçe")
        self.assertEqual(res.context['toplam_yaris'], 1)
        self.assertEqual(res.context['toplam_puan'], 600)
        self.assertEqual(len(res.context['athletes_list']), 1)
        self.assertEqual(res.context['athletes_list'][0]['sporcu'].sporcu_adi, "Ahmet Yılmaz")

    def test_musabaka_sporcu_modal_ve_baraj_hayir_gosterilmez(self):
        """Baraj değeri HAYIR olan yarışlarda HAYIR yazılmaması, boş / tire bırakılması kontrolü."""
        # baraj='HAYIR' olan yeni bir yarış sonucu ekleyelim
        YarisSonucu.objects.create(
            event=self.event,
            sporcu=self.sporcu1,
            kulup=self.kulup1,
            yaris_no="3",
            mesafe=200,
            stil="Serbest",
            cinsiyet="Erkek",
            derece="2:10.00",
            derece_saniye=130.0,
            sira="4",
            puan=450,
            baraj="HAYIR"
        )
        # Sporcu modalı
        url = reverse('sonuclar:musabaka_sporcu_modal', args=[self.event.id, self.sporcu1.id])
        res = self.client.get(url, HTTP_HX_REQUEST='true')
        self.assertEqual(res.status_code, 200)
        content = res.content.decode('utf-8')
        self.assertNotIn('>HAYIR<', content)
        self.assertNotIn('>Hayır<', content)

        # Kulüp modalı
        kulup_url = reverse('sonuclar:musabaka_kulup_modal', args=[self.event.id, self.kulup1.id])
        res_kulup = self.client.get(kulup_url, HTTP_HX_REQUEST='true')
        content_kulup = res_kulup.content.decode('utf-8')
        self.assertNotIn('>HAYIR<', content_kulup)
        self.assertNotIn('>Hayır<', content_kulup)

        # Tekil yarış analiz tablosu
        analiz_url = reverse('sonuclar:musabaka_analiz', args=[self.event.id])
        res_analiz = self.client.get(analiz_url, {'yaris_no': '3'}, HTTP_HX_REQUEST='true')
        content_analiz = res_analiz.content.decode('utf-8')
        self.assertNotIn('>HAYIR<', content_analiz)
        self.assertNotIn('>Hayır<', content_analiz)
