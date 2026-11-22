// lib/screens/reschedule_screen.dart
//
// The class name is retained temporarily so existing navigation remains
// compatible. In the authoritative lifecycle this screen edits a Pending
// request; it does not create a separate Rescheduled status.

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/demo_data.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import '../widgets/time_slot_picker.dart';

class RescheduleScreen extends StatefulWidget {
  const RescheduleScreen({super.key, required this.booking});

  final DemoBooking booking;

  @override
  State<RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends State<RescheduleScreen> {
  late DateTime _date;
  late TimeOfDay _time;
  late TextEditingController _instructionsController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = widget.booking.scheduledStart;
    _time = TimeOfDay.fromDateTime(widget.booking.scheduledStart);
    _instructionsController = TextEditingController(
      text: widget.booking.specialInstructions ?? '',
    );
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initialDate = _date.isBefore(now) ? now : _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
        _error = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimeSlotPicker(
      context: context,
      initialTime: _time,
      title: 'New requested start time',
      description:
          'The service duration stays the same. Eligibility is checked when you save. MYT (UTC+8).',
    );
    if (picked != null && mounted) {
      setState(() {
        _time = picked;
        _error = null;
      });
    }
  }

  void _submit() {
    if (widget.booking.status != BookingStatus.pending) {
      setState(() {
        _error = 'Only a Pending request can be edited.';
      });
      return;
    }

    final start = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    if (!start.isAfter(DateTime.now())) {
      setState(() {
        _error = 'Choose a future date and time.';
      });
      return;
    }

    final duration =
        widget.booking.scheduledEnd.difference(widget.booking.scheduledStart);
    final store = AppProviders.of(context).bookingStore;
    final validationError = store.revisionError(
      id: widget.booking.id,
      newStart: start,
      newEnd: start.add(duration),
    );
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    final updated = store.revisePendingBooking(
      id: widget.booking.id,
      newStart: start,
      newEnd: start.add(duration),
      specialInstructions: _instructionsController.text.trim(),
    );

    if (updated == null) {
      setState(() {
        _error = 'The request could not be updated.';
      });
      return;
    }

    Haptics.medium();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Pending request updated. Availability was checked and will be rechecked before acceptance.',
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final start = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final canEdit = widget.booking.status == BookingStatus.pending;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit pending request'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: sem.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sem.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.booking.property,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: sem.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.booking.serviceType,
                  style: TextStyle(fontSize: 12, color: sem.textSecondary),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Changing the requested interval keeps this request Pending. '
                  'The provider can accept it only after availability and '
                  'booking conflicts are checked again.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'REQUESTED DATE & TIME',
            style: TextStyle(
              fontSize: 11,
              color: sem.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _picker(
                  context,
                  label: 'Date',
                  value: _formatDate(_date),
                  icon: Icons.calendar_today,
                  onTap: _pickDate,
                  enabled: canEdit,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _picker(
                  context,
                  label: 'Time',
                  value: timeSlotLabel(timeOfDayMinutes(_time)),
                  icon: Icons.schedule,
                  onTap: _pickTime,
                  enabled: canEdit,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _instructionsController,
            enabled: canEdit,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Service instructions',
              hintText: 'Add or update instructions for the provider',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Updated request: ${_formatDateTime(start)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF065F46),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: canEdit ? _submit : null,
            icon: const Icon(Icons.check),
            label: const Text('Save pending request'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _picker(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    final sem = SemanticColors.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled
            ? () {
                Haptics.light();
                onTap();
              }
            : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: sem.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sem.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: sem.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: sem.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: sem.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
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
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatDateTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${_formatDate(date)} at $hour:$minute';
  }
}
