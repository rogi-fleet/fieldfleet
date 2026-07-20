import 'dart:async';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/company_type.dart';
import '../../models/workspace.dart';
import '../onboarding/onboarding_screen.dart' show availableGoals;
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../utils/project_terminology.dart';
import '../../services/ai_copilot_flags.dart';
import '../../utils/app_logger.dart';
import '../../utils/app_time_formatter.dart';
import '../../utils/country_list.dart';
import '../../utils/currency_utils.dart';
import '../../utils/tax_rate_lookup.dart';
import '../../utils/timezone_options.dart';
import '../../theme/theme.dart';
import '../../widgets/workspace_avatar.dart';
import '../../widgets/image_upload_options_dialog.dart';
import '../../widgets/ai_persona_picker.dart';
import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class _WorkspaceSettingsTabConfig {
  final String label;
  final IconData icon;
  final Widget child;

  const _WorkspaceSettingsTabConfig({
    required this.label,
    required this.icon,
    required this.child,
  });
}

class WorkspaceSettingsScreen extends StatefulWidget {
  const WorkspaceSettingsScreen({super.key});

  @override
  State<WorkspaceSettingsScreen> createState() =>
      _WorkspaceSettingsScreenState();
}

class _WorkspaceSettingsScreenState extends State<WorkspaceSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _projectTerminologyController = TextEditingController();
  final _startingSerialNumberController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _weeklyWageController = TextEditingController();
  final _workspaceService = ServiceLocator.workspaceService;

  // Company Address controllers
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _websiteController = TextEditingController();
  String? _selectedCountry;
  String _selectedCurrencyCode = 'USD';
  String _selectedTimezone = TimezoneOptions.defaultTimezone;
  String _selectedUnitSystem = 'imperial';

  // Default tax settings
  final _defaultTaxNameController = TextEditingController();
  final _defaultTaxRateController = TextEditingController();
  bool _defaultTaxEnabled = true;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingImage = false;
  Map<String, dynamic>? _workspaceData;
  String? _currentWorkspaceId;
  final Set<String> _dirtyFields = <String>{};
  final _imagePicker = ImagePicker();
  CompanyType? _selectedCompanyType;
  StreamSubscription<Map<String, dynamic>?>? _workspaceSubscription;
  // AI Persona state
  final _aiPersonaNameController = TextEditingController();
  final _aiPersonaContextController = TextEditingController();
  String _aiPersonaAvatar = 'hard_hat';
  String _aiPersonaStyle = 'mentor';

  bool _isLoadingAiFlags = false;
  final Set<String> _savingAiFlagKeys = <String>{};
  Map<String, bool> _aiFlagValues = {
    AiCopilotFlags.riskV1: false,
    AiCopilotFlags.scheduleV1: false,
    AiCopilotFlags.weeklyDigestV1: false,
  };

  static const double _desktopBreakpoint = 700.0;
  static const double _twoColumnThreshold = 560.0;

  // Available project tabs (id -> display name). Reflects the consolidated
  // 7-tab structure; legacy IDs (time-tracking, plans, specifications,
  // change-orders, work-orders, subcontracts, notes, etc.) still
  // resolve via the tab normalizer but no longer surface as configurable
  // top-level tabs.
  static const _availableTabs = {
    'overview': 'Overview',
    'info': 'Properties',
    'tasks': 'Tasks',
    'financials': 'Financials',
    'selections': 'Selections',
    'inventory': 'Inventory',
    'messages': 'Messages',
    'files': 'Files',
  };

  // Legacy tab IDs → consolidated settings ID. Mirrors the runtime
  // normalizer in ProjectDetailScreen but emits the settings-form ID
  // ('financials' rather than 'budget') and only retains values that
  // correspond to a currently configurable top-level tab. Anything not
  // mapped here is dropped on load so stored rows don't accumulate
  // invisible cruft across releases.
  static const Map<String, String> _legacyTabIdMap = {
    'budget': 'financials',
    'time-tracking': 'tasks',
    'timetracking': 'tasks',
    'time': 'tasks',
    'timesheet': 'tasks',
    'timesheets': 'tasks',
    'property': 'info',
    'properties': 'info',
    'notes': 'overview',
    'note': 'overview',
    'plans': 'files',
    'plan': 'files',
    'specifications': 'files',
    'specification': 'files',
    'specs': 'files',
    'spec': 'files',
    'daily-logs': 'files',
    'inspections': 'files',
    'punch-list': 'files',
    'warranties': 'files',
    'documents': 'files',
    'forms': 'files',
    'change-orders': 'financials',
    'change-order': 'financials',
    'changeorders': 'financials',
    'work-orders': 'financials',
    'work-order': 'financials',
    'workorders': 'financials',
    'subcontracts': 'financials',
    'subcontract': 'financials',
    'subs': 'financials',
    'assets': 'inventory',
    'materials': 'inventory',
  };

  /// Maps a stored tab list onto current top-level tab IDs and drops any
  /// IDs that no longer correspond to a configurable tab. Preserves the
  /// first-seen order so the admin's intended ordering survives migration.
  static List<String> _normalizeStoredTabIds(Iterable<String> stored) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in stored) {
      final lower = raw.trim().toLowerCase();
      if (lower.isEmpty) continue;
      final mapped = _legacyTabIdMap[lower] ?? lower;
      if (!_availableTabs.containsKey(mapped)) continue;
      if (seen.add(mapped)) result.add(mapped);
    }
    return result;
  }

  // Available navigation tabs (id -> display name)
  static const _availableNavigationTabs = {
    'projects': 'Projects',
    'tasks': 'Tasks',
    'customers': 'Customers',
    'financials': 'Financials',
    'vendors': 'Vendors',
    'timesheets': 'Time',
    'team': 'Team',
    'assets': 'Assets',
    'vehicles': 'Vehicles',
    'reports': 'Reports',
    'catalog': 'Catalog',
  };

  // Enabled tabs state (empty list means all enabled)
  List<String> _enabledTabs = [];
  List<String> _enabledNavigationTabs = [];

  // Schedule view settings
  bool _showBusinessDaysOnly = false;

  // Goals & Team Size (from onboarding, now editable)
  final Set<String> _selectedGoals = {};
  TeamSize? _selectedTeamSize;

  void _markFieldDirty(String field) {
    _dirtyFields.add(field);
  }

  void _suggestTaxFromLocation() {
    final suggestion = TaxRateLookup.suggest(
      state: _stateController.text.trim(),
      country: _selectedCountry,
    );
    if (suggestion != null) {
      setState(() {
        _defaultTaxNameController.text = suggestion.name;
        _defaultTaxRateController.text = suggestion.rate.toString();
      });
      _markFieldDirty('defaultTaxName');
      _markFieldDirty('defaultTaxRate');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not determine tax rate for this location'),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadWorkspaceData();
  }

  @override
  void dispose() {
    _workspaceSubscription?.cancel();
    _nameController.dispose();
    _projectTerminologyController.dispose();
    _startingSerialNumberController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipCodeController.dispose();
    _websiteController.dispose();
    _hourlyRateController.dispose();
    _weeklyWageController.dispose();
    _defaultTaxNameController.dispose();
    _defaultTaxRateController.dispose();
    _aiPersonaNameController.dispose();
    _aiPersonaContextController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkspaceData() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId == null) {
        throw Exception('No active workspace');
      }

      // Cancel existing subscription before creating a new one
      await _workspaceSubscription?.cancel();

      setState(() {
        _currentWorkspaceId = workspaceId;
        _isLoading = true;
      });

      _loadAiFlags(workspaceId);

      // Subscribe to workspace changes
      _workspaceSubscription = _workspaceService
          .getWorkspace(workspaceId)
          .listen((data) {
            if (mounted && data != null) {
              setState(() {
                _workspaceData = data;
                _nameController.text = data['name'] ?? '';
                _selectedCompanyType = data['companyType'] != null
                    ? CompanyType.fromString(data['companyType'] as String)
                    : null;
                _projectTerminologyController.text =
                    data['projectTerminology'] ?? 'Projects';
                _startingSerialNumberController.text =
                    data['startingProjectSerialNumber']?.toString() ?? '';
                // Load enabled tabs (empty list means all enabled). The
                // normalizer collapses legacy IDs (plans, time-tracking,
                // change-orders, etc.) onto their consolidated
                // settings ID and drops anything that no longer exists, so
                // the FilterChip UI never silently hides a stored value.
                _enabledTabs = data['enabledProjectTabs'] != null
                    ? _normalizeStoredTabIds(
                        List<String>.from(data['enabledProjectTabs'] as List),
                      )
                    : [];
                _enabledNavigationTabs = data['enabledNavigationTabs'] != null
                    ? List<String>.from(data['enabledNavigationTabs'] as List)
                    : [];
                _showBusinessDaysOnly =
                    data['showBusinessDaysOnly'] as bool? ?? false;
                // Load company address
                _addressController.text = data['companyAddress'] ?? '';
                _cityController.text = data['companyCity'] ?? '';
                _stateController.text = data['companyState'] ?? '';
                _zipCodeController.text = data['companyZipCode'] ?? '';
                _selectedCountry = data['companyCountry'] as String?;
                _websiteController.text = data['website'] ?? '';
                _selectedCurrencyCode =
                    data['currencyCode'] as String? ?? 'USD';
                final workspaceTimezone = data['timezone'] as String?;
                _selectedTimezone = TimezoneOptions.isValid(workspaceTimezone)
                    ? workspaceTimezone!
                    : TimezoneOptions.defaultTimezone;
                final workspaceUnitSystem = data['unitSystem'] as String?;
                _selectedUnitSystem =
                    workspaceUnitSystem == 'metric' ? 'metric' : 'imperial';
                _hourlyRateController.text =
                    data['hourlyRate']?.toString() ?? '';
                _weeklyWageController.text =
                    data['weeklyWage']?.toString() ?? '';
                // Default tax settings
                _defaultTaxEnabled = data['defaultTaxEnabled'] as bool? ?? true;
                _defaultTaxNameController.text =
                    data['defaultTaxName'] as String? ?? 'Tax';
                _defaultTaxRateController.text =
                    (data['defaultTaxRate'] as num?)?.toString() ?? '0';
                // AI Persona fields
                _aiPersonaNameController.text =
                    data['aiPersonaName'] as String? ?? '';
                _aiPersonaAvatar =
                    data['aiPersonaAvatar'] as String? ?? 'hard_hat';
                _aiPersonaStyle = data['aiPersonaStyle'] as String? ?? 'mentor';
                _aiPersonaContextController.text =
                    data['aiPersonaContext'] as String? ?? '';
                // Goals & Team Size
                _selectedGoals.clear();
                final goals = data['goals'];
                if (goals is List) {
                  _selectedGoals.addAll(goals.cast<String>());
                }
                final teamSizeValue = data['teamSize'] as int?;
                _selectedTeamSize = teamSizeValue != null
                    ? TeamSize.fromValue(teamSizeValue)
                    : null;
                _dirtyFields.clear();
                _isLoading = false;
              });
            }
          });
    } catch (e) {
      AppLogger.error('Error loading workspace data', error: e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(
              'Error loading workspace: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  Future<void> _loadAiFlags(String workspaceId) async {
    setState(() => _isLoadingAiFlags = true);
    try {
      final riskEnabled = await ServiceLocator.aiCopilotService
          .isFeatureEnabled(
            workspaceId: workspaceId,
            flagKey: AiCopilotFlags.riskV1,
          );
      final scheduleEnabled = await ServiceLocator.aiCopilotService
          .isFeatureEnabled(
            workspaceId: workspaceId,
            flagKey: AiCopilotFlags.scheduleV1,
          );
      final digestEnabled = await ServiceLocator.aiCopilotService
          .isFeatureEnabled(
            workspaceId: workspaceId,
            flagKey: AiCopilotFlags.weeklyDigestV1,
          );
      if (!mounted) return;
      setState(() {
        _aiFlagValues = {
          AiCopilotFlags.riskV1: riskEnabled,
          AiCopilotFlags.scheduleV1: scheduleEnabled,
          AiCopilotFlags.weeklyDigestV1: digestEnabled,
        };
        _isLoadingAiFlags = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingAiFlags = false);
      AppLogger.warning(
        'Failed to load AI feature flags',
        metadata: {'workspaceId': workspaceId, 'error': e.toString()},
      );
    }
  }

  Future<void> _setAiFlag({
    required String flagKey,
    required bool enabled,
  }) async {
    if (_currentWorkspaceId == null) return;
    setState(() => _savingAiFlagKeys.add(flagKey));
    try {
      await ServiceLocator.aiCopilotService.setFeatureFlag(
        workspaceId: _currentWorkspaceId!,
        flagKey: flagKey,
        enabled: enabled,
      );
      if (!mounted) return;
      setState(() {
        _aiFlagValues[flagKey] = enabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${flagKey.split('_').skip(2).join(' ')} ${enabled ? 'enabled' : 'disabled'}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update AI flag: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingAiFlagKeys.remove(flagKey));
      }
    }
  }

  Future<void> _saveWorkspace() async {
    if (!_formKey.currentState!.validate() || _currentWorkspaceId == null) {
      return;
    }

    if (_dirtyFields.isEmpty) {
      _showWorkspaceSnackBar(
        const Text('No changes to save'),
        icon: Icons.info_outline,
        backgroundColor: AppColors.infoLight,
        foregroundColor: AppColors.infoDark,
        iconColor: AppColors.infoDark,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    final projectTerminology = _projectTerminologyController.text.trim().isEmpty
        ? null
        : _projectTerminologyController.text.trim();
    final startingProjectSerialNumber =
        _startingSerialNumberController.text.trim().isEmpty
        ? null
        : int.tryParse(_startingSerialNumberController.text.trim());
    final companyAddress = _addressController.text.trim().isEmpty
        ? null
        : _addressController.text.trim();
    final companyCity = _cityController.text.trim().isEmpty
        ? null
        : _cityController.text.trim();
    final companyState = _stateController.text.trim().isEmpty
        ? null
        : _stateController.text.trim();
    final companyZipCode = _zipCodeController.text.trim().isEmpty
        ? null
        : _zipCodeController.text.trim();
    final website = _websiteController.text.trim().isEmpty
        ? null
        : _websiteController.text.trim();
    final hourlyRate = _hourlyRateController.text.trim().isEmpty
        ? null
        : double.tryParse(_hourlyRateController.text.trim());
    final weeklyWage = _weeklyWageController.text.trim().isEmpty
        ? null
        : double.tryParse(_weeklyWageController.text.trim());
    final defaultTaxName = _defaultTaxNameController.text.trim().isEmpty
        ? 'Tax'
        : _defaultTaxNameController.text.trim();
    final defaultTaxRate = _defaultTaxRateController.text.trim().isEmpty
        ? null
        : double.tryParse(_defaultTaxRateController.text.trim());
    final aiPersonaName = _aiPersonaNameController.text.trim().isEmpty
        ? null
        : _aiPersonaNameController.text.trim();
    final aiPersonaContext = _aiPersonaContextController.text.trim().isEmpty
        ? null
        : _aiPersonaContextController.text.trim();

    setState(() => _isSaving = true);

    try {
      await _workspaceService.updateWorkspace(
        workspaceId: _currentWorkspaceId!,
        name: _nameController.text.trim(),
        companyType: _selectedCompanyType,
        projectTerminology: projectTerminology,
        startingProjectSerialNumber: startingProjectSerialNumber,
        enabledProjectTabs: _enabledTabs,
        enabledNavigationTabs: _enabledNavigationTabs,
        showBusinessDaysOnly: _showBusinessDaysOnly,
        companyAddress: companyAddress,
        companyCity: companyCity,
        companyState: companyState,
        companyZipCode: companyZipCode,
        companyCountry: _selectedCountry,
        website: website,
        currencyCode: _selectedCurrencyCode,
        timezone: _selectedTimezone,
        unitSystem: _selectedUnitSystem,
        hourlyRate: hourlyRate,
        weeklyWage: weeklyWage,
        defaultTaxEnabled: _defaultTaxEnabled,
        defaultTaxName: defaultTaxName,
        defaultTaxRate: defaultTaxRate,
        aiPersonaName: aiPersonaName,
        aiPersonaAvatar: _aiPersonaAvatar,
        aiPersonaStyle: _aiPersonaStyle,
        aiPersonaContext: aiPersonaContext,
        goals: _selectedGoals.toList(),
        teamSize: _selectedTeamSize?.value,
        touchedFields: Set<String>.from(_dirtyFields),
      );

      if (!mounted) return;

      // Update local state immediately with saved values
      setState(() {
        _workspaceData = {
          ..._workspaceData ?? {},
          'name': _nameController.text.trim(),
          'companyType': _selectedCompanyType?.name,
          'projectTerminology': projectTerminology,
          'startingProjectSerialNumber': startingProjectSerialNumber,
          'enabledProjectTabs': _enabledTabs,
          'enabledNavigationTabs': _enabledNavigationTabs,
          'showBusinessDaysOnly': _showBusinessDaysOnly,
          'companyAddress': companyAddress,
          'companyCity': companyCity,
          'companyState': companyState,
          'companyZipCode': companyZipCode,
          'companyCountry': _selectedCountry,
          'website': website,
          'currencyCode': _selectedCurrencyCode,
          'timezone': _selectedTimezone,
          'unitSystem': _selectedUnitSystem,
          'hourlyRate': hourlyRate,
          'weeklyWage': weeklyWage,
          'defaultTaxEnabled': _defaultTaxEnabled,
          'defaultTaxName': defaultTaxName,
          'defaultTaxRate': defaultTaxRate,
          'aiPersonaName': aiPersonaName,
          'aiPersonaAvatar': _aiPersonaAvatar,
          'aiPersonaStyle': _aiPersonaStyle,
          'aiPersonaContext': aiPersonaContext,
          'goals': _selectedGoals.toList(),
          'teamSize': _selectedTeamSize?.value,
        };
        _dirtyFields.clear();
      });

      // Refresh workspace list in provider
      final authProvider = context.read<AuthProvider>();
      if (authProvider.appUser != null) {
        await context.read<WorkspaceProvider>().loadWorkspaces(
          authProvider.appUser!.id,
        );
      }

      if (!mounted) return;

      _showWorkspaceSnackBar(
        const Text('Workspace updated successfully'),
        icon: Icons.check_circle_outline,
        backgroundColor: AppColors.successLight,
        foregroundColor: AppColors.successDark,
        iconColor: AppColors.successDark,
      );
    } catch (e) {
      if (mounted) {
        _showWorkspaceSnackBar(
          SelectableText(
            'Error updating workspace: $e',
            style: const TextStyle(color: Colors.white),
          ),
          icon: Icons.error_outline,
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 10),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    if (_currentWorkspaceId == null) return;

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isUploadingImage = true);

      final bytes = await image.readAsBytes();
      final fileName = image.name;

      await _workspaceService.uploadWorkspaceAvatar(
        _currentWorkspaceId!,
        bytes,
        fileName,
      );

      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workspace avatar updated')),
        );

        // Refresh workspace list in provider
        final authProvider = context.read<AuthProvider>();
        if (authProvider.appUser != null) {
          await context.read<WorkspaceProvider>().loadWorkspaces(
            authProvider.appUser!.id,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'uploading image'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _removeWorkspaceAvatar() async {
    if (_currentWorkspaceId == null) return;

    final avatarUrl = _workspaceData?['avatarUrl'] as String?;
    if (avatarUrl == null) return;

    try {
      setState(() => _isUploadingImage = true);

      await _workspaceService.deleteWorkspaceAvatar(
        _currentWorkspaceId!,
        avatarUrl,
      );

      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workspace avatar removed')),
        );

        // Refresh workspace list in provider
        final authProvider = context.read<AuthProvider>();
        if (authProvider.appUser != null) {
          await context.read<WorkspaceProvider>().loadWorkspaces(
            authProvider.appUser!.id,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'removing avatar'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  List<DropdownMenuItem<CompanyType>> _buildCompanyTypeItems() {
    final Map<String, List<CompanyType>> grouped = {};

    // Group company types by category
    for (final type in CompanyType.values) {
      final category = type.category;
      if (!grouped.containsKey(category)) {
        grouped[category] = [];
      }
      grouped[category]!.add(type);
    }

    final List<DropdownMenuItem<CompanyType>> items = [];

    // Add items with category headers
    grouped.forEach((category, types) {
      // Add category header (disabled)
      items.add(
        DropdownMenuItem<CompanyType>(
          value: null,
          enabled: false,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              category,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ),
      );

      // Add company types under this category
      items.addAll(
        types.map(
          (type) => DropdownMenuItem<CompanyType>(
            value: type,
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Row(
                children: [
                  Icon(type.icon, size: 20, color: AppColors.textTertiary),
                  const SizedBox(width: 12),
                  Text(type.displayName),
                ],
              ),
            ),
          ),
        ),
      );
    });

    return items;
  }

  int _activeTabIndex = 0;

  void _showWorkspaceSnackBar(
    Widget content, {
    IconData? icon,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? iconColor,
    Duration duration = const Duration(seconds: 4),
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    const mobileInset = 16.0;
    const bottomInset = 104.0;
    const targetToastWidth = 420.0;
    final resolvedToastWidth = screenWidth >= 520
        ? targetToastWidth
        : screenWidth - (mobileInset * 2);
    final horizontalInset = ((screenWidth - resolvedToastWidth) / 2).clamp(
      mobileInset,
      screenWidth / 2,
    );
    final resolvedBackgroundColor = backgroundColor ?? AppColors.infoLight;
    final useLightForeground =
        ThemeData.estimateBrightnessForColor(resolvedBackgroundColor) ==
        Brightness.dark;
    final resolvedForegroundColor =
        foregroundColor ??
        (useLightForeground ? Colors.white : AppColors.textPrimary);
    final resolvedIconColor =
        iconColor ??
        (useLightForeground ? Colors.white : AppColors.textSecondary);
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: DefaultTextStyle(
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(color: resolvedForegroundColor),
            child: IconTheme(
              data: IconThemeData(color: resolvedIconColor, size: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon), const SizedBox(width: 10)],
                  Expanded(child: content),
                ],
              ),
            ),
          ),
          backgroundColor: resolvedBackgroundColor,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          elevation: 8,
          dismissDirection: DismissDirection.horizontal,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardRadius,
            side: BorderSide(
              color: useLightForeground
                  ? resolvedBackgroundColor
                  : AppColors.cardBorder,
            ),
          ),
          margin: EdgeInsets.fromLTRB(
            horizontalInset.toDouble(),
            mobileInset,
            horizontalInset.toDouble(),
            bottomInset,
          ),
        ),
      );
  }

  Future<void> _handleCancel() async {
    if (_dirtyFields.isEmpty) {
      context.go('/');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved changes that will be lost if you leave.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.go('/');
    }
  }

  Widget _buildTabHeader({required String title, required String description}) {
    final chrome = ChromeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // GoogleFonts.interTextTheme bakes in a dark default color, so it's
        // invisible on the dark scaffold. Force the chrome-aware text color.
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: chrome.scaffoldText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(color: chrome.scaffoldTextSecondary, fontSize: 14),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCenteredTabBody({required List<Widget> children}) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  /// Lays out [left] and [right] side-by-side when there is room,
  /// otherwise stacks them vertically.
  Widget _buildCardRow(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _twoColumnThreshold) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 16),
              Expanded(child: right),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: 24), right],
        );
      },
    );
  }

  Widget _buildSettingsTabChip({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final isSelected = _activeTabIndex == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: isSelected,
        showCheckmark: false,
        avatar: Icon(
          icon,
          size: 16,
          color: isSelected
              ? theme.colorScheme.primary
              : AppColors.textSecondary,
        ),
        label: Text(label),
        onSelected: (_) {
          setState(() => _activeTabIndex = index);
        },
      ),
    );
  }

  Widget _buildWorkspaceIdentityTab(dynamic currentUser) {
    return _buildCenteredTabBody(
      children: [
        _buildTabHeader(
          title: 'General',
          description:
              'Your workspace identity, company type, and terminology.',
        ),
        // Avatar
        Center(
          child: Column(
            children: [
              Stack(
                children: [
                  _isUploadingImage
                      ? const SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(),
                        )
                      : WorkspaceAvatar(
                          avatarUrl: _workspaceData?['avatarUrl'] as String?,
                          workspaceName: _nameController.text.isNotEmpty
                              ? _nameController.text
                              : 'Workspace',
                          size: WorkspaceAvatarSize.large,
                        ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Material(
                      color: Theme.of(context).primaryColor,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: _isUploadingImage
                            ? null
                            : () {
                                showImageUploadOptionsDialog(
                                  context: context,
                                  onChooseFromGallery: _pickAndUploadImage,
                                  onRemovePhoto:
                                      _workspaceData?['avatarUrl'] != null
                                      ? _removeWorkspaceAvatar
                                      : null,
                                );
                              },
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          child: Icon(
                            Icons.camera_alt,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Workspace logo',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              Text(
                'Recommended: 256 × 256 px or larger',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Main identity card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StackedField(
                  label: 'Workspace Name',
                  child: TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Acme Corp',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a workspace name';
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {
                      _markFieldDirty('name');
                    }),
                  ),
                ),
                const SizedBox(height: 16),
                StackedField(
                  label: 'Company Type',
                  child: DropdownButtonFormField<CompanyType>(
                    borderRadius: AppRadius.cardRadius,
                    initialValue: _selectedCompanyType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business_center),
                      helperText: 'Type of company or business',
                    ),
                    items: _buildCompanyTypeItems(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCompanyType = value;
                        _markFieldDirty('companyType');
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                StackedField(
                  label: 'Project Terminology',
                  child: TextFormField(
                    controller: _projectTerminologyController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Projects, Jobs, Sites',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.folder),
                      helperText:
                          'Customize what you call projects in your workspace',
                    ),
                    onChanged: (_) => setState(() {
                      _markFieldDirty('projectTerminology');
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_workspaceData != null) ...[
          const SizedBox(height: 16),
          // Owner card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Workspace Owner',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.person, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        _workspaceData!['ownerId'] == currentUser?.id
                            ? 'You'
                            : _workspaceData!['ownerId'] ?? 'Unknown',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  if (_workspaceData!['createdAt'] != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Created: ${_formatDate(_workspaceData!['createdAt'], _selectedTimezone)}',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _workspaceData!['ownerId'] == currentUser?.id
                        ? 'As owner you have full administrative access. Contact support to transfer ownership.'
                        : 'Contact the workspace owner to change permissions or transfer ownership.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag_outlined),
                    const SizedBox(width: 8),
                    Text(
                      'Goals & Team',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'What you want to accomplish and how big your team is. This helps us customize your experience.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const Divider(),
                const SizedBox(height: 8),
                Text('Goals', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: availableGoals().map((goal) {
                    final isSelected = _selectedGoals.contains(goal.id);
                    return FilterChip(
                      label: Text(goal.title),
                      selected: isSelected,
                      showCheckmark: false,
                      avatar: Icon(
                        goal.icon,
                        size: 16,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : AppColors.textSecondary,
                      ),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedGoals.add(goal.id);
                          } else {
                            _selectedGoals.remove(goal.id);
                          }
                          _markFieldDirty('goals');
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                StackedField(
                  label: 'Team Size',
                  child: DropdownButtonFormField<TeamSize>(
                    borderRadius: AppRadius.cardRadius,
                    initialValue: _selectedTeamSize,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.groups_outlined),
                    ),
                    items: TeamSize.values.map((size) {
                      return DropdownMenuItem<TeamSize>(
                        value: size,
                        child: Text(size.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedTeamSize = value;
                        _markFieldDirty('teamSize');
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildAiAssistantCard(),
        const SizedBox(height: 16),
        // Advanced settings — collapsed by default
        Card(
          child: ExpansionTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Advanced'),
            subtitle: Text(
              'Developer settings',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              StackedField(
                label: 'Workspace ID',
                child: TextFormField(
                  initialValue: _currentWorkspaceId ?? '',
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.fingerprint),
                    helperText:
                        'Read-only — used when integrating with the API',
                  ),
                  readOnly: true,
                  enabled: false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocaleAndRatesTab() {
    final wagesCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.payments_outlined),
                const SizedBox(width: 8),
                Text(
                  'Default Wages',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Fallback wages used when a team member does not have a specific rate set.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const Divider(),
            const SizedBox(height: 8),
            StackedField(
              label: 'Default Hourly Wage (Optional)',
              child: TextFormField(
                controller: _hourlyRateController,
                decoration: const InputDecoration(
                  hintText: 'e.g. 50.00',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final number = double.tryParse(value.trim());
                    if (number == null || number < 0) {
                      return 'Please enter a valid positive number';
                    }
                  }
                  return null;
                },
                onChanged: (_) => _markFieldDirty('hourlyRate'),
              ),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Default Weekly Wage (Optional)',
              child: TextFormField(
                controller: _weeklyWageController,
                decoration: const InputDecoration(
                  hintText: 'e.g. 1200.00',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final number = double.tryParse(value.trim());
                    if (number == null || number < 0) {
                      return 'Please enter a valid positive number';
                    }
                  }
                  return null;
                },
                onChanged: (_) => _markFieldDirty('weeklyWage'),
              ),
            ),
          ],
        ),
      ),
    );

    final taxCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long),
                const SizedBox(width: 8),
                Text(
                  'Default Tax Settings',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Applied to new documents. Can be changed per document.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Collect Tax by Default'),
              subtitle: const Text('Show tax fields when creating documents'),
              value: _defaultTaxEnabled,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                setState(() => _defaultTaxEnabled = value);
                _markFieldDirty('defaultTaxEnabled');
              },
            ),
            if (_defaultTaxEnabled) ...[
              const SizedBox(height: 8),
              StackedField(
                label: 'Tax Name',
                child: TextFormField(
                  controller: _defaultTaxNameController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Sales Tax, VAT, GST',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                  onChanged: (_) => _markFieldDirty('defaultTaxName'),
                ),
              ),
              const SizedBox(height: 16),
              StackedField(
                label: 'Tax Rate',
                child: TextFormField(
                  controller: _defaultTaxRateController,
                  decoration: InputDecoration(
                    hintText: 'e.g. 8.5',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.percent),
                    suffixText: '%',
                    suffixIcon:
                        _stateController.text.isNotEmpty ||
                            (_selectedCountry != null &&
                                _selectedCountry!.isNotEmpty)
                        ? Tooltip(
                            message: 'Suggest from location',
                            child: IconButton(
                              icon: const Icon(Icons.auto_fix_high),
                              onPressed: _suggestTaxFromLocation,
                            ),
                          )
                        : null,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    if (value != null && value.trim().isNotEmpty) {
                      final number = double.tryParse(value.trim());
                      if (number == null || number < 0) {
                        return 'Please enter a valid positive number';
                      }
                    }
                    return null;
                  },
                  onChanged: (_) => _markFieldDirty('defaultTaxRate'),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final addressCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on),
                const SizedBox(width: 8),
                Text(
                  'Company Address',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your company address for invoices and documents.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const Divider(),
            const SizedBox(height: 8),
            StackedField(
              label: 'Street Address',
              child: TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.home),
                ),
                onChanged: (_) => _markFieldDirty('companyAddress'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: StackedField(
                    label: 'City',
                    child: TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _markFieldDirty('companyCity'),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: StackedField(
                    label: 'State/Province',
                    child: TextFormField(
                      controller: _stateController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _markFieldDirty('companyState'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: StackedField(
                    label: CountryList.getPostalCodeLabel(_selectedCountry),
                    child: TextFormField(
                      controller: _zipCodeController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _markFieldDirty('companyZipCode'),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: StackedField(
                    label: 'Country',
                    child: DropdownButtonFormField<String>(
                      borderRadius: AppRadius.cardRadius,
                      initialValue: _selectedCountry,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.public),
                      ),
                      items: CountryList.getCountries().map((country) {
                        return DropdownMenuItem<String>(
                          value: country.isEnabled ? country.name : null,
                          enabled: country.isEnabled,
                          child: Text(
                            country.name,
                            style: TextStyle(
                              color: country.isEnabled
                                  ? null
                                  : AppColors.textTertiary,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCountry = value;
                          _markFieldDirty('companyCountry');
                          if (value != null) {
                            _selectedCurrencyCode =
                                CurrencyUtils.getDefaultCurrencyForCountry(
                                  value,
                                );
                            _markFieldDirty('currencyCode');
                          }
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Website',
              child: TextFormField(
                controller: _websiteController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.language),
                ),
                onChanged: (_) => _markFieldDirty('website'),
              ),
            ),
          ],
        ),
      ),
    );

    final currencyCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.attach_money),
                const SizedBox(width: 8),
                Text(
                  'Currency & Timezone',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Used across budgets, invoices, reports, and scheduling.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const Divider(),
            const SizedBox(height: 8),
            StackedField(
              label: 'Currency',
              child: DropdownButtonFormField<String>(
                borderRadius: AppRadius.cardRadius,
                initialValue: _selectedCurrencyCode,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.monetization_on),
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
                    setState(() {
                      _selectedCurrencyCode = value;
                      _markFieldDirty('currencyCode');
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Timezone',
              child: DropdownButtonFormField<String>(
                borderRadius: AppRadius.cardRadius,
                initialValue: _selectedTimezone,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
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
                    _markFieldDirty('timezone');
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Units',
              child: DropdownButtonFormField<String>(
                borderRadius: AppRadius.cardRadius,
                initialValue: _selectedUnitSystem,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.straighten),
                  helperText:
                      'Used for temperature labels and other measurements on field forms.',
                ),
                items: const [
                  DropdownMenuItem<String>(
                    value: 'imperial',
                    child: Text('Imperial (°F)'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'metric',
                    child: Text('Metric (°C)'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedUnitSystem = value;
                    _markFieldDirty('unitSystem');
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );

    return _buildCenteredTabBody(
      children: [
        _buildTabHeader(
          title: 'Finance & Region',
          description:
              'Default wages, tax settings, company address, currency, and timezone.',
        ),
        _buildCardRow(wagesCard, taxCard),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.numbers),
            title: const Text('Document Numbering'),
            subtitle: const Text(
              'Customize prefixes and sequence numbers for invoices, POs, bills, etc.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/document-numbering'),
          ),
        ),
        const SizedBox(height: 24),
        _buildCardRow(addressCard, currencyCard),
      ],
    );
  }

  Widget _buildNavigationAndViewsTab() {
    final navigationTabsCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.navigation),
                const SizedBox(width: 8),
                Text(
                  'Main Navigation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose which sections appear in the main sidebar. If none are selected, all sections are shown.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const Divider(),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _availableNavigationTabs.entries.map((entry) {
                final tabId = entry.key;
                final tabName = entry.value;
                final isEnabled =
                    _enabledNavigationTabs.isEmpty ||
                    _enabledNavigationTabs.contains(tabId);
                return FilterChip(
                  label: Text(tabName),
                  selected: isEnabled,
                  onSelected: (selected) {
                    setState(() {
                      _markFieldDirty('enabledNavigationTabs');
                      if (_enabledNavigationTabs.isEmpty) {
                        if (!selected) {
                          _enabledNavigationTabs = _availableNavigationTabs.keys
                              .where((k) => k != tabId)
                              .toList();
                        }
                        return;
                      }
                      if (selected) {
                        if (!_enabledNavigationTabs.contains(tabId)) {
                          _enabledNavigationTabs.add(tabId);
                        }
                      } else {
                        _enabledNavigationTabs.remove(tabId);
                      }
                      if (_enabledNavigationTabs.length ==
                          _availableNavigationTabs.length) {
                        _enabledNavigationTabs = [];
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );

    return _buildCenteredTabBody(
      children: [
        _buildTabHeader(
          title: 'Navigation',
          description:
              'Control which sidebar sections are visible and manage workspace-wide vocabulary.',
        ),
        navigationTabsCard,
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('File Tags'),
            subtitle: const Text(
              'Manage the workspace-wide tag vocabulary used on files. Set '
              'colors and restrict certain tags to specific roles.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/file-tags'),
          ),
        ),
      ],
    );
  }

  Widget _buildTeamAndAccessTab({
    required bool canViewAuditLog,
    required bool canManageRoleTemplates,
    required bool canManageAutomations,
  }) {
    return _buildCenteredTabBody(
      children: [
        _buildTabHeader(
          title: 'Team & Access',
          description:
              'Manage members, roles, permissions, and workspace integrations.',
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Team Members'),
                subtitle: const Text('Invite and manage workspace members'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  context.push(
                    '/settings/invite?workspaceId=$_currentWorkspaceId',
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.build_circle_outlined),
                title: const Text('Skills'),
                subtitle: const Text(
                  'Define skills for team members and tasks',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  context.go('/team?tab=skills');
                },
              ),
              if (canViewAuditLog) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Audit Log'),
                  subtitle: const Text('Review workspace settings changes'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/settings/audit');
                  },
                ),
              ],
              if (canManageRoleTemplates) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.rule_folder_outlined),
                  title: const Text('Roles & Permissions'),
                  subtitle: const Text(
                    'Review the permission matrix and configure role presets',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/settings/permission-matrix');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.tune_outlined),
                  title: const Text('Settings Profiles'),
                  subtitle: const Text(
                    'Save and apply reusable workspace setting bundles',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/settings/profiles');
                  },
                ),
              ],
              if (canManageAutomations) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_motion_outlined),
                  title: const Text('Automation Rules'),
                  subtitle: const Text(
                    'Create workflow rules for notifications and task actions',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/settings/automations');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('API Keys'),
                  subtitle: const Text(
                    'Connect AI assistants (MCP) and integrations to this '
                    'workspace',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/settings/api-keys');
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAiAssistantCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.smart_toy_outlined),
                const SizedBox(width: 8),
                Text(
                  'AI Assistant',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Personalize your AI assistant name and personality.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const Divider(),
            const SizedBox(height: 8),
            TextField(
              controller: _aiPersonaNameController,
              onChanged: (_) => setState(() {
                _markFieldDirty('aiPersonaName');
              }),
              decoration: const InputDecoration(
                labelText: 'Assistant name (optional)',
                hintText: 'e.g., Max, Aria, Atlas',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Avatar', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            PersonaAvatarPicker(
              selectedAvatar: _aiPersonaAvatar,
              onAvatarSelected: (slug) => setState(() {
                _aiPersonaAvatar = slug;
                _markFieldDirty('aiPersonaAvatar');
              }),
            ),
            const SizedBox(height: 16),
            Text('Personality', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            PersonaStylePicker(
              selectedStyle: _aiPersonaStyle,
              onStyleSelected: (slug) => setState(() {
                _aiPersonaStyle = slug;
                _markFieldDirty('aiPersonaStyle');
              }),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Workspace context (optional)',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                TextButton.icon(
                  onPressed: _autoFillPersonaContext,
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: const Text('Auto-fill'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _aiPersonaContextController,
              maxLines: 3,
              onChanged: (_) => setState(() {
                _markFieldDirty('aiPersonaContext');
              }),
              decoration: const InputDecoration(
                hintText:
                    'e.g., We specialize in water damage restoration. Primary markets: Pacific Northwest. Typical job size \$15k-\$80k.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectsTab({required bool canManageAiFlags}) {
    final projectTerminology = context
        .read<WorkspaceProvider>()
        .projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    final plural = projectTerminology;
    final pluralLower = plural.toLowerCase();
    final singularLower = singular.toLowerCase();

    final numberingCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.numbers),
                const SizedBox(width: 8),
                Text(
                  '$singular Numbering',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Control how $pluralLower are numbered when created.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const Divider(),
            const SizedBox(height: 8),
            StackedField(
              label: 'Starting $singular Number (Optional)',
              child: TextFormField(
                controller: _startingSerialNumberController,
                decoration: InputDecoration(
                  hintText: 'e.g. 100',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.numbers),
                  helperText:
                      'Override the first number assigned to new $pluralLower. Useful when migrating from another system.',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final number = int.tryParse(value.trim());
                    if (number == null || number < 1) {
                      return 'Please enter a positive number';
                    }
                  }
                  return null;
                },
                onChanged: (_) =>
                    _markFieldDirty('startingProjectSerialNumber'),
              ),
            ),
          ],
        ),
      ),
    );

    final projectTabsCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tab),
                const SizedBox(width: 8),
                Text(
                  '$singular Tabs',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose which tabs appear in $singularLower views. If none are selected, all tabs are shown.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const Divider(),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _availableTabs.entries.map((entry) {
                final tabId = entry.key;
                final tabName = entry.value;
                final isEnabled =
                    _enabledTabs.isEmpty || _enabledTabs.contains(tabId);
                return FilterChip(
                  label: Text(tabName),
                  selected: isEnabled,
                  onSelected: (selected) {
                    setState(() {
                      _markFieldDirty('enabledProjectTabs');
                      if (_enabledTabs.isEmpty) {
                        if (selected) return;
                        _enabledTabs = _availableTabs.keys
                            .where((k) => k != tabId)
                            .toList();
                        return;
                      }
                      if (selected) {
                        if (!_enabledTabs.contains(tabId)) {
                          _enabledTabs.add(tabId);
                        }
                      } else {
                        _enabledTabs.remove(tabId);
                      }
                      if (_enabledTabs.length == _availableTabs.length) {
                        _enabledTabs = [];
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );

    final scheduleViewCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_view_week),
                const SizedBox(width: 8),
                Text(
                  'Schedule View',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Customize how the schedule and Gantt chart views display.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Business Days Only'),
              subtitle: const Text('Hide weekends in schedule views'),
              value: _showBusinessDaysOnly,
              onChanged: (value) {
                setState(() {
                  _showBusinessDaysOnly = value;
                  _markFieldDirty('showBusinessDaysOnly');
                });
              },
            ),
          ],
        ),
      ),
    );

    final customFieldsCard = Card(
      child: ListTile(
        leading: const Icon(Icons.dynamic_form),
        title: const Text('Custom Fields'),
        subtitle: Text(
          'Add ad-hoc fields to $pluralLower beyond the built-in schema — '
          'permits, lot size, HOA contact, etc.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/settings/custom-fields'),
      ),
    );

    final copilotFlagsCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined),
                const SizedBox(width: 8),
                Text(
                  'AI Copilot Features',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Enable experimental AI features. These are in early access and may change.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const Divider(),
            if (_isLoadingAiFlags)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else ...[
              _buildAiFlagTile(
                title: 'Risk Score',
                subtitle: '$singular AI risk assessment cards',
                flagKey: AiCopilotFlags.riskV1,
              ),
              _buildAiFlagTile(
                title: 'Schedule Optimizer',
                subtitle: 'AI dependency/order suggestions',
                flagKey: AiCopilotFlags.scheduleV1,
              ),
              _buildAiFlagTile(
                title: 'Weekly Digest',
                subtitle: 'Weekly $singularLower summary cards',
                flagKey: AiCopilotFlags.weeklyDigestV1,
              ),
            ],
          ],
        ),
      ),
    );

    return _buildCenteredTabBody(
      children: [
        _buildTabHeader(
          title: plural,
          description:
              'Configure how $pluralLower work in your workspace — numbering, tabs, schedule, and custom fields.',
        ),
        _buildCardRow(numberingCard, projectTabsCard),
        const SizedBox(height: 24),
        _buildCardRow(scheduleViewCard, customFieldsCard),
        if (canManageAiFlags) ...[
          const SizedBox(height: 24),
          copilotFlagsCard,
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.appUser;
    final canViewAuditLog =
        authProvider.canManageUsers || authProvider.canAccessSettings;
    final canManageRoleTemplates = authProvider.canManageUsers;
    final canManageAiFlags = canManageRoleTemplates;
    // Mirrors the is_pm_or_admin RLS check on automation_rules: admins and
    // members with projects write access can manage automations.
    final canManageAutomations =
        authProvider.canManageUsers || authProvider.canEditProjects;

    final projectTerminology = context
        .watch<WorkspaceProvider>()
        .projectTerminology;

    final tabs = <_WorkspaceSettingsTabConfig>[
      _WorkspaceSettingsTabConfig(
        label: 'Workspace',
        icon: Icons.business,
        child: _buildWorkspaceIdentityTab(currentUser),
      ),
      _WorkspaceSettingsTabConfig(
        label: projectTerminology,
        icon: Icons.folder_outlined,
        child: _buildProjectsTab(canManageAiFlags: canManageAiFlags),
      ),
      _WorkspaceSettingsTabConfig(
        label: 'Finance & Region',
        icon: Icons.public,
        child: _buildLocaleAndRatesTab(),
      ),
      _WorkspaceSettingsTabConfig(
        label: 'Navigation',
        icon: Icons.view_sidebar_outlined,
        child: _buildNavigationAndViewsTab(),
      ),
      _WorkspaceSettingsTabConfig(
        label: 'Team',
        icon: Icons.group_outlined,
        child: _buildTeamAndAccessTab(
          canViewAuditLog: canViewAuditLog,
          canManageRoleTemplates: canManageRoleTemplates,
          canManageAutomations: canManageAutomations,
        ),
      ),
    ];

    final safeTabIndex = _activeTabIndex.clamp(0, tabs.length - 1);

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
                  return isDesktop
                      ? _buildDesktopLayout(tabs, safeTabIndex)
                      : _buildMobileLayout(tabs, safeTabIndex);
                },
              ),
            ),
    );
  }

  Widget _buildDesktopLayout(
    List<_WorkspaceSettingsTabConfig> tabs,
    int safeTabIndex,
  ) {
    final theme = Theme.of(context);
    final chrome = ChromeColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sidebar navigation
        Container(
          width: 220,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: chrome.scaffoldDivider)),
          ),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
            children: List.generate(tabs.length, (i) {
              final tab = tabs[i];
              final isSelected = _activeTabIndex == i;
              return ListTile(
                leading: Icon(
                  tab.icon,
                  size: 20,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : chrome.scaffoldTextSecondary,
                ),
                title: Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 14,
                    color: isSelected ? theme.colorScheme.primary : null,
                    fontWeight: isSelected ? FontWeight.w600 : null,
                  ),
                ),
                selected: isSelected,
                selectedTileColor: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.25),
                onTap: () => setState(() => _activeTabIndex = i),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 2,
                ),
                dense: true,
              );
            }),
          ),
        ),
        // Content area with save/cancel footer below the content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: IndexedStack(
                  index: safeTabIndex,
                  children: tabs.map((tab) => tab.child).toList(),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: chrome.scaffoldDivider)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: Row(
                  children: [
                    if (_dirtyFields.isNotEmpty) ...[
                      Icon(
                        Icons.edit_outlined,
                        size: 13,
                        color: chrome.scaffoldTextSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Unsaved changes',
                        style: TextStyle(
                          color: chrome.scaffoldTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const Spacer(),
                    OutlinedButton(
                      onPressed: _isSaving ? null : _handleCancel,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _isSaving ? null : _saveWorkspace,
                      child: _isSaving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save Changes'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(
    List<_WorkspaceSettingsTabConfig> tabs,
    int safeTabIndex,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(
                tabs.length,
                (index) => _buildSettingsTabChip(
                  index: index,
                  icon: tabs[index].icon,
                  label: tabs[index].label,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: safeTabIndex,
            children: tabs.map((tab) => tab.child).toList(),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_dirtyFields.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 13,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Unsaved changes',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving ? null : _handleCancel,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isSaving ? null : _saveWorkspace,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Auto-fill persona context from existing workspace data.
  void _autoFillPersonaContext() {
    if (_workspaceData == null) return;
    final parts = <String>[];
    final companyType = _selectedCompanyType?.displayName;
    if (companyType != null) parts.add('Company type: $companyType.');
    final timezone = _selectedTimezone;
    if (timezone.isNotEmpty) parts.add('Timezone: $timezone.');
    final goals = _workspaceData!['goals'];
    if (goals is List && goals.isNotEmpty) {
      parts.add('Focus areas: ${goals.join(', ')}.');
    }
    if (parts.isNotEmpty) {
      setState(() {
        _aiPersonaContextController.text = parts.join(' ');
        _markFieldDirty('aiPersonaContext');
      });
    }
  }

  Widget _buildAiFlagTile({
    required String title,
    required String subtitle,
    required String flagKey,
  }) {
    final saving = _savingAiFlagKeys.contains(flagKey);
    final enabled = _aiFlagValues[flagKey] == true;

    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: enabled,
      onChanged: saving
          ? null
          : (value) {
              _setAiFlag(flagKey: flagKey, enabled: value);
            },
      secondary: saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.flag_outlined),
    );
  }

  String _formatDate(dynamic timestamp, String timezone) {
    try {
      if (timestamp == null) return 'Unknown';
      DateTime date;
      if (timestamp is String) {
        // Supabase returns ISO8601 strings
        date = DateTime.parse(timestamp);
      } else {
        // Firebase returns Timestamps with toDate()
        date = timestamp.toDate();
      }
      return AppTimeFormatter.formatDate(date, timezone: timezone);
    } catch (e) {
      return 'Unknown';
    }
  }
}
