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

  /// Gelişmiş müsabaka arama (yıl, il, takım, sporcu, cinsiyet filtreli)
  Future<List<MeetSummary>> searchMeets({
    int page = 1,
    String? year,
    String? city,
    String? q,
    String? club,
    String? athlete,
    String? gender,
  }) async {
    final query = <String, dynamic>{'page': page};
    if (year != null && year.isNotEmpty) query['year'] = year;
    if (city != null && city.isNotEmpty) query['city'] = city;
    if (q != null && q.isNotEmpty) query['q'] = q;
    if (club != null && club.isNotEmpty) query['club'] = club;
    if (athlete != null && athlete.isNotEmpty) query['athlete'] = athlete;
    if (gender != null && gender.isNotEmpty) query['gender'] = gender;

    final res = await apiClient.get('/meets/', queryParameters: query);
    final list = res.data['data'] as List<dynamic>? ?? [];
    return list
        .map((e) => MeetSummary.fromJson(e as Map<String, dynamic>))
        .toList();
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

  /// Sporcunun branş/mesafe bazlı hedef reglaman barajları
  Future<List<Map<String, dynamic>>> getAthleteBarajTargets(
    int athleteId, {
    required String stroke,
    required int distance,
    required String course,
    int? pbCs,
  }) async {
    final query = <String, dynamic>{
      'stroke': stroke,
      'distance': distance,
      'course': course,
    };
    if (pbCs != null) query['pb_cs'] = pbCs;

    final res = await apiClient.get(
      '/athletes/$athleteId/baraj-targets/',
      queryParameters: query,
    );
    final list = res.data['data'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Favori sporcular için toplu özet
  Future<List<AthleteSummaryItem>> getAthletesSummary(List<int> ids) async {
    if (ids.isEmpty) return [];
    final res = await apiClient.get('/athletes/summary/', queryParameters: {
      'ids': ids.join(','),
    });
    final list = res.data['data'] as List<dynamic>? ?? [];
    return list
        .map((e) => AthleteSummaryItem.fromJson(e as Map<String, dynamic>))
        .toList();
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
    if (eventNo != null && eventNo.isNotEmpty) {
      query['event_no'] = eventNo;
      query['include_events'] = '0';
    }
    if (status != null && status != 'all') query['status'] = status;

    final res = await apiClient.get('/live/$liveId/feed/', queryParameters: query);
    return res.data as Map<String, dynamic>;
  }

  /// Canlı müsabaka yarış başlıkları (sonuç satırları olmadan hafif liste)
  Future<LiveFeedResponse> getLiveEvents(int liveId) async {
    final res = await apiClient.get(
      '/live/$liveId/feed/',
      queryParameters: {'events_only': '1'},
    );
    return LiveFeedResponse.fromJson(res.data as Map<String, dynamic>);
  }

  /// Canlı müsabaka özet akışı (yarış başlıkları + her yarışın ilk 3'ü + seçili kulüp/sporcu)
  Future<LiveFeedResponse> getLiveSummary(
    int liveId, {
    int? clubId,
    String? clubName,
    String? athleteName,
  }) async {
    final query = <String, dynamic>{'summary': '1'};
    if (clubId != null) query['club_id'] = clubId;
    if (clubName != null && clubName.isNotEmpty) query['club_name'] = clubName;
    if (athleteName != null && athleteName.isNotEmpty) {
      query['athlete_name'] = athleteName;
    }

    final res = await apiClient.get('/live/$liveId/feed/', queryParameters: query);
    return LiveFeedResponse.fromJson(res.data as Map<String, dynamic>);
  }

  /// Canlı yarış akışı (Typed LiveFeedResponse)
  Future<LiveFeedResponse> getLiveFeedResponse(
    int liveId, {
    String? eventNo,
    String? status,
  }) async {
    final map = await getLiveFeed(liveId, eventNo: eventNo, status: status);
    return LiveFeedResponse.fromJson(map);
  }

  /// Genel arama (Autocomplete)
  Future<GlobalSearchResult> searchGlobal(String q) async {
    final res = await apiClient.get('/search/', queryParameters: {'q': q});
    return GlobalSearchResult.fromJson(res.data as Map<String, dynamic>);
  }

  /// Kulüp Bayrak Takımı Simülatörü
  Future<Map<String, dynamic>> getRelaySimulator({
    int? clubId,
    String? clubName,
    String relayType = '4x50_free',
    String gender = 'Erkek',
    String course = 'LC',
    int? birthYear,
  }) async {
    final query = <String, dynamic>{
      'relay_type': relayType,
      'gender': gender,
      'course': course,
    };
    if (clubId != null) query['club_id'] = clubId;
    if (clubName != null && clubName.isNotEmpty) query['club_name'] = clubName;
    if (birthYear != null) query['birth_year'] = birthYear;

    final res = await apiClient.get('/clubs/relay-simulator/', queryParameters: query);
    return (res.data['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Branş / Yaş / İl Top 25 Sıralamaları
  Future<List<Map<String, dynamic>>> getRankings({
    String stroke = 'free',
    int distance = 50,
    String gender = 'Erkek',
    String course = 'LC',
    int? birthYear,
    String? city,
  }) async {
    final query = <String, dynamic>{
      'stroke': stroke,
      'distance': distance,
      'gender': gender,
      'course': course,
    };
    if (birthYear != null) query['birth_year'] = birthYear;
    if (city != null && city.isNotEmpty) query['city'] = city;

    final res = await apiClient.get('/rankings/', queryParameters: query);
    final list = res.data['data'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Favori Sporcu & Kulüp Canlı Özet / Baraj Akışı
  Future<List<Map<String, dynamic>>> getHighlightsFeed({
    List<int> athleteIds = const [],
    int? clubId,
    String? clubName,
  }) async {
    final query = <String, dynamic>{};
    if (athleteIds.isNotEmpty) query['athlete_ids'] = athleteIds.join(',');
    if (clubId != null) query['club_id'] = clubId;
    if (clubName != null && clubName.isNotEmpty) query['club_name'] = clubName;

    final res = await apiClient.get('/highlights/', queryParameters: query);
    final list = res.data['data'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>();
  }
}

