import 'package:flutter/material.dart';
import '../services/backend/owned_workspace_binding.dart';
import '../services/backend/supabase_backend_provider.dart';
import 'connected_route_lifecycle.dart';
import 'connected_state_panel.dart';
import 'snapshot_refresh_notice.dart';

class OwnedWorkspacePage extends StatefulWidget {
  const OwnedWorkspacePage(
      {super.key,
      required this.backend,
      required this.title,
      required this.load,
      required this.builder,
      this.cacheKey,
      this.idField = 'booking_id'});
  final SupabaseBackendProvider backend;
  final String title, idField;
  final String? cacheKey;
  final OwnedWorkspaceLoader load;
  final Widget Function(BuildContext, OwnedWorkspaceBinding) builder;
  @override
  State<OwnedWorkspacePage> createState() => _OwnedWorkspacePageState();
}

class _OwnedWorkspacePageState extends State<OwnedWorkspacePage>
    with ConnectedRouteLifecycle<OwnedWorkspacePage> {
  late final OwnedWorkspaceBinding binding;
  @override
  void initState() {
    super.initState();
    final client = widget.backend.client;
    binding = OwnedWorkspaceBinding(
        load: widget.load,
        userId: client.auth.currentUser?.id ?? '',
        currentUserId: () => client.auth.currentUser?.id,
        sessions: client.auth.onAuthStateChange.map((e) => e.session?.user.id),
        cache: widget.backend.snapshots,
        cacheKey: widget.cacheKey,
        idField: widget.idField);
  }

  @override
  void onConnectedRouteActivity(bool active) => binding.setActive(active);
  @override
  void dispose() {
    binding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: binding,
      builder: (context, _) {
        if (binding.snapshot != null) return widget.builder(context, binding);
        return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: ConnectedStatePanel(
                state: binding.loading
                    ? ConnectedViewState.loading
                    : ConnectedViewState.error,
                title: binding.sessionEnded
                    ? 'Sign in again'
                    : binding.loading
                        ? 'Loading ${widget.title.toLowerCase()}'
                        : 'Could not load ${widget.title.toLowerCase()}',
                message: binding.sessionEnded
                    ? 'Your account session changed.'
                    : 'Check your connection and try again.',
                actionLabel:
                    binding.loading || binding.sessionEnded ? null : 'Retry',
                onAction: binding.refresh));
      });
}

Widget ownedPageFooter(OwnedWorkspaceBinding binding) => Column(children: [
      SnapshotRefreshNotice(
          refreshing: binding.loading,
          failed: binding.refreshError != null,
          onRetry: binding.refresh),
      if (binding.moreError != null)
        const Text('Could not show more items. You can still view the items already shown.'),
      if (binding.next != null)
        OutlinedButton(
            onPressed: binding.loadingMore ? null : binding.loadMore,
            child: Text(binding.loadingMore
                ? 'Loading…'
                : binding.moreError != null
                    ? 'Retry loading more'
                    : 'Load more')),
    ]);
