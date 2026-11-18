import 'package:firebase_core/firebase_core.dart';

/// Firebase settings for the WEB build only (the Android app reads
/// google-services.json instead). Values are injected at build time with
/// --dart-define by .github/workflows/build-web.yml from the
/// FIREBASE_WEB_CONFIG secret, so nothing is hard-coded here.
const _apiKey = String.fromEnvironment('FB_API_KEY');
const _appId = String.fromEnvironment('FB_APP_ID');
const _senderId = String.fromEnvironment('FB_MESSAGING_SENDER_ID');
const _projectId =
    String.fromEnvironment('FB_PROJECT_ID', defaultValue: 'stock-scanner-a4418');
const _authDomain = String.fromEnvironment('FB_AUTH_DOMAIN',
    defaultValue: 'stock-scanner-a4418.firebaseapp.com');
const _databaseUrl = String.fromEnvironment('FB_DATABASE_URL',
    defaultValue: 'https://stock-scanner-a4418-default-rtdb.firebaseio.com');
const _storageBucket = String.fromEnvironment('FB_STORAGE_BUCKET');

/// True when the build was given the web app's apiKey + appId.
bool get webFirebaseConfigured => _apiKey.isNotEmpty && _appId.isNotEmpty;

const webFirebaseOptions = FirebaseOptions(
  apiKey: _apiKey,
  appId: _appId,
  messagingSenderId: _senderId,
  projectId: _projectId,
  authDomain: _authDomain,
  databaseURL: _databaseUrl,
  storageBucket: _storageBucket == '' ? null : _storageBucket,
);
