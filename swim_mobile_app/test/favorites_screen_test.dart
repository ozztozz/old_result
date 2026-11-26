import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swim_mobile_app/core/services/favorite_athletes_service.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/data/models/athlete.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/features/favorites/favorites_screen.dart';

class _FakeFavoritesRepository implements SwimRepository {
  final List<AthleteSummaryItem> items;

  _FakeFavoritesRepository(this.items);

  @override
  Future<List<AthleteSummaryItem>> getAthletesSummary(List<int> ids) async {
    return items.where((item) => ids.contains(item.id)).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'FavoritesScreen empty state renders without overflow at 360x780 and textScale 1.3',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      for (final id in List<int>.from(FavoriteAthletesService.instance.favoriteIds)) {
        await FavoriteAthletesService.instance.removeFavorite(id);
      }

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
            child: FavoritesScreen(
              repository: _FakeFavoritesRepository(const []),
              onGoToDiscover: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Henüz favori sporcu eklemediniz'), findsOneWidget);
      expect(find.text("Keşfet'e Git"), findsOneWidget);
    },
  );

  testWidgets(
    'FavoritesScreen populated list with long athlete and club names does not overflow at 360x780 and textScale 1.3 (dark & light)',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await FavoriteAthletesService.instance.toggleFavorite(101);
      await FavoriteAthletesService.instance.toggleFavorite(102);

      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeFavoritesRepository([
        AthleteSummaryItem(
          id: 101,
          name: 'ABDURRAHMAN ŞAHİN İBRAHİMOĞLU',
          birthYear: 2006,
          clubName:
              'İSTANBUL BÜYÜKŞEHİR BELEDİYESİ SPOR KULÜBÜ YÜZME ŞUBESİ',
          latestRace: AthleteRaceBrief(
            distance: 200,
            stroke: 'KARIŞIK',
            time: '02:04.88',
            points: 812,
          ),
          topPerformance: AthleteRaceBrief(
            distance: 100,
            stroke: 'SERBEST',
            time: '49.12',
            points: 865,
          ),
        ),
        AthleteSummaryItem(
          id: 102,
          name: 'ZEYNEP GÜLŞAH ÇETİNKAYA',
          birthYear: 2008,
          clubName: 'FENERBAHÇE SPOR KULÜBÜ YÜZME TAKIMI',
          latestRace: AthleteRaceBrief(
            distance: 50,
            stroke: 'KELEBEK',
            time: 'DNS',
            points: null,
          ),
          topPerformance: AthleteRaceBrief(
            distance: 100,
            stroke: 'KELEBEK',
            time: '1:08.50',
            points: 408,
          ),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(const CoolSophisticatedDarkPalette()),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
            ),
            child: FavoritesScreen(repository: repo),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('TAKİP ÖZETİ'), findsOneWidget);
      expect(find.text('Abdurrahman Şahin İbrahimoğlu'), findsOneWidget);
      expect(find.text('Zeynep Gülşah Çetinkaya'), findsOneWidget);
      expect(find.text('865 pt'), findsOneWidget);
      expect(find.text('408 pt'), findsOneWidget);
      expect(find.text('DNS'), findsOneWidget);
    },
  );
}
