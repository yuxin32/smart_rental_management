// lib/screens/provider_edit_profile_screen.dart
// Provider profile editor. Reads from + writes to ProviderStore.
//
// Round 7 polish:
//   1. Form validation (name, phone, email, rate, working hours)
//   2. Section grouping (Profile / Contact / Services / Schedule / Rate / Privacy)
//   3. Sticky save button in bottomNavigationBar
//   4. Unsaved changes guard via PopScope + confirm dialog
//   5. Bigger avatar (120x120) with photo/color toggle
//   6. Helper text + char counter + bio limit (200)
//   7. Bonus: Privacy toggle for phone visibility to owners

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../features/availability/domain/provider_availability.dart';
import '../main.dart';
import '../models/demo_data.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import '../widgets/time_slot_picker.dart';
import 'provider_profile_screen.dart';
import '../services/backend/provider_profile_snapshot.dart';
import '../services/backend/connected_failure_message.dart';
import '../services/backend/safe_diagnostics.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

class ProviderEditProfileScreen extends StatefulWidget {
  const ProviderEditProfileScreen(
      {super.key,
      required this.provider,
      this.snapshot,
      this.onSaveConnected,
      this.onReloadConnected,
      this.canEditConnected,
      this.onManageAvailability});
  final DemoProvider provider;
  final ProviderProfileSnapshot? snapshot;
  final Future<ProviderProfileSnapshot> Function(
      ProviderProfileDraft, ProviderProfileSnapshot)? onSaveConnected;
  final Future<ProviderProfileSnapshot> Function()? onReloadConnected;
  final bool Function()? canEditConnected;
  final Future<void> Function()? onManageAvailability;

  @override
  State<ProviderEditProfileScreen> createState() =>
      _ProviderEditProfileScreenState();
}

class _ProviderEditProfileScreenState extends State<ProviderEditProfileScreen> {
  // Controllers ------------------------------------------------------------
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _rateCtrl;
  late TimeOfDay _workStart;
  late TimeOfDay _workEnd;
  late List<String> _services;
  late int _avatarColorIndex;
  late bool _showPhoneToOwners;
  XFile? _avatarImage;
  bool _saving = false;
  bool _appearanceExpanded = false;
  ProviderProfileSnapshot? _server;
  bool get _connected => widget.snapshot != null;
  bool _needsReload = false;
  String? _saveError;
  late TextEditingController _dailyCtrl, _areaCtrl, _originCtrl;
  String _rateText(double? value) => value?.toStringAsFixed(2) ?? '';

  // Snapshot of initial values to detect dirty state.
  late DemoProvider _initial;

  // Constants ----------------------------------------------------------------
  static const _bioMaxLength = 200;
  static const _allServices = <Map<String, String>>[
    {'id': 'standard', 'label': 'Standard cleaning'},
    {'id': 'deep', 'label': 'Deep cleaning'},
    {'id': 'window', 'label': 'Window cleaning'},
    {'id': 'move-in', 'label': 'Move-in cleaning'},
    {'id': 'move-out', 'label': 'Move-out cleaning'},
  ];
  static const _avatarColors = <Color>[
    AppColors.primary, // navy brand option
    AppColors.secondary, // sky-blue brand option
    Color(0xFF6366F1), // indigo
    Color(0xFFFB8C00), // orange
    Color(0xFFEF4444), // red
    Color(0xFF8B5CF6), // purple
  ];

  // Lifecycle ---------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _initial = widget.provider;
    final p = widget.provider;
    _server = widget.snapshot;
    _nameCtrl = TextEditingController(text: p.name);
    _phoneCtrl = TextEditingController(text: p.phone);
    _emailCtrl = TextEditingController(text: p.email);
    _bioCtrl = TextEditingController(text: p.bio);
    _rateCtrl = TextEditingController(
        text: _connected
            ? _rateText(_server!.hourly)
            : p.hourlyRate.toStringAsFixed(0));
    _dailyCtrl = TextEditingController(text: _rateText(_server?.daily));
    _areaCtrl = TextEditingController(text: _server?.area ?? '');
    _originCtrl = TextEditingController(text: _server?.origin ?? '');
    _workStart = p.workingHoursStart;
    _workEnd = p.workingHoursEnd;
    _services =
        _connected ? _server!.selected.toList() : List.of(p.serviceTypes);
    _avatarColorIndex = p.avatarColorIndex;
    _showPhoneToOwners = p.showPhoneToOwners;
    for (final controller in [
      _nameCtrl,
      _phoneCtrl,
      _emailCtrl,
      _bioCtrl,
      _rateCtrl,
      _dailyCtrl,
      _areaCtrl,
      _originCtrl,
    ]) {
      controller.addListener(_refreshSaveState);
    }
  }

  void _refreshSaveState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _bioCtrl.dispose();
    _rateCtrl.dispose();
    _dailyCtrl.dispose();
    _areaCtrl.dispose();
    _originCtrl.dispose();
    super.dispose();
  }

  // Dirty-state detection ---------------------------------------------------
  bool get _isDirty {
    if (_nameCtrl.text.trim() != _initial.name) return true;
    if (_phoneCtrl.text.trim() != _initial.phone) return true;
    if (_emailCtrl.text.trim() != _initial.email) return true;
    if (_bioCtrl.text.trim() != _initial.bio) return true;
    if (_rateCtrl.text.trim() !=
        (_connected
            ? _rateText(_server!.hourly)
            : _initial.hourlyRate.toStringAsFixed(0))) {
      return true;
    }
    if (_workStart != _initial.workingHoursStart) return true;
    if (_workEnd != _initial.workingHoursEnd) return true;
    final initialServices =
        _connected ? _server!.selected.toList() : _initial.serviceTypes;
    if (_services.length != initialServices.length ||
        !_services
            .asMap()
            .entries
            .every((e) => initialServices.contains(e.value))) return true;
    if (_connected &&
        (_dailyCtrl.text.trim() != _rateText(_server!.daily) ||
            _areaCtrl.text.trim() != _server!.area ||
            _originCtrl.text.trim() != _server!.origin)) return true;
    if (_avatarColorIndex != _initial.avatarColorIndex) return true;
    if (_showPhoneToOwners != _initial.showPhoneToOwners) return true;
    return false;
  }

  // Validators --------------------------------------------------------------
  String? _validateName(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Display name is required';
    if (t.length < 2) return 'At least 2 characters';
    if (t.length > 60) return 'Too long (max 60)';
    return null;
  }

  String? _validatePhone(String? v) {
    final t = (v ?? '').trim();
    if (_connected && t.isEmpty && !_showPhoneToOwners) return null;
    if (t.isEmpty) return 'Phone is required';
    // Loose Malaysian phone format: +60 12-345 6789 / 012-345 6789 / +60123456789
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9 ||
        digits.length > (_connected ? 15 : 13) ||
        (_connected && !RegExp(r'^\+?[0-9 ()-]+$').hasMatch(t))) {
      return 'Enter a valid phone (e.g. +60 12-345 6789)';
    }
    return null;
  }

  String? _validateEmail(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Email is required';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
    if (!ok) return 'Enter a valid email';
    return null;
  }

  String? _validateRate(String? v) {
    final t = (v ?? '').trim();
    if (_connected) return _validateConnectedRate(t, _dailyCtrl.text.trim());
    if (t.isEmpty) return 'Hourly rate is required';
    final n = double.tryParse(t);
    if (n == null) return 'Enter a number';
    if (n <= 0) return 'Must be greater than 0';
    if (n > 1000) return 'Too high (max RM 1000/hr)';
    return null;
  }

  String? _validateConnectedRate(String value, String other) {
    if (value.isEmpty)
      return other.isEmpty ? 'Enter an hourly or daily rate' : null;
    final n = double.tryParse(value);
    if (n == null ||
        !n.isFinite ||
        n <= 0 ||
        n > 99999999.99 ||
        !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value))
      return 'Use a positive amount with up to 2 decimals';
    return null;
  }

  String? _validateBio(String? v) {
    final t = v ?? '';
    if (t.length > _bioMaxLength) return 'Max $_bioMaxLength characters';
    return null;
  }

  // Actions -----------------------------------------------------------------
  Future<void> _pickAvatar() async {
    Haptics.light();
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image == null) return;
      setState(() => _avatarImage = image);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not pick image: $e'),
              behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _clearAvatarImage() {
    Haptics.light();
    setState(() => _avatarImage = null);
  }

  Future<void> _pickTime({required bool isStart}) async {
    Haptics.light();
    final initial = isStart ? _workStart : _workEnd;
    final picked = await showTimeSlotPicker(
      context: context,
      initialTime: initial,
      title: isStart ? 'Working hours start' : 'Working hours end',
      firstMinute: isStart
          ? 0
          : timeOfDayMinutes(_workStart) + AvailabilitySlot.minimumMinutes,
      lastMinute: isStart ? 1439 - AvailabilitySlot.minimumMinutes : 1439,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _workStart = picked;
        if (!_isEndAfterStart()) {
          // Preserve the existing minimum two-hour working-slot rule.
          final end =
              timeOfDayMinutes(picked) + AvailabilitySlot.minimumMinutes;
          _workEnd = TimeOfDay(
            hour: end ~/ 60,
            minute: end % 60,
          );
        }
      } else {
        if (!_isEndAfterStart(customEnd: picked)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Working hours must be at least 2 hours long'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        _workEnd = picked;
      }
    });
  }

  bool _isEndAfterStart({TimeOfDay? customStart, TimeOfDay? customEnd}) {
    final s = customStart ?? _workStart;
    final e = customEnd ?? _workEnd;
    final sMin = s.hour * 60 + s.minute;
    final eMin = e.hour * 60 + e.minute;
    return eMin - sMin >= AvailabilitySlot.minimumMinutes;
  }

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved changes. Leave anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _save() async {
    if (_connected) {
      await _saveConnected();
      return;
    }
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fix the errors above'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_services.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick at least one service'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!_isEndAfterStart()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Working hours must be at least 2 hours long'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Haptics.medium();
    setState(() => _saving = true);
    final store = AppProviders.of(context).providerStore;
    final current = store.byId(widget.provider.id) ?? widget.provider;
    var schedule = current.availabilitySchedule;
    if (_workStart != _initial.workingHoursStart ||
        _workEnd != _initial.workingHoursEnd) {
      final slot = AvailabilitySlot(
        _workStart.hour * 60 + _workStart.minute,
        _workEnd.hour * 60 + _workEnd.minute,
      );
      for (var day = 1; day <= 7; day++) {
        if ((schedule.weeklySlots[day] ?? const []).isNotEmpty) {
          schedule = schedule.withDaySlots(day, [slot]);
        }
      }
    }
    final updated = current.copyWith(
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      bio: _bioCtrl.text.trim(),
      hourlyRate: double.tryParse(_rateCtrl.text) ?? widget.provider.hourlyRate,
      workingHoursStart: _workStart,
      workingHoursEnd: _workEnd,
      availabilitySchedule: schedule,
      serviceTypes: _services,
      avatarColorIndex: _avatarColorIndex,
      showPhoneToOwners: _showPhoneToOwners,
    );
    store.update(updated);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _initial = updated; // reset dirty baseline
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Profile updated'),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => ProviderProfileScreen(provider: updated)),
              );
            },
          ),
        ),
      );
      Navigator.of(context).pop();
    });
  }

  Future<void> _saveConnected() async {
    if (_saving || _needsReload || widget.canEditConnected?.call() != true)
      return;
    if (!_formKey.currentState!.validate() || _services.isEmpty) {
      setState(() => _saveError =
          'Check the highlighted fields and select at least one service.');
      return;
    }
    final draft = ProviderProfileDraft(
        name: _nameCtrl.text,
        bio: _bioCtrl.text,
        phone: _phoneCtrl.text,
        area: _areaCtrl.text,
        origin: _originCtrl.text,
        hourly: double.tryParse(_rateCtrl.text),
        daily: double.tryParse(_dailyCtrl.text),
        avatar: _avatarColorIndex,
        sharePhone: _showPhoneToOwners,
        services: _services.toSet());
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSaveConnected!(draft, _server!);
      if (!mounted || widget.canEditConnected?.call() != true) return;
      // Clear dirty state only after the database acknowledged the transaction.
      _allowPop = true;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved to your account')));
      setState(() => _saving = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.providerSetupSave, error);
      if (!mounted || widget.canEditConnected?.call() != true) return;
      final code = error is PostgrestException ? error.code : null;
      setState(() {
        _needsReload = code != '22023' && code != '23514' && code != '22P02';
        _saveError = code == '40001'
            ? 'This profile changed elsewhere. Reload the saved profile before editing again.'
            : code == '23514'
                ? 'A confirmed booking still needs one of your services. Keep that service until the booking is resolved.'
                : code == '22023' || code == '22P02'
                    ? 'Check your name, phone, rates and selected services.'
                    : ConnectedFailureMessage.forWrite(error, item: 'profile');
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _allowPop = false;
  Future<void> _manageConnectedAvailability() async {
    if (_saving || widget.canEditConnected?.call() != true) return;
    try {
      await widget.onManageAvailability?.call();
      if (!mounted || widget.canEditConnected?.call() != true) return;
      final latest = await widget.onReloadConnected!();
      if (!mounted || widget.canEditConnected?.call() != true) return;
      final old = _server!;
      // Refresh only read-only slots; never silently rebase a dirty draft over
      // capability/contact/rate changes made through the availability route.
      setState(() {
        _server = ProviderProfileSnapshot.parse(
            {...old.row, 'weekly_slots': latest.row['weekly_slots']}, old.id);
        if (old.revision != latest.revision || old.contact != latest.contact) {
          _needsReload = true;
          _saveError =
              'Your services or profile changed. Check the saved profile before continuing.';
        }
      });
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.providerSetupLoad, error);
      if (mounted)
        setState(() => _saveError =
            'Could not refresh availability. Reload to check the saved working slots.');
    }
  }

  Future<void> _reloadConnected() async {
    if (_saving || widget.canEditConnected?.call() != true) return;
    if (!await _confirmDiscard() || !mounted) return;
    setState(() => _saving = true);
    try {
      final value = await widget.onReloadConnected!();
      if (!mounted || widget.canEditConnected?.call() != true) return;
      _server = value;
      _initial = value.presentation;
      _nameCtrl.text = value.name;
      _phoneCtrl.text = value.contact ?? '';
      _emailCtrl.text = value.email;
      _bioCtrl.text = value.bio;
      _rateCtrl.text = _rateText(value.hourly);
      _dailyCtrl.text = _rateText(value.daily);
      _areaCtrl.text = value.area;
      _originCtrl.text = value.origin;
      _services = value.selected.toList();
      _avatarColorIndex = value.avatar;
      _showPhoneToOwners = value.sharePhone;
      setState(() {
        _needsReload = false;
        _saveError = null;
      });
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.providerSetupLoad, error);
      if (mounted)
        setState(() => _saveError =
            'Could not check your saved profile. Keep this page open and retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Build -------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_saving) return;
        if (await _confirmDiscard()) {
          if (mounted) {
            if (_connected) {
              setState(() => _allowPop = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).pop();
              });
            } else {
              Navigator.of(context).pop();
            }
          }
        }
      },
      child: Scaffold(
        backgroundColor: sem.background,
        appBar: AppBar(
          title: const Text('Edit profile'),
          actions: [
            if (_connected)
              IconButton(
                  onPressed: _saving ? null : _reloadConnected,
                  tooltip: 'Reload saved profile',
                  icon: const Icon(Icons.refresh)),
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(children: [
              if (_saveError != null) ...[
                Semantics(
                    liveRegion: true,
                    child: Text(_saveError!,
                        style: TextStyle(color: sem.textPrimary))),
                if (_needsReload)
                  TextButton(
                      onPressed: _saving ? null : _reloadConnected,
                      child: const Text('Check saved profile')),
                const SizedBox(height: 12),
              ],
              AbsorbPointer(
                  absorbing: _saving,
                  child: Column(children: [
                    _buildProfileIntro(sem),
                    const SizedBox(height: 20),
                    _sectionCard(
                      sem: sem,
                      title: 'About you',
                      subtitle: 'What property owners see on your profile',
                      icon: Icons.person_outline,
                      children: [
                        _buildAvatarSection(sem),
                        const SizedBox(height: 20),
                        _validatedField(
                          label: 'Display name',
                          controller: _nameCtrl,
                          hint: 'e.g. Aina Cleaning Services',
                          icon: Icons.person_outline,
                          sem: sem,
                          validator: _validateName,
                          maxLength: 60,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(60)
                          ],
                        ),
                        const SizedBox(height: 12),
                        _bioField(sem),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      sem: sem,
                      title: 'Services & rate',
                      subtitle: _connected
                          ? 'Your services and booking rates'
                          : 'Choose what you offer and set your hourly rate',
                      icon: Icons.cleaning_services_outlined,
                      children: [
                        _buildServicesChips(sem),
                        const SizedBox(height: 16),
                        _validatedField(
                          label: 'Hourly rate',
                          controller: _rateCtrl,
                          hint: '80',
                          icon: Icons.payments_outlined,
                          sem: sem,
                          validator: _validateRate,
                          keyboardType: _connected
                              ? const TextInputType.numberWithOptions(
                                  decimal: true)
                              : TextInputType.number,
                          suffix: 'RM/hr',
                          inputFormatters: _connected
                              ? null
                              : [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(4),
                                ],
                        ),
                        const SizedBox(height: 6),
                        _hint('Select at least one service.', sem),
                        if (_connected) ...[
                          const SizedBox(height: 14),
                          _validatedField(
                              label: '8-hour daily rate',
                              controller: _dailyCtrl,
                              hint: 'e.g. 480.00',
                              icon: Icons.payments_outlined,
                              sem: sem,
                              validator: (v) => _validateConnectedRate(
                                  (v ?? '').trim(), _rateCtrl.text.trim()),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              suffix: 'RM / 8 hours'),
                          const SizedBox(height: 8),
                          _hint(
                              'At least one rate is required. The daily rate applies only to an 8-hour booking. Existing booking quotes do not change.',
                              sem),
                          const SizedBox(height: 14),
                          _validatedField(
                              label: 'Service area',
                              controller: _areaCtrl,
                              hint: 'e.g. Setapak, Kuala Lumpur',
                              icon: Icons.location_on_outlined,
                              sem: sem,
                              validator: (v) => (v ?? '').trim().isEmpty ||
                                      (v ?? '').trim().length > 200
                                  ? 'Enter a service area (max 200 characters)'
                                  : null),
                          const SizedBox(height: 14),
                          _validatedField(
                              label: 'Private starting address',
                              controller: _originCtrl,
                              hint: 'e.g. 12 Jalan Example, Kuala Lumpur',
                              icon: Icons.lock_outline,
                              sem: sem,
                              validator: (v) => (v ?? '').trim().isEmpty ||
                                      (v ?? '').trim().length > 500
                                  ? 'Enter your starting address (max 500 characters)'
                                  : null),
                          const SizedBox(height: 6),
                          _hint(
                              'Private: not exposed in the provider directory.',
                              sem),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      sem: sem,
                      title: 'Working hours',
                      subtitle: 'Your default start and end time',
                      icon: Icons.schedule_outlined,
                      children: [
                        if (_connected) ...[
                          Text(_server!.weeklySummary,
                              style: TextStyle(
                                  color: sem.textPrimary, height: 1.5)),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                              onPressed: _manageConnectedAvailability,
                              icon: const Icon(Icons.schedule),
                              label: const Text('Manage weekly availability')),
                          _hint(
                              'Times are in Malaysia time (MYT). Saving your profile does not replace working slots.',
                              sem),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: _buildTimePicker('Start', _workStart,
                                    () => _pickTime(isStart: true), sem),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildTimePicker('End', _workEnd,
                                    () => _pickTime(isStart: false), sem),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _hint(
                            'Changing these hours replaces the slots on each active weekday. Use My schedule for different slots or unavailable dates.',
                            sem,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      sem: sem,
                      title: 'Contact & privacy',
                      subtitle: 'Keep your contact details up to date',
                      icon: Icons.contact_phone_outlined,
                      children: [
                        _validatedField(
                          label: 'Phone',
                          controller: _phoneCtrl,
                          hint: '+60 12 345 6789',
                          icon: Icons.phone_outlined,
                          sem: sem,
                          validator: _validatePhone,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 8),
                        _hint('Example: +60 12-345 6789', sem),
                        const SizedBox(height: 12),
                        _validatedField(
                          label: 'Email',
                          controller: _emailCtrl,
                          hint: 'name@example.com',
                          icon: Icons.email_outlined,
                          sem: sem,
                          validator: _validateEmail,
                          keyboardType: TextInputType.emailAddress,
                          readOnly: _connected,
                        ),
                        if (_connected) ...[
                          const SizedBox(height: 6),
                          _hint(
                              'This is your sign-in email. Changing it requires a separate verified email-change flow.',
                              sem)
                        ],
                        const SizedBox(height: 16),
                        _buildPrivacyToggle(sem),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildVerificationCard(sem),
                  ])),
            ]),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: sem.surface,
              border: Border(
                top: BorderSide(color: sem.border, width: 1),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: _saving ||
                        _needsReload ||
                        !_isDirty ||
                        (_connected && widget.canEditConnected?.call() != true)
                    ? null
                    : _save,
                icon: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary),
                      )
                    : const Icon(Icons.check),
                label: Text(
                  _saving ? 'Saving...' : 'Save changes',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  disabledBackgroundColor: sem.surfaceAlt,
                  disabledForegroundColor: sem.textTertiary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(String text, SemanticColors sem) => Text(
        text,
        style: TextStyle(fontSize: 12, height: 1.4, color: sem.textSecondary),
      );

  Widget _buildProfileIntro(SemanticColors sem) {
    final color = _avatarColors[_avatarColorIndex % _avatarColors.length];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white54, width: 2),
              image: _avatarImage == null
                  ? null
                  : DecorationImage(
                      image: kIsWeb
                          ? NetworkImage(_avatarImage!.path) as ImageProvider
                          : FileImage(File(_avatarImage!.path)),
                      fit: BoxFit.cover,
                    ),
            ),
            child: _avatarImage != null
                ? null
                : Center(
                    child: Text(
                      _nameCtrl.text.trim().isEmpty
                          ? '?'
                          : _nameCtrl.text.trim()[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _connected ? 'YOUR PROVIDER PROFILE' : 'PUBLIC PROFILE',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _nameCtrl.text.trim().isEmpty
                      ? 'Your name'
                      : _nameCtrl.text.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      widget.provider.isVerified
                          ? Icons.verified_rounded
                          : Icons.info_outline_rounded,
                      color: Colors.white70,
                      size: 15,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        _connected
                            ? _server!.approvalLabel
                            : widget.provider.isVerified
                                ? 'Verified provider'
                                : 'Verification pending',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required SemanticColors sem,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    // A clear, shared title band separates each category from its white body.
    final headerColor = Theme.of(context).brightness == Brightness.dark
        ? sem.primarySurface
        : sem.primaryBorder;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: sem.surface,
        border: Border.all(color: sem.border.withOpacity(0.8)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: ValueKey('profile-section-header-$title'),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
            color: headerColor,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: sem.surface.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppTheme.accent(context), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: sem.textPrimary,
                          )),
                      Text(subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: sem.textSecondary,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  // Avatar section ----------------------------------------------------------
  Widget _buildAvatarSection(SemanticColors sem) {
    final hasImage = _avatarImage != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profile appearance',
                    style: TextStyle(
                      color: sem.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasImage ? 'Photo preview selected' : 'Avatar color',
                    style: TextStyle(color: sem.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(
                () => _appearanceExpanded = !_appearanceExpanded,
              ),
              icon: Icon(
                _appearanceExpanded ? Icons.expand_less : Icons.tune,
                size: 17,
              ),
              label: Text(_appearanceExpanded ? 'Done' : 'Customize'),
            ),
          ],
        ),
        if (_appearanceExpanded) ...[
          const SizedBox(height: 14),
          _hint('Choose an avatar color', sem),
          const SizedBox(height: 8),
          _buildColorPicker(),
          const SizedBox(height: 10),
          if (!_connected) TextButton.icon(
            onPressed: _pickAvatar,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
            label: Text(_connected
                ? 'Photo upload not connected'
                : hasImage
                    ? 'Change photo'
                    : 'Preview photo'),
          ),
          if (hasImage)
            TextButton.icon(
              onPressed: _clearAvatarImage,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Remove photo preview'),
            ),
          _hint(
              _connected
                  ? 'Your avatar colour is saved with your profile.'
                  : 'Color is saved. Photo preview is not saved yet.',
              sem),
        ],
      ],
    );
  }

  // Validated text field -----------------------------------------------------
  Widget _validatedField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required SemanticColors sem,
    required String? Function(String?)? validator,
    TextInputType? keyboardType,
    String? suffix,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: sem.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 7),
        TextFormField(
          key: ValueKey('profile-$label'),
          readOnly: readOnly,
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 19),
            suffixText: suffix,
            counterText: '',
            filled: true,
            fillColor: sem.surfaceAlt,
          ),
        ),
      ],
    );
  }

  // Bio with character counter ----------------------------------------------
  Widget _bioField(SemanticColors sem) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('About your service',
            style: TextStyle(
                color: sem.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 7),
        TextFormField(
          controller: _bioCtrl,
          validator: _validateBio,
          maxLines: 3,
          maxLength: _bioMaxLength,
          decoration: InputDecoration(
            hintText: 'Tell owners about your service...',
            filled: true,
            fillColor: sem.surfaceAlt,
          ),
          buildCounter: (context,
              {required currentLength, required isFocused, maxLength}) {
            return Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Text(
                '$currentLength / $maxLength',
                style: TextStyle(
                  fontSize: 11,
                  color: currentLength > (maxLength ?? 0) * 0.9
                      ? Theme.of(context).colorScheme.error
                      : sem.textTertiary,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // Services chips ----------------------------------------------------------
  Widget _buildServicesChips(SemanticColors sem) {
    final catalog = _connected
        ? _server!.services
            .map((s) => <String, String>{
                  'id': s['id'] as String,
                  'label': s['name'] as String
                })
            .toList()
        : _allServices;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: catalog.map((s) {
        final id = s['id']!;
        final label = s['label']!;
        final selected = _services.contains(id);
        return FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: (v) {
            Haptics.light();
            setState(() {
              if (v) {
                if (!_services.contains(id)) _services.add(id);
              } else {
                _services.remove(id);
              }
            });
          },
          selectedColor: sem.secondarySurface,
          backgroundColor: sem.surfaceAlt,
          side: BorderSide(
            color: selected ? sem.secondaryBorder : sem.border,
          ),
          labelStyle: TextStyle(
            fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
            color: selected
                ? Theme.of(context).colorScheme.secondary
                : sem.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          checkmarkColor: Theme.of(context).colorScheme.secondary,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        );
      }).toList(),
    );
  }

  // Time picker field -------------------------------------------------------
  Widget _buildTimePicker(
      String label, TimeOfDay value, VoidCallback onTap, SemanticColors sem) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: sem.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sem.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: sem.textSecondary)),
            Text(
              timeSlotLabel(timeOfDayMinutes(value)),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // Color picker ------------------------------------------------------------
  Widget _buildColorPicker() {
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: List.generate(_avatarColors.length, (i) {
        final color = _avatarColors[i];
        final selected = _avatarColorIndex == i;
        return Semantics(
          label: 'Avatar color ${i + 1}',
          selected: selected,
          button: true,
          child: GestureDetector(
            onTap: () {
              Haptics.light();
              setState(() => _avatarColorIndex = i);
            },
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 3,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                  : null,
            ),
          ),
        );
      }),
    );
  }

  // Privacy toggle ----------------------------------------------------------
  Widget _buildPrivacyToggle(SemanticColors sem) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      decoration: BoxDecoration(
        color: sem.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sem.border),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 20, color: sem.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Show phone to owners',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  _connected
                      ? (_showPhoneToOwners
                          ? 'Only owners of Accepted or In Progress bookings can retrieve your number.'
                          : 'Phone sharing is off. Booking chat remains available.')
                      : _showPhoneToOwners
                          ? 'Owners see your phone and can call you.'
                          : 'Phone hidden. Owners can only contact via in-app chat.',
                  style: TextStyle(fontSize: 12, color: sem.textSecondary),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _showPhoneToOwners,
            onChanged: (v) {
              Haptics.light();
              setState(() => _showPhoneToOwners = v);
            },
          ),
        ],
      ),
    );
  }

  // Verification card -------------------------------------------------------
  Widget _buildVerificationCard(SemanticColors sem) {
    final p = widget.provider;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sem.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sem.border),
      ),
      child: Row(
        children: [
          Icon(
            p.isVerified ? Icons.verified : Icons.info_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _connected
                  ? '${_server!.approvalLabel}. Approval is managed by the platform and cannot be changed here.'
                  : p.isVerified
                      ? 'Verified provider. Owners see a verified badge on your profile.'
                      : 'Not verified yet. Contact support to start verification.',
              style: TextStyle(fontSize: 12, color: sem.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
