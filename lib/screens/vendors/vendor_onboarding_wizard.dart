import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import '../../theme/theme.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../services/service_locator.dart';
import '../../services/geocoding_service.dart';
import '../../utils/address_formatter.dart';
import '../../models/vendor.dart';
import '../../models/vendor_contact.dart';
import '../../models/vendor_subdivision.dart';
import '../../models/customer_type_config.dart';
import '../../models/payment_terms.dart';
import '../../utils/country_list.dart';
import '../../widgets/common/primary_contact_prompt.dart';
import '../../widgets/vendors/vendor_subdivision_form.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

/// A step-by-step onboarding wizard for creating new vendors.
/// When [vendorId] is provided, runs in edit mode with tab chips.
class VendorOnboardingWizard extends StatefulWidget {
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final String? vendorId;
  final bool navigateToDetailOnCreate;

  const VendorOnboardingWizard({
    super.key,
    this.onComplete,
    this.onCancel,
    this.vendorId,
    this.navigateToDetailOnCreate = true,
  });

  @override
  State<VendorOnboardingWizard> createState() => _VendorOnboardingWizardState();
}

class _VendorOnboardingWizardState extends State<VendorOnboardingWizard>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 6;
  bool _isLoading = false;

  // Validation UI state
  bool _showFieldErrors = false;
  String? _validationMessage;
  late final AnimationController _shakeController;

  // Step 1: Company Info
  final _companyNameController = TextEditingController();
  final _dbaController = TextEditingController();
  final _businessPhoneController = TextEditingController();
  final _businessEmailController = TextEditingController();
  final _websiteController = TextEditingController();

  // Step 2: Classification
  String _selectedCategory = 'Other';
  String _selectedVendorType = 'Other';
  List<CustomerTypeConfig> _vendorTypes = [];
  List<CustomerTypeConfig> _vendorCategories = [];
  dynamic _vendorTypeSub;
  dynamic _vendorCatSub;

  // Step 3: Contacts
  final List<VendorContact> _contacts = [];
  // For inline contact form
  final _contactNameController = TextEditingController();
  final _contactTitleController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactMobileController = TextEditingController();
  bool _isEditingContact = false;
  int? _editingContactIndex;

  // Step 4: Business Details
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
  final _taxIdController = TextEditingController();
  final _accountNumberController = TextEditingController();
  PaymentTerms? _selectedPaymentTerms;
  bool _isPreferred = false;

  // Step 5: Notes
  final _notesController = TextEditingController();

  // Subdivisions (create mode: in-memory; edit mode: loaded from DB)
  final List<VendorSubdivision> _pendingSubdivisions = [];
  // Tracks persisted contact IDs to avoid leaking temp UUIDs into DB
  final Set<String> _persistedContactIds = {};

  // Edit mode
  Vendor? _existingVendor;

  // Services
  dynamic get _vendorService => ServiceLocator.vendorService;
  final _subdivisionService = ServiceLocator.vendorSubdivisionService;

  bool get _isEditMode => widget.vendorId != null;

  // Edit mode tab labels (5 tabs, no Review step)
  static const List<String> _editTabLabels = [
    'Company Info',
    'Classification',
    'Contacts',
    'Business Details',
    'Subdivisions',
  ];

  // Step configuration
  static const List<_StepConfig> _steps = [
    _StepConfig(
      number: 1,
      title: 'Company Info',
      subtitle: "Let's start with the company details",
      icon: Icons.business,
    ),
    _StepConfig(
      number: 2,
      title: 'Classification',
      subtitle: "What type of vendor is this?",
      icon: Icons.category,
    ),
    _StepConfig(
      number: 3,
      title: 'Contacts',
      subtitle: "Who should we reach out to?",
      icon: Icons.people,
    ),
    _StepConfig(
      number: 4,
      title: 'Business Details',
      subtitle: 'Address and payment information',
      icon: Icons.location_on,
    ),
    _StepConfig(
      number: 5,
      title: 'Subdivisions',
      subtitle: 'Add office or service locations',
      icon: Icons.store_outlined,
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
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _addressController.addListener(_onAddressChanged);
    _loadVendorTypeConfigs();
    _loadWorkspaceCountryCode();
    if (_isEditMode) {
      _loadVendor();
    }
  }

  void _loadVendorTypeConfigs() {
    final authProvider = Provider.of<app_auth.AuthProvider>(
      context,
      listen: false,
    );
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;
    final service = ServiceLocator.vendorTypeService;
    _vendorTypeSub = service.getVendorTypes(workspaceId).listen((types) {
      if (!mounted) return;
      setState(() {
        _vendorTypes = types;
        final hasSelected = types.any((t) => t.name == _selectedVendorType);
        if (!hasSelected) {
          _selectedVendorType = types.isNotEmpty ? types.first.name : '';
        }
      });
    });
    _vendorCatSub = service.getVendorCategories(workspaceId).listen((cats) {
      if (!mounted) return;
      setState(() {
        _vendorCategories = cats;
        final hasCat = cats.any((c) => c.name == _selectedCategory);
        if (!hasCat) {
          _selectedCategory = cats.isNotEmpty ? cats.first.name : '';
        }
      });
    });
  }

  Future<void> _loadWorkspaceCountryCode() async {
    try {
      final workspaceId = Provider.of<app_auth.AuthProvider>(
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

  Future<void> _loadVendor() async {
    setState(() => _isLoading = true);
    try {
      final vendor = await _vendorService.getVendor(widget.vendorId!);
      if (vendor != null && mounted) {
        setState(() {
          _existingVendor = vendor;
          _companyNameController.text = vendor.companyName;
          _dbaController.text = vendor.dba ?? '';
          _businessPhoneController.text = vendor.businessPhone ?? '';
          _businessEmailController.text = vendor.businessEmail ?? '';
          _websiteController.text = vendor.website ?? '';
          _selectedCategory = vendor.category;
          _selectedVendorType = vendor.vendorType;
          _contacts.clear();
          _contacts.addAll(vendor.contacts);
          _persistedContactIds
            ..clear()
            ..addAll(
              vendor.contacts.where((c) => c.id != null).map((c) => c.id!),
            );
          _isSettingAddressFromSuggestion = true;
          _addressController.text = vendor.address ?? '';
          _isSettingAddressFromSuggestion = false;
          _cityController.text = vendor.city ?? '';
          _stateController.text = vendor.state ?? '';
          _zipController.text = vendor.zipCode ?? '';
          _selectedCountry = vendor.country;
          _taxIdController.text = vendor.taxId ?? '';
          _accountNumberController.text = vendor.accountNumber ?? '';
          _selectedPaymentTerms = vendor.paymentTerms;
          _isPreferred = vendor.isPreferred;
          _notesController.text = vendor.notes ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'loading vendor'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _vendorTypeSub?.cancel();
    _vendorCatSub?.cancel();
    _shakeController.dispose();
    _pageController.dispose();
    _companyNameController.dispose();
    _dbaController.dispose();
    _businessPhoneController.dispose();
    _businessEmailController.dispose();
    _websiteController.dispose();
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
    _taxIdController.dispose();
    _accountNumberController.dispose();
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
      case 0: // Company Info - company name required
        if (_companyNameController.text.trim().isEmpty) {
          setState(() {
            _showFieldErrors = true;
            _validationMessage = 'Company name is required';
          });
          _shakeController.forward(from: 0);
          return false;
        }
        return true;
      case 1: // Classification - already has defaults
        return true;
      case 2: // Contacts
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
      case 3: // Business Details - all optional
        return true;
      case 4: // Subdivisions - optional
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
      final authProvider = context.read<app_auth.AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;
      final userId = authProvider.appUser?.id;

      if (workspaceId == null || userId == null) {
        throw Exception('No workspace found');
      }

      final vendor = Vendor(
        id: '', // Will be set by the service
        workspaceId: workspaceId,
        companyName: _companyNameController.text.trim(),
        dba: _dbaController.text.trim().isEmpty
            ? null
            : _dbaController.text.trim(),
        businessPhone: _businessPhoneController.text.trim().isEmpty
            ? null
            : _businessPhoneController.text.trim(),
        businessEmail: _businessEmailController.text.trim().isEmpty
            ? null
            : _businessEmailController.text.trim(),
        website: _websiteController.text.trim().isEmpty
            ? null
            : _websiteController.text.trim(),
        contacts: _contacts,
        category: _selectedCategory,
        vendorType: _selectedVendorType,
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
        taxId: _taxIdController.text.trim().isEmpty
            ? null
            : _taxIdController.text.trim(),
        accountNumber: _accountNumberController.text.trim().isEmpty
            ? null
            : _accountNumberController.text.trim(),
        paymentTerms: _selectedPaymentTerms,
        isPreferred: _isPreferred,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: userId,
      );

      final newVendorId = await _vendorService.createVendor(vendor);

      // Create pending subdivisions with remapped contact IDs
      if (_pendingSubdivisions.isNotEmpty) {
        // Fetch the saved vendor to get contacts with real DB IDs
        final savedVendor = await _vendorService.getVendor(newVendorId);
        if (savedVendor != null) {
          final tempIds = _contacts.map((c) => c.id).toList();
          final realContacts = savedVendor.contacts;
          final idMap = <String, String>{};
          for (int i = 0; i < tempIds.length && i < realContacts.length; i++) {
            final tempId = tempIds[i];
            final realId = realContacts[i].id;
            if (tempId != null && realId != null) {
              idMap[tempId] = realId;
            }
          }

          for (final pending in _pendingSubdivisions) {
            final remappedContactId = pending.contactId != null
                ? (idMap[pending.contactId!] ?? pending.contactId)
                : null;
            final sub = pending.copyWith(
              vendorId: newVendorId,
              workspaceId: workspaceId,
              contactId: remappedContactId,
            );
            await _subdivisionService.createSubdivision(sub);
          }
        }
      }

      if (mounted) {
        final msg = _pendingSubdivisions.isNotEmpty
            ? 'Vendor and ${_pendingSubdivisions.length} subdivision${_pendingSubdivisions.length == 1 ? '' : 's'} created successfully!'
            : 'Vendor created successfully!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.success),
        );
        widget.onComplete?.call();
        Navigator.of(context).pop(newVendorId);
        if (widget.navigateToDetailOnCreate) {
          context.go('/vendors/$newVendorId');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'creating vendor'),
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
    if (_hasUnsavedContactDraft()) {
      final wasSaved = await _addOrUpdateContact(promptForPrimary: false);
      if (!wasSaved) return;
    }
    if (_companyNameController.text.trim().isEmpty) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = 'Company name is required';
      });
      _shakeController.forward(from: 0);
      return;
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
    if (!_contacts.any((c) => c.isPrimary && c.isActive)) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = 'Please set one contact as primary';
      });
      _shakeController.forward(from: 0);
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (!mounted) return;
      final authProvider = context.read<app_auth.AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
      final userId = authProvider.appUser?.id ?? '';
      final now = DateTime.now();

      final vendor = Vendor(
        id: widget.vendorId!,
        workspaceId: workspaceId,
        companyName: _companyNameController.text.trim(),
        dba: _dbaController.text.trim().isEmpty
            ? null
            : _dbaController.text.trim(),
        businessPhone: _businessPhoneController.text.trim().isEmpty
            ? null
            : _businessPhoneController.text.trim(),
        businessEmail: _businessEmailController.text.trim().isEmpty
            ? null
            : _businessEmailController.text.trim(),
        website: _websiteController.text.trim().isEmpty
            ? null
            : _websiteController.text.trim(),
        contacts: _contacts,
        category: _selectedCategory,
        vendorType: _selectedVendorType,
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
        taxId: _taxIdController.text.trim().isEmpty
            ? null
            : _taxIdController.text.trim(),
        accountNumber: _accountNumberController.text.trim().isEmpty
            ? null
            : _accountNumberController.text.trim(),
        paymentTerms: _selectedPaymentTerms,
        isPreferred: _isPreferred,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: _existingVendor?.createdAt ?? now,
        updatedAt: now,
        createdBy: _existingVendor?.createdBy ?? userId,
      );

      await _vendorService.updateVendor(vendor);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Vendor updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onComplete?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _showValidationError(
          UserFacingError.uiMessage(e, action: 'saving vendor'),
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
            ownerLabel: 'vendor',
          )
        : !hasExistingPrimary;

    // Preserve existing ID when editing, assign temp UUID for new contacts
    final existingId = isEditing ? _contacts[_editingContactIndex!].id : null;
    final contact = VendorContact(
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
                _buildStep1CompanyInfo(),
                _buildStep2Classification(),
                _buildStep3Contacts(),
                _buildStep4BusinessDetails(),
                _buildSubdivisionsTab(),
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
              _buildStep1CompanyInfo(),
              _buildStep2Classification(),
              _buildStep3Contacts(),
              _buildStep4BusinessDetails(),
              _buildStep5Subdivisions(),
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
                _currentStep == _totalSteps - 1 ? 'Create Vendor' : 'Next',
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

  // ==================== STEP 1: COMPANY INFO ====================

  Widget _buildStep1CompanyInfo() {
    final nameEmpty =
        _showFieldErrors && _companyNameController.text.trim().isEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentStep == 0) _buildValidationBanner(),
          // Company Name
          _buildFieldLabel('Company Name', required: true),
          const SizedBox(height: 8),
          TextFormField(
            controller: _companyNameController,
            onChanged: (_) => _clearValidationErrors(),
            decoration: InputDecoration(
              hintText: 'Enter company name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.business),
              errorText: nameEmpty ? 'Company name is required' : null,
            ),
          ),
          const SizedBox(height: 20),

          // DBA
          _buildFieldLabel('DBA (Doing Business As)', required: false),
          const SizedBox(height: 8),
          TextFormField(
            controller: _dbaController,
            decoration: const InputDecoration(
              hintText: 'Enter DBA name if different',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge),
            ),
          ),
          const SizedBox(height: 20),

          // Business Phone & Email
          Row(
            children: [
              Expanded(
                child: Column(
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
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
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
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Website
          _buildFieldLabel('Website', required: false),
          const SizedBox(height: 8),
          TextFormField(
            controller: _websiteController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'www.example.com',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.language),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STEP 2: CLASSIFICATION ====================

  Widget _buildStep2Classification() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vendor Type
          _buildFieldLabel('Vendor Type', required: true),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final hasType = _vendorTypes.any(
                (t) => t.name == _selectedVendorType,
              );
              return DropdownButtonFormField<String>(
                borderRadius: AppRadius.cardRadius,
                value: _selectedVendorType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: [
                  if (!hasType && _selectedVendorType.isNotEmpty)
                    DropdownMenuItem(
                      value: _selectedVendorType,
                      child: Text('$_selectedVendorType (removed)'),
                    ),
                  ..._vendorTypes.map(
                    (t) => DropdownMenuItem(value: t.name, child: Text(t.name)),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedVendorType = value);
                  }
                },
              );
            },
          ),
          const SizedBox(height: 20),

          // Category
          _buildFieldLabel('Category', required: true),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final hasCat = _vendorCategories.any(
                (c) => c.name == _selectedCategory,
              );
              return DropdownButtonFormField<String>(
                borderRadius: AppRadius.cardRadius,
                value: _selectedCategory,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
                items: [
                  if (!hasCat && _selectedCategory.isNotEmpty)
                    DropdownMenuItem(
                      value: _selectedCategory,
                      child: Text('$_selectedCategory (removed)'),
                    ),
                  ..._vendorCategories.map(
                    (c) => DropdownMenuItem(value: c.name, child: Text(c.name)),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedCategory = value);
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ==================== STEP 3: CONTACTS ====================

  Widget _buildStep3Contacts() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentStep == 2) _buildValidationBanner(),
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
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
                        hintText: 'e.g., Sales Rep, Account Manager',
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
                    label: 'Office Phone',
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
                        ? AppColors.warningLight
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
                            color: AppColors.warningLight,
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
                            Icon(
                              Icons.delete,
                              size: 18,
                              color: AppColors.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Delete',
                              style: TextStyle(color: AppColors.error),
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

  // ==================== STEP 4: BUSINESS DETAILS ====================

  Widget _buildStep4BusinessDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Address Section
          Text(
            'Address',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          StackedField(
            label: 'Street Address',
            child: Column(
              children: [
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
                          leading: const Icon(
                            Icons.location_on_outlined,
                            size: 18,
                          ),
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
              ],
            ),
          ),
          const SizedBox(height: 12),
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
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StackedField(
                  label: 'State',
                  child: TextFormField(
                    controller: _stateController,
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
                  label: CountryList.getPostalCodeLabel(_selectedCountry),
                  child: TextFormField(
                    controller: _zipController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: StackedField(
                  label: 'Country',
                  child: DropdownButtonFormField<String>(
                    borderRadius: AppRadius.cardRadius,
                    value: _selectedCountry,
                    decoration: const InputDecoration(
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
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Payment Info Section
          Text(
            'Payment Information',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StackedField(
                  label: 'Tax ID / EIN',
                  child: TextFormField(
                    controller: _taxIdController,
                    decoration: const InputDecoration(
                      hintText: 'XX-XXXXXXX',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.numbers),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StackedField(
                  label: 'Our Account #',
                  child: TextFormField(
                    controller: _accountNumberController,
                    decoration: const InputDecoration(
                      hintText: 'Your account number with them',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.account_circle),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StackedField(
            label: 'Payment Terms',
            child: DropdownButtonFormField<PaymentTerms>(
              borderRadius: AppRadius.cardRadius,
              value: _selectedPaymentTerms,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payment),
              ),
              items: [
                const DropdownMenuItem<PaymentTerms>(
                  value: null,
                  child: Text('Not specified'),
                ),
                ...PaymentTerms.values.map((terms) {
                  return DropdownMenuItem(
                    value: terms,
                    child: Text(terms.displayName),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() => _selectedPaymentTerms = value);
              },
            ),
          ),
          const SizedBox(height: 16),

          // Preferred Vendor
          CheckboxListTile(
            title: const Text('Preferred Vendor'),
            subtitle: const Text(
              'Mark this vendor as preferred for their category',
            ),
            value: _isPreferred,
            onChanged: (value) {
              setState(() => _isPreferred = value ?? false);
            },
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),

          // Notes
          _buildFieldLabel('Notes', required: false),
          const SizedBox(height: 8),
          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(
              hintText: 'Add any internal notes about this vendor...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            maxLength: 2000,
          ),
        ],
      ),
    );
  }

  // ==================== STEP 5: SUBDIVISIONS (CREATE MODE) ====================

  Widget _buildStep5Subdivisions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You can add subdivisions now or later from the vendor detail page.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          if (_pendingSubdivisions.isEmpty)
            _buildSubdivisionsEmptyState()
          else ...[
            ..._pendingSubdivisions.asMap().entries.map(
              (entry) => _buildSubdivisionCard(
                subdivision: entry.value,
                onEdit: () => _showEditPendingSubdivision(entry.key),
                onRemove: () =>
                    setState(() => _pendingSubdivisions.removeAt(entry.key)),
                removeIcon: Icons.close,
                removeTooltip: 'Remove',
              ),
            ),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _showAddSubdivisionDialog(isCreateMode: true),
              icon: const Icon(Icons.add_business_outlined, size: 18),
              label: const Text('Add Subdivision'),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== SUBDIVISIONS TAB (EDIT MODE) ====================

  Widget _buildSubdivisionsTab() {
    return StreamBuilder<List<VendorSubdivision>>(
      stream: _subdivisionService.getSubdivisions(widget.vendorId!),
      builder: (context, snapshot) {
        final subdivisions = snapshot.data ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (snapshot.connectionState == ConnectionState.waiting &&
                  subdivisions.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (subdivisions.isEmpty)
                _buildSubdivisionsEmptyState()
              else ...[
                ...subdivisions.map(
                  (sub) => _buildSubdivisionCard(
                    subdivision: sub,
                    onEdit: () => _showEditExistingSubdivision(sub),
                    onRemove: () => _archiveSubdivision(sub),
                    removeIcon: Icons.archive_outlined,
                    removeTooltip: 'Archive',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _showAddSubdivisionDialog(isCreateMode: false),
                  icon: const Icon(Icons.add_business_outlined, size: 18),
                  label: const Text('Add Subdivision'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubdivisionsEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Column(
          children: [
            Icon(Icons.store_outlined, size: 48, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
            const SizedBox(height: 12),
            Text(
              'No subdivisions yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add offices or service locations for this vendor.',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubdivisionCard({
    required VendorSubdivision subdivision,
    required VoidCallback onEdit,
    required VoidCallback onRemove,
    required IconData removeIcon,
    required String removeTooltip,
  }) {
    final contact = subdivision.contactId != null
        ? _contacts
              .where((c) => c.isActive && c.id == subdivision.contactId)
              .firstOrNull
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.store_outlined, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subdivision.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (subdivision.fullAddress != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      AddressFormatter.condense(subdivision.fullAddress!),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (contact != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      contact.name,
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

  /// Returns contacts eligible for subdivision association.
  /// In edit mode, excludes unsaved contacts (temp UUIDs not yet in DB).
  List<VendorContact> _subdivisionEligibleContacts({
    required bool isCreateMode,
  }) {
    if (isCreateMode) {
      return _contacts.where((c) => c.isActive).toList();
    }
    return _contacts
        .where((c) => c.isActive && _persistedContactIds.contains(c.id))
        .toList();
  }

  void _showAddSubdivisionDialog({required bool isCreateMode}) {
    final authProvider = context.read<app_auth.AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
    final vendorId = widget.vendorId ?? '';

    showDialog(
      context: context,
      builder: (context) => VendorSubdivisionForm(
        workspaceId: workspaceId,
        vendorId: vendorId,
        contacts: _subdivisionEligibleContacts(isCreateMode: isCreateMode),
        onSave: (subdivision) async {
          if (isCreateMode) {
            setState(() => _pendingSubdivisions.add(subdivision));
          } else {
            await _subdivisionService.createSubdivision(subdivision);
          }
        },
      ),
    );
  }

  void _showEditPendingSubdivision(int index) {
    final authProvider = context.read<app_auth.AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
    final subdivision = _pendingSubdivisions[index];

    showDialog(
      context: context,
      builder: (context) => VendorSubdivisionForm(
        workspaceId: workspaceId,
        vendorId: subdivision.vendorId,
        subdivision: subdivision,
        contacts: _subdivisionEligibleContacts(isCreateMode: true),
        onSave: (updated) async {
          setState(() => _pendingSubdivisions[index] = updated);
        },
      ),
    );
  }

  void _showEditExistingSubdivision(VendorSubdivision subdivision) {
    showDialog(
      context: context,
      builder: (context) => VendorSubdivisionForm(
        workspaceId: subdivision.workspaceId,
        vendorId: subdivision.vendorId,
        subdivision: subdivision,
        contacts: _subdivisionEligibleContacts(isCreateMode: false),
        onSave: (updated) async {
          await _subdivisionService.updateSubdivision(updated);
        },
      ),
    );
  }

  void _archiveSubdivision(VendorSubdivision subdivision) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Subdivision'),
        content: Text(
          'Are you sure you want to archive "${subdivision.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _subdivisionService.deleteSubdivision(subdivision.id);
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
                          Icons.store,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _companyNameController.text.trim(),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            if (_dbaController.text.trim().isNotEmpty)
                              Text(
                                'DBA: ${_dbaController.text.trim()}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_isPreferred)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warningLight,
                            borderRadius: BorderRadius.circular(AppRadius.r16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star,
                                size: 14,
                                color: AppColors.warningDark,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Preferred',
                                style: TextStyle(
                                  color: AppColors.warningDark,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 32),

                  // Classification Section
                  _buildReviewSection(
                    icon: Icons.category,
                    title: 'Classification',
                    content: '$_selectedVendorType • $_selectedCategory',
                  ),
                  const SizedBox(height: 16),

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

                  // Address Section
                  if (_addressController.text.isNotEmpty ||
                      _cityController.text.isNotEmpty ||
                      _stateController.text.isNotEmpty) ...[
                    const SizedBox(height: 16),
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
                  ],

                  // Payment Info Section
                  if (_selectedPaymentTerms != null ||
                      _taxIdController.text.isNotEmpty ||
                      _accountNumberController.text.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildReviewSection(
                      icon: Icons.payment,
                      title: 'Payment Info',
                      content: [
                        if (_selectedPaymentTerms != null)
                          'Terms: ${_selectedPaymentTerms!.displayName}',
                        if (_taxIdController.text.isNotEmpty)
                          'Tax ID: ${_taxIdController.text}',
                        if (_accountNumberController.text.isNotEmpty)
                          'Account #: ${_accountNumberController.text}',
                      ].join('\n'),
                    ),
                  ],

                  // Subdivisions Section
                  if (_pendingSubdivisions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildReviewSection(
                      icon: Icons.store_outlined,
                      title: 'Subdivisions (${_pendingSubdivisions.length})',
                      content: _pendingSubdivisions
                          .map((s) {
                            final addr = s.fullAddress;
                            return addr != null
                                ? '${s.name}\n   ${AddressFormatter.condense(addr)}'
                                : s.name;
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
