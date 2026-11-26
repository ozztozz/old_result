import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Arka plan / kapalı durumda gelen FCM mesajlarını işleyen üst düzey fonksiyon.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

/// Canlı Yarış Bildirim Servisi (FCM + Local Notifications Hibrit)
///
/// Kullanıcı girişi gerektirmez; favori canlı müsabakalar için
/// `live_meet_<id>` FCM topic aboneliklerini yönetir.
class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._internal();

  NotificationService._internal();

  static const String _keyLiveNotificationsEnabled =
      'live_notifications_enabled';
  static const String _keySubscribedTopics = 'subscribed_live_meet_topics';
  static const String liveChannelId = 'live_races_channel';
  static const String liveChannelName = 'Canlı Yarış Bildirimleri';
  static const String liveChannelDescription =
      'Takip edilen canlı müsabakalardaki yeni seri ve sonuç bildirimleri.';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<int> _liveMeetTapController =
      StreamController<int>.broadcast();

  SharedPreferences? _prefs;
  bool _isInitialized = false;
  bool _firebaseAvailable = false;
  bool _liveNotificationsEnabled = true;
  bool _hasPermission = false;
  int? _pendingLiveMeetId;
  final Set<String> _subscribedTopics = {};

  bool get isInitialized => _isInitialized;
  bool get firebaseAvailable => _firebaseAvailable;
  bool get liveNotificationsEnabled => _liveNotificationsEnabled;
  bool get hasPermission => _hasPermission;
  Stream<int> get onLiveMeetTap => _liveMeetTapController.stream;

  /// Uygulama kapalıyken bildirime tıklanarak açıldıysa bekleyen müsabaka ID'sini döndürür.
  int? consumePendingLiveMeetId() {
    final id = _pendingLiveMeetId;
    _pendingLiveMeetId = null;
    return id;
  }

  /// Servisi başlatır: tercihleri yükler, yerel bildirimleri ve FCM'i yapılandırır.
  Future<void> init({List<int> initialFavoriteMeetIds = const []}) async {
    if (_isInitialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      _liveNotificationsEnabled =
          _prefs?.getBool(_keyLiveNotificationsEnabled) ?? true;
      final storedTopics = _prefs?.getStringList(_keySubscribedTopics) ?? [];
      _subscribedTopics
        ..clear()
        ..addAll(storedTopics);
    } catch (_) {}

    await _initLocalNotifications();
    await _initFirebaseMessaging(initialFavoriteMeetIds);

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _initLocalNotifications() async {
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          _handlePayloadString(response.payload);
        },
      );

      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        const channel = AndroidNotificationChannel(
          liveChannelId,
          liveChannelName,
          description: liveChannelDescription,
          importance: Importance.high,
        );
        await androidPlugin.createNotificationChannel(channel);
      }
    } catch (e) {
      debugPrint('[NotificationService] Local init hatası: $e');
    }
  }

  Future<void> _initFirebaseMessaging(List<int> initialFavoriteMeetIds) async {
    try {
      await Firebase.initializeApp();
      _firebaseAvailable = true;

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.getNotificationSettings();
      _hasPermission =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;

      // Eğer kullanıcı henüz karar vermediyse ve bildirimler aktifse izin iste
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined &&
          _liveNotificationsEnabled) {
        await requestPermission();
      }

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Ön planda gelen mesajları yerel bildirim olarak göster
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // Arka plandayken bildirime tıklanma
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

      // Uygulama kapalıyken bildirime tıklanarak açılma
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        final meetId = _extractLiveMeetId(initialMessage.data);
        if (meetId != null) {
          _pendingLiveMeetId = meetId;
        }
      }

      if (_liveNotificationsEnabled && _hasPermission) {
        await syncAllFavoriteTopics(initialFavoriteMeetIds);
      }
    } catch (e) {
      _firebaseAvailable = false;
      debugPrint('[NotificationService] Firebase başlatılamadı: $e');
    }
  }

  /// İşletim sisteminden bildirim izni ister.
  Future<bool> requestPermission() async {
    bool granted = false;

    try {
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final androidGranted =
            await androidPlugin.requestNotificationsPermission();
        if (androidGranted != null) {
          granted = androidGranted;
        }
      }
    } catch (_) {}

    if (_firebaseAvailable) {
      try {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        granted = settings.authorizationStatus ==
                AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      } catch (_) {}
    }

    _hasPermission = granted;
    notifyListeners();
    return granted;
  }

  /// Canlı yarış bildirimlerini açar veya kapatır.
  Future<bool> setLiveNotificationsEnabled(
    bool enabled, {
    List<int> favoriteMeetIds = const [],
  }) async {
    _prefs ??= await SharedPreferences.getInstance();

    if (enabled && !_hasPermission) {
      final granted = await requestPermission();
      if (!granted) {
        _liveNotificationsEnabled = false;
        await _prefs?.setBool(_keyLiveNotificationsEnabled, false);
        notifyListeners();
        return false;
      }
    }

    _liveNotificationsEnabled = enabled;
    await _prefs?.setBool(_keyLiveNotificationsEnabled, enabled);

    if (enabled) {
      await syncAllFavoriteTopics(favoriteMeetIds);
    } else {
      await _unsubscribeAllTopics();
    }

    notifyListeners();
    return true;
  }

  /// Tek bir favori canlı müsabaka için topic aboneliğini günceller.
  Future<void> syncFavoriteLiveMeetTopic(
    int liveMeetId,
    bool isFavorite,
  ) async {
    if (!_firebaseAvailable) return;
    final topic = topicForLiveMeet(liveMeetId);

    try {
      if (isFavorite && _liveNotificationsEnabled) {
        if (!_subscribedTopics.contains(topic)) {
          await FirebaseMessaging.instance.subscribeToTopic(topic);
          _subscribedTopics.add(topic);
          await _saveSubscribedTopics();
        }
      } else {
        if (_subscribedTopics.contains(topic)) {
          await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
          _subscribedTopics.remove(topic);
          await _saveSubscribedTopics();
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] Topic sync hatası ($topic): $e');
    }
  }

  /// Kayıtlı tüm favori canlı müsabaka topic'lerini senkronize eder.
  Future<void> syncAllFavoriteTopics(List<int> favoriteMeetIds) async {
    if (!_firebaseAvailable || !_liveNotificationsEnabled) return;

    final desiredTopics = favoriteMeetIds.map(topicForLiveMeet).toSet();
    final toUnsubscribe = _subscribedTopics.difference(desiredTopics).toList();
    final toSubscribe = desiredTopics.difference(_subscribedTopics).toList();

    for (final topic in toUnsubscribe) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
        _subscribedTopics.remove(topic);
      } catch (e) {
        debugPrint('[NotificationService] Unsubscribe hatası ($topic): $e');
      }
    }

    for (final topic in toSubscribe) {
      try {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
        _subscribedTopics.add(topic);
      } catch (e) {
        debugPrint('[NotificationService] Subscribe hatası ($topic): $e');
      }
    }

    await _saveSubscribedTopics();
  }

  Future<void> _unsubscribeAllTopics() async {
    if (!_firebaseAvailable) return;
    for (final topic in _subscribedTopics.toList()) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
        _subscribedTopics.remove(topic);
      } catch (e) {
        debugPrint('[NotificationService] Unsubscribe hatası ($topic): $e');
      }
    }
    await _saveSubscribedTopics();
  }

  Future<void> _saveSubscribedTopics() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setStringList(
        _keySubscribedTopics,
        _subscribedTopics.toList(),
      );
    } catch (_) {}
  }

  void _onForegroundMessage(RemoteMessage message) {
    if (!_liveNotificationsEnabled) return;

    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'Canlı Yarış Güncellemesi';
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        'Takip ettiğiniz müsabakada yeni sonuçlar var.';

    final meetId = _extractLiveMeetId(message.data);
    final payload = meetId != null ? jsonEncode({'live_meet_id': meetId}) : null;

    _localNotifications.show(
      id: meetId ?? message.hashCode,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          liveChannelId,
          liveChannelName,
          channelDescription: liveChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    final meetId = _extractLiveMeetId(message.data);
    if (meetId != null) {
      _liveMeetTapController.add(meetId);
    }
  }

  void _handlePayloadString(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        final meetId = _extractLiveMeetId(decoded);
        if (meetId != null) {
          _liveMeetTapController.add(meetId);
        }
      }
    } catch (_) {
      final directId = int.tryParse(payload);
      if (directId != null) {
        _liveMeetTapController.add(directId);
      }
    }
  }

  int? _extractLiveMeetId(Map<String, dynamic> data) {
    final raw = data['live_meet_id'] ?? data['meet_id'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  static String topicForLiveMeet(int liveMeetId) => 'live_meet_$liveMeetId';
}
