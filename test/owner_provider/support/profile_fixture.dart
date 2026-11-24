import 'package:smart_rental_management/owner_provider/services/backend/provider_profile_snapshot.dart';

const profileActor = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const profileService = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1';
Map<String, dynamic> profileFixture() => {
      'provider_id': profileActor,
      'full_name': 'Test Provider',
      'bio': 'Cleaning service introduction',
      'contact_number': '+60 12-345 6789',
      'email': 'provider@profile.invalid',
      'service_area': 'Kuala Lumpur',
      'service_origin_address': 'Private starting address',
      'hourly_rate': 55.25,
      'daily_rate': 300.50,
      'avatar_color_index': 2,
      'show_phone_to_owners': false,
      'revision': 1,
      'approval_status': 'pending',
      'rating_average': null,
      'review_count': 0,
      'completed_jobs': 3,
      'active_jobs': 1,
      'services': [
        {'id': profileService, 'name': 'Standard cleaning', 'selected': true},
        {
          'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2',
          'name': 'Deep cleaning',
          'selected': false
        },
      ],
      'weekly_slots': [
        {'weekday': 1, 'start_time': '08:00:00', 'end_time': '12:00:00'},
        {'weekday': 1, 'start_time': '14:00:00', 'end_time': '18:00:00'},
      ],
    };
ProviderProfileSnapshot profileReport(
        {Map<String, dynamic> overrides = const {}}) =>
    ProviderProfileSnapshot.parse(
        {...profileFixture(), ...overrides}, profileActor);
