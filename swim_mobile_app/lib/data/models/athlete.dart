// Sporcu ve PB (Kişisel En İyi) Modelleri

class PersonalBest {
  final int distance;
  final String stroke;
  final String strokeLabel;
  final String time;
  final int? timeCs;
  final int? points;
  final String date;
  final String meetName;
  final String course; // 'SC' veya 'LC'

  PersonalBest({
    required this.distance,
    required this.stroke,
    required this.strokeLabel,
    required this.time,
    this.timeCs,
    this.points,
    required this.date,
    required this.meetName,
    required this.course,
  });

  factory PersonalBest.fromJson(Map<String, dynamic> json) {
    return PersonalBest(
      distance: json['distance'] as int? ?? 0,
      stroke: json['stroke'] as String? ?? '',
      strokeLabel: json['stroke_label'] as String? ?? '',
      time: json['time'] as String? ?? '',
      timeCs: json['time_cs'] as int?,
      points: json['points'] as int?,
      date: json['date'] as String? ?? '',
      meetName: json['meet_name'] as String? ?? '',
      course: json['course'] as String? ?? 'LC',
    );
  }
}

class AthleteStats {
  final int totalRaces;
  final int podiumCount;
  final double podiumRate;
  final int standardsPassed;

  AthleteStats({
    required this.totalRaces,
    required this.podiumCount,
    required this.podiumRate,
    required this.standardsPassed,
  });

  factory AthleteStats.fromJson(Map<String, dynamic> json) {
    return AthleteStats(
      totalRaces: json['total_races'] as int? ?? 0,
      podiumCount: json['podium_count'] as int? ?? 0,
      podiumRate: (json['podium_rate'] as num?)?.toDouble() ?? 0.0,
      standardsPassed: json['standards_passed'] as int? ?? 0,
    );
  }
}

class AthleteDetail {
  final int id;
  final String name;
  final int? birthYear;
  final int? age;
  final String gender;
  final String? clubName;
  final int? clubId;
  final String? school;
  final AthleteStats stats;
  final String scoutNote;
  final List<PersonalBest> pbs50m;
  final List<PersonalBest> pbs25m;

  AthleteDetail({
    required this.id,
    required this.name,
    this.birthYear,
    this.age,
    required this.gender,
    this.clubName,
    this.clubId,
    this.school,
    required this.stats,
    required this.scoutNote,
    required this.pbs50m,
    required this.pbs25m,
  });

  factory AthleteDetail.fromJson(Map<String, dynamic> json) {
    final clubObj = json['current_club'] as Map<String, dynamic>?;
    final statsObj = json['stats'] as Map<String, dynamic>? ?? {};
    final pbsObj = json['personal_bests'] as Map<String, dynamic>? ?? {};

    final raw50m = pbsObj['course_50m'] as List<dynamic>? ?? [];
    final raw25m = pbsObj['course_25m'] as List<dynamic>? ?? [];

    return AthleteDetail(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      birthYear: json['birth_year'] as int?,
      age: json['age'] as int?,
      gender: json['gender'] as String? ?? '',
      clubId: clubObj?['id'] as int?,
      clubName: clubObj?['name'] as String?,
      school: json['school'] as String?,
      stats: AthleteStats.fromJson(statsObj),
      scoutNote: json['scout_note'] as String? ?? '',
      pbs50m: raw50m.map((e) => PersonalBest.fromJson(e as Map<String, dynamic>)).toList(),
      pbs25m: raw25m.map((e) => PersonalBest.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class AthleteRaceHistoryItem {
  final int id;
  final int meetId;
  final String meetName;
  final String date;
  final String course;
  final String eventNo;
  final int? distance;
  final String stroke;
  final String strokeLabel;
  final String heat;
  final int? lane;
  final String rank;
  final String? time;
  final int? timeCs;
  final String resultStatus;
  final int? points;
  final String clubName;

  AthleteRaceHistoryItem({
    required this.id,
    required this.meetId,
    required this.meetName,
    required this.date,
    required this.course,
    required this.eventNo,
    this.distance,
    required this.stroke,
    required this.strokeLabel,
    required this.heat,
    this.lane,
    required this.rank,
    this.time,
    this.timeCs,
    required this.resultStatus,
    this.points,
    required this.clubName,
  });

  factory AthleteRaceHistoryItem.fromJson(Map<String, dynamic> json) {
    return AthleteRaceHistoryItem(
      id: json['id'] as int,
      meetId: json['meet_id'] as int? ?? 0,
      meetName: json['meet_name'] as String? ?? '',
      date: json['date'] as String? ?? '',
      course: json['course'] as String? ?? 'LC',
      eventNo: json['event_no'] as String? ?? '',
      distance: json['distance'] as int?,
      stroke: json['stroke'] as String? ?? '',
      strokeLabel: json['stroke_label'] as String? ?? '',
      heat: json['heat'] as String? ?? '',
      lane: json['lane'] as int?,
      rank: json['rank'] as String? ?? '',
      time: json['time'] as String?,
      timeCs: json['time_cs'] as int?,
      resultStatus: json['result_status'] as String? ?? 'OK',
      points: json['points'] as int?,
      clubName: json['club_name'] as String? ?? '',
    );
  }
}

class AthleteRaceBrief {
  final int distance;
  final String stroke;
  final String time;
  final int? points;

  AthleteRaceBrief({
    required this.distance,
    required this.stroke,
    required this.time,
    this.points,
  });

  factory AthleteRaceBrief.fromJson(Map<String, dynamic> json) {
    return AthleteRaceBrief(
      distance: json['distance'] as int? ?? 0,
      stroke: json['stroke'] as String? ?? '',
      time: json['time'] as String? ?? '-',
      points: json['points'] as int?,
    );
  }
}

class AthleteSummaryItem {
  final int id;
  final String name;
  final int? birthYear;
  final String clubName;
  final AthleteRaceBrief? latestRace;
  final AthleteRaceBrief? topPerformance;

  AthleteSummaryItem({
    required this.id,
    required this.name,
    this.birthYear,
    required this.clubName,
    this.latestRace,
    this.topPerformance,
  });

  factory AthleteSummaryItem.fromJson(Map<String, dynamic> json) {
    final latestRaw = json['latest_race'] as Map<String, dynamic>?;
    final topRaw = json['top_performance'] as Map<String, dynamic>?;
    return AthleteSummaryItem(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      birthYear: json['birth_year'] as int?,
      clubName: json['club_name'] as String? ?? 'Ferdi',
      latestRace: latestRaw != null ? AthleteRaceBrief.fromJson(latestRaw) : null,
      topPerformance: topRaw != null ? AthleteRaceBrief.fromJson(topRaw) : null,
    );
  }
}

class AthleteSearchItem {
  final int id;
  final String name;
  final int? birthYear;
  final String clubName;

  AthleteSearchItem({
    required this.id,
    required this.name,
    this.birthYear,
    required this.clubName,
  });

  factory AthleteSearchItem.fromJson(Map<String, dynamic> json) {
    return AthleteSearchItem(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      birthYear: json['birth_year'] as int?,
      clubName: json['club_name'] as String? ?? 'Ferdi',
    );
  }
}

class ClubSearchItem {
  final int? id;
  final String name;
  final int athleteCount;

  ClubSearchItem({
    this.id,
    required this.name,
    required this.athleteCount,
  });

  factory ClubSearchItem.fromJson(Map<String, dynamic> json) {
    return ClubSearchItem(
      id: json['id'] as int?,
      name: json['name'] as String? ?? '',
      athleteCount: json['athlete_count'] as int? ?? 0,
    );
  }
}

class GlobalSearchResult {
  final List<AthleteSearchItem> athletes;
  final List<ClubSearchItem> clubs;

  GlobalSearchResult({
    required this.athletes,
    required this.clubs,
  });

  factory GlobalSearchResult.fromJson(Map<String, dynamic> json) {
    final athletesRaw = json['athletes'] as List<dynamic>? ?? [];
    final clubsRaw = json['clubs'] as List<dynamic>? ?? [];
    return GlobalSearchResult(
      athletes: athletesRaw
          .map((e) => AthleteSearchItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      clubs: clubsRaw
          .map((e) => ClubSearchItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

