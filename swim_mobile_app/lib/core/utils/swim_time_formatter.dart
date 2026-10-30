/// Uluslararası Yüzme Standartlarına Göre Süre Biçimlendirici
class SwimTimeFormatter {
  /// Centisaniye (int) değerini standart yüzme formatına dönüştürür.
  /// Örnekler:
  /// - 2845 -> "28.45"
  /// - 6234 -> "1:02.34"
  /// - 373540 -> "1:02:15.40"
  static String formatCs(int? cs) {
    if (cs == null || cs <= 0) return '-';

    final totalCentis = cs;
    final totalSeconds = totalCentis ~/ 100;
    final centis = totalCentis % 100;

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final centisStr = centis.toString().padLeft(2, '0');
    final secondsStr = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      final minutesStr = minutes.toString().padLeft(2, '0');
      return '$hours:$minutesStr:$secondsStr.$centisStr';
    } else if (minutes > 0) {
      return '$minutes:$secondsStr.$centisStr';
    } else {
      // 1 dakikanın altı için başında "00:" olmaz (Yüzme Kuralı)
      return '$seconds.$centisStr';
    }
  }

  /// Fark saniyesini (+0.25s veya -1.42s) formatlar
  static String formatDeltaCs(int? deltaCs) {
    if (deltaCs == null) return '';
    final isNegative = deltaCs < 0;
    final absCs = deltaCs.abs();
    final s = absCs ~/ 100;
    final cs = absCs % 100;
    final sign = isNegative ? '-' : '+';
    return '$sign$s.${cs.toString().padLeft(2, '0')}s';
  }
}
