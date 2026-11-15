import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class ChatConversationSummary {
  const ChatConversationSummary({
    required this.conversationId,
    required this.otherUserId,
    required this.otherPartyName,
    required this.otherPartyRole,
    required this.unitLabel,
    required this.status,
    required this.lastMessagePreview,
    required this.latestMessageAt,
    required this.unreadCount,
  });

  final String conversationId;
  final String otherUserId;
  final String otherPartyName;
  final String otherPartyRole;
  final String unitLabel;
  final String status;
  final String lastMessagePreview;
  final DateTime latestMessageAt;
  final int unreadCount;

  String get initials {
    final words = otherPartyName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  factory ChatConversationSummary.fromMap(Map<String, dynamic> map) {
    return ChatConversationSummary(
      conversationId: map['chat_conversation_id'] as String,
      otherUserId: map['other_user_id'] as String,
      otherPartyName:
          map['other_party_name'] as String? ?? 'Apartment Administrator',
      otherPartyRole: map['other_party_role'] as String? ?? 'admin',
      unitLabel: map['unit_label'] as String? ?? 'Unit not assigned',
      status: map['chat_status'] as String? ?? 'open',
      lastMessagePreview:
          map['last_message_preview'] as String? ?? 'No messages yet',
      latestMessageAt:
          DateTime.tryParse(map['latest_message_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      unreadCount: (map['unread_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatMessageRecord {
  const ChatMessageRecord({
    required this.messageId,
    required this.conversationId,
    required this.senderUserId,
    required this.messageType,
    required this.messageText,
    required this.attachmentStoragePath,
    required this.attachmentName,
    required this.attachmentMimeType,
    required this.attachmentSizeBytes,
    required this.sentAt,
    required this.deliveredAt,
    required this.readAt,
    required this.expiresAt,
  });

  final String messageId;
  final String conversationId;
  final String senderUserId;
  final String messageType;
  final String? messageText;
  final String? attachmentStoragePath;
  final String? attachmentName;
  final String? attachmentMimeType;
  final int? attachmentSizeBytes;
  final DateTime sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime expiresAt;

  bool get isFile => messageType == 'file';

  factory ChatMessageRecord.fromMap(Map<String, dynamic> map) {
    return ChatMessageRecord(
      messageId: map['message_id'] as String,
      conversationId: map['conversation_id'] as String,
      senderUserId: map['sender_user_id'] as String,
      messageType: map['message_type'] as String? ?? 'text',
      messageText: map['message_text'] as String?,
      attachmentStoragePath: map['attachment_storage_path'] as String?,
      attachmentName: map['attachment_name'] as String?,
      attachmentMimeType: map['attachment_mime_type'] as String?,
      attachmentSizeBytes: (map['attachment_size_bytes'] as num?)?.toInt(),
      sentAt:
          DateTime.tryParse(map['sent_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      deliveredAt: _dateFrom(map['delivered_at']),
      readAt: _dateFrom(map['read_at']),
      expiresAt:
          _dateFrom(map['expires_at']) ??
          DateTime.now().toUtc().add(const Duration(days: 730)),
    );
  }

  static DateTime? _dateFrom(dynamic value) {
    return DateTime.tryParse(value?.toString() ?? '');
  }
}

abstract final class ChatService {
  static SupabaseClient get _client => Supabase.instance.client;

  static String get currentUserId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('The user session has expired.');
    return userId;
  }

  static Future<List<ChatConversationSummary>> fetchConversations() async {
    final response = await _client.rpc('get_my_conversations');
    final rows = response as List? ?? const [];
    return rows
        .map(
          (row) => ChatConversationSummary.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  static Stream<List<ChatMessageRecord>> watchMessages(String conversationId) {
    return _client
        .from('message')
        .stream(primaryKey: ['message_id'])
        .eq('conversation_id', conversationId)
        .order('sent_at', ascending: true)
        .map(
          (rows) => rows
              .map(
                (row) =>
                    ChatMessageRecord.fromMap(Map<String, dynamic>.from(row)),
              )
              .toList(),
        );
  }

  static Future<void> sendTextMessage({
    required String conversationId,
    required String messageText,
  }) async {
    final text = messageText.trim();
    if (text.isEmpty) return;

    await _client.from('message').insert({
      'conversation_id': conversationId,
      'sender_user_id': currentUserId,
      'message_type': 'text',
      'message_text': text,
    });
  }

  static Future<void> sendFileMessage({
    required String conversationId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw StateError('The selected file must be smaller than 10 MB.');
    }

    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        '$conversationId/$currentUserId/${DateTime.now().microsecondsSinceEpoch}_$safeName';

    await _client.storage
        .from('chat-attachments')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    try {
      await _client.from('message').insert({
        'conversation_id': conversationId,
        'sender_user_id': currentUserId,
        'message_type': 'file',
        'message_text': null,
        'attachment_storage_path': path,
        'attachment_name': fileName,
        'attachment_mime_type': mimeType,
        'attachment_size_bytes': bytes.length,
      });
    } catch (_) {
      await _client.storage.from('chat-attachments').remove([path]);
      rethrow;
    }
  }

  static Future<String> createAttachmentUrl(String path) {
    return _client.storage.from('chat-attachments').createSignedUrl(path, 600);
  }

  static Future<void> markConversationRead(String conversationId) async {
    await _client.rpc(
      'mark_conversation_read',
      params: {'target_conversation_id': conversationId},
    );
  }

  static Future<void> performAdministratorRetentionCleanup() async {
    await _client.rpc('purge_expired_chat_messages');

    final rows = await _client
        .from('chat_attachment_cleanup_queue')
        .select('attachment_storage_path')
        .order('queued_at')
        .limit(100);

    final paths = (rows as List)
        .map((row) => (row as Map)['attachment_storage_path']?.toString())
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList();

    if (paths.isEmpty) return;

    await _client.storage.from('chat-attachments').remove(paths);
    await _client
        .from('chat_attachment_cleanup_queue')
        .delete()
        .inFilter('attachment_storage_path', paths);
  }
}
