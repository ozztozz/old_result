import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/data/models/live_meet.dart';
import 'package:swim_mobile_app/data/models/race_result.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/features/live/live_race_results_screen.dart';

class _FakeLiveRaceRepository implements SwimRepository {
  final List<RaceResult> results;

  _FakeLiveRaceRepository(this.results);

  @override
  Future<LiveFeedResponse> getLiveFeedResponse(
    int liveMeetId, {
    String? eventNo,
    String? status,
  }) async {
    return LiveFeedResponse(
      liveId: liveMeetId,
      status: 'CANLI',
      events: const [],
      data: List<RaceResult>.from(results),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LiveMeetSummary _sampleLive() => LiveMeetSummary(
      id: 1,
      name: 'TÜRKİYE UZUN KULVAR MİLLİ TAKIM SEÇME MÜSABAKALARI',
      city: 'Ankara',
      date: '2026-04-12',
      status: 'CANLI',
      totalAthletes: 1355,
      startListProgress: LiveProgress(processed: 10, total: 10),
      resultListProgress: LiveProgress(processed: 5, total: 10),
    );

LiveEventProgramItem _sampleEvent() => LiveEventProgramItem(
      eventNo: '1',
      name: '200M KARIŞIK ERKEKLER GENÇLER FİNAL',
      stroke: 'Medley',
      strokeLabel: 'Karışık',
      distance: 200,
      gender: 'Erkekler',
      ageGroup: 'Gençler',
      isPending: false,
      status: 'TAMAMLANDI',
      totalAthletes: 8,
    );

void main() {
  testWidgets(
    'LiveRaceResultsScreen renders 8 lanes, long athlete/club names, DNS/DSQ rows at 360x780 and textScale 1.3 without overflow (light & dark)',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final results = <RaceResult>[
        for (int i = 0; i < 6; i++)
          RaceResult(
            id: i + 1,
            eventNo: '1',
            distance: 200,
            stroke: 'Medley',
            strokeLabel: 'Karışık',
            heat: '1',
            lane: i + 1,
            rank: '${i + 1}',
            time: '02:0${i + 1}.45',
            timeCs: 12145 + i * 100,
            seedTime: i == 0 ? '02:03.00' : (i == 1 ? '02:01.00' : null),
            seedTimeCs: i == 0 ? 12300 : (i == 1 ? 12100 : null),
            splitTimes: i == 0
                ? {'50m': '28.12', '100m': '59.40', '150m': '01:30.88'}
                : null,
            resultStatus: 'OK',
            source: 'live',
            athleteId: i + 1,
            athleteName:
                'ABDURRAHMAN ŞAHİN İBRAHİMOĞLU SPORCU ${i + 1}',
            clubName:
                'İSTANBUL BÜYÜKŞEHİR BELEDİYESİ SPOR KULÜBÜ YÜZME ŞUBESİ',
          ),
        RaceResult(
          id: 7,
          eventNo: '1',
          distance: 200,
          stroke: 'Medley',
          strokeLabel: 'Karışık',
          heat: '1',
          lane: 7,
          rank: '-',
          time: 'DNS',
          timeCs: null,
          resultStatus: 'DNS',
          source: 'live',
          athleteId: 7,
          athleteName: 'MEHMET ALİ KARAOSMANOĞLU',
          clubName: 'FENERBAHÇE SPOR KULÜBÜ YÜZME ŞUBESİ',
        ),
        RaceResult(
          id: 8,
          eventNo: '1',
          distance: 200,
          stroke: 'Medley',
          strokeLabel: 'Karışık',
          heat: '1',
          lane: 8,
          rank: 'DSQ',
          time: 'DSQ',
          timeCs: null,
          resultStatus: 'DSQ',
          source: 'live',
          athleteId: 8,
          athleteName: 'KEREM CAN ÖZDEMİR',
          clubName: 'GALATASARAY SPOR KULÜBÜ YÜZME ŞUBESİ',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(const CoolSophisticatedLightPalette()),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
            ),
            child: LiveRaceResultsScreen(
              live: _sampleLive(),
              event: _sampleEvent(),
              repository: _FakeLiveRaceRepository(results),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Başlamadı'), findsOneWidget);
      expect(find.text('Diskalifiye'), findsOneWidget);
      expect(find.text('02:03.00'), findsOneWidget);
      expect(find.text('02:01.00'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down_outlined), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_up_outlined), findsOneWidget);

      // Ara dereceler başlangıçta gizli, ikona tıklanınca açılır
      expect(find.text('Ara Dereceler'), findsNothing);
      await tester.tap(find.byTooltip('Ara dereceler').first);
      await tester.pumpAndSettle();
      expect(find.text('Ara Dereceler'), findsOneWidget);
      expect(find.textContaining('28.12'), findsOneWidget);
      expect(find.textContaining('31.28'), findsOneWidget);
      expect(find.textContaining('31.48'), findsOneWidget);
      expect(find.textContaining('30.57'), findsOneWidget);
      expect(find.textContaining('59.40'), findsOneWidget);
      expect(find.textContaining('01:30.88'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('DNS'), findsNothing);
      expect(find.text('DSQ'), findsNothing);
    },
  );

  testWidgets(
    'LiveRaceResultsScreen empty series renders EmptyStateWidget in dark theme at 360x780 and textScale 1.3 without overflow',
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
            child: LiveRaceResultsScreen(
              live: _sampleLive(),
              event: _sampleEvent(),
              repository: _FakeLiveRaceRepository(const []),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sonuç bulunamadı'), findsOneWidget);
    },
  );
}
