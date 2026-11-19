import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swim_mobile_app/core/services/selected_club_service.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/features/clubs/relay_simulator_screen.dart';

class _FakeRelayRepository implements SwimRepository {
  final Map<String, dynamic> simData;

  _FakeRelayRepository(this.simData);

  @override
  Future<Map<String, dynamic>> getRelaySimulator({
    int? clubId,
    String? clubName,
    String relayType = '4x50_free',
    String gender = 'Erkek',
    String course = 'LC',
    int? birthYear,
  }) async {
    return simData;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'RelaySimulatorScreen renders no-club-selected empty state at 360x780 and textScale 1.3 with keyboard inset without overflow',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await SelectedClubService.instance.clearClub();

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
              viewInsets: EdgeInsets.only(bottom: 280),
            ),
            child: RelaySimulatorScreen(
              repository: _FakeRelayRepository(const {}),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Bayrak Simülatörü'), findsOneWidget);
      expect(find.text('Kulüp seçilmedi'), findsOneWidget);
      expect(find.text('Kulüp Seç'), findsOneWidget);
    },
  );

  testWidgets(
    'RelaySimulatorScreen renders long club/athlete names and 4-leg squad at 360x780 and textScale 1.3 without overflow (light & dark)',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await SelectedClubService.instance.setClub(
        id: 1,
        name: 'İSTANBUL BÜYÜKŞEHİR BELEDİYESİ SPOR KULÜBÜ YÜZME ŞUBESİ',
      );

      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeRelayRepository({
        'complete': true,
        'total_time': '01:32.45',
        'legs': [
          {
            'leg': 1,
            'athlete_id': 1,
            'athlete_name': 'STERGIOS MARIOS BILAS',
            'distance': 50,
            'stroke_label': 'Serbest',
            'birth_year': 2001,
            'time': '22.15',
          },
          {
            'leg': 2,
            'athlete_id': 2,
            'athlete_name': 'ABDURRAHMAN ŞAHİN İBRAHİMOĞLU KARAOSMANOĞLU',
            'distance': 50,
            'stroke_label': 'Serbest',
            'birth_year': 2005,
            'time': '23.10',
          },
          {
            'leg': 3,
            'athlete_id': 3,
            'athlete_name': 'SARP SÜNBÜL',
            'distance': 50,
            'stroke_label': 'Serbest',
            'birth_year': 2006,
            'time': '23.40',
          },
          {
            'leg': 4,
            'athlete_id': 4,
            'athlete_name': 'GÜLCE AYDEMİR',
            'distance': 50,
            'stroke_label': 'Serbest',
            'birth_year': 2007,
            'time': '23.80',
          },
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(const CoolSophisticatedDarkPalette()),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
            ),
            child: RelaySimulatorScreen(repository: repo),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Tahmini En Hızlı Bayrak'), findsOneWidget);
      expect(find.text('01:32.45'), findsOneWidget);
      expect(find.text('Stergios Marios Bilas'), findsOneWidget);
      expect(find.text('Sarp Sünbül'), findsOneWidget);
    },
  );

  testWidgets(
    'RelaySimulatorScreen renders empty squad state without overflow',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await SelectedClubService.instance.setClub(
        id: 1,
        name: 'ENKA SPOR KULÜBÜ',
      );

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
            child: RelaySimulatorScreen(
              repository: _FakeRelayRepository({
                'complete': false,
                'total_time': null,
                'legs': const [],
              }),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Yeterli sporcu bulunamadı'), findsOneWidget);
    },
  );
}
