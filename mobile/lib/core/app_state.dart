import 'package:flutter/foundation.dart';

import 'api_client.dart';

class AppState extends ChangeNotifier {
  AppState(this.api);

  final ApiClient api;
  bool loading = true;
  bool authenticated = false;
  String? message;

  Future<void> bootstrap() async {
    authenticated = await api.restoreSession();
    loading = false;
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    loading = true;
    message = null;
    notifyListeners();
    try {
      await api.login(
        username: username.trim(),
        password: password,
        deviceName: defaultTargetPlatform.name,
      );
      authenticated = true;
      return true;
    } on ApiException catch (error) {
      message = _message(error.code);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String username,
    required String password,
    required String displayName,
    String? employeeCode,
  }) async {
    loading = true;
    message = null;
    notifyListeners();
    try {
      await api.register(
        username: username.trim(),
        password: password,
        displayName: displayName.trim(),
        employeeCode: employeeCode?.trim(),
      );
      message = 'Đã đăng ký. Tài khoản đang chờ Admin phê duyệt.';
      return true;
    } on ApiException catch (error) {
      message = _message(error.code);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await api.logout();
    authenticated = false;
    notifyListeners();
  }

  static String _message(String code) => switch (code) {
    'ACCOUNT_PENDING_APPROVAL' => 'Tài khoản đang chờ Admin phê duyệt.',
    'ACCOUNT_REJECTED' => 'Tài khoản đã bị từ chối.',
    'ACCOUNT_DISABLED' => 'Tài khoản đã bị vô hiệu hóa.',
    'USERNAME_EXISTS_OR_INVALID_INPUT' => 'Tên đăng nhập đã tồn tại hoặc dữ liệu chưa hợp lệ.',
    'NETWORK_UNAVAILABLE' => 'Không có mạng. Dữ liệu đã lưu vẫn có thể xem.',
    _ => 'Không thể hoàn tất yêu cầu ($code).',
  };
}
