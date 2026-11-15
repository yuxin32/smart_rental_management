import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class MaintenanceRequestRecord {
  const MaintenanceRequestRecord({
    required this.id,
    required this.category,
    required this.description,
    required this.location,
    required this.status,
    required this.submittedAt,
    required this.imagePath,
    required this.tenantName,
    required this.unitLabel,
    required this.adminName,
  });

  final String id;
  final String category;
  final String description;
  final String? location;
  final String status;
  final DateTime submittedAt;
  final String? imagePath;
  final String tenantName;
  final String unitLabel;
  final String? adminName;

  String get title {
    final firstLine = description.trim().split('\n').first;
    return firstLine.length > 90 ? '${firstLine.substring(0, 87)}…' : firstLine;
  }

  factory MaintenanceRequestRecord.fromMap(Map<String, dynamic> map) {
    final tenancy = _asMap(map['tenancy']);
    final tenant = _asMap(tenancy?['tenant']);
    final unit = _asMap(tenancy?['rental_unit']);
    final admin = _asMap(map['assigned_admin']);
    final label = [
      unit?['block_and_floor']?.toString(),
      unit?['unit_number']?.toString(),
    ].where((part) => part != null && part.trim().isNotEmpty).join(' · ');

    return MaintenanceRequestRecord(
      id: map['maintenance_id'].toString(),
      category: map['category']?.toString() ?? 'Other',
      description: map['description']?.toString() ?? '',
      location: map['location_details']?.toString(),
      status: map['request_status']?.toString() ?? 'submitted',
      submittedAt:
          DateTime.tryParse(map['submitted_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      imagePath: map['image_storage_path']?.toString(),
      tenantName: tenant?['full_name']?.toString() ?? 'Tenant',
      unitLabel: label.isEmpty ? 'Unit' : label,
      adminName: admin?['full_name']?.toString(),
    );
  }
}

class MaintenanceUpdateRecord {
  const MaintenanceUpdateRecord({
    required this.oldStatus,
    required this.newStatus,
    required this.remarks,
    required this.createdAt,
    required this.adminName,
  });

  final String? oldStatus;
  final String newStatus;
  final String? remarks;
  final DateTime createdAt;
  final String adminName;

  factory MaintenanceUpdateRecord.fromMap(Map<String, dynamic> map) {
    final admin = _asMap(map['updated_by_admin']);
    return MaintenanceUpdateRecord(
      oldStatus: map['old_status']?.toString(),
      newStatus: map['new_status']?.toString() ?? '',
      remarks: map['remarks']?.toString(),
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      adminName: admin?['full_name']?.toString() ?? 'Administrator',
    );
  }
}

abstract final class MaintenanceService {
  static const imageBucket = 'maintenance-request-images';
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<String> submitRequest({
    required String category,
    required String description,
    String? location,
    Uint8List? imageBytes,
    String? imageName,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Please sign in again.');

    final tenancy = await _client
        .from('tenancy')
        .select('tenancy_id')
        .eq('tenant_id', userId)
        .eq('tenancy_status', 'active')
        .maybeSingle();
    if (tenancy == null) {
      throw StateError('No active tenancy is assigned to this account.');
    }

    final inserted = await _client
        .from('maintenance_request')
        .insert({
          'tenancy_id': tenancy['tenancy_id'],
          'category': category,
          'description': description.trim(),
          'location_details': _clean(location),
          'request_status': 'submitted',
        })
        .select('maintenance_id')
        .single();
    final maintenanceId = inserted['maintenance_id'].toString();

    if (imageBytes != null && imageName != null) {
      final safeName = imageName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '$userId/$maintenanceId/$safeName';
      try {
        await _client.storage
            .from(imageBucket)
            .uploadBinary(
              path,
              imageBytes,
              fileOptions: FileOptions(
                contentType: _imageContentType(safeName),
                upsert: false,
              ),
            );
        await _client
            .from('maintenance_request')
            .update({'image_storage_path': path})
            .eq('maintenance_id', maintenanceId);
      } catch (_) {
        await _client
            .from('maintenance_request')
            .delete()
            .eq('maintenance_id', maintenanceId);
        rethrow;
      }
    }
    return maintenanceId;
  }

  static Future<List<MaintenanceRequestRecord>> fetchTenantRequests() async {
    final rows = await _client
        .from('maintenance_request')
        .select(_requestSelect)
        .order('submitted_at', ascending: false);
    return (rows as List)
        .map(
          (row) => MaintenanceRequestRecord.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  static Future<List<MaintenanceRequestRecord>> fetchAdminRequests() async {
    final rows = await _client
        .from('maintenance_request')
        .select(_requestSelect)
        .order('submitted_at', ascending: false);
    return (rows as List)
        .map(
          (row) => MaintenanceRequestRecord.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  static Future<List<MaintenanceUpdateRecord>> fetchUpdates(
    String maintenanceId,
  ) async {
    final rows = await _client
        .from('maintenance_update')
        .select(
          'old_status, new_status, remarks, created_at, '
          'updated_by_admin:admin!maintenance_update_updated_by_admin_id_fkey('
          'user_account(full_name))',
        )
        .eq('maintenance_id', maintenanceId)
        .order('created_at');
    return (rows as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final admin = _asMap(map['updated_by_admin']);
      map['updated_by_admin'] = _asMap(admin?['user_account']);
      return MaintenanceUpdateRecord.fromMap(map);
    }).toList();
  }

  static Future<String> createSignedImageUrl(String path) =>
      _client.storage.from(imageBucket).createSignedUrl(path, 300);

  static Future<void> updateStatus({
    required String maintenanceId,
    required String newStatus,
    String? remarks,
  }) async {
    await _client.rpc(
      'update_maintenance_request_status',
      params: {
        'p_maintenance_id': maintenanceId,
        'p_new_status': newStatus,
        'p_remarks': _clean(remarks),
      },
    );
  }

  static const _requestSelect =
      'maintenance_id, category, description, location_details, image_storage_path, '
      'request_status, submitted_at, '
      'tenancy:tenancy!maintenance_request_tenancy_id_fkey('
      'tenant:tenant!tenancy_tenant_id_fkey(user_account(full_name)), '
      'rental_unit: rental_unit!tenancy_unit_id_fkey(unit_number, block_and_floor)), '
      'assigned_admin:admin!maintenance_request_assigned_admin_id_fkey('
      'user_account(full_name))';

  static String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  static String _imageContentType(String name) {
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };
  }
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Map<String, dynamic>.from(value.first as Map);
  }
  return null;
}
