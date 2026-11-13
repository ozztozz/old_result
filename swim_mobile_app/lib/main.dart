import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'core/network/api_client.dart';
import 'core/services/favorite_athletes_service.dart';
import 'core/services/selected_club_service.dart';
import 'data/repositories/swim_repository.dart';
import 'features/home/home_screen.dart';
import 'features/live/live_screen.dart';
import 'features/favorites/favorites_screen.dart';
import 'shared/widgets/app_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global Tercihler, Kulüp ve Favori Sporcular Servisi
  await Future.wait([
    SelectedClubService.instance.init(),
    FavoriteAthletesService.instance.init(),
  ]);

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
    return MaterialApp(
      title: 'TYF Yüzme Sonuçları',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: MainNavigationContainer(repository: repository),
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
  int _currentIndex = 1; // Canlı Takip ile açılış
  late final List<GlobalKey<NavigatorState>> _navigatorKeys;

  @override
  void initState() {
    super.initState();
    _navigatorKeys = [
      GlobalKey<NavigatorState>(),
      GlobalKey<NavigatorState>(),
      GlobalKey<NavigatorState>(),
    ];
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
          _buildTabNavigator(0, HomeScreen(repository: widget.repository)),
          _buildTabNavigator(1, LiveScreen(repository: widget.repository)),
          _buildTabNavigator(2, FavoritesScreen(repository: widget.repository)),
        ],
      ),
    );
  }
}
