import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/availability/domain/cleaning_package.dart';
import 'session_snapshot_cache.dart';
import 'supabase_booking_repository.dart';
import 'supabase_owner_repository.dart';

/// Authenticated package RPCs. Reads are fresh; writes are never auto-replayed.
class CleaningPackageRepository {
  CleaningPackageRepository(this.client, {this.snapshots});
  final SupabaseClient client;
  final SessionSnapshotCache? snapshots;

  // Compatibility for callers using the original package callback signature.
  // Only exact search contexts qualify, and this memory is bounded/session-bound.
  final _quotes = <String, int>{};
  String? _quoteActor;
  int? _quoteGeneration;

  // An uncertain request must keep its original revision even after a write
  // invalidates search snapshots. These are retry inputs, never fresh quotes.
  final _attempts = <String, ({String fingerprint, int revision})>{};
  String? _attemptActor;
  StreamSubscription<AuthState>? _attemptSession;
  bool _disposed = false;

  /// Release package memory and listeners without disposing the shared client.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearAttempts();
    _quotes.clear();
    _quoteActor = null;
    _quoteGeneration = null;
  }

  void _clearAttempts() {
    _attempts.clear();
    _attemptActor = null;
    final subscription = _attemptSession;
    _attemptSession = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _rememberAttempt(
    String actor,
    String token,
    String fingerprint,
    int revision,
  ) {
    if (_attemptActor != actor) _clearAttempts();
    _attemptActor = actor;
    _attemptSession ??= client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedOut ||
            state.session?.user.id != actor) {
          _clearAttempts();
        }
      },
      onError: (Object _) => _clearAttempts(),
      onDone: _clearAttempts,
    );
    _attempts.remove(token);
    _attempts[token] = (fingerprint: fingerprint, revision: revision);
    while (_attempts.length > 32) {
      _attempts.remove(_attempts.keys.first);
    }
  }

  Future<T> _run<T>(
    Future<T> Function(String actor, void Function() check) action, {
    bool writing = false,
  }) async {
    if (_disposed) throw StateError('Cleaning package repository is disposed.');
    final actor = client.auth.currentUser?.id;
    if (actor == null) {
      throw StateError('Sign in again to manage cleaning packages.');
    }
    Future<T> perform() async {
      final lease = snapshots?.lease();
      if (_quoteActor != actor || _quoteGeneration != lease?.generation) {
        _quotes.clear();
        _quoteActor = actor;
        _quoteGeneration = lease?.generation;
      }
      var ended = false;
      final subscription = client.auth.onAuthStateChange.listen(
        (state) {
          if (state.event == AuthChangeEvent.signedOut ||
              state.session?.user.id != actor) {
            ended = true;
            _quotes.clear();
            _clearAttempts();
          }
        },
        onError: (Object _) {
          ended = true;
          _quotes.clear();
          _clearAttempts();
        },
      );
      void check() {
        final current = snapshots?.lease();
        if (_disposed ||
            ended ||
            client.auth.currentUser?.id != actor ||
            lease != null &&
                (current!.userId != lease.userId ||
                    current.generation != lease.generation ||
                    !writing && !snapshots!.valid(lease))) {
          _quotes.clear();
          if (ended || client.auth.currentUser?.id != actor) _clearAttempts();
          throw StateError(
            'Session or cleaning packages changed. Refresh and try again.',
          );
        }
      }

      try {
        check();
        final result = await action(actor, check);
        check();
        return result;
      } catch (error) {
        if (rejectsSnapshot(error)) {
          snapshots?.clear();
          _quotes.clear();
        }
        rethrow;
      } finally {
        await subscription.cancel();
      }
    }

    return writing && snapshots != null ? snapshots!.write(perform) : perform();
  }

  Future<List<CleaningPackage>> myPackages() => _run((actor, check) async {
    final response = await client.rpc('my_cleaning_packages');
    check();
    if (response is! List || response.length > 1024) {
      throw const FormatException('Could not verify cleaning packages.');
    }
    final ids = <String>{}, keys = <String>{};
    final packages = <CleaningPackage>[];
    for (final raw in response) {
      if (raw is! Map) {
        throw const FormatException('Invalid cleaning package.');
      }
      final item = CleaningPackage.parse(Map<String, dynamic>.from(raw), actor);
      if (!ids.add(item.id) ||
          !keys.add(
            '${item.serviceTypeId}/${item.durationMinutes}/${item.cleanerCount}',
          )) {
        throw const FormatException('Duplicate cleaning package.');
      }
      packages.add(item);
    }
    return List.unmodifiable(packages);
  });

  Future<CleaningPackage> savePackage(
    CleaningPackageDraft draft, {
    CleaningPackage? base,
  }) async {
    final error = draft.validationError;
    if (error != null) throw ArgumentError(error);
    final actor = client.auth.currentUser?.id;
    if (actor == null ||
        base != null &&
            (base.providerId != actor ||
                base.revision < 1 ||
                !validPackageId(base.id))) {
      throw StateError('Refresh this package before saving.');
    }
    return _run((actor, check) async {
      final response = await client.rpc(
        'save_my_cleaning_package',
        params: {
          'p_service_type_id': draft.serviceTypeId,
          'p_duration_minutes': draft.durationMinutes,
          'p_cleaner_count': draft.cleanerCount,
          'p_total_price': draft.totalPrice,
          'p_package_scope': draft.scope.trim(),
          'p_enabled': draft.enabled,
          'p_expected_revision': base?.revision ?? 0,
          'p_package_id': base?.id,
        },
      );
      check();
      final saved = CleaningPackage.parse(_map(response), actor);
      if (saved.serviceTypeId != draft.serviceTypeId ||
          saved.durationMinutes != draft.durationMinutes ||
          saved.cleanerCount != draft.cleanerCount ||
          saved.totalPrice != draft.totalPrice ||
          saved.scope != draft.scope.trim() ||
          saved.enabled != draft.enabled ||
          base != null &&
              (saved.id != base.id || saved.revision <= base.revision)) {
        throw const FormatException('Could not verify the saved package.');
      }
      return saved;
    }, writing: true);
  }

  Future<ProviderSearchResult> findPackageMatches({
    required String propertyId,
    required String serviceTypeId,
    required DateTime start,
    required DateTime end,
    required int cleanerCount,
  }) async {
    _interval(start, end);
    if (!validPackageId(propertyId) ||
        !validPackageId(serviceTypeId) ||
        cleanerCount < 1 ||
        cleanerCount > 4) {
      throw ArgumentError('Select a property, cleaning service and crew.');
    }
    return _run((actor, check) async {
      final response = _map(
        await client.rpc(
          'find_package_provider_matches',
          params: {
            'p_property_id': propertyId,
            'p_service_type_id': serviceTypeId,
            'p_start_at': start.toUtc().toIso8601String(),
            'p_end_at': end.toUtc().toIso8601String(),
            'p_cleaner_count': cleanerCount,
          },
        ),
      );
      check();
      final pending = <String, int>{};
      for (final section in ['current', 'alternatives']) {
        final rows = response[section];
        if (rows is! List || rows.length > 1024) {
          throw const FormatException('Could not verify package matches.');
        }
        for (final raw in rows) {
          final row = _map(raw);
          final revision = row['package_revision'];
          final amount = row['quoted_amount'];
          if (!validPackageId(row['package_id']) ||
              !validPackageId(row['provider_id']) ||
              revision is! int ||
              revision < 1 ||
              row['cleaner_count'] != cleanerCount ||
              row['duration_minutes'] != end.difference(start).inMinutes ||
              row['package_scope'] is! String ||
              row['quote_basis'] != 'package' ||
              amount is! num ||
              !amount.isFinite ||
              amount <= 0) {
            throw const FormatException('Could not verify the package quote.');
          }
          final from = section == 'current' ? start : _time(row['start_at']);
          final until = section == 'current' ? end : _time(row['end_at']);
          if (until.difference(from) != end.difference(start)) {
            throw const FormatException('Unexpected package duration.');
          }
          pending[_key(
                propertyId,
                serviceTypeId,
                row['provider_id'] as String,
                row['package_id'] as String,
                from,
                until,
                amount,
              )] =
              revision;
        }
      }
      final result = ProviderSearchResult.fromJson(response);
      _quotes.addAll(pending);
      while (_quotes.length > 128) {
        _quotes.remove(_quotes.keys.first);
      }
      return result;
    });
  }

  Future<BookingCreationOutcome> createPackagePending({
    required String clientRequestId,
    required String providerId,
    required String propertyId,
    required String serviceTypeId,
    required DateTime start,
    required DateTime end,
    required num expectedAmount,
    required String expectedBasis,
    required String packageId,
    int? expectedPackageRevision,
    String instructions = '',
  }) async {
    _interval(start, end);
    if (![
          clientRequestId,
          providerId,
          propertyId,
          serviceTypeId,
          packageId,
        ].every(validPackageId) ||
        !expectedAmount.isFinite ||
        expectedAmount <= 0 ||
        expectedBasis != 'package') {
      throw ArgumentError(
        'Select a valid package quote before requesting cleaning.',
      );
    }
    // Capture the revision before snapshots.write invalidates search memory.
    final actor = client.auth.currentUser?.id;
    if (_attemptActor != actor) _clearAttempts();
    final lease = snapshots?.lease();
    final remembered =
        _quoteActor == actor && _quoteGeneration == lease?.generation
        ? _quotes[_key(
            propertyId,
            serviceTypeId,
            providerId,
            packageId,
            start,
            end,
            expectedAmount,
          )]
        : null;
    final fingerprint = jsonEncode([
      providerId,
      propertyId,
      serviceTypeId,
      packageId,
      start.toUtc().toIso8601String(),
      end.toUtc().toIso8601String(),
      expectedAmount.toDouble(),
      expectedBasis,
      instructions.trim(),
    ]);
    final attempt = _attempts[clientRequestId];
    if (attempt != null &&
        (attempt.fingerprint != fingerprint ||
            expectedPackageRevision != null &&
                expectedPackageRevision != attempt.revision)) {
      throw StateError(
        'This request token belongs to different booking details.',
      );
    }
    final revision = attempt?.revision ?? expectedPackageRevision ?? remembered;
    if (revision == null || revision < 1) {
      throw StateError(
        'Refresh available cleaning packages before requesting.',
      );
    }
    return _run((actor, check) async {
      _rememberAttempt(actor, clientRequestId, fingerprint, revision);
      final response = _map(
        await client.rpc(
          'create_pending_package_booking',
          params: {
            'p_client_request_id': clientRequestId,
            'p_provider_id': providerId,
            'p_property_id': propertyId,
            'p_service_type_id': serviceTypeId,
            'p_start_at': start.toUtc().toIso8601String(),
            'p_end_at': end.toUtc().toIso8601String(),
            'p_package_id': packageId,
            'p_expected_amount': expectedAmount,
            'p_expected_package_revision': revision,
            'p_instructions': instructions.trim(),
          },
        ),
      );
      check();
      final result = BookingCreationOutcome.fromResponse(response);
      if (!validPackageId(result.bookingId) ||
          result.quoteBasis != 'package' ||
          !result.quotedAmount.isFinite ||
          result.quotedAmount != expectedAmount ||
          result.quoteCurrency != 'MYR') {
        throw const FormatException('Could not verify the package booking.');
      }
      _attempts.remove(clientRequestId);
      if (_attempts.isEmpty) _clearAttempts();
      return result;
    }, writing: true);
  }

  static void _interval(DateTime start, DateTime end) {
    final duration = end.difference(start);
    if (duration <= Duration.zero ||
        duration > const Duration(hours: 8) ||
        duration.inMicroseconds % Duration.microsecondsPerMinute != 0) {
      throw ArgumentError(
        'Select a valid cleaning interval of up to eight hours.',
      );
    }
  }

  static Map<String, dynamic> _map(dynamic raw) {
    if (raw is! Map) {
      throw const FormatException('Unexpected package response.');
    }
    return Map<String, dynamic>.from(raw);
  }

  static DateTime _time(dynamic raw) {
    if (raw is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw)) {
      throw const FormatException('Unexpected package time.');
    }
    return DateTime.parse(raw).toUtc();
  }

  static String _key(
    String property,
    String service,
    String provider,
    String package,
    DateTime start,
    DateTime end,
    num amount,
  ) =>
      '$property/$service/$provider/$package/${start.toUtc().toIso8601String()}/${end.toUtc().toIso8601String()}/${amount.toStringAsFixed(2)}';
}
