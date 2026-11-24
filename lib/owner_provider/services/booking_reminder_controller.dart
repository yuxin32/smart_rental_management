import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'booking_reminder.dart';
import 'android_booking_reminder_platform.dart';
import 'backend/cursor_feed.dart';
import 'backend/supabase_backend_provider.dart';
import 'backend/supabase_reminder_source.dart';

/// Local, account/project-scoped alarms, reconciled from fresh server records.
/// Remote changes while this phone is offline require a later foreground sync.
class BookingReminderController extends ChangeNotifier {
  BookingReminderController(
      {required this.platform,
      required this.read,
      required this.watch,
      DateTime Function()? now})
      : _now = now ?? DateTime.now;
  factory BookingReminderController.connected(SupabaseBackendProvider backend) {
    final source = SupabaseReminderSource(backend.client);
    return BookingReminderController(
        platform: AndroidBookingReminderPlatform(),
        read: source.read,
        watch: source.watch);
  }
  final BookingReminderPlatform platform;
  final Future<List<ReminderBooking>> Function(String, DateTime) read;
  final Stream<PageChange> Function(String) watch;
  final DateTime Function() _now;
  String? _actor, _stamp;
  int _epoch = 0, _version = 0;
  bool _disposed = false,
      _active = true,
      _initialized = false,
      _inFlight = false,
      _again = false;
  bool ready = false,
      enabled = true,
      dayBefore = false,
      permissionGranted = false;
  bool syncing = false, failed = false, limited = false;
  DateTime? lastSynced;
  Map<String, dynamic>? _tap;
  Future<void> _tail = Future.value();
  StreamSubscription<PageChange>? _subscription;
  Timer? _debounce, _periodic;
  bool get supported => platform.supported;
  bool get accountBound => _actor != null;
  bool get _canSync =>
      !_disposed &&
      _active &&
      ready &&
      supported &&
      enabled &&
      permissionGranted &&
      _actor != null;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _valid(int epoch) => !_disposed && epoch == _epoch;
  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    await platform.initialize((payload) {
      final parsed = BookingReminderPlan.readPayload(payload);
      if (parsed != null) {
        _tap = parsed;
        _emit();
      }
    });
    _initialized = true;
  }

  Future<void> _cancelOwned(SharedPreferences store) async {
    final ids = (store.getStringList('reminders:v1:ids') ?? [])
        .map(int.tryParse)
        .whereType<int>()
        .where((id) => id > 0 && id <= 0x7fffffff)
        .toSet();
    for (final pending in await platform.pending()) {
      if (BookingReminderPlan.readPayload(pending.payload) != null)
        ids.add(pending.id);
    }
    for (final id in ids) {
      await platform.cancel(id);
    }
    if (!await store.setStringList('reminders:v1:ids', []))
      throw StateError('Reminder cleanup not saved.');
    if (!await store.remove('reminders:v1:payloads'))
      throw StateError('Reminder cleanup not saved.');
  }

  Map<int, String?> _savedPayloads(SharedPreferences store) {
    try {
      final raw = jsonDecode(store.getString('reminders:v1:payloads') ?? '{}');
      if (raw is! Map<String, dynamic>) return {};
      return {
        for (final entry in raw.entries)
          if (int.tryParse(entry.key) != null &&
              entry.value is String &&
              BookingReminderPlan.readPayload(entry.value as String) != null)
            int.parse(entry.key): entry.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _savePayloads(
      SharedPreferences store, Map<int, String?> values) async {
    if (!await store.setString(
        'reminders:v1:payloads',
        jsonEncode({
          for (final entry in values.entries) '${entry.key}': entry.value
        }))) {
      throw StateError('Reminder metadata not saved.');
    }
  }

  Future<void> bind({String? actor, String? project}) async {
    _projectFromStamp = project;
    final stamp = actor == null ? null : reminderDigest('$project:$actor');
    if (_actor == actor && _stamp == stamp && ready) return;
    final epoch = ++_epoch;
    ++_version;
    _actor = actor;
    _stamp = stamp;
    _stopWatch();
    ready = false;
    failed = false;
    syncing = false;
    lastSynced = null;
    limited = false;
    enabled = true;
    dayBefore = false;
    permissionGranted = false;
    _emit();
    if (!supported) {
      ready = true;
      _emit();
      return;
    }
    try {
      await _serial(() async {
        await _initialize();
        final store = await SharedPreferences.getInstance();
        if (!_valid(epoch)) return;
        if (stamp == null || store.getString('reminders:v1:actor') != stamp) {
          await _cancelOwned(store);
        }
        if (!_valid(epoch)) return;
        if (stamp == null) {
          if (!await store.remove('reminders:v1:actor'))
            throw StateError('Reminder cleanup not saved.');
          ready = true;
          _emit();
          return;
        }
        if (!await store.setString('reminders:v1:actor', stamp))
          throw StateError('Reminder account not saved.');
        final allowed = await platform.allowed();
        if (!_valid(epoch)) return;
        enabled = store.getBool('reminders:$stamp:enabled') ?? true;
        dayBefore = store.getBool('reminders:$stamp:dayBefore') ?? false;
        permissionGranted = allowed;
        ready = true;
        if (!enabled) await _cancelOwned(store);
        if (!_valid(epoch)) return;
        if (_tap != null && _tap!['actor'] != stamp) _tap = null;
        _emit();
      });
      if (_valid(epoch)) {
        _listen();
        await refresh();
      }
    } catch (_) {
      if (_valid(epoch)) {
        failed = true;
        ready = false;
        _emit();
      }
    }
  }

  void _stopWatch() {
    final previous = _subscription;
    _subscription = null;
    unawaited(
        previous?.cancel().catchError((Object _) {}) ?? Future<void>.value());
    _debounce?.cancel();
    _periodic?.cancel();
  }

  void _listen() {
    if (!_canSync || _subscription != null) return;
    final epoch = _epoch;
    _subscription = watch(_actor!).listen((change) {
      if (!_valid(epoch) || !_canSync) return;
      if (change.id != null &&
          (change.kind == PageChangeKind.update ||
              change.kind == PageChangeKind.remove)) {
        unawaited(_cancelChanged(change.id!, epoch));
      }
      _debounce?.cancel();
      _debounce =
          Timer(const Duration(milliseconds: 350), () => unawaited(refresh()));
    }, onError: (Object _) {
      if (_valid(epoch)) {
        failed = true;
        _emit();
      }
    });
    _periodic = Timer.periodic(
        const Duration(minutes: 15), (_) => unawaited(refresh()));
  }

  Future<void> _cancelChanged(String id, int epoch) async {
    try {
      await _serial(() async {
        if (!_valid(epoch)) return;
        final hash = reminderDigest(id);
        final store = await SharedPreferences.getInstance();
        final known = {
          ..._savedPayloads(store),
          for (final pending in await platform.pending())
            pending.id: pending.payload
        };
        for (final entry in known.entries) {
          if (!_valid(epoch)) return;
          final payload = BookingReminderPlan.readPayload(entry.value);
          if (payload?['actor'] == _stamp && payload?['booking'] == hash) {
            await platform.cancel(entry.key);
          }
        }
      });
    } catch (_) {
      if (_valid(epoch)) {
        failed = true;
        _emit();
      }
    }
  }

  void setActive(bool active) {
    _active = active;
    if (!active) {
      _stopWatch();
      return;
    }
    if (_actor != null && supported) unawaited(checkPermission());
  }

  Future<void> checkPermission() async {
    if (_disposed || !supported || _actor == null) return;
    if (!ready) {
      await bind(actor: _actor, project: _projectFromStamp);
      return;
    }
    final epoch = _epoch;
    try {
      final allowed = await _serial(() => platform.allowed());
      if (!_valid(epoch)) return;
      permissionGranted = allowed;
      if (!allowed)
        _stopWatch();
      else
        _listen();
      _emit();
      await refresh();
    } catch (_) {
      if (_valid(epoch)) {
        failed = true;
        _emit();
      }
    }
  }

  // Retain the original project value; a stamp is never an input project ID.
  String? _projectFromStamp;
  Future<void> bindAccount(String? actor, String? project) async {
    _projectFromStamp = project;
    await bind(actor: actor, project: project);
  }

  Future<void> retry() async {
    _stopWatch();
    if (!ready) {
      await bind(actor: _actor, project: _projectFromStamp);
    } else {
      await checkPermission();
    }
  }

  Future<bool> allowNotifications() async {
    if (_actor == null || !supported) return false;
    final epoch = _epoch;
    try {
      final allowed = await _serial(() async {
        await _initialize();
        return platform.requestPermission();
      });
      if (!_valid(epoch)) return false;
      permissionGranted = allowed;
      _emit();
      if (allowed) {
        _listen();
        await refresh();
      }
      return allowed;
    } catch (_) {
      if (_valid(epoch)) {
        failed = true;
        _emit();
      }
      return false;
    }
  }

  Future<bool> save({bool? enable, bool? oneDayBefore}) async {
    if (_actor == null || !ready || !supported) return false;
    final epoch = _epoch, stamp = _stamp!;
    try {
      await _serial(() async {
        final store = await SharedPreferences.getInstance();
        if (!_valid(epoch)) return;
        if (enable != null &&
            !await store.setBool('reminders:$stamp:enabled', enable))
          throw StateError('Preference not saved.');
        if (oneDayBefore != null &&
            !await store.setBool('reminders:$stamp:dayBefore', oneDayBefore))
          throw StateError('Preference not saved.');
        if (!_valid(epoch)) return;
        if (enable != null) enabled = enable;
        if (oneDayBefore != null) dayBefore = oneDayBefore;
        if (!enabled) {
          _stopWatch();
          await _cancelOwned(store);
        }
        if (_valid(epoch)) {
          failed = false;
          _emit();
        }
      });
      if (!_valid(epoch)) return false;
      if (enabled) {
        _listen();
        await refresh();
      }
      return true;
    } catch (_) {
      if (_valid(epoch)) {
        failed = true;
        _emit();
      }
      return false;
    }
  }

  Future<void> refresh() async {
    if (!_canSync) return;
    final epoch = _epoch, version = ++_version;
    if (_inFlight) {
      _again = true;
      return;
    }
    _inFlight = true;
    syncing = true;
    _emit();
    try {
      final bookings = await read(_actor!, _now().toUtc())
          .timeout(const Duration(seconds: 25));
      if (!_valid(epoch) || version != _version || !_canSync) return;
      final sorted = bookings.toList()
        ..sort((a, b) => a.startUtc.compareTo(b.startUtc));
      final plans = BookingReminderPlan.build(
          actorStamp: _stamp!,
          bookings: sorted.take(100),
          now: _now(),
          dayBefore: dayBefore);
      await _serial(() async {
        if (!_valid(epoch) || version != _version || !_canSync) return;
        final store = await SharedPreferences.getInstance();
        final pending = await platform.pending();
        if (!_valid(epoch) || version != _version || !_canSync) return;
        final existing = {
          for (final item in pending)
            if (BookingReminderPlan.readPayload(item.payload) != null)
              item.id: item.payload
        };
        final oldIds = (store.getStringList('reminders:v1:ids') ?? [])
            .map(int.tryParse)
            .whereType<int>()
            .toSet();
        final target = {for (final plan in plans) plan.id: plan};
        final allIds = {...oldIds, ...existing.keys, ...target.keys};
        await _savePayloads(store, {
          ..._savedPayloads(store),
          ...existing,
          for (final plan in plans) plan.id: plan.payload
        });
        if (!await store.setStringList(
            'reminders:v1:ids', allIds.map((id) => '$id').toList()))
          throw StateError('Reminder IDs not saved.');
        for (final id in allIds) {
          if (!_valid(epoch) || version != _version || !_canSync) return;
          if (!target.containsKey(id) || existing[id] != target[id]!.payload)
            await platform.cancel(id);
        }
        for (final plan in plans) {
          if (!_valid(epoch) || version != _version || !_canSync) return;
          if (existing[plan.id] != plan.payload) await platform.schedule(plan);
        }
        if (!_valid(epoch) || version != _version || !_canSync) return;
        if (!await store.setStringList(
            'reminders:v1:ids', target.keys.map((id) => '$id').toList()))
          throw StateError('Reminder IDs not saved.');
        await _savePayloads(
            store, {for (final plan in plans) plan.id: plan.payload});
        limited = bookings.length > 100;
        failed = false;
        lastSynced = _now().toUtc();
      });
    } catch (_) {
      if (_valid(epoch)) {
        failed = true;
      }
    } finally {
      _inFlight = false;
      if (_valid(epoch)) {
        syncing = false;
        _emit();
      }
      final again = _again;
      _again = false;
      if (again && _canSync) unawaited(refresh());
    }
  }

  DateTime? takeOpenRequest() {
    if (!accountBound || !ready || _tap?['actor'] != _stamp) return null;
    final date = DateTime.parse(_tap!['start'] as String)
        .toUtc()
        .add(const Duration(hours: 8));
    _tap = null;
    return DateTime.utc(date.year, date.month, date.day);
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    ++_version;
    _stopWatch();
    super.dispose();
  }
}
