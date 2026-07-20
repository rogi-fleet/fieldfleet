import 'dart:async';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../config/supabase_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chrome_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../models/workspace.dart';
import '../../models/company_type.dart';
import '../../models/user_role.dart';
import '../../models/workspace_role_template.dart';
import '../../services/service_locator.dart';
import '../../services/geocoding_service.dart';
import '../../services/supabase/invitation_service.dart';
import '../../theme/theme.dart';
import '../../utils/currency_utils.dart';
import '../../utils/project_terminology.dart';
import '../../utils/app_logger.dart';
import '../../utils/tax_rate_lookup.dart';
import '../../utils/timezone_options.dart';
import '../../widgets/project_form_popup.dart';
import '../../widgets/ai_persona_picker.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

/// Onboarding's hero brand blue — used across the dark hero panels and
/// gradients. Deliberately not in AppColors: it's unique to this screen's
/// marketing-style chrome.
const _onboardingBlue = Color(0xFF0D4F8B);

/// Available goals for onboarding selection
class OnboardingGoal {
  final String id;
  final String title;
  final String description;
  final IconData icon;

  const OnboardingGoal({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
  });
}

List<OnboardingGoal> availableGoals([String singularTerminology = 'project']) {
  return [
    OnboardingGoal(
      id: 'scheduling',
      title: 'Scheduling',
      description:
          'Plan and track ${singularTerminology.toLowerCase()} timelines',
      icon: Icons.calendar_month_outlined,
    ),
    const OnboardingGoal(
      id: 'budgets',
      title: 'Budget Tracking',
      description: 'Monitor costs and profitability',
      icon: Icons.attach_money_outlined,
    ),
    const OnboardingGoal(
      id: 'team',
      title: 'Team Management',
      description: 'Coordinate your crew and tasks',
      icon: Icons.groups_outlined,
    ),
    const OnboardingGoal(
      id: 'customers',
      title: 'Customer Communication',
      description: 'Keep customers informed on progress',
      icon: Icons.chat_outlined,
    ),
    const OnboardingGoal(
      id: 'time',
      title: 'Time Tracking',
      description: 'Track hours and labor costs',
      icon: Icons.access_time_outlined,
    ),
    const OnboardingGoal(
      id: 'documents',
      title: 'Document Management',
      description: 'Store plans, photos, and files',
      icon: Icons.folder_outlined,
    ),
  ];
}

/// Team invite entry for onboarding
class _TeamInviteEntry {
  String email = '';
  UserRole role = UserRole.fieldTechnician;
}

class _ParsedAddress {
  final String? city;
  final String? state;
  final String? zipCode;
  final String? country;

  const _ParsedAddress({this.city, this.state, this.zipCode, this.country});
}

class OnboardingScreen extends StatefulWidget {
  /// When true, creates a new workspace instead of updating the existing one.
  final bool isNewWorkspace;

  const OnboardingScreen({super.key, this.isNewWorkspace = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = false;

  // Total steps: 0-8 (9 steps)
  static const int _totalSteps = 9;

  // Step 1: Company name (welcome)
  final _companyNameController = TextEditingController();
  final _startingSerialNumberController = TextEditingController();

  // Step 2: Goals (moved early for AI processing)
  final Set<String> _selectedGoals = {};

  // Step 3: Company type + project terminology
  CompanyType _selectedCompanyType = CompanyType.restoration;
  final _projectTerminologyController = TextEditingController();

  // Step 4: Business location + timezone + currency
  final _businessAddressController = TextEditingController();
  final GeocodingService _geocodingService = GeocodingService();
  Timer? _addressSuggestionDebounce;
  List<AddressSuggestion> _addressSuggestions = const [];
  bool _isLoadingAddressSuggestions = false;
  bool _isSettingAddressFromSuggestion = false;
  String _selectedTimezone = TimezoneOptions.detectFromDevice();
  String _selectedCurrencyCode = 'USD';

  // Tax suggestion (shown for confirmation, not silently applied)
  ({String name, double rate})? _taxSuggestion;

  // Step 5: Team size
  TeamSize? _selectedTeamSize;

  // Step 5: AI Persona (optional)
  final _aiPersonaNameController = TextEditingController();
  String _aiPersonaAvatar = 'hard_hat';
  String _aiPersonaStyle = 'mentor';

  // Company logo upload (optional, shown in welcome step)
  Uint8List? _logoBytes;
  String? _logoFileName;

  // Step 7: Invite team (optional)
  final List<_TeamInviteEntry> _teamInvites = [_TeamInviteEntry()];

  // Step 8: Create project (optional) - handled via popup

  @override
  void initState() {
    super.initState();
    _businessAddressController.addListener(_onBusinessAddressChanged);
    // Pre-fill project terminology from the default company type
    _projectTerminologyController.text =
        _selectedCompanyType.defaultProjectTerminology;
    _loadExistingData();
  }

  Future<void> _loadExistingData() async {
    final authProvider = context.read<AuthProvider>();

    // Refresh user to ensure we have the latest workspace ID
    await authProvider.refreshUser();

    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId != null && workspaceId.isNotEmpty) {
      final data =
          await ServiceLocator.workspaceService.getWorkspace(workspaceId).first;

      if (data != null && mounted) {
        if (widget.isNewWorkspace) {
          // For new workspace, only pre-fill timezone and location from current workspace
          setState(() {
            final timezone = data['timezone'] as String?;
            if (TimezoneOptions.isValid(timezone)) {
              _selectedTimezone = timezone!;
            }
            final address = data['companyAddress'] as String?;
            if (address != null && address.trim().isNotEmpty) {
              _businessAddressController.text = address;
            }
          });
        } else {
          setState(() {
            _companyNameController.text = data['name'] ?? '';
            if (data['companyType'] != null) {
              _selectedCompanyType = CompanyType.fromString(
                data['companyType'],
              );
            }
            final address = data['companyAddress'] as String?;
            if (address != null && address.trim().isNotEmpty) {
              _businessAddressController.text = address;
            }
            final timezone = data['timezone'] as String?;
            if (TimezoneOptions.isValid(timezone)) {
              _selectedTimezone = timezone!;
            }
            final startingSerial = data['startingProjectSerialNumber'];
            if (startingSerial != null) {
              _startingSerialNumberController.text = startingSerial.toString();
            }
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _companyNameController.dispose();
    _startingSerialNumberController.dispose();
    _projectTerminologyController.dispose();
    _addressSuggestionDebounce?.cancel();
    _businessAddressController.removeListener(_onBusinessAddressChanged);
    _businessAddressController.dispose();
    _aiPersonaNameController.dispose();
    super.dispose();
  }

  void _onBusinessAddressChanged() {
    if (_isSettingAddressFromSuggestion) return;
    final query = _businessAddressController.text.trim();
    _addressSuggestionDebounce?.cancel();

    if (query.length < 3) {
      if (_addressSuggestions.isNotEmpty || _isLoadingAddressSuggestions) {
        setState(() {
          _addressSuggestions = const [];
          _isLoadingAddressSuggestions = false;
        });
      }
      _applyTimezoneFromAddressText(query);
      return;
    }

    _addressSuggestionDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchAddressSuggestions(query);
    });
    _applyTimezoneFromAddressText(query);
  }

  Future<void> _fetchAddressSuggestions(String query) async {
    if (!mounted) return;
    setState(() => _isLoadingAddressSuggestions = true);

    final suggestions = await _geocodingService.searchAddressSuggestions(query);
    if (!mounted) return;

    if (_businessAddressController.text.trim() != query) {
      setState(() => _isLoadingAddressSuggestions = false);
      return;
    }

    setState(() {
      _addressSuggestions = suggestions;
      _isLoadingAddressSuggestions = false;
    });
  }

  void _selectAddressSuggestion(AddressSuggestion suggestion) {
    _isSettingAddressFromSuggestion = true;
    final typedQuery = _businessAddressController.text.trim();
    _businessAddressController.text = suggestion.singleLineAddress(
      typedQuery: typedQuery,
    );
    _businessAddressController.selection = TextSelection.fromPosition(
      TextPosition(offset: _businessAddressController.text.length),
    );
    // Use country/state from the API suggestion directly — the condensed
    // address text strips the country, so re-parsing it loses that info.
    final country = suggestion.country;
    final state = suggestion.state;
    setState(() {
      _addressSuggestions = const [];
      _isLoadingAddressSuggestions = false;
      // Auto-suggest currency from country
      if (country != null) {
        _selectedCurrencyCode = CurrencyUtils.getDefaultCurrencyForCountry(
          country,
        );
      }
      // Compute tax suggestion for confirmation. Prefer the ISO country
      // code — geocoders return full names ("Canada") that the lookup's
      // name normalization may not cover.
      _taxSuggestion = TaxRateLookup.suggest(
        state: state,
        country: suggestion.countryCode ?? country,
      );
    });
    _isSettingAddressFromSuggestion = false;
    // Region (state/province) inference first: coordinates can't separate
    // Canada from the US (e.g. Toronto vs New York share a longitude band).
    final inferredFromText = _inferUsTimezoneFromAddressText(
      [
        _businessAddressController.text,
        if (state != null) state,
      ].join(', '),
    );
    if (inferredFromText != null) {
      if (inferredFromText != _selectedTimezone && mounted) {
        setState(() => _selectedTimezone = inferredFromText);
      }
    } else {
      _applyTimezoneFromAddressCoordinates(
        latitude: suggestion.latitude,
        longitude: suggestion.longitude,
      );
    }
    FocusScope.of(context).unfocus();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep++;
      });
    } else {
      _completeOnboarding();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep--;
      });
    }
  }

  void _skipStep() {
    _nextStep();
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0: // Welcome & company name
        return _companyNameController.text.trim().isNotEmpty;
      case 1: // Goals
        return _selectedGoals.isNotEmpty;
      case 2: // Company type
        return true;
      case 3: // Business location
        return _businessAddressController.text.trim().isNotEmpty &&
            TimezoneOptions.isValid(_selectedTimezone);
      case 4: // Team size
        return _selectedTeamSize != null;
      case 5: // AI Persona (optional)
        return true;
      case 6: // Appearance (optional)
        return true;
      case 7: // Invite team (optional)
        return true;
      case 8: // Create project (optional)
        return true;
      default:
        return false;
    }
  }

  String _validationMessageForStep() {
    switch (_currentStep) {
      case 0:
        return 'Enter your company name to continue';
      case 1:
        return 'Pick at least one goal to continue';
      case 3:
        if (_businessAddressController.text.trim().isEmpty) {
          return 'Enter your business address to continue';
        }
        return 'Pick a valid timezone to continue';
      case 4:
        return 'Pick your team size to continue';
      default:
        return 'Complete this step to continue';
    }
  }

  bool _isOptionalStep() {
    if (widget.isNewWorkspace) {
      // For new workspace creation, all steps after company name are optional
      return _currentStep >= 1;
    }
    return _currentStep >= 5; // Steps 5-8 are optional
  }

  String _stepLabel(int step) {
    const labels = [
      'Company Info',
      'Your Goals',
      'Company Type',
      'Location',
      'Team Size',
      'AI Persona',
      'Appearance',
      'Invite Team',
      'Get Started',
    ];
    return labels[step];
  }

  Future<void> _pickLogo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(() {
            _logoBytes = file.bytes;
            _logoFileName = file.name;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'picking image'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _removeLogo() {
    setState(() {
      _logoBytes = null;
      _logoFileName = null;
    });
  }

  void _addInviteField() {
    setState(() {
      _teamInvites.add(_TeamInviteEntry());
    });
  }

  void _removeInviteField(int index) {
    if (_teamInvites.length > 1) {
      setState(() {
        _teamInvites.removeAt(index);
      });
    }
  }

  Future<String?> _uploadLogo(String workspaceId) async {
    if (_logoBytes == null) return null;

    try {
      final extension = _logoFileName?.split('.').last ?? 'png';
      final fileName =
          'logo_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final path = '$workspaceId/$fileName';

      debugPrint(
        'Uploading logo to ${SupabaseConfig.workspaceLogosBucket}/$path',
      );

      await Supabase.instance.client.storage
          .from(SupabaseConfig.workspaceLogosBucket)
          .uploadBinary(
            path,
            _logoBytes!,
            fileOptions: FileOptions(
              contentType: 'image/$extension',
              upsert: true,
            ),
          );

      final url = Supabase.instance.client.storage
          .from(SupabaseConfig.workspaceLogosBucket)
          .getPublicUrl(path);

      debugPrint('Logo uploaded successfully: $url');
      return url;
    } catch (e, stack) {
      debugPrint('Error uploading logo: $e');
      debugPrint('Stack trace: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Warning: Logo upload failed. You can add it later in settings.',
            ),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return null;
    }
  }

  /// Sends invitations for every team member added during onboarding.
  /// Returns the list of emails that failed so the caller can surface them.
  Future<List<String>> _sendInvitations(
    String workspaceId,
    String invitedBy,
  ) async {
    final invitationService = SupabaseInvitationService();
    final failed = <String>[];
    List<WorkspaceRoleTemplate> templates = const [];

    try {
      templates = await ServiceLocator.roleTemplateService.getTemplates(
        workspaceId: workspaceId,
      );
    } catch (e, stack) {
      AppLogger.error(
        'Error loading role templates for onboarding invites',
        error: e,
        stackTrace: stack,
        metadata: {'workspaceId': workspaceId},
      );
    }

    for (final invite in _teamInvites) {
      final email = invite.email.trim();
      if (email.isEmpty || !_isValidEmail(email)) continue;

      final template = _resolveInviteTemplate(templates, invite.role);
      try {
        await invitationService.inviteUser(
          workspaceId: workspaceId,
          email: email,
          role: template?.legacyRole ?? invite.role,
          invitedBy: invitedBy,
          interfaceMode: template?.defaultInterfaceMode ??
              (invite.role == UserRole.fieldTechnician ? 'field' : 'manager'),
          roleTemplateId: template?.id,
        );
      } catch (e, stack) {
        AppLogger.error(
          'Error sending invitation',
          error: e,
          stackTrace: stack,
          metadata: {'email': email, 'workspaceId': workspaceId},
        );
        failed.add(email);
      }
    }
    return failed;
  }

  WorkspaceRoleTemplate? _resolveInviteTemplate(
    List<WorkspaceRoleTemplate> templates,
    UserRole role,
  ) {
    final matches =
        templates.where((template) => template.role == role).toList();
    if (matches.isEmpty) return null;

    matches.sort((a, b) {
      if (a.isSystem == b.isSystem) return 0;
      return a.isSystem ? -1 : 1;
    });
    return matches.first;
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  void _applyTimezoneFromAddressText(String address) {
    final inferred = _inferUsTimezoneFromAddressText(address);
    if (inferred != null && inferred != _selectedTimezone && mounted) {
      setState(() {
        _selectedTimezone = inferred;
      });
    }
  }

  void _applyTimezoneFromAddressCoordinates({
    required double latitude,
    required double longitude,
  }) {
    final inferred = _inferTimezoneFromCoordinates(
      latitude: latitude,
      longitude: longitude,
    );
    if (inferred != _selectedTimezone && mounted) {
      setState(() {
        _selectedTimezone = inferred;
      });
    }
  }

  String _inferTimezoneFromCoordinates({
    required double latitude,
    required double longitude,
  }) {
    // Supported global presets (match TimezoneOptions.common)
    if (latitude <= -10 && longitude >= 110 && longitude <= 180) {
      return 'Australia/Sydney';
    }
    if (latitude >= 20 &&
        latitude <= 46 &&
        longitude >= 122 &&
        longitude <= 154) {
      return 'Asia/Tokyo';
    }
    if (latitude >= 35 &&
        latitude <= 72 &&
        longitude >= -10 &&
        longitude <= 3) {
      return 'Europe/London';
    }
    if (latitude >= 35 && latitude <= 55 && longitude > 3 && longitude <= 16) {
      return 'Europe/Paris';
    }

    // US/NA defaults
    if (latitude >= 18 &&
        latitude <= 23 &&
        longitude >= -161 &&
        longitude <= -154) {
      return 'Pacific/Honolulu';
    }
    if (latitude >= 50 && longitude <= -130) {
      return 'America/Anchorage';
    }
    if (longitude <= -115) return 'America/Los_Angeles';
    if (longitude <= -100) return 'America/Denver';
    if (longitude <= -85) return 'America/Chicago';
    if (longitude <= -65) return 'America/New_York';
    return TimezoneOptions.detectFromDevice();
  }

  String? _inferUsTimezoneFromAddressText(String address) {
    final normalized = address.toUpperCase();
    if (normalized.isEmpty) return null;

    const eastern = {
      'CT',
      'DE',
      'FL',
      'GA',
      'IN',
      'KY',
      'ME',
      'MD',
      'MA',
      'MI',
      'NH',
      'NJ',
      'NY',
      'NC',
      'OH',
      'PA',
      'RI',
      'SC',
      'TN',
      'VT',
      'VA',
      'WV',
      'DC',
    };
    const central = {
      'AL',
      'AR',
      'IL',
      'IA',
      'KS',
      'LA',
      'MN',
      'MS',
      'MO',
      'NE',
      'ND',
      'OK',
      'SD',
      'TX',
      'WI',
    };
    const mountain = {'AZ', 'CO', 'ID', 'MT', 'NM', 'UT', 'WY'};
    const pacific = {'CA', 'NV', 'OR', 'WA'};
    const alaska = {'AK'};
    const hawaii = {'HI'};

    final match = RegExp(
      r'(?:,\s*|\b)([A-Z]{2})(?:\s+\d{5}(?:-\d{4})?)?(?:,|$)',
    ).firstMatch(normalized);
    final state = match?.group(1);
    if (state != null) {
      if (eastern.contains(state)) return 'America/New_York';
      if (central.contains(state)) return 'America/Chicago';
      if (mountain.contains(state)) return 'America/Denver';
      if (pacific.contains(state)) return 'America/Los_Angeles';
      if (alaska.contains(state)) return 'America/Anchorage';
      if (hawaii.contains(state)) return 'Pacific/Honolulu';
      // Canadian provinces / territories (codes are disjoint from US states),
      // so eastern Canada gets America/Toronto rather than America/New_York.
      const caProvinceTz = {
        'ON': 'America/Toronto',
        'QC': 'America/Toronto',
        'NU': 'America/Toronto',
        'NS': 'America/Halifax',
        'NB': 'America/Halifax',
        'PE': 'America/Halifax',
        'NL': 'America/St_Johns',
        'MB': 'America/Winnipeg',
        'SK': 'America/Regina',
        'AB': 'America/Edmonton',
        'NT': 'America/Edmonton',
        'BC': 'America/Vancouver',
        'YT': 'America/Vancouver',
      };
      final caTz = caProvinceTz[state];
      if (caTz != null) return caTz;
    }

    // Full province names first: geocoders (e.g. Nominatim) return
    // "Ontario", not "ON", and Canadian postal codes never match the
    // two-letter-code regex above.
    const byProvinceName = {
      'ONTARIO': 'America/Toronto',
      'QUEBEC': 'America/Toronto',
      'QUÉBEC': 'America/Toronto',
      'NUNAVUT': 'America/Toronto',
      'NOVA SCOTIA': 'America/Halifax',
      'NEW BRUNSWICK': 'America/Halifax',
      'PRINCE EDWARD ISLAND': 'America/Halifax',
      'NEWFOUNDLAND AND LABRADOR': 'America/St_Johns',
      'MANITOBA': 'America/Winnipeg',
      'SASKATCHEWAN': 'America/Regina',
      'ALBERTA': 'America/Edmonton',
      'NORTHWEST TERRITORIES': 'America/Edmonton',
      'BRITISH COLUMBIA': 'America/Vancouver',
      'YUKON': 'America/Vancouver',
    };

    for (final entry in byProvinceName.entries) {
      if (normalized.contains(entry.key)) return entry.value;
    }

    const byStateName = {
      'ALABAMA': 'America/Chicago',
      'ALASKA': 'America/Anchorage',
      'ARIZONA': 'America/Denver',
      'ARKANSAS': 'America/Chicago',
      'CALIFORNIA': 'America/Los_Angeles',
      'COLORADO': 'America/Denver',
      'CONNECTICUT': 'America/New_York',
      'DELAWARE': 'America/New_York',
      'FLORIDA': 'America/New_York',
      'GEORGIA': 'America/New_York',
      'HAWAII': 'Pacific/Honolulu',
      'IDAHO': 'America/Denver',
      'ILLINOIS': 'America/Chicago',
      'INDIANA': 'America/New_York',
      'IOWA': 'America/Chicago',
      'KANSAS': 'America/Chicago',
      'KENTUCKY': 'America/New_York',
      'LOUISIANA': 'America/Chicago',
      'MAINE': 'America/New_York',
      'MARYLAND': 'America/New_York',
      'MASSACHUSETTS': 'America/New_York',
      'MICHIGAN': 'America/New_York',
      'MINNESOTA': 'America/Chicago',
      'MISSISSIPPI': 'America/Chicago',
      'MISSOURI': 'America/Chicago',
      'MONTANA': 'America/Denver',
      'NEBRASKA': 'America/Chicago',
      'NEVADA': 'America/Los_Angeles',
      'NEW HAMPSHIRE': 'America/New_York',
      'NEW JERSEY': 'America/New_York',
      'NEW MEXICO': 'America/Denver',
      'NEW YORK': 'America/New_York',
      'NORTH CAROLINA': 'America/New_York',
      'NORTH DAKOTA': 'America/Chicago',
      'OHIO': 'America/New_York',
      'OKLAHOMA': 'America/Chicago',
      'OREGON': 'America/Los_Angeles',
      'PENNSYLVANIA': 'America/New_York',
      'RHODE ISLAND': 'America/New_York',
      'SOUTH CAROLINA': 'America/New_York',
      'SOUTH DAKOTA': 'America/Chicago',
      'TENNESSEE': 'America/New_York',
      'TEXAS': 'America/Chicago',
      'UTAH': 'America/Denver',
      'VERMONT': 'America/New_York',
      'VIRGINIA': 'America/New_York',
      'WASHINGTON': 'America/Los_Angeles',
      'WEST VIRGINIA': 'America/New_York',
      'WISCONSIN': 'America/Chicago',
      'WYOMING': 'America/Denver',
      'DISTRICT OF COLUMBIA': 'America/New_York',
    };

    for (final entry in byStateName.entries) {
      if (normalized.contains(entry.key)) return entry.value;
    }
    return null;
  }

  _ParsedAddress _parseAddressParts(String address) {
    if (address.isEmpty) {
      return const _ParsedAddress();
    }

    final parts = address
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final zipMatch = RegExp(r'\b\d{5}(?:-\d{4})?\b').firstMatch(address);
    final zipCode = zipMatch?.group(0);

    String? city;
    String? state;
    String? country;

    // US-format detection: the last comma segment contains a 5-digit zip
    // (e.g., "DC 20500" or "California 94043"). In that case the layout is
    // [Street, City, State Zip] with no country suffix — earlier logic
    // mis-shifted Street into `city`. When a country suffix IS present
    // (4+ segments, last segment has no zip), fall back to the old indexing.
    final lastSegmentHasZip =
        parts.isNotEmpty && RegExp(r'\d{5}(?:-\d{4})?').hasMatch(parts.last);

    if (lastSegmentHasZip) {
      // [Street..., City, State Zip] (no country)
      if (parts.length >= 2) {
        city = parts[parts.length - 2];
      }
      state = parts.last;
    } else {
      // [Street..., City, State, Country]
      if (parts.length >= 3) {
        city = parts[parts.length - 3];
      }
      if (parts.length >= 2) {
        state = parts[parts.length - 2];
      }
      country = parts.last;
    }

    if (state != null && state.contains(' ')) {
      final stateToken = state.split(' ').firstWhere(
            (token) =>
                token.length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(token),
            orElse: () => state!,
          );
      state = stateToken;
    }

    return _ParsedAddress(
      city: city?.isEmpty == true ? null : city,
      state: state?.isEmpty == true ? null : state,
      zipCode: zipCode,
      country: country?.isEmpty == true ? null : country,
    );
  }

  /// Maps selected goals to a list of enabled navigation tab IDs.
  /// If all goals are selected, returns empty list (all tabs enabled).
  List<String> _goalsToEnabledNavigationTabs(Set<String> goals) {
    if (goals.length >= availableGoals().length)
      return []; // All goals = all tabs

    // Always-on tabs. We include the surfaces that the top-bar "+ New"
    // menu can create from any workspace (Customers, Vendors, Messages,
    // plus the universally-needed Files/Documents area), so created
    // records aren't orphaned in a workspace whose goals didn't pick
    // those modules.
    final tabs = <String>{
      'projects',
      'customers',
      'vendors',
      'messages',
      'files',
    };

    // Map each goal to the tabs it implies
    for (final goal in goals) {
      switch (goal) {
        case 'scheduling':
          tabs.add('tasks');
          break;
        case 'budgets':
          tabs.addAll(['financials', 'catalog']);
          break;
        case 'team':
          tabs.add('team');
          break;
        case 'customers':
          tabs.add('customers');
          break;
        case 'time':
          tabs.add('timesheets');
          break;
        case 'documents':
          // Documents are accessible within projects; no separate nav tab
          break;
      }
    }

    return tabs.toList();
  }

  Future<void> _completeOnboarding({bool createProject = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();

      // Refresh user to ensure we have the latest workspace ID
      await authProvider.refreshUser();

      final userId = authProvider.appUser?.id;
      String? workspaceId;

      if (widget.isNewWorkspace) {
        // Create a new workspace first
        if (userId == null) {
          throw Exception('User not authenticated');
        }

        workspaceId = await ServiceLocator.workspaceService.createWorkspace(
          name: _companyNameController.text.trim(),
          ownerId: userId,
          companyType: _selectedCompanyType,
          timezone: _selectedTimezone,
        );
      } else {
        workspaceId = authProvider.appUser?.currentWorkspaceId;
      }

      if (workspaceId == null || workspaceId.isEmpty) {
        throw Exception(
          'No workspace found. Please try signing out and back in.',
        );
      }

      // Upload logo if provided
      String? logoUrl;
      if (_logoBytes != null) {
        logoUrl = await _uploadLogo(workspaceId);
      }

      // Calculate trial dates (14 days from now)
      final now = DateTime.now();
      final trialEnd = now.add(const Duration(days: 14));
      final businessAddress = _businessAddressController.text.trim();
      final parsedAddress = _parseAddressParts(businessAddress);
      final startingProjectSerialNumber =
          _startingSerialNumberController.text.trim().isEmpty
              ? null
              : int.tryParse(_startingSerialNumberController.text.trim());

      // Use pre-computed tax suggestion (shown to user in step 4), or
      // fall back to computing from parsed address if user skipped.
      final taxSuggestion = _taxSuggestion ??
          TaxRateLookup.suggest(
            state: parsedAddress.state,
            country: parsedAddress.country,
          );

      final projectTerminology =
          _projectTerminologyController.text.trim().isEmpty
              ? null
              : _projectTerminologyController.text.trim();

      // Map goals to initial navigation tab configuration
      final enabledNavigationTabs = _goalsToEnabledNavigationTabs(
        _selectedGoals,
      );

      final updateData = <String, dynamic>{
        'name': _companyNameController.text.trim(),
        'company_type': _selectedCompanyType.name,
        if (businessAddress.isNotEmpty) 'company_address': businessAddress,
        if (parsedAddress.city != null) 'company_city': parsedAddress.city,
        if (parsedAddress.state != null) 'company_state': parsedAddress.state,
        if (parsedAddress.zipCode != null)
          'company_zip_code': parsedAddress.zipCode,
        if (parsedAddress.country != null)
          'company_country': parsedAddress.country,
        'team_size': _selectedTeamSize?.value,
        'timezone': _selectedTimezone,
        'currency_code': _selectedCurrencyCode,
        'goals': _selectedGoals.toList(),
        'onboarding_completed': true,
        'updated_at': now.toIso8601String(),
        'ai_persona_avatar': _aiPersonaAvatar,
        'ai_persona_style': _aiPersonaStyle,
        'enabled_navigation_tabs': enabledNavigationTabs,
        if (projectTerminology != null)
          'project_terminology': projectTerminology,
        if (startingProjectSerialNumber != null)
          'starting_project_serial_number': startingProjectSerialNumber,
        if (_aiPersonaNameController.text.trim().isNotEmpty)
          'ai_persona_name': _aiPersonaNameController.text.trim(),
        if (taxSuggestion != null) ...{
          'default_tax_enabled': true,
          'default_tax_name': taxSuggestion.name,
          'default_tax_rate': taxSuggestion.rate,
        },
      };

      if (!widget.isNewWorkspace) {
        // Only seed the trial if the workspace has never started one. Without
        // this guard, a workspace whose trial already expired (and was demoted
        // to free by sweep_expired_trials) would get silently re-trialed on
        // any rerun of onboarding.
        final existing = await Supabase.instance.client
            .from('workspaces')
            .select('trial_start_date, subscription_tier')
            .eq('id', workspaceId)
            .maybeSingle();
        final neverTrialed = existing != null &&
            existing['trial_start_date'] == null &&
            (existing['subscription_tier'] as String? ?? 'free') == 'free';
        if (neverTrialed) {
          updateData.addAll({
            'subscription_tier': 'pro',
            'subscription_status': 'trialing',
            'trial_start_date': now.toIso8601String(),
            'trial_end_date': trialEnd.toIso8601String(),
          });
        }
      }

      if (logoUrl != null) {
        updateData['avatar_url'] = logoUrl;
      }

      await Supabase.instance.client
          .from('workspaces')
          .update(updateData)
          .eq('id', workspaceId);

      List<String> failedInvites = const [];
      if (userId != null) {
        failedInvites = await _sendInvitations(workspaceId, userId);
      }

      if (mounted) {
        // For new workspace, switch to it before navigating
        if (widget.isNewWorkspace) {
          await authProvider.switchWorkspace(workspaceId);
          if (!mounted) return;
          await context.read<WorkspaceProvider>().loadWorkspaces(userId!);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Workspace created successfully')),
          );
        } else if (userId != null) {
          // Standard onboarding (first-time user): we just rewrote
          // workspace fields (project_terminology, goals, team_size, etc.)
          // but the WorkspaceProvider still has stale membership data from
          // before the update, so the dashboard would show pre-onboarding
          // terminology ("project" instead of the chosen "Jobs"). Reload
          // so the provider sees the freshly saved values.
          await context.read<WorkspaceProvider>().loadWorkspaces(userId);
          if (!mounted) return;
        }

        if (failedInvites.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 8),
              content: Text(
                'Could not send invitations to: ${failedInvites.join(', ')}. '
                'You can retry from workspace settings.',
              ),
            ),
          );
        }

        context.go('/');

        // If user chose to create a project, show the popup after a short delay
        if (createProject) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              showProjectFormPopup(context);
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'complete this action'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0a1628), _onboardingBlue, Color(0xFF1565a8)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _GridPainter())),
            SafeArea(
              child: Column(
                children: [
                  // Progress indicator
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            if (widget.isNewWorkspace)
                              Padding(
                                padding:
                                    const EdgeInsets.only(right: AppSpacing.md),
                                child: IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    color: AppColors.textOnDark.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                  onPressed: () => context.go('/'),
                                  tooltip: 'Cancel',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ),
                            for (int i = 0; i < _totalSteps; i++) ...[
                              Expanded(
                                child: Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: i <= _currentStep
                                        ? AppColors.textOnDark
                                        : AppColors.textOnDark.withValues(
                                            alpha: 0.3,
                                          ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              if (i < _totalSteps - 1) const SizedBox(width: 4),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Step ${_currentStep + 1} of $_totalSteps — ${_stepLabel(_currentStep)}',
                          style: TextStyle(
                            color: AppColors.textOnDark.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Page content
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildWelcomeStep(),
                        _buildGoalsStep(),
                        _buildCompanyTypeStep(),
                        _buildTimezoneStep(),
                        _buildTeamSizeStep(),
                        _buildAiPersonaStep(),
                        _buildAppearanceStep(),
                        _buildInviteTeamStep(),
                        _buildGetStartedStep(),
                      ],
                    ),
                  ),

                  // Navigation buttons
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Row(
                      children: [
                        if (_currentStep > 0)
                          TextButton(
                            onPressed: _previousStep,
                            child: Text(
                              'Back',
                              style: TextStyle(
                                color: AppColors.textOnDark.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ),
                        const Spacer(),
                        // "Skip setup" for new workspace — creates workspace with minimal config
                        if (widget.isNewWorkspace &&
                            _currentStep > 0 &&
                            _currentStep < _totalSteps - 1)
                          Padding(
                            padding:
                                const EdgeInsets.only(right: AppSpacing.md),
                            child: TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : () => _completeOnboarding(),
                              child: Text(
                                'Skip setup',
                                style: TextStyle(
                                  color: AppColors.textOnDark.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_isOptionalStep() && _currentStep < _totalSteps - 1)
                          Padding(
                            padding:
                                const EdgeInsets.only(right: AppSpacing.md),
                            child: TextButton(
                              onPressed: _skipStep,
                              child: Text(
                                'Skip',
                                style: TextStyle(
                                  color: AppColors.textOnDark.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_currentStep < _totalSteps - 1)
                          ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    if (!_canProceed()) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _validationMessageForStep(),
                                          ),
                                          backgroundColor: AppColors.warning,
                                        ),
                                      );
                                      return;
                                    }
                                    _nextStep();
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.surface,
                              foregroundColor: _onboardingBlue,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xxl,
                                vertical: AppSpacing.base,
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Continue',
                                    style: TextStyle(
                                      fontWeight: AppTextWeights.semibold,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Step 1: Welcome & Company Name
  Widget _buildWelcomeStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isNewWorkspace
                ? 'Set up your new workspace'
                : 'Welcome to FieldFleet! 👋',
            style: const TextStyle(
              color: AppColors.textOnDark,
              fontSize: 28,
              fontWeight: AppTextWeights.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isNewWorkspace
                ? 'Configure your new workspace in just a few steps.'
                : 'Let\'s set up your workspace in just a few steps.',
            style: TextStyle(
              color: AppColors.textOnDark.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),

          // Company name
          StackedField(
            label: 'Company Name',
            labelColor: AppColors.textOnDark.withValues(alpha: 0.85),
            child: TextField(
              controller: _companyNameController,
              decoration: InputDecoration(
                hintText: 'Enter your company name',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                border: const OutlineInputBorder(
                  borderRadius:
                      BorderRadius.all(Radius.circular(AppRadius.r12)),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.surface,
                prefixIcon: const Icon(Icons.business_outlined),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Company Logo (optional)',
            style: TextStyle(
              color: AppColors.textOnDark.withValues(alpha: 0.85),
              fontSize: 15,
              fontWeight: AppTextWeights.semibold,
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _pickLogo,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.glassHighlight,
                borderRadius: BorderRadius.circular(AppRadius.r12),
                border: Border.all(
                    color: AppColors.textOnDark.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Container(
                      width: 56,
                      height: 56,
                      color: AppColors.textOnDark.withValues(alpha: 0.08),
                      child: _logoBytes != null
                          ? Image.memory(_logoBytes!, fit: BoxFit.cover)
                          : Icon(
                              Icons.image_outlined,
                              color:
                                  AppColors.textOnDark.withValues(alpha: 0.7),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _logoBytes != null
                          ? 'Logo selected${_logoFileName != null ? ': $_logoFileName' : ''}'
                          : 'Upload your company logo (PNG/JPG)',
                      style: TextStyle(
                        color: AppColors.textOnDark.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (_logoBytes != null)
                    IconButton(
                      onPressed: _removeLogo,
                      icon: const Icon(Icons.close),
                      color: AppColors.textOnDark.withValues(alpha: 0.7),
                    )
                  else
                    Icon(
                      Icons.upload_file,
                      color: AppColors.textOnDark.withValues(alpha: 0.7),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Step 2: Goals (moved early for AI processing)
  Widget _buildGoalsStep() {
    final pluralTerminology = _projectTerminologyController.text.trim().isEmpty
        ? _selectedCompanyType.defaultProjectTerminology
        : _projectTerminologyController.text.trim();
    final goalSingular = singularProjectTerminology(pluralTerminology);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What do you want to accomplish?',
            style: TextStyle(
              color: AppColors.textOnDark,
              fontSize: 28,
              fontWeight: AppTextWeights.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select all that apply - we\'ll customize your experience',
            style: TextStyle(
              color: AppColors.textOnDark.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          ...availableGoals(goalSingular).map((goal) {
            final isSelected = _selectedGoals.contains(goal.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: InkWell(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedGoals.remove(goal.id);
                    } else {
                      _selectedGoals.add(goal.id);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(AppRadius.r12),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.surface
                        : AppColors.glassHighlight,
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.surface
                          : AppColors.textOnDark.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _onboardingBlue.withValues(alpha: 0.1)
                              : AppColors.glassHighlight,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Icon(
                          goal.icon,
                          color: isSelected
                              ? _onboardingBlue
                              : AppColors.textOnDark,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              goal.title,
                              style: TextStyle(
                                color: isSelected
                                    ? _onboardingBlue
                                    : AppColors.textOnDark,
                                fontSize: 16,
                                fontWeight: AppTextWeights.semibold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              goal.description,
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.textSecondary
                                    : AppColors.textOnDark.withValues(
                                        alpha: 0.7,
                                      ),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Checkbox(
                        value: isSelected,
                        onChanged: (_) {
                          setState(() {
                            if (isSelected) {
                              _selectedGoals.remove(goal.id);
                            } else {
                              _selectedGoals.add(goal.id);
                            }
                          });
                        },
                        activeColor: _onboardingBlue,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // Step 3: Company Type
  Widget _buildCompanyTypeStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What type of business?',
            style: TextStyle(
              color: AppColors.textOnDark,
              fontSize: 28,
              fontWeight: AppTextWeights.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This helps us customize features for your industry',
            style: TextStyle(
              color: AppColors.textOnDark.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: CompanyType.values.map((type) {
              final isSelected = _selectedCompanyType == type;
              return ChoiceChip(
                avatar: Icon(
                  type.icon,
                  size: 18,
                  color: isSelected
                      ? _onboardingBlue
                      : _onboardingBlue.withValues(alpha: 0.7),
                ),
                label: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xs,
                  ),
                  child: Text(type.displayName),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedCompanyType =
                        selected ? type : _selectedCompanyType;
                    // Auto-fill project terminology from company type
                    if (selected) {
                      _projectTerminologyController.text =
                          type.defaultProjectTerminology;
                    }
                  });
                },
                selectedColor: AppColors.surface,
                backgroundColor: AppColors.surface.withValues(alpha: 0.9),
                labelStyle: TextStyle(
                  color: isSelected
                      ? _onboardingBlue
                      : _onboardingBlue.withValues(alpha: 0.7),
                  fontWeight: isSelected
                      ? AppTextWeights.semibold
                      : AppTextWeights.regular,
                  fontSize: 15,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          StackedField(
            label: 'What should this work be called?',
            labelColor: AppColors.textOnDark.withValues(alpha: 0.85),
            child: TextField(
              controller: _projectTerminologyController,
              decoration: InputDecoration(
                hintText: 'e.g. Jobs, Sites, Projects',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                border: const OutlineInputBorder(
                  borderRadius:
                      BorderRadius.all(Radius.circular(AppRadius.r12)),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.surface,
                prefixIcon: const Icon(Icons.folder_outlined),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _projectTerminologyController,
            builder: (context, value, _) {
              final pluralTerminology = value.text.trim().isEmpty
                  ? _selectedCompanyType.defaultProjectTerminology
                  : value.text.trim();
              return Text(
                'This label will be used throughout the app for $pluralTerminology.',
                style: TextStyle(
                  color: AppColors.textOnDark.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Step 4: Business location + timezone
  Widget _buildTimezoneStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What is your business address?',
            style: TextStyle(
              color: AppColors.textOnDark,
              fontSize: 28,
              fontWeight: AppTextWeights.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We use your location to prefill timezone for schedules and timesheets',
            style: TextStyle(
              color: AppColors.textOnDark.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          StackedField(
            label: 'Business Address',
            labelColor: AppColors.textOnDark.withValues(alpha: 0.85),
            child: TextField(
              controller: _businessAddressController,
              decoration: InputDecoration(
                hintText: '123 Main St, City, ST 00000',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                border: const OutlineInputBorder(
                  borderRadius:
                      BorderRadius.all(Radius.circular(AppRadius.r12)),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.surface,
                prefixIcon: const Icon(Icons.location_on_outlined),
                suffixIcon: _isLoadingAddressSuggestions
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          if (_addressSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.r12),
              ),
              child: Column(
                children: _addressSuggestions.map((suggestion) {
                  final condensedSuggestion = suggestion.singleLineAddress(
                    typedQuery: _businessAddressController.text.trim(),
                  );
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.place_outlined,
                      color: _onboardingBlue,
                    ),
                    title: Text(
                      condensedSuggestion,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectAddressSuggestion(suggestion),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          StackedField(
            label: 'Timezone',
            labelColor: AppColors.textOnDark.withValues(alpha: 0.85),
            child: DropdownButtonFormField<String>(
              borderRadius: AppRadius.cardRadius,
              initialValue: _selectedTimezone,
              decoration: const InputDecoration(
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.all(Radius.circular(AppRadius.r12)),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.surface,
                prefixIcon: Icon(Icons.schedule),
              ),
              items: TimezoneOptions.common.map((tz) {
                return DropdownMenuItem<String>(
                  value: tz.id,
                  child: Text(tz.label),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedTimezone = value;
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Timezone is auto-selected from address when possible, and you can always change it.',
            style: TextStyle(
              color: AppColors.textOnDark.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          StackedField(
            label: 'Currency',
            labelColor: AppColors.textOnDark.withValues(alpha: 0.85),
            child: DropdownButtonFormField<String>(
              borderRadius: AppRadius.cardRadius,
              initialValue: _selectedCurrencyCode,
              decoration: const InputDecoration(
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.all(Radius.circular(AppRadius.r12)),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.surface,
                prefixIcon: Icon(Icons.monetization_on_outlined),
              ),
              items: CurrencyUtils.getCurrencies().map((currency) {
                return DropdownMenuItem<String>(
                  value: currency.code,
                  child: Text(
                    '${currency.symbol} ${currency.code} - ${currency.name}',
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedCurrencyCode = value);
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Auto-selected from your address. Used for budgets, invoices, and reports.',
            style: TextStyle(
              color: AppColors.textOnDark.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          if (_taxSuggestion != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.glassHighlight,
                borderRadius: BorderRadius.circular(AppRadius.r12),
                border: Border.all(
                    color: AppColors.textOnDark.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    color: AppColors.textOnDark.withValues(alpha: 0.9),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'We\'ll set default tax to ${_taxSuggestion!.name} at ${_taxSuggestion!.rate}% based on your location. You can change this in settings.',
                      style: TextStyle(
                        color: AppColors.textOnDark.withValues(alpha: 0.9),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _projectTerminologyController,
            builder: (context, value, _) {
              final pluralTerminology = value.text.trim().isEmpty
                  ? _selectedCompanyType.defaultProjectTerminology
                  : value.text.trim();
              final singularTerminology = singularProjectTerminology(
                pluralTerminology,
              );
              return StackedField(
                label: 'Starting $singularTerminology Serial Number (Optional)',
                labelColor: AppColors.textOnDark.withValues(alpha: 0.85),
                child: TextField(
                  controller: _startingSerialNumberController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: 'e.g. 100',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    border: const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(AppRadius.r12)),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                    prefixIcon: const Icon(Icons.numbers_outlined),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _projectTerminologyController,
            builder: (context, value, _) {
              final pluralTerminology = value.text.trim().isEmpty
                  ? _selectedCompanyType.defaultProjectTerminology
                  : value.text.trim();
              return Text(
                'Only affects serial numbers for new ${pluralTerminology.toLowerCase()}.',
                style: TextStyle(
                  color: AppColors.textOnDark.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Step 5: Team Size
  Widget _buildTeamSizeStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How big is your team?',
            style: TextStyle(
              color: AppColors.textOnDark,
              fontSize: 28,
              fontWeight: AppTextWeights.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This helps us set up the right features',
            style: TextStyle(
              color: AppColors.textOnDark.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          ...TeamSize.values.map((size) {
            final isSelected = _selectedTeamSize == size;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedTeamSize = size;
                  });
                },
                borderRadius: BorderRadius.circular(AppRadius.r12),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.surface
                        : AppColors.glassHighlight,
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.surface
                          : AppColors.textOnDark.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getTeamSizeIcon(size),
                        color:
                            isSelected ? _onboardingBlue : AppColors.textOnDark,
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          size.label,
                          style: TextStyle(
                            color: isSelected
                                ? _onboardingBlue
                                : AppColors.textOnDark,
                            fontSize: 18,
                            fontWeight: AppTextWeights.semibold,
                          ),
                        ),
                      ),
                      if (isSelected)
                        const Icon(
                          Icons.check_circle,
                          color: _onboardingBlue,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  IconData _getTeamSizeIcon(TeamSize size) {
    switch (size) {
      case TeamSize.solo:
        return Icons.person_outline;
      case TeamSize.small:
        return Icons.people_outline;
      case TeamSize.medium:
        return Icons.groups_outlined;
      case TeamSize.large:
        return Icons.groups_3_outlined;
      case TeamSize.enterprise:
        return Icons.corporate_fare_outlined;
    }
  }

  // Step 5: AI Persona (Optional)
  Widget _buildAiPersonaStep() {
    final previewName = _aiPersonaNameController.text.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Meet your AI assistant',
            style: TextStyle(
              color: AppColors.textOnDark,
              fontSize: 28,
              fontWeight: AppTextWeights.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Optional — give your AI a name and personality',
            style: TextStyle(
              color: AppColors.textOnDark.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.glassHighlight,
              borderRadius: BorderRadius.circular(AppRadius.r16),
              border: Border.all(
                  color: AppColors.textOnDark.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assistant Profile',
                  style: TextStyle(
                    color: AppColors.textOnDark.withValues(alpha: 0.95),
                    fontSize: 15,
                    fontWeight: AppTextWeights.bold,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _aiPersonaNameController,
                  decoration: InputDecoration(
                    hintText: 'e.g., Maria, Atlas, Foreman AI',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    labelText: 'AI assistant name (optional)',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    border: const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(AppRadius.r12)),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.glassHighlight,
              borderRadius: BorderRadius.circular(AppRadius.r16),
              border: Border.all(
                  color: AppColors.textOnDark.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose an avatar',
                  style: TextStyle(
                    color: AppColors.textOnDark.withValues(alpha: 0.95),
                    fontSize: 15,
                    fontWeight: AppTextWeights.bold,
                  ),
                ),
                const SizedBox(height: 10),
                PersonaAvatarPicker(
                  selectedAvatar: _aiPersonaAvatar,
                  onAvatarSelected: (slug) =>
                      setState(() => _aiPersonaAvatar = slug),
                  isLightBackground: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.glassHighlight,
              borderRadius: BorderRadius.circular(AppRadius.r16),
              border: Border.all(
                  color: AppColors.textOnDark.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Personality style',
                  style: TextStyle(
                    color: AppColors.textOnDark.withValues(alpha: 0.95),
                    fontSize: 15,
                    fontWeight: AppTextWeights.bold,
                  ),
                ),
                const SizedBox(height: 10),
                PersonaStylePicker(
                  selectedStyle: _aiPersonaStyle,
                  onStyleSelected: (slug) =>
                      setState(() => _aiPersonaStyle = slug),
                  isLightBackground: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF0b3e71),
              borderRadius: BorderRadius.circular(AppRadius.r16),
              border: Border.all(
                color: const Color(0xFF57a8ff).withValues(alpha: 0.55),
                width: 1.4,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live preview',
                  style: TextStyle(
                    color: AppColors.textOnDark.withValues(alpha: 0.95),
                    fontSize: 15,
                    fontWeight: AppTextWeights.bold,
                  ),
                ),
                const SizedBox(height: 10),
                PersonaPreviewBubble(
                  avatarSlug: _aiPersonaAvatar,
                  name: previewName.isNotEmpty ? previewName : null,
                  selectedStyle: _aiPersonaStyle,
                  isLightBackground: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // Step 6 (index): Appearance (Optional)
  Widget _buildAppearanceStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Make it yours',
            style: TextStyle(
              color: AppColors.textOnDark,
              fontSize: 28,
              fontWeight: AppTextWeights.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose how the interface looks — you can change this anytime.',
            style: TextStyle(
              color: AppColors.textOnDark.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.glassHighlight,
              borderRadius: BorderRadius.circular(AppRadius.r16),
              border: Border.all(
                  color: AppColors.textOnDark.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance',
                  style: TextStyle(
                    color: AppColors.textOnDark.withValues(alpha: 0.95),
                    fontSize: 15,
                    fontWeight: AppTextWeights.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Controls the toolbar and header colour scheme.',
                  style: TextStyle(
                    color: AppColors.textOnDark.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Consumer<ChromeProvider>(
                  builder: (context, chromeProvider, _) =>
                      SegmentedButton<bool>(
                    style: SegmentedButton.styleFrom(
                      backgroundColor: AppColors.textOnDark.withValues(
                        alpha: 0.08,
                      ),
                      selectedBackgroundColor: AppColors.surface,
                      selectedForegroundColor: _onboardingBlue,
                      foregroundColor: AppColors.textOnDark,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                    ],
                    selected: {chromeProvider.isDarkChrome},
                    onSelectionChanged: (values) =>
                        chromeProvider.setDarkChrome(values.first),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Step 8: Invite Team (Optional)
  Widget _buildInviteTeamStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Invite your team',
            style: TextStyle(
              color: AppColors.textOnDark,
              fontSize: 28,
              fontWeight: AppTextWeights.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Optional - Add team members to get started together',
            style: TextStyle(
              color: AppColors.textOnDark.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),

          // Invite entries
          ...List.generate(_teamInvites.length, (index) {
            final invite = _teamInvites[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.base),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.base),
                decoration: BoxDecoration(
                  color: AppColors.glassHighlight,
                  borderRadius: BorderRadius.circular(AppRadius.r12),
                  border: Border.all(
                      color: AppColors.textOnDark.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    // Email input
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Email address',
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.all(Radius.circular(AppRadius.sm)),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: AppColors.surface,
                          prefixIcon: Icon(Icons.email_outlined),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.base,
                            vertical: AppSpacing.md,
                          ),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (value) => invite.email = value,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Role selector and remove button
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: DropdownButton<UserRole>(
                              borderRadius: AppRadius.cardRadius,
                              value: invite.role,
                              isExpanded: true,
                              underline: const SizedBox(),
                              items: [
                                UserRole.admin,
                                UserRole.projectManager,
                                UserRole.fieldTechnician,
                              ].map((role) {
                                return DropdownMenuItem(
                                  value: role,
                                  child: Text(role.displayName),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => invite.role = value);
                                }
                              },
                            ),
                          ),
                        ),
                        if (_teamInvites.length > 1) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _removeInviteField(index),
                            icon: const Icon(Icons.remove_circle_outline),
                            color: AppColors.error,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

          // Add more button
          Center(
            child: TextButton.icon(
              onPressed: _addInviteField,
              icon: Icon(
                Icons.add,
                color: AppColors.textOnDark.withValues(alpha: 0.7),
              ),
              label: Text(
                'Add another',
                style: TextStyle(
                  color: AppColors.textOnDark.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Step 8: Get Started (Optional - Create Project or Skip)
  Widget _buildGetStartedStep() {
    final getStartedPlural = _projectTerminologyController.text.trim().isEmpty
        ? _selectedCompanyType.defaultProjectTerminology
        : _projectTerminologyController.text.trim();
    final getStartedSingular = singularProjectTerminology(getStartedPlural);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'You\'re all set! 🎉',
            style: TextStyle(
              color: AppColors.textOnDark,
              fontSize: 28,
              fontWeight: AppTextWeights.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose how you\'d like to get started',
            style: TextStyle(
              color: AppColors.textOnDark.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 48),

          // Create first project option
          InkWell(
            onTap: () => _completeOnboarding(createProject: true),
            borderRadius: BorderRadius.circular(AppRadius.r16),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.r16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _onboardingBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.r12),
                    ),
                    child: const Icon(
                      Icons.add_business_outlined,
                      size: 28,
                      color: _onboardingBlue,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _projectTerminologyController,
                          builder: (context, value, _) {
                            final pluralTerminology = value.text.trim().isEmpty
                                ? _selectedCompanyType.defaultProjectTerminology
                                : value.text.trim();
                            final singularTerminology =
                                singularProjectTerminology(pluralTerminology);
                            return Text(
                              'Create Your First $singularTerminology',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: AppTextWeights.bold,
                                color: _onboardingBlue,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _projectTerminologyController,
                          builder: (context, value, _) {
                            final pluralTerminology = value.text.trim().isEmpty
                                ? _selectedCompanyType.defaultProjectTerminology
                                : value.text.trim();
                            final singularTerminology =
                                singularProjectTerminology(pluralTerminology);
                            return Text(
                              'Get started right away with a new ${singularTerminology.toLowerCase()}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward, color: _onboardingBlue),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Explore first option
          InkWell(
            onTap: () => _completeOnboarding(createProject: false),
            borderRadius: BorderRadius.circular(AppRadius.r16),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.glassHighlight,
                borderRadius: BorderRadius.circular(AppRadius.r16),
                border: Border.all(
                  color: AppColors.textOnDark.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.glassHighlight,
                      borderRadius: BorderRadius.circular(AppRadius.r12),
                    ),
                    child: Icon(
                      Icons.explore_outlined,
                      size: 28,
                      color: AppColors.textOnDark.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Skip & Explore First',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: AppTextWeights.bold,
                            color: AppColors.textOnDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Look around before creating your first ${getStartedSingular.toLowerCase()}',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textOnDark.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward,
                    color: AppColors.textOnDark.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Loading indicator when completing
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppColors.textOnDark),
            ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textOnDark.withValues(alpha: 0.03)
      ..strokeWidth = 1;

    const spacing = 50.0;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
