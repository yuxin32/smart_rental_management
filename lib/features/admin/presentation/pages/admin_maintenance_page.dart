import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../maintenance/data/maintenance_service.dart';
import '../widgets/admin_ui.dart';

class AdminMaintenancePage extends StatefulWidget {
  const AdminMaintenancePage({super.key});

  @override
  State<AdminMaintenancePage> createState() => _AdminMaintenancePageState();
}

class _AdminMaintenancePageState extends State<AdminMaintenancePage> {
  String _filter = 'All';
  late Future<List<MaintenanceRequestRecord>> _requests;

  @override
  void initState() {
    super.initState();
    _requests = MaintenanceService.fetchAdminRequests();
  }

  Future<void> _refresh() async {
    final future = MaintenanceService.fetchAdminRequests();
    setState(() => _requests = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: Column(
        children: [
          const AdminScreenTitle(
            title: 'Maintenance Requests',
            subtitle: 'Review tenant reported problems and progress',
          ),
          SizedBox(
            height: 42,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              children: [
                for (final filter in [
                  'All',
                  'Submitted',
                  'In progress',
                  'Resolved',
                  'Rejected',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filter),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                      selectedColor: const Color(0xFFE0E7FF),
                      backgroundColor: Colors.white,
                      side: BorderSide.none,
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<MaintenanceRequestRecord>>(
              future: _requests,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Maintenance requests could not be loaded.'),
                        TextButton(
                          onPressed: _refresh,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final all = snapshot.data ?? const [];
                final filtered = all
                    .where(
                      (request) =>
                          _filter == 'All' ||
                          _statusLabel(request.status) == _filter,
                    )
                    .toList();
                if (filtered.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      children: const [
                        SizedBox(height: 100),
                        Center(child: Text('No requests in this list yet.')),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _RequestCard(
                      request: filtered[index],
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AdminMaintenanceDetailsPage(
                              request: filtered[index],
                            ),
                          ),
                        );
                        if (mounted) _refresh();
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onTap});
  final MaintenanceRequestRecord request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(request.status);
    return AdminCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AdminIconBox(
                icon: Icons.build_outlined,
                color: Color(0xFF4EA98A),
                backgroundColor: Color(0xFFE4F6EF),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.heading,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${request.tenantName} · ${request.unitLabel}',
                      style: const TextStyle(
                        color: AppColors.body,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA4B3)),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              AdminStatusPill(
                label: _statusLabel(request.status),
                foregroundColor: color,
                backgroundColor: color.withAlpha(24),
              ),
              const Spacer(),
              Text(
                _formatDate(request.submittedAt),
                style: const TextStyle(color: AppColors.body, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AdminMaintenanceDetailsPage extends StatefulWidget {
  const AdminMaintenanceDetailsPage({required this.request, super.key});
  final MaintenanceRequestRecord request;

  @override
  State<AdminMaintenanceDetailsPage> createState() =>
      _AdminMaintenanceDetailsPageState();
}

class _AdminMaintenanceDetailsPageState
    extends State<AdminMaintenanceDetailsPage> {
  late String _status;
  late String _savedStatus;
  final _remarks = TextEditingController();
  late Future<List<MaintenanceUpdateRecord>> _updates;
  bool _saving = false;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _status = widget.request.status;
    _savedStatus = widget.request.status;
    _updates = MaintenanceService.fetchUpdates(widget.request.id);
    final path = widget.request.imagePath;
    if (path != null)
      MaintenanceService.createSignedImageUrl(path).then((url) {
        if (mounted) setState(() => _imageUrl = url);
      });
  }

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await MaintenanceService.updateStatus(
        maintenanceId: widget.request.id,
        newStatus: _status,
        remarks: _remarks.text,
      );
      if (!mounted) return;
      setState(() {
        _savedStatus = _status;
        _remarks.clear();
        _updates = MaintenanceService.fetchUpdates(widget.request.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status and tenant update saved.')),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update failed: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: const AdminBackAppBar(title: 'Maintenance Request'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'MR-${request.id.substring(0, 8).toUpperCase()}',
                        style: const TextStyle(
                          color: AppColors.body,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AdminStatusPill(
                      label: _statusLabel(_status),
                      foregroundColor: _statusColor(_status),
                      backgroundColor: _statusColor(_status).withAlpha(24),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  request.category,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  request.description,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                if (request.location?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Location: ${request.location}',
                    style: const TextStyle(color: AppColors.body),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  '${request.tenantName} · ${request.unitLabel}',
                  style: const TextStyle(color: AppColors.body),
                ),
                Text(
                  'Submitted ${_formatDate(request.submittedAt)}',
                  style: const TextStyle(color: AppColors.body, fontSize: 12),
                ),
                if (_imageUrl != null) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      _imageUrl!,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Update request',
            style: TextStyle(
              color: AppColors.heading,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          AdminCard(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  items: const [
                    DropdownMenuItem(
                      value: 'submitted',
                      enabled: false,
                      child: Text('Submitted'),
                    ),
                    DropdownMenuItem(
                      value: 'in_progress',
                      child: Text('In progress'),
                    ),
                    DropdownMenuItem(
                      value: 'resolved',
                      child: Text('Resolved'),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rejected'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _remarks,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Update for tenant (optional)',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving || _status == _savedStatus
                        ? null
                        : _save,
                    child: Text(_saving ? 'Saving…' : 'Save update'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Request history',
            style: TextStyle(
              color: AppColors.heading,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<MaintenanceUpdateRecord>>(
            future: _updates,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done)
                return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError)
                return Text('History unavailable: ${snapshot.error}');
              final items = snapshot.data ?? const [];
              if (items.isEmpty)
                return const Text('No status updates have been recorded.');
              return Column(
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AdminCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.oldStatus == null ? 'Request submitted' : _statusLabel(item.oldStatus!)} → ${_statusLabel(item.newStatus)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item.adminName} · ${_formatDate(item.createdAt)}',
                              style: const TextStyle(
                                color: AppColors.body,
                                fontSize: 12,
                              ),
                            ),
                            if (item.remarks?.isNotEmpty ?? false)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  item.remarks!,
                                  style: const TextStyle(color: AppColors.body),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
  'submitted' => 'Submitted',
  // Display legacy values from records created before the simplified workflow.
  'under_review' => 'Submitted',
  'in_progress' => 'In progress',
  'resolved' => 'Resolved',
  'rejected' => 'Rejected',
  _ => status,
};

Color _statusColor(String status) => switch (status) {
  'resolved' || 'closed' => AppColors.success,
  'in_progress' => const Color(0xFFE8953E),
  'rejected' => const Color(0xFFD9534F),
  _ => AppColors.primary,
};

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
