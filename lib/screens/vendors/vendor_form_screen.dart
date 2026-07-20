import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../theme/theme.dart';
import '../../models/vendor.dart';
import '../../models/customer_type_config.dart';
import '../../models/payment_terms.dart';
import '../../models/vendor_contact.dart';
import '../../services/service_locator.dart';
import '../../services/geocoding_service.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../widgets/common/form_section.dart';
import '../../widgets/common/primary_contact_prompt.dart';
import '../../utils/country_list.dart';
import '../../widgets/vendors/vendor_contact_form_dialog.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class VendorFormScreen extends StatelessWidget {
  final String? vendorId;

  const VendorFormScreen({super.key, this.vendorId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(vendorId == null ? 'Add Vendor' : 'Edit Vendor'),
      ),
      body: VendorFormContent(vendorId: vendorId, isPopup: false),
    );
  }
}

/// The actual form content, extracted for reuse in popups and screens
class VendorFormContent extends StatefulWidget {
  final String? vendorId;
  final bool isPopup;

  const VendorFormContent({super.key, this.vendorId, this.isPopup = false});

  @override
  State<VendorFormContent> createState() => _VendorFormContentState();
}

class _VendorFormContentState extends State<VendorFormContent>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _vendorService = ServiceLocator.vendorService;

  bool _isLoading = false;
  bool _showFieldErrors = false;
  String? _validationMessage;
  late final AnimationController _shakeController;
  Vendor? _existingVendor;

  // Form fields
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _dbaController = TextEditingController();
  final TextEditingController _businessPhoneController =
      TextEditingController();
  final TextEditingController _businessEmailController =
      TextEditingController();
  final TextEditingController _websiteController = TextEditingController();
  final TextEditingController _taxIdController = TextEditingController();
  final TextEditingController _accountNumberController =
      TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _zipCodeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _discountRateController = TextEditingController();
  final GeocodingService _geocodingService = GeocodingService();
  Timer? _addressSuggestionDebounce;
  List<AddressSuggestion> _addressSuggestions = const [];
  bool _isLoadingAddressSuggestions = false;
  bool _isSettingAddressFromSuggestion = false;
  String? _workspaceCountryCode;

  String _selectedCategory = 'Other';
  String _selectedType = 'Material Supplier';
  PaymentTerms? _selectedPaymentTerms;
  bool _isPreferred = false;
  List<VendorContact> _contacts = [];
  String? _selectedCountry;
  List<CustomerTypeConfig> _vendorTypes = [];
  List<CustomerTypeConfig> _vendorCategories = [];
  dynamic _vendorTypeSub;
  dynamic _vendorCatSub;

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
    if (widget.vendorId != null) {
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
      if (mounted) setState(() => _vendorTypes = types);
    });
    _vendorCatSub = service.getVendorCategories(workspaceId).listen((cats) {
      if (mounted) setState(() => _vendorCategories = cats);
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
      if (vendor != null) {
        setState(() {
          _existingVendor = vendor;
          _companyNameController.text = vendor.companyName;
          _dbaController.text = vendor.dba ?? '';
          _businessPhoneController.text = vendor.businessPhone ?? '';
          _businessEmailController.text = vendor.businessEmail ?? '';
          _websiteController.text = vendor.website ?? '';
          _taxIdController.text = vendor.taxId ?? '';
          _accountNumberController.text = vendor.accountNumber ?? '';
          _isSettingAddressFromSuggestion = true;
          _addressController.text = vendor.address ?? '';
          _isSettingAddressFromSuggestion = false;
          _cityController.text = vendor.city ?? '';
          _stateController.text = vendor.state ?? '';
          _zipCodeController.text = vendor.zipCode ?? '';
          _notesController.text = vendor.notes ?? '';
          _selectedCategory = vendor.category;
          _selectedType = vendor.vendorType;
          _selectedPaymentTerms = vendor.paymentTerms;
          _isPreferred = vendor.isPreferred;
          _contacts = List.from(vendor.contacts);
          _selectedCountry = vendor.country;
          _discountRateController.text =
              vendor.discountRate?.toStringAsFixed(2) ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'loading vendor'),
            ),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _vendorTypeSub?.cancel();
    _vendorCatSub?.cancel();
    _addressSuggestionDebounce?.cancel();
    _companyNameController.dispose();
    _dbaController.dispose();
    _businessPhoneController.dispose();
    _businessEmailController.dispose();
    _websiteController.dispose();
    _taxIdController.dispose();
    _accountNumberController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipCodeController.dispose();
    _notesController.dispose();
    _discountRateController.dispose();
    _shakeController.dispose();
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
      _zipCodeController.text = suggestion.postcode!;
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

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildValidationBanner(),
                  _buildCompanySection(),
                  const SizedBox(height: 24),
                  _buildClassificationSection(),
                  const SizedBox(height: 24),
                  _buildContactsSection(),
                  const SizedBox(height: 24),
                  _buildBusinessDetailsSection(),
                  const SizedBox(height: 24),
                  _buildNotesSection(),
                  const SizedBox(height: 32),
                  _buildSubmitButton(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
  }

  void _clearValidationErrors() {
    if (_showFieldErrors || _validationMessage != null) {
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

  Widget _buildCompanySection() {
    return FormSection(
      title: 'Company Information',
      child: Column(
        children: [
          StackedField(
            label: 'Company Name *',
            child: TextFormField(
              controller: _companyNameController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Company name is required';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 16),
          StackedField(
            label: 'DBA (Doing Business As)',
            child: TextFormField(
              controller: _dbaController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
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
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StackedField(
                  label: 'Business Email',
                  child: TextFormField(
                    controller: _businessEmailController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassificationSection() {
    return FormSection(
      title: 'Classification',
      child: Column(
        children: [
          StackedField(
            label: 'Category *',
            child: Builder(
              builder: (context) {
                final hasCat = _vendorCategories.any(
                  (c) => c.name == _selectedCategory,
                );
                return DropdownButtonFormField<String>(
                  borderRadius: AppRadius.cardRadius,
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    if (!hasCat && _selectedCategory.isNotEmpty)
                      DropdownMenuItem(
                        value: _selectedCategory,
                        child: Text('$_selectedCategory (removed)'),
                      ),
                    ..._vendorCategories.map(
                      (c) =>
                          DropdownMenuItem(value: c.name, child: Text(c.name)),
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
          ),
          const SizedBox(height: 16),
          StackedField(
            label: 'Vendor Type *',
            child: Builder(
              builder: (context) {
                final hasType = _vendorTypes.any(
                  (t) => t.name == _selectedType,
                );
                return DropdownButtonFormField<String>(
                  borderRadius: AppRadius.cardRadius,
                  initialValue: _selectedType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    if (!hasType && _selectedType.isNotEmpty)
                      DropdownMenuItem(
                        value: _selectedType,
                        child: Text('$_selectedType (removed)'),
                      ),
                    ..._vendorTypes.map(
                      (t) =>
                          DropdownMenuItem(value: t.name, child: Text(t.name)),
                    ),
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
          SwitchListTile(
            title: const Text('Preferred Vendor'),
            subtitle: const Text('Mark this vendor as preferred'),
            value: _isPreferred,
            onChanged: (value) {
              setState(() => _isPreferred = value);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _discountRateController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Default discount rate',
              hintText: 'e.g. 5 for 5% off list',
              suffixText: '%',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final n = double.tryParse(v.trim());
              if (n == null) return 'Enter a number';
              if (n < 0 || n > 100) return 'Must be between 0 and 100';
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContactsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Contacts',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: _addContact,
              icon: const Icon(Icons.add),
              label: const Text('Add Contact'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_contacts.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Center(
                child: Text(
                  'At least one contact is required',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          )
        else
          ..._contacts.asMap().entries.map((entry) {
            final index = entry.key;
            final contact = entry.value;
            return _buildContactCard(index, contact);
          }),
      ],
    );
  }

  Widget _buildContactCard(int index, VendorContact contact) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Contact ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_contacts.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _removeContact(index),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Name *',
              child: TextFormField(
                initialValue: contact.name,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Contact name is required';
                  }
                  return null;
                },
                onChanged: (value) {
                  _contacts[index] = contact.copyWith(name: value);
                },
              ),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Title',
              child: TextFormField(
                initialValue: contact.title,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (value) {
                  _contacts[index] = contact.copyWith(
                    title: value.isEmpty ? null : value,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Email',
              child: TextFormField(
                initialValue: contact.email,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                onChanged: (value) {
                  _contacts[index] = contact.copyWith(
                    email: value.isEmpty ? null : value,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Phone',
              child: TextFormField(
                initialValue: contact.phone,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                onChanged: (value) {
                  _contacts[index] = contact.copyWith(
                    phone: value.isEmpty ? null : value,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            StackedField(
              label: 'Cell Phone',
              child: TextFormField(
                initialValue: contact.mobilePhone,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_android),
                ),
                keyboardType: TextInputType.phone,
                onChanged: (value) {
                  _contacts[index] = contact.copyWith(
                    mobilePhone: value.isEmpty ? null : value,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('Primary Contact'),
              value: contact.isPrimary,
              onChanged: (value) {
                if (value == true) {
                  setState(() {
                    // Unset other primary contacts
                    for (int i = 0; i < _contacts.length; i++) {
                      _contacts[i] = _contacts[i].copyWith(
                        isPrimary: i == index,
                      );
                    }
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessDetailsSection() {
    return FormSection(
      title: 'Business Details',
      child: Column(
        children: [
          StackedField(
            label: 'Tax ID',
            child: TextFormField(
              controller: _taxIdController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(height: 16),
          StackedField(
            label: 'Account Number',
            child: TextFormField(
              controller: _accountNumberController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                helperText: 'Your account number with this vendor',
              ),
            ),
          ),
          const SizedBox(height: 16),
          StackedField(
            label: 'Payment Terms',
            child: DropdownButtonFormField<PaymentTerms>(
              borderRadius: AppRadius.cardRadius,
              initialValue: _selectedPaymentTerms,
              decoration: const InputDecoration(border: OutlineInputBorder()),
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
          StackedField(
            label: 'Address',
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
              const SizedBox(width: 16),
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
              const SizedBox(width: 16),
              Expanded(
                child: StackedField(
                  label: CountryList.getPostalCodeLabel(_selectedCountry),
                  child: TextFormField(
                    controller: _zipCodeController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
            ],
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
                      color: country.isEnabled ? null : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
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
    );
  }

  Widget _buildNotesSection() {
    return FormSection(
      title: 'Notes',
      child: StackedField(
        label: 'Notes',
        child: TextFormField(
          controller: _notesController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Add any additional notes about this vendor...',
          ),
          maxLines: 5,
          maxLength: 2000,
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        final dx = _shakeController.isAnimating
            ? math.sin(_shakeController.value * math.pi * 4) * 6
            : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _isLoading ? null : _handleSubmit,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Text(
              widget.vendorId == null ? 'Create Vendor' : 'Update Vendor',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addContact() async {
    final result = await showVendorContactFormDialog(context);

    if (result == null || !mounted) {
      return;
    }

    final shouldMakePrimary = await showPrimaryContactPrompt(
      context,
      contactName: result.name,
      ownerLabel: 'vendor',
    );

    setState(() {
      if (shouldMakePrimary) {
        for (int i = 0; i < _contacts.length; i++) {
          _contacts[i] = _contacts[i].copyWith(isPrimary: false);
        }
      }

      _contacts.add(result.copyWith(isPrimary: shouldMakePrimary));
    });
  }

  void _removeContact(int index) {
    setState(() {
      final wasPrimary = _contacts[index].isPrimary;
      _contacts.removeAt(index);

      // If we removed the primary contact, make the first one primary
      if (wasPrimary && _contacts.isNotEmpty) {
        _contacts[0] = _contacts[0].copyWith(isPrimary: true);
      }
    });
  }

  Future<void> _handleSubmit() async {
    _clearValidationErrors();

    final formValid = _formKey.currentState!.validate();

    if (_contacts.isEmpty) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = 'At least one contact is required';
      });
      _shakeController.forward(from: 0);
      return;
    }

    final primaryCount = _contacts.where((c) => c.isPrimary).length;
    if (primaryCount != 1) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = 'Exactly one contact must be marked as primary';
      });
      _shakeController.forward(from: 0);
      return;
    }

    if (!formValid) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = 'Please fix the errors above';
      });
      _shakeController.forward(from: 0);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<app_auth.AuthProvider>(
        context,
        listen: false,
      );
      final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
      final userId = authProvider.appUser?.id ?? '';

      final now = DateTime.now();

      final vendor = Vendor(
        id: widget.vendorId ?? '',
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
        contacts: _contacts,
        website: _websiteController.text.trim().isEmpty
            ? null
            : _websiteController.text.trim(),
        category: _selectedCategory,
        vendorType: _selectedType,
        // Preserve fields that have no UI control yet — passing nothing
        // would make the Vendor constructor reset them to empty/null and
        // silently destroy data on every save of an existing vendor.
        tags: _existingVendor?.tags,
        insurance: _existingVendor?.insurance,
        licenses: _existingVendor?.licenses,
        taxId: _taxIdController.text.trim().isEmpty
            ? null
            : _taxIdController.text.trim(),
        accountNumber: _accountNumberController.text.trim().isEmpty
            ? null
            : _accountNumberController.text.trim(),
        paymentTerms: _selectedPaymentTerms,
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        state: _stateController.text.trim().isEmpty
            ? null
            : _stateController.text.trim(),
        zipCode: _zipCodeController.text.trim().isEmpty
            ? null
            : _zipCodeController.text.trim(),
        country: _selectedCountry,
        isPreferred: _isPreferred,
        discountRate: _discountRateController.text.trim().isEmpty
            ? null
            : double.tryParse(_discountRateController.text.trim()),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: _existingVendor?.createdAt ?? now,
        updatedAt: now,
        createdBy: _existingVendor?.createdBy ?? userId,
      );

      String? createdVendorId;
      if (widget.vendorId == null) {
        createdVendorId = await _vendorService.createVendor(vendor);
      } else {
        await _vendorService.updateVendor(vendor);
      }

      if (mounted) {
        if (widget.isPopup) {
          Navigator.of(context).pop();
        } else {
          context.go('/vendors');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              createdVendorId != null
                  ? 'Vendor created successfully'
                  : 'Vendor updated successfully',
            ),
            duration: createdVendorId != null
                ? const Duration(seconds: 5)
                : const Duration(seconds: 4),
            action: createdVendorId != null
                ? SnackBarAction(
                    label: 'Add Subdivisions',
                    onPressed: () => context.go('/vendors/$createdVendorId'),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'saving vendor'),
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
}
