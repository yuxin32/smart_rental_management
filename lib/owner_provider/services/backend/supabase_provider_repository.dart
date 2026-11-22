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
    final response = await client.rpc('my_provider_profile');
    if (_providerId != actor) throw StateError('Session changed.');
    return ProviderProfileSnapshot.parse(
        Map<String, dynamic>.from(response as Map), actor);
  }

  Future<ProviderProfileSnapshot> saveMyProfile(
      ProviderProfileDraft draft, ProviderProfileSnapshot base) async {
    final actor = _providerId;
    if (base.id != actor) throw StateError('Session changed.');
    final response = await _write(
        () async => await client.rpc('save_my_provider_profile', params: {
              'p_input': draft.json,
              'p_expected_revision': base.revision,
              'p_expected_contact': base.contact
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
    final results = await Future.wait<List<Map<String, dynamic>>>([
      _serviceTypes(),
      _capabilities(),
      weeklySlots(),
      unavailableDates(),
    ]);
    if (_providerId != actor) throw StateError('Session changed.');
    if (lease != null && !snapshots!.valid(lease)) {
      throw StateError(
          'Availability changed during refresh. Retry to verify it.');
    }
    final data = ProviderSetupData(
      services: List.unmodifiable(results[0]
          .map(
            (row) => ProviderServiceItem(
              id: row['service_type_id'] as String,
              name: row['name'] as String,
            ),
          )
          .toList(growable: false)),
      selectedServiceIds: Set.unmodifiable(
          results[1].map((row) => row['service_type_id'] as String)),
      slots: List.unmodifiable(results[2]
          .map(
            (row) => ProviderWeeklySlotItem(
              id: row['slot_id'] as String,
              weekday: row['weekday'] as int,
              startMinute: ProviderSlotRules.parseDatabaseTime(
                row['start_time'] as String,
              ),
              endMinute: ProviderSlotRules.parseDatabaseTime(
                row['end_time'] as String,
              ),
            ),
          )
          .toList(growable: false)),
      unavailableDates: Set.unmodifiable(
          results[3].map((row) => row['unavailable_on'] as String)),
    );
    if (lease != null)
      snapshots!.put('provider:setup', data,
          lease: lease, bytes: utf8.encode(jsonEncode(results)).length + 512);
    return data;
  }

  Future<List<Map<String, dynamic>>> _serviceTypes() =>
      readServiceTypes(client, cache);

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
