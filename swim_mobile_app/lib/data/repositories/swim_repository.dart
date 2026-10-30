import '../../core/network/api_client.dart';
import '../models/meet.dart';
import '../models/race_result.dart';
import '../models/athlete.dart';
import '../models/live_meet.dart';

/// Mobil API Servislerini Yöneten Ana Veri Deposu (Repository)
class SwimRepository {
  final ApiClient apiClient;

  SwimRepository({required this.apiClient});

  /// Müsabakalar listesi
  Future<List<MeetSummary>> getMeets({
    int page = 1,
    String? year,
    String? city,
    String? q,
  }) async {
    final query = <String, dynamic>{'page': page};
    if (year != null && year.isNotEmpty) query['year'] = year;
    if (city != null && city.isNotEmpty) query['city'] = city;
    if (q != null && q.isNotEmpty) query['q'] = q;

    final res = await apiClient.get('/meets/', queryParameters: query);
    final list = res.data['data'] as List<dynamic>? ?? [];
    return list.map((e) => MeetSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Müsabaka genel detay ve yarış programı
  Future<MeetDetail> getMeetDetail(int meetId) async {
    final res = await apiClient.get('/meets/$meetId/');
    return MeetDetail.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// Müsabaka katılımcıları (0 ms bağımlı filtre için)
  Future<MeetParticipants> getMeetParticipants(int meetId) async {
    final res = await apiClient.get('/meets/$meetId/participants/');
    return MeetParticipants.fromJson(res.data as Map<String, dynamic>);
  }

  /// Filtrelenmiş yarış sonuçları
  Future<List<RaceResult>> getMeetResults(
    int meetId, {
    String? eventNo,
    int? clubId,
    int? athleteId,
    String? status,
    int page = 1,
  }) async {
    final query = <String, dynamic>{'page': page};
    if (eventNo != null && eventNo.isNotEmpty) query['event_no'] = eventNo;
    if (clubId != null) query['club_id'] = clubId;
    if (athleteId != null) query['athlete_id'] = athleteId;
    if (status != null && status != 'all') query['status'] = status;

    final res = await apiClient.get('/meets/$meetId/results/', queryParameters: query);
    final list = res.data['data'] as List<dynamic>? ?? [];
    return list.map((e) => RaceResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Sporcu profili, kariyer istatistikleri ve 25m/50m PB tablosu
  Future<AthleteDetail> getAthleteDetail(int athleteId) async {
    final res = await apiClient.get('/athletes/$athleteId/');
    return AthleteDetail.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  /// Sporcunun yarış geçmişi
  Future<List<AthleteRaceHistoryItem>> getAthleteRaces(
    int athleteId, {
    String? stroke,
    int? distance,
    String? year,
    int page = 1,
  }) async {
    final query = <String, dynamic>{'page': page};
    if (stroke != null && stroke.isNotEmpty) query['stroke'] = stroke;
    if (distance != null) query['distance'] = distance;
    if (year != null && year.isNotEmpty) query['year'] = year;

    final res = await apiClient.get('/athletes/$athleteId/races/', queryParameters: query);
    final list = res.data['data'] as List<dynamic>? ?? [];
    return list.map((e) => AthleteRaceHistoryItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Favori sporcular için toplu özet
  Future<List<Map<String, dynamic>>> getAthletesSummary(List<int> ids) async {
    if (ids.isEmpty) return [];
    final res = await apiClient.get('/athletes/summary/', queryParameters: {
      'ids': ids.join(','),
    });
    final list = res.data['data'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Canlı yarış oturumları listesi
  Future<List<LiveMeetSummary>> getLiveMeets() async {
    final res = await apiClient.get('/live/');
    final list = res.data['data'] as List<dynamic>? ?? [];
    return list.map((e) => LiveMeetSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Canlı yarış akışı (Seri & Kulvar)
  Future<Map<String, dynamic>> getLiveFeed(
    int liveId, {
    String? eventNo,
    String? status,
  }) async {
    final query = <String, dynamic>{};
    if (eventNo != null && eventNo.isNotEmpty) query['event_no'] = eventNo;
    if (status != null && status != 'all') query['status'] = status;

    final res = await apiClient.get('/live/$liveId/feed/', queryParameters: query);
    return res.data as Map<String, dynamic>;
  }

  /// Genel arama (Autocomplete)
  Future<Map<String, dynamic>> searchGlobal(String q) async {
    final res = await apiClient.get('/search/', queryParameters: {'q': q});
    return res.data as Map<String, dynamic>;
  }
}
