/// Resmi TYF Katılım & Harcırah Barajı Kuralı Modeli
class BarajRule {
  final int id;
  final String barajAdi;
  final String barajTuru;
  final String havuz;
  final String cinsiyet;
  final String yasEtiketi;
  final List<int> dogumYillari;
  final int? maxDogumYili;
  final int mesafe;
  final String stil;
  final String sure;
  final int sureCs;
  final int? eventId;
  final int? belgeId;
  final String belgeBaslik;
  final String pdfUrl;
  final String sourceUrl;

  const BarajRule({
    required this.id,
    required this.barajAdi,
    required this.barajTuru,
    required this.havuz,
    required this.cinsiyet,
    required this.yasEtiketi,
    this.dogumYillari = const [],
    this.maxDogumYili,
    required this.mesafe,
    required this.stil,
    required this.sure,
    required this.sureCs,
    this.eventId,
    this.belgeId,
    this.belgeBaslik = '',
    this.pdfUrl = '',
    this.sourceUrl = '',
  });

  factory BarajRule.fromJson(Map<String, dynamic> json) {
    final dys = json['dogum_yillari'] as List<dynamic>? ?? const [];
    return BarajRule(
      id: (json['id'] as num?)?.toInt() ?? 0,
      barajAdi: (json['baraj_adi'] as String?) ?? '',
      barajTuru: (json['baraj_turu'] as String?) ?? 'Katılım Barajı',
      havuz: (json['havuz'] as String?) ?? '',
      cinsiyet: (json['cinsiyet'] as String?) ?? '',
      yasEtiketi: (json['yas_etiketi'] as String?) ?? '',
      dogumYillari: dys.map((e) => (e as num).toInt()).toList(),
      maxDogumYili: (json['max_dogum_yili'] as num?)?.toInt(),
      mesafe: (json['mesafe'] as num?)?.toInt() ?? 0,
      stil: (json['stil'] as String?) ?? '',
      sure: (json['sure'] as String?) ?? '',
      sureCs: (json['sure_cs'] as num?)?.toInt() ?? 0,
      eventId: (json['event_id'] as num?)?.toInt(),
      belgeId: (json['belge_id'] as num?)?.toInt(),
      belgeBaslik: (json['belge_baslik'] as String?) ?? '',
      pdfUrl: (json['pdf_url'] as String?) ?? '',
      sourceUrl: (json['source_url'] as String?) ?? '',
    );
  }
}

class BarajEventOption {
  final int? eventId;
  final String barajAdi;
  final String title;
  final String city;
  final String dateText;
  final String startDate;
  final String validityText;
  final String pdfUrl;
  final String ozet;
  final List<String> onemliNotlar;

  const BarajEventOption({
    this.eventId,
    required this.barajAdi,
    required this.title,
    this.city = '',
    this.dateText = '',
    this.startDate = '',
    this.validityText = '',
    this.pdfUrl = '',
    this.ozet = '',
    this.onemliNotlar = const [],
  });

  factory BarajEventOption.fromJson(Map<String, dynamic> json) {
    final rawNotes = json['onemli_notlar'] as List<dynamic>? ?? const [];
    return BarajEventOption(
      eventId: (json['event_id'] as num?)?.toInt(),
      barajAdi: (json['baraj_adi'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      dateText: (json['date_text'] as String?) ?? '',
      startDate: (json['start_date'] as String?) ?? '',
      validityText: (json['validity_text'] as String?) ?? '',
      pdfUrl: (json['pdf_url'] as String?) ?? '',
      ozet: (json['ozet'] as String?) ?? '',
      onemliNotlar: rawNotes.map((e) => e.toString()).toList(),
    );
  }
}

class BarajFeedResponse {
  final List<BarajRule> rules;
  final List<String> barajNames;
  final List<BarajEventOption> events;
  final List<String> cities;
  final List<String> months;
  final List<String> ageLabels;

  const BarajFeedResponse({
    required this.rules,
    required this.barajNames,
    this.events = const [],
    this.cities = const [],
    this.months = const [],
    required this.ageLabels,
  });
}
