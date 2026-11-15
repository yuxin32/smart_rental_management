import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/feature_flags.dart';
import '../../data/tenant_lifecycle_service.dart';
import '../widgets/admin_ui.dart';
import 'admin_audit_log_page.dart';

class AdminTenantsPage extends StatefulWidget {
  const AdminTenantsPage({super.key});

  @override
  State<AdminTenantsPage> createState() => _AdminTenantsPageState();
}

class _AdminTenantsPageState extends State<AdminTenantsPage> {
  final _searchController = TextEditingController();
  List<TenantRegistrationRecord> _records = const [];
  String _filter = 'All';
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final records = await TenantLifecycleService.fetchRegistrations();
      if (!mounted) return;
      setState(() => _records = records);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final records = _records.where((record) {
      final matchesFilter = switch (_filter) {
        'Invited' => record.isInvitedLifecycle,
        'Review Needed' => record.isReviewNeeded,
        'Active' => record.isActiveLifecycle,
        _ => true,
      };
      final searchable = [
        record.fullName,
        record.icNumber,
        record.email,
        record.unitNumber ?? '',
      ].join(' ').toLowerCase();
      return matchesFilter && (query.isEmpty || searchable.contains(query));
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: Column(
        children: [
          AdminScreenTitle(
            title: 'Tenants & Units',
            subtitle:
                'Complete tenant information before sending an invitation',
            action: IconButton(
              onPressed: _openAddTenant,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFE6EBFF),
                foregroundColor: AppColors.primary,
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              tooltip: 'Add tenant information',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search name, IC number, email, or unit',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 37,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final label = [
                  'All',
                  'Invited',
                  'Review Needed',
                  'Active',
                ][index];
                return ChoiceChip(
                  label: Text(label),
                  selected: _filter == label,
                  onSelected: (_) => setState(() => _filter = label),
                  selectedColor: const Color(0xFFE0E7FF),
                  labelStyle: TextStyle(
                    color: _filter == label
                        ? AppColors.primary
                        : AppColors.body,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  side: BorderSide.none,
                  backgroundColor: Colors.white,
                  showCheckmark: false,
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: _buildContent(records)),
        ],
      ),
    );
  }

  Widget _buildContent(List<TenantRegistrationRecord> records) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          AdminCard(
            color: const Color(0xFFFFF5E8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off_outlined, color: Color(0xFFE8953E)),
                const SizedBox(height: 10),
                const Text(
                  'Tenant lifecycle data is unavailable',
                  style: TextStyle(
                    color: AppColors.heading,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.body,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _loadRecords,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (records.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          AdminCard(
            child: Column(
              children: [
                const AdminIconBox(
                  icon: Icons.people_outline_rounded,
                  color: AppColors.primary,
                  backgroundColor: Color(0xFFE6EBFF),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No tenant registrations yet',
                  style: TextStyle(
                    color: AppColors.heading,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Add the tenant information, send the invitation, and assign a rental unit after the tenant completes account setup.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.body,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _openAddTenant,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add tenant information'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRecords,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        itemCount: records.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _TenantRegistrationCard(
          record: records[index],
          onTap: () => _openDetails(records[index]),
        ),
      ),
    );
  }

  void _openAddTenant() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AdminAddTenantPage()));
    if (saved == true) _loadRecords();
  }

  void _openDetails(TenantRegistrationRecord record) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminTenantDetailsPage(record: record)),
    );
    if (changed == true) _loadRecords();
  }

  static String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('tenant_registration')) {
      return 'Apply the tenant lifecycle database migration before using this page.';
    }
    return 'The application could not load tenant records. Check the connection and try again.';
  }
}

class _TenantRegistrationCard extends StatelessWidget {
  const _TenantRegistrationCard({required this.record, required this.onTap});

  final TenantRegistrationRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.all(15),
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFE0E7FF),
            child: Text(
              _initials(record.fullName),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.fullName,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${record.icNumber} · ${record.unitLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.body, fontSize: 12),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    AdminStatusPill(
                      label: record.stageLabel,
                      foregroundColor: adminStatusColor(record.stageLabel),
                      backgroundColor: adminStatusBackground(record.stageLabel),
                    ),
                    AdminStatusPill(
                      label: record.verificationStageLabel,
                      foregroundColor: adminStatusColor(
                        record.verificationStageLabel,
                      ),
                      backgroundColor: adminStatusBackground(
                        record.verificationStageLabel,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA4B3)),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length > 1) {
      return '${words.first[0]}${words.last[0]}'.toUpperCase();
    }
    return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
  }
}

class AdminAddTenantPage extends StatefulWidget {
  const AdminAddTenantPage({super.key});

  @override
  State<AdminAddTenantPage> createState() => _AdminAddTenantPageState();
}

class _AdminAddTenantPageState extends State<AdminAddTenantPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _icController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _temporaryPasswordController = TextEditingController();
  bool _saving = false;
  bool _obscureTemporaryPassword = true;
  String? _savedRegistrationId;

  @override
  void dispose() {
    _fullNameController.dispose();
    _icController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _temporaryPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveAndInvite() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final registrationId =
          _savedRegistrationId ??
          await TenantLifecycleService.createRegistration(
            fullName: _fullNameController.text.trim(),
            icNumber: _icController.text.trim(),
            email: _emailController.text.trim(),
            phone: _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
          );
      _savedRegistrationId = registrationId;

      await TenantLifecycleService.sendInvitation(
        registrationId,
        temporaryPassword: _temporaryPasswordController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tenant information saved and invitation sent to ${_emailController.text.trim()}.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      if (_savedRegistrationId != null) {
        _showMessage(
          'Tenant information was saved, but the invitation was not sent. '
          '${_friendlyInvitationError(error)}',
        );
      } else {
        _showMessage(_friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: const AdminBackAppBar(title: 'Add & Invite Tenant'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            const Text(
              'Tenant information and invitation',
              style: TextStyle(
                color: AppColors.heading,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter the tenant’s basic information and set a temporary password. Saving the record will immediately send the account invitation.',
              style: TextStyle(
                color: AppColors.body,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            AdminCard(
              child: Column(
                children: [
                  _field(
                    controller: _fullNameController,
                    label: 'Full name',
                    hint: 'As shown on the identity document',
                    icon: Icons.person_outline_rounded,
                    enabled: !_saving && _savedRegistrationId == null,
                    validator: (value) => _required(value, 'full name'),
                  ),
                  const SizedBox(height: 15),
                  _field(
                    controller: _icController,
                    label: 'IC / identity number',
                    hint: 'Enter the tenant identity number',
                    icon: Icons.badge_outlined,
                    enabled: !_saving && _savedRegistrationId == null,
                    validator: (value) => _required(value, 'IC number'),
                  ),
                  const SizedBox(height: 15),
                  _field(
                    controller: _emailController,
                    label: 'Email address',
                    hint: 'The invitation will be sent to this email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_saving && _savedRegistrationId == null,
                    validator: (value) {
                      final requiredError = _required(value, 'email address');
                      if (requiredError != null) return requiredError;
                      if (!value!.contains('@')) {
                        return 'Enter a valid email address.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),
                  _field(
                    controller: _phoneController,
                    label: 'Phone number',
                    hint: 'Optional contact number',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    enabled: !_saving && _savedRegistrationId == null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Invitation setup',
                    style: TextStyle(
                      color: AppColors.heading,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Set a temporary password for the tenant’s first sign-in. The tenant must replace it before continuing with document submission.',
                    style: TextStyle(
                      color: AppColors.body,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _temporaryPasswordController,
                    enabled: !_saving,
                    obscureText: _obscureTemporaryPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration:
                        _fieldDecoration(
                          Icons.password_rounded,
                          'Temporary password',
                        ).copyWith(
                          hintText: 'Use 8–72 characters',
                          suffixIcon: IconButton(
                            onPressed: _saving
                                ? null
                                : () => setState(
                                    () => _obscureTemporaryPassword =
                                        !_obscureTemporaryPassword,
                                  ),
                            icon: Icon(
                              _obscureTemporaryPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                    validator: (value) {
                      if (value == null || value.length < 8) {
                        return 'Use at least 8 characters.';
                      }
                      if (value.length > 72) {
                        return 'Use no more than 72 characters.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 9),
                  const Text(
                    'Share the temporary password with the tenant separately. It is not included in the invitation email or audit log.',
                    style: TextStyle(
                      color: AppColors.body,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AdminCard(
              color: const Color(0xFFF0F5FF),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.timeline_rounded, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _savedRegistrationId == null
                          ? AppFeatureFlags
                                    .bypassTenantDocumentVerificationForTesting
                                ? 'The tenant receives the invitation, replaces the temporary password, and can enter the module. Document submission may be completed later during testing.'
                                : 'The tenant receives the invitation, replaces the temporary password, and uploads the required documents. Review the documents before assigning a rental unit.'
                          : 'The tenant record has been saved. Resolve the invitation issue, then tap Retry Invitation; another tenant record will not be created.',
                      style: const TextStyle(
                        color: Color(0xFF5D75B4),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _saveAndInvite,
                icon: Icon(
                  _savedRegistrationId == null
                      ? Icons.mark_email_unread_outlined
                      : Icons.refresh_rounded,
                ),
                label: Text(
                  _saving
                      ? (_savedRegistrationId == null
                            ? 'Saving and sending...'
                            : 'Retrying invitation...')
                      : (_savedRegistrationId == null
                            ? 'Save & Send Invitation'
                            : 'Retry Invitation'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      validator: validator,
      decoration: _fieldDecoration(icon, label).copyWith(hintText: hint),
    );
  }

  static String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return 'Enter the $label.';
    return null;
  }

  static String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('duplicate') || message.contains('unique')) {
      return 'A tenant with this email or IC number already exists.';
    }
    return 'Unable to save tenant information. Check the database connection.';
  }

  static String _friendlyInvitationError(Object error) {
    final message = error.toString();
    if (message.contains('FunctionException') ||
        message.contains('not configured')) {
      return 'The invitation service is currently unavailable. Please try again.';
    }
    return message.replaceFirst('Bad state: ', '');
  }
}

class AdminTenantDetailsPage extends StatefulWidget {
  const AdminTenantDetailsPage({required this.record, super.key});

  final TenantRegistrationRecord record;

  @override
  State<AdminTenantDetailsPage> createState() => _AdminTenantDetailsPageState();
}

class _AdminTenantDetailsPageState extends State<AdminTenantDetailsPage> {
  late TenantRegistrationRecord _record = widget.record;
  bool _loading = false;

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final record = await TenantLifecycleService.fetchRegistration(
        _record.registrationId,
      );
      if (mounted) setState(() => _record = record);
    } catch (error) {
      if (mounted) _showMessage('Unable to refresh this tenant record.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAssignment() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminAssignTenantPage(record: _record)),
    );
    if (changed == true) {
      await _refresh();
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _sendInvitation() async {
    final resend = _record.registrationStatus == 'invited';
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var obscurePassword = true;

    final temporaryPassword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            resend ? 'Resend tenant invitation' : 'Send tenant invitation',
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'An invitation email will be sent to ${_record.email}. For this demonstration, give the tenant the temporary password separately. The application will require the tenant to replace it after signing in.',
                    style: const TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Temporary password',
                      hintText: 'At least 8 characters',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(
                          () => obscurePassword = !obscurePassword,
                        ),
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 8) {
                        return 'Use at least 8 characters.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'The temporary password is not included in the email or audit log.',
                    style: TextStyle(
                      color: AppColors.body,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.of(dialogContext).pop(passwordController.text);
              },
              child: Text(resend ? 'Resend invitation' : 'Send invitation'),
            ),
          ],
        ),
      ),
    );
    passwordController.dispose();

    if (temporaryPassword == null) return;

    setState(() => _loading = true);
    try {
      await TenantLifecycleService.sendInvitation(
        _record.registrationId,
        resend: resend,
        temporaryPassword: temporaryPassword,
      );
      await _refresh();
      if (mounted) {
        _showMessage(
          resend
              ? 'A new invitation email was sent to ${_record.email}.'
              : 'Invitation email sent to ${_record.email}.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage(_friendlyInvitationError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDocument(String? path, String label) async {
    if (path == null || path.isEmpty) {
      _showMessage('$label has not been uploaded.');
      return;
    }

    try {
      final url = await TenantLifecycleService.createVerificationDocumentUrl(
        path,
      );
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        _showMessage('Unable to open the $label.');
      }
    } catch (_) {
      if (mounted) _showMessage('Unable to open the $label.');
    }
  }

  Future<void> _reviewVerification() async {
    if (!_record.hasVerificationDocuments) {
      _showMessage(
        'Both tenant verification documents are required before review.',
      );
      return;
    }

    var decision = _record.verificationStatus == 'rejected'
        ? 'rejected'
        : 'verified';
    final notesController = TextEditingController(
      text: _record.verificationNotes ?? '',
    );

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Review tenant documents'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review both uploaded documents against the tenant information. This is a manual administrator review and does not perform eKYC or automatic document-authenticity checking.',
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: decision,
                  decoration: const InputDecoration(
                    labelText: 'Review outcome',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'verified',
                      child: Text('Verified'),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rejected'),
                    ),
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text('Keep pending'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => decision = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Review note (optional)',
                    hintText: 'Explain a rejection or required correction',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(decision),
              child: const Text('Save review'),
            ),
          ],
        ),
      ),
    );

    final notes = notesController.text.trim();
    notesController.dispose();
    if (result == null) return;

    setState(() => _loading = true);
    try {
      await TenantLifecycleService.reviewVerification(
        registrationId: _record.registrationId,
        status: result,
        notes: notes.isEmpty ? null : notes,
      );
      await _refresh();
      if (mounted) _showMessage('Tenant verification review saved.');
    } catch (error) {
      if (mounted) {
        _showMessage('Unable to save the verification review: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AdminBackAppBar(
        title: 'Tenant Details',
        subtitle: _loading ? 'Updating record...' : _record.stageLabel,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          AdminCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFFE0E7FF),
                  child: Text(
                    _initials(_record.fullName),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _record.fullName,
                        style: const TextStyle(
                          color: AppColors.heading,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _record.icNumber,
                        style: const TextStyle(
                          color: AppColors.body,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: [
                          AdminStatusPill(
                            label: _record.stageLabel,
                            foregroundColor: adminStatusColor(
                              _record.stageLabel,
                            ),
                            backgroundColor: adminStatusBackground(
                              _record.stageLabel,
                            ),
                          ),
                          AdminStatusPill(
                            label: _record.verificationStageLabel,
                            foregroundColor: adminStatusColor(
                              _record.verificationStageLabel,
                            ),
                            backgroundColor: adminStatusBackground(
                              _record.verificationStageLabel,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Contact information',
            style: TextStyle(
              color: AppColors.heading,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          AdminCard(
            child: Column(
              children: [
                _DetailLine(
                  label: 'Email address',
                  value: _record.email,
                  icon: Icons.email_outlined,
                ),
                _DetailLine(
                  label: 'Phone number',
                  value: _record.phone ?? 'Not provided',
                  icon: Icons.phone_outlined,
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Verification documents',
            style: TextStyle(
              color: AppColors.heading,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          AdminCard(
            child: Column(
              children: [
                _DocumentRow(
                  label: 'Identity document',
                  uploaded: _record.identityDocumentPath != null,
                  onOpen: () => _openDocument(
                    _record.identityDocumentPath,
                    'identity document',
                  ),
                ),
                _DocumentRow(
                  label: 'Employment / study proof',
                  uploaded: _record.employmentOrStudyProofPath != null,
                  onOpen: () => _openDocument(
                    _record.employmentOrStudyProofPath,
                    'employment or study proof',
                  ),
                  last: true,
                ),
                if (_record.verificationNotes != null &&
                    _record.verificationNotes!.isNotEmpty) ...[
                  const Divider(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Review note: ${_record.verificationNotes}',
                      style: const TextStyle(
                        color: AppColors.body,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _loading || !_record.hasVerificationDocuments
                        ? null
                        : _reviewVerification,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(
                      _record.verificationStatus == 'verified'
                          ? 'Update verification review'
                          : 'Review documents',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Rental assignment',
            style: TextStyle(
              color: AppColors.heading,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          AdminCard(
            child: Column(
              children: [
                _DetailLine(
                  label: 'Assigned unit',
                  value: _record.unitLabel,
                  icon: Icons.meeting_room_outlined,
                ),
                _DetailLine(
                  label: 'Tenancy period',
                  value: _dateRange(_record.startDate, _record.endDate),
                  icon: Icons.date_range_outlined,
                ),
                _DetailLine(
                  label: 'Monthly rental amount',
                  value: _record.monthlyRentalAmount == null
                      ? 'Not configured'
                      : 'RM ${_record.monthlyRentalAmount!.toStringAsFixed(2)}',
                  icon: Icons.payments_outlined,
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loading || !_record.canAssign
                  ? null
                  : _openAssignment,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: Text(
                _record.hasAssignment
                    ? 'Update rental assignment'
                    : 'Assign rental unit',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AdminAuditLogPage(
                            registrationId: _record.registrationId,
                            tenantName: _record.fullName,
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.history_rounded),
              label: const Text('View tenant audit history'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0B8A76),
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFF9BD8CB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (_record.canInvite || _record.canResendInvitation) &&
                      !_loading
                  ? _sendInvitation
                  : null,
              icon: Icon(
                _record.registrationStatus == 'invited'
                    ? Icons.mark_email_read_outlined
                    : Icons.send_outlined,
              ),
              label: Text(
                _record.registrationStatus == 'invited'
                    ? 'Resend invitation email'
                    : 'Send invitation email',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFD9DEEA),
                disabledForegroundColor: const Color(0xFF7A8495),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          AdminCard(
            color: const Color(0xFFF0F5FF),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _record.canInvite
                        ? AppFeatureFlags
                                  .bypassTenantDocumentVerificationForTesting
                              ? 'Set a temporary password and send the invitation. The tenant can enter the module after replacing the password; document submission remains available but is optional during testing.'
                              : 'Set a temporary password and send the invitation. The tenant must replace the password and upload both verification documents.'
                        : _record.canResendInvitation
                        ? 'A pending invitation already exists. Resending creates a new temporary password for an account that has not yet been accepted.'
                        : AppFeatureFlags
                              .bypassTenantDocumentVerificationForTesting
                        ? 'Document verification is optional during module testing. You may assign a rental unit after the tenant completes account setup.'
                        : _record.verificationStatus != 'verified'
                        ? 'Unit assignment becomes available after both tenant documents are reviewed and verified.'
                        : 'The tenant is verified. Complete the rental-unit assignment to activate access.',
                    style: const TextStyle(
                      color: Color(0xFF5D75B4),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _friendlyInvitationError(Object error) {
    final message = error.toString();
    if (message.contains('FunctionException') ||
        message.contains('not configured')) {
      return 'The invitation service is not deployed or configured yet.';
    }
    return message.replaceFirst('Bad state: ', '');
  }
}

class AdminAssignTenantPage extends StatefulWidget {
  const AdminAssignTenantPage({required this.record, super.key});

  final TenantRegistrationRecord record;

  @override
  State<AdminAssignTenantPage> createState() => _AdminAssignTenantPageState();
}

class _AdminAssignTenantPageState extends State<AdminAssignTenantPage> {
  final _formKey = GlobalKey<FormState>();
  final _rentController = TextEditingController();
  final _shareController = TextEditingController(text: '1.00');
  List<RentalUnitOption> _units = const [];
  String? _selectedUnitId;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  RentalUnitOption? get _selectedUnit {
    for (final unit in _units) {
      if (unit.unitId == _selectedUnitId) return unit;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _selectedUnitId = widget.record.unitId;
    _startDate = widget.record.startDate ?? DateTime.now();
    _endDate = widget.record.endDate;
    if (widget.record.monthlyRentalAmount != null) {
      _rentController.text = widget.record.monthlyRentalAmount!.toStringAsFixed(
        2,
      );
    }
    _shareController.text = widget.record.occupancyShare.toStringAsFixed(2);
    _loadUnits();
  }

  @override
  void dispose() {
    _rentController.dispose();
    _shareController.dispose();
    super.dispose();
  }

  Future<void> _loadUnits() async {
    try {
      final units = await TenantLifecycleService.fetchAvailableUnits();
      if (!mounted) return;
      setState(() {
        _units = units;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Rental units could not be loaded. Check the database setup.';
      });
    }
  }

  Future<void> _selectDate({required bool start}) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: start ? _startDate : (_endDate ?? _startDate),
    );
    if (selected == null) return;
    setState(() {
      if (start) {
        _startDate = selected;
      } else {
        _endDate = selected;
      }
    });
  }

  Future<void> _selectUnit() async {
    final selected = await showModalBottomSheet<RentalUnitOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RentalUnitPicker(
        units: _units,
        selectedUnitId: _selectedUnitId,
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedUnitId = selected.unitId);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUnitId == null) {
      _showMessage('Select a rental unit.');
      return;
    }
    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      _showMessage('The tenancy end date cannot be before the start date.');
      return;
    }

    final rent = double.tryParse(_rentController.text.trim());
    final share = double.tryParse(_shareController.text.trim());
    if (rent == null || rent < 0) {
      _showMessage('Enter a valid monthly rental amount.');
      return;
    }
    if (share == null || share <= 0 || share > 1) {
      _showMessage('Enter an occupancy share between 0 and 1.');
      return;
    }

    setState(() => _saving = true);
    try {
      await TenantLifecycleService.saveAssignment(
        registrationId: widget.record.registrationId,
        unitId: _selectedUnitId!,
        startDate: _startDate,
        endDate: _endDate,
        monthlyRentalAmount: rent,
        occupancyShare: share,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rental unit assignment saved.')),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) _showMessage('Unable to save the rental assignment.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: const AdminBackAppBar(title: 'Assign Rental Unit'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            Text(
              'Step 2 · ${widget.record.fullName}',
              style: const TextStyle(
                color: AppColors.heading,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Search and assign the rental unit separately from tenant information entry.',
              style: TextStyle(
                color: AppColors.body,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              AdminCard(
                color: const Color(0xFFFFF5E8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.body, height: 1.4),
                ),
              )
            else
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rental unit',
                      style: TextStyle(
                        color: AppColors.heading,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const LinearProgressIndicator()
                    else if (_units.isEmpty)
                      const Text(
                        'No rental units are available for assignment.',
                        style: TextStyle(color: AppColors.body, fontSize: 13),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _selectUnit,
                          icon: const Icon(Icons.search_rounded),
                          label: Text(
                            _selectedUnit?.label ?? 'Search and select a unit',
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    if (!_loading && _selectedUnit != null) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Unit status: ${_selectedUnit!.status}',
                          style: const TextStyle(
                            color: AppColors.body,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    const Text(
                      'Tenancy start date',
                      style: TextStyle(
                        color: AppColors.heading,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _dateButton(
                      icon: Icons.calendar_today_outlined,
                      label: _formatDate(_startDate),
                      onPressed: () => _selectDate(start: true),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'Tenancy end date',
                      style: TextStyle(
                        color: AppColors.heading,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _dateButton(
                      icon: Icons.event_available_outlined,
                      label: _endDate == null
                          ? 'No end date'
                          : _formatDate(_endDate!),
                      onPressed: () => _selectDate(start: false),
                      trailing: _endDate == null
                          ? null
                          : IconButton(
                              onPressed: () => setState(() => _endDate = null),
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: _rentController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) => _required(value, 'monthly rent'),
                      decoration: _fieldDecoration(
                        Icons.payments_outlined,
                        'Monthly rental amount (RM)',
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: _shareController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _fieldDecoration(
                        Icons.pie_chart_outline_rounded,
                        'Occupancy share (0–1)',
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            AdminCard(
              color: const Color(0xFFF0F5FF),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Saving this page records the unit mapping and rental details. The tenant will then be able to use functions linked to the assigned unit.',
                      style: TextStyle(
                        color: Color(0xFF5D75B4),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving || _loading || _units.isEmpty ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save rental assignment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E5ED)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, color: AppColors.primary),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: const TextStyle(color: AppColors.heading),
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  static String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return 'Enter the $label.';
    return null;
  }
}

class _RentalUnitPicker extends StatefulWidget {
  const _RentalUnitPicker({
    required this.units,
    required this.selectedUnitId,
  });

  final List<RentalUnitOption> units;
  final String? selectedUnitId;

  @override
  State<_RentalUnitPicker> createState() => _RentalUnitPickerState();
}

class _RentalUnitPickerState extends State<_RentalUnitPicker> {
  late String _block;
  late int _floor;

  @override
  void initState() {
    super.initState();
    RentalUnitOption? selected;
    for (final unit in widget.units) {
      if (unit.unitId == widget.selectedUnitId) {
        selected = unit;
        break;
      }
    }
    _block = selected?.blockCode == 'B' ? 'B' : 'A';
    _floor = selected?.floorNumber ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    final unitsOnFloor = widget.units
        .where(
          (unit) => unit.blockCode == _block && unit.floorNumber == _floor,
        )
        .toList()
      ..sort((first, second) => first.unitNumber.compareTo(second.unitNumber));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select a rental unit',
                style: TextStyle(
                  color: AppColors.heading,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '1. Choose block',
                style: TextStyle(
                  color: AppColors.body,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final block in ['A', 'B']) ...[
                    Expanded(
                      child: ChoiceChip(
                        label: Text('Block $block'),
                        selected: _block == block,
                        onSelected: (_) => setState(() {
                          _block = block;
                          _floor = 1;
                        }),
                        showCheckmark: false,
                      ),
                    ),
                    if (block == 'A') const SizedBox(width: 10),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _floor,
                decoration: const InputDecoration(labelText: '2. Choose floor'),
                items: [
                  for (var floor = 1; floor <= 25; floor++)
                    DropdownMenuItem(
                      value: floor,
                      child: Text('Floor ${floor.toString().padLeft(2, '0')}'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _floor = value);
                },
              ),
              const SizedBox(height: 12),
              Text(
                '3. Choose unit · Block $_block, Floor ${_floor.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: AppColors.body,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: unitsOnFloor.isEmpty
                    ? const Center(
                        child: Text('No units are available on this floor.'),
                      )
                    : GridView.builder(
                        itemCount: unitsOnFloor.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 2.3,
                            ),
                        itemBuilder: (context, index) {
                          final unit = unitsOnFloor[index];
                          final selected = unit.unitId == widget.selectedUnitId;
                          return OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(unit),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: selected
                                  ? const Color(0xFFEAF0FF)
                                  : Colors.white,
                              side: BorderSide(
                                color: selected
                                    ? AppColors.primary
                                    : const Color(0xFFE1E5ED),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  unit.unitNumber,
                                  style: const TextStyle(
                                    color: AppColors.heading,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  unit.status,
                                  style: const TextStyle(
                                    color: AppColors.body,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.label,
    required this.uploaded,
    required this.onOpen,
    this.last = false,
  });

  final String label;
  final bool uploaded;
  final VoidCallback onOpen;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFECEFF3))),
            ),
      child: Row(
        children: [
          Icon(
            uploaded
                ? Icons.description_outlined
                : Icons.insert_drive_file_outlined,
            color: uploaded ? AppColors.primary : const Color(0xFF9CA4B3),
            size: 22,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  uploaded ? 'File uploaded' : 'Waiting for tenant upload',
                  style: const TextStyle(color: AppColors.body, fontSize: 12),
                ),
              ],
            ),
          ),
          if (uploaded)
            IconButton(
              onPressed: onOpen,
              tooltip: 'Open file',
              icon: const Icon(Icons.open_in_new_rounded),
              color: AppColors.primary,
            ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.label,
    required this.value,
    required this.icon,
    this.last = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFECEFF3))),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.body, fontSize: 13),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
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

InputDecoration _fieldDecoration(IconData icon, String label) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: AppColors.primary),
    filled: true,
    fillColor: const Color(0xFFF8F9FC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE1E5ED)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE1E5ED)),
    ),
  );
}

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

String _dateRange(DateTime? start, DateTime? end) {
  if (start == null) return 'Not configured';
  final startText = _formatDate(start);
  return end == null
      ? '$startText – ongoing'
      : '$startText – ${_formatDate(end)}';
}

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  if (words.length > 1) {
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
  return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
}
