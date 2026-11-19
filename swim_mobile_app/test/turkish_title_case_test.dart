import 'package:flutter_test/flutter_test.dart';
import 'package:swim_mobile_app/core/utils/string_utils.dart';

void main() {
  group('StringUtils.toTitleCase (Turkish-aware)', () {
    test('keeps apostrophe suffixes lowercase and attached', () {
      expect(
        StringUtils.toTitleCase('10 KASIM ATATÜRK’Ü ANMA GÜNÜ'),
        '10 Kasım Atatürk’ü Anma Günü',
      );
      expect(
        StringUtils.toTitleCase('10 KASIM ATATÜRK’ Ü ANMA GÜNÜ'),
        '10 Kasım Atatürk’ü Anma Günü',
      );
      expect(
        StringUtils.toTitleCase("10 KASIM ATATÜRK'ÜN ANMA GÜNÜ"),
        "10 Kasım Atatürk'ün Anma Günü",
      );
    });

    test('preserves Ş/ş, Ç/ç, İ/i, I/ı, Ğ/ğ, Ü/ü, Ö/ö and numeric age tokens', () {
      expect(
        StringUtils.toTitleCase('11-12 YAŞ ULUSAL GELİŞİM LİGİ'),
        '11-12 Yaş Ulusal Gelişim Ligi',
      );
      expect(
        StringUtils.toTitleCase('11-12 YAŞ ULUSAL GELİŞİM LİGİ FİNAL SEÇME'),
        '11-12 Yaş Ulusal Gelişim Ligi Final Seçme',
      );
    });

    test('handles full meet titles with Turkish characters correctly', () {
      expect(
        StringUtils.toTitleCase(
          '11-12 YAŞ ULUSAL GELİŞİM LİGİ FİNAL SEÇME VE 2014 + MİLLİ TAKIM SEÇME MÜSABAKALARI',
        ),
        '11-12 Yaş Ulusal Gelişim Ligi Final Seçme Ve 2014 + Milli Takım Seçme Müsabakaları',
      );
      expect(
        StringUtils.toTitleCase('ISPARTA İSTANBUL ÇANAKKALE ŞIRNAK ĞÜÖ'),
        'Isparta İstanbul Çanakkale Şırnak Ğüö',
      );
    });

    test('uses standard casing for foreign names and keeps acronyms uppercase', () {
      expect(
        StringUtils.toTitleCase('STERGIOS MARIOS BILAS'),
        'Stergios Marios Bilas',
      );
      expect(
        StringUtils.toTitleCase('FILIPPOS ANDRIADAKIS'),
        'Filippos Andriadakis',
      );
      expect(
        StringUtils.toTitleCase('HELLENIC SWIMMING FEDERATION'),
        'Hellenic Swimming Federation',
      );
      expect(StringUtils.toTitleCase('SARP SÜNBÜL'), 'Sarp Sünbül');
      expect(StringUtils.toTitleCase('GÜLCE AYDEMİR'), 'Gülce Aydemir');
      expect(StringUtils.toTitleCase('ATATÜRK’Ü'), 'Atatürk’ü');
      expect(
        StringUtils.toTitleCase('TYF UGP FINA SEM TYB TUR'),
        'TYF UGP FINA SEM TYB TUR',
      );
    });
  });
}
