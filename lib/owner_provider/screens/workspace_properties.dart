import 'package:flutter/material.dart';
import '../services/backend/supabase_backend_provider.dart';
import '../services/backend/supabase_workspace_repository.dart';
import '../services/backend/workspace_binding.dart';
import '../services/user_session.dart';
import '../widgets/owned_workspace_page.dart';
import '../widgets/workspace_actions.dart';
import '../widgets/owner_workspace_navigation.dart';
import 'property_list_screen.dart';
import 'property_detail_screen.dart';
import 'connected_property_form_screen.dart';

class WorkspaceProperties extends StatelessWidget {
  const WorkspaceProperties(
      {super.key, required this.backend, this.propertyId});
  final SupabaseBackendProvider backend;
  final String? propertyId;
  @override
  Widget build(BuildContext context) {
    final repo = SupabaseWorkspaceRepository(backend),
        actions = WorkspaceActions(backend, UserRole.owner);
    return actions.ownerDestination(
        context, 'properties', _content(context, repo, actions));
  }

  Widget _content(BuildContext context, SupabaseWorkspaceRepository repo,
      WorkspaceActions actions) {
    if (propertyId == null)
      return OwnedWorkspacePage(
          backend: backend,
          title: 'My properties',
          cacheKey: 'owner:properties:v1',
          idField: 'property_id',
          load: repo.properties,
          builder: (context, binding) => PropertyListScreen(
              bookings: const [],
              connectedProperties: binding.items
                  .map(SupabaseWorkspaceRepository.propertyPresentation)
                  .toList(),
              totalCount: binding.snapshot!['total_count'] as int,
              portfolio:
                  binding.snapshot!['portfolio'] as Map<String, dynamic>?,
              connectedCounts: {
                for (final row in binding.items)
                  row['property_id'] as String: [
                    row['open'] as int,
                    row['done'] as int,
                    row['total'] as int
                  ]
              },
              footer: ownedPageFooter(binding),
              onRefreshConnected: binding.refresh,
              onAddConnected: () async {
                await actions.addProperty(context);
                if (binding.valid) await binding.refresh();
              },
              onOpenConnected: (p) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => OwnerRootNavigation.inherit(
                          context,
                          WorkspaceProperties(
                              backend: backend, propertyId: p.id))))));
    // A fresh own-property projection and a separately bounded booking feed.
    return OwnedWorkspacePage(
        backend: backend,
        title: 'Property',
        load: ({before, asOf}) => repo.property(propertyId!),
        builder: (context, propertyBinding) {
          final row = propertyBinding.snapshot!,
              property = SupabaseWorkspaceRepository.propertyPresentation(row);
          return OwnedWorkspacePage(
              backend: backend,
              title: property.display,
              load: ({before, asOf}) =>
                  repo.propertyBookings(property.id, before: before),
              builder: (context, bookings) => PropertyDetailScreen(
                  connected: true,
                  property: property,
                  bookings: bookings.items
                      .map(WorkspaceBinding.projectBooking)
                      .toList(),
                  totalBookings: row['total'] as int,
                  onRefreshConnected: () async {
                    await propertyBinding.refresh();
                    await bookings.refresh();
                  },
                  footer: ownedPageFooter(bookings),
                  onOpenBookingConnected: (id) => actions.booking(context, id),
                  onRequestConnected: () =>
                      actions.requestForProperty(context, property.id),
                  onEditConnected: () async {
                    try {
                      final fresh = await repo.property(property.id);
                      if (!context.mounted || !propertyBinding.valid) return;
                      await Navigator.of(context).push<bool>(MaterialPageRoute(
                          builder: (_) => ConnectedPropertyFormScreen(
                              loadBuildingOptions: backend.owner.properties,
                              initial: SupabaseWorkspaceRepository
                                  .propertyPresentation(fresh,
                                      displayLabels: false),
                              canSave: () => propertyBinding.valid,
                              onSave: (input) async {
                                if (!propertyBinding.valid)
                                  throw StateError('Session changed');
                                await repo.saveProperty(property.id,
                                    fresh['property_revision'] as int, {
                                  'unit_name': input.unitName,
                                  'building_name': input.buildingName,
                                  'address': input.address,
                                  'bedrooms': input.bedrooms,
                                  'size_sqft': input.sizeSqft,
                                  'cleaning_window_start':
                                      input.cleaningWindowStart,
                                  'cleaning_window_end': input.cleaningWindowEnd
                                });
                              })));
                      if (propertyBinding.valid)
                        await propertyBinding.refresh();
                    } catch (_) {
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                'Could not open property editor. Please retry.')));
                    }
                  }));
        });
  }
}
