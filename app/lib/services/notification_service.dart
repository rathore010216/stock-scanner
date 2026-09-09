import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local (on-device) notifications for stop-loss / target alerts.
///
/// These fire while the app is running/foregrounded and the Portfolio screen
/// refreshes prices. It is NOT a background push service — see the note in
/// PortfolioScreen. Kept intentionally small: init, permission, show.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;

  static const _channelId = 'sl_target_alerts';
  static const _channelName = 'SL / Target alerts';
  static const _channelDesc =
      'Alerts when a holding reaches its stop-loss or target price';

  Future<void> init() async {
    if (_inited) return;
    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    // Create the Android channel up front.
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );
    // Ask for POST_NOTIFICATIONS on Android 13+ (no-op on older versions).
    await androidImpl?.requestNotificationsPermission();
    _inited = true;
  }

  /// Show an alert. [id] should be stable per symbol+kind so repeated
  /// notifications for the same event replace rather than stack.
  Future<void> showLevelHit({
    required int id,
    required String symbol,
    required bool isStop,
    required double price,
    required double level,
  }) async {
    if (!_inited) await init();
    final title = isStop
        ? '$symbol hit stop-loss'
        : '$symbol reached target';
    final body = isStop
        ? 'Price ₹${price.toStringAsFixed(2)} is at/below your stop '
            '₹${level.toStringAsFixed(2)}.'
        : 'Price ₹${price.toStringAsFixed(2)} is at/above your target '
            '₹${level.toStringAsFixed(2)}.';
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(id, title, body, details);
  }
}
