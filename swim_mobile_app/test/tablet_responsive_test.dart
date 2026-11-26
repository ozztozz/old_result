import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swim_mobile_app/core/services/favorite_athletes_service.dart';
import 'package:swim_mobile_app/core/services/selected_club_service.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/data/models/athlete.dart';
import 'package:swim_mobile_app/data/models/baraj_rule.dart';
import 'package:swim_mobile_app/data/models/live_meet.dart';
import 'package:swim_mobile_app/data/models/meet.dart';
import 'package:swim_mobile_app/data/models/tyf_news.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/features/athletes/athlete_profile_screen.dart';
import 'package:swim_mobile_app/features/barajlar/barajlar_screen.dart';
import 'package:swim_mobile_app/features/clubs/club_detail_screen.dart';
import 'package:swim_mobile_app/features/favorites/favorites_screen.dart';
import 'package:swim_mobile_app/features/home/home_screen.dart';
import 'package:swim_mobile_app/features/live/live_screen.dart';
import 'package:swim_mobile_app/shared/widgets/app_scaffold.dart';

class _TabletFakeRepository implements SwimRepository {
  @override
  Future<List<LiveMeetSummary>> getLiveMeets() async => [
        LiveMeetSummary(
          id: 1,
          name: 'TÜRKİYE YAZ ŞAMPİYONASI',
          city: 'İstanbul',
          date: '2026-07-10',
          status: 'CANLI',
          totalAthletes: 800,
          startListProgress: LiveProgress(processed: 20, total: 20),
          resultListProgress: LiveProgress(processed: 10, total: 20),
        ),
        LiveMeetSummary(
          id: 2,
          name: 'ANKARA İL BİRİNCİLİĞİ',
          city: 'Ankara',
          date: '2026-07-12',
          status: 'TAMAMLANDI',
          totalAthletes: 450,
          startListProgress: LiveProgress(processed: 15, total: 15),
          resultListProgress: LiveProgress(processed: 15, total: 15),
        ),
      ];

  @override
  Future<List<TyfNewsItem>> getNewsFeed({String? type, int limit = 15}) async =>
      const [];

  @override
  Future<LiveFeedResponse> getLiveSummary(
    int liveMeetId, {
    int? clubId,
    String? clubName,
    String? athleteName,
  }) async =>
      LiveFeedResponse(
        liveId: liveMeetId,
        status: 'CANLI',
        events: [
          LiveEventProgramItem(
            eventNo: '1',
            name: '100m Serbest',
            distance: 100,
            stroke: 'free',
            strokeLabel: 'Serbest',
            gender: 'Erkekler',
            isPending: false,
            status: 'Sonuçlandı',
            totalAthletes: 16,
          ),
        ],
        data: const [],
      );

  @override
  Future<MeetParticipants> getMeetParticipants(int meetId) async =>
      MeetParticipants(meetId: meetId, clubs: const [], athletes: const []);

  @override
  Future<List<AthleteSummaryItem>> getAthletesSummary(List<int> ids) async => [
        AthleteSummaryItem(
          id: 1,
          name: 'EMRE SAKÇI',
          birthYear: 1997,
          clubName: 'FENERBAHÇE SK',
          latestRace: AthleteRaceBrief(
            distance: 50,
            stroke: 'KURBAĞALAMA',
            time: '26.83',
            points: 890,
          ),
          topPerformance: AthleteRaceBrief(
            distance: 50,
            stroke: 'KURBAĞALAMA',
            time: '26.83',
            points: 890,
          ),
        ),
        AthleteSummaryItem(
          id: 2,
          name: 'ZEYNEP GÜLŞAH ÇETİNKAYA',
          birthYear: 2008,
          clubName: 'ENKA SK',
          latestRace: AthleteRaceBrief(
            distance: 100,
            stroke: 'KELEBEK',
            time: '1:02.10',
            points: 720,
          ),
          topPerformance: AthleteRaceBrief(
            distance: 100,
            stroke: 'KELEBEK',
            time: '1:02.10',
            points: 720,
          ),
        ),
      ];

  @override
  Future<AthleteDetail> getAthleteDetail(int id) async => AthleteDetail(
        id: id,
        name: 'ÇAĞAN YUSUF TUNÇ',
        gender: 'M',
        clubName: 'FATİH KARAKURT ALPHA ACADEMY SPOR KULÜBÜ',
        birthYear: 2012,
        age: 14,
        stats: AthleteStats(
          totalRaces: 75,
          podiumCount: 20,
          podiumRate: 26.7,
          standardsPassed: 29,
        ),
        scoutNote: 'İyi çıkış ve düzenli gelişim.',
        pbs50m: [
          PersonalBest(
            distance: 50,
            stroke: 'Freestyle',
            strokeLabel: 'Serbest',
            time: '29.27',
            timeCs: 2927,
            points: 450,
            date: '2026-05-01',
            meetName: 'Test Müsabakası',
            course: 'LC',
          ),
        ],
        pbs25m: const [],
      );

  @override
  Future<List<Map<String, dynamic>>> getAthleteBarajTargets(
    int athleteId, {
    String? stroke,
    int? distance,
    String? course,
    int? pbCs,
  }) async =>
      const [];

  @override
  Future<BarajFeedResponse> getBarajlar({
    String? barajAdi,
    int? eventId,
    String? city,
    String? month,
    String? cinsiyet,
    String? yas,
    String? havuz,
    String? stil,
    String? barajTuru,
  }) async =>
      const BarajFeedResponse(
        rules: [
          BarajRule(
            id: 1,
            barajAdi: 'TÜRKİYE YAZ ŞAMPİYONASI',
            barajTuru: 'Katılım Barajı',
            cinsiyet: 'Erkek',
            yasEtiketi: '14 Yaş',
            stil: 'Serbest',
            mesafe: 50,
            havuz: '50m',
            sure: '26.24',
            sureCs: 2624,
          ),
          BarajRule(
            id: 2,
            barajAdi: 'TÜRKİYE YAZ ŞAMPİYONASI',
            barajTuru: 'Katılım Barajı',
            cinsiyet: 'Kadın',
            yasEtiketi: '14 Yaş',
            stil: 'Kelebek',
            mesafe: 100,
            havuz: '50m',
            sure: '1:08.50',
            sureCs: 6850,
          ),
        ],
        barajNames: ['TÜRKİYE YAZ ŞAMPİYONASI'],
        ageLabels: ['14 Yaş'],
      );

  @override
  Future<ClubDetailModel> getClubDetail(int clubId) async => ClubDetailModel(
        id: clubId,
        name: 'FENERBAHÇE SPOR KULÜBÜ',
        city: 'İstanbul',
        isSchool: false,
        athleteCount: 120,
        raceCount: 840,
        phone: '0216 000 00 00',
        summary: ClubSummaryModel.fromJson(const {}),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('AppScaffold uses bottom nav on phone and NavigationRail on tablet',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Phone (< 600px)
    tester.view.physicalSize = const Size(360, 780);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppScaffold(
          currentIndex: 0,
          onNavigationChanged: (_) {},
          screens: const [
            Center(child: Text('Tab 0')),
            Center(child: Text('Tab 1')),
            Center(child: Text('Tab 2')),
          ],
        ),
      ),
    );
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.takeException(), isNull);

    // Tablet (>= 600px)
    tester.view.physicalSize = const Size(1024, 768);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HomeScreen and FavoritesScreen render tablet layouts without overflow',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await SelectedClubService.instance.clearClub();
    await FavoriteAthletesService.instance.clearAll();
    await FavoriteAthletesService.instance.toggleFavorite(1);
    await FavoriteAthletesService.instance.toggleFavorite(2);

    final repo = _TabletFakeRepository();
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomeScreen(repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('BARAJLAR'), findsOneWidget);
    expect(find.text('KULÜPLER'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: FavoritesScreen(repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Emre Sakçı'), findsOneWidget);
    expect(find.text('Zeynep Gülşah Çetinkaya'), findsOneWidget);
  });

  testWidgets('LiveScreen uses Master-Detail layout on tablet landscape',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _TabletFakeRepository();
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1024, 768),
            disableAnimations: true,
          ),
          child: LiveScreen(repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Canlı Takip'), findsOneWidget);
    expect(find.text('Ankara · 12 Tem'), findsOneWidget);

    await tester.tap(find.text('Ankara · 12 Tem'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'AthleteProfileScreen, BarajlarScreen and ClubDetailScreen render cleanly on tablet',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _TabletFakeRepository();
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AthleteProfileScreen(
          athleteId: 1,
          athleteName: 'ÇAĞAN YUSUF TUNÇ',
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Sporcu Profili'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: BarajlarScreen(repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Resmi Barajlar'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ClubDetailScreen(
          clubId: 1,
          clubName: 'FENERBAHÇE SPOR KULÜBÜ',
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Kulüp Detayı'), findsOneWidget);
  });
}
