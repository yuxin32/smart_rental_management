// lib/widgets/booking_card.dart
// Compact booking row used in lists. Shows recurring badge when applicable.

import 'package:flutter/material.dart';
import '../models/demo_data.dart';
import '../theme/app_theme.dart';
import 'status_chip.dart';

class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking, required this.onTap});
  final DemoBooking booking;
  final VoidCallback onTap;

  String _fmtDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _timeRange(DateTime s, DateTime e) =>
      '${_fmtTime(s)} - ${_fmtTime(e)}';

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      booking.property,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: sem.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right,
                      size: 20, color: sem.textTertiary),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusChip(status: booking.status),
                  if (booking.isRecurring)
                    _RecurringBadge(pattern: booking.recurrencePattern!),
                  if (booking.isMultiDay)
                    _MultiDayBadge(days: booking.totalDays),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                booking.serviceType,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sem.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: sem.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    _fmtDate(booking.scheduledStart),
                    style: TextStyle(fontSize: 12, color: sem.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _timeRange(booking.scheduledStart, booking.scheduledEnd),
                      style: TextStyle(fontSize: 12, color: sem.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (booking.providerName != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.person, size: 14, color: sem.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        booking.providerName!,
                        style:
                            TextStyle(fontSize: 12, color: sem.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecurringBadge extends StatelessWidget {
  const _RecurringBadge({required this.pattern});
  final RecurrencePattern pattern;

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: sem.primarySurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: sem.primaryBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.repeat, size: 10, color: accent),
          const SizedBox(width: 3),
          Text(
            pattern.shortLabel,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: accent,
                letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }
}

class _MultiDayBadge extends StatelessWidget {
  const _MultiDayBadge({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: sem.primarySurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: sem.primaryBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_view_week, size: 10, color: accent),
          const SizedBox(width: 3),
          Text(
            '$days days',
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: accent,
                letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }
}
