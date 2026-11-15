import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/chat_service.dart';

class ChatConversationView extends StatefulWidget {
  const ChatConversationView({required this.conversation, super.key});

  final ChatConversationSummary conversation;

  @override
  State<ChatConversationView> createState() => _ChatConversationViewState();
}

class _ChatConversationViewState extends State<ChatConversationView> {
  static const _allowedExtensions = <String>[
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'txt',
    'csv',
  ];

  late Stream<List<ChatMessageRecord>> _messages;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  bool _markingRead = false;
  int _lastMessageCount = -1;

  @override
  void initState() {
    super.initState();
    _messages = ChatService.watchMessages(widget.conversation.conversationId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    if (text.length > 2000) {
      _showMessage('Keep each message within 2,000 characters.');
      return;
    }

    setState(() => _sending = true);
    try {
      await ChatService.sendTextMessage(
        conversationId: widget.conversation.conversationId,
        messageText: text,
      );
      _messageController.clear();
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error, sendingFile: false));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendFile() async {
    if (_sending) return;

    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
    );
    if (file == null) return;

    final extension = _extensionOf(file.name);
    if (!_allowedExtensions.contains(extension)) {
      _showMessage('Choose a supported document or image file.');
      return;
    }

    final size = file.lengthSync() ?? await file.length() ?? 0;
    if (size <= 0 || size > 10 * 1024 * 1024) {
      _showMessage('Choose a non-empty file smaller than 10 MB.');
      return;
    }

    setState(() => _sending = true);
    try {
      await ChatService.sendFileMessage(
        conversationId: widget.conversation.conversationId,
        fileName: file.name,
        mimeType: _mimeTypeFor(extension),
        bytes: await file.readAsBytes(),
      );
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error, sendingFile: true));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openAttachment(ChatMessageRecord message) async {
    final path = message.attachmentStoragePath;
    if (path == null) return;

    try {
      final url = await ChatService.createAttachmentUrl(path);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        _showMessage('The attachment could not be opened.');
      }
    } catch (_) {
      if (mounted) _showMessage('The attachment is temporarily unavailable.');
    }
  }

  void _scheduleReadAndScroll(List<ChatMessageRecord> messages) {
    final currentUserId = ChatService.currentUserId;
    if (!_markingRead &&
        messages.any(
          (message) =>
              message.senderUserId != currentUserId && message.readAt == null,
        )) {
      _markingRead = true;
      ChatService.markConversationRead(
        widget.conversation.conversationId,
      ).catchError((_) {}).whenComplete(() => _markingRead = false);
    }

    if (_lastMessageCount == messages.length) return;
    _lastMessageCount = messages.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<ChatMessageRecord>>(
            stream: _messages,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return _ChatLoadError(
                  onRetry: () => setState(
                    () => _messages = ChatService.watchMessages(
                      widget.conversation.conversationId,
                    ),
                  ),
                );
              }

              final messages = snapshot.data ?? const <ChatMessageRecord>[];
              _scheduleReadAndScroll(messages);

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                itemCount: messages.isEmpty ? 2 : messages.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) return const _RetentionNotice();
                  if (index == 1 && messages.isEmpty) {
                    return const _EmptyConversation();
                  }
                  if (messages.isEmpty) return const SizedBox.shrink();

                  final message = messages[index - 1];
                  return _MessageBubble(
                    message: message,
                    isMine: message.senderUserId == ChatService.currentUserId,
                    onOpenAttachment: () => _openAttachment(message),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE8EBF0))),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: _sending ? null : _pickAndSendFile,
                  tooltip: 'Send a file',
                  icon: const Icon(Icons.attach_file_rounded),
                  color: AppColors.primary,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendText(),
                    decoration: InputDecoration(
                      hintText: 'Write a message...',
                      filled: true,
                      fillColor: const Color(0xFFF1F3F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                IconButton(
                  onPressed: _sending ? null : _sendText,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFD9DEEA),
                    padding: const EdgeInsets.all(12),
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 21),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  static String _mimeTypeFor(String extension) {
    return switch (extension) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt' => 'text/plain',
      'csv' => 'text/csv',
      _ => 'application/octet-stream',
    };
  }

  static String _friendlyError(Object error, {required bool sendingFile}) {
    final message = error.toString().replaceFirst('Bad state: ', '');
    if (message.contains('chat-attachments') ||
        message.contains('message_type')) {
      return 'The live chat database update has not been applied yet.';
    }
    return sendingFile
        ? 'The file could not be sent. Please try again.'
        : 'The message could not be sent. Please try again.';
  }
}

class _RetentionNotice extends StatelessWidget {
  const _RetentionNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3FF),
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'You can start the conversation now. Messages and shared files are retained for up to two years for communication traceability, after which they are automatically deleted.',
              style: TextStyle(
                color: Color(0xFF5D75B4),
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 50),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, color: Color(0xFFADB5C4), size: 44),
          SizedBox(height: 12),
          Text(
            'No messages yet',
            style: TextStyle(
              color: AppColors.heading,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Send a message or file to begin this conversation.',
            style: TextStyle(color: AppColors.body, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ChatLoadError extends StatelessWidget {
  const _ChatLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: Color(0xFFE8953E),
              size: 42,
            ),
            const SizedBox(height: 10),
            const Text(
              'Chat history is unavailable',
              style: TextStyle(
                color: AppColors.heading,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Check the connection and ensure the live chat database update has been applied.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.body, height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.onOpenAttachment,
  });

  final ChatMessageRecord message;
  final bool isMine;
  final VoidCallback onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    final foreground = isMine ? Colors.white : AppColors.heading;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 310),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              decoration: BoxDecoration(
                color: isMine ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMine ? 18 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 18),
                ),
                boxShadow: isMine
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x10000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
              ),
              child: message.isFile
                  ? InkWell(
                      onTap: onOpenAttachment,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.insert_drive_file_outlined,
                            color: foreground,
                          ),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.attachmentName ?? 'Attachment',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: foreground,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (message.attachmentSizeBytes != null)
                                  Text(
                                    _fileSize(message.attachmentSizeBytes!),
                                    style: TextStyle(
                                      color: foreground.withValues(alpha: 0.75),
                                      fontSize: 10.5,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.open_in_new_rounded,
                            color: foreground,
                            size: 18,
                          ),
                        ],
                      ),
                    )
                  : Text(
                      message.messageText ?? '',
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTimestamp(message.sentAt),
                  style: const TextStyle(
                    color: Color(0xFF9AA3B3),
                    fontSize: 10.5,
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.readAt == null
                        ? Icons.done_rounded
                        : Icons.done_all_rounded,
                    color: message.readAt == null
                        ? const Color(0xFF9AA3B3)
                        : AppColors.primary,
                    size: 15,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final time = '$hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
    if (sameDay) return time;
    return '${local.day}/${local.month}/${local.year} · $time';
  }
}
