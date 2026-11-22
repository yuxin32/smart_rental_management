import '../presentation/workspace_text.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'connected_workspace_components.dart';

/// Actual events only: cancelled/declined branches never imply later milestones.
class BookingActivityTile extends StatelessWidget {
  const BookingActivityTile(
      {super.key,
      required this.event,
      this.isLatest = false,
      this.isLast = false,
      this.timeLabel,
      this.actorLabel});
  final Map<String, dynamic> event;
  final bool isLatest, isLast;
  final String? timeLabel, actorLabel;

  static String title(String? status, {String? previous}) => switch (status) {
        'Pending' => previous == null ? 'Request sent' : 'Request updated',
        'Accepted' => 'Request accepted',
        'In Progress' => 'Cleaning started',
        'Completed' => 'Cleaning completed',
        'Cancelled' => 'Booking cancelled',
        'Declined' => 'Request declined',
        _ => 'Booking updated',
      };

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final status = event['new_status'] as String?;
    final reason = event['change_reason'] is String
        ? workspaceText(event['change_reason'] as String).trim()
        : '';
    final icon = switch (status) {
      'Accepted' => Icons.event_available_outlined,
      'In Progress' => Icons.cleaning_services_outlined,
      'Completed' => Icons.task_alt,
      'Cancelled' => Icons.cancel_outlined,
      'Declined' => Icons.do_not_disturb_on_outlined,
      _ => Icons.send_outlined,
    };
    final description = switch (status) {
      'Pending' => 'Waiting for the provider to respond.',
      'Accepted' => 'The provider confirmed this appointment.',
      'In Progress' => 'The provider marked the cleaning as started.',
      'Completed' => 'The provider marked the cleaning as completed.',
      'Cancelled' => 'This booking is closed.',
      'Declined' => 'The provider did not accept this request.',
      _ => 'An update was recorded for this booking.',
    };
    return Stack(children: [
      if (!isLast)
        Positioned(
            left: 15,
            top: 32,
            bottom: 0,
            child: Container(width: 2, color: colors.border)),
      Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: isLatest ? scheme.primary : colors.primarySurface,
                    shape: BoxShape.circle),
                child: Icon(icon,
                    size: 18,
                    color: isLatest ? scheme.onPrimary : scheme.primary)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  if (isLatest)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('Latest update',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary))),
                  Text(
                      title(status,
                          previous: event['previous_status'] as String?),
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text(
                      timeLabel ?? connectedEventTimeLabel(event['changed_at']),
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary)),
                  if (actorLabel != null)
                    Text(actorLabel!,
                        style: TextStyle(
                            fontSize: 12, color: colors.textSecondary)),
                  const SizedBox(height: 7),
                  Text(description,
                      style:
                          TextStyle(color: colors.textSecondary, height: 1.4)),
                  if (reason.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: colors.surfaceAlt,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.border)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Reason',
                                  style: TextStyle(
                                      color: colors.textPrimary,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(reason,
                                  style: TextStyle(
                                      color: colors.textSecondary,
                                      height: 1.4)),
                            ])),
                  ],
                ])),
          ])),
    ]);
  }
}
