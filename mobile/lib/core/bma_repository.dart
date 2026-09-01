import 'api_client.dart';

class BmaRepository {
  const BmaRepository(this.api);

  final ApiClient api;

  Future<CachedResponse> dashboard() => api.getCached('/dashboard');
  Future<CachedResponse> recovery() => api.getCached('/recovery/latest');
  Future<CachedResponse> quality() => api.getCached('/quality/latest?limit=30');
  Future<CachedResponse> attendance() => api.getCached('/attendance/me');
  Future<CachedResponse> profile() => api.getCached('/profile/me');
  Future<CachedResponse> announcements() async {
    final response = await api.getCached('/announcements');
    applyLocalAnnouncementReads(
      response.data,
      await api.localAnnouncementReadIds(),
    );
    return response;
  }

  Future<void> markAnnouncementRead(String id) async {
    await api.rememberAnnouncementRead(id);
    try {
      await api.post('/announcements/$id/read');
    } on ApiException catch (error) {
      if (error.code != 'NETWORK_UNAVAILABLE') rethrow;
    }
  }
}

void applyLocalAnnouncementReads(
  Map<String, dynamic> data,
  Set<String> locallyReadIds,
) {
  final items = data['items'] as List? ?? const [];
  for (final item in items.whereType<Map<String, dynamic>>()) {
    final id = item['id']?.toString();
    if (id != null && locallyReadIds.contains(id) && item['read_at'] == null) {
      item['read_at'] = 'LOCAL';
    }
  }
}
