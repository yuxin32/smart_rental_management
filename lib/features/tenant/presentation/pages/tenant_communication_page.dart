import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../communication/data/announcement_service.dart';
import '../../../communication/data/chat_service.dart';
import '../widgets/tenant_ui.dart';
import 'tenant_chat_page.dart';

class TenantCommunicationPage extends StatelessWidget {
  const TenantCommunicationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TenantScreenTitle(title: 'Communication'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.primary,
                unselectedLabelColor: Color(0xFF98A0AF),
                labelStyle: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
                indicatorColor: AppColors.primary,
                indicatorWeight: 2,
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(text: 'Announcements'),
                  Tab(text: 'Chat'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TabBarView(
              children: [_AnnouncementsList(), const _ChatList()],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementsList extends StatefulWidget {
  @override
  State<_AnnouncementsList> createState() => _AnnouncementsListState();
}

class _AnnouncementsListState extends State<_AnnouncementsList> {
  List<AnnouncementRecord> _announcements = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final announcements =
          await AnnouncementService.fetchPublishedAnnouncements();
      if (mounted) setState(() => _announcements = announcements);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Announcements could not be loaded. Check the connection and database setup.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        children: [
          TenantCard(
            child: Column(
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  color: Color(0xFFE8953E),
                  size: 40,
                ),
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.body, height: 1.4),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loadAnnouncements,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_announcements.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAnnouncements,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: const [
            TenantCard(
              child: Column(
                children: [
                  Icon(
                    Icons.campaign_outlined,
                    color: Color(0xFFADB5C4),
                    size: 42,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'No published announcements',
                    style: TextStyle(
                      color: AppColors.heading,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Updates from the apartment administrator will appear here after they are published.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.body,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAnnouncements,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        itemCount: _announcements.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final announcement = _announcements[index];
          return TenantCard(
            onTap: () => _showAnnouncement(context, announcement),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TenantIconBox(
                  icon: Icons.campaign_outlined,
                  color: AppColors.primary,
                  backgroundColor: Color(0xFFF0F5FF),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              announcement.title,
                              style: const TextStyle(
                                color: AppColors.heading,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(
                              announcement.publishedAt ??
                                  announcement.createdAt,
                            ),
                            style: const TextStyle(
                              color: Color(0xFF98A0AF),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        announcement.content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.body,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Row(
                        children: [
                          Text(
                            'View details',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 5),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }

  static void _showAnnouncement(
    BuildContext context,
    AnnouncementRecord announcement,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 5, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              announcement.title,
              style: const TextStyle(
                color: AppColors.heading,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${announcement.audienceLabel} · ${_formatDate(announcement.publishedAt ?? announcement.createdAt)}',
              style: const TextStyle(color: Color(0xFF98A0AF), fontSize: 13),
            ),
            const SizedBox(height: 15),
            Text(
              announcement.content,
              style: const TextStyle(
                color: AppColors.body,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatList extends StatefulWidget {
  const _ChatList();

  @override
  State<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<_ChatList> {
  List<ChatConversationSummary> _conversations = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conversations = await ChatService.fetchConversations();
      if (mounted) setState(() => _conversations = conversations);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Chat records could not be loaded. Check the connection and database setup.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openConversation(ChatConversationSummary conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TenantChatPage(conversation: conversation),
      ),
    );
    await _loadConversations();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          TenantCard(
            child: Column(
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  color: Color(0xFFE8953E),
                  size: 40,
                ),
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.body, height: 1.4),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loadConversations,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_conversations.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadConversations,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: const [
            TenantCard(
              child: Column(
                children: [
                  Icon(
                    Icons.forum_outlined,
                    color: Color(0xFFADB5C4),
                    size: 42,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Administrator chat is not available yet',
                    style: TextStyle(
                      color: AppColors.heading,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Your conversation will appear automatically after the apartment administrator assigns your rental unit.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.body,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      itemCount: _conversations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final conversation = _conversations[index];
        return TenantCard(
          onTap: () => _openConversation(conversation),
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: const Color(0xFFE0E7FF),
                child: Text(
                  conversation.initials,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.otherPartyName,
                      style: const TextStyle(
                        color: AppColors.heading,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      conversation.lastMessagePreview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF98A0AF),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatConversationDate(conversation.latestMessageAt),
                    style: const TextStyle(
                      color: Color(0xFF98A0AF),
                      fontSize: 12,
                    ),
                  ),
                  if (conversation.unreadCount > 0) ...[
                    const SizedBox(height: 8),
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: AppColors.primary,
                      child: Text(
                        conversation.unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatConversationDate(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) {
      final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
      return '$hour:${local.minute.toString().padLeft(2, '0')} ${local.hour >= 12 ? 'PM' : 'AM'}';
    }
    return '${local.day}/${local.month}/${local.year}';
  }
}
