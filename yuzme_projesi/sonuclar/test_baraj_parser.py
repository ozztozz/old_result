from django.test import SimpleTestCase

from sonuclar.local_baraj_parser import (
    _parse_age_header,
    _parse_event_cell,
    _parse_time_to_seconds,
    evaluate_baraj_for_result,
    parse_baraj_pdf_bytes,
)


class BarajParserUnitTests(SimpleTestCase):
    def setUp(self):
        self.sample_barajlar = {
            "baraj_adi": "Test Reglaman",
            "barajlar": [
                {
                    "havuz": "50m",
                    "baraj_turu": "Katılım Barajı",
                    "cinsiyet": "Erkek",
                    "yas_etiketi": "13 YAŞ",
                    "dogum_yillari": [2014],
                    "max_dogum_yili": None,
                    "min_yas": 13,
                    "max_yas": 13,
                    "mesafe": 50,
                    "stil": "Serbest",
                    "sure": "00:28,63",
                    "sure_saniye": 28.63,
                },
                {
                    "havuz": "50m",
                    "baraj_turu": "Harcırah Barajı",
                    "cinsiyet": "Erkek",
                    "yas_etiketi": "13 YAŞ",
                    "dogum_yillari": [2014],
                    "max_dogum_yili": None,
                    "min_yas": 13,
                    "max_yas": 13,
                    "mesafe": 50,
                    "stil": "Serbest",
                    "sure": "00:27,55",
                    "sure_saniye": 27.55,
                },
                {
                    "havuz": "25m",
                    "baraj_turu": "Katılım Barajı",
                    "cinsiyet": "Erkek",
                    "yas_etiketi": "13 YAŞ",
                    "dogum_yillari": [2014],
                    "max_dogum_yili": None,
                    "min_yas": 13,
                    "max_yas": 13,
                    "mesafe": 50,
                    "stil": "Serbest",
                    "sure": "00:27,98",
                    "sure_saniye": 27.98,
                },
                {
                    "havuz": "50m",
                    "baraj_turu": "Katılım Barajı",
                    "cinsiyet": "Kadın",
                    "yas_etiketi": "16-18 YAŞ",
                    "dogum_yillari": [2009, 2010, 2011],
                    "max_dogum_yili": None,
                    "min_yas": 16,
                    "max_yas": 18,
                    "mesafe": 100,
                    "stil": "Kurbağalama",
                    "sure": "01:17,34",
                    "sure_saniye": 77.34,
                },
                {
                    "havuz": "50m",
                    "baraj_turu": "Katılım Barajı",
                    "cinsiyet": "Erkek",
                    "yas_etiketi": "19+ YAŞ",
                    "dogum_yillari": [],
                    "max_dogum_yili": 2008,
                    "min_yas": 19,
                    "max_yas": None,
                    "mesafe": 50,
                    "stil": "Serbest",
                    "sure": "00:24,51",
                    "sure_saniye": 24.51,
                },
            ],
        }

    def test_parse_time_to_seconds(self):
        self.assertEqual(_parse_time_to_seconds("00:24,51"), 24.51)
        self.assertEqual(_parse_time_to_seconds("01:08,16"), 68.16)
        self.assertEqual(_parse_time_to_seconds("15:54,03"), 954.03)
        self.assertIsNone(_parse_time_to_seconds("-"))

    def test_parse_event_cell(self):
        self.assertEqual(_parse_event_cell("50 m\nSerbest"), (50, "Serbest"))
        self.assertEqual(_parse_event_cell("200 m\nSırtüstü"), (200, "Sırtüstü"))
        self.assertEqual(_parse_event_cell("400 m\nKarışık"), (400, "Karışık"))
        self.assertIsNone(_parse_event_cell("ERKEKLER"))

    def test_parse_age_header(self):
        h_open = _parse_age_header("19+ YAŞ\n2008+")
        self.assertEqual(h_open["yas_etiketi"], "19+ YAŞ")
        self.assertEqual(h_open["max_dogum_yili"], 2008)
        self.assertEqual(h_open["dogum_yillari"], [])

        h_multi = _parse_age_header("18-17-16\nYAŞ\n2009\n2010\n2011")
        self.assertEqual(h_multi["yas_etiketi"], "16-18 YAŞ")
        self.assertEqual(h_multi["dogum_yillari"], [2009, 2010, 2011])
        self.assertEqual(h_multi["min_yas"], 16)
        self.assertEqual(h_multi["max_yas"], 18)

    def test_evaluate_baraj_katilim_prioritized(self):
        res = evaluate_baraj_for_result(
            self.sample_barajlar,
            cinsiyet="Erkek",
            mesafe=50,
            stil="Serbest",
            derece_saniye=27.55,
            birth_year=2014,
            course="LCM",
        )
        self.assertEqual(res, "Katılım Barajı")

        res_katilim = evaluate_baraj_for_result(
            self.sample_barajlar,
            cinsiyet="Erkek",
            mesafe=50,
            stil="Serbest",
            derece_saniye=28.00,
            birth_year=2014,
            course="LCM",
        )
        self.assertEqual(res_katilim, "Katılım Barajı")

    def test_evaluate_baraj_course_filtering(self):
        # 28.10 fails 25m (27.98) even though it passes 50m (28.63)
        res_scm = evaluate_baraj_for_result(
            self.sample_barajlar,
            cinsiyet="Erkek",
            mesafe=50,
            stil="Serbest",
            derece_saniye=28.10,
            birth_year=2014,
            course="SCM",
        )
        self.assertIsNone(res_scm)

    def test_evaluate_baraj_open_age_and_multi_year(self):
        res_open = evaluate_baraj_for_result(
            self.sample_barajlar,
            cinsiyet="Erkek",
            mesafe=50,
            stil="Serbest",
            derece_saniye=24.50,
            birth_year=2004,
            course="LCM",
        )
        self.assertEqual(res_open, "Katılım Barajı")

        res_multi = evaluate_baraj_for_result(
            self.sample_barajlar,
            cinsiyet="Kadın",
            mesafe=100,
            stil="Kurbağalama",
            derece_saniye=77.00,
            birth_year=2010,
            course="LCM",
        )
        self.assertEqual(res_multi, "Katılım Barajı")

    def test_evaluate_baraj_invalid_inputs(self):
        self.assertIsNone(
            evaluate_baraj_for_result(
                {}, cinsiyet="Erkek", mesafe=50, stil="Serbest", derece_saniye=20.0, birth_year=2014
            )
        )
        self.assertIsNone(
            evaluate_baraj_for_result(
                self.sample_barajlar,
                cinsiyet="Erkek",
                mesafe=50,
                stil="Serbest",
                derece_saniye=None,
                birth_year=2014,
            )
        )
        self.assertEqual(parse_baraj_pdf_bytes(b"%PDF-1.4\n%%EOF"), {})
