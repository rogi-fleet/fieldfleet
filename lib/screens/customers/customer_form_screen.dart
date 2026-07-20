import 'dart:async';

import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../theme/theme.dart';
import '../../models/customer.dart';
import '../../models/customer_contact.dart';
import '../../models/customer_type_config.dart';
import '../../models/customer_status.dart';
import '../../widgets/customers/customer_type_badge.dart';
import '../../models/customer_source.dart';
import '../../models/user.dart';
import '../../services/service_locator.dart';
import '../../services/geocoding_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/customers/contacts_list.dart';
import '../../widgets/customers/tag_input_widget.dart';
import '../../widgets/common/form_section.dart';
import '../../utils/app_logger.dart';
import '../../utils/workspace_gated_loader.dart';
import '../../utils/country_list.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class CustomerFormScreen extends StatelessWidget {
  final String? customerId;

  const CustomerFormScreen({super.key, this.customerId});

  bool get _isEditingCustomer => customerId != null && customerId != 'new';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          !_isEditingCustomer
              ? 'New Company Information'
              : 'Edit Company Information',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/customers');
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/customers');
              }
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
      body: CustomerFormContent(customerId: customerId, isPopup: false),
    );
  }
}

/// The actual form content, extracted for reuse in popups and screens
class CustomerFormContent extends StatefulWidget {
  final String? customerId;
  final bool isPopup;

  const CustomerFormContent({super.key, this.customerId, this.isPopup = false});

  @override
  State<CustomerFormContent> createState() => _CustomerFormContentState();
}

class _CustomerFormContentState extends State<CustomerFormContent>
    with WorkspaceGatedLoader {
  final _formKey = GlobalKey<FormState>();
  dynamic get _customerService => ServiceLocator.customerService;
  String? get _existingCustomerId =>
      widget.customerId == null || widget.customerId == 'new'
      ? null
      : widget.customerId;
  bool get _isEditingCustomer => _existingCustomerId != null;

  // Form controllers
  final _companyController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipController = TextEditingController();
  final _notesController = TextEditingController();
  final _websiteController = TextEditingController();
  final _businessPhoneController = TextEditingController();
  final _businessEmailController = TextEditingController();
  final GeocodingService _geocodingService = GeocodingService();
  Timer? _addressSuggestionDebounce;
  List<AddressSuggestion> _addressSuggestions = const [];
  bool _isLoadingAddressSuggestions = false;
  bool _isSettingAddressFromSuggestion = false;
  String? _workspaceCountryCode;

  String _selectedType = 'Residential';
  bool _taxExempt = false;
  bool _isLoading = false;
  List<CustomerContact> _contacts = [];
  String? _selectedParentId;
  List<Customer> _availableParents = [];
  String? _selectedCountry;
  List<CustomerTypeConfig> _customerTypes = [];

  // Phase 1 fields
  CustomerStatus _selectedStatus = CustomerStatus.active;
  CustomerSource? _selectedSource;
  final _referrerNameController = TextEditingController();
  List<String> _selectedTagIds = [];
  String? _selectedOwnerId;
  List<AppUser> _workspaceUsers = [];

  @override
  void initState() {
    super.initState();
    _addressController.addListener(_onAddressChanged);
    if (_isEditingCustomer) {
      _loadCustomer();
    }
  }

  @override
  void onWorkspaceReady(String workspaceId) {
    // Workspace-scoped reference data (customer types, users, country, parent
    // companies). Deferred via WorkspaceGatedLoader so a cold load / hard
    // refresh (appUser briefly null) doesn't leave these unloaded — the
    // Customer Type dropdown would otherwise render "Residential (removed)".
    _loadAvailableParents();
    _loadWorkspaceUsers();
    _loadCustomerTypes();
    _loadWorkspaceCountryCode();
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
      if (mounted) setState(() => _workspaceUsers = users);
    } catch (_) {}
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
        if (mounted) setState(() => _customerTypes = types);
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

  dynamic _customerTypeSubscription;

  Future<void> _loadAvailableParents() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId != null) {
        // Get all active customers as potential parents
        final customers = await _customerService
            .getCustomers(workspaceId)
            .first;

        if (mounted) {
          setState(() {
            // Filter out the current customer (can't be its own parent)
            _availableParents = customers
                .where((c) => c.id != _existingCustomerId)
                .toList();
          });
        }
      }
    } catch (e) {
      AppLogger.error('Failed to load available parent customers', error: e);
    }
  }

  Future<void> _loadCustomer() async {
    setState(() => _isLoading = true);
    try {
      final customer = await _customerService.getCustomer(_existingCustomerId!);
      if (customer != null && mounted) {
        setState(() {
          _contacts = List.from(customer.contacts);
          _companyController.text = customer.companyName ?? '';
          _isSettingAddressFromSuggestion = true;
          _addressController.text = customer.address ?? '';
          _isSettingAddressFromSuggestion = false;
          _cityController.text = customer.city ?? '';
          _stateController.text = customer.state ?? '';
          _zipController.text = customer.zipCode ?? '';
          _notesController.text = customer.notes ?? '';
          _selectedType = customer.customerType;
          _taxExempt = customer.taxExempt;
          _selectedParentId = customer.parentCustomerId;
          _selectedCountry = customer.country;
          // Phase 1 fields
          _selectedStatus = customer.status;
          _selectedSource = customer.source;
          _referrerNameController.text = customer.referrerName ?? '';
          _websiteController.text = customer.website ?? '';
          _businessPhoneController.text = customer.businessPhone ?? '';
          _businessEmailController.text = customer.businessEmail ?? '';
          _selectedTagIds = List.from(customer.tagIds);
          _selectedOwnerId = customer.accountOwnerId;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(
              'Error loading company information: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 10),
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
    _addressSuggestionDebounce?.cancel();
    _customerTypeSubscription?.cancel();
    _companyController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _notesController.dispose();
    _websiteController.dispose();
    _businessPhoneController.dispose();
    _businessEmailController.dispose();
    _referrerNameController.dispose();
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

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate contacts
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one contact')),
      );
      return;
    }

    // Auto-assign primary if only one contact or no primary selected
    if (_contacts.isNotEmpty &&
        !_contacts.any((c) => c.isPrimary && c.isActive)) {
      final index = _contacts.indexWhere((c) => c.isActive);
      if (index != -1) {
        _contacts[index] = _contacts[index].copyWith(isPrimary: true);
      }
    }

    final primaryCount = _contacts
        .where((c) => c.isPrimary && c.isActive)
        .length;
    if (primaryCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set one contact as primary')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      AppLogger.debug(
        'Saving customer form',
        metadata: {
          'hasAppUser': authProvider.appUser != null,
          'workspaceId': authProvider.appUser?.currentWorkspaceId,
        },
      );

      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId == null || workspaceId.isEmpty) {
        throw Exception('No workspace found. Please ensure you are logged in.');
      }

      if (!_isEditingCustomer) {
        // Validate parent selection doesn't create circular reference
        if (_selectedParentId != null) {
          final canSet = await _customerService.canSetAsParent(
            '',
            _selectedParentId!,
          );
          if (!canSet) {
            throw Exception(
              'Invalid parent selection: Would create circular reference',
            );
          }
        }

        // Create new customer - use updateCustomer directly since we need contacts
        final customer = Customer(
          id: '', // Will be set by Firestore
          workspaceId: workspaceId,
          contacts: _contacts,
          parentCustomerId: _selectedParentId,
          // Phase 1 fields
          status: _selectedStatus,
          source: _selectedSource,
          referrerName: _selectedSource == CustomerSource.referral
              ? _referrerNameController.text.trim().isNotEmpty
                    ? _referrerNameController.text.trim()
                    : null
              : null,
          tagIds: _selectedTagIds,
          accountOwnerId: _selectedOwnerId,
          // Other fields
          companyName: _companyController.text.trim().isEmpty
              ? null
              : _companyController.text.trim(),
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
          website: _websiteController.text.trim().isEmpty
              ? null
              : _websiteController.text.trim(),
          businessPhone: _businessPhoneController.text.trim().isEmpty
              ? null
              : _businessPhoneController.text.trim(),
          businessEmail: _businessEmailController.text.trim().isEmpty
              ? null
              : _businessEmailController.text.trim(),
          country: _selectedCountry,
          customerType: _selectedType,
          taxExempt: _taxExempt,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await _customerService.createCustomerWithContacts(
          workspaceId,
          customer,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Company information created successfully'),
            ),
          );
          if (widget.isPopup) {
            Navigator.of(context).pop();
          } else {
            context.go('/customers');
          }
        }
      } else {
        // Validate parent selection doesn't create circular reference
        if (_selectedParentId != null) {
          final canSet = await _customerService.canSetAsParent(
            _existingCustomerId!,
            _selectedParentId!,
          );
          if (!canSet) {
            throw Exception(
              'Invalid parent selection: Would create circular reference',
            );
          }
        }

        // Update existing customer
        final updates = {
          'contacts': _contacts.map((c) => c.toJson()).toList(),
          'parentCustomerId': _selectedParentId,
          // Phase 1 fields
          'status': _selectedStatus.name,
          'source': _selectedSource?.name,
          'referrerName': _selectedSource == CustomerSource.referral
              ? _referrerNameController.text.trim().isNotEmpty
                    ? _referrerNameController.text.trim()
                    : null
              : null,
          'tagIds': _selectedTagIds,
          'accountOwnerId': _selectedOwnerId,
          // Other fields
          'companyName': _companyController.text.trim().isEmpty
              ? null
              : _companyController.text.trim(),
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
          'website': _websiteController.text.trim().isEmpty
              ? null
              : _websiteController.text.trim(),
          'businessPhone': _businessPhoneController.text.trim().isEmpty
              ? null
              : _businessPhoneController.text.trim(),
          'businessEmail': _businessEmailController.text.trim().isEmpty
              ? null
              : _businessEmailController.text.trim(),
          'country': _selectedCountry,
          'customerType': _selectedType,
          'taxExempt': _taxExempt,
          'notes': _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        };

        // Update legacy fields from primary contact for backward compatibility
        final primary = _contacts.firstWhere((c) => c.isPrimary && c.isActive);
        updates['name'] = primary.name;
        updates['email'] = primary.email;
        updates['phone'] = primary.phone;

        await _customerService.updateCustomer(_existingCustomerId!, updates);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Company information updated successfully'),
            ),
          );
          if (widget.isPopup) {
            Navigator.of(context).pop();
          } else {
            context.go('/customers');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'save company information'),
            ),
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
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.appUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                // Contacts Section
                ContactsList(
                  contacts: _contacts,
                  onContactsChanged: (contacts) {
                    setState(() {
                      _contacts = contacts;
                    });
                  },
                ),
                const SizedBox(height: 24),

                FormSection(
                  title: 'Classification',
                  child: Column(
                    children: [
                      StackedField(
                        label: 'Status',
                        child: DropdownButtonFormField<CustomerStatus>(
                          borderRadius: AppRadius.cardRadius,
                          initialValue: _selectedStatus,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            helperText: 'Customer relationship status',
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
                      ),
                      const SizedBox(height: 16),
                      StackedField(
                        label: 'Source',
                        child: DropdownButtonFormField<CustomerSource>(
                          borderRadius: AppRadius.cardRadius,
                          initialValue: _selectedSource,
                          decoration: const InputDecoration(
                            hintText: 'How did you acquire this customer?',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<CustomerSource>(
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
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Consumer<AuthProvider>(
                        builder: (context, authProvider, _) {
                          final workspaceId =
                              authProvider.appUser?.currentWorkspaceId;
                          if (workspaceId == null) {
                            return const SizedBox.shrink();
                          }
                          return TagInputWidget(
                            workspaceId: workspaceId,
                            selectedTagIds: _selectedTagIds,
                            onTagsChanged: (tagIds) {
                              setState(() => _selectedTagIds = tagIds);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                FormSection(
                  title: 'Assignment',
                  child: StackedField(
                    label: 'Account Owner',
                    child: DropdownButtonFormField<String>(
                      borderRadius: AppRadius.cardRadius,
                      value:
                          _workspaceUsers.any((u) => u.id == _selectedOwnerId)
                          ? _selectedOwnerId
                          : null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Assign to a team member',
                        prefixIcon: Icon(Icons.person_outline),
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
                      onChanged: (value) =>
                          setState(() => _selectedOwnerId = value),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                FormSection(
                  title: 'Company Information',
                  child: StackedField(
                    label: 'Company Name',
                    child: TextFormField(
                      controller: _companyController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Optional',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                FormSection(
                  title: 'Address',
                  child: Column(
                    children: [
                      StackedField(
                        label: 'Street Address',
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _addressController,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'Start typing to search addresses...',
                                prefixIcon: Icon(Icons.location_on),
                              ),
                            ),
                            if (_isLoadingAddressSuggestions)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.cardBorder,
                                  ),
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                child: const Row(
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text('Searching addresses...'),
                                  ],
                                ),
                              ),
                            if (_addressSuggestions.isNotEmpty)
                              Container(
                                width: double.infinity,
                                constraints: const BoxConstraints(
                                  maxHeight: 220,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.cardBorder,
                                  ),
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  color: Colors.white,
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: _addressSuggestions.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    color: AppColors.cardBorder,
                                  ),
                                  itemBuilder: (context, index) {
                                    final suggestion =
                                        _addressSuggestions[index];
                                    final condensed = suggestion
                                        .singleLineAddress(
                                          typedQuery: _addressController.text
                                              .trim(),
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
                                      onTap: () =>
                                          _selectAddressSuggestion(suggestion),
                                    );
                                  },
                                ),
                              ),
                          ],
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
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
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
                      const SizedBox(height: 16),
                      StackedField(
                        label: CountryList.getPostalCodeLabel(_selectedCountry),
                        child: TextFormField(
                          controller: _zipController,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.text,
                        ),
                      ),
                      const SizedBox(height: 16),
                      StackedField(
                        label: 'Country',
                        child: DropdownButtonFormField<String>(
                          borderRadius: AppRadius.cardRadius,
                          initialValue: _selectedCountry,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Select a country',
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
                            setState(() {
                              _selectedCountry = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                FormSection(
                  title: 'Business Information',
                  child: Column(
                    children: [
                      StackedField(
                        label: 'Customer Type',
                        child: Builder(
                          builder: (context) {
                            // If current type not in list, include it as an option
                            final hasCurrentType = _customerTypes.any(
                              (t) => t.name == _selectedType,
                            );
                            return DropdownButtonFormField<String>(
                              borderRadius: AppRadius.cardRadius,
                              value: _selectedType,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                if (!hasCurrentType && _selectedType.isNotEmpty)
                                  DropdownMenuItem(
                                    value: _selectedType,
                                    child: Text('$_selectedType (removed)'),
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
                                  setState(() => _selectedType = value);
                                }
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      StackedField(
                        label: 'Parent Company',
                        child: DropdownButtonFormField<String>(
                          borderRadius: AppRadius.cardRadius,
                          initialValue: _selectedParentId,
                          decoration: const InputDecoration(
                            hintText: 'Optional - for sub-companies',
                            border: OutlineInputBorder(),
                            helperText:
                                'Link this company to a parent for consolidated billing',
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('None (Independent Company)'),
                            ),
                            ..._availableParents.map((parent) {
                              return DropdownMenuItem<String>(
                                value: parent.id,
                                child: Text(parent.displayName),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedParentId = value);
                          },
                        ),
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
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: StackedField(
                              label: 'Business Phone',
                              child: TextFormField(
                                controller: _businessPhoneController,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.phone),
                                  hintText: 'Main line for the business',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StackedField(
                              label: 'Business Email',
                              child: TextFormField(
                                controller: _businessEmailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.email),
                                  hintText: 'billing@example.com',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        title: const Text('Tax Exempt'),
                        subtitle: const Text(
                          'Company is exempt from sales tax',
                        ),
                        value: _taxExempt,
                        onChanged: (value) {
                          setState(() => _taxExempt = value ?? false);
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                FormSection(
                  title: 'Notes',
                  child: StackedField(
                    label: 'Internal Notes',
                    child: TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        hintText: 'Add notes about this company...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 4,
                      maxLength: 1000,
                      validator: (value) {
                        if (value != null && value.length > 1000) {
                          return 'Notes must be 1000 characters or less';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Save button
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveCustomer,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          !_isEditingCustomer
                              ? 'Save Company Information'
                              : 'Update Company Information',
                        ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
  }
}
