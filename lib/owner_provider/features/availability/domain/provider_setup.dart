class ProviderServiceItem {
  const ProviderServiceItem({required this.id, required this.name});
  final String id;
  final String name;
}

class ProviderWeeklySlotItem {
  const ProviderWeeklySlotItem({
    required this.id,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
  });
  final String id;
  final int weekday;
  final int startMinute;
  final int endMinute;
}

class ProviderSetupData {
  const ProviderSetupData({
    required this.services,
    required this.selectedServiceIds,
    required this.slots,
    required this.unavailableDates,
  });
  final List<ProviderServiceItem> services;
  final Set<String> selectedServiceIds;
  final List<ProviderWeeklySlotItem> slots;
  final Set<String> unavailableDates;
}

abstract final class ProviderSlotRules {
  static const minimumMinutes = 120;

  static int parseDatabaseTime(String value) {
    final parts = value.split(':');
    if (parts.length < 2) throw const FormatException('Invalid time.');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      throw const FormatException('Invalid time.');
    }
    return hour * 60 + minute;
  }

  static String databaseTime(int minuteOfDay) {
    if (minuteOfDay < 0 || minuteOfDay >= 24 * 60) {
      throw ArgumentError.value(minuteOfDay, 'minuteOfDay');
    }
    final hour = minuteOfDay ~/ 60;
    final minute = minuteOfDay % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static String? validate({
    required int weekday,
    required int startMinute,
    required int endMinute,
    required List<ProviderWeeklySlotItem> existing,
  }) {
    if (weekday < 1 ||
        weekday > 7 ||
        startMinute < 0 ||
        endMinute >= 24 * 60 ||
        endMinute <= startMinute) {
      return 'Choose a valid day and time range.';
    }
    if (endMinute - startMinute < minimumMinutes) {
      return 'Each working slot must be at least 2 hours.';
    }
    if (existing.any((slot) =>
        slot.weekday == weekday &&
        slot.startMinute < endMinute &&
        startMinute < slot.endMinute)) {
      return 'Working slots on the same day cannot overlap.';
    }
    return null;
  }
}
