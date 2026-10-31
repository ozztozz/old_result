import 'package:flutter_test/flutter_test.dart';
import 'package:swim_mobile_app/shared/widgets/swim_result_card.dart';
import 'package:swim_mobile_app/data/models/race_result.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('SwimResultCard displays rank for completed race', (WidgetTester tester) async {
    final result = RaceResult(
      id: 1,
      eventNo: '1',
      stroke: 'Freestyle',
      strokeLabel: 'Serbest',
      heat: '3',
      lane: 4,
      rank: '1',
      time: '28.45',
      timeCs: 2845,
      seedTime: '29.10',
      seedTimeCs: 2910,
      resultStatus: 'OK',
      source: 'live',
      athleteId: 101,
      athleteName: 'Ahmet Yılmaz',
      clubName: 'Fenerbahçe SK',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SwimResultCard(result: result, rankIndex: 1),
        ),
      ),
    );

    // Rank 1. should be shown on the left
    expect(find.text('1.'), findsOneWidget);
    // Finish time 28.45 should be shown
    expect(find.text('28.45'), findsOneWidget);
    // Seed time 29.10 should be shown
    expect(find.text('29.10'), findsOneWidget);
    // Up arrow for improvement should be shown
    expect(find.byIcon(Icons.arrow_drop_up_rounded), findsOneWidget);
  });

  testWidgets('SwimResultCard displays S3/7 for pending race', (WidgetTester tester) async {
    final result = RaceResult(
      id: 2,
      eventNo: '1',
      stroke: 'Freestyle',
      strokeLabel: 'Serbest',
      heat: '3',
      lane: 7,
      rank: '',
      time: null,
      timeCs: null,
      seedTime: '30.50',
      seedTimeCs: 3050,
      resultStatus: 'WAITING',
      source: 'live',
      athleteId: 102,
      athleteName: 'Mehmet Demir',
      clubName: 'Galatasaray SK',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SwimResultCard(result: result),
        ),
      ),
    );

    // Heat/Lane abbreviation S3/7 should be shown
    expect(find.text('S3/7'), findsOneWidget);
    // Seed time 30.50 should be shown
    expect(find.text('30.50'), findsOneWidget);
    // No up arrow because race is pending
    expect(find.byIcon(Icons.arrow_drop_up_rounded), findsNothing);
  });
}
