import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_rental_management/owner_provider/screens/connected_booking_evidence_screen.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_evidence_repository.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAXSURBVBhXY2BgaPjffu71fwYwwdDwHwBQbAl96byCRgAAAABJRU5ErkJggg==');

class _Evidence {
  String? before = 'booking/before.jpg', after = 'booking/after.jpg';
  int removes = 0, completions = 0, cleanups = 0;
  String mode = 'success';
  bool failLoad = false;
  Widget screen({bool provider = true, String status = 'In Progress'}) =>
      MaterialApp(
          theme: AppTheme.light(),
          home: ConnectedBookingEvidenceScreen(
              bookingId: 'booking',
              isProvider: provider,
              status: status,
              load: (_) async {
                if (failLoad) throw StateError('offline');
                return BookingEvidenceRecord(
                    bookingId: 'booking',
                    beforePath: before,
                    afterPath: after,
                    remarks: 'Saved remarks');
              },
              download: (_) async => _png,
              upload: (_, __, ___, ____, _____) async =>
                  throw StateError('unexpected upload'),
              removePhoto: (_, kind, expected) async {
                removes++;
                expect(
                    expected,
                    kind == EvidenceKind.before
                        ? 'booking/before.jpg'
                        : 'booking/after.jpg');
                if (mode == 'unknown') {
                  failLoad = true;
                  throw StateError('offline');
                }
                if (mode == 'conflict') {
                  before = 'booking/new.jpg';
                  throw const EvidencePhotoRemovalRejected('photo_changed');
                }
                if (mode == 'closed')
                  throw const EvidencePhotoRemovalRejected('booking_closed');
                if (kind == EvidenceKind.before) {
                  before = null;
                } else {
                  after = null;
                }
                if (mode == 'lost-response') throw StateError('response lost');
              },
              cleanup: (_) async {
                cleanups++;
                return true;
              },
              complete: (_, __) async => completions++,
              checkStatus: (_) async => status));
}

Future<void> _openRemove(WidgetTester tester, String kind) async {
  final action = find.text('Remove $kind photo');
  await _reveal(tester, action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder action) async {
  final scrollable = find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(action, 160, scrollable: scrollable);
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
}

TextButton _removeButton(WidgetTester tester) => tester.widget<TextButton>(find
    .ancestor(
        of: find.text('Remove before photo'),
        matching: find.byWidgetPredicate((w) => w is TextButton))
    .first);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  for (final kind in ['before', 'after']) {
    testWidgets(
        'remove $kind photo requires confirmation, preserves other photo/remarks and blocks incomplete completion',
        (tester) async {
      final state = _Evidence();
      _phone(tester);
      await tester.pumpWidget(state.screen());
      await tester.pumpAndSettle();
      await _openRemove(tester, kind);
      await tester.tap(find.text('Keep photo'));
      await tester.pumpAndSettle();
      expect(state.removes, 0);
      await _openRemove(tester, kind);
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      expect(state.removes, 1);
      expect(state.cleanups, 2);
      expect(kind == 'before' ? state.before : state.after, isNull);
      expect(kind == 'before' ? state.after : state.before, isNotNull);
      await _reveal(tester, find.text('Add $kind photo'));
      expect(find.text('Add $kind photo'), findsOneWidget);
      await _reveal(tester, find.text('Mark as Completed'));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Saved remarks');
      final completeButton = find.ancestor(
        of: find.text('Mark as Completed'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(tester.widget<FilledButton>(completeButton).onPressed, isNull);
      expect(state.completions, 0);
    });
  }
  testWidgets(
      'lost response reads saved pointer before showing removal success, without replaying writes',
      (tester) async {
    final state = _Evidence()..mode = 'lost-response';
    _phone(tester);
    await tester.pumpWidget(state.screen());
    await tester.pumpAndSettle();
    await _openRemove(tester, 'before');
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    expect(state.removes, 1);
    expect(find.text('Photo removed'), findsOneWidget);
    await _reveal(tester, find.text('Add before photo'));
    expect(find.text('Add before photo'), findsOneWidget);
  });
  testWidgets(
      'unconfirmed removal preserves the photo and blocks changes until explicit reload',
      (tester) async {
    final state = _Evidence()..mode = 'unknown';
    _phone(tester);
    await tester.pumpWidget(state.screen());
    await tester.pumpAndSettle();
    await _openRemove(tester, 'before');
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    expect(state.before, 'booking/before.jpg');
    expect(state.removes, 1);
    expect(
        find.text(
            'Could not confirm whether the photo was removed. Reload this record before changing photos or completing the job.'),
        findsOneWidget);
    await _reveal(tester, find.text('Remove before photo'));
    expect(_removeButton(tester).onPressed, isNull);
    state.failLoad = false;
    await tester.tap(find.text('Reload evidence'));
    await tester.pumpAndSettle();
    expect(state.removes, 1);
    await _reveal(tester, find.text('Remove before photo'));
    expect(_removeButton(tester).onPressed, isNotNull);
  });
  testWidgets('stale removal reloads a replacement without deleting it',
      (tester) async {
    final state = _Evidence()..mode = 'conflict';
    _phone(tester);
    await tester.pumpWidget(state.screen());
    await tester.pumpAndSettle();
    await _openRemove(tester, 'before');
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    expect(state.before, 'booking/new.jpg');
    expect(state.removes, 1);
    expect(find.text('Photo removed'), findsNothing);
    expect(
        find.textContaining('photo changed on another device'), findsOneWidget);
  });
  for (final role in [
    (false, 'In Progress'),
    (true, 'Completed'),
    (true, 'Accepted')
  ]) {
    testWidgets(
        'read-only evidence has no remove action provider=${role.$1} status=${role.$2}',
        (tester) async {
      final state = _Evidence();
      _phone(tester);
      await tester.pumpWidget(state.screen(provider: role.$1, status: role.$2));
      await tester.pumpAndSettle();
      expect(find.text('Remove before photo'), findsNothing);
      expect(find.text('Remove after photo'), findsNothing);
      expect(state.removes, 0);
    });
  }
  testWidgets('a booking closed elsewhere disables all editing after rejection',
      (tester) async {
    final state = _Evidence()..mode = 'closed';
    _phone(tester);
    await tester.pumpWidget(state.screen());
    await tester.pumpAndSettle();
    await _openRemove(tester, 'before');
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    expect(state.before, isNotNull);
    expect(find.text('Remove before photo'), findsNothing);
    expect(find.text('Mark as Completed'), findsNothing);
    expect(find.textContaining('no longer editable'), findsOneWidget);
  });
}
