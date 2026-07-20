/// List of countries for dropdown selection
class CountryList {
  /// Get list of countries with Canada and USA prioritized at the top
  static List<CountryOption> getCountries() {
    return [
      // Priority countries at the top
      CountryOption(name: 'Canada', code: 'CA'),
      CountryOption(name: 'United States', code: 'US'),
      
      // Divider (represented as a disabled option)
      CountryOption(name: '───────────────', code: '', isEnabled: false),
      
      // Other countries alphabetically
      CountryOption(name: 'Afghanistan', code: 'AF'),
      CountryOption(name: 'Albania', code: 'AL'),
      CountryOption(name: 'Algeria', code: 'DZ'),
      CountryOption(name: 'Argentina', code: 'AR'),
      CountryOption(name: 'Australia', code: 'AU'),
      CountryOption(name: 'Austria', code: 'AT'),
      CountryOption(name: 'Belgium', code: 'BE'),
      CountryOption(name: 'Brazil', code: 'BR'),
      CountryOption(name: 'Bulgaria', code: 'BG'),
      CountryOption(name: 'Chile', code: 'CL'),
      CountryOption(name: 'China', code: 'CN'),
      CountryOption(name: 'Colombia', code: 'CO'),
      CountryOption(name: 'Croatia', code: 'HR'),
      CountryOption(name: 'Czech Republic', code: 'CZ'),
      CountryOption(name: 'Denmark', code: 'DK'),
      CountryOption(name: 'Egypt', code: 'EG'),
      CountryOption(name: 'Finland', code: 'FI'),
      CountryOption(name: 'France', code: 'FR'),
      CountryOption(name: 'Germany', code: 'DE'),
      CountryOption(name: 'Greece', code: 'GR'),
      CountryOption(name: 'Hong Kong', code: 'HK'),
      CountryOption(name: 'Hungary', code: 'HU'),
      CountryOption(name: 'Iceland', code: 'IS'),
      CountryOption(name: 'India', code: 'IN'),
      CountryOption(name: 'Indonesia', code: 'ID'),
      CountryOption(name: 'Ireland', code: 'IE'),
      CountryOption(name: 'Israel', code: 'IL'),
      CountryOption(name: 'Italy', code: 'IT'),
      CountryOption(name: 'Japan', code: 'JP'),
      CountryOption(name: 'Malaysia', code: 'MY'),
      CountryOption(name: 'Mexico', code: 'MX'),
      CountryOption(name: 'Netherlands', code: 'NL'),
      CountryOption(name: 'New Zealand', code: 'NZ'),
      CountryOption(name: 'Norway', code: 'NO'),
      CountryOption(name: 'Pakistan', code: 'PK'),
      CountryOption(name: 'Philippines', code: 'PH'),
      CountryOption(name: 'Poland', code: 'PL'),
      CountryOption(name: 'Portugal', code: 'PT'),
      CountryOption(name: 'Romania', code: 'RO'),
      CountryOption(name: 'Russia', code: 'RU'),
      CountryOption(name: 'Saudi Arabia', code: 'SA'),
      CountryOption(name: 'Singapore', code: 'SG'),
      CountryOption(name: 'South Africa', code: 'ZA'),
      CountryOption(name: 'South Korea', code: 'KR'),
      CountryOption(name: 'Spain', code: 'ES'),
      CountryOption(name: 'Sweden', code: 'SE'),
      CountryOption(name: 'Switzerland', code: 'CH'),
      CountryOption(name: 'Taiwan', code: 'TW'),
      CountryOption(name: 'Thailand', code: 'TH'),
      CountryOption(name: 'Turkey', code: 'TR'),
      CountryOption(name: 'Ukraine', code: 'UA'),
      CountryOption(name: 'United Arab Emirates', code: 'AE'),
      CountryOption(name: 'United Kingdom', code: 'GB'),
      CountryOption(name: 'Vietnam', code: 'VN'),
    ];
  }

  /// Find a country ISO code by its name (e.g. 'United States' → 'US')
  static String? findCountryCodeByName(String name) {
    final lowerName = name.toLowerCase();
    for (final country in getCountries()) {
      if (country.isEnabled && country.name.toLowerCase() == lowerName) {
        return country.code;
      }
    }
    return null;
  }

  /// Find a country name by its ISO code (e.g. 'US' → 'United States')
  static String? findCountryNameByCode(String code) {
    final upperCode = code.toUpperCase();
    for (final country in getCountries()) {
      if (country.code == upperCode && country.isEnabled) {
        return country.name;
      }
    }
    return null;
  }

  /// Get the state/province label based on country
  static String getStateLabel(String? country) {
    if (country == null || country.isEmpty) {
      return 'State/Province';
    }

    switch (country) {
      case 'United States':
        return 'State';
      case 'Canada':
        return 'Province';
      default:
        return 'Province';
    }
  }

  /// Get the postal code label based on country
  static String getPostalCodeLabel(String? country) {
    if (country == null || country.isEmpty) {
      return 'ZIP/Postal Code';
    }
    
    switch (country) {
      case 'United States':
        return 'ZIP Code';
      case 'Canada':
        return 'Postal Code';
      default:
        return 'Postal Code';
    }
  }
}

/// Represents a country option in the dropdown
class CountryOption {
  final String name;
  final String code;
  final bool isEnabled;

  CountryOption({
    required this.name,
    required this.code,
    this.isEnabled = true,
  });
}
