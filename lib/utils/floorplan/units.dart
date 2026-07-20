// Unit conversion + formatting helpers for the floorplan editor.
//
// Internal scene coordinates are always in the scene's stored unit
// (default `cm`). The active *display* unit comes from `Scene.unit` and
// is what the painter labels and inspector text fields show.
//
// Keeping internal coords in one unit and converting only at the
// display/input boundary means switching units never mutates the model.

const Set<String> kSupportedUnits = {'mm', 'cm', 'm', 'ft', 'in'};

/// Conversion factor: 1 cm = factor × `unit`. So to convert a value from
/// cm to [unit]: `valueCm * cmToUnit(unit)`.
double cmToUnit(String unit) => switch (unit) {
      'mm' => 10.0,
      'cm' => 1.0,
      'm' => 0.01,
      'ft' => 1 / 30.48,
      'in' => 1 / 2.54,
      _ => 1.0,
    };

double unitToCm(String unit) => 1.0 / cmToUnit(unit);

/// Convert a value stored in cm into [unit].
double convertFromCm(double valueCm, String unit) =>
    valueCm * cmToUnit(unit);

/// Convert a user-typed value in [unit] back into cm.
double convertToCm(double valueInUnit, String unit) =>
    valueInUnit * unitToCm(unit);

/// Render [valueCm] for display in [unit] with a sensible number of
/// decimals — fewer for big units, more for small ones.
String formatLengthCm(double valueCm, String unit) {
  final v = convertFromCm(valueCm, unit);
  final decimals = switch (unit) {
    'mm' => 0,
    'cm' => 0,
    'm' => 2,
    'ft' => 2,
    'in' => 1,
    _ => 0,
  };
  return '${v.toStringAsFixed(decimals)} $unit';
}

/// Render an area stored in cm² for display. Picks `m²` for SI-family
/// scene units (`mm`, `cm`, `m`) and `sq ft` for imperial — using `cm²`
/// or `mm²` directly would print numbers nobody wants to read for room-
/// sized areas (a small bedroom is 80 000 cm²).
String formatAreaCm2(double valueCm2, String unit) {
  final isImperial = unit == 'ft' || unit == 'in';
  if (isImperial) {
    // 1 cm² = 0.001076391 sq ft
    final sqFt = valueCm2 * 0.001076391;
    return '${sqFt.toStringAsFixed(1)} sq ft';
  }
  final m2 = valueCm2 / 10000.0;
  return '${m2.toStringAsFixed(2)} m²';
}

/// Parse a user-typed length string in [unit]. Accepts plain numbers
/// ("5"), explicit unit suffixes ("5m", "12 ft"), and stripped chars.
/// Returns null on a value that doesn't parse.
double? parseLengthToCm(String input, String defaultUnit) {
  final trimmed = input.trim().toLowerCase();
  if (trimmed.isEmpty) return null;
  // Detect explicit unit suffix.
  String unit = defaultUnit;
  String numberPart = trimmed;
  for (final u in kSupportedUnits) {
    if (trimmed.endsWith(u)) {
      unit = u;
      numberPart = trimmed.substring(0, trimmed.length - u.length).trim();
      break;
    }
  }
  final n = double.tryParse(numberPart);
  if (n == null || n.isNaN || n.isInfinite) return null;
  if (n < 0) return null;
  return convertToCm(n, unit);
}
