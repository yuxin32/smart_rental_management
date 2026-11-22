import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/app_logout_button.dart';
import '../../../../core/auth/app_auth_service.dart';
import '../../../../core/config/feature_flags.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../admin/data/tenant_lifecycle_service.dart';
import '../../../tenant/presentation/pages/tenant_module_shell.dart';

class TenantVerificationPage extends StatefulWidget {
  const TenantVerificationPage({super.key});

  @override
  State<TenantVerificationPage> createState() => _TenantVerificationPageState();
}

class _TenantVerificationPageState extends State<TenantVerificationPage> {
  static const _allowedFileExtensions = <String>[
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  ];

  TenantRegistrationRecord? _record;
  String? _identityPath;
  String? _proofPath;
  bool _loading = true;
  bool _uploading = false;
  bool _submitting = false;
  String? _error;

  bool get _canEditDocuments =>
      _record != null && _record!.verificationStatus != 'verified';

  bool get _documentsReady => _identityPath != null && _proofPath != null;

  String _fileExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot < 0 || lastDot == fileName.length - 1) return '';
    return fileName.substring(lastDot + 1).toLowerCase();
  }

  String _mimeTypeFor(String extension) {
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await AppAuthService.loadCurrentProfile();
      if (profile?.isActive == true) {
        if (mounted) _openTenantModule();
        return;
      }

      final record =
          await TenantLifecycleService.fetchCurrentTenantRegistration();
      if (!mounted) return;
      setState(() {
        _record = record;
        _identityPath = record?.identityDocumentPath;
        _proofPath = record?.employmentOrStudyProofPath;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Verification information is temporarily unavailable.';
      });
    }
  }

  Future<void> _pickDocument({required bool identity}) async {
    if (!_canEditDocuments || _uploading) return;

    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _allowedFileExtensions,
    );
    if (file == null) return;

    final extension = _fileExtension(file.name);
    if (!_allowedFileExtensions.contains(extension)) {
      _showMessage('Choose a PDF or supported image file only.');
      return;
    }

    final fileSize = file.lengthSync() ?? await file.length() ?? 0;
    if (fileSize == 0 || fileSize > 10 * 1024 * 1024) {
      _showMessage('Choose a file smaller than 10 MB.');
      return;
    }

    final bytes = await file.readAsBytes();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _showMessage('Your tenant session has expired. Please sign in again.');
      return;
    }

    final fileName = identity
        ? 'identity_document.$extension'
        : 'employment_or_study_proof.$extension';
    final storagePath = '$userId/$fileName';

    setState(() => _uploading = true);
    try {
      await Supabase.instance.client.storage
          .from('tenant-verification-documents')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: _mimeTypeFor(extension),
              upsert: true,
            ),
          );

      if (!mounted) return;
      setState(() {
        if (identity) {
          _identityPath = storagePath;
        } else {
          _proofPath = storagePath;
        }
      });
      _showMessage(
        '${identity ? 'Identity document' : 'Employment / study proof'} uploaded.',
      );
    } catch (error) {
      if (mounted) _showMessage('Unable to upload the file: $error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submitDocuments() async {
    if (!_documentsReady || _submitting) return;

    setState(() => _submitting = true);
    try {
      await TenantLifecycleService.submitTenantVerificationDocuments(
        identityDocumentPath: _identityPath!,
        employmentOrStudyProofPath: _proofPath!,
      );
      await _loadRecord();
      if (mounted) {
        _showMessage(
          'Documents submitted. The administrator will review them.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage('Unable to submit the documents: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openTenantModule() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const TenantModuleShell()),
      (route) => false,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    final isRejected = record?.verificationStatus == 'rejected';
    final isVerified = record?.verificationStatus == 'verified';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: const Text('Tenant verification'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (AppFeatureFlags.bypassTenantDocumentVerificationForTesting)
            TextButton(
              onPressed: _openTenantModule,
              child: const Text(
                'Skip',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          const AppLogoutButton(
            foregroundColor: AppColors.primary,
            backgroundColor: Color(0xFFE6EBFF),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRecord,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                children: [
                  const Text(
                    'Complete your account verification',
                    style: TextStyle(
                      color: AppColors.heading,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    record == null
                        ? (_error ?? 'Your verification record is unavailable.')
                        : 'Hello ${record.fullName}. Upload the two documents requested by your apartment administrator.',
                    style: const TextStyle(
                      color: AppColors.body,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  if (record != null) ...[
                    const SizedBox(height: 18),
                    _PersonalDetailsCard(record: record),
                  ],
                  const SizedBox(height: 18),
                  if (isRejected)
                    _NoticeCard(
                      icon: Icons.warning_amber_rounded,
                      color: const Color(0xFFFFF3E5),
                      iconColor: const Color(0xFFD77B16),
                      title: 'Additional information is required',
                      message:
                          record?.verificationNotes ??
                          'Please replace the document requested by the administrator and submit again.',
                    ),
                  if (isVerified)
                    _NoticeCard(
                      icon: Icons.verified_outlined,
                      color: const Color(0xFFE9F8F1),
                      iconColor: AppColors.success,
                      title: 'Documents verified',
                      message: record?.hasAssignment == true
                          ? 'Your tenant access is being prepared.'
                          : 'The administrator will assign your rental unit before access is activated.',
                    ),
                  if (record != null &&
                      record.documentsSubmittedAt == null &&
                      !isRejected &&
                      !isVerified)
                    const _NoticeCard(
                      icon: Icons.upload_file_outlined,
                      color: Color(0xFFF0F5FF),
                      iconColor: AppColors.primary,
                      title: 'Documents required',
                      message:
                          'Upload both documents and submit them before the administrator can begin the review.',
                    ),
                  if (record?.verificationStatus == 'pending' &&
                      record?.documentsSubmittedAt != null)
                    const _NoticeCard(
                      icon: Icons.hourglass_empty_rounded,
                      color: Color(0xFFF0F5FF),
                      iconColor: AppColors.primary,
                      title: 'Verification under review',
                      message:
                          'Your documents have been submitted. You can replace a document until the administrator completes the review.',
                    ),
                  const SizedBox(height: 16),
                  _DocumentUploadCard(
                    title: 'Identity document',
                    description:
                        'Upload a clear PDF or image of your identity document.',
                    uploaded: _identityPath != null,
                    enabled: _canEditDocuments && !_uploading,
                    onPressed: () => _pickDocument(identity: true),
                  ),
                  const SizedBox(height: 12),
                  _DocumentUploadCard(
                    title: 'Employment or study proof',
                    description:
                        'Upload a current PDF or image proving your employment or study status.',
                    uploaded: _proofPath != null,
                    enabled: _canEditDocuments && !_uploading,
                    onPressed: () => _pickDocument(identity: false),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          !_documentsReady ||
                              _uploading ||
                              _submitting ||
                              !_canEditDocuments
                          ? null
                          : _submitDocuments,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(
                        _submitting
                            ? 'Submitting...'
                            : 'Submit documents for review',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFD9DEEA),
                        disabledForegroundColor: const Color(0xFF7A8495),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Supported files: PDF, JPG/JPEG, PNG, WEBP, HEIC, or HEIF. Maximum 10 MB per document; video and audio files are not allowed. Files are stored privately and are visible only to you and authorised apartment administrators.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.body,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _loadRecord,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh verification status'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DocumentUploadCard extends StatelessWidget {
  const _DocumentUploadCard({
    required this.title,
    required this.description,
    required this.uploaded,
    required this.enabled,
    required this.onPressed,
  });

  final String title;
  final String description;
  final bool uploaded;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: uploaded ? const Color(0xFFB8E5CF) : const Color(0xFFE3E7EE),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: uploaded
                  ? const Color(0xFFE9F8F1)
                  : const Color(0xFFF0F5FF),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              uploaded
                  ? Icons.check_circle_outline
                  : Icons.description_outlined,
              color: uploaded ? AppColors.success : AppColors.primary,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  uploaded ? 'File selected' : description,
                  style: const TextStyle(
                    color: AppColors.body,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: enabled ? onPressed : null,
            child: Text(uploaded ? 'Replace' : 'Choose file'),
          ),
        ],
      ),
    );
  }
}

class _PersonalDetailsCard extends StatelessWidget {
  const _PersonalDetailsCard({required this.record});

  final TenantRegistrationRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE3E7EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Personal details',
            style: TextStyle(
              color: AppColors.heading,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _DetailRow(label: 'Full name', value: record.fullName),
          _DetailRow(label: 'IC number', value: record.icNumber),
          _DetailRow(label: 'Email', value: record.email),
          _DetailRow(label: 'Phone', value: record.contact_number ?? 'Not provided'),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.body,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.heading,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.body,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
