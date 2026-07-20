import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/vehicle.dart';
import '../../services/supabase/vehicle_service.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';

class VehicleFormScreen extends StatelessWidget {
  final String? vehicleId;

  const VehicleFormScreen({super.key, this.vehicleId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(vehicleId == null ? 'New Vehicle' : 'Edit Vehicle'),
      ),
      body: VehicleFormContent(vehicleId: vehicleId, isPopup: false),
    );
  }
}

class VehicleFormContent extends StatefulWidget {
  final String? vehicleId;
  final bool isPopup;
  final ValueNotifier<bool>? dirtyNotifier;

  const VehicleFormContent({
    super.key,
    this.vehicleId,
    this.isPopup = false,
    this.dirtyNotifier,
  });

  @override
  State<VehicleFormContent> createState() => _VehicleFormContentState();
}

class _VehicleFormContentState extends State<VehicleFormContent> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final _vinController = TextEditingController();
  final _mileageController = TextEditingController();
  final _qrCodeController = TextEditingController();

  String _status = 'active';
  bool _isLoading = false;
  Vehicle? _existingVehicle;
  String? _imageUrl;
  bool _isUploadingImage = false;
  bool _initialLoadComplete = false;

  final List<String> _statusOptions = ['active', 'maintenance', 'retired'];

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_markDirty);
    _makeController.addListener(_markDirty);
    _modelController.addListener(_markDirty);
    _yearController.addListener(_markDirty);
    _licensePlateController.addListener(_markDirty);
    _vinController.addListener(_markDirty);
    _mileageController.addListener(_markDirty);
    _qrCodeController.addListener(_markDirty);
    if (widget.vehicleId != null) {
      _loadVehicle();
    } else {
      // Generate QR code for new vehicle
      _qrCodeController.text =
          'vehicle:${DateTime.now().millisecondsSinceEpoch}';
      _initialLoadComplete = true;
    }
  }

  void _markDirty() {
    if (_initialLoadComplete) {
      widget.dirtyNotifier?.value = true;
    }
  }

  Future<void> _loadVehicle() async {
    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final appUser = authProvider.appUser;
      final workspaceId =
          appUser?.activeWorkspaceId ?? appUser?.workspaceId ?? '';

      final vehicleService = SupabaseVehicleService(workspaceId: workspaceId);
      final vehicles = await vehicleService.getVehicles().first;
      _existingVehicle = vehicles.firstWhere((v) => v.id == widget.vehicleId);

      if (_existingVehicle != null) {
        _nameController.text = _existingVehicle!.name;
        _makeController.text = _existingVehicle!.make;
        _modelController.text = _existingVehicle!.model;
        _yearController.text = _existingVehicle!.year.toString();
        _licensePlateController.text = _existingVehicle!.licensePlate;
        _vinController.text = _existingVehicle!.vin ?? '';
        _mileageController.text = _existingVehicle!.currentMileage.toString();
        _qrCodeController.text = _existingVehicle!.qrCode ?? '';
        _status = _existingVehicle!.status;
        _imageUrl = _existingVehicle!.imageUrl;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'loading vehicle'),
            ),
          ),
        );
      }
    } finally {
      _initialLoadComplete = true;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveVehicle() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final appUser = authProvider.appUser;
      final workspaceId =
          appUser?.activeWorkspaceId ?? appUser?.workspaceId ?? '';

      final vehicleService = SupabaseVehicleService(workspaceId: workspaceId);

      final vehicle = Vehicle(
        id: widget.vehicleId ?? '',
        workspaceId: workspaceId,
        name: _nameController.text.trim(),
        make: _makeController.text.trim(),
        model: _modelController.text.trim(),
        year: int.tryParse(_yearController.text.trim()) ?? DateTime.now().year,
        licensePlate: _licensePlateController.text.trim(),
        vin: _vinController.text.trim().isEmpty
            ? null
            : _vinController.text.trim(),
        currentMileage: int.tryParse(_mileageController.text.trim()) ?? 0,
        status: _status,
        qrCode: _qrCodeController.text.trim().isEmpty
            ? null
            : _qrCodeController.text.trim(),
        imageUrl: _imageUrl,
      );

      if (widget.vehicleId == null) {
        await vehicleService.addVehicle(vehicle);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vehicle created successfully')),
          );
        }
      } else {
        await vehicleService.updateVehicle(vehicle);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vehicle updated successfully')),
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
            content: Text(
              UserFacingError.uiMessage(e, action: 'saving vehicle'),
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
    _nameController.removeListener(_markDirty);
    _makeController.removeListener(_markDirty);
    _modelController.removeListener(_markDirty);
    _yearController.removeListener(_markDirty);
    _licensePlateController.removeListener(_markDirty);
    _vinController.removeListener(_markDirty);
    _mileageController.removeListener(_markDirty);
    _qrCodeController.removeListener(_markDirty);
    _nameController.dispose();
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _licensePlateController.dispose();
    _vinController.dispose();
    _mileageController.dispose();
    _qrCodeController.dispose();
    super.dispose();
  }

  Future<void> _uploadVehicleImage() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final appUser = authProvider.appUser;
      final workspaceId =
          appUser?.activeWorkspaceId ?? appUser?.workspaceId ?? '';
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

      setState(() => _isUploadingImage = true);

      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final vehicleId = widget.vehicleId ?? 'temp_$timestamp';
        final contentType = lookupMimeType(file.name) ?? 'image/jpeg';
        late final String downloadUrl;

        if (workspaceId.isEmpty) {
          throw Exception('No active workspace found for image upload');
        }
        final storagePath =
            '$workspaceId/vehicles/$vehicleId/photo_$timestamp.jpg';
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

        if (widget.vehicleId != null) {
          final vehicleService = SupabaseVehicleService(
            workspaceId: workspaceId,
          );
          await vehicleService.updateVehicleImage(
            widget.vehicleId!,
            downloadUrl,
          );
        }

        if (!mounted) return;
        setState(() {
          _markDirty();
          _imageUrl = downloadUrl;
          if (_existingVehicle != null) {
            _existingVehicle = _existingVehicle!.copyWith(
              imageUrl: downloadUrl,
            );
          }
          _isUploadingImage = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo uploaded successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'uploading photo'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
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
                    label: 'Vehicle Name *',
                    child: TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a vehicle name';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: StackedField(
                          label: 'Make *',
                          child: TextFormField(
                            controller: _makeController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StackedField(
                          label: 'Model *',
                          child: TextFormField(
                            controller: _modelController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
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
                          label: 'Year *',
                          child: TextFormField(
                            controller: _yearController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Required';
                              }
                              final year = int.tryParse(value);
                              if (year == null ||
                                  year < 1900 ||
                                  year > DateTime.now().year + 1) {
                                return 'Invalid year';
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StackedField(
                          label: 'License Plate *',
                          child: TextFormField(
                            controller: _licensePlateController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'VIN',
                    child: TextFormField(
                      controller: _vinController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'Current Mileage *',
                    child: TextFormField(
                      controller: _mileageController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        suffixText: 'miles',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter current mileage';
                        }
                        if (int.tryParse(value) == null) {
                          return 'Invalid number';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vehicle Photo (Optional)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_imageUrl != null && _imageUrl!.isNotEmpty)
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: CachedNetworkImage(
                                imageUrl: _imageUrl!,
                                height: 240,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => Container(
                                  height: 200,
                                  decoration: BoxDecoration(
                                    color: AppColors.cardBorder,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.broken_image,
                                      size: 48,
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      color: Colors.white,
                                    ),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black54,
                                    ),
                                    onPressed: _isUploadingImage
                                        ? null
                                        : _uploadVehicleImage,
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.white,
                                    ),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black54,
                                    ),
                                    onPressed: _isUploadingImage
                                        ? null
                                        : () {
                                            _markDirty();
                                            setState(() => _imageUrl = null);
                                          },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _isUploadingImage
                              ? null
                              : _uploadVehicleImage,
                          icon: _isUploadingImage
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_photo_alternate),
                          label: Text(
                            _isUploadingImage ? 'Uploading...' : 'Upload Photo',
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                            side: const BorderSide(color: AppColors.cardBorder),
                          ),
                        ),
                    ],
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
                    label: 'QR Code',
                    child: TextFormField(
                      controller: _qrCodeController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        helperText: 'Auto-generated',
                      ),
                      readOnly: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        FormPopupFooter(
          onSubmit: _isLoading ? null : _saveVehicle,
          submitLabel:
              widget.vehicleId == null ? 'Create Vehicle' : 'Update Vehicle',
          busy: _isLoading,
        ),
      ],
    );
  }
}
