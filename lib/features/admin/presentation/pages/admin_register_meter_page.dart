import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/meter_registration_service.dart';
import '../widgets/admin_ui.dart';

class AdminRegisterMeterPage extends StatefulWidget {
  const AdminRegisterMeterPage({super.key});

  @override
  State<AdminRegisterMeterPage> createState() => _AdminRegisterMeterPageState();
}

class _AdminRegisterMeterPageState extends State<AdminRegisterMeterPage> {
  final _formKey = GlobalKey<FormState>();
  final _deviceIdentifierController = TextEditingController();
  final _serialNumberController = TextEditingController();
  final _slaveAddressController = TextEditingController(text: '1');
  final _samplingIntervalController = TextEditingController(text: '300');
  final _calibrationFactorController = TextEditingController(text: '1.0');
  final _measurementToleranceController = TextEditingController(text: '0.02');
  final _initialKwhController = TextEditingController(text: '0.000');

  List<MeterUnitOption> _units = const [];
  String? _selectedUnitId;
  String? _selectedBuilding;
  DateTime _installationDate = DateTime.now();
  bool _loadingUnits = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  @override
  void dispose() {
    _deviceIdentifierController.dispose();
    _serialNumberController.dispose();
    _slaveAddressController.dispose();
    _samplingIntervalController.dispose();
    _calibrationFactorController.dispose();
    _measurementToleranceController.dispose();
    _initialKwhController.dispose();
    super.dispose();
  }

  Future<void> _loadUnits() async {
    setState(() {
      _loadingUnits = true;
      _loadError = null;
    });

    try {
      final units = await MeterRegistrationService.fetchAssignableUnits();
      if (!mounted) return;
      setState(() {
        _units = units;
        _selectedUnitId = units.length == 1 ? units.first.unitId : null;
        if (units.length == 1) {
          _selectedBuilding = units.first.location;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadError = 'Available rental units could not be loaded.';
        });
      }
    } finally {
      if (mounted) setState(() => _loadingUnits = false);
    }
  }

  Future<void> _selectInstallationDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _installationDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (selected != null && mounted) {
      setState(() => _installationDate = selected);
    }
  }

  Future<void> _registerMeter() async {
    if (!_formKey.currentState!.validate() || _selectedUnitId == null) return;

    setState(() => _saving = true);
    try {
      final deviceId = await MeterRegistrationService.registerSimulatedMeter(
        unitId: _selectedUnitId!,
        deviceIdentifier: _deviceIdentifierController.text,
        meterSerialNumber: _serialNumberController.text,
        modbusSlaveId: int.parse(_slaveAddressController.text),
        samplingIntervalSec: int.parse(_samplingIntervalController.text),
        calibrationFactor: double.parse(_calibrationFactorController.text),
        measurementTolerance: double.parse(
          _measurementToleranceController.text,
        ),
        initialCumulativeKwh: double.parse(_initialKwhController.text),
        installationDate: _installationDate,
      );

      if (mounted) Navigator.of(context).pop(deviceId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(_registrationErrorMessage(error))),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _registrationErrorMessage(Object error) {
    final message = error.toString().toLowerCase();
    if (error is PostgrestException &&
        (message.contains('duplicate') || message.contains('unique'))) {
      return 'The device identifier, serial number, or rental unit is already registered.';
    }
    if (message.contains('schema cache') ||
        message.contains('meter_serial_number')) {
      return 'The latest electricity-meter database update has not been applied yet.';
    }
    if (message.contains('session')) {
      return 'Your administrator session has expired. Please sign in again.';
    }
    return 'The meter could not be registered. Check the information and try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: const AdminBackAppBar(
        title: 'Register Meter',
        subtitle: 'Create a simulated DDSU666 meter',
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
          children: [
            _SimulationNotice(),
            const SizedBox(height: 18),
            _FormSection(
              title: 'Rental unit mapping',
              icon: Icons.home_work_outlined,
              child: _unitSelector(),
            ),
            const SizedBox(height: 16),
            _FormSection(
              title: 'Meter identity',
              icon: Icons.electric_meter_outlined,
              child: Column(
                children: [
                  _ReadOnlyField(
                    label: 'Meter model',
                    value: 'CHINT DDSU666 5(80)A 2P',
                    icon: Icons.memory_outlined,
                  ),
                  const SizedBox(height: 13),
                  TextFormField(
                    controller: _deviceIdentifierController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _inputDecoration(
                      label: 'Device identifier',
                      hint: 'DDS-A1208-01',
                      icon: Icons.badge_outlined,
                    ),
                    validator: (value) {
                      final normalized = value?.trim() ?? '';
                      if (normalized.isEmpty) {
                        return 'Enter a unique device identifier.';
                      }
                      if (!RegExp(
                        r'^[A-Za-z0-9_-]{3,64}$',
                      ).hasMatch(normalized)) {
                        return 'Use 3–64 letters, numbers, hyphens or underscores.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 13),
                  TextFormField(
                    controller: _serialNumberController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _inputDecoration(
                      label: 'Meter serial number',
                      hint: 'Enter the meter serial number',
                      icon: Icons.numbers_rounded,
                    ),
                    validator: (value) {
                      final normalized = value?.trim() ?? '';
                      if (normalized.isEmpty) {
                        return 'Enter the meter serial number.';
                      }
                      if (normalized.length > 80) {
                        return 'The serial number cannot exceed 80 characters.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 13),
                  InkWell(
                    onTap: _selectInstallationDate,
                    borderRadius: BorderRadius.circular(14),
                    child: InputDecorator(
                      decoration: _inputDecoration(
                        label: 'Installation date',
                        icon: Icons.calendar_today_outlined,
                      ),
                      child: Text(
                        _formatDate(_installationDate),
                        style: const TextStyle(
                          color: AppColors.heading,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _FormSection(
              title: 'Reading collection',
              icon: Icons.settings_ethernet_outlined,
              child: Column(
                children: [
                  _ReadOnlyField(
                    label: 'Communication',
                    value: 'RS485 Modbus-RTU',
                    icon: Icons.cable_outlined,
                  ),
                  const SizedBox(height: 13),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _slaveAddressController,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration(
                            label: 'Modbus address',
                            icon: Icons.pin_outlined,
                          ),
                          validator: (value) {
                            final address = int.tryParse(value ?? '');
                            if (address == null ||
                                address < 1 ||
                                address > 247) {
                              return 'Use 1–247.';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _samplingIntervalController,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration(
                            label: 'Interval (sec)',
                            icon: Icons.schedule_outlined,
                          ),
                          validator: (value) {
                            final seconds = int.tryParse(value ?? '');
                            if (seconds == null ||
                                seconds < 60 ||
                                seconds > 86400) {
                              return 'Use 60–86400.';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _calibrationFactorController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _inputDecoration(
                            label: 'Calibration factor',
                            icon: Icons.tune_rounded,
                          ),
                          validator: _positiveNumberValidator,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _measurementToleranceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _inputDecoration(
                            label: 'Tolerance',
                            icon: Icons.rule_outlined,
                          ),
                          validator: (value) {
                            final tolerance = double.tryParse(value ?? '');
                            if (tolerance == null ||
                                tolerance < 0 ||
                                tolerance > 1) {
                              return 'Use 0–1.';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  TextFormField(
                    controller: _initialKwhController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _inputDecoration(
                      label: 'Initial cumulative reading (kWh)',
                      hint: '0.000',
                      icon: Icons.bolt_outlined,
                    ),
                    validator: (value) {
                      final reading = double.tryParse(value ?? '');
                      if (reading == null || reading < 0) {
                        return 'Enter a value of 0 or above.';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving || _loadingUnits || _units.isEmpty
                    ? null
                    : _registerMeter,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_circle_outline_rounded),
                label: Text(_saving ? 'Registering...' : 'Register meter'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFB7C0E8),
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unitSelector() {
    if (_loadingUnits) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Column(
        children: [
          Text(
            _loadError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.body),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _loadUnits,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      );
    }

    if (_units.isEmpty) {
      return const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFE8953E)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No eligible unit is available. A unit with a pending, active, or offline meter cannot receive another meter.',
              style: TextStyle(color: AppColors.body, height: 1.4),
            ),
          ),
        ],
      );
    }

    final buildings = _units.map((u) => u.location ?? '').toSet().toList()
      ..sort();
    final building = buildings.contains(_selectedBuilding)
        ? _selectedBuilding
        : null;
    final buildingUnits = _units
        .where((u) => (u.location ?? '') == building)
        .toList();
    final selectedUnitId = buildingUnits.any((u) => u.unitId == _selectedUnitId)
        ? _selectedUnitId
        : null;

    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: building,
          isExpanded: true,
          decoration: _inputDecoration(
            label: '1. Choose building / apartment',
            icon: Icons.apartment_outlined,
          ),
          items: buildings
              .map((name) => DropdownMenuItem(value: name, child: Text(name)))
              .toList(),
          onChanged: (value) => setState(() {
            _selectedBuilding = value;
            _selectedUnitId = null;
          }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(building),
          initialValue: selectedUnitId,
          isExpanded: true,
          decoration: _inputDecoration(
            label: '2. Choose unit number',
            icon: Icons.meeting_room_outlined,
          ),
          items: buildingUnits
              .map(
                (unit) => DropdownMenuItem(
                  value: unit.unitId,
                  child: Text(unit.unitNumber),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _selectedUnitId = value),
          validator: (value) => value == null ? 'Select a rental unit.' : null,
        ),
      ],
    );
  }

  String? _positiveNumberValidator(String? value) {
    final number = double.tryParse(value ?? '');
    if (number == null || number <= 0) return 'Use a value above 0.';
    return null;
  }
}

class _SimulationNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AdminCard(
      color: const Color(0xFFF0F5FF),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminIconBox(
            icon: Icons.science_outlined,
            color: AppColors.primary,
            backgroundColor: Colors.white,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Simulation mode',
                        style: TextStyle(
                          color: AppColors.heading,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    AdminStatusPill(
                      label: 'Simulated',
                      foregroundColor: AppColors.primary,
                      backgroundColor: Colors.white,
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  'This meter will receive test readings from a dataset through the same backend validation process used by a physical ESP32.',
                  style: TextStyle(
                    color: Color(0xFF5D75B4),
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

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AdminIconBox(icon: icon, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.heading,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: _inputDecoration(label: label, icon: icon),
      child: Text(
        value,
        style: const TextStyle(
          color: AppColors.heading,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration({
  required String label,
  required IconData icon,
  String? hint,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon, color: AppColors.primary, size: 21),
    filled: true,
    fillColor: const Color(0xFFF9FAFD),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE0E4EB)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE0E4EB)),
    ),
  );
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
