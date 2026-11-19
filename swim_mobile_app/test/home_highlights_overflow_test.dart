import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swim_mobile_app/core/services/favorite_athletes_service.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/data/models/live_meet.dart';
import 'package:swim_mobile_app/data/models/meet.dart';
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
  Future<List<LiveMeetSummary>> getLiveMeets() async => [];

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
      expect(find.text('Favori & Kulüp Canlı Akışı'), findsOneWidget);
      expect(find.text('200m Karışık • Ankara'), findsOneWidget);
      expect(find.text('100m Serbest • İstanbul'), findsOneWidget);
      expect(
        find.text('A. Y***, B. K***, C. D***, E. T*** Baraj Geçti'),
        findsOneWidget,
      );
      expect(find.text('02:04.88'), findsOneWidget);
    },
  );
}
