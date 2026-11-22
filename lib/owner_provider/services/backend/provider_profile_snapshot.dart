import '../../models/demo_data.dart';
import '../../features/availability/domain/provider_availability.dart';
import '../../features/availability/domain/provider_setup.dart';

class ProviderProfileSnapshot {
  ProviderProfileSnapshot._(this.row);
  final Map<String, dynamic> row;
  factory ProviderProfileSnapshot.parse(
      Map<String, dynamic> row, String actor) {
    if (row['provider_id'] != actor ||
        (row['revision'] as int) < 1 ||
        (row['avatar_color_index'] as int) < 0 ||
        (row['avatar_color_index'] as int) > 5 ||
        (row['completed_jobs'] as int) < 0 ||
        (row['active_jobs'] as int) < 0) {
      throw const FormatException('Unexpected profile identity or counters.');
    }
    for (final field in ['hourly_rate', 'daily_rate', 'rating_average']) {
      final value = row[field] as num?;
      if (value != null && (!value.isFinite || value < 0))
        throw const FormatException('Invalid profile value.');
    }
    if (row['show_phone_to_owners'] is! bool ||
        row['approval_status'] is! String ||
        row['service_area'] is! String ||
        row['service_origin_address'] is! String ||
        (row['review_count'] as int) < 0 ||
        (row['rating_average'] != null &&
            ((row['rating_average'] as num) < 1 ||
                (row['rating_average'] as num) > 5))) {
      throw const FormatException('Invalid profile fields.');
    }
    final services = List<Map<String, dynamic>>.from(row['services'] as List);
    final slots = List<Map<String, dynamic>>.from(row['weekly_slots'] as List);
    for (final service in services) {
      if (service['id'] is! String ||
          service['name'] is! String ||
          service['selected'] is! bool) {
        throw const FormatException('Invalid service.');
      }
    }
    for (final slot in slots) {
      final day = slot['weekday'] as int;
      final start =
          ProviderSlotRules.parseDatabaseTime(slot['start_time'] as String);
      final end =
          ProviderSlotRules.parseDatabaseTime(slot['end_time'] as String);
      if (day < 1 || day > 7 || end <= start)
        throw const FormatException('Invalid slot.');
    }
    final snapshot = ProviderProfileSnapshot._(Map.unmodifiable({
      ...row,
      'services': List.unmodifiable(
          services.map((s) => Map<String, dynamic>.unmodifiable(s))),
      'weekly_slots': List.unmodifiable(
          slots.map((s) => Map<String, dynamic>.unmodifiable(s)))
    }));
    // Validate optional field types before a widget renders private data.
    snapshot.name;
    snapshot.bio;
    snapshot.email;
    snapshot.contact;
    return snapshot;
  }
  String get id => row['provider_id'] as String;
  int get revision => row['revision'] as int;
  String? get contact => row['contact_number'] as String?;
  String get email => row['email'] as String? ?? '';
  String get name => row['full_name'] as String? ?? '';
  String get bio => row['bio'] as String? ?? '';
  String get area => row['service_area'] as String;
  String get origin => row['service_origin_address'] as String;
  String get approval => row['approval_status'] as String;
  String get approvalLabel => switch (approval) {
        'approved' => 'Approved',
        'pending' => 'Pending review',
        _ => 'Not approved'
      };
  int get avatar => row['avatar_color_index'] as int;
  bool get sharePhone => row['show_phone_to_owners'] as bool;
  int get completed => row['completed_jobs'] as int;
  int get active => row['active_jobs'] as int;
  double? get rating => (row['rating_average'] as num?)?.toDouble();
  double? get hourly => (row['hourly_rate'] as num?)?.toDouble();
  double? get daily => (row['daily_rate'] as num?)?.toDouble();
  List<Map<String, dynamic>> get services =>
      List<Map<String, dynamic>>.from(row['services'] as List);
  List<Map<String, dynamic>> get slots =>
      List<Map<String, dynamic>>.from(row['weekly_slots'] as List);
  Set<String> get selected => services
      .where((s) => s['selected'] == true)
      .map((s) => s['id'] as String)
      .toSet();
  DemoProvider get presentation => DemoProvider(
      id: id,
      name: name,
      serviceTypes: services
          .where((s) => s['selected'] == true)
          .map((s) => s['name'] as String)
          .toList(),
      distanceKm: 0,
      rating: rating ?? 0,
      workload: '',
      score: 0,
      availability: '',
      activeBookingCount: active,
      phone: contact ?? '',
      email: email,
      bio: bio,
      hourlyRate: hourly ?? 0,
      isVerified: approval == 'approved',
      avatarColorIndex: avatar,
      showPhoneToOwners: sharePhone,
      availabilitySchedule: ProviderAvailabilitySchedule.closed);
  String get weeklySummary {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (slots.isEmpty) return 'No working slots saved yet.';
    return slots.map((s) {
      final day = s['weekday'] as int;
      if (day < 1 || day > 7) throw const FormatException('Invalid weekday');
      return '${days[day - 1]} ${ProviderSlotRules.databaseTime(ProviderSlotRules.parseDatabaseTime(s['start_time'] as String))}'
          '–${ProviderSlotRules.databaseTime(ProviderSlotRules.parseDatabaseTime(s['end_time'] as String))}';
    }).join('\n');
  }
}

class ProviderProfileDraft {
  const ProviderProfileDraft(
      {required this.name,
      required this.bio,
      required this.phone,
      required this.area,
      required this.origin,
      required this.hourly,
      required this.daily,
      required this.avatar,
      required this.sharePhone,
      required this.services});
  final String name, bio, phone, area, origin;
  final double? hourly, daily;
  final int avatar;
  final bool sharePhone;
  final Set<String> services;
  Map<String, dynamic> get json => {
        'full_name': name.trim(),
        'bio': bio.trim(),
        'contact_number': phone.trim().isEmpty ? null : phone.trim(),
        'service_area': area.trim(),
        'service_origin_address': origin.trim(),
        'hourly_rate': hourly,
        'daily_rate': daily,
        'avatar_color_index': avatar,
        'show_phone_to_owners': sharePhone,
        'service_type_ids': services.toList()
      };
}
