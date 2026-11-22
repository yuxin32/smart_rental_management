import 'package:flutter/material.dart';
import '../main.dart';
import '../screens/account_settings_screens.dart';
import '../screens/owner_booking_feed.dart';
import '../services/backend/supabase_booking_repository.dart';

import '../screens/connected_booking_request_screen.dart';
import '../screens/connected_property_form_screen.dart';
import '../screens/connected_provider_setup_screen.dart';
import '../screens/connected_workspace_screen.dart';
import '../screens/workspace_schedule.dart';
import '../screens/workspace_earnings.dart';
import '../screens/workspace_profile.dart';
import '../screens/workspace_notifications.dart';
import '../screens/workspace_messages.dart';
import '../screens/workspace_owner_profile.dart';
import '../screens/workspace_properties.dart';
import '../screens/workspace_reports.dart';
import '../screens/about_screen.dart';
import '../screens/owner_records_view.dart';
import '../services/backend/owner_navigation_repository.dart';
import 'provider_workspace_navigation.dart';
import 'owner_workspace_navigation.dart';
import '../services/backend/supabase_backend_provider.dart';
import '../services/backend/safe_diagnostics.dart';
import '../services/user_session.dart';

/// Existing protected operations behind the original home/inbox visuals.
/// New home data never enters the local preview stores.
class WorkspaceActions {
  const WorkspaceActions(this.backend, this.role);
  final SupabaseBackendProvider backend;
  final UserRole role;
  Future<void> properties(BuildContext context) async {
    if (role != UserRole.owner) return;
    await ownerTab(context, 'properties');
  }

  Widget ownerDestination(
          BuildContext context, String activeId, Widget child) =>
      OwnerDestinationFrame(
          activeId: activeId,
          onChange: (id) => ownerTab(context, id),
          child: child);

  Future<void> ownerTab(BuildContext context, String id) async {
    if (role != UserRole.owner ||
        !const {'home', 'properties', 'browse', 'bookings', 'profile'}
            .contains(id)) return;
    await OwnerTabNavigation.open(
        context,
        id,
        (context) => switch (id) {
              'properties' => WorkspaceProperties(backend: backend),
              'profile' => WorkspaceOwnerProfile(backend: backend),
              _ => _directory(context),
            });
  }

  Future<void> browse(BuildContext context) => ownerTab(context, 'browse');

  Widget _directory(BuildContext context) => ownerDestination(
      context,
      'browse',
      Scaffold(
        appBar: AppBar(title: const Text('Providers')),
        body: OwnerRecordsView(
          providers: true,
          openFeed: OwnerNavigationRepository(backend).open,
          onProvider: (row) =>
              Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => OwnerRootNavigation.inherit(
                context,
                Builder(
                  builder: (detailContext) => ownerDestination(
                      detailContext, 'browse', OwnerProviderDetails(row: row)),
                )),
          )),
        ),
      ));

  Future<void> bookingsByStatus(
      BuildContext context, OwnerBookingGroup group) async {
    if (role != UserRole.owner) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => OwnerRootNavigation.inherit(
            context,
            Builder(
                builder: (scopedContext) => ownerDestination(
                    scopedContext,
                    'bookings',
                    OwnerBookingFeed(
                        backend: backend,
                        group: group,
                        onBooking: (item) =>
                            booking(scopedContext, item.id)))))));
  }

  Future<void> spending(BuildContext context) async {
    if (role != UserRole.owner) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorkspaceReports(backend: backend, provider: false)));
  }

  Future<void> statistics(BuildContext context) async {
    if (role != UserRole.provider) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorkspaceReports(backend: backend, provider: true)));
  }

  Future<void> messages(BuildContext context) async =>
      Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => WorkspaceMessages(backend: backend, role: role)));

  Future<void> settings(BuildContext context, String page) async {
    final app = AppProviders.of(context);
    final session = UserSessionAccess.of(context);
    final child = switch (page) {
      'appearance' => const AppearanceSettingsScreen(),
      'notifications' => NotificationSettingsScreen(
          preferences: app.devicePreferences!,
          openNotifications: () => notifications(context)),
      _ => PrivacySecurityScreen(
          email: session.email,
          role: role == UserRole.owner
              ? 'Property Owner'
              : 'Cleaning Service Provider',
          onSignOut: () => signOut(context)),
    };
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => OwnerRootNavigation.inherit(
            context,
            Builder(
                builder: (c) => role == UserRole.owner
                    ? ownerDestination(c, 'profile', child)
                    : Scaffold(
                        body: child,
                        bottomNavigationBar:
                            providerNavigation(c, 'profile'))))));
  }

  Future<void> notifications(BuildContext context) async =>
      Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) =>
              WorkspaceNotifications(backend: backend, role: role)));

  Future<void> about(BuildContext context) async {
    final app = AppProviders.of(context);
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) =>
            OwnerRootNavigation.inherit(context, Builder(builder: (c) {
              final page = AboutScreen(
                  environmentLabel: backend.config?.environmentName,
                  prototypeSupport: app.prototypeSupport);
              return role == UserRole.owner
                  ? ownerDestination(c, 'profile', page)
                  : Scaffold(
                      body: page,
                      bottomNavigationBar: providerNavigation(c, 'profile'));
            }))));
  }

  Widget providerNavigation(BuildContext context, String activeId) =>
      ProviderBottomNav(
          activeId: activeId, onChange: (id) => providerTab(context, id));

  Future<void> providerTab(BuildContext context, String id) async {
    if (role != UserRole.provider) return;
    if (!const {'inbox', 'schedule', 'earnings', 'profile'}.contains(id))
      return;
    await ProviderTabNavigation.open(
        context,
        id,
        (_) => switch (id) {
              'schedule' => WorkspaceSchedule(backend: backend, role: role),
              'earnings' => WorkspaceEarnings(backend: backend),
              _ => WorkspaceProfile(backend: backend),
            });
  }

  Future<void> profile(BuildContext context, {bool edit = false}) async {
    if (role == UserRole.owner) {
      await ownerTab(context, 'profile');
      return;
    }
    if (!edit) {
      await providerTab(context, 'profile');
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorkspaceProfile(backend: backend, edit: edit)));
  }

  Future<void> earnings(BuildContext context) async {
    if (role != UserRole.provider) return;
    await providerTab(context, 'earnings');
  }

  Future<void> schedule(BuildContext context) async {
    if (role == UserRole.provider) {
      await providerTab(context, 'schedule');
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorkspaceSchedule(backend: backend, role: role)));
  }

  Future<void> request(BuildContext context) => _request(context);
  Future<void> requestForProperty(BuildContext context, String propertyId) =>
      _request(context, propertyId: propertyId);
  Future<void> _request(BuildContext context, {String? propertyId}) async {
    if (role != UserRole.owner) return;
    final submitted = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _requestScreen(propertyId: propertyId),
    ));
    if (submitted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('Request sent. Waiting for the provider to respond.')));
    }
  }

  Widget _requestScreen({String? propertyId}) {
    final owner = backend.owner;
    return ConnectedBookingRequestScreen(
      initialPropertyId: propertyId,
      loadProperties: owner.properties,
      loadServiceTypes: owner.serviceTypes,
      findEligible: owner.eligibleProviders,
      createPending: backend.bookings.createPending,
      findCreatedBooking: backend.bookings.createdBookingIdForToken,
    );
  }

  Future<void> addProperty(BuildContext context) async {
    if (role != UserRole.owner) return;
    final actor = backend.client.auth.currentUser?.id;
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ConnectedPropertyFormScreen(
          loadBuildingOptions: backend.owner.properties,
          canSave: () =>
              actor != null && backend.client.auth.currentUser?.id == actor,
          onSave: (input) async {
            if (actor == null || backend.client.auth.currentUser?.id != actor)
              throw StateError('Session changed');
            await backend.owner.addProperty(
              unitName: input.unitName,
              buildingName: input.buildingName,
              address: input.address,
              bedrooms: input.bedrooms,
              sizeSqft: input.sizeSqft,
              cleaningWindowStart: input.cleaningWindowStart,
              cleaningWindowEnd: input.cleaningWindowEnd,
            );
          }),
    ));
  }

  Future<void> providerSetup(BuildContext context) async {
    if (role != UserRole.provider) return;
    final provider = backend.provider;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ConnectedProviderSetupScreen(
        initialData: provider.cachedSetup,
        load: provider.loadSetup,
        saveServices: provider.replaceCapabilities,
        addSlot: (day, start, end) => provider.addWeeklySlot(
            weekday: day, startTime: start, endTime: end),
        removeSlot: provider.removeWeeklySlot,
        addUnavailableDate: provider.addUnavailableDate,
        removeUnavailableDate: provider.removeUnavailableDate,
      ),
    ));
  }

  Future<void> booking(BuildContext context, String id) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) =>
          OwnerRootNavigation.inherit(context, Builder(builder: (c) {
        final detail = ConnectedWorkspaceScreen(
            backend: backend, role: role, bookingId: id);
        return role == UserRole.owner
            ? ownerDestination(c, 'bookings', detail)
            : detail;
      })),
    ));
  }

  Future<void> signOut(BuildContext context) async {
    try {
      await backend.auth.signOut();
      if (context.mounted) UserSessionAccess.of(context).signOut();
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.signOut, error);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not sign out. Check your connection and try again.')));
      }
    }
  }

  void unavailable(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '$label is unavailable. Check your connection and try again.')));
  }
}
