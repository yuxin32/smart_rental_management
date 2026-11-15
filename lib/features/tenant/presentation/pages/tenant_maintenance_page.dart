import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../maintenance/data/maintenance_service.dart';
import '../widgets/tenant_ui.dart';
import 'tenant_new_request_page.dart';

class TenantMaintenancePage extends StatefulWidget {
  const TenantMaintenancePage({super.key});

  @override
  TenantMaintenancePageState createState() => TenantMaintenancePageState();
}

class TenantMaintenancePageState extends State<TenantMaintenancePage> {
  String _filter = 'All';
  late Future<List<MaintenanceRequestRecord>> _requests;

  @override
  void initState() {
    super.initState();
    _requests = MaintenanceService.fetchTenantRequests();
  }

  Future<void> refresh() async {
    final future = MaintenanceService.fetchTenantRequests();
    setState(() => _requests = future);
    await future;
  }

  Future<void> _newRequest() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TenantNewRequestPage()),
    );
    if (submitted == true && mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: TenantScreenTitle(title: 'Maintenance'),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'My Requests',
                        style: TextStyle(
                          color: AppColors.heading,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: refresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final filter in const [
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
                TenantCard(
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  color: const Color(0xFFFBFCFF),
                  child: InkWell(
                    onTap: _newRequest,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_circle_outline_rounded,
                          color: AppColors.primary,
                          size: 27,
                        ),
                        SizedBox(width: 9),
                        Text(
                          'New request',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FutureBuilder<List<MaintenanceRequestRecord>>(
                  future: _requests,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done)
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    if (snapshot.hasError)
                      return TenantCard(
                        child: Column(
                          children: [
                            const Text('Your requests could not be loaded.'),
                            TextButton(
                              onPressed: refresh,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      );
                    final allRequests = snapshot.data ?? const [];
                    final requests = allRequests.where((request) {
                      return _filter == 'All' ||
                          _statusLabel(request.status) == _filter;
                    }).toList();
                    if (requests.isEmpty)
                      return TenantCard(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              allRequests.isEmpty && _filter == 'All'
                                  ? 'You have not submitted a maintenance request yet.'
                                  : 'No requests in this status yet.',
                              style: const TextStyle(color: AppColors.body),
                            ),
                          ),
                        ),
                      );
                    return Column(
                      children: [
                        for (var i = 0; i < requests.length; i++) ...[
                          _TenantRequestCard(request: requests[i]),
                          if (i < requests.length - 1)
                            const SizedBox(height: 10),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _statusLabel(String status) => switch (status) {
  'submitted' || 'under_review' => 'Submitted',
  'in_progress' => 'In progress',
  'resolved' || 'closed' => 'Resolved',
  'rejected' => 'Rejected',
  _ => status,
};

class _TenantRequestCard extends StatelessWidget {
  const _TenantRequestCard({required this.request});
  final MaintenanceRequestRecord request;

  @override
  Widget build(BuildContext context) {
    final color = switch (request.status) {
      'resolved' || 'closed' => AppColors.success,
      'in_progress' => const Color(0xFFE8953E),
      'rejected' => const Color(0xFFD9534F),
      _ => AppColors.primary,
    };
    final label = _statusLabel(request.status);
    return TenantCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TenantIconBox(
                icon: Icons.build_outlined,
                color: AppColors.primary,
                backgroundColor: Color(0xFFF0F5FF),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TenantStatusPill(
                      label: label,
                      foregroundColor: color,
                      backgroundColor: color.withAlpha(24),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      request.title,
                      style: const TextStyle(
                        color: AppColors.heading,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${request.category} · ${request.unitLabel}',
                      style: const TextStyle(
                        color: AppColors.body,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            request.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.body,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Submitted ${_shortDate(request.submittedAt)}',
            style: const TextStyle(color: Color(0xFF98A0AF), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

String _shortDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}
