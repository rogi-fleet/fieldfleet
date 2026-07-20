/// Static tax rate lookup by US state or country.
/// Rates are approximate averages and should be verified by the user.
class TaxRateLookup {
  TaxRateLookup._();

  /// Suggests a tax rate and name from state/country codes.
  /// Tries US state first, then falls back to country.
  static ({String name, double rate})? suggest({
    String? state,
    String? country,
  }) {
    if (state != null && state.isNotEmpty) {
      final code = _toRegionCode(state);
      // US state and Canadian province codes are disjoint, so order is safe.
      final result = forUsState(code) ?? forCanadianProvince(code);
      if (result != null) return result;
    }
    if (country != null && country.isNotEmpty) {
      return forCountry(_toCountryCode(country));
    }
    return null;
  }

  /// Maps full state/province names ("Ontario", "California") to their
  /// two-letter codes — geocoders like Nominatim return full names. Codes
  /// pass through unchanged.
  static String _toRegionCode(String raw) {
    final normalized = raw.trim().toUpperCase();
    return _regionNameToCode[normalized] ?? normalized;
  }

  /// Maps full country names ("Canada") to ISO codes; codes pass through.
  static String _toCountryCode(String raw) {
    final normalized = raw.trim().toUpperCase();
    return _countryNameToCode[normalized] ?? normalized;
  }

  /// Returns the suggested tax for a Canadian province/territory code (e.g.
  /// "ON", "BC"). HST provinces return the single combined rate; GST+PST/QST
  /// provinces return the combined rate; territories return GST only. Without
  /// this, Canadian companies fell back to the country's bare 5% GST (or 0%),
  /// under-charging tax (e.g. Ontario HST is 13%).
  static ({String name, double rate})? forCanadianProvince(
    String provinceCode,
  ) {
    final code = provinceCode.trim().toUpperCase();
    return _caProvinceTaxRates[code];
  }

  /// Returns suggested tax rate for a US state code (e.g. "CA", "TX").
  static ({String name, double rate})? forUsState(String stateCode) {
    final code = stateCode.trim().toUpperCase();
    final rate = _usStateTaxRates[code];
    if (rate == null) return null;
    return (name: 'Sales Tax', rate: rate);
  }

  /// Returns suggested tax rate for a country code (e.g. "US", "GB", "AU").
  static ({String name, double rate})? forCountry(String countryCode) {
    final code = countryCode.trim().toUpperCase();
    final entry = _countryTaxRates[code];
    if (entry == null) return null;
    return entry;
  }

  // Average combined state + local sales tax rates (approximate)
  static const _usStateTaxRates = <String, double>{
    'AL': 9.24,
    'AK': 1.76,
    'AZ': 8.40,
    'AR': 9.47,
    'CA': 8.68,
    'CO': 7.77,
    'CT': 6.35,
    'DE': 0.0,
    'FL': 7.02,
    'GA': 7.35,
    'HI': 4.44,
    'ID': 6.02,
    'IL': 8.82,
    'IN': 7.0,
    'IA': 6.94,
    'KS': 8.70,
    'KY': 6.0,
    'LA': 9.55,
    'ME': 5.5,
    'MD': 6.0,
    'MA': 6.25,
    'MI': 6.0,
    'MN': 7.49,
    'MS': 7.07,
    'MO': 8.29,
    'MT': 0.0,
    'NE': 6.94,
    'NV': 8.23,
    'NH': 0.0,
    'NJ': 6.63,
    'NM': 7.72,
    'NY': 8.52,
    'NC': 6.98,
    'ND': 6.96,
    'OH': 7.24,
    'OK': 8.98,
    'OR': 0.0,
    'PA': 6.34,
    'RI': 7.0,
    'SC': 7.44,
    'SD': 6.40,
    'TN': 9.55,
    'TX': 8.20,
    'UT': 7.19,
    'VT': 6.24,
    'VA': 5.75,
    'WA': 9.29,
    'WV': 6.50,
    'WI': 5.43,
    'WY': 5.36,
    'DC': 6.0,
  };

  // Canadian provinces/territories. HST provinces combine GST+PST into one
  // rate; GST+PST/QST provinces show the combined total; territories are GST
  // only. Approximate; the user can adjust.
  static const _regionNameToCode = <String, String>{
    // Canadian provinces / territories
    'ONTARIO': 'ON',
    'QUEBEC': 'QC',
    'QUÉBEC': 'QC',
    'NOVA SCOTIA': 'NS',
    'NEW BRUNSWICK': 'NB',
    'PRINCE EDWARD ISLAND': 'PE',
    'NEWFOUNDLAND AND LABRADOR': 'NL',
    'MANITOBA': 'MB',
    'SASKATCHEWAN': 'SK',
    'ALBERTA': 'AB',
    'BRITISH COLUMBIA': 'BC',
    'YUKON': 'YT',
    'NORTHWEST TERRITORIES': 'NT',
    'NUNAVUT': 'NU',
    // US states
    'ALABAMA': 'AL',
    'ALASKA': 'AK',
    'ARIZONA': 'AZ',
    'ARKANSAS': 'AR',
    'CALIFORNIA': 'CA',
    'COLORADO': 'CO',
    'CONNECTICUT': 'CT',
    'DELAWARE': 'DE',
    'FLORIDA': 'FL',
    'GEORGIA': 'GA',
    'HAWAII': 'HI',
    'IDAHO': 'ID',
    'ILLINOIS': 'IL',
    'INDIANA': 'IN',
    'IOWA': 'IA',
    'KANSAS': 'KS',
    'KENTUCKY': 'KY',
    'LOUISIANA': 'LA',
    'MAINE': 'ME',
    'MARYLAND': 'MD',
    'MASSACHUSETTS': 'MA',
    'MICHIGAN': 'MI',
    'MINNESOTA': 'MN',
    'MISSISSIPPI': 'MS',
    'MISSOURI': 'MO',
    'MONTANA': 'MT',
    'NEBRASKA': 'NE',
    'NEVADA': 'NV',
    'NEW HAMPSHIRE': 'NH',
    'NEW JERSEY': 'NJ',
    'NEW MEXICO': 'NM',
    'NEW YORK': 'NY',
    'NORTH CAROLINA': 'NC',
    'NORTH DAKOTA': 'ND',
    'OHIO': 'OH',
    'OKLAHOMA': 'OK',
    'OREGON': 'OR',
    'PENNSYLVANIA': 'PA',
    'RHODE ISLAND': 'RI',
    'SOUTH CAROLINA': 'SC',
    'SOUTH DAKOTA': 'SD',
    'TENNESSEE': 'TN',
    'TEXAS': 'TX',
    'UTAH': 'UT',
    'VERMONT': 'VT',
    'VIRGINIA': 'VA',
    'WASHINGTON': 'WA',
    'WEST VIRGINIA': 'WV',
    'WISCONSIN': 'WI',
    'WYOMING': 'WY',
    'DISTRICT OF COLUMBIA': 'DC',
  };

  static const _countryNameToCode = <String, String>{
    'UNITED STATES': 'US',
    'UNITED STATES OF AMERICA': 'US',
    'CANADA': 'CA',
    'UNITED KINGDOM': 'GB',
    'GERMANY': 'DE',
    'FRANCE': 'FR',
    'ITALY': 'IT',
    'SPAIN': 'ES',
    'NETHERLANDS': 'NL',
    'BELGIUM': 'BE',
    'AUSTRIA': 'AT',
    'SWEDEN': 'SE',
    'DENMARK': 'DK',
    'FINLAND': 'FI',
    'NORWAY': 'NO',
    'PORTUGAL': 'PT',
    'IRELAND': 'IE',
    'POLAND': 'PL',
    'CZECHIA': 'CZ',
    'CZECH REPUBLIC': 'CZ',
    'ROMANIA': 'RO',
    'HUNGARY': 'HU',
    'GREECE': 'GR',
    'SWITZERLAND': 'CH',
    'AUSTRALIA': 'AU',
    'NEW ZEALAND': 'NZ',
    'INDIA': 'IN',
    'SINGAPORE': 'SG',
    'MALAYSIA': 'MY',
    'JAPAN': 'JP',
    'SOUTH KOREA': 'KR',
    'BRAZIL': 'BR',
    'MEXICO': 'MX',
    'SOUTH AFRICA': 'ZA',
    'UNITED ARAB EMIRATES': 'AE',
    'SAUDI ARABIA': 'SA',
    'ISRAEL': 'IL',
    'PHILIPPINES': 'PH',
    'THAILAND': 'TH',
  };

  static const _caProvinceTaxRates = <String, ({String name, double rate})>{
    'ON': (name: 'HST', rate: 13.0),
    'NB': (name: 'HST', rate: 15.0),
    'NL': (name: 'HST', rate: 15.0),
    'NS': (name: 'HST', rate: 14.0),
    'PE': (name: 'HST', rate: 15.0),
    'BC': (name: 'GST + PST', rate: 12.0),
    'SK': (name: 'GST + PST', rate: 11.0),
    'MB': (name: 'GST + PST', rate: 12.0),
    'QC': (name: 'GST + QST', rate: 14.975),
    'AB': (name: 'GST', rate: 5.0),
    'NT': (name: 'GST', rate: 5.0),
    'NU': (name: 'GST', rate: 5.0),
    'YT': (name: 'GST', rate: 5.0),
  };

  static const _countryTaxRates = <String, ({String name, double rate})>{
    // VAT countries
    'GB': (name: 'VAT', rate: 20.0),
    'DE': (name: 'VAT', rate: 19.0),
    'FR': (name: 'VAT', rate: 20.0),
    'IT': (name: 'VAT', rate: 22.0),
    'ES': (name: 'VAT', rate: 21.0),
    'NL': (name: 'VAT', rate: 21.0),
    'BE': (name: 'VAT', rate: 21.0),
    'AT': (name: 'VAT', rate: 20.0),
    'SE': (name: 'VAT', rate: 25.0),
    'DK': (name: 'VAT', rate: 25.0),
    'FI': (name: 'VAT', rate: 25.5),
    'NO': (name: 'VAT', rate: 25.0),
    'PT': (name: 'VAT', rate: 23.0),
    'IE': (name: 'VAT', rate: 23.0),
    'PL': (name: 'VAT', rate: 23.0),
    'CZ': (name: 'VAT', rate: 21.0),
    'RO': (name: 'VAT', rate: 19.0),
    'HU': (name: 'VAT', rate: 27.0),
    'GR': (name: 'VAT', rate: 24.0),
    'CH': (name: 'VAT', rate: 8.1),
    // GST countries
    'AU': (name: 'GST', rate: 10.0),
    'NZ': (name: 'GST', rate: 15.0),
    'CA': (name: 'GST', rate: 5.0),
    'IN': (name: 'GST', rate: 18.0),
    'SG': (name: 'GST', rate: 9.0),
    'MY': (name: 'SST', rate: 8.0),
    // Sales Tax
    'US': (name: 'Sales Tax', rate: 7.0),
    'JP': (name: 'Consumption Tax', rate: 10.0),
    'KR': (name: 'VAT', rate: 10.0),
    'BR': (name: 'ICMS', rate: 18.0),
    'MX': (name: 'IVA', rate: 16.0),
    'ZA': (name: 'VAT', rate: 15.0),
    'AE': (name: 'VAT', rate: 5.0),
    'SA': (name: 'VAT', rate: 15.0),
    'IL': (name: 'VAT', rate: 17.0),
    'PH': (name: 'VAT', rate: 12.0),
    'TH': (name: 'VAT', rate: 7.0),
  };
}
