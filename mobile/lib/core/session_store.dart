import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionData {
  const SessionData({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
}

class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'bma_access_token';
  static const _refreshKey = 'bma_refresh_token';
  static const _expiryKey = 'bma_access_expiry';
  final FlutterSecureStorage _storage;

  Future<SessionData?> read() async {
    final values = await _storage.readAll();
    final access = values[_accessKey];
    final refresh = values[_refreshKey];
    final expiry = DateTime.tryParse(values[_expiryKey] ?? '');
    if (access == null || refresh == null || expiry == null) return null;
    return SessionData(
      accessToken: access,
      refreshToken: refresh,
      accessExpiresAt: expiry,
    );
  }

  Future<void> write(SessionData session) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: session.accessToken),
      _storage.write(key: _refreshKey, value: session.refreshToken),
      _storage.write(
        key: _expiryKey,
        value: session.accessExpiresAt.toUtc().toIso8601String(),
      ),
    ]);
  }

  Future<void> clear() => _storage.deleteAll();
}
