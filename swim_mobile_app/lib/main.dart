import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/network/api_client.dart';
import 'core/services/favorite_athletes_service.dart';
import 'core/services/favorite_live_meets_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/selected_club_service.dart';
import 'core/services/theme_service.dart';
import 'data/models/live_meet.dart';
import 'data/models/meet.dart';
import 'data/repositories/swim_repository.dart';
import 'features/home/home_screen.dart';
import 'features/live/live_screen.dart';
import 'features/favorites/favorites_screen.dart';
import 'features/splash/splash_screen.dart';
import 'shared/widgets/app_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Global Tercihler, Tema, Kulüp ve Favori Sporcular Servisi
  await Future.wait([
    ThemeService.instance.init(),
    SelectedClubService.instance.init(),
    FavoriteAthletesService.instance.init(),
    FavoriteLiveMeetsService.instance.init(),
  ]);

  await NotificationService.instance.init(
    initialFavoriteMeetIds: FavoriteLiveMeetsService.instance.favoriteIds,
  );

  // Merkezi HTTP ve Veri Deposu
  final apiClient = ApiClient();
  final repository = SwimRepository(apiClient: apiClient);

  runApp(SwimApp(repository: repository));
}

class SwimApp extends StatelessWidget {
  final SwimRepository repository;

  const SwimApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final themeService = ThemeService.instance;
        final platformDark =
            MediaQuery.platformBrightnessOf(context) == Brightness.dark;
        final isDark = themeService.themeMode == ThemeMode.dark ||
            (themeService.themeMode == ThemeMode.system && platformDark);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
          child: MaterialApp(
            title: 'KulvaR',
            debugShowCheckedModeBanner: false,
            theme: themeService.lightTheme,
            darkTheme: themeService.darkTheme,
            themeMode: themeService.themeMode,
            home: SplashScreen(repository: repository),
          ),
        );
      },
    );
  }
}

class MainNavigationContainer extends StatefulWidget {
  final SwimRepository repository;

  const MainNavigationContainer({super.key, required this.repository});

  @override
  State<MainNavigationContainer> createState() => _MainNavigationContainerState();
}

class _MainNavigationContainerState extends State<MainNavigationContainer> {
  int _currentIndex = 0; // Ana Sayfa ile açılış
  late final List<GlobalKey<NavigatorState>> _navigatorKeys;
  final ValueNotifier<int?> _requestedLiveMeetId = ValueNotifier<int?>(null);
  final ValueNotifier<LiveMeetSummary?> _requestedLiveMeet =
      ValueNotifier<LiveMeetSummary?>(null);
  StreamSubscription<int>? _notificationTapSub;

  @override
  void initState() {
    super.initState();
    _navigatorKeys = [
      GlobalKey<NavigatorState>(),
      GlobalKey<NavigatorState>(),
      GlobalKey<NavigatorState>(),
    ];
    _notificationTapSub =
        NotificationService.instance.onLiveMeetTap.listen(_openLiveMeetInLiveTab);
    final pendingMeetId = NotificationService.instance.consumePendingLiveMeetId();
    if (pendingMeetId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openLiveMeetInLiveTab(pendingMeetId);
      });
    }
  }

  @override
  void dispose() {
    _notificationTapSub?.cancel();
    _requestedLiveMeetId.dispose();
    _requestedLiveMeet.dispose();
    super.dispose();
  }

  void _openLiveMeetInLiveTab(int liveMeetId) {
    if (_requestedLiveMeetId.value == liveMeetId) {
      _requestedLiveMeetId.value = null;
    }
    _requestedLiveMeetId.value = liveMeetId;
    if (_currentIndex != 1) {
      setState(() => _currentIndex = 1);
    }
    _navigatorKeys[1].currentState?.popUntil((route) => route.isFirst);
  }

  void _openMeetInLiveTab(MeetSummary meet) {
    final live = LiveMeetSummary.fromMeetSummary(meet);
    if (_requestedLiveMeet.value?.id == live.id &&
        _requestedLiveMeet.value?.meetId == live.meetId) {
      _requestedLiveMeet.value = null;
    }
    _requestedLiveMeet.value = live;
    if (_currentIndex != 1) {
      setState(() => _currentIndex = 1);
    }
    _navigatorKeys[1].currentState?.popUntil((route) => route.isFirst);
  }

  void _onNavigationChanged(int index) {
    if (index == _currentIndex) {
      // Aktif sekmeye tekrar tıklandığında o sekmenin kök sayfasına dön
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _currentIndex = index);
    }
  }

  Widget _buildTabNavigator(int index, Widget rootScreen) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (routeSettings) {
        return MaterialPageRoute(
          builder: (context) => rootScreen,
          settings: routeSettings,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final currentNavigator = _navigatorKeys[_currentIndex].currentState;
        if (currentNavigator != null && currentNavigator.canPop()) {
          currentNavigator.pop();
        } else if (_currentIndex != 1) {
          setState(() => _currentIndex = 1);
        } else {
          SystemNavigator.pop();
        }
      },
      child: AppScaffold(
        currentIndex: _currentIndex,
        onNavigationChanged: _onNavigationChanged,
        screens: [
          _buildTabNavigator(
            0,
            HomeScreen(
              repository: widget.repository,
              onOpenLiveMeet: _openLiveMeetInLiveTab,
              onOpenMeetInLive: _openMeetInLiveTab,
            ),
          ),
          _buildTabNavigator(
            1,
            LiveScreen(
              repository: widget.repository,
              selectedMeetIdListenable: _requestedLiveMeetId,
              selectedMeetListenable: _requestedLiveMeet,
            ),
          ),
          _buildTabNavigator(2, FavoritesScreen(repository: widget.repository)),
        ],
      ),
    );
  }
}
