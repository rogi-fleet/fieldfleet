/// Lenient parsers for values coming off the Supabase wire, where numeric
/// and date columns can arrive as num, String, or null depending on the
/// select shape.
double parseNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

DateTime? parseDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

String dateOnly(DateTime d) => d.toIso8601String().substring(0, 10);
