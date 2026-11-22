import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'authenticated_memory_cache.dart';

Future<List<Map<String, dynamic>>> readServiceTypes(
  SupabaseClient client,
  AuthenticatedMemoryCache? cache, {
  bool force = false,
}) async {
  Future<List<Map<String, dynamic>>> fetch() async {
    final rows = await client
        .from('service_type')
        .select('service_type_id,name,description')
        .order('name');
    return List.unmodifiable(
      rows.map((row) => Map<String, dynamic>.unmodifiable(row)),
    );
  }

  if (cache == null) return fetch();
  if (force) cache.evict('reference:service-types');
  return cache.read(
    key: 'reference:service-types',
    ttl: const Duration(minutes: 5),
    sizeOf: (rows) => utf8.encode(jsonEncode(rows)).length,
    load: fetch,
  );
}
