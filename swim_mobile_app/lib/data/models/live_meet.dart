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
