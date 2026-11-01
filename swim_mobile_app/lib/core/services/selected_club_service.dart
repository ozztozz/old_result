import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global Seçili Takım / Kulüp Servisi
/// Kullanıcının seçtiği takımı SharedPreferences ile kalıcı olarak saklar
/// ve ChangeNotifier yapısıyla tüm ekranların (ve bileşenlerin) anlık reaktif
/// güncellenmesini sağlar.
class SelectedClubService extends ChangeNotifier {
  static final SelectedClubService instance = SelectedClubService._internal();

  SelectedClubService._internal();

  static const String _keyClubId = 'selected_club_id';
  static const String _keyClubName = 'selected_club_name';

  SharedPreferences? _prefs;
  int? _clubId;
  String? _clubName;
  bool _isInitialized = false;

  int? get clubId => _clubId;
  String? get clubName => _clubName;
  bool get hasSelectedClub => _clubName != null && _clubName!.trim().isNotEmpty;
  bool get isInitialized => _isInitialized;

  /// Servisi başlatıp kayıtlı kulübü yükler
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _clubId = _prefs?.getInt(_keyClubId);
      _clubName = _prefs?.getString(_keyClubName);
      _isInitialized = true;
      notifyListeners();
    } catch (_) {
      _isInitialized = true;
    }
  }

  /// Takım seçimi kaydeder
  Future<void> setClub({int? id, required String name}) async {
    _prefs ??= await SharedPreferences.getInstance();
    _clubId = id;
    _clubName = name.trim();
    if (id != null) {
      await _prefs?.setInt(_keyClubId, id);
    } else {
      await _prefs?.remove(_keyClubId);
    }
    await _prefs?.setString(_keyClubName, _clubName!);
    notifyListeners();
  }

  /// Takım seçimini sıfırlar
  Future<void> clearClub() async {
    _prefs ??= await SharedPreferences.getInstance();
    _clubId = null;
    _clubName = null;
    await _prefs?.remove(_keyClubId);
    await _prefs?.remove(_keyClubName);
    notifyListeners();
  }

  /// Kulüp ismi veya ID eşleşme kontrolü (Türkçe karakter ve kısaltma toleranslı)
  bool matches(String? otherClubName, [int? otherClubId]) {
    if (!hasSelectedClub) return false;
    if (_clubId != null && otherClubId != null && _clubId == otherClubId) {
      return true;
    }
    if (otherClubName == null || otherClubName.trim().isEmpty) return false;

    final a = _normalize(_clubName!);
    final b = _normalize(otherClubName);
    if (a.isEmpty || b.isEmpty) return false;
    return a == b || (a.length >= 3 && b.contains(a)) || (b.length >= 3 && a.contains(b));
  }

  static String _normalize(String text) {
    return text
        .replaceAll('İ', 'i')
        .replaceAll('I', 'i')
        .replaceAll('ı', 'i')
        .toLowerCase()
        .replaceAll('\u0307', '')
        .replaceAll('spor kulübü', '')
        .replaceAll('spor kulubu', '')
        .replaceAll('yüzme kulübü', '')
        .replaceAll('yuzme kulubu', '')
        .replaceAll('kulübü', '')
        .replaceAll('kulubu', '')
        .replaceAll('derneği', '')
        .replaceAll('dernegi', '')
        .replaceAll('s.k.', '')
        .replaceAll('s.k', '')
        .replaceAll('sk', '')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

