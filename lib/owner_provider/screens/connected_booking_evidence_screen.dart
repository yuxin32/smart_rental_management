import '../presentation/workspace_text.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/backend/safe_diagnostics.dart';
import '../services/backend/booking_rate_limit.dart';
import '../services/backend/connected_failure_message.dart';
import '../widgets/rate_limit_notice.dart';
import 'package:image_picker/image_picker.dart';

import '../services/backend/supabase_evidence_repository.dart';
import '../services/backend/evidence_photo_preparation.dart';
import '../widgets/connected_state_panel.dart';
import '../widgets/connected_action_feedback.dart';
import '../widgets/evidence_photo_preview.dart';

typedef PickEvidencePhoto = Future<Uint8List?> Function();

/// Booking-scoped evidence from the private Supabase bucket. The database
/// transition remains authoritative; this screen never sets status directly.
class ConnectedBookingEvidenceScreen extends StatefulWidget {
  const ConnectedBookingEvidenceScreen({
    super.key,
    required this.bookingId,
    required this.isProvider,
    required this.status,
    required this.load,
    required this.download,
    required this.upload,
    required this.complete,
    required this.checkStatus,
    this.start,
    this.propertyName,
    this.pickPhoto,
    this.cleanup,
    this.removePhoto,
  });

  final String bookingId;
  final bool isProvider;
  final String status;
  final String? propertyName;
  final Future<BookingEvidenceRecord?> Function(String) load;
  final Future<Uint8List> Function(String) download;
  final Future<String> Function(
    String,
    EvidenceKind,
    Uint8List,
    String,
    String?,
  ) upload;
  final Future<bool> Function(String)? cleanup;
  final Future<void> Function(String, EvidenceKind, String)? removePhoto;
  final Future<void> Function(String)? start;
  final Future<void> Function(String, String) complete;
  final Future<String?> Function(String) checkStatus;
  final PickEvidencePhoto? pickPhoto;

  @override
  State<ConnectedBookingEvidenceScreen> createState() =>
      _ConnectedBookingEvidenceScreenState();
}

class _ConnectedBookingEvidenceScreenState
    extends State<ConnectedBookingEvidenceScreen> {
  final _remarks = TextEditingController();
  final _ratePause = ActionRatePause();
  BookingEvidenceRecord? _record;
  Uint8List? _beforeBytes;
  Uint8List? _afterBytes;
  bool _loading = true;
  bool _busy = false;
  bool _completed = false;
  bool _remarksEdited = false;
  bool _loadFailed = false;
  String? _error;
  ConnectedActionNotice? _notice;
  String _workingTitle = 'Saving service record';
  EvidencePhotoUpload? _pendingPhoto;
  String? _pendingPhotoDescription;
  bool _cleanupPending = false;
  bool _removalUncertain = false;
  bool _editingClosed = false;
  bool _confirmed = false;

  bool get _starting =>
      widget.isProvider && widget.status == 'Accepted' && widget.start != null;

  bool get _canEdit =>
      widget.isProvider &&
      (_starting || widget.status == 'In Progress') &&
      !_completed &&
      !_editingClosed;

  bool _canChangePhoto(EvidenceKind kind) =>
      _canEdit &&
      (!_starting || kind == EvidenceKind.before) &&
      (kind != EvidenceKind.before || _record?.beforeLockedAtStart != true);

  bool get _canComplete =>
      _confirmed &&
      _record?.beforePath != null &&
      _record?.afterPath != null &&
      _pendingPhoto == null;

  @override
  void initState() {
    super.initState();
    _ratePause.addListener(_onRatePause);
    _refresh();
  }

  @override
  void dispose() {
    _ratePause.removeListener(_onRatePause);
    _ratePause.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final draft = _remarks.text;
    final keepDraft = _remarksEdited;
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
      _notice = null;
    });
    try {
      final record = await widget.load(widget.bookingId);
      final before = record?.beforePath == null
          ? null
          : await widget.download(record!.beforePath!);
      final after = record?.afterPath == null
          ? null
          : await widget.download(record!.afterPath!);
      var cleanupPending = false;
      if (widget.isProvider && widget.cleanup != null) {
        try {
          cleanupPending = !await widget.cleanup!(widget.bookingId)
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          cleanupPending = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _record = record;
        _cleanupPending = cleanupPending;
        _beforeBytes = before;
        _afterBytes = after;
        _remarks.text = keepDraft ? draft : record?.remarks ?? '';
        _loading = false;
        _loadFailed = false;
        _removalUncertain = false;
      });
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.evidenceLoad, error);
      if (mounted) {
        setState(() {
          _error =
              'Could not load private booking evidence. Check your connection and try again.';
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<Uint8List?> _pick() async {
    if (widget.pickPhoto != null) return widget.pickPhoto!();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    final image = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 95,
    );
    if (image != null &&
        await image.length() > EvidencePhotoPolicy.maxInputBytes) {
      throw const PhotoPreparationException(
        'Choose a JPEG or PNG image up to 20 MB.',
      );
    }
    return image?.readAsBytes();
  }

  Future<void> _upload(EvidenceKind kind, {bool selectOnly = false}) async {
    if (_busy ||
        !_canChangePhoto(kind) ||
        _removalUncertain ||
        _ratePause.active) return;
    final photoLabel = kind == EvidenceKind.before ? 'Before' : 'After';
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _workingTitle = 'Choose a ${photoLabel.toLowerCase()} photo';
    });
    try {
      if (_pendingPhoto == null || selectOnly) {
        final bytes = await _pick();
        if (bytes == null || !mounted) return;
        setState(() => _workingTitle = 'Preparing photo for upload');
        final prepared = await prepareEvidencePhoto(bytes);
        if (!mounted) return;
        final photo = EvidencePhotoUpload(
          kind: kind,
          bytes: prepared.bytes,
          expectedPreviousPath: kind == EvidenceKind.before
              ? _record?.beforePath
              : _record?.afterPath,
        );
        photo.extension; // Validate before retaining this selection.
        _pendingPhoto = photo;
        _pendingPhotoDescription = prepared.description;
      }
      if (selectOnly) return;
      final photo = _pendingPhoto!;
      if (photo.kind != kind) return;
      setState(() {
        _workingTitle =
            'Uploading and validating ${photoLabel.toLowerCase()} photo';
      });
      await widget.upload(
        widget.bookingId,
        kind,
        photo.bytes,
        photo.id,
        photo.expectedPreviousPath,
      );
      if (!mounted) return;
      _pendingPhoto = null;
      if (_starting) {
        await _startWithSavedBefore();
        return;
      }
      await _refresh();
      if (mounted && !_loadFailed) {
        setState(
          () => _notice = ConnectedActionNotice(
            ConnectedActionState.success,
            '$photoLabel photo saved',
            'The photo is saved to this booking. Add the remaining evidence before completing the job.',
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      if (error is PhotoPreparationException) {
        setState(() {
          _pendingPhoto = null;
          _pendingPhotoDescription = null;
          _error = error.message;
        });
        return;
      }
      SafeDiagnostics.app.record(SafeOperation.evidenceUpload, error);
      if (error is ServerActionLimit &&
          error.action == BookingLimitedAction.evidence) {
        _ratePause.start(error);
        return; // Keep the same photo bytes/token for the later manual retry.
      }
      if (error is ArgumentError) {
        setState(() {
          _pendingPhoto = null;
          _error = 'Choose a JPEG or PNG image up to 5 MB.';
        });
        return;
      }
      if (error is EvidenceUploadRejected &&
          error.reason != 'upload_not_confirmed') {
        setState(() {
          _pendingPhoto = null;
          _error = error.reason == 'photo_rejected'
              ? 'The server could not validate this photo. Choose another JPEG or PNG photo and try again.'
              : 'This photo could not be applied. The booking or photo changed, or the upload expired. Reload the service record before selecting it again.';
        });
        return;
      }
      try {
        setState(() => _workingTitle = 'Checking saved photo');
        final latest = await widget.load(widget.bookingId);
        if (!mounted) return;
        final latestPath = kind == EvidenceKind.before
            ? latest?.beforePath
            : latest?.afterPath;
        if (_pendingPhoto != null &&
            latestPath == _pendingPhoto!.pathFor(widget.bookingId)) {
          _pendingPhoto = null;
          if (_starting) {
            await _startWithSavedBefore();
            return;
          }
          await _refresh();
          if (mounted && !_loadFailed) {
            setState(
              () => _notice = ConnectedActionNotice(
                ConnectedActionState.success,
                '$photoLabel photo saved',
                'The saved photo was verified in this booking.',
              ),
            );
          }
          return;
        }
        setState(
          () => _error =
              'The photo has not been confirmed saved. Your selection is kept; retry the photo upload without selecting it again.',
        );
      } catch (lookupError) {
        SafeDiagnostics.app.record(SafeOperation.evidenceVerify, lookupError);
        if (mounted) {
          setState(
            () => _error =
                'Could not check whether the photo was saved. Reload this service record before uploading again.',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startWithSavedBefore() async {
    setState(() {
      _busy = true;
      _error = null;
      _workingTitle = 'Starting cleaning';
    });
    try {
      await widget.start!(widget.bookingId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.bookingUpdate, error);
      if (!mounted) return;
      try {
        final status = await widget.checkStatus(widget.bookingId);
        if (!mounted) return;
        if (status == 'In Progress') {
          Navigator.of(context).pop(true);
          return;
        }
        await _refresh();
        if (mounted) {
          setState(() {
            _editingClosed = status != 'Accepted';
            if (!_loadFailed) {
              _error = _editingClosed
                  ? 'Return to booking details to check its current status.'
                  : ConnectedFailureMessage.forWrite(error, item: 'booking');
            }
          });
        }
      } catch (lookupError) {
        SafeDiagnostics.app.record(SafeOperation.bookingVerify, lookupError);
        if (mounted) {
          setState(() => _error =
              'Could not confirm the booking status. Check your connection and reload evidence.');
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(EvidenceKind kind) async {
    if (_busy ||
        !_canChangePhoto(kind) ||
        _removalUncertain ||
        _pendingPhoto != null ||
        widget.removePhoto == null) return;
    final path =
        kind == EvidenceKind.before ? _record?.beforePath : _record?.afterPath;
    if (path == null) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: Text('Remove ${kind.name} photo?'),
              content: const Text(
                  'This photo will be removed from the booking. You will need to add a replacement before marking the job as completed.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Keep photo')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Remove photo')),
              ],
            ));
    if (!mounted || confirmed != true || _busy || !_canChangePhoto(kind))
      return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _workingTitle = 'Removing ${kind.name} photo';
    });
    try {
      await widget.removePhoto!(widget.bookingId, kind, path);
      if (!mounted) return;
      await _refresh();
      if (mounted && !_loadFailed)
        setState(() => _notice = ConnectedActionNotice(
            ConnectedActionState.success,
            'Photo removed',
            'Add a replacement photo before completing the job.'));
    } on EvidencePhotoRemovalRejected catch (error) {
      if (!mounted) return;
      if (error.reason == 'booking_closed') _editingClosed = true;
      await _refresh();
      if (mounted)
        setState(() => _error = error.reason == 'photo_changed'
            ? 'The photo changed on another device. The current record has been reloaded; check it before removing a photo.'
            : 'This booking is no longer editable. Return to booking details to check its current status.');
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.evidenceRemove, error);
      if (!mounted) return;
      _removalUncertain = true;
      try {
        final latest = await widget.load(widget.bookingId);
        if (!mounted) return;
        final current = kind == EvidenceKind.before
            ? latest?.beforePath
            : latest?.afterPath;
        if (latest != null &&
            latest.bookingId == widget.bookingId &&
            current != path) {
          await _refresh();
          if (mounted && !_loadFailed)
            setState(() {
              _notice = ConnectedActionNotice(
                  ConnectedActionState.success,
                  current == null ? 'Photo removed' : 'Photo updated',
                  current == null
                      ? 'The saved record confirms this photo was removed.'
                      : 'A different photo is now attached. The current photo has been kept.');
            });
          return;
        }
      } catch (lookupError) {
        SafeDiagnostics.app
            .record(SafeOperation.evidenceRemoveVerify, lookupError);
      }
      if (mounted)
        setState(() => _error =
            'Could not confirm whether the photo was removed. Reload this record before changing photos or completing the job.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() async {
    if (_busy || !_canEdit || _starting || _removalUncertain || !_canComplete)
      return;
    final text = _remarks.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _workingTitle = 'Confirming job completion';
    });
    try {
      await widget.complete(widget.bookingId, text);
      if (!mounted) return;
      setState(() => _completed = true);
      Navigator.of(context).pop(true);
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.completion, error);
      if (!mounted) return;
      setState(() => _workingTitle = 'Checking completion status');
      try {
        final status = await widget.checkStatus(widget.bookingId);
        if (!mounted) return;
        if (status == 'Completed') {
          setState(() => _completed = true);
          Navigator.of(context).pop(true);
          return;
        }
        setState(
          () => _error =
              'Completion was not confirmed. Your photos and remarks remain on this screen; check your connection and try again.',
        );
      } catch (lookupError) {
        SafeDiagnostics.app.record(SafeOperation.completionVerify, lookupError);
        if (mounted) {
          setState(
            () => _error =
                'Could not check whether the booking was completed. Review its status before trying again; your remarks remain here.',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onRatePause() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_starting
            ? 'Before cleaning'
            : _canEdit
                ? 'Complete cleaning'
                : 'Completion evidence'),
      ),
      body: ConnectedActionFeedbackFrame(
        notice: _busy
            ? ConnectedActionNotice(
                ConnectedActionState.working,
                _workingTitle,
                _starting
                    ? 'Saving the Before photo to this booking.'
                    : 'Your comments are kept on this screen.',
              )
            : _error != null && !_loadFailed
                ? ConnectedActionNotice(
                    ConnectedActionState.error,
                    'Check service record',
                    _error!,
                  )
                : _notice,
        onDismiss: _busy || _error != null
            ? null
            : () => setState(() => _notice = null),
        actionLabel: !_busy &&
                _error != null &&
                !_loadFailed &&
                !(_starting && _pendingPhoto != null)
            ? _pendingPhoto != null
                ? 'Retry photo upload'
                : 'Reload evidence'
            : null,
        onAction: !_busy &&
                _error != null &&
                !_loadFailed &&
                !(_starting && _pendingPhoto != null)
            ? _pendingPhoto != null
                ? () => _upload(_pendingPhoto!.kind)
                : _refresh
            : null,
        child: _loading
            ? const ConnectedStatePanel(
                state: ConnectedViewState.loading,
                title: 'Loading service record',
                message: 'Retrieving photos and remarks for this booking.',
              )
            : _loadFailed
                ? ConnectedStatePanel(
                    state: ConnectedViewState.error,
                    title: 'Could not load service record',
                    message:
                        'Check your connection and reload to view the saved record.',
                    actionLabel: 'Retry',
                    onAction: _refresh,
                  )
                : !widget.isProvider && _record == null
                    ? ConnectedStatePanel(
                        state: ConnectedViewState.empty,
                        title: 'No completion evidence yet',
                        message:
                            'Photos and remarks will appear when the provider submits them.',
                        actionLabel: 'Check again',
                        onAction: _refresh,
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                        children: [
                          if (_canEdit && widget.propertyName != null) ...[
                            Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                title: Text(widget.propertyName!),
                                subtitle: Text(widget.status),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _starting
                                      ? 'Before photo required'
                                      : _canEdit
                                          ? 'Document your work'
                                          : 'Service record',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _starting
                                      ? 'Photograph the area before cleaning.'
                                      : _canEdit
                                          ? 'Add the required photos and confirm the work you completed.'
                                          : 'Photos and remarks are stored privately for this booking.',
                                  style: TextStyle(
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (_cleanupPending) ...[
                            const Text(
                              'Unused-file cleanup is pending. Saved photos are kept; cleanup will retry when you reload this record.',
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (!_starting &&
                              _canEdit &&
                              _record?.beforeLockedAtStart == true &&
                              _beforeBytes != null)
                            _savedBeforeCard(_beforeBytes!, scheme)
                          else
                            _photoCard(
                              'Before cleaning',
                              EvidenceKind.before,
                              _beforeBytes,
                            ),
                          if (_starting && _canEdit) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _busy ||
                                      _ratePause.active ||
                                      !_canChangePhoto(EvidenceKind.before)
                                  ? null
                                  : () => _upload(EvidenceKind.before,
                                      selectOnly: true),
                              icon: const Icon(Icons.add_a_photo_outlined),
                              label: Text(
                                  _pendingPhoto != null || _beforeBytes != null
                                      ? 'Retake photo'
                                      : 'Take before photo'),
                            ),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: _busy ||
                                      _ratePause.active ||
                                      (_pendingPhoto == null &&
                                          _record?.beforePath == null)
                                  ? null
                                  : _pendingPhoto != null
                                      ? () => _upload(EvidenceKind.before)
                                      : () {
                                          if (!_busy) _startWithSavedBefore();
                                        },
                              child: Text(
                                  _pendingPhoto != null && _error != null
                                      ? 'Retry upload'
                                      : _pendingPhoto == null &&
                                              _record?.beforePath != null
                                          ? 'Start cleaning'
                                          : 'Upload & start job'),
                            ),
                          ],
                          if (!_starting) ...[
                            const SizedBox(height: 12),
                            _photoCard(
                              'After cleaning',
                              EvidenceKind.after,
                              _afterBytes,
                            ),
                            const SizedBox(height: 18),
                            if (_canEdit)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: const Text(
                                    'I completed the agreed cleaning tasks'),
                                value: _confirmed,
                                onChanged: _busy
                                    ? null
                                    : (checked) => setState(
                                        () => _confirmed = checked ?? false),
                              ),
                            Text(
                              _canEdit
                                  ? 'Additional comments (optional)'
                                  : 'Completion remarks',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            if (_canEdit)
                              TextField(
                                controller: _remarks,
                                enabled: !_busy,
                                onChanged: (_) => _remarksEdited = true,
                                maxLines: 2,
                                maxLength: 1000,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'e.g. Left the key in the lockbox.',
                                ),
                              )
                            else
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    workspaceText(_record?.remarks ?? '')
                                            .isNotEmpty
                                        ? workspaceText(_record!.remarks)
                                        : 'No remarks submitted.',
                                  ),
                                ),
                              ),
                            if (_canEdit) ...[
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _busy ||
                                        _removalUncertain ||
                                        _ratePause.active ||
                                        !_canComplete
                                    ? null
                                    : _complete,
                                icon: _busy
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.task_alt),
                                label: const Text('Mark as Completed'),
                              ),
                              if (_ratePause.active) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  'Retry the photo upload after the pause to finish.',
                                  textAlign: TextAlign.center,
                                ),
                              ]
                            ],
                          ],
                        ],
                      ),
      ),
    );
  }

  Widget _savedBeforeCard(Uint8List bytes, ColorScheme scheme) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: SizedBox.square(
            dimension: 48,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: EvidencePhotoPreview(
                bytes: bytes,
                cacheWidth: 192,
                errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined),
              ),
            ),
          ),
          title: const Text('Before cleaning'),
          subtitle: const Text('Saved at job start'),
          trailing: Icon(Icons.check_circle, color: scheme.primary),
        ),
      );

  Widget _photoCard(String title, EvidenceKind kind, Uint8List? bytes) {
    final scheme = Theme.of(context).colorScheme;
    final pending = _pendingPhoto?.kind == kind ? _pendingPhoto : null;
    final displayBytes = pending?.bytes ?? bytes;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  kind == EvidenceKind.before
                      ? Icons.photo_camera_back_outlined
                      : Icons.verified_outlined,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (bytes != null && pending == null)
                  Icon(Icons.check_circle, color: scheme.primary, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            if (pending != null) ...[
              Text(
                _ratePause.active
                    ? 'Selected photo · waiting to upload'
                    : 'Selected photo · not confirmed saved',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 8),
              if (_pendingPhotoDescription != null) ...[
                Text(
                  'Optimised photo · $_pendingPhotoDescription',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_ratePause.limit != null) ...[
                RateLimitNotice(limit: _ratePause.limit!),
                const SizedBox(height: 12),
              ],
            ],
            if (displayBytes == null)
              Container(
                height: 120,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _canEdit ? 'No photo added yet' : 'No photo available',
                ),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: EvidencePhotoPreview(
                  bytes: displayBytes,
                  cacheWidth: (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .round()
                      .clamp(320, 1200),
                  errorBuilder: (_, __, ___) => Container(
                    height: 160,
                    padding: const EdgeInsets.all(16),
                    alignment: Alignment.center,
                    color: scheme.surfaceContainerHighest,
                    child: const Text(
                      'Photo preview unavailable. Reload the record or choose another image.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            if (!_starting && _canChangePhoto(kind)) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ||
                        _removalUncertain ||
                        _ratePause.active ||
                        (_pendingPhoto != null && _pendingPhoto!.kind != kind)
                    ? null
                    : () => _upload(kind),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(
                  _pendingPhoto?.kind == kind && !_busy
                      ? 'Retry ${kind.name} photo'
                      : bytes == null
                          ? 'Add ${kind == EvidenceKind.before ? 'before' : 'after'} photo'
                          : 'Replace ${kind == EvidenceKind.before ? 'before' : 'after'} photo',
                ),
              ),
              if (bytes != null &&
                  pending == null &&
                  widget.removePhoto != null)
                TextButton.icon(
                  onPressed: _busy || _removalUncertain || _pendingPhoto != null
                      ? null
                      : () => _removePhoto(kind),
                  icon: const Icon(Icons.delete_outline),
                  label: Text('Remove ${kind.name} photo'),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
