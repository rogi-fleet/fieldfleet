class TimezoneOption {
  final String id;
  final String label;

  const TimezoneOption(this.id, this.label);
}

class TimezoneOptions {
  static const String defaultTimezone = 'UTC';

  static const List<TimezoneOption> common = [
    TimezoneOption('UTC', 'UTC'),
    TimezoneOption('America/New_York', 'America/New York (EST/EDT)'),
    TimezoneOption('America/Chicago', 'America/Chicago (CST/CDT)'),
    TimezoneOption('America/Denver', 'America/Denver (MST/MDT)'),
    TimezoneOption('America/Phoenix', 'America/Phoenix (MST)'),
    TimezoneOption('America/Los_Angeles', 'America/Los Angeles (PST/PDT)'),
    TimezoneOption('America/Anchorage', 'America/Anchorage (AKST/AKDT)'),
    TimezoneOption('Pacific/Honolulu', 'Pacific/Honolulu (HST)'),
    // Canada
    TimezoneOption('America/Toronto', 'America/Toronto (EST/EDT)'),
    TimezoneOption('America/Halifax', 'America/Halifax (AST/ADT)'),
    TimezoneOption('America/St_Johns', "America/St John's (NST/NDT)"),
    TimezoneOption('America/Winnipeg', 'America/Winnipeg (CST/CDT)'),
    TimezoneOption('America/Regina', 'America/Regina (CST)'),
    TimezoneOption('America/Edmonton', 'America/Edmonton (MST/MDT)'),
    TimezoneOption('America/Vancouver', 'America/Vancouver (PST/PDT)'),
    TimezoneOption('Europe/London', 'Europe/London (GMT/BST)'),
    TimezoneOption('Europe/Paris', 'Europe/Paris (CET/CEST)'),
    TimezoneOption('Asia/Tokyo', 'Asia/Tokyo (JST)'),
    TimezoneOption('Australia/Sydney', 'Australia/Sydney (AEST/AEDT)'),
  ];

  static bool isValid(String? timezone) {
    if (timezone == null || timezone.isEmpty) return false;
    return common.any((option) => option.id == timezone);
  }

  static String detectFromDevice() {
    final name = DateTime.now().timeZoneName.toUpperCase();
    final offset = DateTime.now().timeZoneOffset.inHours;

    const byName = {
      'UTC': 'UTC',
      'GMT': 'Europe/London',
      'BST': 'Europe/London',
      'EST': 'America/New_York',
      'EDT': 'America/New_York',
      'CST': 'America/Chicago',
      'CDT': 'America/Chicago',
      'MST': 'America/Denver',
      'MDT': 'America/Denver',
      'PST': 'America/Los_Angeles',
      'PDT': 'America/Los_Angeles',
      'AKST': 'America/Anchorage',
      'AKDT': 'America/Anchorage',
      'HST': 'Pacific/Honolulu',
      'JST': 'Asia/Tokyo',
      'CET': 'Europe/Paris',
      'CEST': 'Europe/Paris',
      'AEST': 'Australia/Sydney',
      'AEDT': 'Australia/Sydney',
    };

    final namedMatch = byName[name];
    if (namedMatch != null) {
      return namedMatch;
    }

    switch (offset) {
      case -10:
        return 'Pacific/Honolulu';
      case -9:
        return 'America/Anchorage';
      case -8:
        return 'America/Los_Angeles';
      case -7:
        return 'America/Denver';
      case -6:
        return 'America/Chicago';
      case -5:
        return 'America/New_York';
      case 0:
        return 'UTC';
      case 1:
        return 'Europe/Paris';
      case 9:
        return 'Asia/Tokyo';
      case 10:
        return 'Australia/Sydney';
      default:
        return defaultTimezone;
    }
  }
}
