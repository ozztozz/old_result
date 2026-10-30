/// Müsabaka Modelleri

class MeetSummary {
  final int id;
  final String name;
  final String city;
  final String startDate;
  final String endDate;
  final String course; // 'SC' veya 'LC'
  final int totalRaces;
  final int totalAthletes;

  MeetSummary({
    required this.id,
    required this.name,
    required this.city,
    required this.startDate,
    required this.endDate,
    required this.course,
    required this.totalRaces,
    required this.totalAthletes,
  });

  factory MeetSummary.fromJson(Map<String, dynamic> json) {
    return MeetSummary(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      city: json['city'] as String? ?? '',
      startDate: json['start_date'] as String? ?? '',
      endDate: json['end_date'] as String? ?? '',
      course: json['course'] as String? ?? 'LC',
      totalRaces: json['total_races'] as int? ?? 0,
      totalAthletes: json['total_athletes'] as int? ?? 0,
    );
  }
}

class MeetEvent {
  final String eventNo;
  final int? distance;
  final String stroke;
  final String strokeLabel;
  final String gender;

  MeetEvent({
    required this.eventNo,
    this.distance,
    required this.stroke,
    required this.strokeLabel,
    required this.gender,
  });

  factory MeetEvent.fromJson(Map<String, dynamic> json) {
    return MeetEvent(
      eventNo: json['event_no'] as String? ?? '',
      distance: json['distance'] as int?,
      stroke: json['stroke'] as String? ?? '',
      strokeLabel: json['stroke_label'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
    );
  }
}

class MeetDetail {
  final int id;
  final String name;
  final String city;
  final String startDate;
  final String endDate;
  final String course;
  final int totalRaces;
  final int totalAthletes;
  final List<MeetEvent> events;

  MeetDetail({
    required this.id,
    required this.name,
    required this.city,
    required this.startDate,
    required this.endDate,
    required this.course,
    required this.totalRaces,
    required this.totalAthletes,
    required this.events,
  });

  factory MeetDetail.fromJson(Map<String, dynamic> json) {
    final rawEvents = json['events'] as List<dynamic>? ?? [];
    return MeetDetail(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      city: json['city'] as String? ?? '',
      startDate: json['start_date'] as String? ?? '',
      endDate: json['end_date'] as String? ?? '',
      course: json['course'] as String? ?? 'LC',
      totalRaces: json['total_races'] as int? ?? 0,
      totalAthletes: json['total_athletes'] as int? ?? 0,
      events: rawEvents.map((e) => MeetEvent.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class ParticipantClub {
  final int id;
  final String name;

  ParticipantClub({required this.id, required this.name});

  factory ParticipantClub.fromJson(Map<String, dynamic> json) {
    return ParticipantClub(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
    );
  }
}

class ParticipantAthlete {
  final int id;
  final String name;
  final int? birthYear;
  final int? clubId;

  ParticipantAthlete({
    required this.id,
    required this.name,
    this.birthYear,
    this.clubId,
  });

  factory ParticipantAthlete.fromJson(Map<String, dynamic> json) {
    return ParticipantAthlete(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      birthYear: json['birth_year'] as int?,
      clubId: json['club_id'] as int?,
    );
  }
}

class MeetParticipants {
  final int meetId;
  final List<ParticipantClub> clubs;
  final List<ParticipantAthlete> athletes;

  MeetParticipants({
    required this.meetId,
    required this.clubs,
    required this.athletes,
  });

  factory MeetParticipants.fromJson(Map<String, dynamic> json) {
    final rawClubs = json['clubs'] as List<dynamic>? ?? [];
    final rawAthletes = json['athletes'] as List<dynamic>? ?? [];
    return MeetParticipants(
      meetId: json['meet_id'] as int? ?? 0,
      clubs: rawClubs.map((c) => ParticipantClub.fromJson(c as Map<String, dynamic>)).toList(),
      athletes: rawAthletes.map((a) => ParticipantAthlete.fromJson(a as Map<String, dynamic>)).toList(),
    );
  }
}
