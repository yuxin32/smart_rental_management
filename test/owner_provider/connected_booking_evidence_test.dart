import 'dart:convert';
import 'package:image/image.dart' as img;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_rental_management/owner_provider/screens/connected_booking_evidence_screen.dart';
import 'package:smart_rental_management/owner_provider/services/backend/connected_failure_message.dart';
import 'package:smart_rental_management/owner_provider/services/backend/safe_diagnostics.dart';
import 'package:smart_rental_management/owner_provider/services/backend/supabase_evidence_repository.dart';
import 'package:smart_rental_management/owner_provider/theme/app_theme.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAXSURBVBhXY2BgaPjffu71fwYwwdDwHwBQbAl96byCRgAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets(
      'locked Before photo allows confirmed completion without comments',
      (tester) async {
    var completions = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: ConnectedBookingEvidenceScreen(
        bookingId: 'locked-booking',
        propertyName: 'Approved rental unit',
        isProvider: true,
        status: 'In Progress',
        load: (_) async => const BookingEvidenceRecord(
          bookingId: 'locked-booking',
          beforePath: 'locked-booking/before.jpg',
          afterPath: 'locked-booking/after.jpg',
          beforeLockedAtStart: true,
          remarks: '',
        ),
        download: (_) async => _png,
        upload: (_, __, ___, ____, _____) async =>
            throw StateError('Unexpected upload'),
        removePhoto: (_, __, ___) async => fail('Locked Before photo removed'),
        complete: (id, comments) async {
          expect(id, 'locked-booking');
          expect(comments, isEmpty);
          completions++;
        },
        checkStatus: (_) async => 'In Progress',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Approved rental unit'), findsOneWidget);
    expect(find.text('Saved at job start'), findsOneWidget);
    expect(find.text('Replace before photo'), findsNothing);
    expect(find.text('Remove before photo'), findsNothing);
    final scrollable = find
        .descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('Replace after photo'), 150,
        scrollable: scrollable);
    expect(find.text('Replace after photo'), findsOneWidget);
    final complete = find.widgetWithText(FilledButton, 'Mark as Completed');
    await tester.scrollUntilVisible(complete, 150, scrollable: scrollable);
    expect(tester.widget<FilledButton>(complete).onPressed, isNull);
    final confirmation = find.text('I completed the agreed cleaning tasks');
    await tester.ensureVisible(confirmation);
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
    await tester.ensureVisible(complete);
    expect(tester.widget<FilledButton>(complete).onPressed, isNotNull);
    await tester.tap(complete);
    await tester.pumpAndSettle();
    expect(completions, 1);
  });

  for (final rejection in {
    'booking_start_not_reached':
        'The scheduled start time has not been reached. Start cleaning at the agreed date and time (MYT).',
    'before_photo_required': 'Save a Before photo before starting cleaning.',
  }.entries) {
    testWidgets('start rejection ${rejection.key} keeps the saved Before photo',
        (tester) async {
      var starts = 0, checks = 0;
      final error = PostgrestException(
          message: 'Private server message',
          code: 'PT409',
          details: rejection.key);
      expect(SafeDiagnostics.category(error), SafeFailureCategory.conflict);
      expect(ConnectedFailureMessage.forWrite(error, item: 'booking'),
          rejection.value);
      await tester.pumpWidget(MaterialApp(
        home: ConnectedBookingEvidenceScreen(
          bookingId: 'rejected-start',
          isProvider: true,
          status: 'Accepted',
          load: (_) async => const BookingEvidenceRecord(
            bookingId: 'rejected-start',
            beforePath: 'rejected-start/before.jpg',
            remarks: '',
          ),
          download: (_) async => _png,
          upload: (_, __, ___, ____, _____) async =>
              throw StateError('Saved Before photo uploaded again'),
          start: (_) async {
            starts++;
            throw error;
          },
          complete: (_, __) async => fail('Completed from Accepted'),
          checkStatus: (_) async {
            checks++;
            return 'Accepted';
          },
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start cleaning'));
      await tester.pumpAndSettle();
      expect(starts, 1);
      expect(checks, 1);
      expect(find.text(rejection.value), findsOneWidget);
      expect(find.text('Private server message'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Start cleaning'),
        150,
        scrollable: find.descendant(
          of: find.byType(ListView), matching: find.byType(Scrollable)).first,
      );
      expect(find.text('Start cleaning'), findsOneWidget);
      expect(find.text('After cleaning'), findsNothing);
    });
  }

  testWidgets('Before preview waits for upload and retries the same photo',
      (tester) async {
    final tokens = <String>[];
    var starts = 0;
    String? before;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => ConnectedBookingEvidenceScreen(
                  bookingId: 'accepted-booking',
                  isProvider: true,
                  status: 'Accepted',
                  load: (_) async => BookingEvidenceRecord(
                    bookingId: 'accepted-booking',
                    beforePath: before,
                    remarks: '',
                  ),
                  download: (_) async => _png,
                  pickPhoto: () async => _png,
                  upload: (id, kind, bytes, token, previous) async {
                    expect(kind, EvidenceKind.before);
                    tokens.add(token);
                    if (tokens.length == 1) throw StateError('offline');
                    before = '$id/before_$token.jpg';
                    return before!;
                  },
                  start: (_) async {
                    expect(before, isNotNull);
                    starts++;
                    throw StateError('response lost');
                  },
                  complete: (_, __) async => fail('Completed from Accepted'),
                  checkStatus: (_) async => 'In Progress',
                ),
              ),
            ),
            child: const Text('Open Before'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open Before'));
    await tester.pumpAndSettle();
    final start = find.widgetWithText(FilledButton, 'Upload & start job');
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    expect(find.text('After cleaning'), findsNothing);
    await tester.tap(find.text('Take before photo'));
    await tester.pumpAndSettle();
    expect(tokens, isEmpty);
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(tokens, hasLength(1));
    expect(starts, 0);
    final photoList = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Retake photo'),
      150,
      scrollable: photoList,
    );
    expect(find.text('Retake photo'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Retry upload'),
      150,
      scrollable: photoList,
    );
    await tester.tap(find.text('Retry upload'));
    await tester.pumpAndSettle();
    expect(tokens, [tokens.first, tokens.first]);
    expect(starts, 1);
    expect(find.text('Open Before'), findsOneWidget);
  });

  testWidgets(
      'invalid selected image is rejected before upload or write verification',
      (tester) async {
    var uploads = 0, reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectedBookingEvidenceScreen(
          bookingId: 'invalid-image',
          isProvider: true,
          status: 'In Progress',
          load: (_) async {
            reads++;
            return null;
          },
          download: (_) async => _png,
          upload: (_, __, ___, ____, _____) async {
            uploads++;
            return 'unused';
          },
          complete: (_, __) async {},
          checkStatus: (_) async => 'In Progress',
          pickPhoto: () async => base64Decode('/9j/'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add before photo'));
    await tester.pumpAndSettle();
    expect(uploads, 0);
    expect(reads, 1);
    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(find.text('Retry photo upload'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('provider must add both photos and confirm before completion',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? before;
    String? after;
    String remarks = '';
    var completed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectedBookingEvidenceScreen(
          bookingId: 'booking-1',
          isProvider: true,
          status: 'In Progress',
          load: (_) async => BookingEvidenceRecord(
            bookingId: 'booking-1',
            beforePath: before,
            afterPath: after,
            remarks: remarks,
          ),
          download: (_) async => _png,
          upload: (_, kind, bytes, token, previous) async {
            expect(img.decodeJpg(bytes), isNotNull);
            if (kind == EvidenceKind.before) {
              before = 'booking-1/before.png';
              return before!;
            }
            after = 'booking-1/after.png';
            return after!;
          },
          complete: (_, text) async {
            remarks = text;
            completed++;
          },
          checkStatus: (_) async => 'In Progress',
          pickPhoto: () async => _png,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Mark as Completed'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final completeButton = find.ancestor(
      of: find.text('Mark as Completed'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(tester.widget<FilledButton>(completeButton).onPressed, isNull);
    expect(completed, 0);

    await tester.scrollUntilVisible(
      find.text('Add before photo'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add before photo'));
    await tester.pumpAndSettle();
    expect(before, isNotNull);
    await tester.scrollUntilVisible(
      find.text('Add after photo'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add after photo'));
    await tester.pumpAndSettle();
    expect(after, isNotNull);

    await tester.scrollUntilVisible(
      find.text('Mark as Completed'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<FilledButton>(completeButton).onPressed, isNull);
    expect(completed, 0);

    final confirmation = find.text('I completed the agreed cleaning tasks');
    await tester.ensureVisible(confirmation);
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Kitchen and bathroom cleaned.',
    );
    await tester.scrollUntilVisible(
      find.text('Mark as Completed'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Mark as Completed'));
    await tester.pumpAndSettle();
    expect(remarks, 'Kitchen and bathroom cleaned.');
    expect(completed, 1);
  });

  testWidgets('owner can view saved evidence but cannot change it',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectedBookingEvidenceScreen(
          bookingId: 'booking-2',
          isProvider: false,
          status: 'Completed',
          load: (_) async => const BookingEvidenceRecord(
            bookingId: 'booking-2',
            beforePath: 'booking-2/before.png',
            afterPath: 'booking-2/after.png',
            remarks: 'Cleaned both rooms.',
          ),
          download: (_) async => _png,
          upload: (_, __, ___, ____, _____) async =>
              throw StateError('read-only'),
          complete: (_, __) async => throw StateError('read-only'),
          checkStatus: (_) async => 'Completed',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Cleaned both rooms.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cleaned both rooms.'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('Add before photo'), findsNothing);
    expect(find.text('Add after photo'), findsNothing);
    expect(find.text('Mark as Completed'), findsNothing);
  });

  testWidgets('lost completion response checks status before retrying',
      (tester) async {
    var completions = 0;
    var checks = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ConnectedBookingEvidenceScreen(
                    bookingId: 'booking-3',
                    isProvider: true,
                    status: 'In Progress',
                    load: (_) async => const BookingEvidenceRecord(
                      bookingId: 'booking-3',
                      beforePath: 'booking-3/before.png',
                      afterPath: 'booking-3/after.png',
                      remarks: '',
                    ),
                    download: (_) async => _png,
                    upload: (_, __, ___, ____, _____) async =>
                        throw StateError('not used'),
                    complete: (_, __) async {
                      completions++;
                      throw StateError('response lost');
                    },
                    checkStatus: (_) async {
                      checks++;
                      return 'Completed';
                    },
                  ),
                ),
              ),
              child: const Text('Open evidence'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open evidence'));
    await tester.pumpAndSettle();
    final confirmation = find.text('I completed the agreed cleaning tasks');
    await tester.scrollUntilVisible(
      confirmation,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Mark as Completed'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Mark as Completed'));
    await tester.pumpAndSettle();
    expect(completions, 1);
    expect(checks, 1);
    expect(find.text('Open evidence'), findsOneWidget);
  });

  testWidgets('lost photo upload response checks saved evidence path',
      (tester) async {
    String? beforePath;
    var uploads = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectedBookingEvidenceScreen(
          bookingId: 'booking-4',
          isProvider: true,
          status: 'In Progress',
          load: (_) async => BookingEvidenceRecord(
            bookingId: 'booking-4',
            beforePath: beforePath,
            remarks: '',
          ),
          download: (_) async => _png,
          upload: (id, kind, bytes, token, previous) async {
            uploads++;
            beforePath = '$id/${kind.name}_$token.jpg';
            throw StateError('response lost');
          },
          complete: (_, __) async {},
          checkStatus: (_) async => 'In Progress',
          pickPhoto: () async => _png,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add before photo'));
    await tester.pumpAndSettle();
    expect(uploads, 1);
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('not confirmed'), findsNothing);
  });

  testWidgets('photo refresh does not erase unsaved completion remarks',
      (tester) async {
    String? beforePath;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectedBookingEvidenceScreen(
          bookingId: 'booking-5',
          isProvider: true,
          status: 'In Progress',
          load: (_) async => BookingEvidenceRecord(
            bookingId: 'booking-5',
            beforePath: beforePath,
            remarks: '',
          ),
          download: (_) async => _png,
          upload: (_, __, ___, ____, _____) async {
            beforePath = 'booking-5/before.png';
            return beforePath!;
          },
          complete: (_, __) async {},
          checkStatus: (_) async => 'In Progress',
          pickPhoto: () async => _png,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(TextField),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), 'Do not erase this draft');
    await tester.scrollUntilVisible(
      find.text('Add before photo'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add before photo'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(TextField),
      180,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Do not erase this draft',
    );
  });

  test('evidence row maps private paths and remarks', () {
    final data = BookingEvidenceRecord.fromMap({
      'booking_id': 'id',
      'before_path': 'id/before.jpg',
      'after_path': 'id/after.jpg',
      'completion_remarks': 'Done',
    });
    expect(data.beforePath, 'id/before.jpg');
    expect(data.afterPath, 'id/after.jpg');
    expect(data.remarks, 'Done');
    expect(data.beforeLockedAtStart, isFalse);
    expect(
      BookingEvidenceRecord.fromMap({
        'booking_id': 'locked',
        'before_locked_at_start': true,
      }).beforeLockedAtStart,
      isTrue,
    );
  });

  testWidgets(
      'failed upload retries retained bytes and ID without picking again',
      (tester) async {
    var picks = 0;
    var attempts = 0;
    String? before;
    final ids = <String>[];
    final payloads = <List<int>>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectedBookingEvidenceScreen(
          bookingId: 'retry-booking',
          isProvider: true,
          status: 'In Progress',
          load: (_) async => BookingEvidenceRecord(
            bookingId: 'retry-booking',
            beforePath: before,
            remarks: '',
          ),
          download: (_) async => _png,
          pickPhoto: () async {
            picks++;
            return _png;
          },
          upload: (id, kind, bytes, token, previous) async {
            expect(img.decodeJpg(bytes), isNotNull);
            ids.add(token);
            payloads.add(bytes);
            attempts++;
            if (attempts == 1) throw StateError('offline');
            before = '$id/${kind.name}_$token.jpg';
            return before!;
          },
          complete: (_, __) async {},
          checkStatus: (_) async => 'In Progress',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add before photo'));
    await tester.pumpAndSettle();
    expect(find.text('Retry before photo'), findsOneWidget);
    await tester.tap(find.text('Retry photo upload'));
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(ids, [ids.first, ids.first]);
    expect(identical(payloads[0], payloads[1]), isTrue);
    expect(find.text('Before photo saved'), findsOneWidget);
  });

  testWidgets(
      'cleanup failure does not turn a confirmed photo into upload failure',
      (tester) async {
    String? before;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectedBookingEvidenceScreen(
          bookingId: 'cleanup-booking',
          isProvider: true,
          status: 'In Progress',
          load: (_) async => BookingEvidenceRecord(
            bookingId: 'cleanup-booking',
            beforePath: before,
            remarks: '',
          ),
          download: (_) async => _png,
          pickPhoto: () async => _png,
          upload: (id, kind, bytes, token, previous) async {
            before = '$id/${kind.name}_$token.jpg';
            return before!;
          },
          cleanup: (_) async => throw StateError('cleanup unavailable'),
          complete: (_, __) async {},
          checkStatus: (_) async => 'In Progress',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add before photo'));
    await tester.pumpAndSettle();
    expect(find.text('Before photo saved'), findsOneWidget);
    expect(
      find.textContaining('Unused-file cleanup is pending'),
      findsOneWidget,
    );
    expect(find.text('Retry before photo'), findsNothing);
  });

  testWidgets('another devices photo is not mistaken for our uncertain upload',
      (tester) async {
    String? before;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ConnectedBookingEvidenceScreen(
          bookingId: 'competing-booking',
          isProvider: true,
          status: 'In Progress',
          load: (_) async => BookingEvidenceRecord(
            bookingId: 'competing-booking',
            beforePath: before,
            remarks: '',
          ),
          download: (_) async => _png,
          pickPhoto: () async => _png,
          upload: (_, __, ___, ____, _____) async {
            before = 'competing-booking/another-device.png';
            throw StateError('response lost');
          },
          complete: (_, __) async {},
          checkStatus: (_) async => 'In Progress',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add before photo'));
    await tester.pumpAndSettle();
    expect(find.text('Before photo saved'), findsNothing);
    expect(find.text('Retry photo upload'), findsOneWidget);
    expect(find.text('Selected photo · not confirmed saved'), findsOneWidget);
  });
}
