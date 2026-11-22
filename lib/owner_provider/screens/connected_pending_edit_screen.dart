import '../presentation/workspace_text.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/backend/supabase_booking_repository.dart';
import '../services/backend/connected_failure_message.dart';
import '../widgets/time_slot_picker.dart';
import '../widgets/unsaved_changes_guard.dart';
import 'connected_booking_request_screen.dart';

/// A revision keeps the saved service duration and quote. Changing property,
/// provider or duration is a new request, not a client-side reprice.
class ConnectedPendingEditScreen extends StatefulWidget {
  const ConnectedPendingEditScreen(
      {super.key,
      required this.row,
      required this.save,
      required this.canSave});
  final Map<String, dynamic> row;
  final Future<AcceptanceOutcome> Function(DateTime, DateTime, String) save;
  final bool Function() canSave;
  @override
  State<ConnectedPendingEditScreen> createState() =>
      _ConnectedPendingEditState();
}

class _ConnectedPendingEditState extends State<ConnectedPendingEditScreen> {
  final form = GlobalKey<FormState>();
  late final original =
      DateTime.parse(widget.row['requested_start_at'] as String).toUtc();
  late final duration = DateTime.parse(widget.row['requested_end_at'] as String)
      .toUtc()
      .difference(original);
  late DateTime day;
  late TimeOfDay time;
  late final instructions = TextEditingController(
      text: workspaceText(widget.row['instructions'] as String? ?? ''));
  late final notesLimit = math.max(
      1600, (widget.row['instructions'] as String? ?? '').runes.length);
  bool busy = false, uncertain = false, saved = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final myt = original.add(const Duration(hours: 8));
    day = DateTime(myt.year, myt.month, myt.day);
    time = TimeOfDay(hour: myt.hour, minute: myt.minute);
  }

  @override
  void dispose() {
    instructions.dispose();
    super.dispose();
  }

  DateTime get start => malaysiaBookingInstant(day, time);
  bool get dirty =>
      !saved &&
      (start != original ||
          instructions.text !=
              workspaceText(widget.row['instructions'] as String? ?? ''));
  Future<void> _save() async {
    if (busy || uncertain || !form.currentState!.validate()) return;
    if (!widget.canSave()) {
      setState(() =>
          error = 'Your session changed. Close this page and sign in again.');
      return;
    }
    if (!start.isAfter(DateTime.now().toUtc())) {
      setState(() => error = 'Choose a future start time.');
      return;
    }
    final endMyt = start.add(duration).add(const Duration(hours: 8));
    if (endMyt.day != day.day ||
        endMyt.month != day.month ||
        endMyt.year != day.year) {
      setState(() => error = 'The cleaning must finish on the same day.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.save(
          start,
          start.add(duration),
          instructions.text ==
                  workspaceText(widget.row['instructions'] as String? ?? '')
              ? (widget.row['instructions'] as String? ?? '')
              : instructions.text.trim());
      if (!mounted) return;
      if (!result.accepted) {
        setState(() => error =
            ConnectedFailureMessage.forBookingReason(result.reason ?? ''));
        return;
      }
      saved = true;
      busy = false;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(() {
          uncertain = true;
          error =
              'We could not confirm this save. Your entries are kept. Return to the booking and refresh to check its time and instructions before trying again.';
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      dirty: () => dirty,
      busy: () => busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit Pending request')),
        body: Form(
            key: form,
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Change the time or instructions',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Text(
                          'Your ${duration.inMinutes}-minute duration, unit, provider, service and saved quote stay the same. A different duration needs a new request.'),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text('${day.day}/${day.month}/${day.year}'),
                          onPressed: busy || uncertain
                              ? null
                              : () async {
                                  final now = DateTime.now()
                                      .toUtc()
                                      .add(const Duration(hours: 8));
                                  final today =
                                      DateTime(now.year, now.month, now.day);
                                  final value = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          day.isBefore(today) ? today : day,
                                      firstDate: today,
                                      lastDate:
                                          today.add(const Duration(days: 365)));
                                  if (value != null && mounted)
                                    setState(() => day = value);
                                }),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          icon: const Icon(Icons.schedule),
                          label: Text(
                              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} MYT'),
                          onPressed: busy || uncertain
                              ? null
                              : () async {
                                  final value = await showTimeSlotPicker(
                                      context: context,
                                      initialTime: time,
                                      title: 'New start time',
                                      lastMinute: 1439 - duration.inMinutes,
                                      description:
                                          'The server checks the complete interval before saving.');
                                  if (value != null && mounted)
                                    setState(() => time = value);
                                }),
                      const SizedBox(height: 20),
                      TextFormField(
                          controller: instructions,
                          enabled: !busy && !uncertain,
                          maxLength: notesLimit,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(
                              labelText: 'Cleaning instructions (optional)',
                              helperText:
                                  'Includes any saved extra-task requests. Extra tasks remain outside the quote.',
                              helperMaxLines: 3,
                              hintText:
                                  'e.g. Please focus on the kitchen and balcony'),
                          validator: (v) => (v?.runes.length ?? 0) > notesLimit
                              ? 'Use at most $notesLimit characters.'
                              : null),
                      if (error != null)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: busy || uncertain ? null : _save,
                          child:
                              Text(busy ? 'Saving…' : 'Save request changes')),
                    ]))),
      ));
}
