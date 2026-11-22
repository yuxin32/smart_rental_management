import 'package:flutter/material.dart';
import '../services/backend/provider_profile_binding.dart';
import '../services/backend/supabase_backend_provider.dart';
import '../widgets/connected_route_lifecycle.dart';
import '../widgets/connected_state_panel.dart';
import '../widgets/workspace_actions.dart';
import 'provider_profile_screen.dart';
import 'provider_edit_profile_screen.dart';
import '../services/user_session.dart';
import '../widgets/snapshot_refresh_notice.dart';

class WorkspaceProfile extends StatefulWidget {
  const WorkspaceProfile({super.key, required this.backend, this.edit = false});
  final SupabaseBackendProvider backend;
  final bool edit;
  @override
  State<WorkspaceProfile> createState() => _WorkspaceProfileState();
}

class _WorkspaceProfileState extends State<WorkspaceProfile>
    with ConnectedRouteLifecycle<WorkspaceProfile> {
  late final ProviderProfileBinding binding;
  @override
  void initState() {
    super.initState();
    binding = ProviderProfileBinding.connected(widget.backend,
        allowCached: !widget.edit);
    binding.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void onConnectedRouteActivity(bool active) =>
      binding.setActive(active, refreshOnResume: !widget.edit);
  @override
  void dispose() {
    binding.removeListener(_changed);
    binding.dispose();
    super.dispose();
  }

  Future<void> _manageAvailability() async {
    await WorkspaceActions(widget.backend, UserRole.provider)
        .providerSetup(context);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = binding.snapshot;
    if (binding.error != null || snapshot == null)
      return Scaffold(
          bottomNavigationBar: widget.edit
              ? null
              : WorkspaceActions(widget.backend, UserRole.provider)
                  .providerNavigation(context, 'profile'),
          appBar: AppBar(title: const Text('Profile')),
          body: ConnectedStatePanel(
              state: binding.loading
                  ? ConnectedViewState.loading
                  : ConnectedViewState.error,
              title: binding.sessionEnded
                  ? 'Sign in again'
                  : binding.loading
                      ? 'Loading profile'
                      : 'Could not load profile',
              message: binding.sessionEnded
                  ? 'Your account session changed. Return to sign in.'
                  : binding.loading
                      ? 'Checking your saved details.'
                      : 'Check your connection and retry.',
              actionLabel:
                  binding.loading || binding.sessionEnded ? null : 'Retry',
              onAction: binding.refresh));
    if (widget.edit)
      return ProviderEditProfileScreen(
          key: ValueKey(snapshot.revision),
          provider: snapshot.presentation,
          snapshot: snapshot,
          onSaveConnected: widget.backend.provider.saveMyProfile,
          onReloadConnected: widget.backend.provider.myProfile,
          canEditConnected: () => binding.canEdit,
          onManageAvailability: _manageAvailability);
    return ProviderProfileScreen(
        onSettings: (page) {
          final actions = WorkspaceActions(widget.backend, UserRole.provider);
          if (page == 'about') {
            actions.about(context);
          } else {
            actions.settings(context, page);
          }
        },
        refreshNotice: SnapshotRefreshNotice(
            refreshing: binding.refreshing,
            failed: binding.refreshError != null,
            onRetry: binding.refresh),
        bottomNavigationBar: WorkspaceActions(widget.backend, UserRole.provider)
            .providerNavigation(context, 'profile'),
        provider: snapshot.presentation,
        snapshot: snapshot,
        onRefresh: binding.refresh,
        onEdit: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) =>
                WorkspaceProfile(backend: widget.backend, edit: true))),
        onManageAvailability: _manageAvailability);
  }
}
