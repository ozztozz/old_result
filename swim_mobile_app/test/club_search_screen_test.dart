import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swim_mobile_app/core/services/selected_club_service.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/data/models/athlete.dart';
import 'package:swim_mobile_app/data/models/live_meet.dart';
import 'package:swim_mobile_app/data/models/meet.dart';
import 'package:swim_mobile_app/data/models/tyf_news.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/features/clubs/club_search_screen.dart';
import 'package:swim_mobile_app/features/home/home_screen.dart';

class _FakeClubSearchRepository implements SwimRepository {
  String? lastQuery;
  String? lastType;
  String? lastCity;
  String? lastLetter;
  String? lastKind;
  int lastPage = 1;
  bool returnFullPage = false;

  @override
  Future<List<ClubSearchItem>> searchClubs({
    int page = 1,
    String? q,
    String? city,
    String? letter,
    String kind = 'club',
    double? lat,
    double? lon,
  }) async {
    lastPage = page;
    lastQuery = q;
    lastCity = city;
    lastLetter = letter;
    lastKind = kind;
    if (returnFullPage) {
      if (page == 1) {
        return List.generate(
          25,
          (i) => ClubSearchItem(
            id: i + 1,
            name: 'BURSA KULÜBÜ ${i + 1}',
            city: 'BURSA',
            athleteCount: 50 + i,
          ),
        );
      }
      return [
        ClubSearchItem(
          id: 26,
          name: 'BURSA KULÜBÜ 26',
          city: 'BURSA',
          athleteCount: 99,
        ),
      ];
    }
    return [
      ClubSearchItem(
        id: 42,
        name: 'FENERBAHÇE SPOR KULÜBÜ',
        city: 'İSTANBUL',
        athleteCount: 312,
      ),
    ];
  }

  @override
  Future<GlobalSearchResult> searchGlobal(
    String q, {
    String type = 'all',
    String? city,
  }) async {
    lastQuery = q;
    lastType = type;
    lastCity = city;
    return GlobalSearchResult(
      athletes: const [],
      clubs: [
        ClubSearchItem(
          id: 42,
          name: 'FENERBAHÇE SPOR KULÜBÜ',
          city: 'İSTANBUL',
          athleteCount: 312,
        ),
      ],
    );
  }

  @override
  Future<List<MeetSummary>> getMeets({
    int page = 1,
    String? year,
    String? city,
    String? q,
  }) async =>
      const [];

  @override
  Future<List<TyfNewsItem>> getNewsFeed({String? type, int limit = 15}) async =>
      const [];

  @override
  Future<List<LiveMeetSummary>> getLiveMeets() async => const [];

  @override
  Future<List<LiveMeetSummary>> getClubLiveMeets({int? clubId, String? clubName}) async => const [];

  @override
  Future<List<Map<String, dynamic>>> getHighlightsFeed({
    List<int> athleteIds = const [],
    int? clubId,
    String? clubName,
  }) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'ClubSearchScreen searches clubs and allows selecting a team at 360x780 textScale 1.3',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await SelectedClubService.instance.clearClub();
      final repo = _FakeClubSearchRepository();

      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(const CoolSophisticatedLightPalette()),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
            ),
            child: ClubSearchScreen(repository: repo),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Fenerbahçe');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(repo.lastQuery, 'Fenerbahçe');
      expect(find.textContaining('Fenerbahçe Spor Kulübü'), findsOneWidget);
      expect(find.text('İstanbul · 312 Kayıtlı Sporcu'), findsOneWidget);

      await tester.tap(find.text('İstanbul'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repo.lastCity, 'İstanbul');

      await tester.enterText(find.byType(TextField).at(1), 'Ankara');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repo.lastCity, 'Ankara');

      await tester.tap(find.textContaining('Fenerbahçe Spor Kulübü'));
      await tester.pumpAndSettle();

      expect(find.text('Takımım Olarak Seç'), findsOneWidget);
      expect(find.text('Kulübün Müsabakalarını Gör'), findsOneWidget);

      await tester.tap(find.text('Takımım Olarak Seç'));
      await tester.pumpAndSettle();

      expect(SelectedClubService.instance.hasSelectedClub, isTrue);
      expect(SelectedClubService.instance.clubId, 42);
      expect(find.text('Seçili'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'HomeScreen shows Kulüp Ara card and opens ClubSearchScreen on tap',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await SelectedClubService.instance.clearClub();
      final repo = _FakeClubSearchRepository();

      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(const CoolSophisticatedLightPalette()),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
            ),
            child: HomeScreen(repository: repo),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('KULÜPLER'), findsOneWidget);

      await tester.tap(find.text('KULÜPLER'));
      await tester.pumpAndSettle();

      expect(find.byType(ClubSearchScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ClubSearchScreen supports alphabetical letter filter with pagination',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await SelectedClubService.instance.clearClub();
      final repo = _FakeClubSearchRepository()..returnFullPage = true;

      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(const CoolSophisticatedLightPalette()),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
            ),
            child: ClubSearchScreen(repository: repo),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      expect(repo.lastLetter, 'B');
      expect(repo.lastKind, 'club');
      expect(repo.lastPage, 1);
      expect(find.text('Bursa Kulübü 1'), findsOneWidget);

      await tester.tap(find.text('Okul'));
      await tester.pumpAndSettle();
      expect(repo.lastKind, 'school');

      await tester.tap(find.text('Takım'));
      await tester.pumpAndSettle();
      expect(repo.lastKind, 'club');

      await tester.ensureVisible(find.text('Daha Fazla Yükle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daha Fazla Yükle'));
      await tester.pumpAndSettle();

      expect(repo.lastPage, 2);
      expect(find.text('Bursa Kulübü 26'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
