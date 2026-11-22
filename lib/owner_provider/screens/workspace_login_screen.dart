import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/user_session.dart';
import '../services/backend/supabase_auth_repository.dart';
import '../services/backend/supabase_backend_provider.dart';
import '../services/backend/safe_diagnostics.dart';
import '../services/backend/auth_failure_message.dart';
import '../theme/app_theme.dart';
import 'password_recovery_screen.dart';

/// Local preview login, or Supabase email/password when configured.
class WorkspaceLoginScreen extends StatefulWidget {
  const WorkspaceLoginScreen({
    super.key,
    this.backend,
    this.initiallyRegistering = false,
    this.onBackToWelcome,
  });

  final SupabaseBackendProvider? backend;
  final bool initiallyRegistering;
  final VoidCallback? onBackToWelcome;

  @override
  State<WorkspaceLoginScreen> createState() => _WorkspaceLoginScreenState();
}

class _WorkspaceLoginScreenState extends State<WorkspaceLoginScreen> {
  static const _customServiceArea = 'Other area';
  static const _serviceAreas = [
    'Johor',
    'Kedah',
    'Kelantan',
    'Kuala Lumpur',
    'Labuan',
    'Melaka',
    'Negeri Sembilan',
    'Pahang',
    'Penang',
    'Perak',
    'Perlis',
    'Putrajaya',
    'Sabah',
    'Sarawak',
    'Selangor',
    'Terengganu',
    _customServiceArea,
  ];

  GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController(text: 'owner@example.com');
  final _passCtrl = TextEditingController(text: 'demo1234');
  final _contactCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  int _registrationStep = 0;
  String? _authError;
  final _scroll = ScrollController();
  final _customServiceAreaCtrl = TextEditingController();
  final _originCtrl = TextEditingController();
  final _hourlyRateCtrl = TextEditingController();
  final _dailyRateCtrl = TextEditingController();
  UserRole _role = UserRole.owner;
  bool _submitting = false;
  bool _registering = false;
  bool _showPassword = false;
  String? _selectedServiceArea;

  @override
  void initState() {
    super.initState();
    _registering = widget.initiallyRegistering;
    if (widget.backend != null) {
      _emailCtrl.clear();
      _passCtrl.clear();
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _contactCtrl.dispose();
    _nameCtrl.dispose();
    _scroll.dispose();
    _customServiceAreaCtrl.dispose();
    _originCtrl.dispose();
    _hourlyRateCtrl.dispose();
    _dailyRateCtrl.dispose();
    super.dispose();
  }

  void _selectRole(UserRole role) {
    if (_submitting || _role == role) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    setState(() {
      _role = role;
      _registrationStep = 0;
      _authError = null;
      _formKey = GlobalKey<FormState>();
      if (widget.backend == null) {
        _emailCtrl.text = role == UserRole.owner
            ? 'owner@example.com'
            : 'provider@example.com';
      }
    });
  }

  String? _validateContactNumber(String? value) {
    final input = (value ?? '').trim();
    if (input.isEmpty) return 'Contact number is required';
    if (!RegExp(r'^\+?[0-9()\s-]+$').hasMatch(input)) {
      return 'Use digits, spaces or hyphens only';
    }
    final digits = input.replaceAll(RegExp(r'\D'), '');
    final local = digits.startsWith('60') ? '0${digits.substring(2)}' : digits;
    if (!RegExp(r'^0[1-9]\d{7,9}$').hasMatch(local)) {
      return 'Enter a Malaysian number, e.g. 012-345 6789';
    }
    return null;
  }

  void _switchMode() {
    if (_submitting) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    setState(() {
      _registering = !_registering;
      _registrationStep = 0;
      _authError = null;
      // Rebuild the form so validation from the previous mode is discarded.
      _formKey = GlobalKey<FormState>();
    });
  }

  void _openPasswordRecovery() {
    if (_submitting) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    setState(() => _formKey = GlobalKey<FormState>());
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PasswordRecoveryScreen(
          backend: widget.backend,
          initialEmail: _emailCtrl.text.trim(),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      setState(
          () => _authError = 'Check the highlighted fields before continuing.');
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      return;
    }
    if (_registering && _registrationStep == 0) {
      setState(() {
        _registrationStep = 1;
        _formKey = GlobalKey<FormState>();
        _authError = null;
      });
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      return;
    }
    setState(() {
      _submitting = true;
      _authError = null;
    });
    try {
      if (widget.backend == null) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        UserSessionAccess.of(context).signIn(
          email: _emailCtrl.text.trim(),
          displayName: _role == UserRole.owner ? 'Oh Wan Ting' : 'Provider A',
          role: _role,
        );
      } else if (_registering) {
        final hourlyRate = double.tryParse(_hourlyRateCtrl.text.trim());
        final dailyRate = double.tryParse(_dailyRateCtrl.text.trim());
        final outcome = await widget.backend!.auth.register(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
          role: _role,
          contactNumber: _contactCtrl.text.trim(),
          displayName: _nameCtrl.text.trim(),
          providerDetails: _role == UserRole.provider
              ? ProviderRegistrationDetails(
                  serviceArea: _selectedServiceArea == _customServiceArea
                      ? _customServiceAreaCtrl.text.trim()
                      : _selectedServiceArea!,
                  serviceOriginAddress: _originCtrl.text.trim(),
                  hourlyRate: hourlyRate,
                  dailyRate: dailyRate,
                )
              : null,
        );
        if (!mounted) return;
        _notice(outcome.requiresEmailConfirmation
            ? 'Check your email to confirm the account, then sign in.'
            : 'Account created. You can now sign in.');
        setState(() {
          _registering = false;
          _registrationStep = 0;
          _formKey = GlobalKey<FormState>();
        });
      } else {
        final identity = await widget.backend!.auth.signIn(
          _emailCtrl.text.trim(),
          _passCtrl.text,
        );
        if (identity.role != _role) {
          await widget.backend!.auth.signOut();
          throw const AccountRoleMismatch();
        }
        if (!mounted) return;
        UserSessionAccess.of(context).signIn(
          email: identity.email,
          displayName: identity.displayName ?? '',
          role: identity.role,
          providerId:
              identity.role == UserRole.provider ? identity.userId : null,
        );
      }
    } catch (error) {
      SafeDiagnostics.app.record(
          _registering ? SafeOperation.register : SafeOperation.signIn, error);
      if (mounted) {
        setState(() => _authError =
            AuthFailureMessage.forOperation(error, registering: _registering));
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _notice(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: widget.onBackToWelcome == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_submitting) widget.onBackToWelcome?.call();
        },
        child: Scaffold(
          appBar: widget.onBackToWelcome == null
              ? null
              : AppBar(
                  leading: BackButton(
                      onPressed: _submitting ? () {} : widget.onBackToWelcome),
                  title: Text(_registering ? 'Create account' : 'Log in'),
                ),
          backgroundColor: AppColors.backgroundLight,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(22, 25, 22, 30),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(Icons.home_work_outlined,
                                color: AppColors.primaryLighter, size: 31),
                            SizedBox(height: 18),
                            Text('Smart Rental',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 27,
                                    fontWeight: FontWeight.w800)),
                            SizedBox(height: 6),
                            Text(
                                'Cleaning-service workspace for owners and providers',
                                style: TextStyle(
                                    color: Color(0xFFD9E8FF),
                                    fontSize: 12,
                                    height: 1.4)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                    _registering
                                        ? 'Create account'
                                        : 'Welcome back',
                                    style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary)),
                                const SizedBox(height: 6),
                                Text(
                                    widget.backend == null
                                        ? 'Choose your role and continue.'
                                        : _registering
                                            ? 'Set up your account in a few steps.'
                                            : 'Use your registered Owner or Provider account.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondaryLight)),
                                const SizedBox(height: 20),
                                if (_authError != null)
                                  Semantics(
                                      liveRegion: true,
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        margin:
                                            const EdgeInsets.only(bottom: 16),
                                        decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .errorContainer,
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Text(_authError!,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onErrorContainer)),
                                      )),
                                if (_registering) ...[
                                  Text(_registrationStep == 0
                                      ? 'Step 1 of 2 · Account details'
                                      : 'Step 2 of 2 · Contact & service details'),
                                  const SizedBox(height: 12),
                                ],
                                if (!_registering ||
                                    _registrationStep == 0) ...[
                                  LayoutBuilder(
                                      builder: (context, constraints) {
                                    final stackRoles =
                                        constraints.maxWidth < 260 ||
                                            MediaQuery.textScalerOf(context)
                                                    .scale(11) >
                                                15;
                                    if (stackRoles) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _roleTile(
                                              UserRole.owner,
                                              Icons.apartment_outlined,
                                              'Property Owner'),
                                          const SizedBox(height: 10),
                                          _roleTile(
                                              UserRole.provider,
                                              Icons.cleaning_services_outlined,
                                              'Service Provider'),
                                        ],
                                      );
                                    }
                                    return Row(children: [
                                      Expanded(
                                          child: _roleTile(
                                              UserRole.owner,
                                              Icons.apartment_outlined,
                                              'Property Owner')),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: _roleTile(
                                              UserRole.provider,
                                              Icons.cleaning_services_outlined,
                                              'Service Provider')),
                                    ]);
                                  }),
                                  const SizedBox(height: 20),
                                  if (_registering) ...[
                                    _label('Your name'),
                                    const SizedBox(height: 7),
                                    TextFormField(
                                      key: const Key('registration-name'),
                                      controller: _nameCtrl,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      autofillHints: const [AutofillHints.name],
                                      maxLength: 60,
                                      decoration: const InputDecoration(
                                          hintText: 'e.g. Wan Ting',
                                          helperText:
                                              'Shown on your profile and welcome message.'),
                                      validator: (v) => v == null ||
                                              v.trim().runes.length < 2 ||
                                              v.trim().runes.length > 60
                                          ? 'Enter a name of 2–60 characters'
                                          : null,
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  _label('Email address'),
                                  const SizedBox(height: 7),
                                  TextFormField(
                                    controller: _emailCtrl,
                                    autovalidateMode:
                                        AutovalidateMode.onUserInteraction,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      hintText: 'name@example.com',
                                      prefixIcon: Icon(Icons.mail_outline),
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Email address is required';
                                      }
                                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                          .hasMatch(value.trim())) {
                                        return 'Enter a valid email';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _label('Password'),
                                  const SizedBox(height: 7),
                                  TextFormField(
                                    controller: _passCtrl,
                                    autovalidateMode:
                                        AutovalidateMode.onUserInteraction,
                                    obscureText: !_showPassword,
                                    textInputAction: _registering
                                        ? TextInputAction.next
                                        : TextInputAction.done,
                                    onFieldSubmitted:
                                        _registering ? null : (_) => _submit(),
                                    decoration: InputDecoration(
                                      hintText: 'Password',
                                      helperText: _registering
                                          ? 'Use at least 8 characters.'
                                          : null,
                                      prefixIcon:
                                          const Icon(Icons.lock_outline),
                                      suffixIcon: IconButton(
                                        tooltip: _showPassword
                                            ? 'Hide password'
                                            : 'Show password',
                                        onPressed: () => setState(() =>
                                            _showPassword = !_showPassword),
                                        icon: Icon(_showPassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Password is required';
                                      }
                                      if (value.length <
                                          (widget.backend == null ? 6 : 8)) {
                                        return widget.backend == null
                                            ? 'At least 6 characters'
                                            : 'At least 8 characters';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                                if (_registering && _registrationStep == 1) ...[
                                  Text(
                                      'Creating a ${_role == UserRole.owner ? 'Property Owner' : 'Service Provider'} account for ${_nameCtrl.text.trim()}'),
                                  TextButton(
                                      onPressed: _submitting
                                          ? null
                                          : () => setState(() {
                                                _registrationStep = 0;
                                                _formKey =
                                                    GlobalKey<FormState>();
                                                _authError = null;
                                              }),
                                      child:
                                          const Text('Edit account details')),
                                  const SizedBox(height: 22),
                                  _label('Contact details'),
                                  const SizedBox(height: 12),
                                  _label('Contact number'),
                                  const SizedBox(height: 7),
                                  TextFormField(
                                    controller: _contactCtrl,
                                    autovalidateMode:
                                        AutovalidateMode.onUserInteraction,
                                    keyboardType: TextInputType.phone,
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [
                                      LengthLimitingTextInputFormatter(20),
                                    ],
                                    decoration: const InputDecoration(
                                      hintText: '+60 12 345 6789',
                                      helperText:
                                          'Malaysia: 012-345 6789 or +60 12-345 6789',
                                      prefixIcon: Icon(Icons.phone_outlined),
                                    ),
                                    validator: _validateContactNumber,
                                  ),
                                  if (_role == UserRole.provider) ...[
                                    const SizedBox(height: 22),
                                    _label('Service details'),
                                    const SizedBox(height: 12),
                                    _label('Service area'),
                                    const SizedBox(height: 7),
                                    DropdownButtonFormField<String>(
                                      value: _selectedServiceArea,
                                      autovalidateMode:
                                          AutovalidateMode.onUserInteraction,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        hintText:
                                            'Select your main coverage area',
                                        helperText:
                                            'Choose a state or federal territory.',
                                        prefixIcon: Icon(Icons.place_outlined),
                                      ),
                                      items: _serviceAreas
                                          .map((area) => DropdownMenuItem(
                                                value: area,
                                                child: Text(area),
                                              ))
                                          .toList(),
                                      onChanged: (area) => setState(
                                          () => _selectedServiceArea = area),
                                      validator: (area) => area == null
                                          ? 'Select a service area'
                                          : null,
                                    ),
                                    if (_selectedServiceArea ==
                                        _customServiceArea) ...[
                                      const SizedBox(height: 16),
                                      _label('Your service area'),
                                      const SizedBox(height: 7),
                                      TextFormField(
                                        controller: _customServiceAreaCtrl,
                                        autovalidateMode:
                                            AutovalidateMode.onUserInteraction,
                                        decoration: const InputDecoration(
                                          hintText: 'e.g. Petaling Jaya',
                                          helperText:
                                              'Enter the town or district you cover.',
                                        ),
                                        validator: (value) => value == null ||
                                                value.trim().isEmpty
                                            ? 'Enter your service area'
                                            : null,
                                      ),
                                    ],
                                    const SizedBox(height: 16),
                                    _label('Service origin address'),
                                    const SizedBox(height: 7),
                                    TextFormField(
                                        controller: _originCtrl,
                                        autovalidateMode:
                                            AutovalidateMode.onUserInteraction,
                                        textInputAction: TextInputAction.next,
                                        decoration: const InputDecoration(
                                          hintText:
                                              'Where you start travelling from',
                                          helperText:
                                              'Used to estimate route distance to jobs.',
                                          prefixIcon:
                                              Icon(Icons.location_on_outlined),
                                        ),
                                        validator: (value) => value == null ||
                                                value.trim().isEmpty
                                            ? 'Service origin is required'
                                            : null),
                                    const SizedBox(height: 16),
                                    _label('Hourly rate (RM) · optional'),
                                    const SizedBox(height: 7),
                                    TextFormField(
                                        controller: _hourlyRateCtrl,
                                        autovalidateMode:
                                            AutovalidateMode.onUserInteraction,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          hintText: 'e.g. 80',
                                          helperText:
                                              'Your price per hour in Malaysian ringgit.',
                                          prefixText: 'RM ',
                                          suffixText: '/hour',
                                        ),
                                        validator: (value) {
                                          final input = (value ?? '').trim();
                                          if (input.isEmpty) {
                                            return _dailyRateCtrl.text
                                                    .trim()
                                                    .isEmpty
                                                ? 'Enter an hourly or daily rate'
                                                : null;
                                          }
                                          final rate = double.tryParse(input);
                                          return rate == null ||
                                                  !rate.isFinite ||
                                                  rate <= 0
                                              ? 'Enter a rate greater than RM 0'
                                              : null;
                                        }),
                                    const SizedBox(height: 16),
                                    _label('8-hour daily rate (RM) · optional'),
                                    const SizedBox(height: 7),
                                    TextFormField(
                                        controller: _dailyRateCtrl,
                                        autovalidateMode:
                                            AutovalidateMode.onUserInteraction,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          hintText: 'e.g. 280',
                                          helperText:
                                              'Fixed price for one 8-hour booking. Shorter jobs need an hourly rate.',
                                          prefixText: 'RM ',
                                          suffixText: '/8 hours',
                                        ),
                                        validator: (value) {
                                          final input = (value ?? '').trim();
                                          if (input.isEmpty) return null;
                                          final rate = double.tryParse(input);
                                          return rate == null ||
                                                  !rate.isFinite ||
                                                  rate <= 0
                                              ? 'Enter a rate greater than RM 0'
                                              : null;
                                        }),
                                  ],
                                ],
                                if (!_registering)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _submitting
                                          ? null
                                          : _openPasswordRecovery,
                                      child: const Text('Forgot password?'),
                                    ),
                                  ),
                                const SizedBox(height: 5),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(minHeight: 48),
                                  child: FilledButton(
                                    onPressed: _submitting ? null : _submit,
                                    child: Text(_submitting
                                        ? 'Please wait…'
                                        : _registering
                                            ? _registrationStep == 0
                                                ? 'Continue'
                                                : 'Create account'
                                            : 'Log in'),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(minHeight: 48),
                                  child: OutlinedButton(
                                    onPressed: _submitting
                                        ? null
                                        : widget.backend == null
                                            ? () => _notice(
                                                'Connect to your workspace to create an account.')
                                            : _switchMode,
                                    child: Text(_registering
                                        ? 'Back to login'
                                        : _role == UserRole.owner
                                            ? 'Register owner account'
                                            : 'Register provider account'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                          widget.backend == null
                              ? 'Offline workspace · Online sign-in unavailable'
                              : 'Your properties and cleaning services, together.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondaryLight)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryLight),
      );

  Widget _roleTile(UserRole role, IconData icon, String label) {
    final selected = _role == role;
    return Material(
      color: selected ? AppColors.primarySurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: selected ? AppColors.primaryLight : AppColors.borderLight,
            width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        onTap: () => _selectRole(role),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 14),
          child: Column(children: [
            Icon(icon,
                size: 21,
                color: selected
                    ? AppColors.primaryLight
                    : AppColors.textSecondaryLight),
            const SizedBox(height: 7),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondaryLight)),
          ]),
        ),
      ),
    );
  }
}
