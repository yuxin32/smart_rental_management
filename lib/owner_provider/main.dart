// lib/main.dart
// Dual-mode app entry. Without Supabase settings it preserves the local demo;
// with settings it opens the connected workspace and never mixes demo rows
// with authenticated data. Provides shared:
//   - AppProviders (theme + booking store + provider store)
//   - UserSessionAccess (login + onboarding state + providerId)
//
// Local route: Login -> Onboarding (first run) -> Owner Home.
// Connected route: verified login -> server-backed workspace.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/device_preferences.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'widgets/connected_route_lifecycle.dart';
import 'widgets/message_unread_scope.dart';
import 'widgets/safe_error_boundary.dart';
import 'screens/workspace_entry_screen.dart';
import 'screens/workspace_home.dart';
import 'screens/backend_setup_required_screen.dart';
import 'widgets/backend_environment_frame.dart';
import 'screens/onboarding_screen.dart';
import 'screens/owner_home_screen.dart';
import 'screens/provider_inbox_screen.dart';
import 'models/local_preview_data.dart';
import 'services/booking_store.dart';
import 'services/backend/backend_config.dart';
import 'services/backend/auth_session_storage.dart';
import 'services/backend/supabase_backend_provider.dart';
import 'services/message_store.dart';
import 'services/provider_store.dart';
import 'services/property_store.dart';
import 'services/review_store.dart';
import 'services/user_session.dart';
import 'services/prototype_support_store.dart';
import 'theme/app_theme.dart';
import 'screens/reset_password_screen.dart';
import 'services/backend/recovery_web_callback_stub.dart'
    if (dart.library.js_interop) 'services/backend/recovery_web_callback.dart';

// Retain a captured callback only in memory across connection-setup retries.
// Its URL has already been scrubbed; never persist or log this value.
Uri? _pendingRecoveryCallback;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installSafeErrorBoundaries();
  _pendingRecoveryCallback ??= takeRecoveryWebCallback();
  final recoveryCallback = _pendingRecoveryCallback;
  const backendConfig = BackendConfig.fromEnvironment();
  runApp(
    MaterialApp(
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Checking secure connection'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  SupabaseBackendProvider? backend;
  try {
    backend = await SupabaseBackendProvider.initialize(
      backendConfig,
      webRecoveryCallback: recoveryCallback,
    );
  } catch (error) {
    // Fail closed without logging credentials or falling back to sample data.
    runApp(
      MaterialApp(
        theme: AppTheme.light(),
        debugShowCheckedModeBanner: false,
        initialRoute: '/',
        home: BackendSetupRequiredScreen(
          onRetry: main,
          storageUnavailable: error is AuthStorageException,
        ),
      ),
    );
    return;
  }
  final localPreviewRole = kDebugMode && backend == null
      ? switch (Uri.base.queryParameters['preview']) {
          'owner' => UserRole.owner,
          'provider' => UserRole.provider,
          _ => null,
        }
      : null;
  _pendingRecoveryCallback = null;
  runApp(RentalAppDemo(backend: backend, localPreviewRole: localPreviewRole));
}

class RentalAppDemo extends StatefulWidget {
  const RentalAppDemo({super.key, this.backend, this.localPreviewRole});

  final SupabaseBackendProvider? backend;

  /// Debug-only sample-data preview. Never bypasses a connected backend.
  final UserRole? localPreviewRole;

  @override
  State<RentalAppDemo> createState() => _RentalAppDemoState();
}

class _RentalAppDemoState extends State<RentalAppDemo>
    with WidgetsBindingObserver {
  final _routeObserver = RouteObserver<ModalRoute<dynamic>>();
  StreamSubscription<dynamic>? _authSubscription;
  String? _connectedUserId;
  int _connectedSessionGeneration = 0;
  late ThemeMode _themeMode = kDebugMode &&
          widget.backend == null &&
          widget.localPreviewRole != null &&
          Uri.base.queryParameters['theme'] == 'dark'
      ? ThemeMode.dark
      : ThemeMode.light;
  final _devicePreferences = DevicePreferences();
  bool _themeChosen = false;
  bool _restoringConnectedSession = false;
  bool _recoveryBlocked = false;
  final ProviderStore _providerStore = ProviderStore();
  final PropertyStore _propertyStore = PropertyStore();
  late final BookingStore _bookingStore = BookingStore(
    providerStore: _providerStore,
    propertyStore: _propertyStore,
    initialBookings:
        kDebugMode && widget.backend == null && widget.localPreviewRole != null
            ? LocalPreviewData.bookings()
            : null,
  );
  final ReviewStore _reviewStore = ReviewStore();
  final MessageStore _messageStore = MessageStore();
  final UserSession _userSession = UserSession();
  late final _prototypeSupport = PrototypeSupportStore(
      enabled: widget.backend == null);

  void _syncPrototypeSession() {
    final account = !_userSession.isLoggedIn
        ? null
        : widget.backend != null
            ? widget.backend!.client.auth.currentUser?.id
            : 'local:${_userSession.role.name}:${_userSession.email.toLowerCase()}';
    _prototypeSupport.bindSession(account);
    unawaited(_devicePreferences.bindAccount(account));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _userSession.addListener(_syncPrototypeSession);
    _restoreAppearance();
    if (widget.backend != null) {
      _recoveryBlocked = widget.backend!.recovery?.blocksWorkspace ?? false;
      widget.backend!.recovery?.addListener(_onRecoveryChanged);
      _connectedUserId = widget.backend!.client.auth.currentUser?.id;
      widget.backend!.cache.bindSession(_connectedUserId);
      widget.backend!.snapshots.bindSession(_connectedUserId);
      PaintingBinding.instance.imageCache.maximumSizeBytes = 20 * 1024 * 1024;
      PaintingBinding.instance.imageCache.maximumSize = 64;
      _authSubscription = widget.backend!.client.auth.onAuthStateChange.listen(
        (state) => _onConnectedIdentity(state.session?.user.id),
        // Offline token-refresh failures are not a confirmed sign-out. The
        // live views expose their own connection failure and server RLS still
        // controls access. Do not crash or silently change the local role.
        onError: (Object _) {},
      );
      _restoringConnectedSession = !_recoveryBlocked;
      if (!_recoveryBlocked) _restoreConnectedSession();
    } else if (kDebugMode && widget.localPreviewRole != null) {
      final role = widget.localPreviewRole!;
      _userSession.signIn(
        email: role == UserRole.owner
            ? 'owner-preview@example.invalid'
            : 'provider-preview@example.invalid',
        displayName:
            role == UserRole.owner ? 'Owner Preview' : 'Provider Preview',
        role: role,
      );
      _userSession.markOnboardingSeen();
    }
  }

  void _onConnectedIdentity(String? userId) {
    if (!mounted || userId == _connectedUserId) return;
    final previous = _connectedUserId;
    _connectedUserId = userId;
    _prototypeSupport.bindSession(null);
    widget.backend?.cache.bindSession(userId);
    widget.backend?.snapshots.bindSession(userId);
    if (previous != null) {
      _clearDecodedImages();
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _clearDecodedImages());
      _userSession.signOut();
      setState(() {
        ++_connectedSessionGeneration;
        _restoringConnectedSession = false;
      });
    }
  }

  void _onRecoveryChanged() {
    final blocked = widget.backend?.recovery?.blocksWorkspace ?? false;
    if (!mounted || blocked == _recoveryBlocked) return;
    widget.backend?.cache.clear();
    widget.backend?.snapshots.clear();
    _clearDecodedImages();
    _userSession.signOut();
    setState(() {
      _recoveryBlocked = blocked;
      _restoringConnectedSession = false;
      ++_connectedSessionGeneration;
    });
  }

  void _clearDecodedImages() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  @override
  void didHaveMemoryPressure() {
    widget.backend?.cache.clear();
    widget.backend?.snapshots.clear();
    if (widget.backend != null) _clearDecodedImages();
  }

  @override
  void dispose() {
    _userSession.removeListener(_syncPrototypeSession);
    _prototypeSupport.dispose();
    widget.backend?.recovery?.removeListener(_onRecoveryChanged);
    unawaited(widget.backend?.recoveryLinks?.dispose() ?? Future<void>.value());
    WidgetsBinding.instance.removeObserver(this);
    widget.backend?.cache.clear();
    widget.backend?.snapshots.clear();
    if (widget.backend != null) _clearDecodedImages();
    unawaited(_authSubscription?.cancel() ?? Future<void>.value());
    _userSession.dispose();
    _devicePreferences.dispose();
    super.dispose();
  }

  Future<void> _restoreConnectedSession() async {
    final generation = _connectedSessionGeneration;
    final expectedUser = widget.backend!.client.auth.currentUser?.id;
    try {
      final identity = await widget.backend!.auth.currentIdentity();
      if (!mounted ||
          _recoveryBlocked ||
          identity == null ||
          generation != _connectedSessionGeneration ||
          identity.userId != expectedUser ||
          widget.backend!.client.auth.currentUser?.id != expectedUser) return;
      _userSession.signIn(
        email: identity.email,
        displayName: identity.displayName ?? '',
        role: identity.role,
        providerId: identity.role == UserRole.provider ? identity.userId : null,
      );
    } catch (_) {
      // Keep the user at the real login screen if the backend cannot verify
      // this persisted session; never substitute a demo identity.
    } finally {
      if (mounted && generation == _connectedSessionGeneration) {
        setState(() => _restoringConnectedSession = false);
      }
    }
  }

  Future<void> _restoreAppearance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString('appearance:theme');
      if (mounted && !_themeChosen && value != null) {
        setState(() => _themeMode = ThemeMode.values.firstWhere(
            (m) => m.name == value,
            orElse: () => ThemeMode.system));
      }
    } catch (_) {/* Keep the current usable theme. */}
  }

  Future<void> _setThemeMode(ThemeMode value) async {
    _themeChosen = true;
    setState(() => _themeMode = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString('appearance:theme', value.name))
        throw StateError('Preference not saved');
    } catch (_) {
      // The appearance page reports persistence failure through this Future.
      rethrow;
    }
  }

  void _toggleTheme() {
    unawaited(_setThemeMode(
            _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light)
        .catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    return AppProviders(
      themeMode: _themeMode,
      onToggleTheme: _toggleTheme,
      onSetThemeMode: _setThemeMode,
      devicePreferences: _devicePreferences,
      bookingStore: _bookingStore,
      providerStore: _providerStore,
      propertyStore: _propertyStore,
      reviewStore: _reviewStore,
      messageStore: _messageStore,
      backend: widget.backend,
      prototypeSupport: _prototypeSupport,
      child: UserSessionAccess(
        session: _userSession,
        child: ConnectedRouteScope(
          observer: _routeObserver,
          child: MaterialApp(
            key: ValueKey(_connectedSessionGeneration),
            navigatorObservers: [_routeObserver],
            title: 'Smart Rental Manager',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: _themeMode,
            debugShowCheckedModeBanner: false,
            initialRoute: '/',
            builder: (context, child) => BackendEnvironmentFrame(
              config: widget.backend?.config,
              connected: widget.backend != null,
              child: MessageUnreadHost(
                  backend: widget.backend,
                  session: _userSession,
                  child: child ?? const SizedBox.shrink()),
            ),
            home: _recoveryBlocked
                ? ResetPasswordScreen(controller: widget.backend!.recovery!)
                : _restoringConnectedSession
                    ? const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      )
                    : _RootRouter(backend: widget.backend),
          ),
        ),
      ),
    );
  }
}

class _RootRouter extends StatefulWidget {
  const _RootRouter({this.backend});

  final SupabaseBackendProvider? backend;

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  @override
  Widget build(BuildContext context) {
    final session = UserSessionAccess.of(context);
    return AnimatedBuilder(
      animation: session,
      builder: (ctx, _) {
        if (!session.isLoggedIn) {
          return WorkspaceEntryScreen(backend: widget.backend);
        }
        if (widget.backend != null) {
          return WorkspaceHome(
            backend: widget.backend!,
            role: session.role,
          );
        }
        if (!session.hasSeenOnboarding) return const OnboardingScreen();
        // If provider, route to Provider Inbox. Otherwise Owner Home.
        return session.role == UserRole.provider
            ? const _ProviderEntry()
            : const OwnerHomeScreen();
      },
    );
  }
}

class _ProviderEntry extends StatefulWidget {
  const _ProviderEntry();
  @override
  State<_ProviderEntry> createState() => _ProviderEntryState();
}

class _ProviderEntryState extends State<_ProviderEntry> {
  @override
  void initState() {
    super.initState();
    // After first frame, sync providerId from session → store
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = UserSessionAccess.of(context);
      final store = AppProviders.of(context).providerStore;
      if (session.providerId != null) {
        store.setCurrentProviderId(session.providerId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Default to Provider A for demo
    return const ProviderInboxScreen(provider: null);
  }
}

/// Top-level providers: theme + booking store + provider store.
class AppProviders extends InheritedWidget {
  const AppProviders({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
    required this.bookingStore,
    required this.providerStore,
    required this.propertyStore,
    required this.reviewStore,
    required this.messageStore,
    this.backend,
    this.prototypeSupport,
    this.devicePreferences,
    this.onSetThemeMode,
    required super.child,
  });

  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode)? onSetThemeMode;
  final DevicePreferences? devicePreferences;
  final VoidCallback onToggleTheme;
  final BookingStore bookingStore;
  final ProviderStore providerStore;
  final PropertyStore propertyStore;
  final ReviewStore reviewStore;
  final MessageStore messageStore;
  final SupabaseBackendProvider? backend;
  final PrototypeSupportStore? prototypeSupport;

  static AppProviders? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppProviders>();

  static AppProviders of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<AppProviders>();
    assert(result != null, 'No AppProviders found in context');
    return result!;
  }

  bool get isDark => themeMode == ThemeMode.dark;

  @override
  bool updateShouldNotify(AppProviders oldWidget) =>
      oldWidget.themeMode != themeMode;
}

/// Backwards-compat shim. Old code used `RentalTheme.of(context)`.
class RentalTheme {
  RentalTheme._();
  static AppProviders of(BuildContext context) => AppProviders.of(context);
  static bool get isDark => false; // not used standalone
  static VoidCallback get onToggle => () {}; // not used standalone
}
