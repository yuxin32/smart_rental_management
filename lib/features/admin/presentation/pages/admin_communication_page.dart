import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../communication/data/announcement_service.dart';
import '../../../communication/data/chat_service.dart';
import '../../../communication/presentation/widgets/chat_conversation_view.dart';
import '../widgets/admin_ui.dart';

class AdminCommunicationPage extends StatefulWidget {
  const AdminCommunicationPage({super.key});

  @override
  State<AdminCommunicationPage> createState() => _AdminCommunicationPageState();
}

class _AdminCommunicationPageState extends State<AdminCommunicationPage> {
  int _selectedView = 0;
  int _announcementRefreshToken = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: Column(
        children: [
          AdminScreenTitle(
            title: 'Communication',
            subtitle: 'Chat with tenants and publish announcements',
            action: _selectedView == 1
                ? IconButton(
                    onPressed: _openAnnouncementComposer,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFE6EBFF),
                      foregroundColor: AppColors.primary,
                    ),
                    icon: const Icon(Icons.add_rounded),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _ViewChip(
                    label: 'Tenant chats',
                    index: 0,
                    selected: _selectedView,
                    onTap: _selectView,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ViewChip(
                    label: 'Announcements',
                    index: 1,
                    selected: _selectedView,
                    onTap: _selectView,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _selectedView == 0
                ? const _ConversationList()
                : _AnnouncementList(refreshToken: _announcementRefreshToken),
          ),
        ],
      ),
    );
  }

  void _selectView(int index) => setState(() => _selectedView = index);

  Future<void> _openAnnouncementComposer() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AdminAnnouncementPage()),
    );
    if (!mounted || result == null) return;

    setState(() => _announcementRefreshToken++);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result == 'published'
                ? 'Announcement published successfully.'
                : 'Announcement saved as draft.',
          ),
        ),
      );
  }
}

class _ViewChip extends StatelessWidget {
  const _ViewChip({
    required this.label,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int index;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = index == selected;
    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE0E7FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.body,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ConversationList extends StatefulWidget {
  const _ConversationList();

  @override
  State<_ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<_ConversationList> {
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
      await ChatService.performAdministratorRetentionCleanup();
      final conversations = await ChatService.fetchConversations();
      if (mounted) setState(() => _conversations = conversations);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Tenant conversations could not be loaded. Check the connection and database setup.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openConversation(ChatConversationSummary conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminConversationPage(conversation: conversation),
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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          AdminCard(
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: const [
            AdminCard(
              child: Column(
                children: [
                  Icon(
                    Icons.forum_outlined,
                    color: Color(0xFFADB5C4),
                    size: 42,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'No tenant conversations yet',
                    style: TextStyle(
                      color: AppColors.heading,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'A database-backed chat is created automatically when a rental unit is assigned to a tenant.',
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
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      itemCount: _conversations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final conversation = _conversations[index];
        return AdminCard(
          padding: const EdgeInsets.all(15),
          onTap: () => _openConversation(conversation),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFE0E7FF),
                child: Text(
                  conversation.initials,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.otherPartyName,
                            style: const TextStyle(
                              color: AppColors.heading,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          _formatConversationDate(conversation.latestMessageAt),
                          style: const TextStyle(
                            color: AppColors.body,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      conversation.unitLabel,
                      style: const TextStyle(
                        color: AppColors.body,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      conversation.lastMessagePreview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.body,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (conversation.unreadCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${conversation.unreadCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
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

class _AnnouncementList extends StatefulWidget {
  const _AnnouncementList({required this.refreshToken});

  final int refreshToken;

  @override
  State<_AnnouncementList> createState() => _AnnouncementListState();
}

class _AnnouncementListState extends State<_AnnouncementList> {
  List<AnnouncementRecord> _announcements = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  @override
  void didUpdateWidget(covariant _AnnouncementList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadAnnouncements();
    }
  }

  Future<void> _loadAnnouncements() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final announcements = await AnnouncementService.fetchAdminAnnouncements();
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

  Future<void> _openAnnouncement(AnnouncementRecord announcement) async {
    if (announcement.status != 'draft') {
      _showAnnouncement(context, announcement);
      return;
    }

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => AdminAnnouncementPage(draft: announcement),
      ),
    );
    if (!mounted || result == null) return;

    await _loadAnnouncements();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result == 'published'
                ? 'Draft published successfully.'
                : 'Draft changes saved.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          AdminCard(
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: const [
            AdminCard(
              child: Column(
                children: [
                  Icon(
                    Icons.campaign_outlined,
                    color: Color(0xFFADB5C4),
                    size: 42,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'No announcements yet',
                    style: TextStyle(
                      color: AppColors.heading,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Create an announcement and either save it as a draft or publish it to tenants.',
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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        itemCount: _announcements.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final announcement = _announcements[index];
          final iconColor = announcement.isPublished
              ? AppColors.success
              : const Color(0xFFEF9B58);
          final iconBackground = announcement.isPublished
              ? const Color(0xFFE2F7E9)
              : const Color(0xFFFFF0D7);
          final status = _statusLabel(announcement.status);

          return AdminCard(
            onTap: () => _openAnnouncement(announcement),
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                AdminIconBox(
                  icon: Icons.campaign_outlined,
                  color: iconColor,
                  backgroundColor: iconBackground,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        announcement.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.heading,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${announcement.audienceLabel} · ${_formatDate(announcement.publishedAt ?? announcement.createdAt)}',
                        style: const TextStyle(
                          color: AppColors.body,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AdminStatusPill(
                  label: status,
                  foregroundColor: adminStatusColor(status),
                  backgroundColor: adminStatusBackground(status),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _statusLabel(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
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
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 5, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AdminStatusPill(
                    label: _statusLabel(announcement.status),
                    foregroundColor: adminStatusColor(announcement.status),
                    backgroundColor: adminStatusBackground(announcement.status),
                  ),
                ],
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
      ),
    );
  }
}

class AdminConversationPage extends StatelessWidget {
  const AdminConversationPage({required this.conversation, super.key});

  final ChatConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AdminBackAppBar(
        title: conversation.otherPartyName,
        subtitle: conversation.unitLabel,
      ),
      body: ChatConversationView(conversation: conversation),
    );
  }
}

class AdminAnnouncementPage extends StatefulWidget {
  const AdminAnnouncementPage({this.draft, super.key});

  final AnnouncementRecord? draft;

  @override
  State<AdminAnnouncementPage> createState() => _AdminAnnouncementPageState();
}

class _AdminAnnouncementPageState extends State<AdminAnnouncementPage> {
  static const _audienceOptions = <String>[
    'All tenants',
    'Block A tenants',
    'Block B tenants',
  ];

  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late String _audience;
  bool _saving = false;

  bool get _editingDraft => widget.draft != null;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    _titleController = TextEditingController(text: draft?.title ?? '');
    _contentController = TextEditingController(text: draft?.content ?? '');
    _audience = _audienceOptions.contains(draft?.audienceLabel)
        ? draft!.audienceLabel
        : 'All tenants';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveAnnouncement({required bool publish}) async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete the title and message.')),
      );
      return;
    }
    if (title.length > 150 || content.length > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Use no more than 150 title characters and 5,000 message characters.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final draft = widget.draft;
      if (draft == null) {
        await AnnouncementService.createAnnouncement(
          title: title,
          content: content,
          audienceLabel: _audience,
          publish: publish,
        );
      } else {
        await AnnouncementService.updateDraftAnnouncement(
          announcementId: draft.announcementId,
          title: title,
          content: content,
          audienceLabel: _audience,
          publish: publish,
        );
      }
      if (mounted) Navigator.of(context).pop(publish ? 'published' : 'draft');
    } catch (error) {
      if (!mounted) return;
      final raw = error.toString();
      final message =
          raw.contains('create_announcement') ||
              raw.contains('update_draft_announcement') ||
              raw.contains('audience_label')
          ? 'The announcement database update has not been applied yet.'
          : 'The announcement could not be saved. Please try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AdminBackAppBar(
        title: _editingDraft ? 'Edit Draft' : 'Create Announcement',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Text(
            _editingDraft
                ? 'Review and update this draft'
                : 'Share an update with tenants',
            style: const TextStyle(
              color: AppColors.heading,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _editingDraft
                ? 'Save your changes as a draft or publish the announcement when it is ready.'
                : 'Published announcements will be retained as communication records.',
            style: const TextStyle(color: AppColors.body, fontSize: 13),
          ),
          const SizedBox(height: 18),
          AdminCard(
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Announcement title',
                    prefixIcon: Icon(Icons.title_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _audience,
                  items: _audienceOptions
                      .map(
                        (audience) => DropdownMenuItem(
                          value: audience,
                          child: Text(audience),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _audience = value);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Audience',
                    prefixIcon: Icon(Icons.groups_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _contentController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _saveAnnouncement(publish: false),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save as draft'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _saveAnnouncement(publish: true),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.campaign_outlined),
                  label: const Text('Publish'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
