import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/features/rankings/rankings_screen.dart';

class _FakeRankingsRepository implements SwimRepository {
  final List<Map<String, dynamic>> items;

  _FakeRankingsRepository(this.items);

  @override
  Future<List<Map<String, dynamic>>> getRankings({
    String stroke = 'free',
    int distance = 50,
    String gender = 'Erkek',
    String course = 'LC',
    int? birthYear,
    String? city,
  }) async {
    return items;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'RankingsScreen renders 25 rows with long names and keyboard inset at 360x780 and textScale 1.3 without overflow (light)',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final items = List.generate(25, (i) {
        return {
          'rank': i + 1,
          'athlete_id': i + 1,
          'athlete_name':
              'ABDURRAHMAN ŞAHİN İBRAHİMOĞLU SPORCU ${i + 1}',
          'birth_year': 2010 + (i % 4),
          'club_name':
              'İSTANBUL BÜYÜKŞEHİR BELEDİYESİ SPOR KULÜBÜ YÜZME ŞUBESİ',
          'city': 'ANKARA',
          'time': '23.${(10 + i).toString().padLeft(2, '0')}',
          'points': 850 - i * 10,
        };
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(const CoolSophisticatedLightPalette()),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
              viewInsets: EdgeInsets.only(bottom: 280),
            ),
            child: RankingsScreen(repository: _FakeRankingsRepository(items)),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Top 25 Sıralama'), findsOneWidget);
      expect(find.text('Getir'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('850 FINA'), findsOneWidget);
    },
  );

  testWidgets(
    'RankingsScreen renders empty state in dark theme at 360x780 and textScale 1.3 without overflow',
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
            child: RankingsScreen(repository: _FakeRankingsRepository(const [])),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Seçilen kriterlerde sonuç bulunamadı.'),
        findsOneWidget,
      );
    },
  );
}
