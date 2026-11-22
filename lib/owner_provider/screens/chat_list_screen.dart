// lib/screens/chat_list_screen.dart
// Lists all conversations for the current user.
// Tap a conversation → opens the chat screen.
//
// Round 9 polish (CL1-CL6):
//   CL1 Theme colors throughout (sem.* + AppColors.*)
//   CL2 intl.DateFormat for time-ago labels
//   CL3 Search bar to filter conversations by counterpart name
//   CL4 "Unread only" filter chip in app bar
//   CL5 "Pinned" conversations float to top (first 2, demo only)
//   CL6 Total unread badge in app bar
//
// Round 14 fix: wrap the body in AnimatedBuilder so the list rebuilds
// when a new message is sent (was reading store.conversations directly).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/message.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import 'chat_screen.dart';
import '../services/backend/conversation_binding.dart';
import '../widgets/connected_state_panel.dart';
import '../widgets/snapshot_refresh_notice.dart';
import '../widgets/message_unread_scope.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen(
      {super.key,
      this.binding,
      this.onOpenConversation,
      this.isProvider = false})
      : assert(binding == null || onOpenConversation != null);
  final ConversationBinding? binding;
  final Future<void> Function(String bookingId)? onOpenConversation;
  final bool isProvider;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _unreadOnly = false;
  Timer? _searchTimer;
  bool _opening = false;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final binding = widget.binding;
    if (binding != null) {
      return AnimatedBuilder(
          animation: binding,
          builder: (context, _) {
            final rows = binding.feed.items
                .map((c) => c.present(binding.userId))
                .toList();
            return _buildScaffold(
                ctx: context,
                me: binding.userId,
                isProvider: widget.isProvider,
                all: rows,
                filtered: rows,
                pinnedTop: const [],
                rest: rows,
                totalUnread: MessageUnreadScope.maybeOf(context)?.count ??
                    binding.unreadTotal ??
                    0,
                connectedBody: _connectedList(binding));
          });
    }
    final session = UserSessionAccess.of(context);
    final me = session.displayName.isEmpty ? 'Owner' : session.displayName;
    final isProvider = session.role == UserRole.provider;
    // Round 14 fix: wrap the body in AnimatedBuilder so the list rebuilds
    // when a new message is sent or read state changes.
    final store = AppProviders.of(context).messageStore;
    return AnimatedBuilder(
      animation: store,
      builder: (ctx, _) {
        final all = store.conversations
            .where((c) => c.participantA == me || c.participantB == me)
            .toList();

        // Apply search + unread filters
        final filtered = all.where((c) {
          if (_unreadOnly && c.unreadCount == 0) return false;
          if (_searchQuery.isEmpty) return true;
          final counterpart =
              c.participantA == me ? c.participantB : c.participantA;
          return counterpart.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        // CL5: Pinned conversations float to top (first 2 by lastTimestamp).
        // (Demo only — no real pin storage; uses mock logic.)
        final pinned = [...filtered]
          ..sort((a, b) => b.lastTimestamp.compareTo(a.lastTimestamp));
        final pinnedTop = pinned.take(2).toList();
        final rest = pinned.skip(2).toList();

        final totalUnread = all.fold<int>(0, (a, c) => a + c.unreadCount);

        return _buildScaffold(
          ctx: ctx,
          me: me,
          isProvider: isProvider,
          all: all,
          filtered: filtered,
          pinnedTop: pinnedTop,
          rest: rest,
          totalUnread: totalUnread,
        );
      },
    );
  }

  Widget _buildScaffold({
    required BuildContext ctx,
    required String me,
    required bool isProvider,
    required List<Conversation> all,
    required List<Conversation> filtered,
    required List<Conversation> pinnedTop,
    required List<Conversation> rest,
    required int totalUnread,
    Widget? connectedBody,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Flexible(child: Text('Messages',maxLines:1,overflow:TextOverflow.ellipsis)),
            if (totalUnread > 0) ...[
              const SizedBox(width: 8),
              _UnreadBadge(count: totalUnread),
            ],
          ],
        ),
        actions: [
          if (widget.binding == null || widget.binding!.loadUnread != null)
            // CL4: Unread-only filter chip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: FilterChip(
                selected: _unreadOnly,
                label: const Text('Unread'),
                avatar: Icon(
                  _unreadOnly ? Icons.mark_email_read : Icons.mark_email_unread,
                  size: 16,
                  color: _unreadOnly ? Colors.white : AppColors.primary,
                ),
                selectedColor: AppColors.primary,
                showCheckmark: false,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _unreadOnly ? Colors.white : AppColors.primary,
                ),
                onSelected: (v) {
                  widget.binding?.setUnreadOnly(v);
                  setState(() => _unreadOnly = v);
                },
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // CL3: Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              maxLength: widget.binding == null ? null : 80,
              inputFormatters: widget.binding == null
                  ? null
                  : [
                      TextInputFormatter.withFunction((oldValue, newValue) =>
                          newValue.text.runes.length <= 80
                              ? newValue
                              : oldValue),
                    ],
              onChanged: _search,
              decoration: InputDecoration(
                hintText: widget.binding == null
                    ? 'Search conversations...'
                    : 'Search name, unit or service…',
                counterText: '',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: SemanticColors.of(context).textTertiary,
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 6),
                  child: Icon(
                    Icons.search,
                    size: 18,
                    color: SemanticColors.of(context).textSecondary,
                  ),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          _search('');
                        },
                      ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: connectedBody ??
                (filtered.isEmpty
                    ? _EmptyChat(
                        isFiltered: _searchQuery.isNotEmpty || _unreadOnly,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: pinnedTop.length + rest.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 76),
                        itemBuilder: (ctx, i) {
                          final isPinned = i < pinnedTop.length;
                          final c = isPinned
                              ? pinnedTop[i]
                              : rest[i - pinnedTop.length];
                          final counterpart = c.participantA == me
                              ? c.participantB
                              : c.participantA;
                          return _ConversationTile(
                            conversation: c,
                            counterpart: counterpart,
                            isProvider: isProvider,
                            isPinned: isPinned,
                            onTap: () {
                              Haptics.selection();
                              Navigator.of(ctx).push(MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  conversationId: c.id,
                                  counterpart: counterpart,
                                ),
                              ));
                            },
                          );
                        },
                      )),
          ),
        ],
      ),
    );
  }

  void _search(String query) {
    _searchTimer?.cancel();
    _searchTimer = null;
    setState(() => _searchQuery = query);
    if (widget.binding == null) return;
    if (query.trim().isEmpty) {
      widget.binding!.setSearch('');
    } else {
      _searchTimer = Timer(const Duration(milliseconds: 350), () {
        _searchTimer = null;
        if (mounted) {
          widget.binding!.setSearch(query);
          setState(() {});
        }
      });
    }
  }

  Future<void> _open(String id) async {
    if (_opening || widget.binding!.feed.sessionEnded) return;
    setState(() => _opening = true);
    try {
      await widget.onOpenConversation!(id);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Could not open this conversation. Please try again.')));
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        final feed = widget.binding!.feed;
        if (feed.active && !feed.loading) await feed.refresh();
      }
    }
  }

  Widget _connectedList(ConversationBinding binding) {
    final feed = binding.feed;
    return LayoutBuilder(builder: (context, size) {
      final rows = feed.items;
      Widget? state;
      if (feed.sessionEnded) {
        state = const ConnectedStatePanel(
            state: ConnectedViewState.error,
            title: 'Session ended',
            message: 'Sign in again to view your conversations.');
      } else if (_searchTimer != null || (feed.loading && !feed.hasSnapshot)) {
        state = const ConnectedStatePanel(
            state: ConnectedViewState.loading,
            title: 'Loading conversations',
            message: 'Getting your booking conversations.');
      } else if (feed.error != null) {
        state = ConnectedStatePanel(
            state: ConnectedViewState.error,
            title: 'Could not load conversations',
            message: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: feed.refresh);
      } else if (rows.isEmpty) {
        state = SingleChildScrollView(
            child: _EmptyChat(
                isFiltered: binding.search.isNotEmpty || binding.unreadOnly,
                connected: true));
      }
      return RefreshIndicator(
          onRefresh: feed.refresh,
          child: ListView(
              key: ValueKey(
                  'conversations:${binding.search}:${binding.unreadOnly}'),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SnapshotRefreshNotice(
                    refreshing: feed.refreshing,
                    failed: feed.refreshError != null,
                    onRetry: feed.refresh),
                if (state != null)
                  SizedBox(height: size.maxHeight, child: state)
                else ...[
                  for (final row in rows) ...[
                    _ConversationTile(
                        conversation: row.present(binding.userId),
                        counterpart: row.counterpart,
                        isProvider: widget.isProvider,
                        isPinned: false,
                        onTap: () => _open(row.bookingId)),
                    const Divider(height: 1, indent: 76),
                  ],
                  if (feed.moreError != null)
                    const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                            'Could not show more conversations. You can still view the conversations already shown.')),
                  if (feed.hasMore)
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: OutlinedButton(
                            onPressed: feed.loadingMore ? null : feed.loadMore,
                            child: Text(feed.loadingMore
                                ? 'Loading…'
                                : feed.moreError != null
                                    ? 'Retry loading more'
                                    : 'Load more conversations'))),
                ],
              ]));
    });
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.counterpart,
    required this.isProvider,
    required this.isPinned,
    required this.onTap,
  });
  final Conversation conversation;
  final String counterpart;
  final bool isProvider;
  final bool isPinned;
  final VoidCallback onTap;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (name.trim().isEmpty) return '?';
    if (parts.length == 1) return parts[0].characters.first.toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  String _formatTime(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    // CL2: intl for older messages
    return DateFormat('d MMM').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final hasUnread = conversation.unreadCount > 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isProvider
                    ? AppColors.primarySurface
                    : AppColors.secondarySurface,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _initials(counterpart),
                  style: TextStyle(
                    color: isProvider
                        ? AppColors.primary
                        : AppColors.secondaryDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            // CL5: Pinned indicator
                            if (isPinned) ...[
                              Icon(
                                Icons.push_pin,
                                size: 12,
                                color: sem.textTertiary,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                counterpart,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: hasUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: sem.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatTime(conversation.lastTimestamp),
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              hasUnread ? AppColors.primary : sem.textTertiary,
                          fontWeight:
                              hasUnread ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conversation.property,
                    style: TextStyle(fontSize: 11, color: sem.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.lastMessage.isEmpty
                              ? 'No messages yet'
                              : conversation.lastMessage,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                hasUnread ? sem.textPrimary : sem.textSecondary,
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${conversation.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({this.isFiltered = false, this.connected = false});
  final bool isFiltered;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isFiltered
                    ? Icons.filter_alt_off_outlined
                    : Icons.chat_bubble_outline,
                size: 32,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isFiltered ? 'No matches' : 'No conversations',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: sem.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isFiltered
                  ? 'Try a different search or filter.'
                  : connected
                      ? 'Conversations appear once a booking is accepted. Previous chats remain available after the booking ends.'
                      : 'Open a booking and tap "Message" to start a chat.',
              style: TextStyle(fontSize: 13, color: sem.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
