import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/live_meet.dart';
import 'notification_service.dart';

/// Yerel Favori Canlı Yarışlar Servisi
/// Kullanıcının favorilediği canlı müsabaka ID'lerini SharedPreferences ile
/// kalıcı olarak saklar ve ChangeNotifier ile ekranları anlık günceller.
class FavoriteLiveMeetsService extends ChangeNotifier {
  static final FavoriteLiveMeetsService instance =
      FavoriteLiveMeetsService._internal();

  FavoriteLiveMeetsService._internal();

  static const String _keyFavoriteLiveMeetIds = 'favorite_live_meet_ids';

  SharedPreferences? _prefs;
  final List<int> _favoriteIds = [];
  bool _isInitialized = false;

  List<int> get favoriteIds => List.unmodifiable(_favoriteIds);
  bool get isEmpty => _favoriteIds.isEmpty;
  bool get isInitialized => _isInitialized;

  bool isFavorite(int liveMeetId) => _favoriteIds.contains(liveMeetId);

  /// Servisi başlatıp kayıtlı favori canlı müsabaka ID'lerini yükler.
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      final stored = _prefs?.getStringList(_keyFavoriteLiveMeetIds) ?? [];
      _favoriteIds
        ..clear()
        ..addAll(stored.map(int.tryParse).whereType<int>());
      _isInitialized = true;
      notifyListeners();
    } catch (_) {
      _isInitialized = true;
    }
  }

  /// Canlı müsabakayı favorilere ekler veya çıkarır; yeni durumu döndürür.
  Future<bool> toggleFavorite(int liveMeetId) async {
    _prefs ??= await SharedPreferences.getInstance();
    final added = !_favoriteIds.contains(liveMeetId);
    if (added) {
      _favoriteIds.add(liveMeetId);
    } else {
      _favoriteIds.remove(liveMeetId);
    }
    await _save();
    notifyListeners();
    unawaited(
      NotificationService.instance.syncFavoriteLiveMeetTopic(liveMeetId, added),
    );
    return added;
  }

  /// Favori canlı müsabakaları listenin başına alır (mevcut sırayı koruyarak).
  List<LiveMeetSummary> sortWithFavoritesFirst(List<LiveMeetSummary> meets) {
    if (_favoriteIds.isEmpty || meets.length <= 1) {
      return List<LiveMeetSummary>.from(meets);
    }
    final favs = <LiveMeetSummary>[];
    final others = <LiveMeetSummary>[];
    for (final m in meets) {
      if (_favoriteIds.contains(m.id)) {
        favs.add(m);
      } else {
        others.add(m);
      }
    }
    return [...favs, ...others];
  }

  /// Testler için bellekteki durumu sıfırlar.
  @visibleForTesting
  Future<void> clearAll() async {
    _prefs ??= await SharedPreferences.getInstance();
    _favoriteIds.clear();
    _isInitialized = false;
    await _prefs?.remove(_keyFavoriteLiveMeetIds);
    notifyListeners();
  }

  Future<void> _save() async {
    await _prefs?.setStringList(
      _keyFavoriteLiveMeetIds,
      _favoriteIds.map((id) => id.toString()).toList(),
    );
  }
}
