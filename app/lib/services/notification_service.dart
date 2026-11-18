// Local notifications exist only on the phone. The web build gets a no-op
// version with the same API, so flutter_local_notifications (Android-only)
// is never compiled into the web app.
export 'notification_service_mobile.dart'
    if (dart.library.js_interop) 'notification_service_web.dart';
