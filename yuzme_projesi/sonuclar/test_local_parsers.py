# -*- coding: utf-8 -*-
import glob
import os
import sys
import unittest

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(CURRENT_DIR)
ROOT_DIR = os.path.dirname(PROJECT_DIR)
if PROJECT_DIR not in sys.path:
    sys.path.insert(0, PROJECT_DIR)

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "yuzme_projesi.settings")
import django
django.setup()

from sonuclar.athlete_matcher import clean_athlete_name_tags
from sonuclar.local_live_engine import _normalize_gender
from sonuclar.local_resultlist_parser import LocalResultListParser
from sonuclar.local_startlist_parser import LocalStartListParser


class TestLocalParsersAndEngine(unittest.TestCase):
    def test_clean_athlete_name_tags_preserves_leading_f_t_d(self):
        self.assertEqual(clean_athlete_name_tags("Duru **ç**"), "Duru **ç**")
        self.assertEqual(clean_athlete_name_tags("Derin **kme*"), "Derin **kme*")
        self.assertEqual(clean_athlete_name_tags("Demir *l***ç"), "Demir *l***ç")
        self.assertEqual(clean_athlete_name_tags("Furkan YILMAZ"), "Furkan YILMAZ")
        self.assertEqual(clean_athlete_name_tags("Tuna ACAR"), "Tuna ACAR")
        # Etiketler hâlâ temizlenmeli
        self.assertEqual(clean_athlete_name_tags("(Fd) Duru **ç**"), "Duru **ç**")
        self.assertEqual(clean_athlete_name_tags("(f5) Adem ŞAHİN"), "Adem ŞAHİN")
        self.assertEqual(clean_athlete_name_tags("( Metehan İŞLER"), "Metehan İŞLER")
        self.assertEqual(clean_athlete_name_tags("(F Metehan"), "Metehan")
        self.assertEqual(clean_athlete_name_tags("F) Metehan"), "Metehan")
        self.assertEqual(clean_athlete_name_tags("d) can"), "can")

    def test_normalize_gender(self):
        self.assertEqual(_normalize_gender("Erkekler"), "Erkek")
        self.assertEqual(_normalize_gender("Boys"), "Erkek")
        self.assertEqual(_normalize_gender("Kadınlar"), "Kadın")
        self.assertEqual(_normalize_gender("Kızlar"), "Kadın")
        self.assertEqual(_normalize_gender("Bayanlar"), "Kadın")
        self.assertEqual(_normalize_gender("Karma"), "Karma")
        self.assertIsNone(_normalize_gender("18 yaş ve büyükler"))

    def test_startlist_numeric_club_and_wrapped_name_protection(self):
        parser = LocalStartListParser()
        self.assertFalse(parser._is_valid_club_line("0"))
        self.assertFalse(parser._is_valid_club_line("11"))
        self.assertFalse(parser._is_valid_club_line("NT"))
        self.assertFalse(parser._is_valid_club_line("1:45.20"))
        self.assertTrue(parser._is_valid_club_line("Fenerbahçe Spor Kulübü"))

        lines = ["YILMAZ", "11", "Enka Spor Kulübü", "29.50"]
        name, by, next_idx = parser._consume_birth_year_and_name(lines, 0, len(lines), "Ahmet")
        self.assertEqual(name, "Ahmet YILMAZ")
        self.assertEqual(by, "11")
        self.assertEqual(next_idx, 2)

    def test_local_startlist_pdfs(self):
        parser = LocalStartListParser()
        pdfs = sorted(
            glob.glob(os.path.join(ROOT_DIR, "StartList_*.pdf"))
            + glob.glob(os.path.join(ROOT_DIR, "temp_test", "StartList_*.pdf"))
        )
        self.assertGreater(len(pdfs), 0)
        for pdf in pdfs:
            res = parser.parse(pdf)
            sp = res["sporcular"]
            self.assertGreater(len(sp), 0, f"{pdf} boş döndü")
            for row in sp:
                self.assertTrue(row["kulup"], f"{pdf} kulup boş: {row}")
                self.assertFalse(str(row["kulup"]).isdigit(), f"{pdf} sayısal kulüp: {row}")
                self.assertTrue(row["dogum_yili"], f"{pdf} doğum yılı boş: {row}")
                self.assertTrue(row["seri"], f"{pdf} seri boş: {row}")
                self.assertIsNotNone(row["kulvar"], f"{pdf} kulvar boş: {row}")

    def test_local_resultlist_1070_and_dsq_block(self):
        parser = LocalResultListParser()
        pdf_path = os.path.join(ROOT_DIR, "ResultList_1070.pdf")
        if os.path.exists(pdf_path):
            res = parser.parse(pdf_path)
            self.assertEqual(res["derece_alanlar"], 15)
            self.assertEqual(res["dsq_dns_sayisi"], 1)

        dsq_rows = parser._parse_dsq_block(
            "DSQ 4/3 2012 Ahmet YILMAZ (10:59 - SW 8.5 - TEK EL)", page_no=1
        )
        self.assertEqual(len(dsq_rows), 1)
        self.assertEqual(dsq_rows[0]["kulvar"], 4)
        self.assertEqual(dsq_rows[0]["seri"], 3)
        self.assertEqual(dsq_rows[0]["dogum_yili"], "2012")
        self.assertEqual(dsq_rows[0]["sporcu"], "Ahmet YILMAZ")


if __name__ == "__main__":
    unittest.main(verbosity=2)
