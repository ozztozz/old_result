/// Türkçe karakter duyarlı metin biçimlendirme yardımcıları
abstract final class StringUtils {
  static const Set<String> _acronyms = {
    'UGP',
    'TYF',
    'FINA',
    'SEM',
    'TYB',
    'TUR',
  };

  static const Map<String, String> _knownTurkishWords = {
    'IZMIR': 'İzmir',
    'ISMAIL': 'İsmail',
  };

  static final RegExp _turkishCharRegex = RegExp(r'[İıŞşĞğÇçÖöÜü]');

  /// Metni akıllı Başlık Düzenine (Title Case) çevirir.
  /// - Kısaltmaları (UGP, TYF, FINA, SEM, TYB, TUR) büyük harf korur.
  /// - Metin Türkçe karakter (İ ı Ş Ğ Ç Ö Ü) içeriyorsa Türkçe kurallarıyla,
  ///   yabancı isimler/metinler için standart (I -> i) kurallarıyla dönüştürür.
  /// - Kesme işaretleri (’ ve ') kelime içi karakter sayılır; sonrasındaki ek
  ///   küçük harf ve bitişik tutulur ("ATATÜRK’Ü" / "ATATÜRK’ Ü" -> "Atatürk’ü").
  static String toTitleCase(String text) {
    if (text.isEmpty) return text;
    final normalized = text.replaceAllMapped(
      RegExp(r"([’'])\s+"),
      (match) => match.group(1)!,
    );
    final useTurkish = _turkishCharRegex.hasMatch(normalized);

    return normalized.split(' ').map((word) {
      if (word.isEmpty) return word;
      final upper = word.toUpperCase();
      if (_acronyms.contains(upper)) return upper;
      final known = _knownTurkishWords[upper];
      if (known != null) return known;

      if (useTurkish || _turkishCharRegex.hasMatch(word)) {
        final lower = toTurkishLower(word);
        final first = _toTurkishUpperChar(lower[0]);
        return first + lower.substring(1);
      }

      final lower = word.toLowerCase();
      return lower[0].toUpperCase() + lower.substring(1);
    }).join(' ');
  }

  /// Türkçe büyük/küçük harf dönüşümü ('İ' -> 'i', 'I' -> 'ı' eşlemesi sonrası toLowerCase)
  static String toTurkishLower(String text) {
    return text
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ç', 'ç')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ü', 'ü')
        .replaceAll('Ö', 'ö')
        .toLowerCase();
  }

  static String _toTurkishUpperChar(String ch) {
    switch (ch) {
      case 'i':
        return 'İ';
      case 'ı':
        return 'I';
      case 'ğ':
        return 'Ğ';
      case 'ü':
        return 'Ü';
      case 'ş':
        return 'Ş';
      case 'ö':
        return 'Ö';
      case 'ç':
        return 'Ç';
      default:
        return ch.toUpperCase();
    }
  }
}
