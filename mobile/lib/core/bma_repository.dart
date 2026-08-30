import 'api_client.dart';

class BmaRepository {
  const BmaRepository(this.api);

  final ApiClient api;

  Future<CachedResponse> dashboard() => api.getCached('/dashboard');
  Future<CachedResponse> recovery() => api.getCached('/recovery/latest');
  Future<CachedResponse> quality() => api.getCached('/quality/latest?limit=30');
  Future<CachedResponse> attendance() => api.getCached('/attendance/me');
  Future<CachedResponse> profile() => api.getCached('/profile/me');
  Future<CachedResponse> announcements() => api.getCached('/announcements');
  Future<void> markAnnouncementRead(String id) => api.post('/announcements/$id/read');
}
