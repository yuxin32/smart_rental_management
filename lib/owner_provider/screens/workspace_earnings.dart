import 'package:flutter/material.dart';
import '../services/backend/earnings_binding.dart';
import '../services/backend/supabase_backend_provider.dart';
import '../widgets/connected_route_lifecycle.dart';
import 'earnings_history_screen.dart';
import '../widgets/workspace_actions.dart';
import '../services/user_session.dart';

/// Original Earnings screen owns every visual; this route only wires lifecycle.
class WorkspaceEarnings extends StatefulWidget {
  const WorkspaceEarnings({super.key, required this.backend});
  final SupabaseBackendProvider backend;
  @override
  State<WorkspaceEarnings> createState() => _WorkspaceEarningsState();
}

class _WorkspaceEarningsState extends State<WorkspaceEarnings>
    with ConnectedRouteLifecycle<WorkspaceEarnings> {
  late final EarningsBinding binding;
  @override
  void initState() {
    super.initState();
    binding = EarningsBinding.connected(widget.backend);
  }

  @override
  void onConnectedRouteActivity(bool active) => binding.setActive(active);
  @override
  void dispose() {
    binding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EarningsHistoryScreen(
      bottomNavigationBar: WorkspaceActions(widget.backend, UserRole.provider)
          .providerNavigation(context, 'earnings'),
      providerName: '',
      bookings: const [],
      binding: binding);
}
