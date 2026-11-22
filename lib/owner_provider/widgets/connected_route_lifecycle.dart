import 'package:flutter/widgets.dart';

/// One observer per Navigator. Modal sheets/dialogs also suspend the page below.
class ConnectedRouteScope extends InheritedWidget {
  const ConnectedRouteScope({
    super.key,
    required this.observer,
    required super.child,
  });
  final RouteObserver<ModalRoute<dynamic>> observer;

  static RouteObserver<ModalRoute<dynamic>>? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ConnectedRouteScope>()
          ?.observer;

  @override
  bool updateShouldNotify(ConnectedRouteScope oldWidget) =>
      observer != oldWidget.observer;
}

/// Only a current, resumed route may maintain live subscriptions. Changes are
/// delivered after the frame to avoid mutating descendants during route builds.
mixin ConnectedRouteLifecycle<T extends StatefulWidget> on State<T>
    implements RouteAware {
  late final _appObserver = _RouteAppObserver(didChangeAppLifecycleState);
  RouteObserver<ModalRoute<dynamic>>? _observer;
  ModalRoute<dynamic>? _route;
  bool _routeVisible = true;
  bool _foreground = true;
  bool _active = false;
  bool _queued = false;
  final ValueNotifier<bool> connectedRouteActivity = ValueNotifier(false);
  bool get connectedRouteActive => _active;

  void onConnectedRouteActivity(bool active);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_appObserver);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = ConnectedRouteScope.maybeOf(context);
    final route = ModalRoute.of(context);
    if (_observer != observer || _route != route) {
      _observer?.unsubscribe(this);
      _observer = observer;
      _route = route;
      _routeVisible = route?.isCurrent ?? true;
      if (observer != null && route != null) observer.subscribe(this, route);
    }
    _scheduleActivity();
  }

  void _scheduleActivity() {
    // Backgrounded apps may not draw another frame. Tear down immediately;
    // only activation needs to wait for a safe build boundary.
    if (_active && (!_routeVisible || !_foreground)) {
      _active = false;
      connectedRouteActivity.value = false;
      onConnectedRouteActivity(false);
    }
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted) return;
      final active = _routeVisible && _foreground;
      if (_active == active) return;
      _active = active;
      connectedRouteActivity.value = active;
      onConnectedRouteActivity(active);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _scheduleActivity();
  }

  @override
  void didPush() {
    _routeVisible = _route?.isCurrent ?? true;
    _scheduleActivity();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _scheduleActivity();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _scheduleActivity();
  }

  @override
  void didPop() {
    _routeVisible = false;
    _scheduleActivity();
  }

  @override
  void dispose() {
    _observer?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(_appObserver);
    connectedRouteActivity.dispose();
    super.dispose();
  }
}

class _RouteAppObserver with WidgetsBindingObserver {
  _RouteAppObserver(this.onChanged);
  final ValueChanged<AppLifecycleState> onChanged;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChanged(state);
}
