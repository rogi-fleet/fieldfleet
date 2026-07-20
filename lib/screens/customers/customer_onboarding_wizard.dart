import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../theme/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../services/geocoding_service.dart';
import '../../utils/address_formatter.dart';
import '../../models/customer.dart';
import '../../models/customer_contact.dart';
import '../../models/customer_location.dart';
import '../../models/customer_type_config.dart';
import '../../models/user.dart';
import '../../widgets/customers/customer_type_badge.dart';
import '../../models/customer_status.dart';
import '../../models/customer_source.dart';
import '../../utils/country_list.dart';
import '../../widgets/common/primary_contact_prompt.dart';
import '../../widgets/customers/customer_location_form.dart';
import '../../widgets/customers/tag_input_widget.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

/// A step-by-step onboarding wizard for creating new customers.
/// When [customerId] is provided, runs in edit mode with tab chips.
class CustomerOnboardingWizard extends StatefulWidget {
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final String? customerId;
  final int? initialStep;
  final bool navigateToDetailOnCreate;

  const CustomerOnboardingWizard({
    super.key,
    this.onComplete,
    this.onCancel,
    this.customerId,
    this.initialStep,
    this.navigateToDetailOnCreate = true,
  });

  @override
  State<CustomerOnboardingWizard> createState() =>
      _CustomerOnboardingWizardState();
}

class _CustomerOnboardingWizardState extends State<CustomerOnboardingWizard>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 6;
  bool _isLoading = false;

  // Validation UI state
  bool _showFieldErrors = false;
  String? _validationMessage;
  late final AnimationController _shakeController;

  // Step 1: Basic Info
  final _companyNameController = TextEditingController();
  final _businessPhoneController = TextEditingController();
  final _businessEmailController = TextEditingController();
  String _selectedCustomerType = 'Residential';
  List<CustomerTypeConfig> _customerTypes = [];
  dynamic _customerTypeSubscription;

  // Step 2: Contacts
  final List<CustomerContact> _contacts = [];
  // For inline contact form
  final _contactNameController = TextEditingController();
  final _contactTitleController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactMobileController = TextEditingController();
  bool _isEditingContact = false;
  int? _editingContactIndex;

  // Step 3: Address
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipController = TextEditingController();
  String? _selectedCountry;
  final GeocodingService _geocodingService = GeocodingService();
  Timer? _addressSuggestionDebounce;
  List<AddressSuggestion> _addressSuggestions = const [];
  bool _isLoadingAddressSuggestions = false;
  bool _isSettingAddressFromSuggestion = false;
  String? _workspaceCountryCode;

  // Step 4: Classification
  CustomerStatus _selectedStatus = CustomerStatus.active;
  CustomerSource? _selectedSource;
  final _referrerNameController = TextEditingController();
  String? _selectedParentId;
  List<Customer> _availableParents = [];
  bool _taxExempt = false;
  final _notesController = TextEditingController();
  List<String> _selectedTagIds = [];
  String? _selectedOwnerId;
  List<AppUser> _workspaceUsers = [];

  // Step 5: Locations (create mode only — edit mode loads from DB)
  final List<CustomerLocation> _pendingLocations = [];
  // Tracks persisted contact IDs to avoid leaking temp UUIDs into DB locations
  final Set<String> _persistedContactIds = {};

  // Services
  dynamic get _customerService => ServiceLocator.customerService;
  final _locationService = ServiceLocator.customerLocationService;

  bool get _isEditMode => widget.customerId != null;

  // Edit mode tab labels (5 tabs, no Review step)
  static const List<String> _editTabLabels = [
    'Basic Info',
    'Contacts',
    'Address',
    'Classification',
    'Locations',
  ];

  // Step configuration
  static const List<_StepConfig> _steps = [
    _StepConfig(
      number: 1,
      title: 'Basic Info',
      subtitle: "Let's start with the company details",
      icon: Icons.business,
    ),
    _StepConfig(
      number: 2,
      title: 'Contacts',
      subtitle: "Who should we reach out to?",
      icon: Icons.people,
    ),
    _StepConfig(
      number: 3,
      title: 'Address',
      subtitle: "Where is this customer located?",
      icon: Icons.location_on,
    ),
    _StepConfig(
      number: 4,
      title: 'Classification',
      subtitle: 'How should we categorize this customer?',
      icon: Icons.category,
    ),
    _StepConfig(
      number: 5,
      title: 'Locations',
      subtitle: 'Add service locations for this customer',
      icon: Icons.location_on_outlined,
    ),
    _StepConfig(
      number: 6,
      title: 'Review & Create',
      subtitle: "Review the details before creating",
      icon: Icons.check_circle,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentStep = _resolveInitialStep();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _addressController.addListener(_onAddressChanged);
    _loadAvailableParents();
    _loadWorkspaceUsers();
    _loadCustomerTypes();
    _loadWorkspaceCountryCode();
    if (_isEditMode) {
      _loadCustomer();
    }
  }

  Future<void> _loadWorkspaceUsers() async {
    try {
      final workspaceId = Provider.of<AuthProvider>(
        context,
        listen: false,
      ).appUser?.currentWorkspaceId;
      if (workspaceId == null) return;

      final members = await ServiceLocator.workspaceMemberService
          .getWorkspaceMembers(workspaceId)
          .first;
      final List<AppUser> users = [];
      for (final member in members) {
        final user = await ServiceLocator.userService.getUserById(
          member.userId,
        );
        if (user != null) users.add(user);
      }
      if (mounted) {
        setState(() => _workspaceUsers = users);
      }
    } catch (_) {}
  }

  int _resolveInitialStep() {
    final requested = widget.initialStep ?? 0;
    final maxStep = _isEditMode ? _editTabLabels.length : _totalSteps;
    return requested.clamp(0, maxStep - 1);
  }

  Future<void> _loadCustomerTypes() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final workspaceId = authProvider.appUser?.currentWorkspaceId;
      if (workspaceId == null) return;

      final service = ServiceLocator.customerTypeService;
      _customerTypeSubscription = service.getCustomerTypes(workspaceId).listen((
        types,
      ) {
        CustomerTypeBadge.updateColorCache(types);
        if (!mounted) return;
        setState(() {
          _customerTypes = types;
          // Avoid the "$type (removed)" first-impression bug when the
          // hardcoded default ('Residential') isn't a seeded type in this
          // workspace. If the workspace has any types, switch to the first;
          // if it has none, clear the field so the dropdown doesn't render
          // a ghost "(removed)" entry pointing at the default name.
          final hasSelected = types.any((t) => t.name == _selectedCustomerType);
          if (!hasSelected) {
            _selectedCustomerType = types.isNotEmpty ? types.first.name : '';
          }
        });
      });
    } catch (_) {}
  }

  Future<void> _loadWorkspaceCountryCode() async {
    try {
      final workspaceId = Provider.of<AuthProvider>(
        context,
        listen: false,
      ).appUser?.currentWorkspaceId;
      if (workspaceId == null) return;
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

  Future<void> _loadCustomer() async {
    setState(() => _isLoading = true);
    try {
      final customer = await _customerService.getCustomer(widget.customerId!);
      if (customer != null && mounted) {
        setState(() {
          _contacts.clear();
          _contacts.addAll(customer.contacts);
          _persistedContactIds
            ..clear()
            ..addAll(
              customer.contacts.where((c) => c.id != null).map((c) => c.id!),
            );
          _companyNameController.text = customer.companyName ?? '';
          _businessPhoneController.text = customer.businessPhone ?? '';
          _businessEmailController.text = customer.businessEmail ?? '';
          _selectedCustomerType = customer.customerType;
          _isSettingAddressFromSuggestion = true;
          _addressController.text = customer.address ?? '';
          _isSettingAddressFromSuggestion = false;
          _cityController.text = customer.city ?? '';
          _stateController.text = customer.state ?? '';
          _zipController.text = customer.zipCode ?? '';
          _selectedCountry = customer.country;
          _selectedStatus = customer.status;
          _selectedSource = customer.source;
          _referrerNameController.text = customer.referrerName ?? '';
          _selectedParentId = customer.parentCustomerId;
          _taxExempt = customer.taxExempt;
          _notesController.text = customer.notes ?? '';
          _selectedTagIds = List.from(customer.tagIds);
          _selectedOwnerId = customer.accountOwnerId;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'loading customer'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAvailableParents() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId != null) {
        final customers = await _customerService
            .getCustomers(workspaceId)
            .first;
        if (mounted) {
          setState(() {
            _availableParents = customers;
          });
        }
      }
    } catch (e) {
      // Silently fail - parent selection is optional
    }
  }

  @override
  void dispose() {
    _customerTypeSubscription?.cancel();
    _shakeController.dispose();
    _pageController.dispose();
    _companyNameController.dispose();
    _businessPhoneController.dispose();
    _businessEmailController.dispose();
    _contactNameController.dispose();
    _contactTitleController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    _contactMobileController.dispose();
    _addressSuggestionDebounce?.cancel();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _referrerNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onAddressChanged() {
    if (_isSettingAddressFromSuggestion) return;

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
    if (suggestion.city != null) {
      _cityController.text = suggestion.city!;
    }
    if (suggestion.state != null) {
      _stateController.text = suggestion.state!;
    }
    if (suggestion.postcode != null) {
      _zipController.text = suggestion.postcode!;
    }
    if (suggestion.countryCode != null) {
      final countryName = CountryList.findCountryNameByCode(
        suggestion.countryCode!,
      );
      if (countryName != null) {
        _selectedCountry = countryName;
      }
    }
    setState(() {
      _addressSuggestions = const [];
      _isLoadingAddressSuggestions = false;
    });
    _isSettingAddressFromSuggestion = false;
    FocusScope.of(context).unfocus();
  }

  Future<bool> _validateCurrentStep() async {
    switch (_currentStep) {
      case 0: // Basic Info - company name is optional, email must be valid
        final email = _businessEmailController.text.trim();
        if (email.isNotEmpty && !_isValidEmail(email)) {
          setState(() {
            _showFieldErrors = true;
            _validationMessage = 'Please enter a valid business email address';
          });
          _shakeController.forward(from: 0);
          return false;
        }
        return true;
      case 1: // Contacts
        if (_hasUnsavedContactDraft()) {
          final wasSaved = await _addOrUpdateContact(promptForPrimary: false);
          if (!wasSaved) {
            return false;
          }
        }
        if (_contacts.isEmpty) {
          setState(() {
            _showFieldErrors = true;
            _validationMessage = 'Please add at least one contact';
          });
          _shakeController.forward(from: 0);
          return false;
        }
        final hasPrimary = _contacts.any((c) => c.isPrimary && c.isActive);
        if (!hasPrimary) {
          setState(() {
            _showFieldErrors = true;
            _validationMessage = 'Please set one contact as primary';
          });
          _shakeController.forward(from: 0);
          return false;
        }
        return true;
      case 2: // Address - all optional
        return true;
      case 3: // Classification - all optional
        return true;
      case 4: // Locations - optional
        return true;
      case 5: // Review
        return true;
      default:
        return true;
    }
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
    final maxStep = _isEditMode ? _editTabLabels.length : _totalSteps;
    if (step >= 0 && step < maxStep) {
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

  Future<void> _nextStep() async {
    if (await _validateCurrentStep()) {
      if (_currentStep < _totalSteps - 1) {
        _goToStep(_currentStep + 1);
      } else {
        _handleCreate();
      }
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    }
  }

  Future<void> _handleCreate() async {
    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId == null) {
        throw Exception('No workspace found');
      }

      final customer = Customer(
        id: '', // Will be set by the service
        workspaceId: workspaceId,
        contacts: _contacts,
        parentCustomerId: _selectedParentId,
        status: _selectedStatus,
        source: _selectedSource,
        referrerName: _selectedSource == CustomerSource.referral
            ? _referrerNameController.text.trim().isNotEmpty
                  ? _referrerNameController.text.trim()
                  : null
            : null,
        tagIds: _selectedTagIds,
        accountOwnerId: _selectedOwnerId,
        companyName: _companyNameController.text.trim().isEmpty
            ? null
            : _companyNameController.text.trim(),
        businessPhone: _businessPhoneController.text.trim().isEmpty
            ? null
            : _businessPhoneController.text.trim(),
        businessEmail: _businessEmailController.text.trim().isEmpty
            ? null
            : _businessEmailController.text.trim(),
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        state: _stateController.text.trim().isEmpty
            ? null
            : _stateController.text.trim(),
        zipCode: _zipController.text.trim().isEmpty
            ? null
            : _zipController.text.trim(),
        country: _selectedCountry,
        customerType: _selectedCustomerType,
        taxExempt: _taxExempt,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final newCustomer = await _customerService.createCustomerWithContacts(
        workspaceId,
        customer,
      );

      // Create pending locations with remapped contact IDs
      if (_pendingLocations.isNotEmpty) {
        // Build temp→real contact ID map by matching index order
        final tempIds = _contacts.map((c) => c.id).toList();
        final realContacts = newCustomer.contacts;
        final idMap = <String, String>{};
        for (int i = 0; i < tempIds.length && i < realContacts.length; i++) {
          final tempId = tempIds[i];
          final realId = realContacts[i].id;
          if (tempId != null && realId != null) {
            idMap[tempId] = realId;
          }
        }

        for (final pending in _pendingLocations) {
          final remappedIds = pending.contactIds
              .map((id) => idMap[id] ?? id)
              .toList();
          final loc = pending.copyWith(
            customerId: newCustomer.id,
            workspaceId: workspaceId,
            contactIds: remappedIds,
          );
          await _locationService.createLocation(loc);
        }
      }

      if (mounted) {
        final msg = _pendingLocations.isNotEmpty
            ? 'Customer and ${_pendingLocations.length} location${_pendingLocations.length == 1 ? '' : 's'} created successfully!'
            : 'Customer created successfully!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.success),
        );
        widget.onComplete?.call();
        Navigator.of(context).pop(newCustomer.id);
        if (widget.navigateToDetailOnCreate) {
          context.go('/customers/${newCustomer.id}');
        }
      }
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
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveChanges() async {
    final workspaceId = context
        .read<AuthProvider>()
        .appUser
        ?.currentWorkspaceId;
    if (workspaceId == null) {
      _showValidationError('No workspace found');
      return;
    }

    // Auto-save any unsaved contact draft before persisting
    if (_hasUnsavedContactDraft()) {
      final wasSaved = await _addOrUpdateContact(promptForPrimary: false);
      if (!wasSaved) return;
    }
    if (_contacts.isEmpty) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = 'Please add at least one contact';
      });
      _shakeController.forward(from: 0);
      return;
    }
    if (!_contacts.any((c) => c.isPrimary && c.isActive)) {
      final index = _contacts.indexWhere((c) => c.isActive);
      if (index != -1) {
        _contacts[index] = _contacts[index].copyWith(isPrimary: true);
      }
    }
    final primaryCount = _contacts
        .where((c) => c.isPrimary && c.isActive)
        .length;
    if (primaryCount == 0) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = 'Please set one contact as primary';
      });
      _shakeController.forward(from: 0);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final updates = {
        'contacts': _contacts.map((c) => c.toJson()).toList(),
        'companyName': _companyNameController.text.trim().isEmpty
            ? null
            : _companyNameController.text.trim(),
        'businessPhone': _businessPhoneController.text.trim().isEmpty
            ? null
            : _businessPhoneController.text.trim(),
        'businessEmail': _businessEmailController.text.trim().isEmpty
            ? null
            : _businessEmailController.text.trim(),
        'customerType': _selectedCustomerType,
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'city': _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        'state': _stateController.text.trim().isEmpty
            ? null
            : _stateController.text.trim(),
        'zipCode': _zipController.text.trim().isEmpty
            ? null
            : _zipController.text.trim(),
        'country': _selectedCountry,
        'status': _selectedStatus.name,
        'source': _selectedSource?.name,
        'referrerName': _selectedSource == CustomerSource.referral
            ? _referrerNameController.text.trim().isNotEmpty
                  ? _referrerNameController.text.trim()
                  : null
            : null,
        'parentCustomerId': _selectedParentId,
        'taxExempt': _taxExempt,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'tagIds': _selectedTagIds,
        'accountOwnerId': _selectedOwnerId,
      };
      // Keep legacy fields in sync
      final primary = _contacts.firstWhere((c) => c.isPrimary && c.isActive);
      updates['name'] = primary.name;
      updates['email'] = primary.email;
      updates['phone'] = primary.phone;

      await _customerService.updateCustomer(widget.customerId!, updates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onComplete?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _showValidationError(
          UserFacingError.uiMessage(e, action: 'save customer'),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearContactForm() {
    _contactNameController.clear();
    _contactTitleController.clear();
    _contactEmailController.clear();
    _contactPhoneController.clear();
    _contactMobileController.clear();
    setState(() {
      _isEditingContact = false;
      _editingContactIndex = null;
    });
  }

  Future<bool> _addOrUpdateContact({required bool promptForPrimary}) async {
    final name = _contactNameController.text.trim();
    if (name.isEmpty) {
      _showValidationError('Contact name is required');
      return false;
    }

    final email = _contactEmailController.text.trim();
    if (email.isNotEmpty && !_isValidEmail(email)) {
      _showValidationError('Please enter a valid email address');
      return false;
    }

    final isEditing = _editingContactIndex != null;
    final hasExistingPrimary = _contacts.any((c) => c.isPrimary && c.isActive);
    final shouldMakePrimary = isEditing
        ? _contacts[_editingContactIndex!].isPrimary
        : promptForPrimary
        ? await showPrimaryContactPrompt(
            context,
            contactName: name,
            ownerLabel: 'customer',
          )
        : !hasExistingPrimary;

    // Preserve existing ID when editing, assign temp UUID for new contacts
    final existingId = isEditing ? _contacts[_editingContactIndex!].id : null;
    final contact = CustomerContact(
      id: existingId ?? const Uuid().v4(),
      name: name,
      title: _contactTitleController.text.trim().isEmpty
          ? null
          : _contactTitleController.text.trim(),
      email: email.isEmpty ? null : email,
      phone: _contactPhoneController.text.trim().isEmpty
          ? null
          : _contactPhoneController.text.trim(),
      mobilePhone: _contactMobileController.text.trim().isEmpty
          ? null
          : _contactMobileController.text.trim(),
      isPrimary: shouldMakePrimary,
      isActive: true,
    );

    setState(() {
      if (shouldMakePrimary) {
        for (int i = 0; i < _contacts.length; i++) {
          _contacts[i] = _contacts[i].copyWith(isPrimary: false);
        }
      }

      if (_editingContactIndex != null) {
        _contacts[_editingContactIndex!] = contact;
      } else {
        _contacts.add(contact);
      }
    });

    _clearContactForm();
    return true;
  }

  bool _hasUnsavedContactDraft() {
    if (_isEditingContact) {
      return true;
    }

    return _contactNameController.text.trim().isNotEmpty ||
        _contactTitleController.text.trim().isNotEmpty ||
        _contactEmailController.text.trim().isNotEmpty ||
        _contactPhoneController.text.trim().isNotEmpty ||
        _contactMobileController.text.trim().isNotEmpty;
  }

  void _editContact(int index) {
    final contact = _contacts[index];
    setState(() {
      _contactNameController.text = contact.name;
      _contactTitleController.text = contact.title ?? '';
      _contactEmailController.text = contact.email ?? '';
      _contactPhoneController.text = contact.phone ?? '';
      _contactMobileController.text = contact.mobilePhone ?? '';
      _isEditingContact = true;
      _editingContactIndex = index;
    });
  }

  void _deleteContact(int index) {
    final contact = _contacts[index];
    setState(() {
      _contacts.removeAt(index);
      // If deleted contact was primary and there are remaining contacts, make first one primary
      if (contact.isPrimary && _contacts.isNotEmpty) {
        _contacts[0] = _contacts[0].copyWith(isPrimary: true);
      }
    });
  }

  void _setAsPrimary(int index) {
    setState(() {
      for (int i = 0; i < _contacts.length; i++) {
        _contacts[i] = _contacts[i].copyWith(isPrimary: i == index);
      }
    });
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    if (_isEditMode) {
      if (_isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Column(
        children: [
          _buildEditHeader(theme),
          Expanded(
            child: IndexedStack(
              index: _currentStep,
              children: [
                _buildStep1BasicInfo(),
                _buildStep2Contacts(),
                _buildStep3Address(),
                _buildStep4Classification(),
                _buildLocationsTab(),
              ],
            ),
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
            children: [
              _buildStep1BasicInfo(),
              _buildStep2Contacts(),
              _buildStep3Address(),
              _buildStep4Classification(),
              _buildStep5Locations(),
              _buildStep6Review(),
            ],
          ),
        ),

        // Navigation buttons
        _buildNavigationBar(primaryColor),
      ],
    );
  }

  Widget _buildEditHeader(ThemeData theme) {
    final primaryColor = theme.colorScheme.primary;
    final currentConfig = _steps[_currentStep];

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
              children: List.generate(_editTabLabels.length, (index) {
                return _buildEditTabChip(
                  index: index,
                  icon: _steps[index].icon,
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
                      _editTabLabels[_currentStep],
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentConfig.subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
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
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
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
                onPressed: _isLoading ? null : _saveChanges,
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
                  color: Color.fromRGBO(
                    primaryColor.r.toInt(),
                    primaryColor.g.toInt(),
                    primaryColor.b.toInt(),
                    0.1,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  _steps[_currentStep].icon,
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
                      '${_currentStep + 1}. ${_steps[_currentStep].title}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _steps[_currentStep].subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
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
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? primaryColor : Colors.transparent,
        border: Border.all(
          color: isActive ? primaryColor : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
          width: 2,
        ),
      ),
      child: Center(
        child: isCompleted
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : Text(
                '$number',
                style: TextStyle(
                  color: isActive ? Colors.white : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
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
          // Next/Create button
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
                _currentStep == _totalSteps - 1 ? 'Create Customer' : 'Next',
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

  // ==================== STEP 1: BASIC INFO ====================

  Widget _buildStep1BasicInfo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Company Name
          _buildFieldLabel('Company Name', required: false),
          const SizedBox(height: 8),
          TextFormField(
            controller: _companyNameController,
            decoration: const InputDecoration(
              hintText: 'Enter company name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.business),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Leave blank if this is an individual customer',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),

          // Business Phone & Email
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < AppBreakpoints.mobile;
              final phoneField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('Business Phone', required: false),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _businessPhoneController,
                    decoration: const InputDecoration(
                      hintText: 'Main phone number',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                ],
              );
              final emailField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('Business Email', required: false),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _businessEmailController,
                    decoration: const InputDecoration(
                      hintText: 'Main email address',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              );
              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    phoneField,
                    const SizedBox(height: 16),
                    emailField,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: phoneField),
                  const SizedBox(width: 16),
                  Expanded(child: emailField),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // Customer Type
          _buildFieldLabel('Customer Type', required: true),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final hasCurrentType = _customerTypes.any(
                (t) => t.name == _selectedCustomerType,
              );
              return DropdownButtonFormField<String>(
                borderRadius: AppRadius.cardRadius,
                value: _selectedCustomerType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: [
                  if (!hasCurrentType && _selectedCustomerType.isNotEmpty)
                    DropdownMenuItem(
                      value: _selectedCustomerType,
                      child: Text('$_selectedCustomerType (removed)'),
                    ),
                  ..._customerTypes.map((type) {
                    return DropdownMenuItem(
                      value: type.name,
                      child: Text(type.name),
                    );
                  }),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedCustomerType = value);
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ==================== STEP 2: CONTACTS ====================

  Widget _buildStep2Contacts() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Proactive requirements hint so the user knows BEFORE clicking
          // Next what step 2 expects — previously the requirements ("add at
          // least one contact" + "mark one as primary") only surfaced after
          // a failed Next click.
          if (_contacts.isEmpty ||
              !_contacts.any((c) => c.isPrimary && c.isActive))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.infoDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _contacts.isEmpty
                          ? 'Add at least one contact. After saving, mark '
                                'one as the primary contact to continue.'
                          : 'Mark one contact as primary to continue.',
                      style: TextStyle(
                        color: AppColors.infoDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_currentStep == 1) _buildValidationBanner(),
          // Contact Form
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isEditingContact ? Icons.edit : Icons.person_add,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isEditingContact ? 'Edit Contact' : 'Add Contact',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (_contacts.isEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.secondarySurface,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            'Required',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.warningDark,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'Name *',
                    child: TextFormField(
                      controller: _contactNameController,
                      decoration: const InputDecoration(
                        hintText: 'Contact name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StackedField(
                    label: 'Title / Role',
                    child: TextFormField(
                      controller: _contactTitleController,
                      decoration: const InputDecoration(
                        hintText: 'e.g., Project Manager, Owner',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.work),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StackedField(
                    label: 'Email',
                    child: TextFormField(
                      controller: _contactEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: 'email@example.com',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StackedField(
                    label: 'Phone',
                    child: TextFormField(
                      controller: _contactPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: '(555) 123-4567',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StackedField(
                    label: 'Cell Phone',
                    child: TextFormField(
                      controller: _contactMobileController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: '(555) 987-6543',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_android),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_isEditingContact)
                        TextButton(
                          onPressed: _clearContactForm,
                          child: const Text('Cancel'),
                        ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          await _addOrUpdateContact(promptForPrimary: true);
                        },
                        icon: Icon(_isEditingContact ? Icons.save : Icons.add),
                        label: Text(
                          _isEditingContact ? 'Update Contact' : 'Add Contact',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Contacts List
          if (_contacts.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'Contacts (${_contacts.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '★ = Primary Contact',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(_contacts.length, (index) {
              final contact = _contacts[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: contact.isPrimary
                        ? AppColors.secondarySurface
                        : AppColors.surfaceAlt,
                    child: Icon(
                      contact.isPrimary ? Icons.star : Icons.person,
                      color: contact.isPrimary
                          ? AppColors.warningDark
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        contact.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (contact.isPrimary) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.secondarySurface,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            'Primary',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.warningDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (contact.title != null)
                        Text(
                          contact.title!,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
                        ),
                      if (contact.email != null ||
                          contact.phone != null ||
                          contact.mobilePhone != null)
                        Text(
                          [
                            contact.email,
                            contact.phone,
                            contact.mobilePhone,
                          ].where((e) => e != null).join(' • '),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    itemBuilder: (context) => [
                      if (!contact.isPrimary)
                        const PopupMenuItem(
                          value: 'primary',
                          child: Row(
                            children: [
                              Icon(Icons.star, size: 18),
                              SizedBox(width: 8),
                              Text('Set as Primary'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            const SizedBox(width: 8),
                            const Text(
                              'Delete',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'primary':
                          _setAsPrimary(index);
                          break;
                        case 'edit':
                          _editContact(index);
                          break;
                        case 'delete':
                          _deleteContact(index);
                          break;
                      }
                    },
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ==================== STEP 3: ADDRESS ====================

  Widget _buildStep3Address() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel('Street Address', required: false),
          const SizedBox(height: 8),
          TextFormField(
            controller: _addressController,
            decoration: const InputDecoration(
              hintText: 'Start typing to search addresses...',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_on),
            ),
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
                  final condensed = suggestion.singleLineAddress(
                    typedQuery: _addressController.text.trim(),
                  );
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined, size: 18),
                    title: Text(
                      condensed,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectAddressSuggestion(suggestion),
                  );
                },
              ),
            ),
          const SizedBox(height: 20),

          LayoutBuilder(
            builder: (context, constraints) {
              final cityField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('City', required: false),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _cityController,
                    decoration: const InputDecoration(
                      hintText: 'City',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              );
              final stateField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel(
                    CountryList.getStateLabel(_selectedCountry),
                    required: false,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _stateController,
                    decoration: InputDecoration(
                      hintText: CountryList.getStateLabel(_selectedCountry),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              );
              if (constraints.maxWidth < 400) {
                return Column(
                  children: [cityField, const SizedBox(height: 12), stateField],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 2, child: cityField),
                  const SizedBox(width: 16),
                  Expanded(child: stateField),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          LayoutBuilder(
            builder: (context, constraints) {
              final zipField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel(
                    CountryList.getPostalCodeLabel(_selectedCountry),
                    required: false,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _zipController,
                    decoration: InputDecoration(
                      hintText: CountryList.getPostalCodeLabel(
                        _selectedCountry,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              );
              final countryField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('Country', required: false),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    borderRadius: AppRadius.cardRadius,
                    value: _selectedCountry,
                    decoration: const InputDecoration(
                      hintText: 'Select country',
                      border: OutlineInputBorder(),
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
                                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedCountry = value);
                    },
                  ),
                ],
              );
              if (constraints.maxWidth < 400) {
                return Column(
                  children: [
                    zipField,
                    const SizedBox(height: 12),
                    countryField,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: zipField),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: countryField),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ==================== STEP 4: CLASSIFICATION ====================

  Widget _buildStep4Classification() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status
          _buildFieldLabel('Status', required: false),
          const SizedBox(height: 8),
          DropdownButtonFormField<CustomerStatus>(
            borderRadius: AppRadius.cardRadius,
            value: _selectedStatus,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.flag),
            ),
            items: CustomerStatus.values.map((status) {
              return DropdownMenuItem(
                value: status,
                child: Text(status.displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedStatus = value);
              }
            },
          ),
          const SizedBox(height: 20),

          // Source
          _buildFieldLabel(
            'How did you acquire this customer?',
            required: false,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<CustomerSource?>(
            borderRadius: AppRadius.cardRadius,
            value: _selectedSource,
            decoration: const InputDecoration(
              hintText: 'Select source',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.source),
            ),
            items: [
              const DropdownMenuItem<CustomerSource?>(
                value: null,
                child: Text('Not specified'),
              ),
              ...CustomerSource.values.map((source) {
                return DropdownMenuItem(
                  value: source,
                  child: Text(source.displayName),
                );
              }),
            ],
            onChanged: (value) {
              setState(() => _selectedSource = value);
            },
          ),
          if (_selectedSource == CustomerSource.referral) ...[
            const SizedBox(height: 16),
            StackedField(
              label: 'Referrer Name',
              child: TextFormField(
                controller: _referrerNameController,
                decoration: const InputDecoration(
                  hintText: 'Who referred this customer?',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Parent Company
          _buildFieldLabel('Parent Company', required: false),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            borderRadius: AppRadius.cardRadius,
            value: _selectedParentId,
            decoration: const InputDecoration(
              hintText: 'Optional - for sub-companies',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.account_tree),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('None (Independent)'),
              ),
              ..._availableParents.map((parent) {
                return DropdownMenuItem<String?>(
                  value: parent.id,
                  child: Text(parent.displayName),
                );
              }),
            ],
            onChanged: (value) {
              setState(() => _selectedParentId = value);
            },
          ),
          const SizedBox(height: 20),

          // Tax Exempt
          CheckboxListTile(
            title: const Text('Tax Exempt'),
            subtitle: const Text('Customer is exempt from sales tax'),
            value: _taxExempt,
            onChanged: (value) {
              setState(() => _taxExempt = value ?? false);
            },
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 20),

          // Notes
          _buildFieldLabel('Notes', required: false),
          const SizedBox(height: 8),
          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(
              hintText: 'Add any internal notes about this customer...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            maxLength: 1000,
          ),
          const SizedBox(height: 20),
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final workspaceId = authProvider.appUser?.currentWorkspaceId;
              if (workspaceId == null) return const SizedBox.shrink();
              return TagInputWidget(
                workspaceId: workspaceId,
                selectedTagIds: _selectedTagIds,
                onTagsChanged: (tagIds) {
                  setState(() => _selectedTagIds = tagIds);
                },
              );
            },
          ),
          const SizedBox(height: 20),
          _buildFieldLabel('Account Owner', required: false),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            borderRadius: AppRadius.cardRadius,
            initialValue: _workspaceUsers.any((u) => u.id == _selectedOwnerId)
                ? _selectedOwnerId
                : null,
            decoration: const InputDecoration(
              hintText: 'Assign to a team member',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.manage_accounts),
              helperText: 'Assign this customer to a team member',
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('No owner assigned'),
              ),
              ..._workspaceUsers.map((user) {
                return DropdownMenuItem<String>(
                  value: user.id,
                  child: Text(user.displayName ?? user.email),
                );
              }),
            ],
            onChanged: (value) {
              setState(() => _selectedOwnerId = value);
            },
          ),
        ],
      ),
    );
  }

  // ==================== STEP 5: LOCATIONS (CREATE MODE) ====================

  Widget _buildStep5Locations() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You can add locations now or later from the customer detail page.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          if (_pendingLocations.isEmpty)
            _buildLocationsEmptyState(isCreateMode: true)
          else ...[
            ..._pendingLocations.asMap().entries.map(
              (entry) => _buildPendingLocationCard(entry.key, entry.value),
            ),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _showAddLocationDialog(isCreateMode: true),
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: const Text('Add Location'),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== LOCATIONS TAB (EDIT MODE) ====================

  Widget _buildLocationsTab() {
    return StreamBuilder<List<CustomerLocation>>(
      stream: _locationService.getLocations(widget.customerId!),
      builder: (context, snapshot) {
        final locations = snapshot.data ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (snapshot.connectionState == ConnectionState.waiting &&
                  locations.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (locations.isEmpty)
                _buildLocationsEmptyState(isCreateMode: false)
              else ...[
                ...locations.map((loc) => _buildExistingLocationCard(loc)),
                const SizedBox(height: 12),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _showAddLocationDialog(isCreateMode: false),
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: const Text('Add Location'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocationsEmptyState({required bool isCreateMode}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Column(
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 12),
            Text(
              'No locations yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isCreateMode
                  ? 'Add service sites where work is performed.'
                  : 'Add locations to track multiple service sites.',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingLocationCard(int index, CustomerLocation location) {
    return _buildLocationCard(
      location: location,
      onEdit: () => _showEditPendingLocation(index),
      onRemove: () => setState(() => _pendingLocations.removeAt(index)),
      removeIcon: Icons.close,
      removeTooltip: 'Remove',
    );
  }

  Widget _buildExistingLocationCard(CustomerLocation location) {
    return _buildLocationCard(
      location: location,
      onEdit: () => _showEditExistingLocation(location),
      onRemove: () => _archiveLocation(location),
      removeIcon: Icons.archive_outlined,
      removeTooltip: 'Archive',
    );
  }

  Widget _buildLocationCard({
    required CustomerLocation location,
    required VoidCallback onEdit,
    required VoidCallback onRemove,
    required IconData removeIcon,
    required String removeTooltip,
  }) {
    final contactNames = _contacts
        .where((c) => c.isActive && location.contactIds.contains(c.id))
        .map((c) => c.name)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    location.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (location.fullAddress != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      AddressFormatter.condense(location.fullAddress!),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (contactNames.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      contactNames.join(', '),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit,
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: Icon(removeIcon, size: 18, color: AppColors.error),
              onPressed: onRemove,
              tooltip: removeTooltip,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  /// Returns contacts eligible for location association.
  /// In edit mode, excludes unsaved contacts (temp UUIDs not yet in DB).
  List<CustomerContact> _locationEligibleContacts({
    required bool isCreateMode,
  }) {
    if (isCreateMode) {
      return _contacts.where((c) => c.isActive).toList();
    }
    // Edit mode: only include persisted contacts to avoid writing temp IDs to DB
    return _contacts
        .where((c) => c.isActive && _persistedContactIds.contains(c.id))
        .toList();
  }

  void _showAddLocationDialog({required bool isCreateMode}) {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
    final customerId = widget.customerId ?? '';

    showDialog(
      context: context,
      builder: (context) => CustomerLocationForm(
        workspaceId: workspaceId,
        customerId: customerId,
        contacts: _locationEligibleContacts(isCreateMode: isCreateMode),
        onSave: (location) async {
          if (isCreateMode) {
            setState(() => _pendingLocations.add(location));
          } else {
            await _locationService.createLocation(location);
          }
        },
      ),
    );
  }

  void _showEditPendingLocation(int index) {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
    final location = _pendingLocations[index];

    showDialog(
      context: context,
      builder: (context) => CustomerLocationForm(
        workspaceId: workspaceId,
        customerId: location.customerId,
        location: location,
        contacts: _locationEligibleContacts(isCreateMode: true),
        onSave: (updated) async {
          setState(() => _pendingLocations[index] = updated);
        },
      ),
    );
  }

  void _showEditExistingLocation(CustomerLocation location) {
    showDialog(
      context: context,
      builder: (context) => CustomerLocationForm(
        workspaceId: location.workspaceId,
        customerId: location.customerId,
        location: location,
        contacts: _locationEligibleContacts(isCreateMode: false),
        onSave: (updated) async {
          await _locationService.updateLocation(updated);
        },
      ),
    );
  }

  void _archiveLocation(CustomerLocation location) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Location'),
        content: Text('Are you sure you want to archive "${location.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _locationService.deleteLocation(location.id);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  // ==================== STEP 6: REVIEW ====================

  Widget _buildStep6Review() {
    final primaryContact = _contacts.isNotEmpty
        ? _contacts.firstWhere(
            (c) => c.isPrimary,
            orElse: () => _contacts.first,
          )
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Card
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Color.fromRGBO(
                          Theme.of(context).colorScheme.primary.r.toInt(),
                          Theme.of(context).colorScheme.primary.g.toInt(),
                          Theme.of(context).colorScheme.primary.b.toInt(),
                          0.1,
                        ),
                        child: Icon(
                          Icons.business,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _companyNameController.text.trim().isNotEmpty
                                  ? _companyNameController.text.trim()
                                  : primaryContact?.name ?? 'New Customer',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              _selectedCustomerType,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(AppRadius.r16),
                        ),
                        child: Text(
                          _selectedStatus.displayName,
                          style: TextStyle(
                            color: AppColors.successDark,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),

                  // Contacts Section
                  _buildReviewSection(
                    icon: Icons.people,
                    title: 'Contacts (${_contacts.length})',
                    content: _contacts.isEmpty
                        ? 'No contacts added'
                        : _contacts
                              .map((c) {
                                final info = [
                                      c.title,
                                      c.email,
                                      c.phone,
                                      c.mobilePhone,
                                    ]
                                    .where((e) => e != null && e.isNotEmpty)
                                    .join(' • ');
                                return '${c.isPrimary ? '★ ' : ''}${c.name}${info.isNotEmpty ? '\n   $info' : ''}';
                              })
                              .join('\n'),
                  ),
                  const SizedBox(height: 16),

                  // Address Section
                  if (_addressController.text.isNotEmpty ||
                      _cityController.text.isNotEmpty ||
                      _stateController.text.isNotEmpty)
                    _buildReviewSection(
                      icon: Icons.location_on,
                      title: 'Address',
                      content: [
                        _addressController.text,
                        [
                          _cityController.text,
                          _stateController.text,
                          _zipController.text,
                        ].where((s) => s.isNotEmpty).join(', '),
                        _selectedCountry,
                      ].where((s) => s != null && s.isNotEmpty).join('\n'),
                    ),

                  // Classification Section
                  if (_selectedSource != null ||
                      _selectedParentId != null ||
                      _taxExempt) ...[
                    const SizedBox(height: 16),
                    _buildReviewSection(
                      icon: Icons.category,
                      title: 'Classification',
                      content: [
                        if (_selectedSource != null)
                          'Source: ${_selectedSource!.displayName}',
                        if (_selectedSource == CustomerSource.referral &&
                            _referrerNameController.text.isNotEmpty)
                          'Referrer: ${_referrerNameController.text}',
                        if (_selectedParentId != null)
                          'Parent: ${_availableParents.firstWhere((p) => p.id == _selectedParentId).displayName}',
                        if (_taxExempt) 'Tax Exempt: Yes',
                      ].join('\n'),
                    ),
                  ],

                  // Locations Section
                  if (_pendingLocations.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildReviewSection(
                      icon: Icons.location_on_outlined,
                      title: 'Locations (${_pendingLocations.length})',
                      content: _pendingLocations
                          .map((l) {
                            final addr = l.fullAddress;
                            return addr != null
                                ? '${l.name}\n   ${AddressFormatter.condense(addr)}'
                                : l.name;
                          })
                          .join('\n'),
                    ),
                  ],

                  // Notes Section
                  if (_notesController.text.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildReviewSection(
                      icon: Icons.notes,
                      title: 'Notes',
                      content: _notesController.text,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Edit hint
          Center(
            child: Text(
              'Click "Back" to make any changes before creating',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewSection({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label, {bool required = false}) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        if (required)
          Text(
            ' *',
            style: TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

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
