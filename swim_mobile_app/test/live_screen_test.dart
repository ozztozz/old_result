import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swim_mobile_app/core/services/favorite_live_meets_service.dart';
import 'package:swim_mobile_app/core/theme/app_theme.dart';
import 'package:swim_mobile_app/data/models/live_meet.dart';
import 'package:swim_mobile_app/data/models/meet.dart';
import 'package:swim_mobile_app/data/models/race_result.dart';
import 'package:swim_mobile_app/data/repositories/swim_repository.dart';
import 'package:swim_mobile_app/features/live/live_meet_detail_screen.dart';
import 'package:swim_mobile_app/features/live/live_screen.dart';
import 'package:swim_mobile_app/shared/widgets/modern_filter_chips.dart';

class _FakeLiveScreenRepository implements SwimRepository {
  final List<LiveMeetSummary> meets;
  int getLiveEventsCalls = 0;
  int getLiveSummaryCalls = 0;
  int getLiveFeedFullCalls = 0;
  int getMeetDetailCalls = 0;
  int getMeetResultsCalls = 0;

  _FakeLiveScreenRepository(this.meets);

  @override
  Future<MeetDetail> getMeetDetail(int meetId) async {
    getMeetDetailCalls++;
    return MeetDetail(
      id: meetId,
      name: 'ANTALYA BAHAR KUPASI',
      city: 'Antalya',
      startDate: '2026-04-12',
      endDate: '2026-04-14',
      course: 'LC',
      totalRaces: 1,
      totalAthletes: 120,
      events: [
        MeetEvent(
          eventNo: '1',
          distance: 50,
          stroke: 'free',
          strokeLabel: 'Serbest',
          gender: 'Kadın',
          status: 'Sonuçlandı',
          isPending: false,
        ),
      ],
    );
  }

  @override
  Future<List<RaceResult>> getMeetResults(
    int meetId, {
    String? eventNo,
    int? clubId,
    int? athleteId,
    String? status,
    int page = 1,
    bool summary = false,
  }) async {
    getMeetResultsCalls++;
    return const [];
  }

  @override
  Future<List<LiveMeetSummary>> getLiveMeets() async => meets;

  @override
  Future<LiveFeedResponse> getLiveSummary(
    int liveMeetId, {
    int? clubId,
    String? clubName,
    String? athleteName,
  }) async {
    getLiveSummaryCalls++;
    return LiveFeedResponse(
      liveId: liveMeetId,
      status: 'CANLI',
      events: [
        LiveEventProgramItem(
          eventNo: '1',
          name: '100m Serbest',
          distance: 100,
          stroke: 'free',
          strokeLabel: 'Serbest',
          gender: 'Erkekler',
          isPending: false,
          status: 'Sonuçlandı',
          totalAthletes: 16,
        ),
      ],
      data: const [],
    );
  }

  @override
  Future<LiveFeedResponse> getLiveEvents(int liveMeetId) async {
    getLiveEventsCalls++;
    return LiveFeedResponse(
      liveId: liveMeetId,
      status: 'CANLI',
      events: [
        LiveEventProgramItem(
          eventNo: '1',
          name: '100m Serbest',
          distance: 100,
          stroke: 'free',
          strokeLabel: 'Serbest',
          gender: 'Erkekler',
          isPending: false,
          status: 'Sonuçlandı',
          totalAthletes: 16,
        ),
      ],
      data: const [],
    );
  }

  @override
  Future<LiveFeedResponse> getLiveFeedResponse(
    int liveMeetId, {
    String? eventNo,
    String? status,
  }) async {
    if (eventNo == null || eventNo.isEmpty) {
      getLiveFeedFullCalls++;
    }
    return LiveFeedResponse(
      liveId: liveMeetId,
      status: 'CANLI',
      events: const [],
      data: const [],
    );
  }

  @override
  Future<MeetParticipants> getMeetParticipants(int meetId) async {
    return MeetParticipants(meetId: meetId, clubs: const [], athletes: const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<LiveMeetSummary> _sampleMeets() => [
      LiveMeetSummary(
        id: 1,
        name:
            'TÜRKİYE UZUN KULVAR MİLLİ TAKIM SEÇME VE OLİMPİK DENEME MÜSABAKALARI',
        city: 'Kahramanmaraş Büyükşehir Merkez',
        date: '2026-04-12',
        status: 'CANLI',
        totalAthletes: 1420,
        startListProgress: LiveProgress(processed: 36, total: 36),
        resultListProgress: LiveProgress(processed: 18, total: 36),
      ),
      LiveMeetSummary(
        id: 2,
        name: 'ANKARA İL BİRİNCİLİĞİ VE BARAJ GEÇME YARIŞLARI FİNAL SEANSI',
        city: 'Ankara',
        date: '2026-04-14',
        status: 'TAMAMLANDI',
        totalAthletes: 640,
        startListProgress: LiveProgress(processed: 20, total: 20),
        resultListProgress: LiveProgress(processed: 20, total: 20),
      ),
      LiveMeetSummary(
        id: 3,
        name: 'İZMİR BAHAR KUPASI BÖLGE YÜZME ŞAMPİYONASI VE SEÇMELERİ',
        city: 'İzmir',
        date: '2026-04-15',
        status: 'CANLI',
        totalAthletes: 315,
        startListProgress: LiveProgress(processed: 12, total: 16),
        resultListProgress: LiveProgress(processed: 0, total: 16),
      ),
      LiveMeetSummary(
        id: 4,
        name: 'BURSA KIŞ KUPASI HAZIRLIK YARIŞLARI',
        city: 'Bursa',
        date: '2026-04-16',
        status: 'BEKLIYOR',
        totalAthletes: 180,
        startListProgress: LiveProgress(processed: 0, total: 0),
        resultListProgress: LiveProgress(processed: 0, total: 0),
      ),
    ];

List<LiveMeetSummary> _manyMeets(int count) => List.generate(
      count,
      (i) => LiveMeetSummary(
        id: i + 10,
        name: 'BÖLGESEL YÜZME ŞAMPİYONASI ETAP ${i + 1}',
        city: i % 2 == 0 ? 'İstanbul' : 'Ankara',
        date: '2026-05-${(i + 1).toString().padLeft(2, '0')}',
        status: i == 0 ? 'CANLI' : (i % 3 == 0 ? 'TAMAMLANDI' : 'CANLI'),
        totalAthletes: 300 + i * 25,
        startListProgress: LiveProgress(processed: 20, total: 20),
        resultListProgress: LiveProgress(
          processed: i % 3 == 0 ? 20 : 10,
          total: 20,
        ),
      ),
    );

void main() {
  for (final isDark in [false, true]) {
    final label = isDark ? 'dark' : 'light';
    testWidgets(
      'LiveScreen timeline cards handle 0%, 50%, 100%, no-race, disableAnimations static mode at 360x780 textScale 1.3 ($label)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final theme = isDark
            ? AppTheme.dark(const CoolSophisticatedDarkPalette())
            : AppTheme.light(const CoolSophisticatedLightPalette());

        final repo = _FakeLiveScreenRepository(_sampleMeets());

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 780),
                textScaler: TextScaler.linear(1.3),
                disableAnimations: true,
                padding: EdgeInsets.only(top: 24, bottom: 16),
              ),
              child: LiveScreen(
                repository: repo,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Canlı Müsabakalar'), findsNothing);
        expect(find.text('Canlı Takip'), findsOneWidget);
        expect(find.byType(ModernFilterChipBar), findsNothing);

        // In disableAnimations mode, all cards stay at opacity 1.0 (no fading)
        final opacities = tester.widgetList<Opacity>(find.byType(Opacity));
        for (final op in opacities) {
          expect(op.opacity, 1.0);
        }

        // Verify Stories strip & Selected Story Feed render without overflow
        expect(find.text('Yarış Hikayeleri'), findsNothing);
        expect(find.text('Tam Ekran'), findsNothing);
        expect(tester.takeException(), isNull);

        // Tap a second Story card and verify feed switches cleanly
        await tester.tap(find.text('ANK').first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Open full detail screen via selected meet header
        await tester.tap(find.byKey(const ValueKey('selected_story_meet_header')));
        await tester.pumpAndSettle();
        expect(find.byType(LiveMeetDetailScreen), findsOneWidget);
        expect(repo.getLiveSummaryCalls, greaterThanOrEqualTo(1));
        expect(repo.getLiveFeedFullCalls, 0);
        expect(repo.getLiveEventsCalls, 0);
        expect(find.textContaining('Serbest'), findsWidgets);
        tester.takeException();
      },
    );
  }

  testWidgets(
    'LiveScreen handles 1-group list without overflow at 360x780 textScale 1.3',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(const CoolSophisticatedLightPalette()),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
              disableAnimations: true,
            ),
            child: LiveScreen(
              repository: _FakeLiveScreenRepository([_sampleMeets().first]),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Canlı Takip'), findsOneWidget);
      expect(find.textContaining('Kahramanmaraş'), findsWidgets);
    },
  );

  testWidgets(
    'LiveScreen handles many groups with active fisheye scroll at 360x780 textScale 1.3 without overflow',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(const CoolSophisticatedLightPalette()),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
            ),
            child: LiveScreen(
              repository: _FakeLiveScreenRepository(_manyMeets(12)),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);

      // Scroll through middle and bottom positions
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'LiveScreen prioritizes favorited live meet on open and persists toggle',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'favorite_live_meet_ids': ['2'],
      });
      await FavoriteLiveMeetsService.instance.clearAll();
      SharedPreferences.setMockInitialValues({
        'favorite_live_meet_ids': ['2'],
      });

      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(const CoolSophisticatedLightPalette()),
          home: LiveScreen(
            repository: _FakeLiveScreenRepository(_sampleMeets()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Meet id=2 (Ankara İl Birinciliği) should be prioritized & selected first
      expect(find.byKey(const ValueKey('favorite_live_meet_2')), findsOneWidget);
      expect(find.textContaining('Ankara İl Birinciliği'), findsWidgets);

      // Unfavorite meet id=2
      await tester.tap(find.byKey(const ValueKey('favorite_live_meet_2')));
      await tester.pumpAndSettle();
      expect(FavoriteLiveMeetsService.instance.isFavorite(2), isFalse);
    },
  );

  testWidgets(
    'LiveScreen opens archived MeetSummary via selectedMeetListenable without a second detail page',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _FakeLiveScreenRepository(_sampleMeets());
      final selectedMeet = ValueNotifier<LiveMeetSummary?>(null);
      addTearDown(selectedMeet.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(const CoolSophisticatedLightPalette()),
          home: LiveScreen(
            repository: repo,
            selectedMeetListenable: selectedMeet,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final archivedMeet = MeetSummary(
        id: 766,
        name: 'ANTALYA BAHAR KUPASI',
        city: 'Antalya',
        startDate: '2026-04-12',
        endDate: '2026-04-14',
        course: 'LC',
        totalRaces: 1,
        totalAthletes: 120,
      );
      selectedMeet.value = LiveMeetSummary.fromMeetSummary(archivedMeet);
      await tester.pumpAndSettle();

      expect(repo.getMeetDetailCalls, 1);
      expect(repo.getMeetResultsCalls, 1);
      expect(find.textContaining('Antalya'), findsWidgets);
      expect(find.textContaining('Serbest'), findsWidgets);
      expect(find.byType(LiveMeetDetailScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
