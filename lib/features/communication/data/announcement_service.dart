import 'package:supabase_flutter/supabase_flutter.dart';

class AnnouncementRecord {
  const AnnouncementRecord({
    required this.announcementId,
    required this.title,
    required this.content,
    required this.audienceScope,
    required this.audienceLabel,
    required this.status,
    required this.publishedAt,
    required this.expiresAt,
    required this.createdAt,
    this.readAt,
  });

  final String announcementId;
  final String title;
  final String content;
  final String audienceScope;
  final String audienceLabel;
  final String status;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime? readAt;
  bool get isRead => readAt != null;

  AnnouncementRecord withReadAt(DateTime value) => AnnouncementRecord(
    announcementId: announcementId,
    title: title,
    content: content,
    audienceScope: audienceScope,
    audienceLabel: audienceLabel,
    status: status,
    publishedAt: publishedAt,
    expiresAt: expiresAt,
    createdAt: createdAt,
    readAt: value,
  );

  bool get isPublished => status == 'published';

  factory AnnouncementRecord.fromMap(Map<String, dynamic> map) {
    return AnnouncementRecord(
      announcementId: map['announcement_id'] as String,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      audienceScope: map['audience_scope'] as String? ?? 'all_tenants',
      audienceLabel: map['audience_label'] as String? ?? 'All tenants',
      status: map['announcement_status'] as String? ?? 'draft',
      publishedAt: _dateFrom(map['published_at']),
      expiresAt: _dateFrom(map['expires_at']),
      readAt:
          _dateFrom(map['read_at']) ??
          ((map['announcement_recipient'] as List?) ?? const [])
              .map((recipient) => _dateFrom(recipient['read_at']))
              .whereType<DateTime>()
              .firstOrNull,
      createdAt:
          _dateFrom(map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static DateTime? _dateFrom(dynamic value) {
    return DateTime.tryParse(value?.toString() ?? '');
  }
}

abstract final class AnnouncementService {
  static SupabaseClient get _client => Supabase.instance.client;

  static const _columns =
      'announcement_id, title, content, audience_scope, audience_label, '
      'announcement_status, published_at, expires_at, created_at';

  static Future<List<AnnouncementRecord>> fetchAdminAnnouncements() async {
    final rows = await _client
        .from('announcement')
        .select(_columns)
        .order('created_at', ascending: false);
    return _recordsFrom(rows);
  }

  static Future<List<AnnouncementRecord>> fetchPublishedAnnouncements() async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return const [];

    final account = await _client
        .from('user_account')
        .select('accepted_at, created_at')
        .eq('user_id', currentUserId)
        .maybeSingle();
    if (account == null) return const [];

    final visibleFrom =
        _dateFrom(account['accepted_at']) ?? _dateFrom(account['created_at']);
    if (visibleFrom == null) return const [];

    final rows = await _client
        .from('announcement')
        .select('$_columns, announcement_recipient(tenant_id,read_at)')
        .eq('announcement_status', 'published')
        .eq('announcement_recipient.tenant_id', currentUserId)
        .gte('published_at', visibleFrom.toUtc().toIso8601String())
        .order('published_at', ascending: false);
    return _recordsFrom(rows);
  }

  static Future<DateTime> markRead(String announcementId) async {
    final result = await _client.rpc(
      'mark_tenant_announcement_read',
      params: {'p_announcement_id': announcementId},
    );
    return DateTime.parse(result as String);
  }

  static Future<String> createAnnouncement({
    required String title,
    required String content,
    required String audienceLabel,
    required bool publish,
  }) async {
    final audienceScope = audienceLabel == 'All tenants'
        ? 'all_tenants'
        : 'selected_units';
    final response = await _client.rpc(
      'create_announcement',
      params: {
        'p_title': title.trim(),
        'p_content': content.trim(),
        'p_audience_scope': audienceScope,
        'p_audience_label': audienceLabel,
        'p_publish': publish,
      },
    );
    return response.toString();
  }

  static Future<String> updateDraftAnnouncement({
    required String announcementId,
    required String title,
    required String content,
    required String audienceLabel,
    required bool publish,
  }) async {
    final audienceScope = audienceLabel == 'All tenants'
        ? 'all_tenants'
        : 'selected_units';
    final response = await _client.rpc(
      'update_draft_announcement',
      params: {
        'p_announcement_id': announcementId,
        'p_title': title.trim(),
        'p_content': content.trim(),
        'p_audience_scope': audienceScope,
        'p_audience_label': audienceLabel,
        'p_publish': publish,
      },
    );
    return response.toString();
  }

  static List<AnnouncementRecord> _recordsFrom(dynamic rows) {
    return (rows as List? ?? const [])
        .map(
          (row) =>
              AnnouncementRecord.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  static DateTime? _dateFrom(dynamic value) {
    return DateTime.tryParse(value?.toString() ?? '');
  }
}
