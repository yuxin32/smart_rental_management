class Ddsu666GraphDemoSample {
  const Ddsu666GraphDemoSample({
    required this.voltageV,
    required this.powerW,
    required this.powerFactor,
    required this.frequencyHz,
  });

  final double voltageV;
  final double powerW;
  final double powerFactor;
  final double frequencyHz;

  double get currentA => powerW / (voltageV * powerFactor);
}

/// Fixed, reproducible measurements used in place of the physical DDSU666 and
/// ESP32 during the FYP demonstration. The application replays one sample every
/// 30 seconds through the same backend path intended for future physical data.
const ddsu666GraphDemoDataset = <Ddsu666GraphDemoSample>[
  Ddsu666GraphDemoSample(
    voltageV: 237.5,
    powerW: 420,
    powerFactor: 0.94,
    frequencyHz: 50.0,
  ),
  Ddsu666GraphDemoSample(
    voltageV: 237.9,
    powerW: 575,
    powerFactor: 0.95,
    frequencyHz: 50.0,
  ),
  Ddsu666GraphDemoSample(
    voltageV: 238.3,
    powerW: 760,
    powerFactor: 0.96,
    frequencyHz: 49.9,
  ),
  Ddsu666GraphDemoSample(
    voltageV: 238.7,
    powerW: 925,
    powerFactor: 0.94,
    frequencyHz: 50.1,
  ),
  Ddsu666GraphDemoSample(
    voltageV: 237.6,
    powerW: 810,
    powerFactor: 0.95,
    frequencyHz: 50.0,
  ),
  Ddsu666GraphDemoSample(
    voltageV: 238.0,
    powerW: 660,
    powerFactor: 0.96,
    frequencyHz: 50.0,
  ),
  Ddsu666GraphDemoSample(
    voltageV: 238.4,
    powerW: 1040,
    powerFactor: 0.94,
    frequencyHz: 49.9,
  ),
  Ddsu666GraphDemoSample(
    voltageV: 238.8,
    powerW: 1210,
    powerFactor: 0.95,
    frequencyHz: 50.1,
  ),
];
