import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/features/athletes/athlete_profile_screen.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/data/models/athlete.dart';
import 'package:swim_mobile_app/data/models/baraj_rule.dart';

class MockSwimRepository implements SwimRepository {
  @override
  Future<AthleteDetail> getAthleteDetail(int id) async {
    return AthleteDetail(
      id: id,
      name: 'Emre Sakçı',
      gender: 'M',
      clubName: 'Fenerbahçe SK',
      birthYear: 1997,
      age: 27,
      stats: AthleteStats(
        totalRaces: 42,
        podiumCount: 31,
        podiumRate: 73.8,
        standardsPassed: 14,
      ),
      scoutNote: 'Çıkış ve su altı reaksiyon süresi dünya standartlarında. 50m Kurbağalamada patlayıcı güç üst seviyede.',
      pbs50m: [
        PersonalBest(
          distance: 50,
          stroke: 'Breaststroke',
          strokeLabel: 'Kurbağalama',
          time: '26.83',
          timeCs: 2683,
          points: 890,
          date: '2023-05-10',
          meetName: 'Türkiye Şampiyonası',
          course: 'LC',
        ),
      ],
      pbs25m: [
        PersonalBest(
          distance: 50,
          stroke: 'Breaststroke',
          strokeLabel: 'Kurbağalama',
          time: '24.95',
          timeCs: 2495,
          points: 980,
          date: '2021-12-27',
          meetName: 'Gaziantep Kısa Kulvar',
          course: 'SC',
        ),
      ],
    );
  }

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
      const BarajFeedResponse(rules: [], barajNames: [], ageLabels: []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('AthleteProfileScreen renders 2 tabs and displays athlete info correctly',
      (WidgetTester tester) async {
    final repo = MockSwimRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AthleteProfileScreen(
          athleteId: 1,
          athleteName: 'Emre Sakçı',
          repository: repo,
        ),
      ),
    );

    // Initial load shimmer/indicator
    await tester.pumpAndSettle();

    // Name and club should be rendered
    expect(find.text('Emre Sakçı'), findsOneWidget);
    expect(find.textContaining('Fenerbahçe'), findsOneWidget);

    // The two main swipeable tabs should be visible
    expect(find.text('Best Time'), findsOneWidget);
    expect(find.text('Barajlar'), findsOneWidget);

    // Bottom race history title 'Son Yarışlar' should NOT exist
    expect(find.text('Son Yarışlar'), findsNothing);

    // PB tab is selected by default; Kurbağalama stroke card and 50m tile should be visible
    expect(find.text('Kurbağalama'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('26.83'), findsOneWidget);

    // Switch to Scout Analizi tab
    await tester.tap(find.text('Scout Analizi'));
    await tester.pumpAndSettle();

    // Scout report note should now be visible
    expect(find.text('Scout Analiz Raporu'), findsOneWidget);
    expect(find.textContaining('Çıkış ve su altı reaksiyon süresi'), findsOneWidget);
    expect(find.text('%73.8'), findsOneWidget);
  });

  testWidgets(
      'AthleteProfileScreen does not overflow at 360x780 with textScale 1.3, very long athlete/club names, and empty best times',
      (WidgetTester tester) async {
    final repo = _LongEmptyMockRepository();

    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 780),
            textScaler: TextScaler.linear(1.3),
          ),
          child: AthleteProfileScreen(
            athleteId: 99,
            athleteName:
                'ABDURRAHMAN ŞAHİN İBRAHİMOĞLU KARAOSMANOĞLU',
            repository: repo,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Kayıtlı PB Bulunamadı'), findsOneWidget);
  });

  testWidgets(
      'AthleteProfileScreen wraps 5 events in one stroke at 360x780 with textScale 1.3 without overflow',
      (WidgetTester tester) async {
    final repo = _FiveEventsMockRepository();

    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 780),
            textScaler: TextScaler.linear(1.3),
          ),
          child: AthleteProfileScreen(
            athleteId: 77,
            athleteName: 'EGE CAN DEMİR',
            repository: repo,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Serbest'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
    expect(find.text('400'), findsOneWidget);
    expect(find.text('1500'), findsOneWidget);
  });
}

class _FiveEventsMockRepository implements SwimRepository {
  @override
  Future<AthleteDetail> getAthleteDetail(int id) async {
    return AthleteDetail(
      id: id,
      name: 'EGE CAN DEMİR',
      gender: 'M',
      clubName: 'GALATASARAY SPOR KULÜBÜ',
      birthYear: 2007,
      age: 19,
      stats: AthleteStats(
        totalRaces: 24,
        podiumCount: 10,
        podiumRate: 41.7,
        standardsPassed: 5,
      ),
      scoutNote: '',
      pbs50m: [
        PersonalBest(
          distance: 50,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          time: '24.10',
          timeCs: 2410,
          points: 364,
          date: '2025-04-12',
          meetName: 'Türkiye Şampiyonası',
          course: 'LC',
        ),
        PersonalBest(
          distance: 100,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          time: '52.85',
          timeCs: 5285,
          points: 612,
          date: '2025-04-13',
          meetName: 'Türkiye Şampiyonası',
          course: 'LC',
        ),
        PersonalBest(
          distance: 200,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          time: '01:55.40',
          timeCs: 11540,
          points: 640,
          date: '2025-04-14',
          meetName: 'Türkiye Şampiyonası',
          course: 'LC',
        ),
        PersonalBest(
          distance: 400,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          time: '04:08.12',
          timeCs: 24812,
          points: 625,
          date: '2025-04-15',
          meetName: 'Türkiye Şampiyonası',
          course: 'LC',
        ),
        PersonalBest(
          distance: 1500,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          time: '16:45.90',
          timeCs: 100590,
          points: 590,
          date: '2025-04-16',
          meetName: 'Türkiye Şampiyonası',
          course: 'LC',
        ),
      ],
      pbs25m: const [],
    );
  }

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
      const BarajFeedResponse(rules: [], barajNames: [], ageLabels: []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LongEmptyMockRepository implements SwimRepository {
  @override
  Future<AthleteDetail> getAthleteDetail(int id) async {
    return AthleteDetail(
      id: id,
      name: 'ABDURRAHMAN ŞAHİN İBRAHİMOĞLU KARAOSMANOĞLU',
      gender: 'M',
      clubName:
          'İSTANBUL BÜYÜKŞEHİR BELEDİYESİ SPOR KULÜBÜ YÜZME ŞUBESİ',
      birthYear: 2005,
      age: 21,
      stats: AthleteStats(
        totalRaces: 0,
        podiumCount: 0,
        podiumRate: 0,
        standardsPassed: 0,
      ),
      scoutNote: '',
      pbs50m: const [],
      pbs25m: const [],
    );
  }

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
      const BarajFeedResponse(rules: [], barajNames: [], ageLabels: []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
