import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/features/admin/data/tenant_lifecycle_service.dart';

RegisteredTenancyUnit unit({
  int bedrooms = 4,
  int occupants = 0,
  bool whole = false,
  List<int> rooms = const [0, 0, 0, 0],
}) => RegisteredTenancyUnit({
  'unit_id': 'unit',
  'unit_number': 'A-101',
  'building_name': 'Example Building',
  'bedrooms': bedrooms,
  'occupancy': {'total': occupants, 'whole': whole ? 1 : 0, 'rooms': rooms},
});

void main() {
  test('eight occupants make a unit unavailable', () {
    expect(unit(occupants: 8, rooms: [2, 2, 2, 2]).isFullyOccupied, isTrue);
  });
  test('whole-unit reservation blocks selection even below eight people', () {
    expect(unit(whole: true, occupants: 1).isFullyOccupied, isTrue);
  });
  test('a two-bedroom apartment is full when both rooms are full', () {
    expect(
      unit(bedrooms: 2, occupants: 4, rooms: [2, 2, 0, 0]).isFullyOccupied,
      isTrue,
    );
  });
  test('one shared room place keeps the unit selectable', () {
    final value = unit(bedrooms: 2, occupants: 3, rooms: [2, 1, 0, 0]);
    expect(value.isFullyOccupied, isFalse);
    expect(value.remaining(false, 1), 0);
    expect(value.remaining(false, 2), 1);
  });
  test('an empty registered property is selectable', () {
    expect(unit().isFullyOccupied, isFalse);
  });
  test('room six follows the owner bedroom count', () {
    final value = unit(bedrooms: 6, occupants: 2, rooms: [0, 0, 0, 0, 0, 2]);
    expect(value.roomOccupants.length, 6);
    expect(value.remaining(false, 6), 0);
    expect(value.remaining(false, 5), 2);
    expect(value.remaining(false, 7), 0);
  });
  test('the unit-wide limit still applies with more than four bedrooms', () {
    final value = unit(bedrooms: 6, occupants: 8, rooms: [2, 2, 2, 2, 0, 0]);
    expect(value.isFullyOccupied, isTrue);
    expect(value.remaining(false, 6), 0);
  });
}
