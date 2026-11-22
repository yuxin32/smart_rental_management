import 'package:flutter/material.dart';

import '../models/demo_data.dart';

enum PropertySaveFailure {
  notFound,
  invalidFields,
  invalidCleaningWindow,
  duplicateUnit,
  bookedIdentity,
}

class PropertySaveResult {
  const PropertySaveResult.success(this.property) : failure = null;
  const PropertySaveResult.failure(this.failure) : property = null;

  final DemoProperty? property;
  final PropertySaveFailure? failure;
  bool get saved => property != null;

  String get message => switch (failure) {
        PropertySaveFailure.notFound => 'Property not found.',
        PropertySaveFailure.invalidFields =>
          'Enter the unit, building, address, bedrooms and size.',
        PropertySaveFailure.invalidCleaningWindow =>
          'The cleaning window must end after it starts.',
        PropertySaveFailure.duplicateUnit =>
          'This unit is already registered in that building.',
        PropertySaveFailure.bookedIdentity =>
          'This unit already has bookings. Its unit and building name cannot be changed in the local demo.',
        null => 'Property saved.',
      };
}

/// Owner-scoped local records. Cloud identity and RLS will replace this store.
class PropertyStore extends ChangeNotifier {
  PropertyStore() : _properties = List.of(DemoProperty.all);

  List<DemoProperty> _properties;
  int _sequence = 0;
  List<DemoProperty> get properties => List.unmodifiable(_properties);

  DemoProperty? byId(String id) =>
      _properties.where((property) => property.id == id).firstOrNull;

  DemoProperty? byDisplay(String display) =>
      _properties.where((property) => property.display == display).firstOrNull;

  PropertySaveResult add({
    required String unit,
    required String tower,
    required String address,
    required int bedrooms,
    required int sizeSqft,
    required TimeOfDay cleaningWindowStart,
    required TimeOfDay cleaningWindowEnd,
  }) {
    final candidate = DemoProperty(
      id: 'prop-local-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}',
      unit: unit.trim(),
      tower: tower.trim(),
      address: address.trim(),
      bedrooms: bedrooms,
      sizeSqft: sizeSqft,
      cleaningWindowStart: cleaningWindowStart,
      cleaningWindowEnd: cleaningWindowEnd,
    );
    final failure = _validate(candidate);
    if (failure != null) return PropertySaveResult.failure(failure);
    _properties = [..._properties, candidate];
    notifyListeners();
    return PropertySaveResult.success(candidate);
  }

  PropertySaveResult update(DemoProperty updated,
      {required Iterable<DemoBooking> bookings}) {
    final index = _properties.indexWhere((item) => item.id == updated.id);
    if (index < 0) {
      return const PropertySaveResult.failure(PropertySaveFailure.notFound);
    }
    final current = _properties[index];
    if (updated.display != current.display &&
        bookings.any((booking) => booking.property == current.display)) {
      return const PropertySaveResult.failure(
          PropertySaveFailure.bookedIdentity);
    }
    final failure = _validate(updated, exceptId: updated.id);
    if (failure != null) return PropertySaveResult.failure(failure);
    _properties = List.of(_properties)..[index] = updated;
    notifyListeners();
    return PropertySaveResult.success(updated);
  }

  PropertySaveFailure? _validate(DemoProperty property, {String? exceptId}) {
    if (property.unit.trim().isEmpty ||
        property.tower.trim().isEmpty ||
        property.address.trim().isEmpty ||
        property.bedrooms <= 0 ||
        property.sizeSqft <= 0) {
      return PropertySaveFailure.invalidFields;
    }
    final start = property.cleaningWindowStart.hour * 60 +
        property.cleaningWindowStart.minute;
    final end = property.cleaningWindowEnd.hour * 60 +
        property.cleaningWindowEnd.minute;
    if (end <= start) return PropertySaveFailure.invalidCleaningWindow;
    if (_properties.any((item) =>
        item.id != exceptId &&
        item.unit.toLowerCase() == property.unit.toLowerCase() &&
        item.tower.toLowerCase() == property.tower.toLowerCase())) {
      return PropertySaveFailure.duplicateUnit;
    }
    return null;
  }
}
