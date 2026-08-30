import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'session_store.dart';

class CachedResponse {
  const CachedResponse(this.data, {required this.isStale, required this.fromCache});

  final Map<String, dynamic> data;
  final bool isStale;
  final bool fromCache;
}

class ApiException implements Exception {
  const ApiException(this.code, [this.statusCode]);

  final String code;
  final int? statusCode;

  @override
  String toString() => code;
}

class ApiClient {
  ApiClient({
    required this.sessionStore,
    http.Client? client,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       baseUrl = (baseUrl ?? const String.fromEnvironment(
         'BMA_API_BASE_URL',
         defaultValue: 'https://gateway.abmtlab.com/bmapp/api/v1',
       )).replaceAll(RegExp(r'/$'), '');

  final SessionStore sessionStore;
  final http.Client _client;
  final String baseUrl;
  SessionData? _session;
  bool _refreshing = false;

  Future<bool> restoreSession() async {
    _session = await sessionStore.read();
    return _session != null;
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String displayName,
    String? employeeCode,
  }) => _sendJson(
    'POST',
    '/auth/register',
    body: {
      'username': username,
      'password': password,
      'display_name': displayName,
      'employee_code': employeeCode,
    },
    authenticated: false,
  );

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    required String deviceName,
  }) async {
    final response = await _sendJson(
      'POST',
      '/auth/login',
      body: {
        'username': username,
        'password': password,
        'device_name': deviceName,
      },
      authenticated: false,
    );
    await _saveTokens(response);
    return response;
  }

  Future<void> logout() async {
    final refresh = _session?.refreshToken;
    if (refresh != null) {
      try {
        await _sendJson(
          'POST',
          '/auth/revoke',
          body: {'refresh_token': refresh, 'reason': 'USER_LOGOUT'},
        );
      } on Object {
        // Local logout must remain available when the network is unavailable.
      }
    }
    _session = null;
    await sessionStore.clear();
  }

  Future<CachedResponse> getCached(String path) async {
    final preferences = await SharedPreferences.getInstance();
    final cacheKey = Uri.encodeComponent('$baseUrl$path');
    final etagKey = '${cacheKey}_etag';
    final bodyKey = '${cacheKey}_body';
    final headers = <String, String>{};
    final etag = preferences.getString(etagKey);
    if (etag != null) headers['If-None-Match'] = etag;
    try {
      final response = await _send(
        'GET',
        path,
        headers: headers,
        retryAfterRefresh: true,
      );
      if (response.statusCode == HttpStatus.notModified) {
        final cached = preferences.getString(bodyKey);
        if (cached != null) {
          return CachedResponse(
            jsonDecode(cached) as Map<String, dynamic>,
            isStale: false,
            fromCache: true,
          );
        }
      }
      _ensureSuccess(response);
      await preferences.setString(bodyKey, response.body);
      final responseEtag = response.headers['etag'];
      if (responseEtag != null) await preferences.setString(etagKey, responseEtag);
      return CachedResponse(
        jsonDecode(response.body) as Map<String, dynamic>,
        isStale: false,
        fromCache: false,
      );
    } on ApiException catch (error) {
      if (error.statusCode != null) rethrow;
      final cached = preferences.getString(bodyKey);
      if (cached == null) rethrow;
      return CachedResponse(
        jsonDecode(cached) as Map<String, dynamic>,
        isStale: true,
        fromCache: true,
      );
    }
  }

  Future<void> post(String path, [Map<String, dynamic>? body]) async {
    final response = await _send('POST', path, body: body, retryAfterRefresh: true);
    _ensureSuccess(response);
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final response = await _send(
      method,
      path,
      body: body,
      retryAfterRefresh: authenticated,
      authenticated: authenticated,
    );
    _ensureSuccess(response);
    return response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    bool retryAfterRefresh = false,
    bool authenticated = true,
  }) async {
    if (authenticated) await _ensureAccessToken();
    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip',
      if (body != null) 'Content-Type': 'application/json',
      if (authenticated && _session != null)
        'Authorization': 'Bearer ${_session!.accessToken}',
      ...?headers,
    };
    try {
      final uri = Uri.parse('$baseUrl$path');
      final encoded = body == null ? null : jsonEncode(body);
      final response = switch (method) {
        'GET' => await _client.get(uri, headers: requestHeaders),
        'POST' => await _client.post(uri, headers: requestHeaders, body: encoded),
        _ => throw const ApiException('UNSUPPORTED_HTTP_METHOD'),
      };
      if (response.statusCode == HttpStatus.unauthorized && retryAfterRefresh) {
        final refreshed = await _refresh();
        if (refreshed) {
          return _send(
            method,
            path,
            headers: headers,
            body: body,
            authenticated: authenticated,
          );
        }
      }
      return response;
    } on SocketException {
      throw const ApiException('NETWORK_UNAVAILABLE');
    } on http.ClientException {
      throw const ApiException('NETWORK_UNAVAILABLE');
    }
  }

  Future<void> _ensureAccessToken() async {
    _session ??= await sessionStore.read();
    if (_session == null) throw const ApiException('SESSION_REQUIRED', 401);
    if (_session!.accessExpiresAt.isBefore(DateTime.now().toUtc().add(const Duration(seconds: 30)))) {
      final refreshed = await _refresh();
      if (!refreshed) throw const ApiException('SESSION_REVOKED', 401);
    }
  }

  Future<bool> _refresh() async {
    if (_refreshing) {
      while (_refreshing) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return _session != null;
    }
    _session ??= await sessionStore.read();
    if (_session == null) return false;
    _refreshing = true;
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _session!.refreshToken}),
      );
      if (response.statusCode == HttpStatus.unauthorized) {
        _session = null;
        await sessionStore.clear();
        return false;
      }
      _ensureSuccess(response);
      await _saveTokens(jsonDecode(response.body) as Map<String, dynamic>);
      return true;
    } on SocketException {
      throw const ApiException('NETWORK_UNAVAILABLE');
    } on http.ClientException {
      throw const ApiException('NETWORK_UNAVAILABLE');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _saveTokens(Map<String, dynamic> value) async {
    final session = SessionData(
      accessToken: value['access_token'] as String,
      refreshToken: value['refresh_token'] as String,
      accessExpiresAt: DateTime.parse(value['access_expires_at'] as String).toUtc(),
    );
    _session = session;
    await sessionStore.write(session);
  }

  static void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    var code = 'HTTP_${response.statusCode}';
    try {
      final value = jsonDecode(response.body) as Map<String, dynamic>;
      code = (value['error'] ?? code).toString();
    } on Object {
      // Preserve the compact HTTP error when the response is not JSON.
    }
    throw ApiException(code, response.statusCode);
  }
}
