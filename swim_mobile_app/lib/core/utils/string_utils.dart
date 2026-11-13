/// Türkçe karakter duyarlı metin biçimlendirme yardımcıları
abstract final class StringUtils {
  /// Metni Türkçe kurallarına uygun Başlık Düzenine (Title Case) çevirir.
  static String toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      final lower = toTurkishLower(word);
      final first = _toTurkishUpperChar(lower[0]);
      return first + lower.substring(1);
    }).join(' ');
  }

  /// Türkçe büyük/küçük harf dönüşümü
  static String toTurkishLower(String text) {
    return text
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
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
