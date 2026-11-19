import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swim_mobile_app/core/components/app_dialog.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/data/models/athlete.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/features/athletes/widgets/pb_history_sheet.dart';
import 'package:swim_mobile_app/shared/widgets/club_selection_sheet.dart';
import 'package:swim_mobile_app/shared/widgets/theme_picker_sheet.dart';

void main() {
  testWidgets(
    'ClubSelectionSheet handles long club names and empty search at 360x780 and textScale 1.3 without overflow',
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
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      ClubSelectionSheet.show(
                        context,
                        availableClubs: const [
                          'İSTANBUL BÜYÜKŞEHİR BELEDİYESİ SPOR KULÜBÜ YÜZME ŞUBESİ',
                          'FENERBAHÇE SPOR KULÜBÜ ANADOLU YAKASI YÜZME AKADEMİSİ',
                          'ENKA SPOR KULÜBÜ',
                        ],
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Takımını Seç'), findsOneWidget);
      expect(
        find.text('İstanbul Büyükşehir Belediyesi Spor Kulübü Yüzme Şubesi'),
        findsOneWidget,
      );

      // Search for a non-existent club -> empty search state
      await tester.enterText(find.byType(TextField), 'XYZ_YOK');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Aramanızla eşleşen kulüp bulunamadı.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ThemePickerSheet and AppDialog render in dark theme at 360x780 and textScale 1.3 without overflow',
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
            child: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => ThemePickerSheet.show(context),
                      child: const Text('Themes'),
                    ),
                    ElevatedButton(
                      onPressed: () => AppDialog.show(
                        context,
                        title: 'Bilgi',
                        body: 'Test diyalog içeriği.',
                        cancelLabel: 'Vazgeç',
                      ),
                      child: const Text('Dialog'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Themes'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Görünüm ve Tema'), findsOneWidget);

      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dialog'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Bilgi'), findsOneWidget);
      expect(find.text('Vazgeç'), findsOneWidget);
    },
  );

  testWidgets(
    'PbHistorySheet renders chart, 10+ entries, long meet name, and mapped Turkish statuses at 360x780 and textScale 1.3 without overflow',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakePbHistoryRepository();
      final pb = PersonalBest(
        distance: 100,
        stroke: 'Freestyle',
        strokeLabel: 'Serbest',
        time: '52.85',
        timeCs: 5285,
        points: 612,
        date: '2026-04-12',
        meetName: 'Türkiye Şampiyonası',
        course: 'LC',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(const CoolSophisticatedLightPalette()),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
            ),
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      PbHistorySheet.show(
                        context,
                        athleteId: 1,
                        pb: pb,
                        strokeLabel: 'Serbest',
                        repository: repo,
                      );
                    },
                    child: const Text('History'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('100m Serbest'), findsOneWidget);
      expect(find.text('Tüm Yarışlar (11)'), findsOneWidget);
      expect(find.text('Başlamadı'), findsOneWidget);
      expect(find.text('Bekleniyor'), findsOneWidget);
      expect(find.text('Diskalifiye'), findsOneWidget);
      expect(find.text('Tamamlamadı'), findsOneWidget);
      expect(find.text('DNS'), findsNothing);
      expect(find.text('WAITING'), findsNothing);
      expect(find.text('DSQ'), findsNothing);
      expect(find.text('DNF'), findsNothing);
    },
  );
}

class _FakePbHistoryRepository implements SwimRepository {
  @override
  Future<List<AthleteRaceHistoryItem>> getAthleteRaces(
    int athleteId, {
    int page = 1,
    String? year,
    String? stroke,
    int? distance,
  }) async {
    const longMeet =
        'TÜRKİYE YÜZME FEDERASYONU UZUN KULVAR MİLLİ TAKIM SEÇME VE BARAJ GEÇME MÜSABAKALARI';
    return [
      for (int i = 0; i < 7; i++)
        AthleteRaceHistoryItem(
          id: i + 1,
          meetId: 100 + i,
          meetName: longMeet,
          date: '2026-0${(i % 9) + 1}-15',
          course: 'LC',
          eventNo: '${i + 1}',
          distance: 100,
          stroke: 'Freestyle',
          strokeLabel: 'Serbest',
          heat: '1',
          lane: 4,
          rank: '${i + 1}',
          time: '53.${10 + i}',
          timeCs: 5285 + i * 25,
          resultStatus: 'OK',
          points: 600 - i * 10,
          clubName: 'Fenerbahçe SK',
        ),
      AthleteRaceHistoryItem(
        id: 8,
        meetId: 108,
        meetName: longMeet,
        date: '2026-08-01',
        course: 'LC',
        eventNo: '8',
        distance: 100,
        stroke: 'Freestyle',
        strokeLabel: 'Serbest',
        heat: '1',
        lane: 2,
        rank: '-',
        time: 'DNS',
        timeCs: null,
        resultStatus: 'DNS',
        points: null,
        clubName: 'Fenerbahçe SK',
      ),
      AthleteRaceHistoryItem(
        id: 9,
        meetId: 109,
        meetName: longMeet,
        date: '2026-08-02',
        course: 'LC',
        eventNo: '9',
        distance: 100,
        stroke: 'Freestyle',
        strokeLabel: 'Serbest',
        heat: '1',
        lane: 3,
        rank: '-',
        time: 'WAITING',
        timeCs: null,
        resultStatus: 'WAITING',
        points: null,
        clubName: 'Fenerbahçe SK',
      ),
      AthleteRaceHistoryItem(
        id: 10,
        meetId: 110,
        meetName: longMeet,
        date: '2026-08-03',
        course: 'LC',
        eventNo: '10',
        distance: 100,
        stroke: 'Freestyle',
        strokeLabel: 'Serbest',
        heat: '1',
        lane: 5,
        rank: '-',
        time: 'DSQ',
        timeCs: null,
        resultStatus: 'DSQ',
        points: null,
        clubName: 'Fenerbahçe SK',
      ),
      AthleteRaceHistoryItem(
        id: 11,
        meetId: 111,
        meetName: longMeet,
        date: '2026-08-04',
        course: 'LC',
        eventNo: '11',
        distance: 100,
        stroke: 'Freestyle',
        strokeLabel: 'Serbest',
        heat: '1',
        lane: 6,
        rank: '-',
        time: 'DNF',
        timeCs: null,
        resultStatus: 'DNF',
        points: null,
        clubName: 'Fenerbahçe SK',
      ),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getAthleteBarajTargets(
    int athleteId, {
    required String stroke,
    required int distance,
    required String course,
    int? pbCs,
  }) async {
    return [
      {
        'passed': true,
        'diff_cs': -15,
        'target_cs': 5300,
        'meet_name': 'TÜRKİYE MİLLİ TAKIM A BARAJI',
      },
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
