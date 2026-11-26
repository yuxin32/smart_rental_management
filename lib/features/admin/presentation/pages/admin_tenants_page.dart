import 'package:supabase_flutter/supabase_flutter.dart';
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
            contact_number: _phoneController.text.trim().isEmpty
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
                    'An invitation email will be sent to ${_record.email}. The email includes the temporary password you enter below. The application will require the tenant to replace it after signing in.',
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
                    'The temporary password is included in the invitation email. It is not saved in application records or audit logs.',
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
                  value: _record.contact_number ?? 'Not provided',
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
                if (_record.hasAssignment) ...[
                  _DetailLine(
                    label: 'Rental space',
                    value: _record.rentalType == 'room'
                        ? 'Room ${_record.roomNumber}'
                        : 'Whole unit',
                    icon: Icons.bed_outlined,
                  ),
                  _DetailLine(
                    label: 'Number of occupants',
                    value: '${_record.occupantCount}',
                    icon: Icons.people_outline,
                  ),
                ],
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
  const AdminAssignTenantPage({
    required this.record,
    this.loadUnits,
    super.key,
  });

  final TenantRegistrationRecord record;
  final Future<List<RegisteredTenancyUnit>> Function(
    DateTime start,
    DateTime? end,
  )?
  loadUnits;

  @override
  State<AdminAssignTenantPage> createState() => _AdminAssignTenantPageState();
}

class _AdminAssignTenantPageState extends State<AdminAssignTenantPage> {
  final _formKey = GlobalKey<FormState>();
  final _rentController = TextEditingController();
  List<RegisteredTenancyUnit> _units = const [];
  String? _selectedBuilding, _selectedUnitId;
  bool _singleRoom = false;
  int? _room;
  int _occupants = 1, _loadVersion = 0;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _loading = true, _saving = false;
  String? _loadError, _saveError;
  static const _red = Color(0xFFB42318);

  RegisteredTenancyUnit? get _selectedUnit =>
      _units.where((u) => u.unitId == _selectedUnitId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _selectedUnitId = widget.record.unitId;
    _startDate = widget.record.startDate ?? DateTime.now();
    _endDate = widget.record.endDate;
    _singleRoom = widget.record.rentalType == 'room';
    _room = widget.record.roomNumber;
    _occupants = widget.record.occupantCount;
    final rent = widget.record.monthlyRentalAmount;
    if (rent != null) _rentController.text = rent.toStringAsFixed(2);
    _loadUnits();
  }

  @override
  void dispose() {
    _rentController.dispose();
    super.dispose();
  }

  Future<void> _loadUnits() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final units =
          await (widget.loadUnits?.call(_startDate, _endDate) ??
              TenantLifecycleService.fetchTenancyUnits(
                registrationId: widget.record.registrationId,
                start: _startDate,
                end: _endDate,
              ));
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _units = units;
        final unit = _selectedUnit;
        _selectedBuilding = unit?.buildingName ?? _selectedBuilding;
        if (!units.any((u) => u.buildingName == _selectedBuilding))
          _selectedBuilding = null;
        if (unit == null || unit.isFullyOccupied) {
          if (unit?.isFullyOccupied == true)
            _saveError =
                'This unit is now fully occupied for the selected dates. Choose another unit or change the dates.';
          _selectedUnitId = null;
          _room = null;
        } else if (_room != null && _room! > unit.bedrooms) {
          _room = null;
          _saveError =
              'The Owner has updated the bedroom count. Please select an available room again.';
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loading = false;
        _loadError =
            'We could not check unit availability. Check your connection and select Retry. Your entries have been kept.';
      });
    }
  }

  Future<void> _selectDate(bool start) async {
    if (_saving || _loading) return;
    final date = await showDatePicker(
      context: context,
      firstDate: start ? DateTime(2020) : _startDate,
      lastDate: DateTime(2100),
      initialDate: start ? _startDate : (_endDate ?? _startDate),
    );
    if (date == null || !mounted) return;
    setState(() {
      _saveError = null;
      if (start) {
        _startDate = date;
        if (_endDate?.isBefore(date) == true) _endDate = null;
      } else {
        _endDate = date;
      }
    });
    await _loadUnits();
  }

  String? get _availabilityProblem {
    final unit = _selectedUnit;
    if (unit == null) return null;
    if (unit.wholeUnitReserved)
      return 'This unit is reserved under a whole-unit tenancy for these dates. Choose a different unit or date range.';
    if (!_singleRoom && unit.total > 0)
      return 'This unit already has room tenants during these dates. Tick “Rent single room” to choose an available room, or select another unit for whole-unit rental.';
    if (_singleRoom && _room == null) return null;
    final remaining = unit.remaining(!_singleRoom, _room);
    if (remaining == 0)
      return _singleRoom
          ? 'Room $_room has no available places for these dates. Select another room or change the dates.'
          : 'This unit is fully occupied for these dates. Select another unit.';
    if (_occupants > remaining)
      return 'Only $remaining place${remaining == 1 ? '' : 's'} remain${remaining == 1 ? 's' : ''} for these dates. Reduce the number of occupants or choose another room.';
    return null;
  }

  String _friendlyError(Object error) {
    if (error is PostgrestException) {
      final text = error.message.toLowerCase();
      if (error.code == '42501')
        return 'Your administrator session is no longer authorised. Sign in again and retry.';
      if (text.contains('room does not exist'))
        return 'The selected room is no longer listed for this property. Review the updated bedroom count and choose a room again.';
      if (text.contains('reserved'))
        return 'Another tenancy now overlaps this unit for the selected dates. Choose an available room or another unit.';
      if (text.contains('capacity'))
        return 'This room or unit no longer has enough space. Availability has been refreshed; reduce the occupants or choose another space.';
      if (text.contains('account setup'))
        return 'This tenant has not completed account setup. Ask them to set their password and sign in before assigning a unit.';
      if (text.contains('registered rental unit'))
        return 'This property is no longer available for assignment. Select another registered unit.';
      if (error.code == '23505' ||
          error.code == '40001' ||
          error.code == '40P01')
        return 'The tenancy was updated elsewhere. Review the latest availability and try again.';
      if (error.code == '22023' || error.code == '23514')
        return 'Some tenancy details are invalid. Check the dates, rental amount, room and occupant count, then retry.';
    }
    return 'We could not confirm the assignment. Your entries have been kept. Check the tenant details before retrying to avoid repeating a completed assignment.';
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    setState(() => _saveError = null);
    final valid = _formKey.currentState!.validate();
    String? problem;
    if (_loadError != null)
      problem =
          'Unit availability could not be checked. Select Retry before saving.';
    else if (_units.isEmpty)
      problem =
          'There are no registered Owner properties to assign. Add a property through the Owner module first.';
    else if (_selectedBuilding == null)
      problem = 'Select a building or apartment first.';
    else if (_selectedUnit == null)
      problem =
          'Select an available unit in the chosen building. Grey units are fully occupied for the selected dates.';
    else if (_singleRoom && _room == null)
      problem = 'Select a room for this tenancy.';
    else if (_endDate?.isBefore(_startDate) == true)
      problem = 'The tenancy end date must be on or after its start date.';
    else
      problem = _availabilityProblem;
    if (problem != null || !valid) {
      setState(
        () => _saveError =
            problem ??
            'Enter a valid monthly rental amount in the highlighted field.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await TenantLifecycleService.saveAssignment(
        registrationId: widget.record.registrationId,
        unitId: _selectedUnitId!,
        startDate: _startDate,
        endDate: _endDate,
        monthlyRentalAmount: double.parse(_rentController.text.trim()),
        rentalType: _singleRoom ? 'room' : 'whole_unit',
        roomNumber: _singleRoom ? _room : null,
        occupantCount: _occupants,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF16794C),
          content: Text(
            'Tenancy assigned successfully. Tenant details have been updated.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saveError = _friendlyError(error));
      await _loadUnits();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _notice(String text, {bool error = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFF1F0) : const Color(0xFFEEF4FF),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: error ? const Color(0xFFF5B7B1) : const Color(0xFFD1DFFC),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.error_outline : Icons.info_outline,
          color: error ? _red : AppColors.primary,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: error ? _red : AppColors.heading,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _section(
    String number,
    String title,
    IconData icon,
    List<Widget> children,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2F8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$number. $title',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.heading,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    ),
  );

  InputDecoration _input(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    errorStyle: const TextStyle(color: _red),
    errorMaxLines: 3,
  );

  Widget _dateTile(
    String label,
    String value,
    VoidCallback action, {
    Widget? trailing,
  }) => OutlinedButton(
    onPressed: _saving || _loading ? null : action,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child: Row(
      children: [
        const Icon(Icons.calendar_today_outlined, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppColors.body),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.heading,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final unit = _selectedUnit;
    final locked = _saving || _loading;
    final buildings = _units.map((u) => u.buildingName).toSet().toList()
      ..sort();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: const AdminBackAppBar(title: 'Assign tenancy'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            Text(
              widget.record.fullName,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: AppColors.heading,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose the tenancy dates and rental space. Availability is checked for the entire selected period.',
              style: TextStyle(color: AppColors.body, height: 1.45),
            ),
            const SizedBox(height: 20),
            _section('1', 'Tenancy period', Icons.date_range_outlined, [
              _dateTile(
                'Start date',
                _formatDate(_startDate),
                () => _selectDate(true),
              ),
              const SizedBox(height: 10),
              _dateTile(
                'End date',
                _endDate == null ? 'No end date' : _formatDate(_endDate!),
                () => _selectDate(false),
                trailing: _endDate == null
                    ? null
                    : IconButton(
                        tooltip: 'Remove end date',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: locked
                            ? null
                            : () async {
                                setState(() {
                                  _endDate = null;
                                  _saveError = null;
                                });
                                await _loadUnits();
                              },
                      ),
              ),
            ]),
            _section('2', 'Building & unit', Icons.apartment_outlined, [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: LinearProgressIndicator(),
                ),
              if (_loadError != null) ...[
                _notice(_loadError!, error: true),
                TextButton.icon(
                  onPressed: locked ? null : _loadUnits,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry availability'),
                ),
              ] else if (!_loading && _units.isEmpty)
                _notice(
                  'No Owner properties are registered. Add a property in the Owner module before assigning a tenancy.',
                  error: true,
                ),
              DropdownButtonFormField<String>(
                key: ValueKey('building-$_selectedBuilding'),
                initialValue: _selectedBuilding,
                decoration: _input('Building / apartment'),
                isExpanded: true,
                items: buildings
                    .map(
                      (name) => DropdownMenuItem(
                        value: name,
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: locked
                    ? null
                    : (value) => setState(() {
                        _selectedBuilding = value;
                        _selectedUnitId = null;
                        _room = null;
                        _occupants = 1;
                        _saveError = null;
                      }),
                validator: (value) =>
                    value == null ? 'Select a building / apartment.' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: ValueKey('unit-$_selectedBuilding-$_selectedUnitId'),
                initialValue: _selectedUnitId,
                decoration: _input('Unit number'),
                isExpanded: true,
                items: _units
                    .where((u) => u.buildingName == _selectedBuilding)
                    .map(
                      (u) => DropdownMenuItem(
                        value: u.unitId,
                        enabled: !u.isFullyOccupied,
                        child: Text(
                          u.isFullyOccupied
                              ? '${u.unitNumber} · Fully occupied'
                              : u.unitNumber,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: u.isFullyOccupied
                                ? Colors.grey
                                : AppColors.heading,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: locked || _selectedBuilding == null
                    ? null
                    : (value) => setState(() {
                        _selectedUnitId = value;
                        _room = null;
                        _occupants = 1;
                        _saveError = null;
                      }),
                validator: (value) =>
                    value == null ? 'Select an available unit.' : null,
              ),
              if (unit != null) ...[
                const SizedBox(height: 14),
                _notice(
                  '${unit.bedrooms} bedroom${unit.bedrooms == 1 ? '' : 's'} registered by the Owner. Grey units and rooms are unavailable for the selected dates.',
                ),
              ],
            ]),
            if (unit != null)
              _section(
                '3',
                'Rental space',
                _singleRoom ? Icons.bed_outlined : Icons.home_outlined,
                [
                  Container(
                    decoration: BoxDecoration(
                      color: _singleRoom
                          ? const Color(0xFFEAF7F4)
                          : const Color(0xFFEEF2F8),
                      border: Border.all(
                        color: _singleRoom
                            ? const Color(0xFF75BFAF)
                            : const Color(0xFFC8D3E2),
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: CheckboxListTile(
                        value: _singleRoom,
                        activeColor: const Color(0xFF197C68),
                        title: const Text(
                          'Rent single room',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          _singleRoom
                              ? 'Select one room. Maximum 2 occupants in that room.'
                              : 'Unchecked: rent the entire unit for this household. Maximum 8 occupants.',
                        ),
                        onChanged: locked
                            ? null
                            : (value) => setState(() {
                                _singleRoom = value!;
                                _room = null;
                                _occupants = 1;
                                _saveError = null;
                              }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        _singleRoom ? Icons.bed_outlined : Icons.home_outlined,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _singleRoom
                            ? 'Single-room tenancy'
                            : 'Whole-unit tenancy',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.heading,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_singleRoom) ...[
                    DropdownButtonFormField<int>(
                      key: ValueKey('room-$_selectedUnitId-$_room'),
                      initialValue: _room,
                      decoration: _input('Select room'),
                      isExpanded: true,
                      items: List.generate(unit.bedrooms, (i) {
                        final full = unit.remaining(false, i + 1) == 0;
                        return DropdownMenuItem(
                          value: i + 1,
                          enabled: !full,
                          child: Text(
                            'Room ${i + 1} · ${full ? 'Full' : '${unit.roomOccupants[i]}/2 occupied'}',
                            style: TextStyle(
                              color: full ? Colors.grey : AppColors.heading,
                            ),
                          ),
                        );
                      }),
                      onChanged: locked
                          ? null
                          : (value) => setState(() {
                              _room = value;
                              _occupants = 1;
                              _saveError = null;
                            }),
                      validator: (value) => _singleRoom && value == null
                          ? 'Select an available room.'
                          : null,
                    ),
                    const SizedBox(height: 14),
                  ],
                  DropdownButtonFormField<int>(
                    key: ValueKey('occupants-$_singleRoom-$_occupants'),
                    initialValue: _occupants,
                    decoration: _input('Number of occupants'),
                    items: List.generate(
                      _singleRoom ? 2 : 8,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1} ${i == 0 ? 'person' : 'people'}'),
                      ),
                    ),
                    onChanged: locked
                        ? null
                        : (value) => setState(() {
                            _occupants = value!;
                            _saveError = null;
                          }),
                  ),
                  const SizedBox(height: 14),
                  if (_availabilityProblem != null)
                    _notice(_availabilityProblem!, error: true)
                  else
                    _notice(
                      _singleRoom && _room == null
                          ? 'Choose a room to see its availability.'
                          : '${unit.remaining(!_singleRoom, _room)} place(s) available in this rental space. The unit limit remains 8 occupants in total.',
                    ),
                ],
              ),
            _section(
              unit == null ? '3' : '4',
              'Monthly rent',
              Icons.payments_outlined,
              [
                TextFormField(
                  controller: _rentController,
                  enabled: !_saving,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _input('Monthly rental amount (RM)'),
                  validator: (value) {
                    final amount = double.tryParse(value?.trim() ?? '');
                    if (amount == null || !amount.isFinite || amount < 0)
                      return 'Enter a rental amount of RM 0.00 or above.';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                const Text(
                  'Enter the monthly amount for this tenancy: the selected room or the entire unit.',
                  style: TextStyle(fontSize: 12, color: AppColors.body),
                ),
              ],
            ),
            if (_saveError != null) ...[
              _notice(_saveError!, error: true),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: locked ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _saving ? 'Saving assignment…' : 'Save tenancy assignment',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
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
