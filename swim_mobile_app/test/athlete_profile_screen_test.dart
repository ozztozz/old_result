import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/features/athletes/athlete_profile_screen.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/data/models/athlete.dart';

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Name and club should be rendered
    expect(find.text('Emre Sakçı'), findsOneWidget);
    expect(find.text('Fenerbahçe SK'), findsOneWidget);

    // The two main swipeable tabs should be visible
    expect(find.text('Best Time'), findsOneWidget);
    expect(find.text('Scout Analizi'), findsOneWidget);

    // Bottom race history title 'Son Yarışlar' should NOT exist
    expect(find.text('Son Yarışlar'), findsNothing);

    // PB tab is selected by default; Kurbağalama stroke card and 50m tile should be visible
    expect(find.text('Kurbağalama'), findsOneWidget);
    expect(find.text('50m'), findsOneWidget);
    expect(find.text('26.83'), findsOneWidget);
    expect(find.text('890 FINA'), findsOneWidget);

    // Switch to Scout Analizi tab
    await tester.tap(find.text('Scout Analizi'));
    await tester.pumpAndSettle();

    // Scout report note should now be visible
    expect(find.text('Scout Analiz Raporu'), findsOneWidget);
    expect(find.textContaining('Çıkış ve su altı reaksiyon süresi'), findsOneWidget);
    expect(find.text('%73.8'), findsOneWidget);
    expect(find.text('980 FINA'), findsOneWidget);
  });
}
