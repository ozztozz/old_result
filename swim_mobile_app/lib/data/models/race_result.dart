/// Yarış Sonucu ve Baraj Modelleri

class QualifyingStandard {
  final bool passed;
  final String badge;

  QualifyingStandard({required this.passed, required this.badge});

  factory QualifyingStandard.fromJson(Map<String, dynamic> json) {
    return QualifyingStandard(
      passed: json['passed'] as bool? ?? false,
      badge: json['badge'] as String? ?? '',
    );
  }
}

class RaceResult {
  final int id;
  final String eventNo;
  final int? distance;
  final String stroke;
  final String strokeLabel;
  final String heat;
  final int? lane;
  final String rank;
  final String? time;
  final int? timeCs;
  final String? seedTime;
  final int? seedTimeCs;
  final String resultStatus; // 'OK', 'DQ', 'DNS', 'DNF', 'WAITING'
  final int? points;
  final QualifyingStandard? qualifyingStandard;
  final String source; // 'official' veya 'live'
  final int athleteId;
  final String athleteName;
  final int? birthYear;
  final int? age;
  final int? clubId;
  final String clubName;

  RaceResult({
    required this.id,
    required this.eventNo,
    this.distance,
    required this.stroke,
    required this.strokeLabel,
    required this.heat,
    this.lane,
    required this.rank,
    this.time,
    this.timeCs,
    this.seedTime,
    this.seedTimeCs,
    required this.resultStatus,
    this.points,
    this.qualifyingStandard,
    required this.source,
    required this.athleteId,
    required this.athleteName,
    this.birthYear,
    this.age,
    this.clubId,
    required this.clubName,
  });

  factory RaceResult.fromJson(Map<String, dynamic> json) {
    final athleteObj = json['athlete'] as Map<String, dynamic>? ?? {};
    final clubObj = json['club'] as Map<String, dynamic>?;
    final standardObj = json['qualifying_standard'] as Map<String, dynamic>?;

    return RaceResult(
      id: json['id'] as int,
      eventNo: json['event_no'] as String? ?? '',
      distance: json['distance'] as int?,
      stroke: json['stroke'] as String? ?? '',
      strokeLabel: json['stroke_label'] as String? ?? '',
      heat: json['heat'] as String? ?? '',
      lane: json['lane'] as int?,
      rank: json['rank'] as String? ?? '',
      time: json['time'] as String?,
      timeCs: json['time_cs'] as int?,
      seedTime: json['seed_time'] as String?,
      seedTimeCs: json['seed_time_cs'] as int?,
      resultStatus: json['result_status'] as String? ?? 'OK',
      points: json['points'] as int?,
      qualifyingStandard: standardObj != null ? QualifyingStandard.fromJson(standardObj) : null,
      source: json['source'] as String? ?? 'official',
      athleteId: athleteObj['id'] as int? ?? 0,
      athleteName: athleteObj['name'] as String? ?? '',
      birthYear: athleteObj['birth_year'] as int?,
      age: athleteObj['age'] as int?,
      clubId: clubObj?['id'] as int?,
      clubName: clubObj?['name'] as String? ?? 'Ferdi',
    );
  }
}
