/// A server-owned fixed total for one cleaning session, including its crew.
class CleaningPackage {
  const CleaningPackage({
    required this.id,
    this.providerId = '',
    required this.serviceTypeId,
    required this.durationMinutes,
    required this.cleanerCount,
    required this.totalPrice,
    required this.scope,
    required this.enabled,
    required this.revision,
  });

  final String id, providerId, serviceTypeId, scope;
  final int durationMinutes, cleanerCount, revision;
  final num totalPrice;
  final bool enabled;
  String get packageId => id;

  factory CleaningPackage.parse(Map<String, dynamic> row, String actor) {
    final id = row['package_id'];
    final service = row['service_type_id'];
    final revision = row['revision'];
    final draft = CleaningPackageDraft(
      serviceTypeId: service is String ? service : '',
      durationMinutes: row['duration_minutes'] is int
          ? row['duration_minutes'] as int
          : 0,
      cleanerCount: row['cleaner_count'] is int
          ? row['cleaner_count'] as int
          : 0,
      totalPrice: row['total_price'] is num ? row['total_price'] as num : 0,
      scope: row['package_scope'] is String
          ? row['package_scope'] as String
          : '',
      enabled: row['enabled'] == true,
    );
    if (!validPackageId(id) ||
        row['provider_id'] != actor ||
        revision is! int ||
        revision < 1 ||
        row['enabled'] is! bool ||
        draft.validationError != null) {
      throw const FormatException('Could not verify cleaning package.');
    }
    return CleaningPackage(
      id: id as String,
      providerId: actor,
      serviceTypeId: draft.serviceTypeId,
      durationMinutes: draft.durationMinutes,
      cleanerCount: draft.cleanerCount,
      totalPrice: draft.totalPrice,
      scope: draft.scope,
      enabled: draft.enabled,
      revision: revision,
    );
  }

  CleaningPackageDraft get draft => CleaningPackageDraft(
    serviceTypeId: serviceTypeId,
    durationMinutes: durationMinutes,
    cleanerCount: cleanerCount,
    totalPrice: totalPrice,
    scope: scope,
    enabled: enabled,
  );
}

class CleaningPackageDraft {
  const CleaningPackageDraft({
    required this.serviceTypeId,
    required this.durationMinutes,
    required this.cleanerCount,
    required this.totalPrice,
    required this.scope,
    this.enabled = true,
  });

  final String serviceTypeId, scope;
  final int durationMinutes, cleanerCount;
  final num totalPrice;
  final bool enabled;

  String? get validationError {
    if (!validPackageId(serviceTypeId)) return 'Select a cleaning service.';
    if (!const {120, 180, 240, 360, 480}.contains(durationMinutes)) {
      return 'Select a supported cleaning duration.';
    }
    if (cleanerCount < 1 || cleanerCount > 4) {
      return 'Choose one to four cleaners.';
    }
    if (!totalPrice.isFinite ||
        totalPrice <= 0 ||
        totalPrice > 99999999.99 ||
        (totalPrice * 100 - (totalPrice * 100).round()).abs() > 0.000001) {
      return 'Enter a positive total price with at most two decimal places.';
    }
    if (scope.trim().isEmpty || scope.trim().length > 2000) {
      return 'Describe the included cleaning in at most 2000 characters.';
    }
    return null;
  }

  static List<int> durationsForService(String name) =>
      name.toLowerCase().contains('deep')
      ? const [240, 360, 480]
      : const [120, 180, 240];
}

bool validPackageId(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
