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

class ClubBarajRuleStatus {
  final int distance;
  final String stroke;
  final String strokeLabel;
  final String course;
  final String barajTuru;
  final String yasEtiketi;
  final int targetCs;
  final String targetTime;
  final int? pbCs;
  final String? pbTime;
  final int? diffCs;
  final bool passed;

  const ClubBarajRuleStatus({
    required this.distance,
    required this.stroke,
    required this.strokeLabel,
    required this.course,
    required this.barajTuru,
    required this.yasEtiketi,
    required this.targetCs,
    required this.targetTime,
    this.pbCs,
    this.pbTime,
    this.diffCs,
    required this.passed,
  });

  factory ClubBarajRuleStatus.fromJson(Map<String, dynamic> json) {
    return ClubBarajRuleStatus(
      distance: (json['distance'] as num?)?.toInt() ?? 0,
      stroke: (json['stroke'] as String?) ?? '',
      strokeLabel: (json['stroke_label'] as String?) ?? '',
      course: (json['course'] as String?) ?? '',
      barajTuru: (json['baraj_turu'] as String?) ?? '',
      yasEtiketi: (json['yas_etiketi'] as String?) ?? '',
      targetCs: (json['target_cs'] as num?)?.toInt() ?? 0,
      targetTime: (json['target_time'] as String?) ?? '',
      pbCs: (json['pb_cs'] as num?)?.toInt(),
      pbTime: json['pb_time'] as String?,
      diffCs: (json['diff_cs'] as num?)?.toInt(),
      passed: json['passed'] as bool? ?? false,
    );
  }
}

class ClubBarajAthleteStatus {
  final int id;
  final String name;
  final int? birthYear;
  final String gender;
  final int passedCount;
  final int totalCount;
  final List<ClubBarajRuleStatus> rules;

  const ClubBarajAthleteStatus({
    required this.id,
    required this.name,
    this.birthYear,
    required this.gender,
    required this.passedCount,
    required this.totalCount,
    required this.rules,
  });

  factory ClubBarajAthleteStatus.fromJson(Map<String, dynamic> json) {
    final rawRules = json['rules'] as List<dynamic>? ?? const [];
    return ClubBarajAthleteStatus(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      birthYear: (json['birth_year'] as num?)?.toInt(),
      gender: (json['gender'] as String?) ?? '',
      passedCount: (json['passed_count'] as num?)?.toInt() ?? 0,
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      rules: rawRules
          .map((e) => ClubBarajRuleStatus.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ClubBarajSummary {
  final int totalAthletes;
  final int passedAthletes;
  final int totalPassedRules;
  final int totalApplicableRules;

  const ClubBarajSummary({
    this.totalAthletes = 0,
    this.passedAthletes = 0,
    this.totalPassedRules = 0,
    this.totalApplicableRules = 0,
  });

  factory ClubBarajSummary.fromJson(Map<String, dynamic> json) {
    return ClubBarajSummary(
      totalAthletes: (json['total_athletes'] as num?)?.toInt() ?? 0,
      passedAthletes: (json['passed_athletes'] as num?)?.toInt() ?? 0,
      totalPassedRules: (json['total_passed_rules'] as num?)?.toInt() ?? 0,
      totalApplicableRules:
          (json['total_applicable_rules'] as num?)?.toInt() ?? 0,
    );
  }
}

class ClubBarajStatusResponse {
  final ClubBarajSummary summary;
  final List<ClubBarajAthleteStatus> athletes;

  const ClubBarajStatusResponse({
    this.summary = const ClubBarajSummary(),
    this.athletes = const [],
  });

  factory ClubBarajStatusResponse.fromJson(Map<String, dynamic> json) {
    final rawAthletes = json['athletes'] as List<dynamic>? ?? const [];
    return ClubBarajStatusResponse(
      summary: ClubBarajSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const {},
      ),
      athletes: rawAthletes
          .map((e) =>
              ClubBarajAthleteStatus.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
