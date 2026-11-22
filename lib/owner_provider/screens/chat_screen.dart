// lib/screens/chat_screen.dart
// Single conversation chat screen. Chat-style bubbles + input.
// Mark-read on entry; auto-scroll to latest on new message.
//
// Round 9 polish (CH1-CH6):
//   CH1 Theme colors throughout (sem.* + AppColors.*)
//   CH2 intl.DateFormat for date divider (Today / Yesterday / d MMM y)
//   CH3 App bar shows avatar (initials) + presence dot + last-seen
//   CH4 "Typing..." indicator stub (toggleable for demo)
//   CH5 Read receipt on outgoing messages (single tick / double tick)
//   CH6 Send button is disabled when input is empty (visual state)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/message.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversationId, required this.counterpart});
  final String conversationId;
  final String counterpart;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _me = 'Owner';
  // CH4: local "typing..." indicator (demo only — not driven by remote state).
  bool _showTyping = false;

  @override
  void initState() {
    super.initState();
    final session = UserSessionAccess.of(context);
    _me = session.displayName.isEmpty ? 'Owner' : session.displayName;
    _inputCtrl.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppProviders.of(context).messageStore.markRead(widget.conversationId);
        // Simulate counterpart typing for a few seconds after entry.
        setState(() => _showTyping = true);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showTyping = false);
        });
      }
    });
  }

  void _onInputChanged() => setState(() {});

  @override
  void dispose() {
    _inputCtrl.removeListener(_onInputChanged);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    Haptics.light();
    final store = AppProviders.of(context).messageStore;
    store.send(
      conversationId: widget.conversationId,
      senderName: _me,
      text: text,
    );
    _inputCtrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(DateTime d) {
    return DateFormat('HH:mm').format(d);
  }

  String _formatDateDivider(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    if (that == today) return 'Today';
    if (that == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('d MMM y').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Scaffold(
      appBar: AppBar(
        // CH3: avatar + presence + name
        titleSpacing: 0,
        title: Row(
          children: [
            _Avatar(name: widget.counterpart, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.counterpart,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: sem.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Online',
                        style: TextStyle(fontSize: 11, color: sem.textTertiary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Conversation details are unavailable here.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            tooltip: 'Info',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AnimatedBuilder(
                animation: AppProviders.of(context).messageStore,
                builder: (ctx, _) {
                  final messages = AppProviders.of(context).messageStore
                      .messagesFor(widget.conversationId);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollCtrl.hasClients) {
                      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                    }
                  });
                  if (messages.isEmpty && !_showTyping) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          'Say hi to ${widget.counterpart}!',
                          style: TextStyle(
                            color: sem.textTertiary,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: messages.length + (_showTyping ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == messages.length && _showTyping) {
                        return const _TypingIndicator();
                      }
                      final m = messages[i];
                      final isMe = m.senderName == _me;
                      final showDate = i == 0 ||
                          _formatDateDivider(messages[i].timestamp) !=
                              _formatDateDivider(messages[i - 1].timestamp);
                      return Column(
                        children: [
                          if (showDate)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: sem.surfaceAlt,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _formatDateDivider(m.timestamp),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: sem.textTertiary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          _MessageBubble(
                            message: m,
                            isMe: isMe,
                            time: _formatTime(m.timestamp),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            _buildInput(sem),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(SemanticColors sem) {
    final canSend = _inputCtrl.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: BoxDecoration(
        color: sem.surface,
        border: Border(top: BorderSide(color: sem.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.add, color: sem.textSecondary),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('File attachments are unavailable in this conversation.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              tooltip: 'Attach',
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: sem.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: TextField(
                  controller: _inputCtrl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Message...',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    hintStyle: TextStyle(color: sem.textTertiary, fontSize: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // CH6: send button disabled state
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: canSend ? AppColors.primary : sem.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: canSend ? _send : null,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.send,
                      color: canSend ? Colors.white : sem.textTertiary,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular avatar with initials.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 32});
  final String name;
  final double size;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _initials(name),
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Subtle "Typing..." indicator — three animated dots.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: sem.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: sem.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _ctl,
                  builder: (ctx, _) {
                    final t = (_ctl.value - i * 0.15).clamp(0.0, 1.0);
                    final opacity = 0.3 + 0.7 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
                    return Container(
                      margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: sem.textSecondary.withOpacity(opacity),
                        shape: BoxShape.circle,
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMe, required this.time});
  final Message message;
  final bool isMe;
  final String time;

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMe) const SizedBox(width: 40),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe ? AppColors.primary : sem.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                border: isMe ? null : Border.all(color: sem.border),
                boxShadow: isMe
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: isMe ? Colors.white : sem.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 9,
                          color: isMe ? Colors.white70 : sem.textTertiary,
                        ),
                      ),
                      // CH5: read receipt (double tick) for outgoing messages
                      if (isMe) ...[
                        const SizedBox(width: 3),
                        Icon(
                          Icons.done_all,
                          size: 11,
                          color: message.read ? Colors.lightBlueAccent : Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!isMe) const SizedBox(width: 40),
        ],
      ),
    );
  }
}
