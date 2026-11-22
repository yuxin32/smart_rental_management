import '../presentation/workspace_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Presentation widgets shared by the real connected route and its visual
/// tests. They receive server data but never fabricate booking records.
class ConnectedWorkspaceHero extends StatelessWidget {
  const ConnectedWorkspaceHero({super.key, required this.owner});

  final bool owner;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFF254684)],
          ),
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              owner
                  ? Icons.home_work_outlined
                  : Icons.cleaning_services_outlined,
              color: AppColors.primaryLighter,
              size: 31,
            ),
            const SizedBox(height: 14),
            Text(
              owner ? 'Your cleaning services' : 'Your cleaning jobs',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              owner
                  ? 'Manage requests, appointments and service records in one place.'
                  : 'Check requests, manage your hours and keep jobs on track.',
              style: const TextStyle(
                color: Color(0xFFD9E8FF),
                height: 1.4,
              ),
            ),
          ],
        ),
      );
}

class ConnectedSummaryTiles extends StatelessWidget {
  const ConnectedSummaryTiles({super.key, required this.values});

  final List<(String, int, IconData)> values;

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColors.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: values
            .map((item) => Semantics(
                  container: true,
                  label: '${item.$1}: ${item.$2}',
                  child: ExcludeSemantics(
                      child: SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border.all(color: colors.border),
                        borderRadius: BorderRadius.circular(AppRadius.l),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(item.$3,
                              size: 21,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 8),
                          Text('${item.$2}',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 25,
                              )),
                          Text(item.$1,
                              style: TextStyle(color: colors.textSecondary)),
                        ],
                      ),
                    ),
                  )),
                ))
            .toList(),
      );
    });
  }
}

class ConnectedPropertyCard extends StatelessWidget {
  const ConnectedPropertyCard({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColors.of(context);
    final name = [row['unit_name'], row['building_name']]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .map(workspaceText)
        .join(', ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.primarySurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.apartment_outlined,
                  color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    )),
                const SizedBox(height: 4),
                Text('${row['bedrooms']} bedrooms · ${row['size_sqft']} sqft',
                    style: TextStyle(color: colors.textSecondary)),
                const SizedBox(height: 4),
                Text(workspaceText(row['address'] as String? ?? ''),
                    style: TextStyle(color: colors.textSecondary)),
              ],
            )),
          ],
        ),
      ),
    );
  }
}

class ConnectedProviderProfileCard extends StatelessWidget {
  const ConnectedProviderProfileCard({super.key, required this.profile});

  final Map<String, dynamic>? profile;

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColors.of(context);
    final status = profile?['approval_status']?.toString() ?? 'missing';
    final approved = status == 'approved';
    final pending = status == 'pending';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your provider profile',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                )),
            const SizedBox(height: 8),
            Text(
                profile?['service_area']?.toString() ??
                    'Complete your provider profile to get started.',
                style: TextStyle(color: colors.textSecondary)),
            const SizedBox(height: 10),
            Text(
              approved
                  ? 'Approved · You can receive and accept cleaning requests.'
                  : pending
                      ? 'Approval pending · Set your services and working hours while you wait.'
                      : 'Not approved for new requests. Check your profile status before accepting jobs.',
              style: TextStyle(
                color: approved
                    ? Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.secondary
                        : AppColors.positive
                    : colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String connectedBookingTimeLabel(Object? startValue, Object? endValue) {
  final start = DateTime.tryParse(startValue?.toString() ?? '');
  final end = DateTime.tryParse(endValue?.toString() ?? '');
  if (start == null || end == null) return 'Schedule unavailable';
  final malaysiaStart = start.toUtc().add(const Duration(hours: 8));
  final malaysiaEnd = end.toUtc().add(const Duration(hours: 8));
  final date = DateFormat('EEE, d MMM yyyy').format(malaysiaStart);
  final startTime = DateFormat('h:mm a').format(malaysiaStart);
  final endTime = DateFormat('h:mm a').format(malaysiaEnd);
  final endDate = malaysiaStart.year == malaysiaEnd.year &&
          malaysiaStart.month == malaysiaEnd.month &&
          malaysiaStart.day == malaysiaEnd.day
      ? ''
      : '–${DateFormat('d MMM').format(malaysiaEnd)} ';
  return '$date · $startTime–$endDate$endTime MYT';
}

String connectedEventTimeLabel(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return 'Time unavailable';
  final malaysia = parsed.toUtc().add(const Duration(hours: 8));
  return '${DateFormat('d MMM yyyy, h:mm a').format(malaysia)} MYT';
}

class ConnectedBookingCard extends StatelessWidget {
  const ConnectedBookingCard({
    super.key,
    required this.row,
    required this.isProvider,
    required this.busy,
    this.propertyName,
    required this.onAction,
    required this.onHistory,
    required this.onMessages,
    required this.onEvidence,
    required this.onReview,
    required this.onCancel,
    this.onEdit,
  });

  final Map<String, dynamic> row;
  final bool isProvider;
  final bool busy;
  final String? propertyName;
  final void Function(String action) onAction;
  final VoidCallback onHistory;
  final VoidCallback onMessages;
  final VoidCallback onEvidence;
  final VoidCallback onReview;
  final VoidCallback onCancel;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColors.of(context);
    final status = row['current_status'] as String? ?? 'Unknown';
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = switch (status) {
      'Accepted' ||
      'Completed' =>
        isDark ? scheme.secondary : AppColors.positive,
      'In Progress' => Theme.of(context).colorScheme.tertiary,
      'Declined' || 'Cancelled' => isDark ? scheme.error : AppColors.negative,
      _ => Theme.of(context).colorScheme.primary,
    };
    final nextStep = switch ((isProvider, status)) {
      (true, 'Pending') => 'Review this request and decide whether to accept.',
      (true, 'Accepted') => 'Ready to start at the agreed time.',
      (true, 'In Progress') => 'Add photos and remarks when the job is done.',
      (false, 'Pending') => 'Waiting for the provider to respond.',
      (false, 'Accepted') => 'Your provider has confirmed this appointment.',
      (false, 'In Progress') => 'The cleaning is under way.',
      (_, 'Completed') => 'Cleaning completed. The record is ready to review.',
      (_, 'Cancelled') => 'This booking was cancelled.',
      (_, 'Declined') => 'The provider declined this request.',
      _ => 'Check the booking status history for updates.',
    };
    final quoted = row['quoted_amount'];
    final bookingLabel = propertyName == null || propertyName!.isEmpty
        ? 'cleaning booking'
        : propertyName!;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final title = Text(
                propertyName == null || propertyName!.isEmpty
                    ? 'Cleaning booking'
                    : propertyName!,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              );
              final badge = Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    )),
              );
              if (constraints.maxWidth < 280 ||
                  MediaQuery.textScalerOf(context).scale(17) > 23) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 8), badge],
                );
              }
              return Row(children: [
                Expanded(child: title),
                const SizedBox(width: 8),
                badge,
              ]);
            }),
            const SizedBox(height: 12),
            if (row['service_name'] is String) ...[
              Text(
                row['service_name'] as String,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.event_outlined, size: 20, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                connectedBookingTimeLabel(
                    row['requested_start_at'], row['requested_end_at']),
                style: TextStyle(color: colors.textPrimary),
              )),
            ]),
            if (row['property_address'] is String &&
                (row['property_address'] as String).isNotEmpty) ...[
              const SizedBox(height: 7),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.place_outlined,
                    size: 20, color: colors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                  workspaceText(row['property_address'] as String),
                  style: TextStyle(color: colors.textSecondary),
                )),
              ]),
            ],
            if (row['instructions'] is String &&
                workspaceText(row['instructions'] as String).isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                  '${isProvider ? 'Owner instructions' : 'Your instructions'}: ${workspaceText(row['instructions'] as String)}',
                  style: TextStyle(color: colors.textSecondary)),
            ],
            if (quoted is num) ...[
              const SizedBox(height: 7),
              Text('Quoted cleaning fee · RM ${quoted.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  )),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.primarySurface,
                borderRadius: BorderRadius.circular(AppRadius.m),
              ),
              child:
                  Text(nextStep, style: TextStyle(color: colors.textPrimary)),
            ),
            const SizedBox(height: 12),
            if (isProvider && status == 'Pending')
              _primary(context, 'Accept request', () => onAction('Accepted')),
            if (isProvider && status == 'Accepted')
              _primary(
                  context, 'Start cleaning', () => onAction('In Progress')),
            if (isProvider && status == 'In Progress')
              _primary(context, 'Add evidence & complete', onEvidence),
            if (!isProvider && status == 'Completed')
              _primary(context, 'Review completed service', onEvidence),
            if (!isProvider && ['Accepted', 'In Progress'].contains(status))
              _primary(context, 'Message provider', onMessages),
            if (!isProvider && status == 'Pending') ...[
              if (onEdit != null) _primary(context, 'Edit request', onEdit!),
              Text('Messaging opens after the provider accepts.',
                  style: TextStyle(color: colors.textSecondary)),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if ((isProvider &&
                      ['Accepted', 'In Progress'].contains(status)) ||
                  ['Completed', 'Cancelled', 'Declined'].contains(status))
                _contextAction(
                  label: 'Open messages for $bookingLabel',
                  onTap: onMessages,
                  child: TextButton.icon(
                    onPressed: onMessages,
                    icon: const Icon(Icons.chat_bubble_outline, size: 19),
                    label: Text(
                        ['Completed', 'Cancelled', 'Declined'].contains(status)
                            ? 'View conversation'
                            : 'Messages'),
                  ),
                ),
              if (status == 'Completed')
                TextButton.icon(
                  onPressed: onReview,
                  icon: const Icon(Icons.star_outline_rounded, size: 19),
                  label: Text(isProvider ? 'Owner review' : 'Rate cleaning'),
                ),
              if (isProvider && status == 'Completed')
                TextButton.icon(
                  onPressed: onEvidence,
                  icon: const Icon(Icons.photo_library_outlined, size: 19),
                  label: const Text('Evidence'),
                ),
              if (isProvider && status == 'Pending')
                TextButton(
                  onPressed: busy ? null : () => onAction('Declined'),
                  child: const Text('Decline'),
                ),
            ]),
            if ((isProvider && status == 'Accepted') ||
                (!isProvider && ['Pending', 'Accepted'].contains(status))) ...[
              const SizedBox(height: 12),
              SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onCancel,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        foregroundColor: scheme.error,
                        side:
                            BorderSide(color: scheme.error.withOpacity(0.55))),
                    icon: const Icon(Icons.cancel_outlined, size: 19),
                    label: const Text('Cancel booking'),
                  )),
            ],
            const SizedBox(height: 16),
            Divider(color: colors.border),
            _contextAction(
                label: 'View status history for $bookingLabel',
                onTap: onHistory,
                child: TextButton.icon(
                    onPressed: busy ? null : onHistory,
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                    icon: const Icon(Icons.history, size: 19),
                    label: const Text('Status history'))),
          ],
        ),
      ),
    );
  }

  Widget _primary(BuildContext context, String label, VoidCallback action) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : action,
              child: Text(label),
            ),
          ));

  Widget _contextAction({
    required String label,
    required VoidCallback onTap,
    required Widget child,
  }) =>
      Semantics(
        button: true,
        label: label,
        onTap: onTap,
        child: ExcludeSemantics(child: child),
      );
}
