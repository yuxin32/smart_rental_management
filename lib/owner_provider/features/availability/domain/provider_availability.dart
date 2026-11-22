/// A half-open local-time interval within one day: [startMinute, endMinute).
class AvailabilitySlot {
  const AvailabilitySlot(this.startMinute, this.endMinute);

  /// A provider's declared working slot must cover at least two hours.
  static const int minimumMinutes = 120;

  final int startMinute;
  final int endMinute;

  bool get isValid =>
      startMinute >= 0 &&
      endMinute <= 24 * 60 &&
      endMinute - startMinute >= minimumMinutes;

  bool covers(int start, int end) => start >= startMinute && end <= endMinute;
}

/// Weekly declared hours and whole-day exceptions. Alternative windows are
/// calculated from this data and never stored as permanent records.
class ProviderAvailabilitySchedule {
  const ProviderAvailabilitySchedule({
    required this.weeklySlots,
    this.unavailableDates = const {},
  });

  static const daily = ProviderAvailabilitySchedule(weeklySlots: {
    1: [AvailabilitySlot(8 * 60, 18 * 60)],
    2: [AvailabilitySlot(8 * 60, 18 * 60)],
    3: [AvailabilitySlot(8 * 60, 18 * 60)],
    4: [AvailabilitySlot(8 * 60, 18 * 60)],
    5: [AvailabilitySlot(8 * 60, 18 * 60)],
    6: [AvailabilitySlot(8 * 60, 18 * 60)],
    7: [AvailabilitySlot(8 * 60, 18 * 60)],
  });

  static const partialDaily = ProviderAvailabilitySchedule(weeklySlots: {
    1: [AvailabilitySlot(8 * 60, 10 * 60)],
    2: [AvailabilitySlot(8 * 60, 10 * 60)],
    3: [AvailabilitySlot(8 * 60, 10 * 60)],
    4: [AvailabilitySlot(8 * 60, 10 * 60)],
    5: [AvailabilitySlot(8 * 60, 10 * 60)],
    6: [AvailabilitySlot(8 * 60, 10 * 60)],
    7: [AvailabilitySlot(8 * 60, 10 * 60)],
  });

  static const closed = ProviderAvailabilitySchedule(weeklySlots: {});

  final Map<int, List<AvailabilitySlot>> weeklySlots;
  final Set<String> unavailableDates;

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  List<AvailabilitySlot> slotsFor(DateTime date) =>
      unavailableDates.contains(dateKey(date))
          ? const []
          : List.unmodifiable(weeklySlots[date.weekday] ?? const []);

  bool covers(DateTime start, DateTime end) {
    if (start.year != end.year ||
        start.month != end.month ||
        start.day != end.day ||
        !end.isAfter(start)) {
      return false;
    }
    final startMinute = start.hour * 60 + start.minute;
    final endMinute = end.hour * 60 + end.minute;
    return slotsFor(start).any((slot) => slot.covers(startMinute, endMinute));
  }

  ProviderAvailabilitySchedule withDaySlots(
      int weekday, List<AvailabilitySlot> slots) {
    if (weekday < 1 || weekday > 7) {
      throw ArgumentError.value(weekday, 'weekday', 'Must be 1–7');
    }
    final sorted = List<AvailabilitySlot>.of(slots)
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    if (sorted.any((slot) => !slot.isValid)) {
      throw ArgumentError.value(
          slots, 'slots', 'Working slots must be at least two hours long');
    }
    for (var index = 1; index < sorted.length; index++) {
      if (sorted[index].startMinute < sorted[index - 1].endMinute) {
        throw ArgumentError.value(slots, 'slots', 'Weekly slots overlap');
      }
    }
    return ProviderAvailabilitySchedule(
      weeklySlots: Map<int, List<AvailabilitySlot>>.unmodifiable({
        ...weeklySlots,
        weekday: List<AvailabilitySlot>.unmodifiable(sorted),
      }),
      unavailableDates: unavailableDates,
    );
  }

  ProviderAvailabilitySchedule withUnavailableDate(DateTime date,
      {required bool unavailable}) {
    final dates = Set<String>.of(unavailableDates);
    final key = dateKey(date);
    if (unavailable) {
      dates.add(key);
    } else {
      dates.remove(key);
    }
    return ProviderAvailabilitySchedule(
      weeklySlots: weeklySlots,
      unavailableDates: Set.unmodifiable(dates),
    );
  }
}
