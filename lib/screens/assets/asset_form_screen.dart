import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/asset.dart';
import '../../models/asset_category.dart';
import '../../models/asset_category_config.dart';
import '../../services/supabase/asset_category_service.dart';
import '../../utils/workspace_gated_loader.dart';
import '../../services/supabase/asset_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../theme/theme.dart';
import '../../utils/currency_utils.dart';
import '../../widgets/files/file_tag_input.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';

class AssetFormScreen extends StatelessWidget {
  final String? assetId;

  const AssetFormScreen({super.key, this.assetId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(assetId == null ? 'New Equipment' : 'Edit Equipment')),
      body: AssetFormContent(assetId: assetId, isPopup: false),
    );
  }
}

class AssetFormContent extends StatefulWidget {
  final String? assetId;
  final bool isPopup;
  final ValueNotifier<bool>? dirtyNotifier;

  const AssetFormContent({
    super.key,
    this.assetId,
    this.isPopup = false,
    this.dirtyNotifier,
  });

  @override
  State<AssetFormContent> createState() => _AssetFormContentState();
}

class _AssetFormContentState extends State<AssetFormContent>
    with WorkspaceGatedLoader {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _serialNumberController = TextEditingController();
  final _qrCodeController = TextEditingController();
  final _purchaseCostController = TextEditingController();
  final _notesController = TextEditingController();
  final _locationController = TextEditingController();
  final _dailyRentalController = TextEditingController();
  final _weeklyRentalController = TextEditingController();
  final _monthlyRentalController = TextEditingController();
  final _replacementCostController = TextEditingController();

  bool _isLeasable = false;
  DateTime? _purchaseDate;
  String _status = 'available';
  String _categoryName = 'Other';
  List<AssetCategoryConfig> _availableCategories = const [];
  bool _isLoading = false;
  bool _isUploadingPhoto = false;
  List<String> _photoUrls = const [];
  List<String> _tags = const [];
  List<String> _suggestedTags = const [];
  bool _initialLoadComplete = false;

  final List<String> _statusOptions = [
    'available',
    'assigned',
    'maintenance',
    'retired',
  ];

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_markDirty);
    _descriptionController.addListener(_markDirty);
    _serialNumberController.addListener(_markDirty);
    _qrCodeController.addListener(_markDirty);
    _purchaseCostController.addListener(_markDirty);
    _notesController.addListener(_markDirty);
    _locationController.addListener(_markDirty);
    _dailyRentalController.addListener(_markDirty);
    _weeklyRentalController.addListener(_markDirty);
    _monthlyRentalController.addListener(_markDirty);
    _replacementCostController.addListener(_markDirty);
    if (widget.assetId != null) {
      _loadAsset();
    } else {
      _qrCodeController.text = 'asset:${DateTime.now().millisecondsSinceEpoch}';
      _initialLoadComplete = true;
    }
  }

  // This screen resolves the workspace via activeWorkspaceId (with a fallback),
  // not currentWorkspaceId — so override the mixin's resolver.
  @override
  String? resolveWorkspaceId(AuthProvider auth) =>
      auth.appUser?.activeWorkspaceId ?? auth.appUser?.workspaceId;

  @override
  void onWorkspaceReady(String workspaceId) {
    // Ref data (tags, categories) loaded once the workspace hydrates via
    // WorkspaceGatedLoader — avoids the cold-load empty Category dropdown.
    _loadTagSuggestions();
    _loadCategories();
  }

  Future<void> _loadTagSuggestions() async {
    final authProvider = context.read<AuthProvider>();
    final appUser = authProvider.appUser;
    final workspaceId =
        appUser?.activeWorkspaceId ?? appUser?.workspaceId ?? '';
    if (workspaceId.isEmpty) return;
    try {
      final tags =
          await SupabaseAssetService(workspaceId: workspaceId).getDistinctTags();
      if (!mounted) return;
      setState(() => _suggestedTags = tags);
    } catch (_) {
      // Suggestions are nice-to-have; failure shouldn't block the form.
    }
  }

  Widget _buildCategoryDropdown() {
    if (_availableCategories.isEmpty) {
      // First paint before categories load: fall back to enum so the
      // form is interactive immediately.
      final fallback = AssetCategory.fromName(_categoryName);
      return DropdownButtonFormField<String>(
        borderRadius: AppRadius.cardRadius,
        initialValue: fallback.label,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: AssetCategory.values
            .map(
              (c) => DropdownMenuItem(
                value: c.label,
                child: Row(
                  children: [
                    Icon(c.icon, size: 18, color: c.color),
                    const SizedBox(width: 8),
                    Text(c.label),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) {
            _markDirty();
            setState(() => _categoryName = value);
          }
        },
      );
    }

    final hasMatch =
        _availableCategories.any((c) => c.name == _categoryName);
    return DropdownButtonFormField<String>(
      borderRadius: AppRadius.cardRadius,
      initialValue: hasMatch ? _categoryName : _availableCategories.first.name,
      decoration: const InputDecoration(border: OutlineInputBorder()),
      items: _availableCategories
          .map(
            (c) => DropdownMenuItem(
              value: c.name,
              child: Row(
                children: [
                  Icon(c.icon, size: 18, color: c.colorValue),
                  const SizedBox(width: 8),
                  Text(c.name),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          _markDirty();
          setState(() => _categoryName = value);
        }
      },
    );
  }

  Future<void> _loadCategories() async {
    final authProvider = context.read<AuthProvider>();
    final appUser = authProvider.appUser;
    final workspaceId =
        appUser?.activeWorkspaceId ?? appUser?.workspaceId ?? '';
    if (workspaceId.isEmpty) return;
    try {
      final categories =
          await SupabaseAssetCategoryService().getCategories(workspaceId);
      if (!mounted) return;
      setState(() {
        _availableCategories = categories;
        // If the asset's stored category isn't in the workspace list
        // (e.g. it was deleted), fall back to 'Other'.
        if (!categories.any((c) => c.name == _categoryName)) {
          final fallback = categories.firstWhere(
            (c) => c.name == 'Other',
            orElse: () => categories.isEmpty
                ? AssetCategoryConfig(
                    id: '',
                    workspaceId: workspaceId,
                    name: 'Other',
                    color: '#9E9E9E',
                    iconName: 'category_outlined',
                    sortOrder: 0,
                    isDefault: true,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  )
                : categories.first,
          );
          _categoryName = fallback.name;
        }
      });
    } catch (_) {
      // Form still works; we'll fall back to enum-based dropdown below.
    }
  }

  void _markDirty() {
    if (_initialLoadComplete) {
      widget.dirtyNotifier?.value = true;
    }
  }

  Future<void> _loadAsset() async {
    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final appUser = authProvider.appUser;
      final workspaceId =
          appUser?.activeWorkspaceId ?? appUser?.workspaceId ?? '';

      final assetService = SupabaseAssetService(workspaceId: workspaceId);
      final loaded = await assetService.getAsset(widget.assetId!);

      if (loaded != null) {
        _nameController.text = loaded.name;
        _descriptionController.text = loaded.description ?? '';
        _serialNumberController.text = loaded.serialNumber ?? '';
        _qrCodeController.text = loaded.qrCode ?? '';
        _purchaseCostController.text = loaded.purchasePrice?.toString() ?? '';
        _notesController.text = loaded.notes ?? '';
        _status = loaded.status;
        _categoryName = loaded.category.isEmpty ? 'Other' : loaded.category;
        _locationController.text = loaded.location ?? '';
        _purchaseDate = loaded.purchaseDate;
        _photoUrls = List<String>.from(loaded.photoUrls);
        _tags = List<String>.from(loaded.tags);
        _isLeasable = loaded.isLeasable;
        _dailyRentalController.text =
            loaded.dailyRentalRate?.toString() ?? '';
        _weeklyRentalController.text =
            loaded.weeklyRentalRate?.toString() ?? '';
        _monthlyRentalController.text =
            loaded.monthlyRentalRate?.toString() ?? '';
        _replacementCostController.text =
            loaded.replacementCost?.toString() ?? '';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'loading equipment'),
            ),
          ),
        );
      }
    } finally {
      _initialLoadComplete = true;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAsset() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final appUser = authProvider.appUser;
      final workspaceId =
          appUser?.activeWorkspaceId ?? appUser?.workspaceId ?? '';

      final assetService = SupabaseAssetService(workspaceId: workspaceId);

      final asset = Asset(
        id: widget.assetId ?? '',
        workspaceId: workspaceId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        serialNumber: _serialNumberController.text.trim().isEmpty
            ? null
            : _serialNumberController.text.trim(),
        qrCode: _qrCodeController.text.trim().isEmpty
            ? null
            : _qrCodeController.text.trim(),
        status: _status,
        category: _categoryName,
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        purchaseDate: _purchaseDate,
        purchasePrice: double.tryParse(_purchaseCostController.text.trim()),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        photoUrls: _photoUrls,
        tags: _tags,
        isLeasable: _isLeasable,
        dailyRentalRate: _isLeasable
            ? double.tryParse(_dailyRentalController.text.trim())
            : null,
        weeklyRentalRate: _isLeasable
            ? double.tryParse(_weeklyRentalController.text.trim())
            : null,
        monthlyRentalRate: _isLeasable
            ? double.tryParse(_monthlyRentalController.text.trim())
            : null,
        replacementCost:
            double.tryParse(_replacementCostController.text.trim()),
      );

      if (widget.assetId == null) {
        await assetService.addAsset(asset);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Equipment created successfully')),
          );
        }
      } else {
        await assetService.updateAsset(asset);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Equipment updated successfully')),
          );
        }
      }

      if (mounted) {
        if (widget.isPopup) {
          Navigator.of(context).pop();
        } else {
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'saving equipment')),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadPhoto() async {
    final authProvider = context.read<AuthProvider>();
    final appUser = authProvider.appUser;
    final workspaceId =
        appUser?.activeWorkspaceId ?? appUser?.workspaceId ?? '';
    if (workspaceId.isEmpty) return;

    try {
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

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final assetIdForPath = widget.assetId ?? 'temp_$timestamp';
      final contentType = lookupMimeType(file.name) ?? 'image/jpeg';
      final storagePath =
          '$workspaceId/assets/$assetIdForPath/photo_$timestamp.jpg';
      final supabase = Supabase.instance.client;

      await supabase.storage
          .from('project-images')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );
      final downloadUrl =
          supabase.storage.from('project-images').getPublicUrl(storagePath);

      final updated = [..._photoUrls, downloadUrl];

      if (widget.assetId != null) {
        final assetService = SupabaseAssetService(workspaceId: workspaceId);
        await assetService.updateAssetPhotos(widget.assetId!, updated);
      }

      if (!mounted) return;
      setState(() {
        _photoUrls = updated;
        _isUploadingPhoto = false;
      });
      _markDirty();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo added'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'uploading photo')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _removePhoto(int index) async {
    final updated = [..._photoUrls]..removeAt(index);
    setState(() => _photoUrls = updated);
    _markDirty();

    if (widget.assetId != null) {
      try {
        final authProvider = context.read<AuthProvider>();
        final appUser = authProvider.appUser;
        final workspaceId =
            appUser?.activeWorkspaceId ?? appUser?.workspaceId ?? '';
        final assetService = SupabaseAssetService(workspaceId: workspaceId);
        await assetService.updateAssetPhotos(widget.assetId!, updated);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'removing photo')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_markDirty);
    _descriptionController.removeListener(_markDirty);
    _serialNumberController.removeListener(_markDirty);
    _qrCodeController.removeListener(_markDirty);
    _purchaseCostController.removeListener(_markDirty);
    _notesController.removeListener(_markDirty);
    _locationController.removeListener(_markDirty);
    _dailyRentalController.removeListener(_markDirty);
    _weeklyRentalController.removeListener(_markDirty);
    _monthlyRentalController.removeListener(_markDirty);
    _replacementCostController.removeListener(_markDirty);
    _nameController.dispose();
    _descriptionController.dispose();
    _serialNumberController.dispose();
    _qrCodeController.dispose();
    _purchaseCostController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    _dailyRentalController.dispose();
    _weeklyRentalController.dispose();
    _monthlyRentalController.dispose();
    _replacementCostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StackedField(
                    label: 'Equipment Name *',
                    child: TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter an equipment name';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildPhotoSection(),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'Description',
                    child: TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'Serial Number',
                    child: TextFormField(
                      controller: _serialNumberController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'QR Code',
                    child: TextFormField(
                      controller: _qrCodeController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        helperText: 'Auto-generated or scan existing',
                      ),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'Status',
                    child: DropdownButtonFormField<String>(
                      borderRadius: AppRadius.cardRadius,
                      initialValue: _status,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: _statusOptions.map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Text(
                            status[0].toUpperCase() + status.substring(1),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          _markDirty();
                          setState(() => _status = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'Category',
                    child: _buildCategoryDropdown(),
                  ),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'Location',
                    child: TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'e.g. Truck #3, Yard, Site B - tool crib',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Purchase Date'),
                    subtitle: Text(
                      _purchaseDate == null
                          ? 'Not set'
                          : '${_purchaseDate!.year}-${_purchaseDate!.month.toString().padLeft(2, '0')}-${_purchaseDate!.day.toString().padLeft(2, '0')}',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _purchaseDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        _markDirty();
                        setState(() => _purchaseDate = date);
                      }
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'Purchase Cost',
                    child: TextFormField(
                      controller: _purchaseCostController,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        prefixText:
                            '${CurrencyUtils.getSymbol(context.read<WorkspaceProvider>().currencyCode)} ',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'Replacement Cost',
                    child: TextFormField(
                      controller: _replacementCostController,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        helperText:
                            'What it would cost to replace if lost on a job',
                        prefixText:
                            '${CurrencyUtils.getSymbol(context.read<WorkspaceProvider>().currencyCode)} ',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildLeasingSection(),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'Notes',
                    child: TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FileTagInput(
                    initialTags: _tags,
                    suggestedTags: _suggestedTags,
                    onTagsChanged: (tags) {
                      _markDirty();
                      setState(() => _tags = tags);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        FormPopupFooter(
          onSubmit: _isLoading ? null : _saveAsset,
          submitLabel:
              widget.assetId == null ? 'Create Equipment' : 'Update Equipment',
          busy: _isLoading,
        ),
      ],
    );
  }

  Widget _buildLeasingSection() {
    final symbol = CurrencyUtils.getSymbol(
      context.read<WorkspaceProvider>().currencyCode,
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        color: AppColors.surfaceAlt,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Available for rental',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Bill this equipment to jobs at a daily / weekly / monthly rate '
              '(e.g. air movers, dehumidifiers, scrubbers)',
            ),
            value: _isLeasable,
            onChanged: (v) {
              _markDirty();
              setState(() => _isLeasable = v);
            },
          ),
          if (_isLeasable) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: StackedField(
                    label: 'Daily Rate',
                    child: TextFormField(
                      controller: _dailyRentalController,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        prefixText: '$symbol ',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StackedField(
                    label: 'Weekly Rate',
                    child: TextFormField(
                      controller: _weeklyRentalController,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        prefixText: '$symbol ',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StackedField(
                    label: 'Monthly Rate',
                    child: TextFormField(
                      controller: _monthlyRentalController,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        prefixText: '$symbol ',
                      ),
                      keyboardType: TextInputType.number,
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

  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Photos',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        if (_photoUrls.isEmpty)
          OutlinedButton.icon(
            onPressed: _isUploadingPhoto ? null : _uploadPhoto,
            icon: _isUploadingPhoto
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_isUploadingPhoto ? 'Uploading...' : 'Add photo'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
              side: const BorderSide(color: AppColors.cardBorder),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < _photoUrls.length; i++)
                _PhotoThumb(
                  url: _photoUrls[i],
                  onRemove: _isUploadingPhoto ? null : () => _removePhoto(i),
                ),
              _AddPhotoTile(
                isUploading: _isUploadingPhoto,
                onTap: _isUploadingPhoto ? null : _uploadPhoto,
              ),
            ],
          ),
      ],
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final String url;
  final VoidCallback? onRemove;

  const _PhotoThumb({required this.url, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 96,
              height: 96,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                color: AppColors.cardBorder,
                child: Icon(
                  Icons.broken_image,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 4,
              right: 4,
              child: InkWell(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  final bool isUploading;
  final VoidCallback? onTap;

  const _AddPhotoTile({required this.isUploading, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.cardBorder),
          color: AppColors.surfaceAlt,
        ),
        child: Center(
          child: isUploading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.add_photo_alternate_outlined,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                ),
        ),
      ),
    );
  }
}
