import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/data/models/meet.dart';
import 'package:swim_mobile_app/data/models/race_result.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/features/live/live_meet_detail_screen.dart';
import 'package:swim_mobile_app/features/meets/meet_search_screen.dart';

class _FakeMeetSearchRepository implements SwimRepository {
  String? lastYear;
  String? lastCity;
  String? lastQ;
  String? lastClub;
  String? lastAthlete;
  String? lastGender;

  @override
  Future<List<MeetSummary>> searchMeets({
    int page = 1,
    String? year,
    String? city,
    String? q,
    String? club,
    String? athlete,
    String? gender,
  }) async {
    lastYear = year;
    lastCity = city;
    lastQ = q;
    lastClub = club;
    lastAthlete = athlete;
    lastGender = gender;

    return [
      MeetSummary(
        id: 766,
        name: 'ANTALYA 9-10-11-12 YAŞ ULUSAL GELİŞİM LİGİ',
        city: 'Antalya',
        startDate: '2026-04-12',
        endDate: '2026-04-14',
        course: 'LC',
        totalRaces: 24,
        totalAthletes: 450,
      ),
    ];
  }

  @override
  Future<MeetDetail> getMeetDetail(int id) async => MeetDetail(
        id: id,
        name: 'ANTALYA 9-10-11-12 YAŞ ULUSAL GELİŞİM LİGİ',
        city: 'Antalya',
        startDate: '2026-04-12',
        endDate: '2026-04-14',
        course: 'LC',
        totalRaces: 24,
        totalAthletes: 450,
        events: const [],
      );

  @override
  Future<MeetParticipants> getMeetParticipants(int id) async =>
      MeetParticipants(meetId: id, clubs: const [], athletes: const []);

  @override
  Future<List<RaceResult>> getMeetResults(
    int meetId, {
    String? eventNo,
    int? clubId,
    int? athleteId,
    String? status,
    int page = 1,
  }) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'MeetSearchScreen filters by year/gender/city/club/athlete and opens MeetDetailScreen on tap',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = _FakeMeetSearchRepository();

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
            child: MeetSearchScreen(repository: repo),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      expect(repo.lastYear, '2026');

      await tester.tap(find.text('Kadın'));
      await tester.pumpAndSettle();
      expect(repo.lastGender, 'Kadın');

      await tester.enterText(find.byType(TextField).at(1), 'Antalya');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repo.lastCity, 'Antalya');

      await tester.tap(find.textContaining('Antalya 9-10-11-12'));
      await tester.pumpAndSettle();
      expect(find.byType(LiveMeetDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
