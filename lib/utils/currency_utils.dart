import 'package:intl/intl.dart';

/// Represents a currency option for dropdown selection
class CurrencyOption {
  final String code;   // ISO 4217 code: USD, CAD, EUR, GBP, AUD
  final String name;   // Full name: "US Dollar", "Canadian Dollar"
  final String symbol; // Currency symbol: $, CA$, £, €, A$

  const CurrencyOption({
    required this.code,
    required this.name,
    required this.symbol,
  });
}

/// Utility class for currency-related operations
class CurrencyUtils {
  /// Get list of supported currencies with priority currencies first
  static List<CurrencyOption> getCurrencies() {
    return const [
      // Priority currencies at the top
      CurrencyOption(code: 'USD', name: 'US Dollar', symbol: '\$'),
      CurrencyOption(code: 'CAD', name: 'Canadian Dollar', symbol: '\$'),
      CurrencyOption(code: 'GBP', name: 'British Pound', symbol: '£'),
      CurrencyOption(code: 'EUR', name: 'Euro', symbol: '€'),
      CurrencyOption(code: 'AUD', name: 'Australian Dollar', symbol: 'A\$'),

      // Other currencies alphabetically by code
      CurrencyOption(code: 'CHF', name: 'Swiss Franc', symbol: 'CHF'),
      CurrencyOption(code: 'CNY', name: 'Chinese Yuan', symbol: '¥'),
      CurrencyOption(code: 'DKK', name: 'Danish Krone', symbol: 'kr'),
      CurrencyOption(code: 'HKD', name: 'Hong Kong Dollar', symbol: 'HK\$'),
      CurrencyOption(code: 'INR', name: 'Indian Rupee', symbol: '₹'),
      CurrencyOption(code: 'JPY', name: 'Japanese Yen', symbol: '¥'),
      CurrencyOption(code: 'MXN', name: 'Mexican Peso', symbol: 'MX\$'),
      CurrencyOption(code: 'NOK', name: 'Norwegian Krone', symbol: 'kr'),
      CurrencyOption(code: 'NZD', name: 'New Zealand Dollar', symbol: 'NZ\$'),
      CurrencyOption(code: 'SEK', name: 'Swedish Krona', symbol: 'kr'),
      CurrencyOption(code: 'SGD', name: 'Singapore Dollar', symbol: 'S\$'),
      CurrencyOption(code: 'ZAR', name: 'South African Rand', symbol: 'R'),
    ];
  }

  /// Get the default currency code for a given country name
  static String getDefaultCurrencyForCountry(String? country) {
    if (country == null || country.isEmpty) {
      return 'USD';
    }

    // Map country names to currency codes
    const countryToCurrency = {
      // North America
      'United States': 'USD',
      'Canada': 'CAD',
      'Mexico': 'MXN',

      // Europe - GBP
      'United Kingdom': 'GBP',

      // Europe - EUR
      'Germany': 'EUR',
      'France': 'EUR',
      'Italy': 'EUR',
      'Spain': 'EUR',
      'Netherlands': 'EUR',
      'Belgium': 'EUR',
      'Austria': 'EUR',
      'Ireland': 'EUR',
      'Portugal': 'EUR',
      'Finland': 'EUR',
      'Greece': 'EUR',

      // Europe - Other
      'Switzerland': 'CHF',
      'Norway': 'NOK',
      'Sweden': 'SEK',
      'Denmark': 'DKK',
      'Poland': 'PLN',
      'Czech Republic': 'CZK',
      'Hungary': 'HUF',
      'Romania': 'RON',
      'Bulgaria': 'BGN',
      'Croatia': 'EUR',
      'Iceland': 'ISK',

      // Asia-Pacific
      'Australia': 'AUD',
      'New Zealand': 'NZD',
      'Japan': 'JPY',
      'China': 'CNY',
      'Hong Kong': 'HKD',
      'Singapore': 'SGD',
      'South Korea': 'KRW',
      'India': 'INR',
      'Thailand': 'THB',
      'Malaysia': 'MYR',
      'Indonesia': 'IDR',
      'Philippines': 'PHP',
      'Vietnam': 'VND',
      'Taiwan': 'TWD',
      'Pakistan': 'PKR',

      // Middle East
      'United Arab Emirates': 'AED',
      'Saudi Arabia': 'SAR',
      'Israel': 'ILS',
      'Turkey': 'TRY',

      // Africa
      'South Africa': 'ZAR',
      'Egypt': 'EGP',

      // South America
      'Brazil': 'BRL',
      'Argentina': 'ARS',
      'Chile': 'CLP',
      'Colombia': 'COP',

      // Other
      'Russia': 'RUB',
      'Ukraine': 'UAH',
    };

    return countryToCurrency[country] ?? 'USD';
  }

  /// Get the currency symbol for a given currency code
  static String getSymbol(String currencyCode) {
    final currencies = getCurrencies();
    final currency = currencies.firstWhere(
      (c) => c.code == currencyCode,
      orElse: () => const CurrencyOption(code: 'USD', name: 'US Dollar', symbol: '\$'),
    );
    return currency.symbol;
  }

  /// Get a CurrencyOption by code
  static CurrencyOption? getCurrencyByCode(String currencyCode) {
    final currencies = getCurrencies();
    try {
      return currencies.firstWhere((c) => c.code == currencyCode);
    } catch (_) {
      return null;
    }
  }

  /// Format a currency amount with the appropriate symbol and formatting
  static String formatCurrency(double amount, String currencyCode) {
    final symbol = getSymbol(currencyCode);

    // Use NumberFormat for proper formatting
    final formatter = NumberFormat.currency(
      symbol: symbol,
      decimalDigits: 2,
    );

    return formatter.format(amount);
  }

  /// Get a NumberFormat instance for the given currency
  static NumberFormat getFormatter(String currencyCode) {
    final symbol = getSymbol(currencyCode);
    return NumberFormat.currency(
      symbol: symbol,
      decimalDigits: 2,
    );
  }

  /// Format currency without decimals (for display of whole numbers)
  static String formatCurrencyCompact(double amount, String currencyCode) {
    final symbol = getSymbol(currencyCode);

    if (amount >= 1000000) {
      return '$symbol${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '$symbol${(amount / 1000).toStringAsFixed(1)}K';
    }

    return '$symbol${amount.toStringAsFixed(0)}';
  }
}
