import 'package:flutter/material.dart';
import '../services/backend/notification_binding.dart';
import '../services/backend/supabase_backend_provider.dart';
import '../services/user_session.dart';
import '../widgets/connected_route_lifecycle.dart';
import '../widgets/workspace_actions.dart';
import 'notifications_screen.dart';

class WorkspaceNotifications extends StatefulWidget {
  const WorkspaceNotifications(
      {super.key, required this.backend, required this.role});
  final SupabaseBackendProvider backend;
  final UserRole role;
  @override
  State<WorkspaceNotifications> createState() => _WorkspaceNotificationsState();
}

class _WorkspaceNotificationsState extends State<WorkspaceNotifications>
    with ConnectedRouteLifecycle<WorkspaceNotifications> {
  late final NotificationBinding binding;
  @override
  void initState() {
    super.initState();
    binding = NotificationBinding.connected(widget.backend,
        provider: widget.role == UserRole.provider);
  }

  @override
  void onConnectedRouteActivity(bool active) => binding.setActive(active);
  @override
  void dispose() {
    binding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotificationsScreen(
      role: widget.role == UserRole.provider ? 'Provider' : 'Owner',
      binding: binding,
      onOpenBooking: (id) =>
          WorkspaceActions(widget.backend, widget.role).booking(context, id));
}
