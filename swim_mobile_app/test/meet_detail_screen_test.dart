import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/data/models/meet.dart';
import 'package:swim_mobile_app/data/models/race_result.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/features/meets/meet_detail_screen.dart';
import 'package:swim_mobile_app/shared/widgets/modern_filter_chips.dart';

class _FakeMeetDetailRepository implements SwimRepository {
  final int totalRaces;
  final int totalAthletes;

  _FakeMeetDetailRepository({
    this.totalRaces = 24,
    this.totalAthletes = 1355,
  });

  @override
  Future<MeetDetail> getMeetDetail(int id) async {
    return MeetDetail(
      id: id,
      name:
          'TÜRKİYE YÜZME FEDERASYONU UZUN KULVAR MİLLİ TAKIM SEÇME VE BARAJ GEÇME MÜSABAKALARI',
      city: 'Ankara',
      startDate: '2026-04-10',
      endDate: '2026-04-13',
      course: 'LC',
      totalRaces: totalRaces,
      totalAthletes: totalAthletes,
      events: [
        MeetEvent(
          eventNo: '1',
          distance: 100,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          gender: 'Erkekler',
        ),
        MeetEvent(
          eventNo: '2',
          distance: 200,
          stroke: 'Medley',
          strokeLabel: 'Karışık',
          gender: 'Kadınlar',
        ),
      ],
    );
  }

  @override
  Future<MeetParticipants> getMeetParticipants(int id) async {
    return MeetParticipants(
      meetId: id,
      clubs: [
        ParticipantClub(
          id: 1,
          name: 'İSTANBUL BÜYÜKŞEHİR BELEDİYESİ SPOR KULÜBÜ YÜZME ŞUBESİ',
        ),
      ],
      athletes: [
        ParticipantAthlete(
          id: 1,
          name: 'ABDURRAHMAN ŞAHİN İBRAHİMOĞLU KARAOSMANOĞLU',
          birthYear: 2006,
          clubId: 1,
        ),
      ],
    );
  }

  @override
  Future<List<RaceResult>> getMeetResults(
    int meetId, {
    String? eventNo,
    int? clubId,
    int? athleteId,
    String? status,
    int page = 1,
    bool summary = false,
  }) async {
    if (status == 'pending') return [];

    return [
      for (int i = 0; i < 8; i++)
        RaceResult(
          id: i + 1,
          eventNo: '1',
          distance: 100,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          heat: '1',
          lane: i + 1,
          rank: '${i + 1}',
          time: '52.${10 + i}',
          timeCs: 5210 + i * 15,
          seedTime: i == 0 ? '53.45' : (i == 1 ? '51.00' : null),
          seedTimeCs: i == 0 ? 5345 : (i == 1 ? 5100 : null),
          qualifyingStandard: i == 0
              ? QualifyingStandard(
                  passed: true,
                  badge: 'TÜRKİYE MİLLİ TAKIM A BARAJI GEÇİLDİ',
                )
              : null,
          resultStatus: 'OK',
          source: 'official',
          athleteId: i + 1,
          athleteName:
              'ABDURRAHMAN ŞAHİN İBRAHİMOĞLU SPORCU ${i + 1}',
          clubId: 1,
          clubName:
              'İSTANBUL BÜYÜKŞEHİR BELEDİYESİ SPOR KULÜBÜ YÜZME ŞUBESİ',
        ),
      RaceResult(
        id: 9,
        eventNo: '1',
        distance: 100,
        stroke: 'Freestyle',
        strokeLabel: 'Serbest',
        heat: '2',
        lane: 1,
        rank: '-',
        time: 'DNS',
        timeCs: null,
        resultStatus: 'DNS',
        source: 'official',
        athleteId: 9,
        athleteName: 'MEHMET ALİ DEMİR',
        clubName: 'FENERBAHÇE SPOR KULÜBÜ',
      ),
      RaceResult(
        id: 10,
        eventNo: '1',
        distance: 100,
        stroke: 'Freestyle',
        strokeLabel: 'Serbest',
        heat: '2',
        lane: 2,
        rank: 'DSQ',
        time: 'DSQ',
        timeCs: null,
        resultStatus: 'DSQ',
        source: 'official',
        athleteId: 10,
        athleteName: 'ZEYNEP GÜLŞAH ÇETİNKAYA',
        clubName: 'GALATASARAY SPOR KULÜBÜ',
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'MeetDetailScreen renders long meet/athlete/club names, 10 rows, active filters, and empty result at 360x780 and textScale 1.3 without overflow',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

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
            child: MeetDetailScreen(
              meetId: 1,
              meetTitle: 'TÜRKİYE ŞAMPİYONASI',
              repository: _FakeMeetDetailRepository(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Ankara • 24 yarış'), findsOneWidget);
      expect(find.text('1.355'), findsOneWidget);
      expect(find.text('100m Serbest'), findsOneWidget);

      // Scroll status chip bar to bring 'Bekleyen' fully into view and tap it -> triggers empty result state
      await tester.drag(
        find.byType(ModernFilterChipBar).last,
        const Offset(-200, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bekleyen'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sonuç bulunamadı'), findsOneWidget);
    },
  );

  testWidgets(
    'MeetDetailScreen renders in dark theme at 360x780 and textScale 1.3 without overflow',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(const CoolSophisticatedDarkPalette()),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
            ),
            child: MeetDetailScreen(
              meetId: 1,
              meetTitle: 'TÜRKİYE ŞAMPİYONASI',
              repository: _FakeMeetDetailRepository(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Başlamadı'), findsOneWidget);
      expect(find.text('Diskalifiye'), findsOneWidget);
      expect(
        find.text('Türkiye Milli Takım A Barajı Geçildi'),
        findsOneWidget,
      );
      expect(find.text('53.45'), findsOneWidget);
      expect(find.text('51.00'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down_outlined), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_up_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'MeetDetailScreen falls back to events and participants/results when MeetDetail totalRaces/totalAthletes are 0',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

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
            child: MeetDetailScreen(
              meetId: 2,
              meetTitle: 'TÜRKİYE ŞAMPİYONASI',
              repository: _FakeMeetDetailRepository(
                totalRaces: 0,
                totalAthletes: 0,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // 2 events in mock, 1 participant in mock -> hero shows 1 and 2 instead of 0
      expect(find.text('Ankara • 2 yarış'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    },
  );
}
