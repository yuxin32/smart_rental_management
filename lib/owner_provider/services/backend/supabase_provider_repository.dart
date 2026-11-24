import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

import '../../features/availability/domain/provider_setup.dart';
import 'authenticated_memory_cache.dart';
import 'reference_data.dart';
import 'provider_profile_snapshot.dart';
import 'session_snapshot_cache.dart';

/// Provider-managed profile and availability; database triggers protect
/// confirmed future bookings from an incompatible availability edit.
class SupabaseProviderRepository {
  const SupabaseProviderRepository(this.client, {this.cache, this.snapshots});
  final SupabaseClient client;
  final AuthenticatedMemoryCache? cache;
  final SessionSnapshotCache? snapshots;
  Future<T> _write<T>(Future<T> Function() action) =>
      snapshots?.write(action) ?? action();
  ProviderSetupData? get cachedSetup =>
      snapshots?.peek<ProviderSetupData>('provider:setup')?.value;

  Future<ProviderProfileSnapshot> myProfile() async {
    final actor = _providerId;
    final response = await client.rpc('my_provider_profile_with_location');
    if (_providerId != actor) throw StateError('Session changed.');
    return ProviderProfileSnapshot.parse(
        Map<String, dynamic>.from(response as Map), actor);
  }

  Future<ProviderProfileSnapshot> saveMyProfile(
      ProviderProfileDraft draft, ProviderProfileSnapshot base) async {
    final actor = _providerId;
    if (base.id != actor) throw StateError('Session changed.');
    final response = await _write(() async => await client.rpc(
            draft.coverageAreaIds.isEmpty
                ? 'save_my_provider_profile'
                : 'save_located_provider_profile',
            params: {
              'p_input': draft.json,
              'p_expected_revision': base.revision,
              'p_expected_contact': base.contact,
              if (draft.coverageAreaIds.isNotEmpty)
                'p_area_ids': draft.coverageAreaIds.toList(),
              if (draft.coverageAreaIds.isNotEmpty)
                'p_pin_link': draft.originPinLink.trim(),
            }));
    if (_providerId != actor) throw StateError('Session changed.');
    return ProviderProfileSnapshot.parse(
        Map<String, dynamic>.from(response as Map), actor);
  }

  String get _providerId =>
      client.auth.currentUser?.id ??
      (throw StateError('Sign in as a Cleaning Service Provider first.'));

  Future<Map<String, dynamic>?> profile() => client
      .from('provider_profile')
      .select()
      .eq('provider_id', _providerId)
      .maybeSingle();

  Future<ProviderSetupData> loadSetup() async {
    try {
      return await _loadSetup();
    } catch (e) {
      if (rejectsSnapshot(e)) snapshots?.clear();
      rethrow;
    }
  }

  Future<ProviderSetupData> _loadSetup() async {
    final actor = _providerId;
    final lease = snapshots?.lease();
    final results = await Future.wait<Object>([
      _serviceTypes(),
      _capabilities(),
      weeklyState(),
      unavailableDates(),
    ]);
    if (_providerId != actor) throw StateError('Session changed.');
    if (lease != null && !snapshots!.valid(lease)) {
      throw StateError(
          'Availability changed during refresh. Retry to verify it.');
    }
    final weekly = results[2] as ProviderWeeklyState;
    final data = ProviderSetupData(
      weeklyState: weekly,
      services: List.unmodifiable((results[0] as List<Map<String, dynamic>>)
          .map(
            (row) => ProviderServiceItem(
              id: row['service_type_id'] as String,
              name: row['name'] as String,
            ),
          )
          .toList(growable: false)),
      selectedServiceIds: Set.unmodifiable(
          (results[1] as List<Map<String, dynamic>>)
              .map((row) => row['service_type_id'] as String)),
      slots: weekly.slots,
      unavailableDates: Set.unmodifiable(
          (results[3] as List<Map<String, dynamic>>)
              .map((row) => row['unavailable_on'] as String)),
    );
    if (lease != null)
      snapshots!.put('provider:setup', data,
          lease: lease,
          bytes: utf8
                  .encode(jsonEncode([results[0], results[1], results[3]]))
                  .length +
              weekly.slots.length * 160 +
              weekly.required.length * 96 +
              1024);
    return data;
  }

  Future<List<Map<String, dynamic>>> _serviceTypes() =>
      readServiceTypes(client, cache);

  Future<ProviderWeeklyState> weeklyState() async {
    final actor = _providerId;
    final lease = snapshots?.lease();
    final response = await client.rpc('my_provider_weekly_hours');
    if (_providerId != actor || lease != null && !snapshots!.valid(lease)) {
      throw StateError('Session or working hours changed.');
    }
    return ProviderWeeklyState.parse(
        Map<String, dynamic>.from(response as Map), actor);
  }

  Future<ProviderWeeklyState> replaceWeeklyHours(
      Map<int, List<ProviderWorkingRange>> days,
      ProviderWeeklyState expected) async {
    final actor = _providerId;
    if (expected.providerId != actor || days.isEmpty || days.length > 7) {
      throw StateError('Check your working hours before saving.');
    }
    for (final entry in days.entries) {
      final error = expected.validateDay(entry.key, entry.value);
      if (error != null) throw ArgumentError(error);
    }
    final response = await _write(
        () async => await client.rpc('replace_my_weekly_hours', params: {
              'p_expected_revision': expected.revision,
              'p_changes': days.entries
                  .map((entry) => {
                        'weekday': entry.key,
                        'slots':
                            entry.value.map((range) => range.json).toList(),
                      })
                  .toList(),
            }));
    if (_providerId != actor) throw StateError('Session changed.');
    return ProviderWeeklyState.parse(
        Map<String, dynamic>.from(response as Map), actor);
  }

  Future<List<Map<String, dynamic>>> _capabilities() async {
    final rows = await client
        .from('provider_capability')
        .select('service_type_id')
        .eq('provider_id', _providerId);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> replaceCapabilities(Set<String> serviceTypeIds) async {
    if (serviceTypeIds.isEmpty) {
      throw ArgumentError('Select at least one cleaning service.');
    }
    await _write(() async => await client.rpc(
          'replace_provider_capabilities',
          params: {
            'p_service_type_ids': serviceTypeIds.toList(growable: false),
          },
        ));
  }

  Future<void> saveProfile({
    required String serviceArea,
    required String serviceOriginAddress,
    double? hourlyRate,
    double? dailyRate,
    String? bio,
  }) async {
    if (serviceArea.trim().isEmpty ||
        serviceOriginAddress.trim().isEmpty ||
        (hourlyRate == null && dailyRate == null) ||
        (hourlyRate != null && (!hourlyRate.isFinite || hourlyRate <= 0)) ||
        (dailyRate != null && (!dailyRate.isFinite || dailyRate <= 0))) {
      throw ArgumentError(
        'Service area, origin and a positive hourly or daily rate are required.',
      );
    }
    final existing = await profile();
    final editable = {
      'service_area': serviceArea.trim(),
      'service_origin_address': serviceOriginAddress.trim(),
      'hourly_rate': hourlyRate,
      'daily_rate': dailyRate,
      'bio': bio?.trim(),
    };
    if (existing == null) {
      await _write(() async => await client.from('provider_profile').insert({
            'provider_id': _providerId,
            ...editable,
          }));
    } else {
      await _write(() async => await client
          .from('provider_profile')
          .update(editable)
          .eq('provider_id', _providerId));
    }
  }

  Future<List<Map<String, dynamic>>> weeklySlots() async {
    final rows = await client
        .from('provider_weekly_slot')
        .select()
        .eq('provider_id', _providerId)
        .order('weekday');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> unavailableDates() async {
    final rows = await client
        .from('provider_unavailable_date')
        .select()
        .eq('provider_id', _providerId)
        .order('unavailable_on');
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Query minimal own-account data on every opening, independent of Inbox or
  /// cached setup pages. Continue to an empty keyset page, even if the Data API
  /// caps responses below our requested limit. Never return a partial calendar.
  Future<ProviderDayOffConstraints> dayOffConstraints(
    DateTime firstDate,
    DateTime lastDate, {
    DateTime? now,
  }) async {
    final actor = _providerId;
    final lease = snapshots?.lease();
    final first = DateTime.utc(firstDate.year, firstDate.month, firstDate.day);
    final last = DateTime.utc(lastDate.year, lastDate.month, lastDate.day);
    if (last.isBefore(first) || last.difference(first).inDays > 733) {
      throw ArgumentError('Choose a date range of at most two years.');
    }
    final checkedAt = (now ?? DateTime.now()).toUtc();
    final endUtc =
        last.add(const Duration(days: 1)).subtract(const Duration(hours: 8));
    void checkSession() {
      if (_providerId != actor || lease != null && !snapshots!.valid(lease)) {
        throw StateError('Session or availability changed. Check dates again.');
      }
    }

    final days = <String>{};
    String? after;
    var complete = false;
    for (var page = 0; page < 64; page++) {
      var query = client
          .from('booking')
          .select(
              'booking_id,provider_id,current_status,requested_start_at,requested_end_at')
          .eq('provider_id', actor)
          .inFilter('current_status', ['Accepted', 'In Progress'])
          .gt('requested_end_at', checkedAt.toIso8601String())
          .lt('requested_start_at', endUtc.toIso8601String());
      if (after != null) query = query.gt('booking_id', after);
      final rows = List<Map<String, dynamic>>.from(
          await query.order('booking_id').limit(128));
      checkSession();
      if (rows.isEmpty) {
        complete = true;
        break;
      }
      for (final row in rows) {
        final id = row['booking_id'];
        final startRaw = row['requested_start_at'];
        final endRaw = row['requested_end_at'];
        if (id is! String ||
            !RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
                .hasMatch(id) ||
            after != null && id.compareTo(after) <= 0 ||
            row['provider_id'] != actor ||
            !{'Accepted', 'In Progress'}.contains(row['current_status']) ||
            startRaw is! String ||
            endRaw is! String ||
            !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(startRaw) ||
            !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(endRaw)) {
          throw const FormatException('Could not verify booking dates.');
        }
        final start = DateTime.parse(startRaw).toUtc();
        final end = DateTime.parse(endRaw).toUtc();
        if (!end.isAfter(start) ||
            !end.isAfter(checkedAt) ||
            !start.isBefore(endUtc)) {
          throw const FormatException('Could not verify booking dates.');
        }
        final wall = start.add(const Duration(hours: 8));
        final day = ProviderDayOffConstraints.dateKey(wall);
        if (day.compareTo(ProviderDayOffConstraints.dateKey(first)) >= 0)
          days.add(day);
        after = id;
      }
    }
    if (!complete)
      throw StateError('Could not verify the complete date range.');
    final firstKey = ProviderDayOffConstraints.dateKey(first);
    final lastKey = ProviderDayOffConstraints.dateKey(last);
    final response = await client
        .from('provider_unavailable_date')
        .select('provider_id,unavailable_on')
        .eq('provider_id', actor)
        .gte('unavailable_on', firstKey)
        .lte('unavailable_on', lastKey)
        .count(CountOption.exact);
    final blocked = List<Map<String, dynamic>>.from(response.data);
    checkSession();
    if (response.count != blocked.length) {
      throw StateError('Could not verify all existing days off.');
    }
    final unavailable = <String>{};
    for (final row in blocked) {
      final day = row['unavailable_on'];
      if (row['provider_id'] != actor ||
          day is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) ||
          day.compareTo(firstKey) < 0 ||
          day.compareTo(lastKey) > 0 ||
          !unavailable.add(day)) {
        throw const FormatException('Could not verify days off.');
      }
    }
    return ProviderDayOffConstraints(
        firstDate: firstDate,
        lastDate: lastDate,
        confirmedDates: Set.unmodifiable(days),
        unavailableDates: Set.unmodifiable(unavailable));
  }

  Future<void> addWeeklySlot({
    required int weekday,
    required String startTime,
    required String endTime,
  }) async {
    final start = ProviderSlotRules.parseDatabaseTime(startTime);
    final end = ProviderSlotRules.parseDatabaseTime(endTime);
    final error = ProviderSlotRules.validate(
      weekday: weekday,
      startMinute: start,
      endMinute: end,
      existing: const [],
    );
    if (error != null) throw ArgumentError(error);
    await _write(() async => await client.from('provider_weekly_slot').insert({
          'provider_id': _providerId,
          'weekday': weekday,
          'start_time': startTime,
          'end_time': endTime,
        }));
  }

  Future<void> removeWeeklySlot(String slotId) async {
    await _write(() async => await client
        .from('provider_weekly_slot')
        .delete()
        .eq('provider_id', _providerId)
        .eq('slot_id', slotId));
  }

  Future<void> addUnavailableDate(String yyyyMmDd) async {
    await _write(
        () async => await client.from('provider_unavailable_date').insert({
              'provider_id': _providerId,
              'unavailable_on': yyyyMmDd,
            }));
  }

  Future<void> removeUnavailableDate(String yyyyMmDd) async {
    await _write(() async => await client
        .from('provider_unavailable_date')
        .delete()
        .eq('provider_id', _providerId)
        .eq('unavailable_on', yyyyMmDd));
  }
}
