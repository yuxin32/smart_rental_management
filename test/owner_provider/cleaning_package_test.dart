import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/features/availability/domain/cleaning_package.dart';

const actor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const service = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const package = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

Map<String, dynamic> packageRow() => {
  'package_id': package,
  'provider_id': actor,
  'service_type_id': service,
  'duration_minutes': 180,
  'cleaner_count': 2,
  'total_price': 125.50,
  'package_scope': 'Floors and bathrooms',
  'enabled': true,
  'revision': 3,
};

void main() {
  test('parses own fixed session total and exposes editable draft', () {
    final result = CleaningPackage.parse(packageRow(), actor);
    expect(result.id, package);
    expect(result.packageId, package);
    expect(result.providerId, actor);
    expect(result.revision, 3);
    expect(result.totalPrice, 125.50); // Not multiplied by crew or duration.
    expect(result.draft.totalPrice, result.totalPrice);
    expect(result.draft.cleanerCount, 2);
    expect(result.draft.validationError, isNull);
  });
  test('disabled packages remain editable', () {
    expect(
      CleaningPackage.parse({...packageRow(), 'enabled': false}, actor).enabled,
      isFalse,
    );
  });
  for (final patch in <Map<String, dynamic>>[
    {'provider_id': service},
    {'package_id': 'bad'},
    {'service_type_id': null},
    {'revision': 0},
    {'revision': '3'},
    {'duration_minutes': 90},
    {'duration_minutes': 180.0},
    {'cleaner_count': 0},
    {'cleaner_count': 5},
    {'total_price': double.nan},
    {'total_price': double.infinity},
    {'total_price': 0},
    {'total_price': 1.001},
    {'total_price': 100000000},
    {'package_scope': ''},
    {'package_scope': null},
    {'enabled': 'true'},
  ]) {
    test('rejects invalid server row $patch', () {
      expect(
        () => CleaningPackage.parse({...packageRow(), ...patch}, actor),
        throwsFormatException,
      );
    });
  }
  test('duration presets distinguish standard and deep cleaning', () {
    expect(CleaningPackageDraft.durationsForService('Standard Cleaning'), [
      120,
      180,
      240,
    ]);
    expect(CleaningPackageDraft.durationsForService('DEEP cleaning'), [
      240,
      360,
      480,
    ]);
  });
  test('draft limits scope and accepts ordinary two-decimal prices', () {
    CleaningPackageDraft draft(num price, String scope) => CleaningPackageDraft(
      serviceTypeId: service,
      durationMinutes: 120,
      cleanerCount: 1,
      totalPrice: price,
      scope: scope,
    );
    for (final price in [0.01, 19.99, 125.50, 99999999.99]) {
      expect(draft(price, 'Included cleaning').validationError, isNull);
    }
    expect(draft(1, List.filled(2001, 'x').join()).validationError, isNotNull);
    expect(draft(1, '  ').validationError, isNotNull);
  });
}
