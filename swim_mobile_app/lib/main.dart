import 'package:flutter/material.dart';
import 'core/theme/swim_theme.dart';
import 'core/network/api_client.dart';
import 'data/repositories/swim_repository.dart';
import 'features/home/home_screen.dart';
import 'features/live/live_screen.dart';
import 'features/favorites/favorites_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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
      theme: SwimTheme.light(),
      darkTheme: SwimTheme.dark(),
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
  int _currentIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(repository: widget.repository),
      LiveScreen(repository: widget.repository),
      FavoritesScreen(repository: widget.repository),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        elevation: 0,
        backgroundColor: Theme.of(context).cardTheme.color,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Ana Sayfa',
          ),
          NavigationDestination(
            icon: const Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors, color: context.swimColors.danger),
            label: 'Canlı Takip',
          ),
          NavigationDestination(
            icon: const Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star, color: context.swimColors.medalGold),
            label: 'Favorilerim',
          ),
        ],
      ),
    );
  }
}
