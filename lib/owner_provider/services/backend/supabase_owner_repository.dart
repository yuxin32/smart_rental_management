import 'package:supabase_flutter/supabase_flutter.dart';
import 'authenticated_memory_cache.dart';
import 'reference_data.dart';
import 'session_snapshot_cache.dart';

/// Safe fields returned by the approved-provider directory RPC. The exact
/// service origin is intentionally not part of this owner-facing model.
class ApprovedProviderDirectoryItem {
  const ApprovedProviderDirectoryItem({
    required this.providerId,
    required this.serviceArea,
    required this.serviceTypeIds,
    this.bio,
    this.hourlyRate,
    this.dailyRate,
    this.ratingAverage,
    required this.completedJobCount,
  });

  final String providerId;
  final String serviceArea;
  final List<String> serviceTypeIds;
  final String? bio;
  final num? hourlyRate;
  final num? dailyRate;
  final num? ratingAverage;
  final int completedJobCount;

  factory ApprovedProviderDirectoryItem.fromJson(Map<String, dynamic> row) =>
      ApprovedProviderDirectoryItem(
        providerId: row['provider_id'] as String,
        serviceArea: row['service_area'] as String,
        serviceTypeIds: List<String>.from(row['service_type_ids'] as List),
        bio: row['bio'] as String?,
        hourlyRate: row['hourly_rate'] as num?,
        dailyRate: row['daily_rate'] as num?,
        ratingAverage: row['rating_average'] as num?,
        completedJobCount: row['completed_job_count'] as int,
      );
}

/// A Provider who passed request-specific mandatory checks at query time.
/// This is an eligibility result, not a distance/rating/workload score.
class EligibleProviderItem {
  const EligibleProviderItem({
    required this.providerId,
    required this.serviceArea,
    this.bio,
    this.hourlyRate,
    this.dailyRate,
    this.ratingAverage,
    required this.completedJobCount,
    required this.quoteBasis,
    required this.quotedAmount,
  });

  final String providerId;
  final String serviceArea;
  final String? bio;
  final num? hourlyRate;
  final num? dailyRate;
  final num? ratingAverage;
  final int completedJobCount;
  final String quoteBasis;
  final num quotedAmount;

  factory EligibleProviderItem.fromJson(Map<String, dynamic> row) =>
      EligibleProviderItem(
        providerId: row['provider_id'] as String,
        serviceArea: row['service_area'] as String,
        bio: row['bio'] as String?,
        hourlyRate: row['hourly_rate'] as num?,
        dailyRate: row['daily_rate'] as num?,
        ratingAverage: row['rating_average'] as num?,
        completedJobCount: row['completed_job_count'] as int,
        quoteBasis: row['quote_basis'] as String,
        quotedAmount: row['quoted_amount'] as num,
      );
}

class OwnerDashboardSnapshot {
  const OwnerDashboardSnapshot({
    required this.propertyCount,
    required this.pendingCount,
    required this.activeCount,
    required this.completedCount,
  });

  final int propertyCount;
  final int pendingCount;
  final int activeCount;
  final int completedCount;
}

/// Data is additionally restricted by the database's owner RLS policies.
class SupabaseOwnerRepository {
  const SupabaseOwnerRepository(this.client, {this.cache, this.snapshots});
  final SupabaseClient client;
  final AuthenticatedMemoryCache? cache;
  final SessionSnapshotCache? snapshots;
  Future<T> _write<T>(Future<T> Function() action) =>
      snapshots?.write(action) ?? action();

  String get _ownerId =>
      client.auth.currentUser?.id ??
      (throw StateError('Sign in as a Property Owner first.'));

  Future<List<ApprovedProviderDirectoryItem>>
      approvedProviderDirectory() async {
    // The RPC enforces approval and returns only public presentation fields.
    // Do not query provider_profile directly from an Owner session.
    final rows = await client.rpc('list_approved_provider_directory');
    return List<Map<String, dynamic>>.from(rows as List)
        .map(ApprovedProviderDirectoryItem.fromJson)
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> properties() async {
    final rows = await client
        .from('property')
        .select(
          'property_id,unit_name,building_name,address,bedrooms,size_sqft,cleaning_window_start,cleaning_window_end',
        )
        .eq('owner_id', _ownerId)
        .order('building_name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> serviceTypes({bool force = false}) =>
      readServiceTypes(client, cache, force: force);

  Future<List<EligibleProviderItem>> eligibleProviders({
    required String propertyId,
    required String serviceTypeId,
    required DateTime start,
    required DateTime end,
  }) async {
    if (!end.isAfter(start)) {
      throw ArgumentError('The booking end must be after the start.');
    }
    final rows = await client.rpc(
      'find_eligible_providers',
      params: {
        'p_property_id': propertyId,
        'p_service_type_id': serviceTypeId,
        'p_start_at': start.toUtc().toIso8601String(),
        'p_end_at': end.toUtc().toIso8601String(),
      },
    );
    return List<Map<String, dynamic>>.from(rows as List)
        .map(EligibleProviderItem.fromJson)
        .toList(growable: false);
  }

  Future<String> addProperty({
    required String unitName,
    required String buildingName,
    required String address,
    required int bedrooms,
    required int sizeSqft,
    required String cleaningWindowStart,
    required String cleaningWindowEnd,
  }) async {
    if (unitName.trim().isEmpty ||
        buildingName.trim().isEmpty ||
        address.trim().isEmpty ||
        bedrooms <= 0 ||
        sizeSqft <= 0 ||
        cleaningWindowStart.compareTo(cleaningWindowEnd) >= 0) {
      throw ArgumentError('Enter valid property details and cleaning window.');
    }
    final row = await _write(() async => await client
        .from('property')
        .insert({
          'owner_id': _ownerId,
          'unit_name': unitName.trim(),
          'building_name': buildingName.trim(),
          'address': address.trim(),
          'bedrooms': bedrooms,
          'size_sqft': sizeSqft,
          'cleaning_window_start': cleaningWindowStart,
          'cleaning_window_end': cleaningWindowEnd,
        })
        .select('property_id')
        .single());
    return row['property_id'] as String;
  }

  Future<void> updateProperty({
    required String propertyId,
    required String unitName,
    required String buildingName,
    required String address,
    required int bedrooms,
    required int sizeSqft,
    required String cleaningWindowStart,
    required String cleaningWindowEnd,
  }) async {
    if (unitName.trim().isEmpty ||
        buildingName.trim().isEmpty ||
        address.trim().isEmpty ||
        bedrooms <= 0 ||
        sizeSqft <= 0 ||
        cleaningWindowStart.compareTo(cleaningWindowEnd) >= 0) {
      throw ArgumentError('Enter valid property details and cleaning window.');
    }
    await _write(() async => await client
        .from('property')
        .update({
          'unit_name': unitName.trim(),
          'building_name': buildingName.trim(),
          'address': address.trim(),
          'bedrooms': bedrooms,
          'size_sqft': sizeSqft,
          'cleaning_window_start': cleaningWindowStart,
          'cleaning_window_end': cleaningWindowEnd,
        })
        .eq('property_id', propertyId)
        .eq('owner_id', _ownerId));
  }

  Future<OwnerDashboardSnapshot> dashboard() async {
    final result = Map<String, dynamic>.from(
      await client.rpc('owner_dashboard_summary') as Map,
    );
    return OwnerDashboardSnapshot(
      propertyCount: result['property_count'] as int,
      pendingCount: result['pending_count'] as int,
      activeCount: result['active_count'] as int,
      completedCount: result['completed_count'] as int,
    );
  }
}
