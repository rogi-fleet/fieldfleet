import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/customer_contact.dart';
import '../../models/customer_location.dart';
import '../../services/geocoding_service.dart';
import '../../theme/theme.dart';
import '../../utils/country_list.dart';

class CustomerLocationForm extends StatefulWidget {
  final String workspaceId;
  final String customerId;
  final CustomerLocation? location;
  final CustomerLocation? initialLocation;
  final List<CustomerContact> contacts;
  final Future<void> Function(CustomerLocation location) onSave;

  const CustomerLocationForm({
    super.key,
    required this.workspaceId,
    required this.customerId,
    this.location,
    this.initialLocation,
    required this.contacts,
    required this.onSave,
  });

  @override
  State<CustomerLocationForm> createState() => _CustomerLocationFormState();
}

class _CustomerLocationFormState extends State<CustomerLocationForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  late final TextEditingController _zipController;
  late final TextEditingController _countryController;
  late final TextEditingController _accessDetailsController;
  late final TextEditingController _notesController;
  List<String> _selectedContactIds = [];
  bool _saving = false;

  // Address autocomplete
  final GeocodingService _geocodingService = GeocodingService();
  Timer? _addressSuggestionDebounce;
  List<AddressSuggestion> _addressSuggestions = const [];
  bool _isLoadingAddressSuggestions = false;
  bool _isSettingAddressFromSuggestion = false;

  bool get _isEditing => widget.location != null;

  @override
  void initState() {
    super.initState();
    final loc = widget.location ?? widget.initialLocation;
    _nameController = TextEditingController(text: loc?.name ?? '');
    _addressController = TextEditingController(text: loc?.address ?? '');
    _cityController = TextEditingController(text: loc?.city ?? '');
    _stateController = TextEditingController(text: loc?.state ?? '');
    _zipController = TextEditingController(text: loc?.zipCode ?? '');
    _countryController = TextEditingController(text: loc?.country ?? '');
    _accessDetailsController = TextEditingController(
      text: loc?.accessDetails ?? '',
    );
    _notesController = TextEditingController(text: loc?.notes ?? '');
    _selectedContactIds = List<String>.from(loc?.contactIds ?? []);
    _addressController.addListener(_onAddressChanged);
  }

  @override
  void dispose() {
    _addressSuggestionDebounce?.cancel();
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _countryController.dispose();
    _accessDetailsController.dispose();
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

    final suggestions = await _geocodingService.searchAddressSuggestions(query);

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
        _countryController.text = countryName;
      }
    }
    setState(() {
      _addressSuggestions = const [];
      _isLoadingAddressSuggestions = false;
    });
    _isSettingAddressFromSuggestion = false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isEditing ? 'Edit Location' : 'Create Location',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Location Name *',
                      hintText: 'e.g., Main Office, Unit 101, TSCC 3066',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Name is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Street Address',
                      hintText: 'Start typing to search addresses...',
                      prefixIcon: Icon(Icons.location_on_outlined),
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _cityController,
                          decoration: const InputDecoration(labelText: 'City'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _stateController,
                          decoration: const InputDecoration(
                            labelText: 'State / Province',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _zipController,
                          decoration: const InputDecoration(
                            labelText: 'ZIP / Postal Code',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _countryController,
                          decoration: const InputDecoration(
                            labelText: 'Country',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (widget.contacts.isNotEmpty) ...[
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Site Contacts',
                        contentPadding: EdgeInsets.fromLTRB(12, 8, 12, 8),
                      ),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: widget.contacts.where((c) => c.isActive).map((
                          c,
                        ) {
                          final selected = _selectedContactIds.contains(c.id);
                          return FilterChip(
                            label: Text(
                              c.title != null && c.title!.isNotEmpty
                                  ? '${c.name} (${c.title})'
                                  : c.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                            selected: selected,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  if (c.id != null) {
                                    _selectedContactIds.add(c.id!);
                                  }
                                } else {
                                  _selectedContactIds.remove(c.id);
                                }
                              });
                            },
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _accessDetailsController,
                    decoration: const InputDecoration(
                      labelText: 'Access Details',
                      hintText:
                          'Gate codes, keys, hours, parking instructions...',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _saving ? null : _handleSave,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_isEditing ? 'Save' : 'Create'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      // Geocode the address
      double? lat;
      double? lng;
      final addressText = _addressController.text.trim();
      if (addressText.isNotEmpty) {
        final parts = <String>[addressText];
        if (_cityController.text.trim().isNotEmpty) {
          parts.add(_cityController.text.trim());
        }
        if (_stateController.text.trim().isNotEmpty) {
          parts.add(_stateController.text.trim());
        }
        if (_zipController.text.trim().isNotEmpty) {
          parts.add(_zipController.text.trim());
        }
        final fullAddr = parts.join(', ');
        final result = await _geocodingService.geocodeAddress(fullAddr);
        if (result != null) {
          lat = result.latitude;
          lng = result.longitude;
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not geocode address. Location will be saved without map coordinates.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }

      final now = DateTime.now();
      final location = CustomerLocation(
        id: widget.location?.id ?? '',
        workspaceId: widget.workspaceId,
        customerId: widget.customerId,
        name: _nameController.text.trim(),
        address: addressText.isEmpty ? null : addressText,
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        state: _stateController.text.trim().isEmpty
            ? null
            : _stateController.text.trim(),
        zipCode: _zipController.text.trim().isEmpty
            ? null
            : _zipController.text.trim(),
        country: _countryController.text.trim().isEmpty
            ? null
            : _countryController.text.trim(),
        latitude: lat ?? widget.location?.latitude,
        longitude: lng ?? widget.location?.longitude,
        contactIds: _selectedContactIds,
        accessDetails: _accessDetailsController.text.trim().isEmpty
            ? null
            : _accessDetailsController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        isActive: widget.location?.isActive ?? true,
        createdAt: widget.location?.createdAt ?? now,
        updatedAt: now,
      );

      await widget.onSave(location);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving location: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
