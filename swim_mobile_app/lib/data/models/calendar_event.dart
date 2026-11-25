/// Ulusal (TYF) ve İl Etkinlik Takvimi Modeli
class CalendarEvent {
  final int id;
  final String name;
  final String city;
  final String startDate;
  final String endDate;
  final String rawDate;
  final String pool;
  final String ageGroup;
  final int? minAge;
  final int? maxAge;
  final String sourceType;
  final String scope; // ULUSAL | IL
  final bool hasResults;
  final int barajCount;
  final String pdfUrl;
  final String ozet;

  const CalendarEvent({
    required this.id,
    required this.name,
    this.city = '',
    this.startDate = '',
    this.endDate = '',
    this.rawDate = '',
    this.pool = '',
    this.ageGroup = '',
    this.minAge,
    this.maxAge,
    this.sourceType = '',
    this.scope = 'ULUSAL',
    this.hasResults = false,
    this.barajCount = 0,
    this.pdfUrl = '',
    this.ozet = '',
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      startDate: (json['start_date'] as String?) ?? '',
      endDate: (json['end_date'] as String?) ?? '',
      rawDate: (json['raw_date'] as String?) ?? '',
      pool: (json['pool'] as String?) ?? '',
      ageGroup: (json['age_group'] as String?) ?? '',
      minAge: (json['min_age'] as num?)?.toInt(),
      maxAge: (json['max_age'] as num?)?.toInt(),
      sourceType: (json['source_type'] as String?) ?? '',
      scope: (json['scope'] as String?) ?? 'ULUSAL',
      hasResults: (json['has_results'] as bool?) ?? false,
      barajCount: (json['baraj_count'] as num?)?.toInt() ?? 0,
      pdfUrl: (json['pdf_url'] as String?) ?? '',
      ozet: (json['ozet'] as String?) ?? '',
    );
  }

  String get monthKey {
    if (startDate.length >= 7) return startDate.substring(0, 7);
    return 'DİĞER';
  }
}

class CalendarFeedResponse {
  final List<CalendarEvent> events;
  final List<String> cities;

  const CalendarFeedResponse({
    required this.events,
    required this.cities,
  });
}
