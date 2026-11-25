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

  /// Türkçe büyük harf dönüşümü ('i' -> 'İ', 'ı' -> 'I' eşlemesi sonrası toUpperCase)
  static String toTurkishUpper(String text) {
    return text
        .replaceAll('i', 'İ')
        .replaceAll('ı', 'I')
        .replaceAll('ş', 'Ş')
        .replaceAll('ç', 'Ç')
        .replaceAll('ğ', 'Ğ')
        .replaceAll('ü', 'Ü')
        .replaceAll('ö', 'Ö')
        .toUpperCase();
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

  /// "Maskeli Sporcu (...)" ön ekini ve parantezleri kaldırarak
  /// ayrıştırılmış sporcu adını Başlık Düzenine çevirir.
  static String formatAthleteName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;

    var cleaned = trimmed.replaceAll(
      RegExp(
        r'(?:maskel[iİı]\s+sporcu|MASKEL[İI]\s+SPORCU)\s*[-–:]?\s*',
        caseSensitive: false,
      ),
      '',
    );

    // "Maskeli sporcu (Ad Soyad)" veya "(Ad Soyad)" parantezlerini temizle
    cleaned = cleaned.replaceAll('(', '').replaceAll(')', '');
    cleaned = cleaned.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    if (cleaned.isEmpty) return 'İsimsiz Sporcu';
    return toTitleCase(cleaned);
  }

  /// Cümle/not içindeki "Maskeli sporcu (Ad Soyad)" ifadelerini ve parantezleri
  /// cümle düzenini bozmadan temizler.
  static String cleanMaskedText(String text) {
    if (text.isEmpty) return text;
    return text.replaceAllMapped(
      RegExp(
        r'(?:maskel[iİı]\s+sporcu|MASKEL[İI]\s+SPORCU)\s*\(([^)]*)\)',
        caseSensitive: false,
      ),
      (m) {
        final inner = (m.group(1) ?? '').trim();
        return inner.isNotEmpty ? toTitleCase(inner) : 'İsimsiz Sporcu';
      },
    ).replaceAll(
      RegExp(
        r'(?:maskel[iİı]\s+sporcu|MASKEL[İI]\s+SPORCU)\s*[-–:]?\s*',
        caseSensitive: false,
      ),
      '',
    );
  }
}
