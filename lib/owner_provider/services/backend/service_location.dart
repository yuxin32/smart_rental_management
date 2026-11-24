import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceAreaOption {
  const ServiceAreaOption(this.id, this.name, {this.parentId});
  final String id, name;
  final String? parentId;
  factory ServiceAreaOption.fromJson(Map<String, dynamic> row) =>
      ServiceAreaOption(row['id'] as String, row['name'] as String,
          parentId: row['parent_id'] as String?);
}

/// Read a selected Maps pin, never a camera viewport, and never fetch the URL.
String? validateMapPin(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final uri = Uri.tryParse(value.trim());
  if (value.length > 2048 ||
      uri?.scheme != 'https' ||
      !{'www.google.com', 'google.com', 'maps.google.com', 'www.google.com.my'}
          .contains(uri?.host)) {
    return 'Use a full Google Maps link to a selected pin.';
  }
  final point =
      RegExp(r'!3d(-?[0-9]+\.[0-9]+)!4d(-?[0-9]+\.[0-9]+)').firstMatch(value);
  final query = uri!.queryParameters['q'] ?? uri.queryParameters['query'];
  final pair = query == null
      ? null
      : RegExp(r'^(-?[0-9]+(?:\.[0-9]+)?),\s*(-?[0-9]+(?:\.[0-9]+)?)$')
          .firstMatch(query);
  final match = point ?? pair;
  if (match == null)
    return 'Copy a link to a selected pin, not a map view or shortened link.';
  final lat = double.tryParse(match[1]!), lon = double.tryParse(match[2]!);
  if (lat == null ||
      lon == null ||
      !lat.isFinite ||
      !lon.isFinite ||
      lat.abs() > 90 ||
      lon.abs() > 180) {
    return 'This map pin has invalid coordinates.';
  }
  return null;
}

class ServiceLocationRepository {
  const ServiceLocationRepository(this.client);
  final SupabaseClient client;
  Future<List<ServiceAreaOption>> areas() async =>
      List<Map<String, dynamic>>.from(
              await client.rpc('list_service_areas') as List)
          .map(ServiceAreaOption.fromJson)
          .toList(growable: false);
  Future<Map<String, dynamic>> property(String id) async =>
      Map<String, dynamic>.from(await client
          .rpc('my_property_location', params: {'p_property_id': id}) as Map);
  Future<Map<String, dynamic>> provider() async =>
      Map<String, dynamic>.from(await client.rpc('my_service_location') as Map);
  Future<void> saveProperty(
      String id, int revision, String area, String pin) async {
    await client.rpc('save_property_location', params: {
      'p_property_id': id,
      'p_revision': revision,
      'p_area_id': area,
      'p_pin_link': pin.trim(),
    });
  }
}
