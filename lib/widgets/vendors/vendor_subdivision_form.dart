import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/vendor_contact.dart';
import '../../models/vendor_subdivision.dart';
import '../../services/geocoding_service.dart';
import '../../theme/theme.dart';
import '../../utils/country_list.dart';

class VendorSubdivisionForm extends StatefulWidget {
  final String workspaceId;
  final String vendorId;
  final VendorSubdivision? subdivision;
  final List<VendorContact> contacts;
  final Future<void> Function(VendorSubdivision subdivision) onSave;

  const VendorSubdivisionForm({
    super.key,
    required this.workspaceId,
    required this.vendorId,
    this.subdivision,
    required this.contacts,
    required this.onSave,
  });

  @override
  State<VendorSubdivisionForm> createState() => _VendorSubdivisionFormState();
}

class _VendorSubdivisionFormState extends State<VendorSubdivisionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  late final TextEditingController _zipController;
  late final TextEditingController _countryController;
  late final TextEditingController _accessDetailsController;
  late final TextEditingController _notesController;
  String? _selectedContactId;
  bool _saving = false;

  // Address autocomplete
  final GeocodingService _geocodingService = GeocodingService();
  Timer? _addressSuggestionDebounce;
  List<AddressSuggestion> _addressSuggestions = const [];
  bool _isLoadingAddressSuggestions = false;
  bool _isSettingAddressFromSuggestion = false;

  bool get _isEditing => widget.subdivision != null;

  @override
  void initState() {
    super.initState();
    final sub = widget.subdivision;
    _nameController = TextEditingController(text: sub?.name ?? '');
    _addressController = TextEditingController(text: sub?.address ?? '');
    _cityController = TextEditingController(text: sub?.city ?? '');
    _stateController = TextEditingController(text: sub?.state ?? '');
    _zipController = TextEditingController(text: sub?.zipCode ?? '');
    _countryController = TextEditingController(text: sub?.country ?? '');
    _accessDetailsController = TextEditingController(
      text: sub?.accessDetails ?? '',
    );
    _notesController = TextEditingController(text: sub?.notes ?? '');
    _selectedContactId = sub?.contactId;
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
                    _isEditing ? 'Edit Subdivision' : 'Create Subdivision',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Subdivision Name *',
                      hintText: 'e.g., Sales, Warehouse, Service Dept',
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
                    DropdownButtonFormField<String?>(
                      borderRadius: AppRadius.cardRadius,
                      initialValue: _selectedContactId,
                      decoration: const InputDecoration(
                        labelText: 'Site Contact',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('None'),
                        ),
                        ...widget.contacts
                            .where((c) => c.isActive && c.id != null)
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                  c.title != null && c.title!.isNotEmpty
                                      ? '${c.name} (${c.title})'
                                      : c.name,
                                ),
                              ),
                            ),
                      ],
                      onChanged: (v) => setState(() => _selectedContactId = v),
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
                'Could not geocode address. Subdivision will be saved without map coordinates.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }

      final now = DateTime.now();
      final subdivision = VendorSubdivision(
        id: widget.subdivision?.id ?? '',
        workspaceId: widget.workspaceId,
        vendorId: widget.vendorId,
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
        latitude: lat ?? widget.subdivision?.latitude,
        longitude: lng ?? widget.subdivision?.longitude,
        contactId: _selectedContactId,
        accessDetails: _accessDetailsController.text.trim().isEmpty
            ? null
            : _accessDetailsController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        isActive: widget.subdivision?.isActive ?? true,
        createdAt: widget.subdivision?.createdAt ?? now,
        updatedAt: now,
      );

      await widget.onSave(subdivision);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving subdivision: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
