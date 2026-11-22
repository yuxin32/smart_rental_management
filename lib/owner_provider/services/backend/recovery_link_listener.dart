import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'password_recovery_controller.dart';
import 'safe_diagnostics.dart';

/// One owner for OS links; the SDK's broad URL auto-detection is disabled.
class RecoveryLinkListener {
  RecoveryLinkListener(this.controller);
  final PasswordRecoveryController controller;
  StreamSubscription<Uri>? _links;

  Future<void> start({Uri? webCallback}) async {
    if (kIsWeb) {
      if (webCallback != null) await controller.handleLink(webCallback);
      return;
    }
    final appLinks = AppLinks();
    _links = appLinks.uriLinkStream.listen((uri) {
      unawaited(controller.handleLink(uri));
    }, onError: (Object error) {
      SafeDiagnostics.app.record(SafeOperation.recoveryLink, error);
    },);
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) await controller.handleLink(initial);
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.recoveryLink, error);
    }
  }

  Future<void> dispose() async => _links?.cancel();
}
