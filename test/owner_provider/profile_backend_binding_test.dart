import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/services/backend/provider_profile_snapshot.dart';
import 'package:smart_rental_management/owner_provider/services/backend/provider_profile_binding.dart';
import 'support/profile_fixture.dart';

void main() {
  test(
      'server identity/null rating, exact rates and actual slots project without demo defaults',
      () {
    final p = profileReport();
    expect(p.presentation.name, 'Test Provider');
    expect(p.presentation.phone, '+60 12-345 6789');
    expect(p.presentation.isVerified, false);
    expect(p.rating, isNull);
    expect(p.hourly, 55.25);
    expect(p.daily, 300.5);
    expect(p.completed, 3);
    expect(p.selected, {profileService});
    expect(p.weeklySummary, 'Mon 08:00–12:00\nMon 14:00–18:00');
    final empty = profileReport(overrides: {
      'full_name': null,
      'bio': null,
      'contact_number': null,
      'hourly_rate': null,
      'weekly_slots': []
    });
    expect(empty.presentation.name, '');
    expect(empty.presentation.phone, '');
    expect(empty.bio, '');
    expect(empty.hourly, isNull);
    expect(empty.weeklySummary, 'No working slots saved yet.');
  });
  test('wrong identities and invalid counters fail closed', () {
    for (final patch in [
      {'provider_id': 'other'},
      {'revision': 0},
      {'completed_jobs': -1},
      {'hourly_rate': double.infinity},
      {'avatar_color_index': 9}
    ]) {
      expect(() => profileReport(overrides: patch), throwsFormatException);
    }
  });
  test('draft allowlist excludes privileged/email/availability fields', () {
    const draft = ProviderProfileDraft(
        name: ' Name ',
        bio: ' Bio ',
        phone: '',
        area: ' Area ',
        origin: ' Private ',
        hourly: null,
        daily: 300.5,
        avatar: 1,
        sharePhone: false,
        services: {profileService});
    expect(draft.json['full_name'], 'Name');
    expect(draft.json['contact_number'], isNull);
    for (final key in [
      'provider_id',
      'approval_status',
      'rating_average',
      'completed_jobs',
      'email',
      'weekly_slots',
      'profile_revision'
    ]) {
      expect(draft.json.containsKey(key), false);
    }
  });
  test('session change clears loaded private profile and ignores late result',
      () async {
    final sessions = StreamController<String?>.broadcast();
    String? identity = profileActor;
    final wait = Completer<ProviderProfileSnapshot>();
    final b = ProviderProfileBinding(
        load: () => wait.future,
        userId: profileActor,
        currentUserId: () => identity,
        sessionChanges: sessions.stream);
    b.setActive(true);
    identity = 'other';
    sessions.add(identity);
    await Future<void>.delayed(Duration.zero);
    wait.complete(profileReport());
    await Future<void>.delayed(Duration.zero);
    expect(b.snapshot, isNull);
    expect(b.sessionEnded, true);
    expect(b.canEdit, false);
    b.dispose();
    await sessions.close();
  });
  test(
      'editor route pause/resume preserves form baseline, profile view refreshes',
      () async {
    final sessions = StreamController<String?>.broadcast();
    var reads = 0;
    final b = ProviderProfileBinding(
        load: () async {
          reads++;
          return profileReport();
        },
        userId: profileActor,
        currentUserId: () => profileActor,
        sessionChanges: sessions.stream);
    b.setActive(true);
    await Future<void>.delayed(Duration.zero);
    b.setActive(false);
    b.setActive(true, refreshOnResume: false);
    expect(reads, 1);
    expect(b.snapshot, isNotNull);
    b.setActive(false);
    b.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 2);
    b.dispose();
    await sessions.close();
  });
  test('read error stays error and retry recovers without sample profile',
      () async {
    final sessions = StreamController<String?>.broadcast();
    var fail = true;
    final b = ProviderProfileBinding(
        load: () async {
          if (fail) throw StateError('network');
          return profileReport();
        },
        userId: profileActor,
        currentUserId: () => profileActor,
        sessionChanges: sessions.stream);
    b.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(b.snapshot, isNull);
    expect(b.error, isNotNull);
    fail = false;
    await b.refresh();
    expect(b.error, isNull);
    expect(b.snapshot, isNotNull);
    b.dispose();
    await sessions.close();
  });
}
