import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/tenant_lifecycle_service.dart';
import '../widgets/admin_ui.dart';

class AdminAuditLogPage extends StatefulWidget {
  const AdminAuditLogPage({
    required this.registrationId,
    required this.tenantName,
    super.key,
  });

  final String registrationId;
  final String tenantName;

  @override
  State<AdminAuditLogPage> createState() => _AdminAuditLogPageState();
}

class _AdminAuditLogPageState extends State<AdminAuditLogPage> {
  List<AuditLogRecord> _logs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final logs = await TenantLifecycleService.fetchAuditLogs(
        registrationId: widget.registrationId,
      );
      if (!mounted) return;
      setState(() => _logs = logs);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'The audit log could not be loaded. Confirm that the audit migration has been applied.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AdminBackAppBar(
        title: 'Tenant Audit History',
        subtitle: 'Onboarding activity for ${widget.tenantName}',
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          AdminCard(
            color: const Color(0xFFFFF5E8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off_outlined, color: Color(0xFFE8953E)),
                const SizedBox(height: 10),
                const Text(
                  'Audit history is unavailable',
                  style: TextStyle(
                    color: AppColors.heading,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.body,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _loadLogs,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_logs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadLogs,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            AdminCard(
              child: Column(
                children: [
                  const AdminIconBox(
                    icon: Icons.fact_check_outlined,
                    color: AppColors.primary,
                    backgroundColor: Color(0xFFE6EBFF),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No onboarding events yet',
                    style: TextStyle(
                      color: AppColors.heading,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tenant information, unit assignments, and invitation activity will appear here as the workflow is completed.',
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
      onRefresh: _loadLogs,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        itemCount: _logs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _AuditLogCard(log: _logs[index]),
      ),
    );
  }
}

class _AuditLogCard extends StatelessWidget {
  const _AuditLogCard({required this.log});

  final AuditLogRecord log;

  @override
  Widget build(BuildContext context) {
    final isInvitation = log.actionType.contains('INVITATION');
    final icon = switch (log.actionType) {
      'TENANT_INFORMATION_ADDED' => Icons.person_add_alt_1_rounded,
      'TENANT_UNIT_ASSIGNED' => Icons.meeting_room_outlined,
      'TENANT_INVITATION_SENT' => Icons.mark_email_read_outlined,
      'TENANT_INVITATION_RESENT' => Icons.forward_to_inbox_outlined,
      _ => Icons.history_rounded,
    };
    final color = isInvitation ? const Color(0xFF0B8A76) : AppColors.primary;
    final background = isInvitation
        ? const Color(0xFFE3F7F2)
        : const Color(0xFFE6EBFF);

    return AdminCard(
      padding: const EdgeInsets.all(15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminIconBox(icon: icon, color: color, backgroundColor: background),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.actionLabel,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  log.detailLabel,
                  style: const TextStyle(
                    color: AppColors.body,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatTimestamp(log.eventTimestamp),
                  style: const TextStyle(
                    color: Color(0xFF7A8495),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          AdminStatusPill(
            label: log.outcome == 'success' ? 'Success' : log.outcome,
            foregroundColor: log.outcome == 'success'
                ? const Color(0xFF0B8A76)
                : const Color(0xFFB34A48),
            backgroundColor: log.outcome == 'success'
                ? const Color(0xFFE3F7F2)
                : const Color(0xFFFFE8E8),
            dot: false,
          ),
        ],
      ),
    );
  }

  static String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year at $hour:$minute';
  }
}
