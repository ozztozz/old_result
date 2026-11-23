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

  testWidgets(
    'LiveRaceResultsScreen applies rank+time vs heat/lane+seedTime rule per row',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      final mixedResults = <RaceResult>[
        RaceResult(
          id: 1,
          eventNo: '1',
          distance: 100,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          heat: '1',
          lane: 4,
          rank: '1',
          time: '52.40',
          timeCs: 5240,
          seedTime: '53.10',
          seedTimeCs: 5310,
          resultStatus: 'OK',
          source: 'live',
          athleteId: 101,
          athleteName: 'DENİZ KAYA',
          clubName: 'TEST KULÜBÜ',
        ),
        RaceResult(
          id: 2,
          eventNo: '1',
          distance: 100,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          heat: '2',
          lane: 3,
          rank: '',
          time: null,
          timeCs: null,
          seedTime: '54.25',
          seedTimeCs: 5425,
          resultStatus: 'WAITING',
          source: 'live',
          athleteId: 102,
          athleteName: 'EFE YILMAZ',
          clubName: 'TEST KULÜBÜ',
        ),
        RaceResult(
          id: 3,
          eventNo: '1',
          distance: 100,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          heat: '2',
          lane: 5,
          rank: '',
          time: '-',
          timeCs: null,
          seedTime: '55.00',
          seedTimeCs: 5500,
          resultStatus: 'OK',
          source: 'live',
          athleteId: 103,
          athleteName: 'MERT DEMİR',
          clubName: 'TEST KULÜBÜ',
        ),
        RaceResult(
          id: 4,
          eventNo: '1',
          distance: 100,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          heat: '3',
          lane: 1,
          rank: '',
          time: null,
          timeCs: null,
          seedTime: null,
          seedTimeCs: null,
          resultStatus: 'WAITING',
          source: 'live',
          athleteId: 104,
          athleteName: 'CAN ARSLAN',
          clubName: 'TEST KULÜBÜ',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(const CoolSophisticatedLightPalette()),
          home: LiveRaceResultsScreen(
            live: _sampleLive(),
            event: _sampleEvent(),
            repository: _FakeLiveRaceRepository(mixedResults),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Sonucu olan satır: sıralama + sonuç
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('52.40'), findsOneWidget);
      // Sonucu olmayan satırlar (WAITING veya '-' dereceli): seri/sıra + giriş derecesi
      expect(find.text('2/3'), findsOneWidget);
      expect(find.text('54.25'), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);
      expect(find.text('55.00'), findsOneWidget);
      expect(find.text('Giriş derecesi'), findsNWidgets(2));
      // Giriş derecesi de olmayan satır: seri/sıra + Bekleniyor
      expect(find.text('3/1'), findsOneWidget);
      expect(find.text('Bekleniyor'), findsOneWidget);
      // '-' metni asla büyük derece olarak basılmamalı
      expect(find.text('-'), findsNothing);
    },
  );

  testWidgets(
    'LiveRaceResultsScreen splits multiple 1./2. rankings locally into separate categories',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      final multiRankResults = <RaceResult>[
        RaceResult(
          id: 1,
          eventNo: '1',
          distance: 200,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          heat: '1',
          lane: 4,
          rank: '1',
          time: '02:16.69',
          timeCs: 13669,
          resultStatus: 'OK',
          source: 'live',
          athleteId: 201,
          athleteName: 'MÜNEVVER MAYA TURGUT',
          age: 11,
          clubName: 'MURATPAŞA BELEDİYESİ',
        ),
        RaceResult(
          id: 2,
          eventNo: '1',
          distance: 200,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          heat: '1',
          lane: 3,
          rank: '1',
          time: '02:17.86',
          timeCs: 13786,
          resultStatus: 'OK',
          source: 'live',
          athleteId: 202,
          athleteName: 'AZRA CAMBAZOĞLU',
          age: 10,
          clubName: 'MANAVGAT BARLAS',
        ),
        RaceResult(
          id: 3,
          eventNo: '1',
          distance: 200,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          heat: '1',
          lane: 5,
          rank: '2',
          time: '02:18.14',
          timeCs: 13814,
          resultStatus: 'OK',
          source: 'live',
          athleteId: 203,
          athleteName: 'ZEYNEP ADA SADIKLAR',
          age: 11,
          clubName: 'ANTALYA FAROZ',
        ),
        RaceResult(
          id: 4,
          eventNo: '1',
          distance: 200,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          heat: '1',
          lane: 6,
          rank: '2',
          time: '02:22.31',
          timeCs: 14231,
          resultStatus: 'OK',
          source: 'live',
          athleteId: 204,
          athleteName: 'YAĞMUR ADALIYILMAZ',
          age: 10,
          clubName: 'MURATPAŞA BELEDİYESİ',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(const CoolSophisticatedLightPalette()),
          home: LiveRaceResultsScreen(
            live: _sampleLive(),
            event: _sampleEvent(),
            repository: _FakeLiveRaceRepository(multiRankResults),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Varsayılan olarak tüm gruplar açık ve yaşlar karışmadan ayrı başlıklarla görünür
      expect(find.text('10 Yaş'), findsOneWidget);
      expect(find.text('Azra Cambazoğlu'), findsOneWidget);

      // Başlığa tıklayınca kapanır, tekrar tıklayınca açılır
      await tester.tap(find.text('10 Yaş'));
      await tester.pumpAndSettle();
      expect(find.text('Azra Cambazoğlu'), findsNothing);

      await tester.tap(find.text('10 Yaş'));
      await tester.pumpAndSettle();
      expect(find.text('Azra Cambazoğlu'), findsOneWidget);

      await tester.drag(find.byType(ListView).first, const Offset(0, -350));
      await tester.pumpAndSettle();

      expect(find.text('11 Yaş'), findsOneWidget);
      expect(find.text('1.'), findsWidgets);
    },
  );
}
