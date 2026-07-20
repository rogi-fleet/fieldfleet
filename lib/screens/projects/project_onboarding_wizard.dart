import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../services/geocoding_service.dart';
import '../../models/project.dart';
import '../../models/customer.dart';
import '../../models/customer_location.dart';
import '../../widgets/customers/customer_location_form.dart';
import '../../models/price_type.dart';
import '../../models/cost_plus_type.dart';
import '../../models/job_type.dart';
import '../../models/project_status_theme.dart';
import '../../models/user.dart';
import '../../models/user_role.dart';
import '../../models/project_template.dart';
import '../../providers/custom_field_definitions_provider.dart';
import '../../utils/country_list.dart';
import '../../utils/project_customer_name.dart';
import '../../widgets/common/adaptive_popup.dart';
import '../../widgets/custom_fields_section.dart';
import '../../widgets/user_avatar.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

/// A step-by-step onboarding wizard for creating new projects
class ProjectOnboardingWizard extends StatefulWidget {
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final String? initialCustomerId;
  final String? initialVendorId;
  final DateTime? initialStartDate;
  final ProjectTemplate? template;
  final String? projectId;
  final ValueNotifier<bool>? dirtyNotifier;
  final ScrollController? scrollController;

  const ProjectOnboardingWizard({
    super.key,
    this.onComplete,
    this.onCancel,
    this.initialCustomerId,
    this.initialVendorId,
    this.initialStartDate,
    this.template,
    this.projectId,
    this.dirtyNotifier,
    this.scrollController,
  });

  @override
  State<ProjectOnboardingWizard> createState() =>
      _ProjectOnboardingWizardState();
}

/// Ordered logical step kinds. The wizard dynamically emits an ordered
/// list of these based on workspace configuration — Custom Fields only
/// appears when the workspace has at least one active `showInForm` def
/// (or an archived def with a value on the edited project).
enum _StepKind { customer, identify, team, pricing, customFields, review }

class _ProjectOnboardingWizardState extends State<ProjectOnboardingWizard>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = false;

  // Validation UI state
  bool _showFieldErrors = false;
  String? _validationMessage;
  late final AnimationController _shakeController;

  // Step 1: Customer & Location
  String? _selectedCustomerId;
  String? _customerName;
  String? _selectedCustomerLocationId;
  Future<List<CustomerLocation>>? _customerLocationsFuture;
  String?
  _selectedLocationAddress; // tracks selected location's address for divergence detection
  String? _selectedVendorSubdivisionId;

  // Step 2: Identify Project
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationDetailsController = TextEditingController();
  final GeocodingService _geocodingService = GeocodingService();
  JobType? _selectedJobType;
  String? _photoUrl;
  bool _isUploadingPhoto = false;
  Timer? _addressSuggestionDebounce;
  List<AddressSuggestion> _addressSuggestions = const [];
  bool _isLoadingAddressSuggestions = false;
  ({double latitude, double longitude})? _selectedAddressCoordinates;
  bool _isSettingAddressFromSuggestion = false;
  String? _workspaceCountryCode;

  // Step 3: Team & Pricing
  String? _selectedProjectManagerId;
  String? _selectedSupervisorId;
  String? _selectedSalespersonId;
  List<String> _selectedTeamMemberIds = [];
  final _primaryContactNameController = TextEditingController();
  final _primaryContactRoleController = TextEditingController();
  final _primaryContactPhoneController = TextEditingController();
  final _primaryContactEmailController = TextEditingController();
  bool _showPrimaryContact = false;

  // Step 3: Pricing & Budget
  PriceType _selectedPriceType = PriceType.timeAndMaterial;
  CostPlusType _selectedCostPlusType = CostPlusType.percentage;
  final _contractAmountController = TextEditingController();
  final _costPlusValueController = TextEditingController();
  final _budgetController = TextEditingController();
  final _materialMarkupController = TextEditingController(text: '20');
  final _laborMarkupController = TextEditingController(text: '30');
  final _purchaseOrderController = TextEditingController();

  // Step 4: Timeline
  ProjectStatus _selectedStatus = ProjectStatus.bidding;
  DateTime? _selectedStartDate;
  DateTime? _selectedCompletionDate;
  DateTime? _dateRequestReceived;

  // Services and data
  dynamic get _customerService => ServiceLocator.customerService;
  final dynamic _userService = ServiceLocator.userService;
  final dynamic _workspaceMemberService = ServiceLocator.workspaceMemberService;
  List<AppUser> _workspaceUsers = [];
  bool _isLoadingUsers = true;
  Project? _existingProject;
  late final Stream<List<Customer>> _customersStream;

  // Custom fields — workspace-scoped admin-defined fields. Values are
  // sent as a single `custom_fields` jsonb payload on create/update
  // (full-replace, not merge — see docs/plans/custom-fields.md).
  final CustomFieldDefinitionsProvider _customFieldsProvider =
      CustomFieldDefinitionsProvider();
  Map<String, dynamic> _customFieldValues = {};

  /// Snapshot of `_orderedSteps` captured during the last build. Used
  /// to remap `_currentStep` when defs load mid-session and the step
  /// list grows — without this, an index that pointed to Review in the
  /// old layout would silently point to Custom Fields in the new one.
  List<_StepKind> _lastBuildOrderedSteps = const [];

  /// True when the workspace has at least one active def flagged
  /// `showInForm`, OR (edit mode) the edited project has a value for an
  /// archived def — in which case the step must appear so the value
  /// isn't silently dropped from the UI.
  bool get _hasCustomFieldsStep {
    final defs = _customFieldsProvider.all;
    final anyActiveForm = defs.any((d) => !d.isArchived && d.showInForm);
    if (anyActiveForm) return true;
    // Archived-with-value: only relevant in edit mode, and only if the
    // project actually has that value loaded.
    return defs.any((d) => d.isArchived && _customFieldValues[d.key] != null);
  }

  /// Ordered list of step kinds currently in the wizard. Review is
  /// always last; Custom Fields slots in just before it when present.
  List<_StepKind> get _orderedSteps {
    return [
      _StepKind.customer,
      _StepKind.identify,
      _StepKind.team,
      _StepKind.pricing,
      if (_hasCustomFieldsStep) _StepKind.customFields,
      _StepKind.review,
    ];
  }

  int get _totalSteps => _orderedSteps.length;

  _StepKind _kindAt(int index) => _orderedSteps[index];

  int get _reviewStepIndex => _orderedSteps.indexOf(_StepKind.review);

  // Step configuration
  List<_StepConfig> _buildSteps(String singular) {
    final lower = singular.toLowerCase();
    _StepConfig configFor(_StepKind kind, int number) {
      switch (kind) {
        case _StepKind.customer:
          return _StepConfig(
            number: number,
            title: 'Customer & Site',
            subtitle: "Who is this $lower for and where is it?",
            icon: Icons.people,
          );
        case _StepKind.identify:
          return _StepConfig(
            number: number,
            title: 'Identify $singular',
            subtitle: "Let's gather some quick details about your $lower",
            icon: Icons.business,
          );
        case _StepKind.team:
          return _StepConfig(
            number: number,
            title: 'Team',
            subtitle: "Who's working on this $lower?",
            icon: Icons.group,
          );
        case _StepKind.pricing:
          return _StepConfig(
            number: number,
            title: 'Pricing',
            subtitle: "How is this $lower priced?",
            icon: Icons.payments,
          );
        case _StepKind.customFields:
          return _StepConfig(
            number: number,
            title: 'Custom Fields',
            subtitle: "Workspace-specific details for this $lower",
            icon: Icons.dynamic_form,
          );
        case _StepKind.review:
          return _StepConfig(
            number: number,
            title: 'Review & Create',
            subtitle: "Review your $lower details before creating",
            icon: Icons.check_circle,
          );
      }
    }

    final ordered = _orderedSteps;
    return [
      for (var i = 0; i < ordered.length; i++) configFor(ordered[i], i + 1),
    ];
  }

  List<String> get _editTabLabels {
    return _orderedSteps.map((kind) {
      switch (kind) {
        case _StepKind.customer:
          return 'Customer & Site';
        case _StepKind.identify:
          return 'Details';
        case _StepKind.team:
          return 'Team';
        case _StepKind.pricing:
          return 'Pricing';
        case _StepKind.customFields:
          return 'Custom';
        case _StepKind.review:
          return 'Timeline';
      }
    }).toList();
  }

  bool get _isEditMode => widget.projectId != null;

  String _singularTerminology(BuildContext context, {bool listen = true}) {
    final plural = listen
        ? context.watch<WorkspaceProvider>().projectTerminology
        : context.read<WorkspaceProvider>().projectTerminology;
    if (plural.endsWith('s') && plural.length > 1) {
      return plural.substring(0, plural.length - 1);
    }
    return plural;
  }

  bool _initialLoadComplete = false;

  void _markDirty() {
    if (_initialLoadComplete) {
      widget.dirtyNotifier?.value = true;
    }
  }

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    final workspaceId = Provider.of<AuthProvider>(
      context,
      listen: false,
    ).appUser!.currentWorkspaceId;
    _selectedCustomerId = widget.initialCustomerId;
    _selectedStartDate = widget.initialStartDate;
    _customersStream = _customerService.getCustomers(workspaceId);
    if (_selectedCustomerId != null) {
      _loadNewCustomerName(_selectedCustomerId!);
      _customerLocationsFuture = ServiceLocator.customerLocationService
          .getLocationsForCustomer(_selectedCustomerId!);
    }
    _loadWorkspaceUsers(workspaceId);
    _loadWorkspaceCountryCode(workspaceId);
    // Load custom field definitions. When they arrive, `_hasCustomFieldsStep`
    // may flip and the wizard needs to rebuild so the step appears.
    _customFieldsProvider.addListener(_onCustomFieldsChanged);
    _customFieldsProvider.load(workspaceId);
    _applyTemplateIfPresent();
    _addressController.addListener(_onAddressChanged);
    _nameController.addListener(_markDirty);
    _descriptionController.addListener(_markDirty);
    _addressController.addListener(_markDirty);
    _budgetController.addListener(_markDirty);
    if (_isEditMode) {
      _loadProject().then((_) => _initialLoadComplete = true);
    } else {
      _initialLoadComplete = true;
    }
  }

  /// Pre-fill wizard fields from a template if one was provided.
  void _applyTemplateIfPresent() {
    final template = widget.template;
    if (template == null) return;

    final settings = template.settings;

    // Description
    if (settings.description != null && settings.description!.isNotEmpty) {
      _descriptionController.text = settings.description!;
    }

    // Job type
    if (settings.jobType != null) {
      try {
        _selectedJobType = JobType.fromString(settings.jobType!);
      } catch (_) {}
    }

    // Price type
    if (settings.priceType != null) {
      _selectedPriceType = PriceType.fromString(settings.priceType!);
    }

    // Markups
    if (settings.materialMarkupPercent != null) {
      _materialMarkupController.text = settings.materialMarkupPercent!
          .toStringAsFixed(0);
    }
    if (settings.laborMarkupPercent != null) {
      _laborMarkupController.text = settings.laborMarkupPercent!
          .toStringAsFixed(0);
    }

    // Budget
    if (settings.estimatedBudget != null) {
      _budgetController.text = settings.estimatedBudget!.toStringAsFixed(2);
    }

    // Contract / cost-plus
    if (settings.contractAmount != null) {
      _contractAmountController.text = settings.contractAmount!.toStringAsFixed(
        2,
      );
    }
    if (settings.costPlusType != null) {
      _selectedCostPlusType = CostPlusType.fromString(settings.costPlusType!);
    }
    if (settings.costPlusValue != null) {
      _costPlusValueController.text = settings.costPlusValue!.toStringAsFixed(
        2,
      );
    }
  }

  Future<void> _loadWorkspaceUsers(String workspaceId) async {
    try {
      final members = await _workspaceMemberService
          .getWorkspaceMembers(workspaceId)
          .first;
      final List<AppUser> users = [];
      for (final member in members) {
        final user = await _userService.getUserById(member.userId);
        if (user != null) {
          users.add(user);
        }
      }
      if (mounted) {
        setState(() {
          _workspaceUsers = users;
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  Future<void> _loadWorkspaceCountryCode(String workspaceId) async {
    try {
      final data = await ServiceLocator.workspaceService
          .getWorkspace(workspaceId)
          .first;
      if (data == null || !mounted) return;
      final country = data['companyCountry'] as String?;
      if (country != null) {
        _workspaceCountryCode = CountryList.findCountryCodeByName(country);
      }
    } catch (_) {}
  }

  Future<void> _loadProject() async {
    setState(() => _isLoading = true);
    try {
      final project = await ServiceLocator.projectService.getProject(
        widget.projectId!,
      );
      if (project != null && mounted) {
        setState(() {
          _existingProject = project;
          _nameController.text = project.name;
          _addressController.text = project.address.trim();
          _descriptionController.text = project.description ?? '';
          _locationDetailsController.text = project.locationDetails ?? '';
          _selectedJobType = project.jobType;
          _photoUrl = project.photoUrl;
          _selectedCustomerId = project.clientId;
          _selectedCustomerLocationId = project.customerLocationId;
          if (project.customerLocationId != null) {
            _selectedLocationAddress = project.address.trim();
          }
          _selectedVendorSubdivisionId = project.vendorSubdivisionId;
          if (project.clientId != null) {
            _customerLocationsFuture = ServiceLocator.customerLocationService
                .getLocationsForCustomer(project.clientId!);
          }
          _customerName = normalizeProjectCustomerName(project.customerName);
          _selectedProjectManagerId = project.projectManagerId;
          _selectedSupervisorId = project.supervisorId;
          _selectedSalespersonId = project.salespersonId;
          _selectedTeamMemberIds = List<String>.from(project.teamMemberIds);
          _primaryContactNameController.text = project.primaryContactName ?? '';
          _primaryContactRoleController.text = project.primaryContactRole ?? '';
          _primaryContactPhoneController.text =
              project.primaryContactPhone ?? '';
          _primaryContactEmailController.text =
              project.primaryContactEmail ?? '';
          _showPrimaryContact =
              _primaryContactNameController.text.isNotEmpty ||
              _primaryContactRoleController.text.isNotEmpty ||
              _primaryContactPhoneController.text.isNotEmpty ||
              _primaryContactEmailController.text.isNotEmpty;

          _selectedPriceType = project.priceType;
          _selectedCostPlusType =
              project.costPlusType ?? CostPlusType.percentage;
          _contractAmountController.text =
              project.contractAmount?.toString() ?? '';
          _costPlusValueController.text =
              project.costPlusValue?.toString() ?? '';
          _budgetController.text = project.estimatedBudget?.toString() ?? '';
          _materialMarkupController.text = project.materialMarkupPercent
              .toString();
          _laborMarkupController.text = project.laborMarkupPercent.toString();
          _purchaseOrderController.text = project.purchaseOrderNumber ?? '';

          _selectedStatus = project.status;
          _selectedStartDate = project.startDate;
          _selectedCompletionDate = project.targetCompletionDate;
          _dateRequestReceived = project.dateRequestReceived;
          _customFieldValues = Map<String, dynamic>.from(project.customFields);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'loading project'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _pageController.dispose();
    _addressSuggestionDebounce?.cancel();
    _addressController.removeListener(_onAddressChanged);
    _nameController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    _locationDetailsController.dispose();
    _primaryContactNameController.dispose();
    _primaryContactRoleController.dispose();
    _primaryContactPhoneController.dispose();
    _primaryContactEmailController.dispose();
    _contractAmountController.dispose();
    _costPlusValueController.dispose();
    _budgetController.dispose();
    _materialMarkupController.dispose();
    _laborMarkupController.dispose();
    _purchaseOrderController.dispose();
    _customFieldsProvider.removeListener(_onCustomFieldsChanged);
    _customFieldsProvider.dispose();
    super.dispose();
  }

  void _onCustomFieldsChanged() {
    if (!mounted) return;
    // The provider has already mutated its list; `_orderedSteps` now
    // returns the new layout. Use the snapshot from the previous build
    // to figure out which kind the user was looking at, then pin to
    // that kind's new position.
    final previous = _lastBuildOrderedSteps;
    final ordered = _orderedSteps;
    _StepKind? currentKind;
    if (_currentStep >= 0 && _currentStep < previous.length) {
      currentKind = previous[_currentStep];
    }
    setState(() {
      int targetIndex = _currentStep;
      if (currentKind != null) {
        final newIndex = ordered.indexOf(currentKind);
        // If the kind the user was on has vanished from the layout
        // (e.g. Custom Fields step disappeared after all active defs
        // were archived), fall back to the last valid step rather
        // than leaving _currentStep pointing past the end.
        targetIndex = newIndex >= 0 ? newIndex : ordered.length - 1;
      }
      if (targetIndex >= ordered.length) {
        targetIndex = ordered.length - 1;
      }
      if (targetIndex < 0) targetIndex = 0;
      if (targetIndex != _currentStep) {
        _currentStep = targetIndex;
        if (!_isEditMode && _pageController.hasClients) {
          _pageController.jumpToPage(targetIndex);
        }
      }
    });
  }

  void _onAddressChanged() {
    if (_isSettingAddressFromSuggestion) return;

    _selectedAddressCoordinates = null;
    final query = _addressController.text.trim();
    _addressSuggestionDebounce?.cancel();

    if (query.length < 3) {
      if (_addressSuggestions.isNotEmpty || _isLoadingAddressSuggestions) {
        setState(() {
          _addressSuggestions = const [];
          _isLoadingAddressSuggestions = false;
        });
      }
      return;
    }

    _addressSuggestionDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchAddressSuggestions(query);
    });
  }

  Future<void> _fetchAddressSuggestions(String query) async {
    if (!mounted) return;
    setState(() => _isLoadingAddressSuggestions = true);

    final suggestions = await _geocodingService.searchAddressSuggestions(
      query,
      countryCode: _workspaceCountryCode,
    );

    if (!mounted) return;
    if (_addressController.text.trim() != query) {
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
    final typedQuery = _addressController.text.trim();
    _addressController.text = suggestion.singleLineAddress(
      typedQuery: typedQuery,
    );
    _addressController.selection = TextSelection.fromPosition(
      TextPosition(offset: _addressController.text.length),
    );
    _selectedAddressCoordinates = (
      latitude: suggestion.latitude,
      longitude: suggestion.longitude,
    );
    setState(() {
      _addressSuggestions = const [];
      _isLoadingAddressSuggestions = false;
    });
    _isSettingAddressFromSuggestion = false;
    FocusScope.of(context).unfocus();
  }

  String? _validationMessageForStep(int step) {
    if (step < 0 || step >= _orderedSteps.length) return null;
    switch (_kindAt(step)) {
      case _StepKind.customer:
        if (_addressController.text.trim().isEmpty) {
          return 'Please enter an address';
        }
        return null;
      case _StepKind.identify:
        if (_nameController.text.trim().isEmpty) {
          return 'Please enter a name';
        }
        return null;
      case _StepKind.team:
        return null;
      case _StepKind.pricing:
        if (_selectedPriceType == PriceType.fixedPrice) {
          if (_contractAmountController.text.trim().isNotEmpty) {
            final amount = double.tryParse(
              _contractAmountController.text.trim(),
            );
            if (amount == null || amount <= 0) {
              return 'Please enter a valid contract amount';
            }
          }
        }
        if (_selectedPriceType == PriceType.costPlus) {
          if (_costPlusValueController.text.trim().isEmpty) {
            return 'Fee value is required for cost plus projects';
          }
          final value = double.tryParse(_costPlusValueController.text.trim());
          if (value == null || value <= 0) {
            return 'Please enter a valid fee value';
          }
        }
        return null;
      case _StepKind.customFields:
        // Required-field validation happens inside the section itself;
        // we don't block wizard navigation on it (required defs can be
        // added to an existing workspace without forcing retroactive
        // fixes on historical drafts).
        return null;
      case _StepKind.review:
        return null;
    }
  }

  bool _validateCurrentStep() {
    final message = _validationMessageForStep(_currentStep);
    if (message != null) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = message;
      });
      _shakeController.forward(from: 0);
      return false;
    }
    return true;
  }

  bool _validateBeforeSubmit() {
    for (var step = 0; step < _totalSteps; step++) {
      final message = _validationMessageForStep(step);
      if (message != null) {
        _goToStep(step);
        setState(() {
          _showFieldErrors = true;
          _validationMessage = message;
        });
        _shakeController.forward(from: 0);
        return false;
      }
    }
    return true;
  }

  void _clearValidationErrors() {
    if (_showFieldErrors) {
      setState(() {
        _showFieldErrors = false;
        _validationMessage = null;
      });
    }
  }

  Widget _buildValidationBanner() {
    if (!_showFieldErrors || _validationMessage == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _validationMessage!,
              style: TextStyle(
                color: AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _goToStep(int step) {
    if (step >= 0 && step < _totalSteps) {
      if (!_isEditMode) {
        _pageController.animateToPage(
          step,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      setState(() {
        _currentStep = step;
        _showFieldErrors = false;
        _validationMessage = null;
      });
    }
  }

  void _nextStep() {
    if (_validateCurrentStep()) {
      if (_currentStep < _totalSteps - 1) {
        _goToStep(_currentStep + 1);
      } else {
        _handleSubmit();
      }
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    }
  }

  void _saveFromEditLayout() {
    if (_validateBeforeSubmit()) {
      _handleSubmit();
    }
  }

  Set<ProjectUpdateField> _buildClearFieldsForUpdate({
    required String address,
    required double? latitude,
    required double? longitude,
    required double? estimatedBudget,
    required double? contractAmount,
    required CostPlusType? costPlusType,
    required double? costPlusValue,
  }) {
    final clearFields = <ProjectUpdateField>{};

    if (_selectedCustomerId == null) {
      clearFields.add(ProjectUpdateField.clientId);
      clearFields.add(ProjectUpdateField.customerName);
      clearFields.add(ProjectUpdateField.customerLocationId);
    }
    if (_selectedCustomerLocationId == null) {
      clearFields.add(ProjectUpdateField.customerLocationId);
    }
    if (_selectedVendorSubdivisionId == null) {
      clearFields.add(ProjectUpdateField.vendorSubdivisionId);
    }
    if (estimatedBudget == null) {
      clearFields.add(ProjectUpdateField.estimatedBudget);
    }
    if (_selectedStartDate == null) {
      clearFields.add(ProjectUpdateField.startDate);
    }
    if (_selectedCompletionDate == null) {
      clearFields.add(ProjectUpdateField.targetCompletionDate);
    }
    if (contractAmount == null) {
      clearFields.add(ProjectUpdateField.contractAmount);
    }
    if (costPlusType == null) {
      clearFields.add(ProjectUpdateField.costPlusType);
    }
    if (costPlusValue == null) {
      clearFields.add(ProjectUpdateField.costPlusValue);
    }
    if (_descriptionController.text.trim().isEmpty) {
      clearFields.add(ProjectUpdateField.description);
    }
    if (_selectedProjectManagerId == null) {
      clearFields.add(ProjectUpdateField.projectManagerId);
    }
    if (_photoUrl == null) {
      clearFields.add(ProjectUpdateField.photoUrl);
    }
    if (_selectedJobType == null) {
      clearFields.add(ProjectUpdateField.jobType);
    }
    if (_purchaseOrderController.text.trim().isEmpty) {
      clearFields.add(ProjectUpdateField.purchaseOrderNumber);
    }
    if (_dateRequestReceived == null) {
      clearFields.add(ProjectUpdateField.dateRequestReceived);
    }
    if (_locationDetailsController.text.trim().isEmpty) {
      clearFields.add(ProjectUpdateField.locationDetails);
    }
    if (_selectedSalespersonId == null) {
      clearFields.add(ProjectUpdateField.salespersonId);
    }
    if (_selectedSupervisorId == null) {
      clearFields.add(ProjectUpdateField.supervisorId);
    }
    if (_primaryContactNameController.text.trim().isEmpty) {
      clearFields.add(ProjectUpdateField.primaryContactName);
    }
    if (_primaryContactRoleController.text.trim().isEmpty) {
      clearFields.add(ProjectUpdateField.primaryContactRole);
    }
    if (_primaryContactPhoneController.text.trim().isEmpty) {
      clearFields.add(ProjectUpdateField.primaryContactPhone);
    }
    if (_primaryContactEmailController.text.trim().isEmpty) {
      clearFields.add(ProjectUpdateField.primaryContactEmail);
    }

    final existingProject = _existingProject;
    final hadCoordinates =
        existingProject?.latitude != null || existingProject?.longitude != null;
    final addressChanged =
        existingProject != null && address != existingProject.address.trim();
    if (addressChanged &&
        hadCoordinates &&
        latitude == null &&
        longitude == null) {
      clearFields.add(ProjectUpdateField.latitude);
      clearFields.add(ProjectUpdateField.longitude);
    }

    return clearFields;
  }

  Future<void> _handleSubmit() async {
    if (!_validateBeforeSubmit()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId == null) {
        throw Exception('No workspace found');
      }

      // Parse budget values
      final estimatedBudget = _budgetController.text.trim().isNotEmpty
          ? double.tryParse(_budgetController.text.trim())
          : null;
      final materialMarkup =
          double.tryParse(_materialMarkupController.text.trim()) ?? 20.0;
      final laborMarkup =
          double.tryParse(_laborMarkupController.text.trim()) ?? 30.0;
      final contractAmount =
          _contractAmountController.text.trim().isNotEmpty &&
              _selectedPriceType == PriceType.fixedPrice
          ? double.tryParse(_contractAmountController.text.trim())
          : null;
      final costPlusType = _selectedPriceType == PriceType.costPlus
          ? _selectedCostPlusType
          : null;
      final costPlusValue =
          _costPlusValueController.text.trim().isNotEmpty &&
              _selectedPriceType == PriceType.costPlus
          ? double.tryParse(_costPlusValueController.text.trim())
          : null;

      // Geocode address unless user selected a suggestion that already has coordinates.
      double? latitude = _selectedAddressCoordinates?.latitude;
      double? longitude = _selectedAddressCoordinates?.longitude;
      final address = _addressController.text.trim();
      if (address.isNotEmpty && (latitude == null || longitude == null)) {
        try {
          final coordinates = await _geocodingService.geocodeAddress(address);
          if (coordinates != null) {
            latitude = coordinates.latitude;
            longitude = coordinates.longitude;
          }
        } catch (e) {
          // Continue without coordinates
        }
      }

      final clearFields = _isEditMode
          ? _buildClearFieldsForUpdate(
              address: address,
              latitude: latitude,
              longitude: longitude,
              estimatedBudget: estimatedBudget,
              contractAmount: contractAmount,
              costPlusType: costPlusType,
              costPlusValue: costPlusValue,
            )
          : const <ProjectUpdateField>{};

      if (_isEditMode) {
        await ServiceLocator.projectService.updateProject(
          projectId: widget.projectId!,
          name: _nameController.text.trim(),
          address: address,
          status: _selectedStatus,
          clientId: _selectedCustomerId,
          customerName: _customerName,
          estimatedBudget: estimatedBudget,
          materialMarkupPercent: materialMarkup,
          laborMarkupPercent: laborMarkup,
          startDate: _selectedStartDate,
          targetCompletionDate: _selectedCompletionDate,
          priceType: _selectedPriceType,
          contractAmount: contractAmount,
          costPlusType: costPlusType,
          costPlusValue: costPlusValue,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          projectManagerId: _selectedProjectManagerId,
          latitude: latitude,
          longitude: longitude,
          photoUrl: _photoUrl,
          jobType: _selectedJobType,
          purchaseOrderNumber: _purchaseOrderController.text.trim().isEmpty
              ? null
              : _purchaseOrderController.text.trim(),
          dateRequestReceived: _dateRequestReceived,
          locationDetails: _locationDetailsController.text.trim().isEmpty
              ? null
              : _locationDetailsController.text.trim(),
          salespersonId: _selectedSalespersonId,
          supervisorId: _selectedSupervisorId,
          primaryContactName: _primaryContactNameController.text.trim().isEmpty
              ? null
              : _primaryContactNameController.text.trim(),
          primaryContactRole: _primaryContactRoleController.text.trim().isEmpty
              ? null
              : _primaryContactRoleController.text.trim(),
          primaryContactPhone:
              _primaryContactPhoneController.text.trim().isEmpty
              ? null
              : _primaryContactPhoneController.text.trim(),
          primaryContactEmail:
              _primaryContactEmailController.text.trim().isEmpty
              ? null
              : _primaryContactEmailController.text.trim(),
          customerLocationId: _selectedCustomerLocationId,
          vendorSubdivisionId: _selectedVendorSubdivisionId,
          teamMemberIds: _selectedTeamMemberIds,
          customFields: _customFieldValues,
          clearFields: clearFields,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_singularTerminology(context, listen: false)} updated successfully!',
              ),
              backgroundColor: AppColors.success,
            ),
          );
          widget.onComplete?.call();
          Navigator.of(context).pop();
        }
      } else {
        final newProject = await ServiceLocator.projectService.createProject(
          workspaceId: workspaceId,
          name: _nameController.text.trim(),
          address: address,
          status: _selectedStatus,
          clientId: _selectedCustomerId,
          customerName: _customerName,
          estimatedBudget: estimatedBudget,
          materialMarkupPercent: materialMarkup,
          laborMarkupPercent: laborMarkup,
          startDate: _selectedStartDate,
          targetCompletionDate: _selectedCompletionDate,
          priceType: _selectedPriceType,
          contractAmount: contractAmount,
          costPlusType: costPlusType,
          costPlusValue: costPlusValue,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          projectManagerId: _selectedProjectManagerId,
          latitude: latitude,
          longitude: longitude,
          photoUrl: _photoUrl,
          jobType: _selectedJobType,
          purchaseOrderNumber: _purchaseOrderController.text.trim().isEmpty
              ? null
              : _purchaseOrderController.text.trim(),
          dateRequestReceived: _dateRequestReceived,
          locationDetails: _locationDetailsController.text.trim().isEmpty
              ? null
              : _locationDetailsController.text.trim(),
          salespersonId: _selectedSalespersonId,
          supervisorId: _selectedSupervisorId,
          primaryContactName: _primaryContactNameController.text.trim().isEmpty
              ? null
              : _primaryContactNameController.text.trim(),
          primaryContactRole: _primaryContactRoleController.text.trim().isEmpty
              ? null
              : _primaryContactRoleController.text.trim(),
          primaryContactPhone:
              _primaryContactPhoneController.text.trim().isEmpty
              ? null
              : _primaryContactPhoneController.text.trim(),
          primaryContactEmail:
              _primaryContactEmailController.text.trim().isEmpty
              ? null
              : _primaryContactEmailController.text.trim(),
          customerLocationId: _selectedCustomerLocationId,
          vendorSubdivisionId: _selectedVendorSubdivisionId,
          teamMemberIds: _selectedTeamMemberIds,
          customFields: _customFieldValues,
        );

        if (mounted) {
          // If we have a template, apply tasks and budget items to new project
          if (widget.template != null) {
            try {
              // Apply tasks
              if (widget.template!.tasks.isNotEmpty) {
                for (final templateTask in widget.template!.tasks) {
                  // Use task service to insert
                  await ServiceLocator.taskService.createTask(
                    workspaceId: workspaceId,
                    projectId: newProject.id,
                    title: templateTask.title,
                    description: templateTask.description,
                    sortOrder: templateTask.sortOrder.toDouble(),
                  );
                }
              }
            } catch (e) {
              // Non-fatal: project was created, template data may partially apply
            }
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_singularTerminology(context, listen: false)} created successfully!',
              ),
              backgroundColor: AppColors.success,
            ),
          );

          // Ask about AI setup before closing wizard (context is still valid)
          final useAi = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              icon: const Icon(
                Icons.auto_awesome,
                color: AppColors.secondaryDark,
                size: 36,
              ),
              title: const Text('Set Up with AI?'),
              content: Text(
                'Would you like AI to generate phases, tasks, and budget items for this ${_singularTerminology(context, listen: false).toLowerCase()}?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Skip'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Set Up with AI'),
                ),
              ],
            ),
          );

          if (!mounted) return;

          widget.onComplete?.call();
          Navigator.of(context).pop();
          // Navigate with aiSetup flag so the detail screen can show the wizard
          if (useAi == true) {
            context.go('/projects/${newProject.id}?aiSetup=true');
          } else {
            context.go('/projects/${newProject.id}');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(
                e,
                action: _isEditMode
                    ? 'saving ${_singularTerminology(context, listen: false).toLowerCase()}'
                    : 'creating ${_singularTerminology(context, listen: false).toLowerCase()}',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadProjectPhoto() async {
    try {
      final workspaceId = Provider.of<AuthProvider>(
        context,
        listen: false,
      ).appUser?.currentWorkspaceId;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('Selected file has no readable bytes');
      }
      const maxPhotoSizeBytes = 10 * 1024 * 1024;
      if (bytes.length > maxPhotoSizeBytes) {
        throw Exception('Photo size must be less than 10MB');
      }

      if (!mounted) return;

      setState(() => _isUploadingPhoto = true);

      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final projectId = widget.projectId ?? 'temp_$timestamp';
        final contentType = lookupMimeType(file.name) ?? 'image/jpeg';
        late final String downloadUrl;

        if (workspaceId == null || workspaceId.isEmpty) {
          throw Exception('No active workspace found for image upload');
        }
        final storagePath =
            '$workspaceId/projects/$projectId/photo_$timestamp.jpg';
        final supabase = Supabase.instance.client;

        await supabase.storage
            .from('project-images')
            .uploadBinary(
              storagePath,
              bytes,
              fileOptions: FileOptions(contentType: contentType),
            );
        downloadUrl = supabase.storage
            .from('project-images')
            .getPublicUrl(storagePath);

        if (widget.projectId != null) {
          await ServiceLocator.projectService.updateProjectPhoto(
            widget.projectId!,
            downloadUrl,
          );
        }

        setState(() {
          _photoUrl = downloadUrl;
          _isUploadingPhoto = false;
        });
      } catch (e) {
        setState(() => _isUploadingPhoto = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'uploading photo'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'selecting photo'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleCustomerPickerResult(List<Customer> customers) async {
    final result = await showAdaptiveSheet<_CustomerPickerResult>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _CustomerPickerSheet(
        customers: customers,
        currentCustomerId: _selectedCustomerId,
      ),
    );
    if (result == null || !mounted) return;
    switch (result) {
      case _CustomerPickerAddNew():
        final newCustomerId = await _showAddCustomerDialog();
        if (newCustomerId != null) {
          setState(() => _selectedCustomerId = newCustomerId);
          _loadNewCustomerName(newCustomerId);
        }
      case _CustomerPickerCleared():
        _clearSelectedCustomer();
      case _CustomerPickerSelected(:final customer):
        _selectCustomer(customer);
    }
  }

  void _clearSelectedCustomer() {
    setState(() {
      _selectedCustomerId = null;
      _customerName = null;
      _selectedCustomerLocationId = null;
      _selectedLocationAddress = null;
      _customerLocationsFuture = null;
    });
  }

  void _selectCustomer(Customer customer) {
    setState(() {
      _selectedCustomerId = customer.id;
      _customerName = customer.businessDisplayName;
      _selectedCustomerLocationId = null;
      _selectedLocationAddress = null;
      _customerLocationsFuture = ServiceLocator.customerLocationService
          .getLocationsForCustomer(customer.id);
    });
  }

  Future<String?> _showAddCustomerDialog() async {
    final nameController = TextEditingController();
    final companyController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? newCustomerId;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Customer'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StackedField(
                  label: 'Name *',
                  child: TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Name is required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 12),
                StackedField(
                  label: 'Company Name (Optional)',
                  child: TextFormField(
                    controller: companyController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                StackedField(
                  label: 'Email (Optional)',
                  child: TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(height: 12),
                StackedField(
                  label: 'Phone (Optional)',
                  child: TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Create Customer'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final workspaceId = Provider.of<AuthProvider>(
          context,
          listen: false,
        ).appUser!.currentWorkspaceId;
        final customer = await _customerService.createCustomer(
          workspaceId: workspaceId,
          name: nameController.text.trim(),
          companyName: companyController.text.trim().isEmpty
              ? null
              : companyController.text.trim(),
          email: emailController.text.trim().isEmpty
              ? null
              : emailController.text.trim(),
          phone: phoneController.text.trim().isEmpty
              ? null
              : phoneController.text.trim(),
        );
        newCustomerId = customer.id;
        _customerName = customer.businessDisplayName;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'creating customer'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }

    nameController.dispose();
    companyController.dispose();
    emailController.dispose();
    phoneController.dispose();

    return newCustomerId;
  }

  Future<void> _loadNewCustomerName(String customerId) async {
    final customer = await _customerService.getCustomer(customerId);
    if (customer != null && mounted) {
      setState(() {
        _customerName = customer.businessDisplayName;
        _customerLocationsFuture = ServiceLocator.customerLocationService
            .getLocationsForCustomer(customerId);
      });
    }
  }

  Future<void> _showAddLocationDialog() async {
    if (_selectedCustomerId == null) return;
    final workspaceId = Provider.of<AuthProvider>(
      context,
      listen: false,
    ).appUser!.currentWorkspaceId;

    final customer = await _customerService.getCustomer(_selectedCustomerId!);
    if (customer == null || !mounted) return;

    String? createdLocationId;
    CustomerLocation? savedLocation;
    await showDialog<void>(
      context: context,
      builder: (context) => CustomerLocationForm(
        workspaceId: workspaceId,
        customerId: _selectedCustomerId!,
        contacts: customer.contacts
            .where((contact) => contact.isActive)
            .toList(),
        onSave: (location) async {
          createdLocationId = await ServiceLocator.customerLocationService
              .createLocation(location);
          savedLocation = location;
        },
      ),
    );

    if (createdLocationId != null && mounted) {
      setState(() {
        _customerLocationsFuture = ServiceLocator.customerLocationService
            .getLocationsForCustomer(_selectedCustomerId!);
        _selectedCustomerLocationId = createdLocationId;
        _selectedLocationAddress = savedLocation?.fullAddress;
        if (savedLocation?.fullAddress != null) {
          _addressController.text = savedLocation!.fullAddress!;
        }
      });
    }
  }

  Future<void> _showCreateLocationFromAddress() async {
    if (_selectedCustomerId == null) return;
    final workspaceId = Provider.of<AuthProvider>(
      context,
      listen: false,
    ).appUser!.currentWorkspaceId;

    final customer = await _customerService.getCustomer(_selectedCustomerId!);
    if (customer == null || !mounted) return;

    final now = DateTime.now();
    final initialLocation = CustomerLocation(
      id: '',
      workspaceId: workspaceId,
      customerId: _selectedCustomerId!,
      name: '',
      address: _addressController.text.trim(),
      createdAt: now,
      updatedAt: now,
    );

    String? createdLocationId;
    CustomerLocation? savedLocation;
    await showDialog<void>(
      context: context,
      builder: (context) => CustomerLocationForm(
        workspaceId: workspaceId,
        customerId: _selectedCustomerId!,
        initialLocation: initialLocation,
        contacts: customer.contacts
            .where((contact) => contact.isActive)
            .toList(),
        onSave: (location) async {
          createdLocationId = await ServiceLocator.customerLocationService
              .createLocation(location);
          savedLocation = location;
        },
      ),
    );

    if (createdLocationId != null && mounted) {
      setState(() {
        _customerLocationsFuture = ServiceLocator.customerLocationService
            .getLocationsForCustomer(_selectedCustomerId!);
        _selectedCustomerLocationId = createdLocationId;
        _selectedLocationAddress = savedLocation?.fullAddress;
        if (savedLocation?.fullAddress != null) {
          _addressController.text = savedLocation!.fullAddress!;
        }
      });
    }
  }

  Future<void> _selectDate(String type) async {
    final now = DateTime.now();
    DateTime? initialDate;
    DateTime firstDate;
    DateTime lastDate = now.add(const Duration(days: 365 * 5));

    switch (type) {
      case 'start':
        initialDate = _selectedStartDate ?? now;
        firstDate = now.subtract(const Duration(days: 365));
        break;
      case 'completion':
        initialDate = _selectedCompletionDate ?? _selectedStartDate ?? now;
        firstDate =
            _selectedStartDate ?? now.subtract(const Duration(days: 365));
        break;
      case 'request':
        initialDate = _dateRequestReceived ?? now;
        firstDate = now.subtract(const Duration(days: 365));
        break;
      default:
        return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (picked != null) {
      setState(() {
        switch (type) {
          case 'start':
            _selectedStartDate = picked;
            if (_selectedCompletionDate != null &&
                _selectedCompletionDate!.isBefore(picked)) {
              _selectedCompletionDate = null;
            }
            break;
          case 'completion':
            _selectedCompletionDate = picked;
            break;
          case 'request':
            _dateRequestReceived = picked;
            break;
        }
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final orderedSteps = _orderedSteps;
    _lastBuildOrderedSteps = orderedSteps;
    final pages = orderedSteps.map(_buildStepContent).toList();

    if (_isEditMode) {
      return Column(
        children: [
          _buildEditHeader(theme),
          Expanded(
            child: IndexedStack(index: _currentStep, children: pages),
          ),
          _buildEditNavigationBar(theme),
        ],
      );
    }

    return Column(
      children: [
        // Header with step indicator
        _buildHeader(theme, primaryColor),

        // Step content
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (index) => setState(() => _currentStep = index),
            children: pages,
          ),
        ),

        // Navigation buttons
        _buildNavigationBar(primaryColor),
      ],
    );
  }

  Widget _buildStepContent(_StepKind kind) {
    switch (kind) {
      case _StepKind.customer:
        return _buildStep1CustomerLocation();
      case _StepKind.identify:
        return _buildStep2IdentifyProject();
      case _StepKind.team:
        return _buildStep3Team();
      case _StepKind.pricing:
        return _buildStep4Pricing();
      case _StepKind.customFields:
        return _buildCustomFieldsStep();
      case _StepKind.review:
        return _buildStep5ReviewCreate();
    }
  }

  Widget _buildEditHeader(ThemeData theme) {
    final primaryColor = theme.colorScheme.primary;
    final steps = _buildSteps(_singularTerminology(context));
    final currentConfig = steps[_currentStep];
    final sectionTitle = _currentStep == _totalSteps - 1
        ? 'Timeline & Status'
        : currentConfig.title;
    final sectionSubtitle = _currentStep == _totalSteps - 1
        ? 'Update timing, status, and review the summary before saving'
        : currentConfig.subtitle;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_totalSteps, (index) {
                return _buildEditTabChip(
                  index: index,
                  icon: steps[index].icon,
                  label: _editTabLabels[index],
                );
              }),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(currentConfig.icon, color: primaryColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sectionTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sectionSubtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditTabChip({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final isSelected = _currentStep == index;

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
              : theme.colorScheme.onSurface.withValues(alpha: 0.65),
        ),
        label: Text(label),
        onSelected: (_) => _goToStep(index),
      ),
    );
  }

  Widget _buildEditNavigationBar(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: AppColors.cardBorder)),
        ),
        child: Row(
          children: [
            TextButton(
              onPressed: () {
                widget.onCancel?.call();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            const Spacer(),
            AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                final dx = _shakeController.isAnimating
                    ? math.sin(_shakeController.value * math.pi * 4) * 6
                    : 0.0;
                return Transform.translate(offset: Offset(dx, 0), child: child);
              },
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _saveFromEditLayout,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: const Text('Save Changes'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.md,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, Color primaryColor) {
    final steps = _buildSteps(_singularTerminology(context));
    final stepTitle = _currentStep == _totalSteps - 1 && _isEditMode
        ? 'Review & Update'
        : steps[_currentStep].title;
    final stepSubtitle = _currentStep == _totalSteps - 1 && _isEditMode
        ? 'Review your updates before saving'
        : steps[_currentStep].subtitle;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        children: [
          // Step indicator
          Row(
            children: List.generate(_totalSteps * 2 - 1, (index) {
              if (index.isOdd) {
                // Connector line
                final stepIndex = index ~/ 2;
                final isCompleted = stepIndex < _currentStep;
                return Expanded(
                  child: Container(
                    height: 2,
                    color: isCompleted ? primaryColor : AppColors.cardBorder,
                  ),
                );
              } else {
                // Step circle
                final stepIndex = index ~/ 2;
                final isCompleted = stepIndex < _currentStep;
                final isCurrent = stepIndex == _currentStep;
                return _buildStepCircle(
                  stepIndex + 1,
                  isCompleted: isCompleted,
                  isCurrent: isCurrent,
                  primaryColor: primaryColor,
                );
              }
            }),
          ),
          const SizedBox(height: 20),
          // Step title and subtitle
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  steps[_currentStep].icon,
                  color: primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_currentStep + 1}. $stepTitle',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stepSubtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepCircle(
    int number, {
    required bool isCompleted,
    required bool isCurrent,
    required Color primaryColor,
  }) {
    final isActive = isCompleted || isCurrent;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? primaryColor : Colors.transparent,
        border: Border.all(
          color: isActive ? primaryColor : onSurface.withValues(alpha: 0.45),
          width: 2,
        ),
      ),
      child: Center(
        child: isCompleted
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : Text(
                '$number',
                style: TextStyle(
                  color: isActive ? Colors.white : onSurface.withValues(alpha: 0.65),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }

  Widget _buildNavigationBar(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          // Back button
          if (_currentStep > 0)
            TextButton.icon(
              onPressed: _previousStep,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Back'),
            )
          else
            TextButton(
              onPressed: () {
                widget.onCancel?.call();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
          const Spacer(),
          // Next/Create button with shake animation
          AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) {
              final dx = _shakeController.isAnimating
                  ? math.sin(_shakeController.value * math.pi * 4) * 6
                  : 0.0;
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _nextStep,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _currentStep == _totalSteps - 1
                          ? Icons.check
                          : Icons.arrow_forward,
                    ),
              label: Text(
                _currentStep == _totalSteps - 1
                    ? (_isEditMode
                          ? 'Save Changes'
                          : 'Create ${_singularTerminology(context)}')
                    : 'Next',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STEP 2: IDENTIFY PROJECT ====================

  Widget _buildStep2IdentifyProject() {
    final nameEmpty = _showFieldErrors && _nameController.text.trim().isEmpty;
    return SingleChildScrollView(
      controller: _currentStep == 1 ? widget.scrollController : null,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentStep == 1) _buildValidationBanner(),
          // Project Name
          _buildFieldLabel(
            '${_singularTerminology(context)} Name',
            required: true,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            onChanged: (_) => _clearValidationErrors(),
            decoration: InputDecoration(
              hintText:
                  'Enter ${_singularTerminology(context).toLowerCase()} name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.business),
              errorText: nameEmpty ? 'Name is required' : null,
            ),
          ),
          const SizedBox(height: 20),

          // Job Type — explicitly marked Optional so the "(Required)" label
          // on Job Name doesn't make Job Type look required by contrast.
          _buildFieldLabel('Job Type', optional: true),
          const SizedBox(height: 8),
          DropdownButtonFormField<JobType>(
            borderRadius: AppRadius.cardRadius,
            value: _selectedJobType,
            decoration: const InputDecoration(
              hintText: 'Select job type',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.category),
            ),
            items: [
              // Soft placeholder for the "skip" option — was "No job type
              // selected" which looked like a required-but-unfilled state
              // even though Job Type is optional.
              const DropdownMenuItem<JobType>(
                value: null,
                child: Text(
                  '— None —',
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ),
              ...JobType.values.map((type) {
                return DropdownMenuItem<JobType>(
                  value: type,
                  child: Row(
                    children: [
                      Icon(type.icon, size: 18, color: type.color),
                      const SizedBox(width: 8),
                      Text(type.displayName),
                    ],
                  ),
                );
              }),
            ],
            onChanged: (value) => setState(() => _selectedJobType = value),
          ),
          const SizedBox(height: 20),

          // Description
          _buildFieldLabel('Description', required: false),
          const SizedBox(height: 8),
          TextFormField(
            controller: _descriptionController,
            decoration: InputDecoration(
              hintText:
                  'Describe the ${_singularTerminology(context).toLowerCase()} scope and details...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 4,
          ),
          const SizedBox(height: 20),

          // Project Photo
          _buildFieldLabel(
            '${_singularTerminology(context)} Photo',
            required: false,
          ),
          const SizedBox(height: 8),
          if (_photoUrl != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: CachedNetworkImage(
                    imageUrl: _photoUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                        color: Colors.white,
                        onPressed: _uploadProjectPhoto,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.error,
                        ),
                        color: Colors.white,
                        onPressed: () => setState(() => _photoUrl = null),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: _isUploadingPhoto ? null : _uploadProjectPhoto,
              icon: _isUploadingPhoto
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate),
              label: Text(_isUploadingPhoto ? 'Uploading...' : 'Upload Photo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 40),
                minimumSize: const Size(double.infinity, 100),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== STEP 1: CUSTOMER & SITE ====================

  Widget _buildStep1CustomerLocation() {
    final addressEmpty =
        _showFieldErrors && _addressController.text.trim().isEmpty;
    final addressDiverged =
        _selectedCustomerLocationId != null &&
        _selectedLocationAddress != null &&
        _addressController.text.trim() != _selectedLocationAddress!.trim();
    return SingleChildScrollView(
      controller: _currentStep == 0 ? widget.scrollController : null,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentStep == 0) _buildValidationBanner(),
          // Customer
          _buildFieldLabel('Customer', required: false),
          const SizedBox(height: 8),
          StreamBuilder<List<Customer>>(
            stream: _customersStream,
            builder: (context, snapshot) {
              final customers = snapshot.data ?? [];
              final customerIds = customers.map((c) => c.id).toSet();
              final validatedCustomerId =
                  _selectedCustomerId != null &&
                      customerIds.contains(_selectedCustomerId)
                  ? _selectedCustomerId
                  : null;
              final selectedCustomer = validatedCustomerId == null
                  ? null
                  : customers.firstWhere((c) => c.id == validatedCustomerId);

              return InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => _handleCustomerPickerResult(customers),
                child: InputDecorator(
                  decoration: InputDecoration(
                    hintText: 'Select customer',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person),
                    suffixIcon: selectedCustomer != null
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Clear customer',
                            onPressed: _clearSelectedCustomer,
                          )
                        : const Icon(Icons.search),
                  ),
                  isEmpty: selectedCustomer == null,
                  child: selectedCustomer == null
                      ? null
                      : Text(
                          selectedCustomer.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              );
            },
          ),

          // Saved-location picker (shown when a customer is selected)
          if (_selectedCustomerId != null &&
              _customerLocationsFuture != null) ...[
            const SizedBox(height: 20),
            _buildFieldLabel('Saved location', required: false),
            const SizedBox(height: 8),
            FutureBuilder<List<CustomerLocation>>(
              future: _customerLocationsFuture,
              builder: (context, locSnapshot) {
                final locations = locSnapshot.data ?? [];

                final locationIds = locations.map((l) => l.id).toSet();
                final validatedLocationId =
                    _selectedCustomerLocationId != null &&
                        locationIds.contains(_selectedCustomerLocationId)
                    ? _selectedCustomerLocationId
                    : null;

                return DropdownButtonFormField<String?>(
                  borderRadius: AppRadius.cardRadius,
                  isExpanded: true,
                  value: validatedLocationId,
                  decoration: const InputDecoration(
                    hintText: 'Use a saved location (optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.bookmark_outline),
                    helperText: 'Auto-fills the address below',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No location selected'),
                    ),
                    const DropdownMenuItem<String?>(
                      value: '__add_new_location__',
                      child: Row(
                        children: [
                          Icon(Icons.add_location_alt, size: 20),
                          SizedBox(width: 8),
                          Text(
                            '+ Add New Location',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    ...locations.map((loc) {
                      final subtitle = loc.fullAddress != null
                          ? ' - ${loc.fullAddress}'
                          : '';
                      return DropdownMenuItem<String?>(
                        value: loc.id,
                        child: Text(
                          '${loc.name}$subtitle',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                  ],
                  onChanged: (value) async {
                    if (value == '__add_new_location__') {
                      await _showAddLocationDialog();
                    } else if (value == null) {
                      setState(() {
                        _selectedCustomerLocationId = null;
                        _selectedLocationAddress = null;
                      });
                    } else {
                      final loc = locations.firstWhere((l) => l.id == value);
                      setState(() {
                        _selectedCustomerLocationId = value;
                        _selectedLocationAddress = loc.fullAddress;
                        if (loc.fullAddress != null) {
                          _addressController.text = loc.fullAddress!;
                        }
                      });
                    }
                  },
                );
              },
            ),
          ],
          const SizedBox(height: 20),

          // Address
          _buildFieldLabel('Address', required: true),
          const SizedBox(height: 8),
          TextFormField(
            controller: _addressController,
            onChanged: (_) => _clearValidationErrors(),
            decoration: InputDecoration(
              hintText:
                  'Enter ${_singularTerminology(context).toLowerCase()} address',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_on),
              errorText: addressEmpty ? 'Address is required' : null,
            ),
            maxLines: 2,
          ),
          if (_isLoadingAddressSuggestions)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.cardBorder),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Searching addresses...'),
                ],
              ),
            ),
          if (_addressSuggestions.isNotEmpty)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.cardBorder),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                color: Colors.white,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _addressSuggestions.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppColors.cardBorder),
                itemBuilder: (context, index) {
                  final suggestion = _addressSuggestions[index];
                  final condensedSuggestion = suggestion.singleLineAddress(
                    typedQuery: _addressController.text.trim(),
                  );
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined, size: 18),
                    title: Text(
                      condensedSuggestion,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectAddressSuggestion(suggestion),
                  );
                },
              ),
            ),
          if (addressDiverged) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Address differs from selected location',
                      style: TextStyle(fontSize: 13, color: AppColors.warning),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showCreateLocationFromAddress,
                    icon: const Icon(Icons.add_location_alt, size: 16),
                    label: const Text('Create Location'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Location Details
          _buildFieldLabel('Location Details', required: false),
          const SizedBox(height: 8),
          TextFormField(
            controller: _locationDetailsController,
            decoration: const InputDecoration(
              hintText: 'e.g., Unit 5, Floor 3, Building A',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.pin_drop),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STEP 3: TEAM ====================

  Widget _buildStep3Team() {
    return SingleChildScrollView(
      controller: _currentStep == 2 ? widget.scrollController : null,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Project Manager
          _buildFieldLabel(
            '${_singularTerminology(context)} Manager',
            required: false,
          ),
          const SizedBox(height: 8),
          _isLoadingUsers
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<String>(
                  borderRadius: AppRadius.cardRadius,
                  value: _selectedProjectManagerId,
                  decoration: InputDecoration(
                    hintText:
                        'Select ${_singularTerminology(context).toLowerCase()} manager',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('No manager assigned'),
                    ),
                    ..._workspaceUsers.map((user) {
                      return DropdownMenuItem<String>(
                        value: user.id,
                        child: Row(
                          children: [
                            UserAvatar(
                              user: user,
                              size: AvatarSize.small,
                              onTap: null,
                              navigable: false,
                            ),
                            const SizedBox(width: 8),
                            Text(user.displayName ?? user.email),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedProjectManagerId = value),
                ),
          const SizedBox(height: 20),

          // Supervisor
          _buildFieldLabel('Supervisor', required: false),
          const SizedBox(height: 8),
          _isLoadingUsers
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<String>(
                  borderRadius: AppRadius.cardRadius,
                  value: _selectedSupervisorId,
                  decoration: const InputDecoration(
                    hintText: 'Select supervisor',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.supervisor_account),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('No supervisor assigned'),
                    ),
                    ..._workspaceUsers.map((user) {
                      return DropdownMenuItem<String>(
                        value: user.id,
                        child: Row(
                          children: [
                            UserAvatar(
                              user: user,
                              size: AvatarSize.small,
                              onTap: null,
                              navigable: false,
                            ),
                            const SizedBox(width: 8),
                            Text(user.displayName ?? user.email),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedSupervisorId = value),
                ),
          const SizedBox(height: 20),

          // Salesperson
          _buildFieldLabel('Salesperson', required: false),
          const SizedBox(height: 8),
          _isLoadingUsers
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<String>(
                  borderRadius: AppRadius.cardRadius,
                  value: _selectedSalespersonId,
                  decoration: const InputDecoration(
                    hintText: 'Select salesperson',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_pin),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('No salesperson assigned'),
                    ),
                    ..._workspaceUsers.map((user) {
                      return DropdownMenuItem<String>(
                        value: user.id,
                        child: Row(
                          children: [
                            UserAvatar(
                              user: user,
                              size: AvatarSize.small,
                              onTap: null,
                              navigable: false,
                            ),
                            const SizedBox(width: 8),
                            Text(user.displayName ?? user.email),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedSalespersonId = value),
                ),
          const SizedBox(height: 20),

          // Team Members
          _buildFieldLabel('Team Members', required: false),
          const SizedBox(height: 8),
          if (_selectedTeamMemberIds.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedTeamMemberIds.map((userId) {
                final user = _workspaceUsers.firstWhere(
                  (u) => u.id == userId,
                  orElse: () => AppUser(
                    id: userId,
                    email: 'Unknown',
                    displayName: 'Unknown User',
                    workspaceId: '',
                    role: UserRole.fieldTechnician,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ),
                );
                return Chip(
                  avatar: UserAvatar(
                    user: user,
                    size: AvatarSize.small,
                    onTap: null,
                    navigable: false,
                  ),
                  label: Text(user.displayName ?? user.email),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () =>
                      setState(() => _selectedTeamMemberIds.remove(userId)),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          if (!_isLoadingUsers)
            DropdownButtonFormField<String>(
              borderRadius: AppRadius.cardRadius,
              value: null,
              decoration: const InputDecoration(
                hintText: 'Add team member...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_add),
              ),
              items: _workspaceUsers
                  .where((user) => !_selectedTeamMemberIds.contains(user.id))
                  .map((user) {
                    return DropdownMenuItem<String>(
                      value: user.id,
                      child: Row(
                        children: [
                          UserAvatar(
                            user: user,
                            size: AvatarSize.small,
                            onTap: null,
                            navigable: false,
                          ),
                          const SizedBox(width: 8),
                          Text(user.displayName ?? user.email),
                        ],
                      ),
                    );
                  })
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedTeamMemberIds.add(value));
                }
              },
            ),
          const SizedBox(height: 20),

          // Primary Contact (collapsible)
          InkWell(
            onTap: () =>
                setState(() => _showPrimaryContact = !_showPrimaryContact),
            child: Row(
              children: [
                Icon(
                  _showPrimaryContact ? Icons.expand_less : Icons.expand_more,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Primary Contact (Optional)',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (_showPrimaryContact) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: StackedField(
                    label: 'Name',
                    child: TextFormField(
                      controller: _primaryContactNameController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StackedField(
                    label: 'Role',
                    child: TextFormField(
                      controller: _primaryContactRoleController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StackedField(
                    label: 'Phone',
                    child: TextFormField(
                      controller: _primaryContactPhoneController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StackedField(
                    label: 'Email',
                    child: TextFormField(
                      controller: _primaryContactEmailController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ==================== STEP 4: PRICING ====================

  Widget _buildStep4Pricing() {
    final costPlusFeeEmpty =
        _showFieldErrors &&
        _selectedPriceType == PriceType.costPlus &&
        _costPlusValueController.text.trim().isEmpty;
    final costPlusFeeInvalid =
        _showFieldErrors &&
        _selectedPriceType == PriceType.costPlus &&
        _costPlusValueController.text.trim().isNotEmpty &&
        (double.tryParse(_costPlusValueController.text.trim()) == null ||
            double.tryParse(_costPlusValueController.text.trim())! <= 0);
    return SingleChildScrollView(
      controller: _currentStep == 3 ? widget.scrollController : null,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentStep == 3) _buildValidationBanner(),

          // Price Type - Segmented Button Style
          _buildFieldLabel('Pricing Model', required: true),
          const SizedBox(height: 8),
          _buildPriceTypeSelector(),
          const SizedBox(height: 20),

          // Conditional: Contract Amount for Fixed Price
          if (_selectedPriceType == PriceType.fixedPrice) ...[
            _buildFieldLabel('Contract Amount', required: false),
            const SizedBox(height: 8),
            TextFormField(
              controller: _contractAmountController,
              onChanged: (_) => _clearValidationErrors(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: 'Enter contract amount',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.attach_money),
                errorText:
                    _showFieldErrors &&
                        _contractAmountController.text.trim().isNotEmpty &&
                        (double.tryParse(
                                  _contractAmountController.text.trim(),
                                ) ==
                                null ||
                            double.tryParse(
                                  _contractAmountController.text.trim(),
                                )! <=
                                0)
                    ? 'Please enter a valid contract amount'
                    : null,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Conditional: Cost Plus fields
          if (_selectedPriceType == PriceType.costPlus) ...[
            _buildFieldLabel('Cost Plus Type', required: true),
            const SizedBox(height: 8),
            SegmentedButton<CostPlusType>(
              segments: CostPlusType.values.map((type) {
                return ButtonSegment(
                  value: type,
                  label: Text(type.displayName),
                );
              }).toList(),
              selected: {_selectedCostPlusType},
              onSelectionChanged: (selected) {
                setState(() => _selectedCostPlusType = selected.first);
              },
            ),
            const SizedBox(height: 16),
            _buildFieldLabel(
              _selectedCostPlusType == CostPlusType.percentage
                  ? 'Fee Percentage'
                  : 'Fixed Fee Amount',
              required: true,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _costPlusValueController,
              onChanged: (_) => _clearValidationErrors(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: _selectedCostPlusType == CostPlusType.percentage
                    ? 'Enter percentage (e.g., 15)'
                    : 'Enter fixed fee amount',
                border: const OutlineInputBorder(),
                prefixIcon: Icon(
                  _selectedCostPlusType == CostPlusType.percentage
                      ? Icons.percent
                      : Icons.attach_money,
                ),
                errorText: costPlusFeeEmpty
                    ? 'Fee value is required'
                    : costPlusFeeInvalid
                    ? 'Please enter a valid fee value'
                    : null,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Estimated Budget
          _buildFieldLabel('Estimated Budget', required: false),
          const SizedBox(height: 8),
          TextFormField(
            controller: _budgetController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: 'Customer-approved budget (optional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.account_balance_wallet),
            ),
          ),
          const SizedBox(height: 20),

          // Markup percentages
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Material Markup %', required: false),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _materialMarkupController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        hintText: '20',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.percent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Labor Markup %', required: false),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _laborMarkupController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        hintText: '30',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.percent),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Purchase Order Number
          _buildFieldLabel('Purchase Order Number', required: false),
          const SizedBox(height: 8),
          TextFormField(
            controller: _purchaseOrderController,
            decoration: const InputDecoration(
              hintText: 'e.g., PO-230930',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.receipt_long),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceTypeSelector() {
    return Column(
      children: PriceType.values.map((priceType) {
        final isSelected = _selectedPriceType == priceType;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => setState(() => _selectedPriceType = priceType),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : AppColors.cardBorder,
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                color: isSelected
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.05)
                    : null,
              ),
              child: Row(
                children: [
                  Radio<PriceType>(
                    value: priceType,
                    groupValue: _selectedPriceType,
                    onChanged: (value) =>
                        setState(() => _selectedPriceType = value!),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          priceType.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          priceType.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ==================== CUSTOM FIELDS (conditional step) ====================

  Widget _buildCustomFieldsStep() {
    final customFieldsIndex = _orderedSteps.indexOf(_StepKind.customFields);
    return SingleChildScrollView(
      controller: _currentStep == customFieldsIndex
          ? widget.scrollController
          : null,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomFieldsSection(
            activeDefinitions: _customFieldsProvider.active,
            allDefinitions: _customFieldsProvider.all,
            values: _customFieldValues,
            onChanged: (v) => _customFieldValues = v,
          ),
        ],
      ),
    );
  }

  // ==================== STEP 5: REVIEW & SUBMIT ====================

  Widget _buildStep5ReviewCreate() {
    return SingleChildScrollView(
      controller: _currentStep == _reviewStepIndex
          ? widget.scrollController
          : null,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline section
          _buildFieldLabel(
            '${_singularTerminology(context)} Status',
            required: false,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<ProjectStatus>(
            borderRadius: AppRadius.cardRadius,
            value: _selectedStatus,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.flag),
            ),
            items: ProjectStatus.values.map((status) {
              return DropdownMenuItem<ProjectStatus>(
                value: status,
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: ProjectStatusTheme.color(status),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: status.displayName),
                            TextSpan(
                              text: '  ${status.shortDescription}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            selectedItemBuilder: (context) {
              return ProjectStatus.values.map((status) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: ProjectStatusTheme.color(status),
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(status.displayName)),
                    ],
                  ),
                );
              }).toList();
            },
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedStatus = value);
              }
            },
          ),
          const SizedBox(height: 20),

          // Dates row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Start Date', required: false),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _selectDate('start'),
                      icon: const Icon(Icons.event),
                      label: Text(
                        _selectedStartDate == null
                            ? 'Set start date'
                            : _formatDate(_selectedStartDate!),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Target Completion', required: false),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _selectDate('completion'),
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        _selectedCompletionDate == null
                            ? 'Set target date'
                            : _formatDate(_selectedCompletionDate!),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // Project Summary Card
          _buildSummaryCard(),
          const SizedBox(height: 20),

          // AI Feedback section (stub)
          if (!_isEditMode) _buildAiFeedbackSection(),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.summarize,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '${_singularTerminology(context)} Summary',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSummaryRow(
            'Name',
            _nameController.text.isEmpty ? '—' : _nameController.text,
          ),
          _buildSummaryRow('Job Type', _selectedJobType?.displayName ?? '—'),
          _buildSummaryRow(
            'Address',
            _addressController.text.isEmpty ? '—' : _addressController.text,
          ),
          _buildSummaryRow('Pricing', _selectedPriceType.displayName),
          if (_selectedPriceType == PriceType.fixedPrice &&
              _contractAmountController.text.isNotEmpty)
            _buildSummaryRow('Contract', '\$${_contractAmountController.text}'),
          if (_budgetController.text.isNotEmpty)
            _buildSummaryRow('Budget', '\$${_budgetController.text}'),
          _buildSummaryRow('Status', _selectedStatus.displayName),
          if (_selectedStartDate != null)
            _buildSummaryRow('Start', _formatDate(_selectedStartDate!)),
          if (_selectedCompletionDate != null)
            _buildSummaryRow('Target', _formatDate(_selectedCompletionDate!)),
          if (_customFieldValues.isNotEmpty)
            _buildSummaryRow(
              'Custom',
              '${_customFieldValues.length} '
                  'field${_customFieldValues.length == 1 ? '' : 's'} set',
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiFeedbackSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.secondaryDark.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.secondaryDark.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: AppColors.secondaryDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI ${_singularTerminology(context)} Setup',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondaryDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'After creating your ${_singularTerminology(context).toLowerCase()}, AI can automatically generate phases, tasks, and budget items based on your ${_singularTerminology(context).toLowerCase()} details.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(
    String label, {
    bool required = false,
    bool optional = false,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          Text(
            'Required',
            style: TextStyle(fontSize: 12, color: AppColors.error),
          ),
        ],
        if (optional && !required) ...[
          const SizedBox(width: 4),
          Text(
            'Optional',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

// Step configuration class
class _StepConfig {
  final int number;
  final String title;
  final String subtitle;
  final IconData icon;

  const _StepConfig({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

sealed class _CustomerPickerResult {
  const _CustomerPickerResult();
}

class _CustomerPickerAddNew extends _CustomerPickerResult {
  const _CustomerPickerAddNew();
}

class _CustomerPickerCleared extends _CustomerPickerResult {
  const _CustomerPickerCleared();
}

class _CustomerPickerSelected extends _CustomerPickerResult {
  final Customer customer;
  const _CustomerPickerSelected(this.customer);
}

class _CustomerPickerSheet extends StatefulWidget {
  final List<Customer> customers;
  final String? currentCustomerId;

  const _CustomerPickerSheet({
    required this.customers,
    required this.currentCustomerId,
  });

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Customer> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.customers;
    return widget.customers.where((c) {
      return c.displayName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    final filtered = _filtered;
    final hasSelection = widget.currentCustomerId != null;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select Customer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (hasSelection)
                    TextButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(const _CustomerPickerCleared()),
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search customers',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ListTile(
                      leading: const Icon(Icons.add_circle),
                      title: const Text(
                        '+ Add New Customer',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () => Navigator.of(
                        context,
                      ).pop(const _CustomerPickerAddNew()),
                    );
                  }
                  final customer = filtered[index - 1];
                  final isSelected = customer.id == widget.currentCustomerId;
                  return ListTile(
                    title: Text(
                      customer.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    selected: isSelected,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_CustomerPickerSelected(customer)),
                  );
                },
              ),
            ),
            if (filtered.isEmpty && _query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Text(
                  'No customers match "$_query"',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
