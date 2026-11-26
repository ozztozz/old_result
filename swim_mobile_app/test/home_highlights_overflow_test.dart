import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swim_mobile_app/core/services/favorite_athletes_service.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/data/models/live_meet.dart';
import 'package:swim_mobile_app/data/models/meet.dart';
import 'package:swim_mobile_app/data/models/tyf_news.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/features/home/home_screen.dart';

class _FakeHomeRepository implements SwimRepository {
  @override
  Future<List<MeetSummary>> getMeets({
    int page = 1,
    String? year,
    String? city,
    String? q,
  }) async =>
      [];

  @override
  Future<List<TyfNewsItem>> getNewsFeed({String? type, int limit = 15}) async =>
      const [];

  @override
  Future<List<LiveMeetSummary>> getLiveMeets() async => [
        LiveMeetSummary(
          id: 1,
          name:
              'TÜRKİYE YÜZME FEDERASYONU UZUN KULVAR MİLLİ TAKIM SEÇME MÜSABAKALARI',
          city: 'ANKARA',
          date: '2026-04-12',
          status: 'CANLI',
          totalAthletes: 640,
          startListProgress: LiveProgress(processed: 10, total: 10),
          resultListProgress: LiveProgress(processed: 5, total: 10),
        ),
        LiveMeetSummary(
          id: 2,
          name: 'UZUN KULVAR TÜRKİYE ŞAMPİYONASI VE SEÇME YARIŞLARI',
          city: 'İSTANBUL',
          date: '2026-04-14',
          status: 'CANLI',
          totalAthletes: 420,
          startListProgress: LiveProgress(processed: 8, total: 8),
          resultListProgress: LiveProgress(processed: 4, total: 8),
        ),
      ];

  @override
  Future<List<Map<String, dynamic>>> getHighlightsFeed({
    List<int> athleteIds = const [],
    int? clubId,
    String? clubName,
  }) async {
    return [
      {
        'athlete_id': 1,
        'athlete_name':
            'İSTANBUL BÜYÜKŞEHİR BELEDİYESİ SPOR KULÜBÜ YÜZME ŞUBESİ',
        'distance': 200,
        'stroke_label': 'Karışık',
        'city': 'ANKARA',
        'meet_name':
            'TÜRKİYE YÜZME FEDERASYONU UZUN KULVAR MİLLİ TAKIM SEÇME MÜSABAKALARI',
        'time': '02:04.88',
        'qualifying_standard': {
          'passed': true,
          'badge': 'A. Y***, B. K***, C. D***, E. T*** Baraj Geçti',
        },
      },
      {
        'athlete_id': 2,
        'athlete_name': 'FENERBAHÇE SPOR KULÜBÜ YÜZME TAKIMI SPORCUSU',
        'distance': 100,
        'stroke_label': 'Serbest',
        'city': 'İSTANBUL',
        'meet_name': 'UZUN KULVAR TÜRKİYE ŞAMPİYONASI',
        'time': '49.12',
        'qualifying_standard': {
          'passed': true,
          'badge': 'A Barajı',
        },
      },
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'HomeScreen highlights section does not overflow with long club names, 3+ masked athlete names, and textScale 1.3',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await FavoriteAthletesService.instance.toggleFavorite(1);

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
            child: HomeScreen(repository: _FakeHomeRepository()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('CANLI AKIŞ'), findsOneWidget);
      expect(find.text('2 yarış'), findsOneWidget);
      expect(find.text('2026-04-12 · Ankara'), findsOneWidget);
      expect(find.text('2026-04-14 · İstanbul'), findsOneWidget);
    },
  );
}
