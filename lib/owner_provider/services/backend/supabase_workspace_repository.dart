import '../../presentation/workspace_text.dart';
import 'package:flutter/material.dart';
import 'supabase_backend_provider.dart';
import 'cursor_feed.dart';
import '../../models/demo_data.dart';
import 'workspace_binding.dart';

class SupabaseWorkspaceRepository {
  const SupabaseWorkspaceRepository(this.backend);
  final SupabaseBackendProvider backend;
  Future<Map<String, dynamic>> read(String rpc,
      {Map<String, dynamic>? params}) async {
    final actor = backend.client.auth.currentUser?.id;
    if (actor == null) throw StateError('Sign in required');
    final row = Map<String, dynamic>.from(
        await backend.client.rpc(rpc, params: params) as Map);
    if (backend.client.auth.currentUser?.id != actor)
      throw StateError('Session changed');
    if (row['actor_id'] != actor) throw const FormatException('Wrong account');
    return row;
  }

  Future<Map<String, dynamic>> properties(
      {PageCursor? before, String? asOf}) async {
    final row = await read('page_my_properties',
        params: {'p_before_at': before?.timestamp, 'p_before_id': before?.id});
    if (row['total_count'] is! int || (row['total_count'] as int) < 0)
      throw const FormatException('Invalid total');
    for (final item in List<Map<String, dynamic>>.from(row['items'] as List)) {
      propertyPresentation(item);
      for (final key in ['total', 'open', 'done']) {
        if (item[key] is! int || (item[key] as int) < 0)
          throw const FormatException('Invalid property counts');
      }
    }
    final portfolio = await read('my_owner_portfolio_summary');
    for (final key in [
      'property_count',
      'building_count',
      'size_sqft',
      'open',
      'done',
      'total'
    ]) {
      if (portfolio[key] is! int || (portfolio[key] as int) < 0)
        throw const FormatException('Invalid portfolio summary');
    }
    row['portfolio'] = portfolio;
    return row;
  }

  Future<Map<String, dynamic>> property(String id) async {
    final row = await read('my_property', params: {'p_property_id': id});
    propertyPresentation(row);
    if (row['property_id'] != id) throw const FormatException('Wrong property');
    return row;
  }

  Future<Map<String, dynamic>> propertyBookings(String id,
      {PageCursor? before, String? asOf}) async {
    final row = await read('page_my_property_bookings', params: {
      'p_property_id': id,
      'p_before_at': before?.timestamp,
      'p_before_id': before?.id
    });
    for (final item in List<Map<String, dynamic>>.from(row['items'] as List)) {
      if (item['property_id'] != id)
        throw const FormatException('Wrong property booking');
      WorkspaceBinding.projectBooking(item);
    }
    return row;
  }

  Future<Map<String, dynamic>> ownerProfile(
      {PageCursor? before, String? asOf}) async {
    final row = await read('my_owner_profile');
    if (row['revision'] is! int ||
        (row['revision'] as int) < 1 ||
        row['property_count'] is! int ||
        row['email'] is! String ||
        row['full_name'] != null && row['full_name'] is! String ||
        row['contact_number'] != null && row['contact_number'] is! String) {
      throw const FormatException('Invalid owner profile');
    }
    return row;
  }

  Future<void> saveOwner(Map<String, dynamic> input, int revision) =>
      backend.snapshots.write(() async {
        await read('save_my_owner_profile',
            params: {'p_input': input, 'p_revision': revision});
      });
  Future<void> saveProperty(
          String id, int revision, Map<String, dynamic> input) =>
      backend.snapshots.write(() async {
        final row = await read('save_my_property', params: {
          'p_property_id': id,
          'p_revision': revision,
          'p_input': input
        });
        if (row['property_id'] != id)
          throw const FormatException('Wrong property');
      });
  static DemoProperty propertyPresentation(Map<String, dynamic> row,
      {bool displayLabels = true}) {
    TimeOfDay time(String key) {
      final value = row[key] as String;
      if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d(:00)?$').hasMatch(value))
        throw const FormatException('Invalid property window');
      return TimeOfDay(
          hour: int.parse(value.substring(0, 2)),
          minute: int.parse(value.substring(3, 5)));
    }

    if (row['property_revision'] is! int ||
        (row['property_revision'] as int) < 1 ||
        row['bedrooms'] is! int ||
        row['size_sqft'] is! int)
      throw const FormatException('Invalid property');
    return DemoProperty(
        id: row['property_id'] as String,
        unit: displayLabels
            ? workspaceText(row['unit_name'] as String)
            : row['unit_name'] as String,
        tower: displayLabels
            ? workspaceText(row['building_name'] as String)
            : row['building_name'] as String,
        address: displayLabels
            ? workspaceText(row['address'] as String)
            : row['address'] as String,
        bedrooms: row['bedrooms'] as int,
        sizeSqft: row['size_sqft'] as int,
        cleaningWindowStart: time('cleaning_window_start'),
        cleaningWindowEnd: time('cleaning_window_end'));
  }
}
