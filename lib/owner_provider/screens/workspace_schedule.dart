import 'package:flutter/material.dart';

import '../services/backend/schedule_binding.dart';
import '../services/backend/supabase_backend_provider.dart';
import '../services/user_session.dart';
import '../widgets/connected_route_lifecycle.dart';
import '../widgets/workspace_actions.dart';
import 'schedule_screen.dart';
import 'provider_schedule_screen.dart';

/// Composition/lifecycle only; original Schedule widgets own their visuals.
class WorkspaceSchedule extends StatefulWidget {
  const WorkspaceSchedule(
      {super.key, required this.backend, required this.role});
  final SupabaseBackendProvider backend;
  final UserRole role;
  @override
  State<WorkspaceSchedule> createState() => _WorkspaceScheduleState();
}

class _WorkspaceScheduleState extends State<WorkspaceSchedule>
    with ConnectedRouteLifecycle<WorkspaceSchedule> {
  late final ScheduleBinding binding;
  late final WorkspaceActions actions;
  @override
  void initState() {
    super.initState();
    binding = ScheduleBinding.connected(widget.backend,
        provider: widget.role == UserRole.provider);
    actions = WorkspaceActions(widget.backend, widget.role);
  }

  @override
  void onConnectedRouteActivity(bool active) => binding.setActive(active);
  @override
  void dispose() {
    binding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.role == UserRole.provider
      ? ProviderScheduleScreen(
          bottomNavigationBar: actions.providerNavigation(context, 'schedule'),
          providerName: '',
          bookings: const [],
          binding: binding,
          onBooking: (booking) => actions.booking(context, booking.id),
          onManageAvailability: () => actions.providerSetup(context))
      : ScheduleScreen(
          bookings: const [],
          binding: binding,
          onBooking: (booking) => actions.booking(context, booking.id));
}
