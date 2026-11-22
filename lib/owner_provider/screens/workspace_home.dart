import 'package:flutter/material.dart';

import '../services/backend/supabase_backend_provider.dart';
import '../services/backend/workspace_binding.dart';
import '../services/user_session.dart';
import '../widgets/connected_route_lifecycle.dart';
import '../widgets/workspace_actions.dart';
import 'owner_home_screen.dart';
import 'provider_inbox_screen.dart';

/// Lifecycle/composition only. The original screens remain the UI owners.
class WorkspaceHome extends StatefulWidget {
  const WorkspaceHome({super.key, required this.backend, required this.role});
  final SupabaseBackendProvider backend;
  final UserRole role;

  @override
  State<WorkspaceHome> createState() => _WorkspaceHomeState();
}

class _WorkspaceHomeState extends State<WorkspaceHome>
    with ConnectedRouteLifecycle<WorkspaceHome> {
  late final WorkspaceBinding _binding;
  late final WorkspaceActions _actions;

  @override
  void initState() {
    super.initState();
    _binding = WorkspaceBinding.connected(widget.backend,
        provider: widget.role == UserRole.provider);
    _actions = WorkspaceActions(widget.backend, widget.role);
  }

  @override
  void onConnectedRouteActivity(bool active) => _binding.setActive(active);

  @override
  void dispose() {
    _binding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.role == UserRole.owner
      ? OwnerHomeScreen(binding: _binding, actions: _actions)
      : ProviderInboxScreen(binding: _binding, actions: _actions);
}
