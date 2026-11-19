import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/data/models/athlete.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/features/athletes/athlete_compare_screen.dart';
import 'package:swim_mobile_app/shared/widgets/modern_segmented_tab_bar.dart';

class _MockCompareRepository implements SwimRepository {
  bool failNextDetail = false;
  late AthleteDetail athleteB;

  @override
  Future<GlobalSearchResult> searchGlobal(String query) async {
    return GlobalSearchResult(
      athletes: [
        AthleteSearchItem(
          id: 2,
          name: athleteB.name,
          birthYear: athleteB.birthYear,
          clubName: athleteB.clubName ?? '',
        ),
      ],
      clubs: const [],
    );
  }

  @override
  Future<AthleteDetail> getAthleteDetail(int id) async {
    if (failNextDetail) {
      failNextDetail = false;
      throw Exception('Network error');
    }
    return athleteB;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PersonalBest _pb({
  required int distance,
  required String stroke,
  required String strokeLabel,
  int? timeCs,
  String course = 'LC',
}) {
  return PersonalBest(
    distance: distance,
    stroke: stroke,
    strokeLabel: strokeLabel,
    time: timeCs == null ? '' : '$timeCs',
    timeCs: timeCs,
    points: 700,
    date: '2025-05-10',
    meetName: 'Türkiye Şampiyonası',
    course: course,
  );
}

AthleteDetail _buildAthleteA() {
  return AthleteDetail(
    id: 1,
    name: 'MUHAMMED MUSTAFA KARADEMİROĞLU',
    gender: 'M',
    clubName: 'İSTANBUL BÜYÜKŞEHİR BELEDİYESİ SPOR KULÜBÜ',
    birthYear: 2006,
    age: 20,
    stats: AthleteStats(
      totalRaces: 128,
      podiumCount: 44,
      podiumRate: 34.4,
      standardsPassed: 19,
    ),
    scoutNote: '',
    pbs50m: [
      _pb(distance: 50, stroke: 'free', strokeLabel: 'Serbest', timeCs: 2345),
      _pb(distance: 100, stroke: 'free', strokeLabel: 'Serbest', timeCs: 5120),
      _pb(distance: 200, stroke: 'free', strokeLabel: 'Serbest', timeCs: 11240),
      _pb(distance: 400, stroke: 'free', strokeLabel: 'Serbest', timeCs: 24510),
      _pb(distance: 800, stroke: 'free', strokeLabel: 'Serbest', timeCs: 61012), // 10:10.12
      _pb(distance: 1500, stroke: 'free', strokeLabel: 'Serbest', timeCs: null), // both missing
      _pb(distance: 50, stroke: 'back', strokeLabel: 'Sırtüstü', timeCs: 2710),
      _pb(distance: 100, stroke: 'back', strokeLabel: 'Sırtüstü', timeCs: 5830),
      _pb(distance: 200, stroke: 'back', strokeLabel: 'Sırtüstü', timeCs: null), // A missing
      _pb(distance: 50, stroke: 'breast', strokeLabel: 'Kurbağalama', timeCs: 2940),
      _pb(distance: 100, stroke: 'breast', strokeLabel: 'Kurbağalama', timeCs: 6410),
      _pb(distance: 50, stroke: 'fly', strokeLabel: 'Kelebek', timeCs: 2490),
      _pb(distance: 100, stroke: 'fly', strokeLabel: 'Kelebek', timeCs: 5510),
      _pb(distance: 200, stroke: 'medley', strokeLabel: 'Karışık', timeCs: 12850),
    ],
    pbs25m: [
      _pb(distance: 50, stroke: 'free', strokeLabel: 'Serbest', timeCs: 2290, course: 'SC'),
    ],
  );
}

AthleteDetail _buildAthleteB() {
  return AthleteDetail(
    id: 2,
    name: 'ALİ EMRE YILDIZOĞLU',
    gender: 'M',
    clubName: 'FENERBAHÇE SPOR KULÜBÜ YÜZME ŞUBESİ',
    birthYear: 2005,
    age: 21,
    stats: AthleteStats(
      totalRaces: 96,
      podiumCount: 52,
      podiumRate: 54.2,
      standardsPassed: 19,
    ),
    scoutNote: '',
    pbs50m: [
      _pb(distance: 50, stroke: 'free', strokeLabel: 'Serbest', timeCs: 2446), // A faster by -1.01 s
      _pb(distance: 100, stroke: 'free', strokeLabel: 'Serbest', timeCs: 4841), // B faster by +2.79 s
      _pb(distance: 200, stroke: 'free', strokeLabel: 'Serbest', timeCs: 11300),
      _pb(distance: 400, stroke: 'free', strokeLabel: 'Serbest', timeCs: 24600),
      _pb(distance: 800, stroke: 'free', strokeLabel: 'Serbest', timeCs: 61500),
      _pb(distance: 1500, stroke: 'free', strokeLabel: 'Serbest', timeCs: null), // both missing
      _pb(distance: 50, stroke: 'back', strokeLabel: 'Sırtüstü', timeCs: 2750),
      _pb(distance: 100, stroke: 'back', strokeLabel: 'Sırtüstü', timeCs: 5910),
      _pb(distance: 200, stroke: 'back', strokeLabel: 'Sırtüstü', timeCs: 12500), // A missing, B present
      _pb(distance: 50, stroke: 'breast', strokeLabel: 'Kurbağalama', timeCs: 3010),
      _pb(distance: 100, stroke: 'breast', strokeLabel: 'Kurbağalama', timeCs: 6390),
      _pb(distance: 50, stroke: 'fly', strokeLabel: 'Kelebek', timeCs: null), // B missing
      _pb(distance: 100, stroke: 'fly', strokeLabel: 'Kelebek', timeCs: 5490),
      _pb(distance: 200, stroke: 'medley', strokeLabel: 'Karışık', timeCs: 12910),
    ],
    pbs25m: [
      _pb(distance: 50, stroke: 'free', strokeLabel: 'Serbest', timeCs: 2310, course: 'SC'),
    ],
  );
}

Widget _wrapTest({
  required ThemeData theme,
  required AthleteDetail athleteA,
  required SwimRepository repository,
}) {
  return MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(360, 780),
        textScaler: TextScaler.linear(1.3),
        padding: EdgeInsets.only(top: 24, bottom: 16),
      ),
      child: AthleteCompareScreen(
        athleteA: athleteA,
        repository: repository,
      ),
    ),
  );
}

void main() {
  for (final isDark in [false, true]) {
    final themeLabel = isDark ? 'dark' : 'light';
    testWidgets(
      'AthleteCompareScreen renders empty, 14-row comparison, and error states without overflow ($themeLabel)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = _MockCompareRepository()..athleteB = _buildAthleteB();
        final athleteA = _buildAthleteA();
        final theme = isDark ? AppTheme.dark() : AppTheme.light();

        await tester.pumpWidget(
          _wrapTest(theme: theme, athleteA: athleteA, repository: repo),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Sporcu Karşılaştırma'), findsOneWidget);
        expect(
          find.text('Karşılaştırmak için ikinci sporcuyu seç'),
          findsOneWidget,
        );
        expect(find.text('Sporcu Seç'), findsOneWidget);

        // Search and trigger an error first
        repo.failNextDetail = true;
        await tester.enterText(find.byType(TextField), 'Ali');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(find.byType(ListTile), findsOneWidget);
        await tester.tap(find.byType(ListTile).first);
        await tester.pumpAndSettle();

        expect(find.text('Tekrar dene'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Retry and load second athlete
        await tester.tap(find.text('Tekrar dene'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(ModernSegmentedTabBar), findsOneWidget);
        expect(find.text('10:10.12'), findsOneWidget);
        expect(find.text('-1.01 s'), findsOneWidget);
        expect(find.text('+2.79 s'), findsOneWidget);
        expect(find.text('–'), findsWidgets);
        expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(2));
        expect(find.byIcon(Icons.arrow_drop_down_outlined), findsWidgets);

        // Scroll to verify all 14 event rows render cleanly without overflow
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(find.text('200m Karışık'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Switch to 25m pool tab
        await tester.drag(find.byType(ListView), const Offset(0, 600));
        await tester.pumpAndSettle();
        await tester.tap(find.text('25m Kısa Kulvar'));
        await tester.pumpAndSettle();
        expect(find.text('22.90'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
