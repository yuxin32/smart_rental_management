import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/backend/safe_diagnostics.dart';

/// Install once at application entry, not during build. The original framework
/// handlers/ErrorWidget can print/paint exception text and request details.
void installSafeErrorBoundaries() {
  FlutterError.onError = (details) {
    SafeDiagnostics.app
        .record(SafeOperation.frameworkFailure, details.exception);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    SafeDiagnostics.app.record(SafeOperation.unhandledAsyncFailure, error);
    return true;
  };
  ErrorWidget.builder = (_) => const SafeErrorPlaceholder();
}

class SafeErrorPlaceholder extends StatelessWidget {
  const SafeErrorPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Color(0xFFF6F7FC),
          child: Center(
              child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
                'This screen could not be displayed. Reopen the app and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFF223168),
                    fontSize: 16,
                    decoration: TextDecoration.none,),),
          ),),
        ),
      );
}
