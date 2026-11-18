/// Web stand-in for the phone's local notifications: same API, does nothing.
/// (Stop-loss/target auto-sells still run on the backend regardless.)
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  Future<void> init() async {}

  Future<void> showLevelHit({
    required int id,
    required String symbol,
    required bool isStop,
    required double price,
    required double level,
  }) async {}
}
