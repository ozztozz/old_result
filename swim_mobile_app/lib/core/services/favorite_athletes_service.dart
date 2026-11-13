import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global Favori Sporcular Servisi
/// Kullanıcının takip ettiği sporcu ID'lerini SharedPreferences ile kalıcı
/// olarak saklar ve ChangeNotifier ile ekranları anlık günceller.
class FavoriteAthletesService extends ChangeNotifier {
  static final FavoriteAthletesService instance =
      FavoriteAthletesService._internal();

  FavoriteAthletesService._internal();

  static const String _keyFavoriteIds = 'favorite_athlete_ids';

  SharedPreferences? _prefs;
  final List<int> _favoriteIds = [];
  bool _isInitialized = false;

  List<int> get favoriteIds => List.unmodifiable(_favoriteIds);
  bool get isEmpty => _favoriteIds.isEmpty;
  bool get isInitialized => _isInitialized;

  bool isFavorite(int athleteId) => _favoriteIds.contains(athleteId);

  /// Servisi başlatıp kayıtlı favori sporcu ID'lerini yükler
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      final stored = _prefs?.getStringList(_keyFavoriteIds) ?? [];
      _favoriteIds
        ..clear()
        ..addAll(stored.map(int.tryParse).whereType<int>());
      _isInitialized = true;
      notifyListeners();
    } catch (_) {
      _isInitialized = true;
    }
  }

  /// Sporcuyu favorilere ekler veya çıkarır; yeni durumu döndürür
  Future<bool> toggleFavorite(int athleteId) async {
    _prefs ??= await SharedPreferences.getInstance();
    final added = !_favoriteIds.contains(athleteId);
    if (added) {
      _favoriteIds.add(athleteId);
    } else {
      _favoriteIds.remove(athleteId);
    }
    await _save();
    notifyListeners();
    return added;
  }

  /// Favorilerden belirli bir sporcuyu çıkarır
  Future<void> removeFavorite(int athleteId) async {
    if (!_favoriteIds.contains(athleteId)) return;
    _prefs ??= await SharedPreferences.getInstance();
    _favoriteIds.remove(athleteId);
    await _save();
    notifyListeners();
  }

  /// Testler için bellekteki durumu sıfırlar
  @visibleForTesting
  Future<void> clearAll() async {
    _prefs ??= await SharedPreferences.getInstance();
    _favoriteIds.clear();
    await _prefs?.remove(_keyFavoriteIds);
    notifyListeners();
  }

  Future<void> _save() async {
    await _prefs?.setStringList(
      _keyFavoriteIds,
      _favoriteIds.map((id) => id.toString()).toList(),
    );
  }
}
