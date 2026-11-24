import 'package:smart_rental_management/owner_provider/features/availability/domain/provider_setup.dart';

ProviderWeeklyState weeklyHoursFixture({
  List<ProviderWeeklySlotItem> slots = const [],
  List<ProviderRequiredInterval> required = const [],
  Set<String> services = const {},
}) =>
    ProviderWeeklyState(
      providerId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      revision: '00000000000000000000000000000000',
      slots: slots,
      required: required,
      requiredServices: services,
    );
