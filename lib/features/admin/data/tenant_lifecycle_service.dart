import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/feature_flags.dart';

class TenantRegistrationRecord {
  const TenantRegistrationRecord({
    required this.registrationId,
    required this.fullName,
    required this.icNumber,
    required this.email,
    required this.contact_number,
    required this.verificationStatus,
    required this.registrationStatus,
    required this.unitId,
    required this.unitNumber,
    required this.unitLocation,
    required this.startDate,
    required this.endDate,
    required this.monthlyRentalAmount,
    required this.occupancyShare,
    required this.invitedAt,
    required this.authUserId,
    required this.identityDocumentPath,
    required this.employmentOrStudyProofPath,
    required this.documentsSubmittedAt,
    required this.verificationNotes,
    required this.verificationReviewedAt,
  });

  final String registrationId;
  final String fullName;
  final String icNumber;
  final String email;
  final String? contact_number;
  final String verificationStatus;
  final String registrationStatus;
  final String? unitId;
  final String? unitNumber;
  final String? unitLocation;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? monthlyRentalAmount;
  final double occupancyShare;
  final DateTime? invitedAt;
  final String? authUserId;
  final String? identityDocumentPath;
  final String? employmentOrStudyProofPath;
  final DateTime? documentsSubmittedAt;
  final String? verificationNotes;
  final DateTime? verificationReviewedAt;

  bool get hasAssignment =>
      unitId != null && startDate != null && monthlyRentalAmount != null;

  bool get canInvite =>
      authUserId == null &&
      (registrationStatus == 'draft' || registrationStatus == 'expired');

  bool get canResendInvitation =>
      registrationStatus == 'invited' && authUserId != null;

  bool get canAssign =>
      (AppFeatureFlags.bypassTenantDocumentVerificationForTesting ||
          verificationStatus == 'verified') &&
      authUserId != null &&
      (registrationStatus == 'accepted' || registrationStatus == 'assigned');

  bool get hasVerificationDocuments =>
      identityDocumentPath != null && employmentOrStudyProofPath != null;

  bool get isActiveLifecycle =>
      registrationStatus == 'assigned' &&
      (AppFeatureFlags.bypassTenantDocumentVerificationForTesting ||
          verificationStatus == 'verified') &&
      hasAssignment;

  bool get isReviewNeeded =>
      !isActiveLifecycle &&
      registrationStatus == 'accepted' &&
      (documentsSubmittedAt != null ||
          AppFeatureFlags.bypassTenantDocumentVerificationForTesting);

  bool get isInvitedLifecycle =>
      registrationStatus == 'invited' ||
      (registrationStatus == 'accepted' &&
          documentsSubmittedAt == null &&
          !AppFeatureFlags.bypassTenantDocumentVerificationForTesting);

  String get verificationStageLabel {
    if (isActiveLifecycle) return 'Active';
    if (verificationStatus == 'verified') return 'Assign unit';
    if (verificationStatus == 'rejected') return 'Resubmission needed';
    if (documentsSubmittedAt != null) return 'Review needed';
    if (registrationStatus == 'invited') return 'Awaiting account setup';
    if (registrationStatus == 'accepted') {
      return AppFeatureFlags.bypassTenantDocumentVerificationForTesting
          ? 'Ready to assign'
          : 'Awaiting documents';
    }
    return 'Not submitted';
  }

  String get unitLabel {
    if (unitNumber == null) return 'Not assigned';
    if (unitLocation == null || unitLocation!.isEmpty) return unitNumber!;
    return '$unitLocation · $unitNumber';
  }

  String get stageLabel {
    if (isActiveLifecycle) return 'Account active';
    return switch (registrationStatus) {
      'draft' => 'Ready to invite',
      'assigned' => 'Unit assigned',
      'invited' => 'Invitation sent',
      'accepted' =>
        verificationStatus == 'verified'
            ? 'Unit assignment needed'
            : documentsSubmittedAt == null
            ? AppFeatureFlags.bypassTenantDocumentVerificationForTesting
                  ? 'Unit assignment needed'
                  : 'Account created'
            : verificationStatus == 'rejected'
            ? 'Documents rejected'
            : 'Documents submitted',
      'expired' => 'Invitation expired',
      'cancelled' => 'Cancelled',
      _ => registrationStatus,
    };
  }

  factory TenantRegistrationRecord.fromMap(Map<String, dynamic> map) {
    final unit = map['rental_unit'] is Map
        ? Map<String, dynamic>.from(map['rental_unit'] as Map)
        : null;

    return TenantRegistrationRecord(
      registrationId: map['registration_id'] as String,
      fullName: map['full_name'] as String? ?? '',
      icNumber: map['ic_number'] as String? ?? '',
      email: map['email'] as String? ?? '',
      contact_number: map['contact_number'] as String?,
      verificationStatus: map['verification_status'] as String? ?? 'pending',
      registrationStatus: map['registration_status'] as String? ?? 'draft',
      unitId: map['unit_id'] as String?,
      unitNumber: unit?['unit_number'] as String?,
      unitLocation: unit?['block_and_floor'] as String?,
      startDate: _dateFrom(map['start_date']),
      endDate: _dateFrom(map['end_date']),
      monthlyRentalAmount: _doubleFrom(map['monthly_rental_amount']),
      occupancyShare: _doubleFrom(map['occupancy_share']) ?? 1,
      invitedAt: _dateFrom(map['invited_at']),
      authUserId: map['auth_user_id'] as String?,
      identityDocumentPath: map['identity_document_path'] as String?,
      employmentOrStudyProofPath:
          map['employment_or_study_proof_path'] as String?,
      documentsSubmittedAt: _dateFrom(map['documents_submitted_at']),
      verificationNotes: map['verification_notes'] as String?,
      verificationReviewedAt: _dateFrom(map['verification_reviewed_at']),
    );
  }

  static DateTime? _dateFrom(dynamic value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  static double? _doubleFrom(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class RentalUnitOption {
  const RentalUnitOption({
    required this.unitId,
    required this.unitNumber,
    required this.location,
    required this.status,
    required this.capacity,
  });

  final String unitId;
  final String unitNumber;
  final String? location;
  final String status;
  final int capacity;

  String get blockCode {
    final parts = unitNumber.split('-');
    return parts.length == 3 ? parts[0] : '';
  }

  int? get floorNumber {
    final parts = unitNumber.split('-');
    return parts.length == 3 ? int.tryParse(parts[1]) : null;
  }

  String get label {
    if (location == null || location!.isEmpty) return unitNumber;
    return '$location · $unitNumber';
  }

  factory RentalUnitOption.fromMap(Map<String, dynamic> map) {
    return RentalUnitOption(
      unitId: map['unit_id'] as String,
      unitNumber: map['unit_number'] as String? ?? '',
      location: map['block_and_floor'] as String?,
      status: map['unit_status'] as String? ?? 'available',
      capacity: (map['occupancy_capacity'] as num?)?.toInt() ?? 1,
    );
  }
}

class AuditLogRecord {
  const AuditLogRecord({
    required this.auditId,
    required this.actionType,
    required this.entityType,
    required this.entityId,
    required this.outcome,
    required this.eventTimestamp,
    required this.metadata,
  });

  final String auditId;
  final String actionType;
  final String entityType;
  final String? entityId;
  final String outcome;
  final DateTime eventTimestamp;
  final Map<String, dynamic> metadata;

  String get actionLabel => switch (actionType) {
    'TENANT_INFORMATION_ADDED' => 'Tenant information added',
    'TENANT_UNIT_ASSIGNED' => 'Rental unit assigned',
    'TENANT_INVITATION_SENT' => 'Invitation sent',
    'TENANT_INVITATION_RESENT' => 'Invitation resent',
    'TENANT_VERIFICATION_REVIEWED' => 'Verification reviewed',
    _ =>
      actionType
          .toLowerCase()
          .split('_')
          .map(
            (part) => part.isEmpty
                ? part
                : '${part[0].toUpperCase()}${part.substring(1)}',
          )
          .join(' '),
  };

  String get detailLabel {
    final unit = metadata['unit_number'] ?? metadata['unit_id'];
    if (unit != null) return 'Unit: $unit';
    final email = metadata['email'];
    if (email != null) return 'Invitation address: $email';
    return 'Tenant onboarding record updated';
  }

  factory AuditLogRecord.fromMap(Map<String, dynamic> map) {
    final rawMetadata = map['metadata'];
    return AuditLogRecord(
      auditId: map['audit_id'] as String,
      actionType: map['action_type'] as String? ?? 'UNKNOWN_ACTION',
      entityType: map['entity_type'] as String? ?? 'unknown',
      entityId: map['entity_id'] as String?,
      outcome: map['outcome'] as String? ?? 'success',
      eventTimestamp:
          DateTime.tryParse(map['event_timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      metadata: rawMetadata is Map
          ? Map<String, dynamic>.from(rawMetadata)
          : const <String, dynamic>{},
    );
  }
}

abstract final class TenantLifecycleService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<TenantRegistrationRecord>> fetchRegistrations() async {
    final rows = await _client
        .from('tenant_registration')
        .select('*, rental_unit(unit_number, block_and_floor, unit_status)')
        .order('created_at', ascending: false);

    return (rows as List)
        .map(
          (row) => TenantRegistrationRecord.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  static Future<TenantRegistrationRecord> fetchRegistration(
    String registrationId,
  ) async {
    final row = await _client
        .from('tenant_registration')
        .select('*, rental_unit(unit_number, block_and_floor, unit_status)')
        .eq('registration_id', registrationId)
        .single();

    return TenantRegistrationRecord.fromMap(row);
  }

  static Future<List<RentalUnitOption>> fetchAvailableUnits() async {
    final rows = await _client
        .from('rental_unit')
        .select(
          'unit_id, unit_number, block_and_floor, occupancy_capacity, unit_status',
        )
        .inFilter('unit_status', ['available', 'occupied'])
        .order('unit_number');

    return (rows as List)
        .map(
          (row) =>
              RentalUnitOption.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  static Future<List<AuditLogRecord>> fetchAuditLogs({
    required String registrationId,
  }) async {
    final request = _client
        .from('audit_log')
        .select('*')
        .inFilter('action_type', [
          'TENANT_INFORMATION_ADDED',
          'TENANT_UNIT_ASSIGNED',
          'TENANT_INVITATION_SENT',
          'TENANT_INVITATION_RESENT',
          'TENANT_VERIFICATION_REVIEWED',
        ]);

    final rows = await request
        .eq('entity_id', registrationId)
        .order('event_timestamp', ascending: false);

    return (rows as List)
        .map(
          (row) =>
              AuditLogRecord.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  static Future<String> createRegistration({
    required String fullName,
    required String icNumber,
    required String email,
    String? contact_number,
  }) async {
    final adminId = _client.auth.currentUser?.id;
    if (adminId == null) throw StateError('Administrator session is missing.');

    final row = await _client
        .from('tenant_registration')
        .insert({
          'full_name': fullName,
          'ic_number': icNumber,
          'email': email,
          'contact_number': contact_number,
          'verification_status': 'pending',
          'registration_status': 'draft',
          'created_by_admin_id': adminId,
        })
        .select('registration_id')
        .single();

    return row['registration_id'] as String;
  }

  static Future<void> saveAssignment({
    required String registrationId,
    required String unitId,
    required DateTime startDate,
    DateTime? endDate,
    required double monthlyRentalAmount,
    required double occupancyShare,
  }) async {
    await _client.rpc(
      'assign_verified_tenant',
      params: {
        'p_registration_id': registrationId,
        'p_unit_id': unitId,
        'p_start_date': _dateValue(startDate),
        'p_end_date': endDate == null ? null : _dateValue(endDate),
        'p_monthly_rental_amount': monthlyRentalAmount,
        'p_occupancy_share': occupancyShare,
      },
    );
  }

  static Future<void> reviewVerification({
    required String registrationId,
    required String status,
    String? notes,
  }) async {
    await _client.rpc(
      'review_tenant_verification',
      params: {
        'p_registration_id': registrationId,
        'p_verification_status': status,
        'p_verification_notes': notes,
      },
    );
  }

  static Future<void> sendInvitation(
    String registrationId, {
    bool resend = false,
    required String temporaryPassword,
  }) async {
    final response = await _client.functions.invoke(
      'invite-tenant',
      body: {
        'registration_id': registrationId,
        'resend': resend,
        'temporary_password': temporaryPassword,
      },
    );

    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error'] : null;
      throw StateError(message?.toString() ?? 'Unable to send invitation.');
    }
  }

  static Future<void> activateCurrentTenant() async {
    await _client.rpc('complete_current_tenant_setup');
  }

  static Future<TenantRegistrationRecord?>
  fetchCurrentTenantRegistration() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final row = await _client
        .from('tenant_registration')
        .select('*, rental_unit(unit_number, block_and_floor, unit_status)')
        .eq('auth_user_id', userId)
        .maybeSingle();

    if (row == null) return null;
    return TenantRegistrationRecord.fromMap(row);
  }

  static Future<void> submitTenantVerificationDocuments({
    required String identityDocumentPath,
    required String employmentOrStudyProofPath,
  }) async {
    final response = await _client.rpc(
      'submit_tenant_verification_documents',
      params: {
        'p_identity_document_path': identityDocumentPath,
        'p_employment_or_study_proof_path': employmentOrStudyProofPath,
      },
    );

    if (response != true) {
      throw StateError(
        'The tenant registration is not ready for document submission.',
      );
    }
  }

  static Future<String> createVerificationDocumentUrl(String path) {
    return _client.storage
        .from('tenant-verification-documents')
        .createSignedUrl(path, 600);
  }

  static Future<TenantRentalDetails?> fetchCurrentTenantDetails() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final account = await _client
        .from('user_account')
        .select('full_name, email, contact_number')
        .eq('user_id', userId)
        .maybeSingle();

    final tenancy = await _client
        .from('tenancy')
        .select(
          'start_date, end_date, monthly_rental_amount, occupancy_share, tenancy_status, rental_unit(unit_number, block_and_floor)',
        )
        .eq('tenant_id', userId)
        .inFilter('tenancy_status', ['pending', 'active'])
        .order('start_date', ascending: false)
        .limit(1)
        .maybeSingle();

    if (account == null) return null;

    if (tenancy == null) {
      return TenantRentalDetails(
        fullName: account['full_name'] as String? ?? '',
        email: account['email'] as String? ?? '',
        contact_number: account['contact_number'] as String?,
        unitNumber: 'Not assigned',
        unitLocation: null,
        tenancyStatus: 'unassigned',
        startDate: null,
        endDate: null,
        monthlyRentalAmount: 0,
        occupancyShare: 1,
      );
    }

    final unit = tenancy['rental_unit'] is Map
        ? Map<String, dynamic>.from(tenancy['rental_unit'] as Map)
        : <String, dynamic>{};

    return TenantRentalDetails(
      fullName: account['full_name'] as String? ?? '',
      email: account['email'] as String? ?? '',
      contact_number: account['contact_number'] as String?,
      unitNumber: unit['unit_number'] as String? ?? 'Not assigned',
      unitLocation: unit['block_and_floor'] as String?,
      tenancyStatus: tenancy['tenancy_status'] as String? ?? 'pending',
      startDate: TenantRegistrationRecord._dateFrom(tenancy['start_date']),
      endDate: TenantRegistrationRecord._dateFrom(tenancy['end_date']),
      monthlyRentalAmount:
          TenantRegistrationRecord._doubleFrom(
            tenancy['monthly_rental_amount'],
          ) ??
          0,
      occupancyShare:
          TenantRegistrationRecord._doubleFrom(tenancy['occupancy_share']) ?? 1,
    );
  }

  static String _dateValue(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class TenantRentalDetails {
  const TenantRentalDetails({
    required this.fullName,
    required this.email,
    required this.contact_number,
    required this.unitNumber,
    required this.unitLocation,
    required this.tenancyStatus,
    required this.startDate,
    required this.endDate,
    required this.monthlyRentalAmount,
    required this.occupancyShare,
  });

  final String fullName;
  final String email;
  final String? contact_number;
  final String unitNumber;
  final String? unitLocation;
  final String tenancyStatus;
  final DateTime? startDate;
  final DateTime? endDate;
  final double monthlyRentalAmount;
  final double occupancyShare;

  bool get hasTenancy => tenancyStatus != 'unassigned';

  String get unitLabel {
    if (unitLocation == null || unitLocation!.isEmpty) return unitNumber;
    return '$unitLocation · $unitNumber';
  }
}
