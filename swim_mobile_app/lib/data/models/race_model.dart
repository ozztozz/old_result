/// TYF Yüzme Sonuçları — Yarış Modeli
enum RaceStatus { completed, live, upcoming }

class RaceModel {
  final String id;
  final String distance;
  final String strokeName;
  final String gender;
  final String ageCategory;
  final RaceStatus status;
  final String? startTime;
  final String? heatLaneInfo;
  final String? winnerSummary;
  bool isFavorite;
  final dynamic rawEvent;

  RaceModel({
    required this.id,
    required this.distance,
    required this.strokeName,
    required this.gender,
    required this.ageCategory,
    required this.status,
    this.startTime,
    this.heatLaneInfo,
    this.winnerSummary,
    this.isFavorite = false,
    this.rawEvent,
  });
}

