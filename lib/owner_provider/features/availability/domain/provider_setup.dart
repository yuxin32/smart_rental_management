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
    this.weeklyState,
  });
  final List<ProviderServiceItem> services;
  final Set<String> selectedServiceIds;
  final List<ProviderWeeklySlotItem> slots;
  final Set<String> unavailableDates;
  final ProviderWeeklyState? weeklyState;
}

class ProviderWorkingRange {
  const ProviderWorkingRange(this.start, this.end);
  final int start, end;
  Map<String, int> get json => {'start_minute': start, 'end_minute': end};
}

class ProviderRequiredInterval {
  const ProviderRequiredInterval(
      this.weekday, this.start, this.end, this.count);
  final int weekday, start, end, count;
}

/// Own-account preflight. Revision prevents another device overwriting hours;
/// required intervals are checked again by the saving transaction.
class ProviderWeeklyState {
  const ProviderWeeklyState({
    required this.providerId,
    required this.revision,
    required this.slots,
    required this.required,
    required this.requiredServices,
  });
  final String providerId, revision;
  final List<ProviderWeeklySlotItem> slots;
  final List<ProviderRequiredInterval> required;
  final Set<String> requiredServices;

  factory ProviderWeeklyState.parse(Map<String, dynamic> row, String actor) {
    final revision = row['revision'];
    final rawSlots = row['slots'], rawRequired = row['required_intervals'];
    final rawServices = row['required_service_ids'];
    if (row['provider_id'] != actor ||
        revision is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(revision) ||
        rawSlots is! List ||
        rawSlots.length > 256 ||
        rawRequired is! List ||
        rawRequired.length > 512 ||
        rawServices is! List ||
        rawServices.length > 256) {
      throw const FormatException('Could not verify working hours.');
    }
    bool integer(dynamic value, int min, int max) =>
        value is int && value >= min && value <= max;
    final ids = <String>{};
    final slots = <ProviderWeeklySlotItem>[];
    for (final raw in rawSlots) {
      if (raw is! Map ||
          raw['slot_id'] is! String ||
          !RegExp(r'^[0-9a-f-]{36}$').hasMatch(raw['slot_id'] as String) ||
          !ids.add(raw['slot_id'] as String) ||
          !integer(raw['weekday'], 1, 7) ||
          !integer(raw['start_minute'], 0, 1439) ||
          !integer(raw['end_minute'], 1, 1440) ||
          (raw['end_minute'] as int) <= (raw['start_minute'] as int)) {
        throw const FormatException('Could not verify working hours.');
      }
      slots.add(ProviderWeeklySlotItem(
          id: raw['slot_id'] as String,
          weekday: raw['weekday'] as int,
          startMinute: raw['start_minute'] as int,
          endMinute: raw['end_minute'] as int));
    }
    final required = <ProviderRequiredInterval>[];
    for (final raw in rawRequired) {
      if (raw is! Map ||
          !integer(raw['weekday'], 1, 7) ||
          !integer(raw['start_minute'], 0, 1439) ||
          !integer(raw['end_minute'], 1, 1440) ||
          (raw['end_minute'] as int) <= (raw['start_minute'] as int) ||
          !integer(raw['booking_count'], 1, 2147483647)) {
        throw const FormatException('Could not verify confirmed jobs.');
      }
      required.add(ProviderRequiredInterval(
          raw['weekday'] as int,
          raw['start_minute'] as int,
          raw['end_minute'] as int,
          raw['booking_count'] as int));
    }
    if (rawServices.any((value) =>
        value is! String || !RegExp(r'^[0-9a-f-]{36}$').hasMatch(value))) {
      throw const FormatException('Could not verify required services.');
    }
    slots.sort((a, b) => a.weekday != b.weekday
        ? a.weekday.compareTo(b.weekday)
        : a.startMinute.compareTo(b.startMinute));
    return ProviderWeeklyState(
        providerId: actor,
        revision: revision,
        slots: List.unmodifiable(slots),
        required: List.unmodifiable(required),
        requiredServices: Set.unmodifiable(rawServices.cast<String>()));
  }

  List<ProviderWorkingRange> rangesFor(int day) => slots
      .where((slot) => slot.weekday == day)
      .map((slot) => ProviderWorkingRange(slot.startMinute, slot.endMinute))
      .toList();
  int countFor(int day) => required
      .where((item) => item.weekday == day)
      .fold(0, (count, item) => count + item.count);
  String? validateDay(int day, List<ProviderWorkingRange> ranges) {
    if (day < 1 || day > 7 || ranges.length > 12)
      return 'Choose valid working hours.';
    final sorted = List<ProviderWorkingRange>.of(ranges)
      ..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 0; i < sorted.length; i++) {
      final range = sorted[i];
      if (range.start < 0 ||
          range.end > 1439 ||
          range.end - range.start < 120) {
        return 'Each working slot must be at least 2 hours within one day.';
      }
      if (i > 0 && range.start < sorted[i - 1].end)
        return 'Working slots cannot overlap.';
    }
    for (final job in required.where((item) => item.weekday == day)) {
      if (!ranges
          .any((range) => range.start <= job.start && range.end >= job.end)) {
        final starts = ProviderSlotRules.databaseTime(job.start);
        final ends =
            job.end == 1440 ? '24:00' : ProviderSlotRules.databaseTime(job.end);
        return 'Keep $starts–$ends available for a confirmed job.';
      }
    }
    return null;
  }
}

/// Fresh date-only constraints for the MYT day-off calendar. These are an early
/// interaction check; the database still serialises acceptance and availability.
class ProviderDayOffConstraints {
  const ProviderDayOffConstraints({
    required this.firstDate,
    required this.lastDate,
    required this.confirmedDates,
    required this.unavailableDates,
  });
  final DateTime firstDate, lastDate;
  final Set<String> confirmedDates, unavailableDates;

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  bool allows(DateTime date) {
    final key = dateKey(date);
    return key.compareTo(dateKey(firstDate)) >= 0 &&
        key.compareTo(dateKey(lastDate)) <= 0 &&
        !confirmedDates.contains(key) &&
        !unavailableDates.contains(key);
  }
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
