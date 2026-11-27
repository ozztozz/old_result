import '../../core/network/api_client.dart';
import '../models/meet.dart';
import '../models/race_result.dart';
import '../models/athlete.dart';
import '../models/live_meet.dart';
import '../models/tyf_news.dart';
import '../models/calendar_event.dart';
import '../models/baraj_rule.dart';

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
    int? clubId,
    String? club,
    String? athlete,
    String? gender,
  }) async {
    final query = <String, dynamic>{'page': page};
    if (year != null && year.isNotEmpty) query['year'] = year;
    if (city != null && city.isNotEmpty) query['city'] = city;
    if (q != null && q.isNotEmpty) query['q'] = q;
    if (clubId != null && clubId > 0) query['club_id'] = clubId.toString();
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
    bool summary = false,
  }) async {
    final query = <String, dynamic>{'page': page};
    if (eventNo != null && eventNo.isNotEmpty) query['event_no'] = eventNo;
    if (clubId != null) query['club_id'] = clubId;
    if (athleteId != null) query['athlete_id'] = athleteId;
    if (status != null && status != 'all') query['status'] = status;
    if (summary) query['summary'] = '1';

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

  /// Sporcunun branş/mesafe bazlı veya tüm sezon hedef reglaman barajları
  Future<List<Map<String, dynamic>>> getAthleteBarajTargets(
    int athleteId, {
    String? stroke,
    int? distance,
    String? course,
    int? pbCs,
  }) async {
    final query = <String, dynamic>{};
    if (stroke != null && stroke.isNotEmpty) query['stroke'] = stroke;
    if (distance != null) query['distance'] = distance;
    if (course != null && course.isNotEmpty) query['course'] = course;
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

  /// Seçili kulübün katıldığı canlı müsabakalar
  Future<List<LiveMeetSummary>> getClubLiveMeets({
    int? clubId,
    String? clubName,
  }) async {
    final query = <String, dynamic>{};
    if (clubId != null && clubId > 0) query['club_id'] = clubId.toString();
    if (clubName != null && clubName.trim().isNotEmpty) {
      query['club_name'] = clubName.trim();
    }
    final res = await apiClient.get(
      '/live/club/',
      queryParameters: query.isEmpty ? null : query,
    );
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

  /// Sayfalı ve alfabetik/il/tür/konum filtreli kulüp arama
  Future<List<ClubSearchItem>> searchClubs({
    int page = 1,
    String? q,
    String? city,
    String? letter,
    String kind = 'club',
    double? lat,
    double? lon,
  }) async {
    final query = <String, dynamic>{'page': page, 'kind': kind};
    if (q != null && q.trim().isNotEmpty) query['q'] = q.trim();
    if (city != null && city.trim().isNotEmpty) query['city'] = city.trim();
    if (letter != null && letter.trim().isNotEmpty) {
      query['letter'] = letter.trim();
    }
    if (lat != null && lon != null) {
      query['lat'] = lat;
      query['lon'] = lon;
    }
    final res = await apiClient.get('/clubs/', queryParameters: query);
    final list = res.data['data'] as List<dynamic>? ?? [];
    return list
        .map((e) => ClubSearchItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Harita üzerinde gösterilecek koordinatlı kulüpler
  Future<List<ClubSearchItem>> getMapClubs({
    String? q,
    String? city,
    String kind = 'all',
  }) async {
    final query = <String, dynamic>{'kind': kind};
    if (q != null && q.trim().isNotEmpty) query['q'] = q.trim();
    if (city != null && city.trim().isNotEmpty) query['city'] = city.trim();
    final res = await apiClient.get('/clubs/map/', queryParameters: query);
    final list = res.data['data'] as List<dynamic>? ?? [];
    return list
        .map((e) => ClubSearchItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Kulüp Profili, İletişim/Sosyal Medya ve Sporcu Özeti
  Future<ClubDetailModel> getClubDetail(int clubId) async {
    final res = await apiClient.get('/clubs/$clubId/');
    return ClubDetailModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// Genel arama (Autocomplete)
  Future<GlobalSearchResult> searchGlobal(
    String q, {
    String type = 'all',
    String? city,
  }) async {
    final query = <String, dynamic>{'q': q};
    if (type != 'all') query['type'] = type;
    if (city != null && city.trim().isNotEmpty) query['city'] = city.trim();
    final res = await apiClient.get('/search/', queryParameters: query);
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

  /// TYF Takvim, Reglaman ve Milli Takım Kriterleri Haber Bandı
  Future<List<TyfNewsItem>> getNewsFeed({String? type, int limit = 15}) async {
    final query = <String, dynamic>{'limit': limit};
    if (type != null && type.isNotEmpty) query['type'] = type;

    final res = await apiClient.get('/news-feed/', queryParameters: query);
    final list = res.data['data'] as List<dynamic>? ?? [];
    return list
        .map((e) => TyfNewsItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Ulusal (TYF) ve İl Etkinlik Takvimi
  Future<CalendarFeedResponse> getEventCalendar({
    String scope = 'all',
    String? city,
    String? pool,
    int? age,
    String? q,
    bool includePast = false,
  }) async {
    final query = <String, dynamic>{'scope': scope};
    if (city != null && city.isNotEmpty) query['city'] = city;
    if (pool != null && pool.isNotEmpty) query['pool'] = pool;
    if (age != null) query['age'] = age.toString();
    if (q != null && q.isNotEmpty) query['q'] = q;
    if (includePast) query['include_past'] = '1';

    final res = await apiClient.get('/calendar/', queryParameters: query);
    final list = res.data['data'] as List<dynamic>? ?? [];
    final meta = res.data['meta'] as Map<String, dynamic>? ?? {};
    final citiesRaw = meta['cities'] as List<dynamic>? ?? [];
    return CalendarFeedResponse(
      events: list
          .map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      cities: citiesRaw.map((c) => c.toString()).toList(),
    );
  }

  /// Resmi TYF Katılım & Harcırah Barajları
  Future<BarajFeedResponse> getBarajlar({
    String? barajAdi,
    int? eventId,
    String? city,
    String? month,
    String? barajTuru,
    String? havuz,
    String? cinsiyet,
    String? yas,
    String? stil,
  }) async {
    final query = <String, dynamic>{};
    if (eventId != null) query['event_id'] = eventId;
    if (barajAdi != null && barajAdi.isNotEmpty) query['baraj_adi'] = barajAdi;
    if (city != null && city.isNotEmpty) query['city'] = city;
    if (month != null && month.isNotEmpty) query['month'] = month;
    if (barajTuru != null && barajTuru.isNotEmpty) query['baraj_turu'] = barajTuru;
    if (havuz != null && havuz.isNotEmpty) query['havuz'] = havuz;
    if (cinsiyet != null && cinsiyet.isNotEmpty) query['cinsiyet'] = cinsiyet;
    if (yas != null && yas.isNotEmpty) query['yas'] = yas;
    if (stil != null && stil.isNotEmpty) query['stil'] = stil;

    final res = await apiClient.get('/barajlar/', queryParameters: query);
    final list = res.data['data'] as List<dynamic>? ?? [];
    final meta = res.data['meta'] as Map<String, dynamic>? ?? {};
    final names = meta['baraj_names'] as List<dynamic>? ?? [];
    final eventsRaw = meta['events'] as List<dynamic>? ?? [];
    final citiesRaw = meta['cities'] as List<dynamic>? ?? [];
    final monthsRaw = meta['months'] as List<dynamic>? ?? [];
    final ages = meta['age_labels'] as List<dynamic>? ?? [];
    return BarajFeedResponse(
      rules: list
          .map((e) => BarajRule.fromJson(e as Map<String, dynamic>))
          .toList(),
      barajNames: names.map((e) => e.toString()).toList(),
      events: eventsRaw
          .map((e) => BarajEventOption.fromJson(e as Map<String, dynamic>))
          .toList(),
      cities: citiesRaw.map((e) => e.toString()).toList(),
      months: monthsRaw.map((e) => e.toString()).toList(),
      ageLabels: ages.map((e) => e.toString()).toList(),
    );
  }

  /// Seçili kulübün seçilen barajdaki sporcu durumları
  Future<ClubBarajStatusResponse> getClubBarajStatus({
    int? clubId,
    String? clubName,
    int? eventId,
    String? barajAdi,
    String? barajTuru,
    String? havuz,
  }) async {
    final query = <String, dynamic>{};
    if (clubId != null && clubId > 0) query['club_id'] = clubId.toString();
    if (clubName != null && clubName.trim().isNotEmpty) {
      query['club_name'] = clubName.trim();
    }
    if (eventId != null) query['event_id'] = eventId.toString();
    if (barajAdi != null && barajAdi.trim().isNotEmpty) {
      query['baraj_adi'] = barajAdi.trim();
    }
    if (barajTuru != null && barajTuru.trim().isNotEmpty) {
      query['baraj_turu'] = barajTuru.trim();
    }
    if (havuz != null && havuz.trim().isNotEmpty) {
      query['havuz'] = havuz.trim();
    }

    final res =
        await apiClient.get('/clubs/baraj-status/', queryParameters: query);
    return ClubBarajStatusResponse.fromJson(res.data as Map<String, dynamic>);
  }
}

