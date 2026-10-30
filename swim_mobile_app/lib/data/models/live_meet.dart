import 'race_result.dart';

/// Canlı Yarış Takip Modelleri

class LiveProgress {
  final int processed;
  final int total;

  LiveProgress({required this.processed, required this.total});

  factory LiveProgress.fromJson(Map<String, dynamic> json) {
    return LiveProgress(
      processed: json['processed'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
    );
  }
}

class LiveMeetSummary {
  final int id;
  final int? meetId;
  final String name;
  final String city;
  final String date;
  final String status;
  final int totalAthletes;
  final LiveProgress startListProgress;
  final LiveProgress resultListProgress;
  final String? lastActivity;

  LiveMeetSummary({
    required this.id,
    this.meetId,
    required this.name,
    required this.city,
    required this.date,
    required this.status,
    required this.totalAthletes,
    required this.startListProgress,
    required this.resultListProgress,
    this.lastActivity,
  });

  factory LiveMeetSummary.fromJson(Map<String, dynamic> json) {
    final startProg = json['start_list_progress'] as Map<String, dynamic>? ?? {};
    final resultProg = json['result_list_progress'] as Map<String, dynamic>? ?? {};

    return LiveMeetSummary(
      id: json['id'] as int,
      meetId: json['meet_id'] as int?,
      name: json['name'] as String? ?? 'Canlı Yarış',
      city: json['city'] as String? ?? '',
      date: json['date'] as String? ?? '',
      status: json['status'] as String? ?? 'BEKLIYOR',
      totalAthletes: json['total_athletes'] as int? ?? 0,
      startListProgress: LiveProgress.fromJson(startProg),
      resultListProgress: LiveProgress.fromJson(resultProg),
      lastActivity: json['last_activity'] as String?,
    );
  }
}

class LiveEventProgramItem {
  final String eventNo;
  final String name;
  final int? distance;
  final String stroke;
  final String strokeLabel;
  final String? gender;
  final String? ageGroup;
  final bool isPending;
  final String status;
  final int totalAthletes;

  LiveEventProgramItem({
    required this.eventNo,
    required this.name,
    this.distance,
    required this.stroke,
    required this.strokeLabel,
    this.gender,
    this.ageGroup,
    this.isPending = true,
    this.status = 'Bekliyor',
    this.totalAthletes = 0,
  });

  factory LiveEventProgramItem.fromJson(Map<String, dynamic> json) {
    final dist = json['distance'] as int?;
    final sLabel = json['stroke_label'] as String? ?? '';
    final defaultName = dist != null && dist > 0 ? '$dist m $sLabel'.trim() : sLabel;

    return LiveEventProgramItem(
      eventNo: json['event_no'] as String? ?? '',
      name: json['name'] as String? ?? (defaultName.isNotEmpty ? defaultName : 'Yarış'),
      distance: dist,
      stroke: json['stroke'] as String? ?? '',
      strokeLabel: sLabel,
      gender: json['gender'] as String?,
      ageGroup: json['age_group'] as String?,
      isPending: json['is_pending'] as bool? ?? (json['status'] != 'Sonuçlandı'),
      status: json['status'] as String? ?? 'Bekliyor',
      totalAthletes: json['total_athletes'] as int? ?? 0,
    );
  }

  /// Temiz yarış başlığı (Mesafe + Stil, örn: "50m Serbest")
  String get displayTitle {
    final parts = <String>[];
    if (distance != null && distance! > 0) parts.add('${distance}m');
    if (strokeLabel.isNotEmpty) parts.add(strokeLabel);
    return parts.isNotEmpty ? parts.join(' ') : name;
  }

  /// Cinsiyet Etiketi (Erkekler / Kadınlar)
  String get genderLabel {
    if (gender == null || gender!.isEmpty) return '';
    final g = gender!.toLowerCase();
    if (g.contains('kad') || g.contains('bayan')) return 'Kadınlar';
    if (g.contains('erkek')) return 'Erkekler';
    return gender!;
  }
}

class LiveFeedResponse {
  final int liveId;
  final String status;
  final List<LiveEventProgramItem> events;
  final List<RaceResult> data;

  LiveFeedResponse({
    required this.liveId,
    required this.status,
    required this.events,
    required this.data,
  });

  factory LiveFeedResponse.fromJson(Map<String, dynamic> json) {
    final eventsRaw = json['events'] as List<dynamic>? ?? [];
    final dataRaw = json['data'] as List<dynamic>? ?? [];

    return LiveFeedResponse(
      liveId: json['live_id'] as int? ?? 0,
      status: json['status'] as String? ?? 'BEKLIYOR',
      events: eventsRaw
          .map((e) => LiveEventProgramItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      data: dataRaw
          .map((e) => RaceResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
