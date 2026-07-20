import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../utils/workspace_gated_loader.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../models/project.dart';
import '../../models/customer.dart';
import '../../models/customer_location.dart';
import '../../models/vendor.dart';
import '../../models/vendor_subdivision.dart';
import '../../models/price_type.dart';
import '../../models/cost_plus_type.dart';
import '../../models/job_type.dart';
import '../../models/project_status_theme.dart';
import '../../models/user.dart';
import '../../models/user_role.dart';
import '../../providers/workspace_provider.dart';
import '../../utils/app_logger.dart';
import '../../utils/project_customer_name.dart';
import '../../utils/project_terminology.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/customer_form_popup.dart';
import '../../widgets/vendor_form_popup.dart';
import '../../widgets/custom_fields_section.dart';
import '../../providers/custom_field_definitions_provider.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class ProjectFormScreen extends StatelessWidget {
  final String? projectId;

  const ProjectFormScreen({super.key, this.projectId});

  @override
  Widget build(BuildContext context) {
    final singular = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          projectId == null ? 'New $singular' : 'Edit $singular',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/projects');
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/projects');
              }
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
      body: ProjectFormContent(projectId: projectId, isPopup: false),
    );
  }
}

/// The actual form content, extracted for reuse in popups and screens
class ProjectFormContent extends StatefulWidget {
  final String? projectId;
  final bool isPopup;

  const ProjectFormContent({super.key, this.projectId, this.isPopup = false});

  @override
  State<ProjectFormContent> createState() => _ProjectFormContentState();
}

class _ProjectFormContentState extends State<ProjectFormContent>
    with WorkspaceGatedLoader {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _budgetController = TextEditingController();
  final _materialMarkupController = TextEditingController(text: '20');
  final _laborMarkupController = TextEditingController(text: '30');
  dynamic get _customerService => ServiceLocator.customerService;
  final _contractAmountController = TextEditingController();
  final _costPlusValueController = TextEditingController();
  final _descriptionController = TextEditingController();
  final dynamic _userService = ServiceLocator.userService;
  final dynamic _workspaceMemberService = ServiceLocator.workspaceMemberService;
  ProjectStatus _selectedStatus = ProjectStatus.bidding;
  PriceType _selectedPriceType = PriceType.timeAndMaterial;
  CostPlusType _selectedCostPlusType = CostPlusType.percentage;
  DateTime? _selectedStartDate;
  DateTime? _selectedCompletionDate;
  String? _selectedCustomerId;
  String? _customerName;
  String? _selectedCustomerLocationId;
  Future<List<CustomerLocation>>? _customerLocationsFuture;
  String? _selectedVendorId;
  String? _vendorName;
  String? _selectedVendorSubdivisionId;
  Future<List<VendorSubdivision>>? _vendorSubdivisionsFuture;
  String? _selectedProjectManagerId;
  bool _isLoading = false;
  Project? _existingProject;
  String? _photoUrl;
  bool _isUploadingPhoto = false;

  // Enhanced project fields
  JobType? _selectedJobType;
  final _purchaseOrderController = TextEditingController();
  DateTime? _dateRequestReceived;
  final _locationDetailsController = TextEditingController();
  String? _selectedSalespersonId;
  String? _selectedSupervisorId;
  final _primaryContactNameController = TextEditingController();
  final _primaryContactRoleController = TextEditingController();
  final _primaryContactPhoneController = TextEditingController();

  final _primaryContactEmailController = TextEditingController();
  final _scrollController = ScrollController();

  // Team members selected for the project
  List<String> _selectedTeamMemberIds = [];

  // Workspace users (loaded from workspace_members)
  List<AppUser> _workspaceUsers = [];
  bool _isLoadingUsers = true;

  // Cached streams for customers
  Stream<List<Customer>>? _customersStream;
  Stream<List<Vendor>>? _vendorsStream;

  // Geofence / GPS settings (per project)
  bool _requireGeofenceValidation = false;
  bool _allowClockInOutsideGeofence = true;
  int _geofenceRadiusMeters = 500;
  bool _capturingGeofenceLocation = false;
  double? _geofenceLatitudeOverride;
  double? _geofenceLongitudeOverride;

  // Custom fields. Definitions are loaded once per workspace via the
  // provider; values live in this map and are sent as a single
  // `custom_fields` jsonb payload (full-replace, not merge — see
  // docs/plans/custom-fields.md).
  final CustomFieldDefinitionsProvider _customFieldsProvider =
      CustomFieldDefinitionsProvider();
  Map<String, dynamic> _customFieldValues = {};

  // Streams/loads init once via WorkspaceGatedLoader (waits for the workspace
  // to hydrate, avoiding the cold-load appUser-null crash). One-shot: don't
  // re-init streams mid-edit on a workspace switch.
  @override
  bool get reloadOnWorkspaceChange => false;

  @override
  void onWorkspaceReady(String workspaceId) {
    _customersStream = _customerService.getCustomers(workspaceId);
    _vendorsStream = ServiceLocator.vendorService.getVendors(workspaceId);
    _loadWorkspaceUsers(workspaceId);
    _customFieldsProvider.load(workspaceId);
    if (widget.projectId != null) {
      _loadProject();
    }
  }

  Future<void> _loadWorkspaceUsers(String workspaceId) async {
    try {
      // Get workspace members from workspace_members collection
      final members = await _workspaceMemberService
          .getWorkspaceMembers(workspaceId)
          .first;

      // Fetch user details for each member
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
        setState(() {
          _isLoadingUsers = false;
        });
      }
    }
  }

  Future<void> _loadVendorFromSubdivision(String subdivisionId) async {
    final subdivision = await ServiceLocator.vendorSubdivisionService
        .getSubdivision(subdivisionId);
    if (subdivision != null && mounted) {
      setState(() {
        _selectedVendorId = subdivision.vendorId;
        _vendorSubdivisionsFuture = ServiceLocator.vendorSubdivisionService
            .getSubdivisionsForVendor(subdivision.vendorId);
      });
    }
  }

  Future<void> _loadProject() async {
    setState(() => _isLoading = true);
    try {
      final project = await ServiceLocator.projectService.getProject(
        widget.projectId!,
      );
      if (project != null) {
        setState(() {
          _existingProject = project;
          _nameController.text = project.name;
          _addressController.text = project.address;
          _selectedStatus = project.status;
          _selectedCustomerId = project.clientId;
          _selectedCustomerLocationId = project.customerLocationId;
          if (project.clientId != null) {
            _customerLocationsFuture = ServiceLocator.customerLocationService
                .getLocationsForCustomer(project.clientId!);
          }
          _customerName = normalizeProjectCustomerName(project.customerName);
          _budgetController.text = project.estimatedBudget?.toString() ?? '';
          _materialMarkupController.text = project.materialMarkupPercent
              .toString();
          _laborMarkupController.text = project.laborMarkupPercent.toString();
          _selectedStartDate = project.startDate;
          _selectedCompletionDate = project.targetCompletionDate;
          _selectedPriceType = project.priceType;
          _contractAmountController.text =
              project.contractAmount?.toString() ?? '';
          _selectedCostPlusType =
              project.costPlusType ?? CostPlusType.percentage;
          _costPlusValueController.text =
              project.costPlusValue?.toString() ?? '';
          _descriptionController.text = project.description ?? '';
          _selectedProjectManagerId = project.projectManagerId;
          _photoUrl = project.photoUrl;

          // Load enhanced fields
          _selectedJobType = project.jobType;
          _purchaseOrderController.text = project.purchaseOrderNumber ?? '';
          _dateRequestReceived = project.dateRequestReceived;
          _locationDetailsController.text = project.locationDetails ?? '';
          _selectedSalespersonId = project.salespersonId;
          _selectedSupervisorId = project.supervisorId;
          _primaryContactNameController.text = project.primaryContactName ?? '';
          _primaryContactRoleController.text = project.primaryContactRole ?? '';
          _primaryContactPhoneController.text =
              project.primaryContactPhone ?? '';

          _primaryContactEmailController.text =
              project.primaryContactEmail ?? '';
          _selectedTeamMemberIds = List<String>.from(project.teamMemberIds);
          _selectedVendorSubdivisionId = project.vendorSubdivisionId;
          _customFieldValues = Map<String, dynamic>.from(project.customFields);
          _requireGeofenceValidation = project.requireGeofenceValidation;
          _allowClockInOutsideGeofence = project.allowClockInOutsideGeofence;
          _geofenceRadiusMeters = project.geofenceRadiusMeters;
        });
        if (project.vendorSubdivisionId != null) {
          _loadVendorFromSubdivision(project.vendorSubdivisionId!);
        }
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
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _budgetController.dispose();
    _materialMarkupController.dispose();
    _laborMarkupController.dispose();
    _contractAmountController.dispose();
    _costPlusValueController.dispose();
    _descriptionController.dispose();
    _purchaseOrderController.dispose();
    _locationDetailsController.dispose();
    _primaryContactNameController.dispose();
    _primaryContactRoleController.dispose();
    _primaryContactPhoneController.dispose();
    _primaryContactEmailController.dispose();
    _scrollController.dispose();
    _customFieldsProvider.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );

    if (picked != null) {
      setState(() {
        _selectedStartDate = picked;
        // Validate that completion date is after start date
        if (_selectedCompletionDate != null &&
            _selectedCompletionDate!.isBefore(picked)) {
          _selectedCompletionDate = null;
        }
      });
    }
  }

  Future<void> _selectCompletionDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _selectedCompletionDate ?? _selectedStartDate ?? DateTime.now(),
      firstDate:
          _selectedStartDate ??
          DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );

    if (picked != null) {
      setState(() {
        _selectedCompletionDate = picked;
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  int? _calculateDuration() {
    if (_selectedStartDate != null && _selectedCompletionDate != null) {
      return _selectedCompletionDate!.difference(_selectedStartDate!).inDays;
    }
    return null;
  }

  Future<void> _captureGeofenceFromHere() async {
    setState(() => _capturingGeofenceLocation = true);
    try {
      final svc = LocationService();
      final granted = await svc.requestLocationPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Location permission denied. Enable it in your browser/device settings to set the geofence pin.')));
        }
        return;
      }
      final pos = await svc.getCurrentPosition();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Unable to read your GPS location. Try again outdoors or check device permissions.')));
        }
        return;
      }
      setState(() {
        _geofenceLatitudeOverride = pos.latitude;
        _geofenceLongitudeOverride = pos.longitude;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Geofence pin set to your current location (±${pos.accuracy.toStringAsFixed(0)}m). Save the project to apply.')));
      }
    } finally {
      if (mounted) setState(() => _capturingGeofenceLocation = false);
    }
  }

  Widget _buildGeofenceSection() {
    final effectiveLat = _geofenceLatitudeOverride ?? _existingProject?.latitude;
    final effectiveLng =
        _geofenceLongitudeOverride ?? _existingProject?.longitude;
    final hasPin = effectiveLat != null && effectiveLng != null;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.my_location, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text('GPS & Geofence',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Capture worker GPS on clock-in/out and enforce a radius around '
              'the project site. The pin is derived from the address by '
              'default — use "Set pin from here" on site for best accuracy.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Require GPS check on clock-in/out'),
              subtitle: const Text(
                  'Workers must have GPS available; their distance is recorded.',
                  style: TextStyle(fontSize: 12)),
              value: _requireGeofenceValidation,
              onChanged: (v) =>
                  setState(() => _requireGeofenceValidation = v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                  'Allow clock-in from outside the geofence (with warning)'),
              subtitle: const Text(
                  'Off = strict; workers outside the radius cannot clock in.',
                  style: TextStyle(fontSize: 12)),
              value: _allowClockInOutsideGeofence,
              onChanged: _requireGeofenceValidation
                  ? (v) => setState(() => _allowClockInOutsideGeofence = v)
                  : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Radius',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const Spacer(),
                Text(
                  _geofenceRadiusMeters >= 1000
                      ? '${(_geofenceRadiusMeters / 1000).toStringAsFixed(_geofenceRadiusMeters % 1000 == 0 ? 0 : 1)} km'
                      : '$_geofenceRadiusMeters m',
                  style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
            Slider(
              value: _geofenceRadiusMeters.clamp(50, 5000).toDouble(),
              min: 50,
              max: 5000,
              divisions: 99,
              label: '$_geofenceRadiusMeters m',
              onChanged: _requireGeofenceValidation
                  ? (v) =>
                      setState(() => _geofenceRadiusMeters = v.round())
                  : null,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    hasPin
                        ? 'Pin: ${effectiveLat.toStringAsFixed(5)}, ${effectiveLng.toStringAsFixed(5)}'
                            '${_geofenceLatitudeOverride != null ? "  (overrides address)" : "  (from address)"}'
                        : 'No pin set — geofence checks will be skipped until a pin exists. '
                            'A pin will be derived from the address on save.',
                    style: TextStyle(
                      fontSize: 12,
                      color: hasPin
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontStyle: hasPin ? null : FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _capturingGeofenceLocation
                      ? null
                      : _captureGeofenceFromHere,
                  icon: _capturingGeofenceLocation
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.gps_fixed, size: 16),
                  label: const Text('Set pin from here'),
                ),
                if (_geofenceLatitudeOverride != null) ...[
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => setState(() {
                      _geofenceLatitudeOverride = null;
                      _geofenceLongitudeOverride = null;
                    }),
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
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

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId == null) {
        throw Exception('No workspace found');
      }

      final estimatedBudget = _budgetController.text.trim().isNotEmpty
          ? double.tryParse(_budgetController.text.trim())
          : null;
      final materialMarkup =
          double.tryParse(_materialMarkupController.text.trim()) ?? 20.0;
      final laborMarkup =
          double.tryParse(_laborMarkupController.text.trim()) ?? 30.0;

      // Parse price type specific fields
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

      // Geocode the address to get coordinates
      double? latitude;
      double? longitude;
      final address = _addressController.text.trim();
      if (address.isNotEmpty) {
        try {
          final coordinates = await GeocodingService().geocodeAddress(address);
          if (coordinates != null) {
            latitude = coordinates.latitude;
            longitude = coordinates.longitude;
          }
        } catch (e) {
          // Geocoding failed, continue without coordinates
          // The project will still be saved with just the address text
        }
      }

      // GPS "set pin from here" override takes precedence over geocoding so
      // the geofence can be anchored to where the supervisor is standing.
      if (_geofenceLatitudeOverride != null &&
          _geofenceLongitudeOverride != null) {
        latitude = _geofenceLatitudeOverride;
        longitude = _geofenceLongitudeOverride;
      }

      final clearFields = widget.projectId != null
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

      if (widget.projectId == null) {
        // Create new project
        final newProject = await ServiceLocator.projectService.createProject(
          workspaceId: workspaceId,
          name: _nameController.text.trim(),
          address: _addressController.text.trim(),
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
          geofenceRadiusMeters: _geofenceRadiusMeters,
          requireGeofenceValidation: _requireGeofenceValidation,
          allowClockInOutsideGeofence: _allowClockInOutsideGeofence,
        );

        if (mounted) {
          if (widget.isPopup) {
            Navigator.of(context).pop(newProject);
          } else {
            debugPrint(
              'Navigating to project detail: /projects/${newProject.id}',
            );
            context.go('/projects/${newProject.id}');
          }
        }
      } else {
        // Update existing project
        await ServiceLocator.projectService.updateProject(
          projectId: widget.projectId!,
          name: _nameController.text.trim(),
          address: _addressController.text.trim(),
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
          geofenceRadiusMeters: _geofenceRadiusMeters,
          requireGeofenceValidation: _requireGeofenceValidation,
          allowClockInOutsideGeofence: _allowClockInOutsideGeofence,
          clearFields: clearFields,
        );

        if (mounted) {
          if (widget.isPopup) {
            Navigator.of(context).pop();
          } else {
            context.go('/projects');
          }
        }
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Project form save failed',
        error: e,
        stackTrace: stackTrace,
        metadata: {
          'mode': widget.projectId == null ? 'create' : 'update',
          'workspaceId': context
              .read<AuthProvider>()
              .appUser
              ?.currentWorkspaceId,
          'teamMemberCount': _selectedTeamMemberIds.length,
          'hasCustomer': _selectedCustomerId != null,
          'hasCustomerLocation': _selectedCustomerLocationId != null,
          'hasVendorSubdivision': _selectedVendorSubdivisionId != null,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'saving project'),
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

  // Upload project photo
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
          if (_existingProject != null) {
            _existingProject = _existingProject!.copyWith(
              photoUrl: downloadUrl,
            );
          }
          _isUploadingPhoto = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo uploaded successfully!'),
              backgroundColor: AppColors.success,
            ),
          );
        }
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

  @override
  Widget build(BuildContext context) {
    final singular = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );
    // Until the workspace hydrates the streams aren't ready (see
    // didChangeDependencies) — show a loader rather than touching null streams.
    if (_customersStream == null || _vendorsStream == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _isLoading && _existingProject == null
        ? const Center(child: CircularProgressIndicator())
        : Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StackedField(
                      label: '$singular Name',
                      child: TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.business),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a name';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    StackedField(
                      label: 'Address',
                      child: TextFormField(
                        controller: _addressController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_on),
                        ),
                        maxLines: 2,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter an address';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    StackedField(
                      label: 'Description (Optional)',
                      child: TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildGeofenceSection(),
                    const SizedBox(height: 16),

                    // Project Photo Upload Section
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$singular Photo (Optional)',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_photoUrl != null)
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                child: CachedNetworkImage(
                                  imageUrl: _photoUrl!,
                                  height: 300,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorWidget: (context, url, error) => Container(
                                    height: 200,
                                    decoration: BoxDecoration(
                                      color: AppColors.cardBorder,
                                      borderRadius: BorderRadius.circular(AppRadius.sm),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.broken_image,
                                        size: 48,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                  ),
                                  onPressed: _uploadProjectPhoto,
                                ),
                              ),
                            ],
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: _isUploadingPhoto
                                ? null
                                : _uploadProjectPhoto,
                            icon: _isUploadingPhoto
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.add_photo_alternate),
                            label: Text(
                              _isUploadingPhoto
                                  ? 'Uploading...'
                                  : 'Upload Photo',
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 50),
                              minimumSize: const Size(double.infinity, 120),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    _isLoadingUsers
                        ? const Center(child: CircularProgressIndicator())
                        : StackedField(
                            label: '$singular Manager (Optional)',
                            child: DropdownButtonFormField<String>(
                              borderRadius: AppRadius.cardRadius,
                              value: _selectedProjectManagerId,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.person_outline),
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
                              onChanged: (value) {
                                setState(() {
                                  _selectedProjectManagerId = value;
                                });
                              },
                            ),
                          ),
                    const SizedBox(height: 16),

                    _isLoadingUsers
                        ? const Center(child: CircularProgressIndicator())
                        : StackedField(
                            label: 'Supervisor (Optional)',
                            child: DropdownButtonFormField<String>(
                              borderRadius: AppRadius.cardRadius,
                              value: _selectedSupervisorId,
                              decoration: const InputDecoration(
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
                              onChanged: (value) {
                                setState(() {
                                  _selectedSupervisorId = value;
                                });
                              },
                            ),
                          ),
                    const SizedBox(height: 16),

                    // Team Members Multi-Select
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header with count
                        Row(
                          children: [
                            const Icon(
                              Icons.group,
                              size: 20,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Team Members (${_selectedTeamMemberIds.length} selected)',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Selected members chips
                        if (_selectedTeamMemberIds.isNotEmpty) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _selectedTeamMemberIds.map((userId) {
                              final user = _workspaceUsers.firstWhere(
                                (u) => u.id == userId,
                                orElse: () => AppUser(
                                  id: userId,
                                  email: 'Unknown User',
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
                                onDeleted: () {
                                  setState(() {
                                    _selectedTeamMemberIds.remove(userId);
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Add member dropdown
                        if (_isLoadingUsers)
                          const Center(child: CircularProgressIndicator())
                        else
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.cardBorder),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: DropdownButtonFormField<String>(
                              borderRadius: AppRadius.cardRadius,
                              value: null,
                              decoration: const InputDecoration(
                                hintText: 'Add team member...',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                ),
                                prefixIcon: Icon(Icons.person_add),
                              ),
                              items: _workspaceUsers
                                  .where(
                                    (user) => !_selectedTeamMemberIds.contains(
                                      user.id,
                                    ),
                                  )
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
                                  setState(() {
                                    _selectedTeamMemberIds.add(value);
                                  });
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Job Type Dropdown
                    StackedField(
                      label: 'Job Type (Optional)',
                      child: DropdownButtonFormField<JobType>(
                        borderRadius: AppRadius.cardRadius,
                        value: _selectedJobType,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        items: [
                          DropdownMenuItem<JobType>(
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
                        onChanged: (value) {
                          setState(() {
                            _selectedJobType = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    StreamBuilder<List<Customer>>(
                      stream: _customersStream!,
                      builder: (context, snapshot) {
                        final customers = snapshot.data ?? [];

                        // Ensure the selected customer ID exists in the list
                        // If not, set it to null to avoid dropdown assertion error
                        final customerIds = customers.map((c) => c.id).toSet();
                        final hasPendingSelectedCustomer =
                            _selectedCustomerId != null &&
                            !customerIds.contains(_selectedCustomerId) &&
                            (_customerName?.trim().isNotEmpty ?? false);
                        final validatedCustomerId =
                            _selectedCustomerId != null &&
                                (customerIds.contains(_selectedCustomerId) ||
                                    hasPendingSelectedCustomer)
                            ? _selectedCustomerId
                            : null;

                        return StackedField(
                          label: 'Customer (Optional)',
                          child: DropdownButtonFormField<String>(
                            borderRadius: AppRadius.cardRadius,
                            isExpanded: true,
                            initialValue: validatedCustomerId,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person),
                              helperText: 'Required for creating invoices',
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('No customer selected'),
                              ),
                              const DropdownMenuItem<String>(
                                value: '__add_new__',
                                child: Row(
                                  children: [
                                    Icon(Icons.add_circle, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      '+ Add New Customer',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const DropdownMenuItem<String>(
                                value: '__divider__',
                                enabled: false,
                                child: Divider(),
                              ),
                              if (hasPendingSelectedCustomer)
                                DropdownMenuItem<String>(
                                  value: _selectedCustomerId,
                                  child: Text(
                                    _customerName!,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ...customers.map((customer) {
                                return DropdownMenuItem<String>(
                                  value: customer.id,
                                  child: Text(
                                    customer.displayName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                            ],
                            onChanged: (value) async {
                              if (value == '__add_new__') {
                                final newCustomerId =
                                    await showCustomerFormPopup(
                                      context,
                                      navigateToDetailOnCreate: false,
                                    );
                                if (newCustomerId != null) {
                                  final customer = await _customerService
                                      .getCustomer(newCustomerId);
                                  if (!mounted) return;
                                  setState(() {
                                    _selectedCustomerId = newCustomerId;
                                    _customerName =
                                        customer?.businessDisplayName;
                                    _selectedCustomerLocationId = null;
                                    _customerLocationsFuture = ServiceLocator
                                        .customerLocationService
                                        .getLocationsForCustomer(newCustomerId);
                                  });
                                }
                              } else if (value == null) {
                                setState(() {
                                  _selectedCustomerId = null;
                                  _customerName = null;
                                  _selectedCustomerLocationId = null;
                                  _customerLocationsFuture = null;
                                });
                              } else if (value != '__divider__') {
                                final customer = customers.firstWhere(
                                  (c) => c.id == value,
                                );
                                setState(() {
                                  _selectedCustomerId = value;
                                  _customerName = customer.businessDisplayName;
                                  _selectedCustomerLocationId = null;
                                  _customerLocationsFuture = ServiceLocator
                                      .customerLocationService
                                      .getLocationsForCustomer(value);
                                });
                              }
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // Location Picker (shown when a customer is selected)
                    if (_selectedCustomerId != null &&
                        _customerLocationsFuture != null)
                      FutureBuilder<List<CustomerLocation>>(
                        future: _customerLocationsFuture,
                        builder: (context, locSnapshot) {
                          final locations = locSnapshot.data ?? [];
                          if (locations.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          // Validate that selected location is still in the list
                          final locationIds = locations
                              .map((l) => l.id)
                              .toSet();
                          final validatedLocationId =
                              _selectedCustomerLocationId != null &&
                                  locationIds.contains(
                                    _selectedCustomerLocationId,
                                  )
                              ? _selectedCustomerLocationId
                              : null;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: StackedField(
                              label: 'Location (Optional)',
                              child: DropdownButtonFormField<String?>(
                                borderRadius: AppRadius.cardRadius,
                                value: validatedLocationId,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.location_on_outlined),
                                  helperText:
                                      'Select a customer location to auto-fill the address',
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('No location selected'),
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
                                onChanged: (value) {
                                  if (value == null) {
                                    setState(() {
                                      _selectedCustomerLocationId = null;
                                    });
                                  } else {
                                    final loc = locations.firstWhere(
                                      (l) => l.id == value,
                                    );
                                    setState(() {
                                      _selectedCustomerLocationId = value;
                                      // Auto-fill address from location
                                      if (loc.fullAddress != null) {
                                        _addressController.text =
                                            loc.fullAddress!;
                                      }
                                    });
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),

                    // Vendor Picker
                    StreamBuilder<List<Vendor>>(
                      stream: _vendorsStream!,
                      builder: (context, snapshot) {
                        final vendors = snapshot.data ?? [];
                        final vendorIds = vendors.map((v) => v.id).toSet();
                        final hasPendingSelectedVendor =
                            _selectedVendorId != null &&
                            !vendorIds.contains(_selectedVendorId) &&
                            (_vendorName?.trim().isNotEmpty ?? false);
                        final validatedVendorId =
                            _selectedVendorId != null &&
                                (vendorIds.contains(_selectedVendorId) ||
                                    hasPendingSelectedVendor)
                            ? _selectedVendorId
                            : null;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: StackedField(
                            label: 'Vendor (Optional)',
                            child: DropdownButtonFormField<String>(
                              borderRadius: AppRadius.cardRadius,
                              value: validatedVendorId,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.business_outlined),
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('No vendor selected'),
                                ),
                                const DropdownMenuItem<String>(
                                  value: '__add_new_vendor__',
                                  child: Row(
                                    children: [
                                      Icon(Icons.add_circle, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        '+ Add New Vendor',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const DropdownMenuItem<String>(
                                  value: '__vendor_divider__',
                                  enabled: false,
                                  child: Divider(),
                                ),
                                if (hasPendingSelectedVendor)
                                  DropdownMenuItem<String>(
                                    value: _selectedVendorId,
                                    child: Text(_vendorName!),
                                  ),
                                ...vendors.map((vendor) {
                                  return DropdownMenuItem<String>(
                                    value: vendor.id,
                                    child: Text(vendor.companyName),
                                  );
                                }),
                              ],
                              onChanged: (value) async {
                                if (value == '__add_new_vendor__') {
                                  final newVendorId = await showVendorFormPopup(
                                    context,
                                    navigateToDetailOnCreate: false,
                                  );
                                  if (newVendorId != null) {
                                    final vendor = await ServiceLocator
                                        .vendorService
                                        .getVendor(newVendorId);
                                    if (!mounted) return;
                                    setState(() {
                                      _selectedVendorId = newVendorId;
                                      _vendorName = vendor?.companyName;
                                      _selectedVendorSubdivisionId = null;
                                      _vendorSubdivisionsFuture = ServiceLocator
                                          .vendorSubdivisionService
                                          .getSubdivisionsForVendor(
                                            newVendorId,
                                          );
                                    });
                                  }
                                } else if (value == null) {
                                  setState(() {
                                    _selectedVendorId = null;
                                    _vendorName = null;
                                    _selectedVendorSubdivisionId = null;
                                    _vendorSubdivisionsFuture = null;
                                  });
                                } else if (value != '__vendor_divider__') {
                                  final vendor = vendors.firstWhere(
                                    (v) => v.id == value,
                                  );
                                  setState(() {
                                    _selectedVendorId = value;
                                    _vendorName = vendor.companyName;
                                    _selectedVendorSubdivisionId = null;
                                    _vendorSubdivisionsFuture = ServiceLocator
                                        .vendorSubdivisionService
                                        .getSubdivisionsForVendor(value);
                                  });
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),

                    // Vendor Subdivision Picker
                    if (_selectedVendorId != null &&
                        _vendorSubdivisionsFuture != null)
                      FutureBuilder<List<VendorSubdivision>>(
                        future: _vendorSubdivisionsFuture,
                        builder: (context, subSnapshot) {
                          final subdivisions = subSnapshot.data ?? [];
                          if (subdivisions.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          final subdivisionIds = subdivisions
                              .map((s) => s.id)
                              .toSet();
                          final validatedSubdivisionId =
                              _selectedVendorSubdivisionId != null &&
                                  subdivisionIds.contains(
                                    _selectedVendorSubdivisionId,
                                  )
                              ? _selectedVendorSubdivisionId
                              : null;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: StackedField(
                              label: 'Subdivision (Optional)',
                              child: DropdownButtonFormField<String?>(
                                borderRadius: AppRadius.cardRadius,
                                value: validatedSubdivisionId,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.location_on_outlined),
                                  helperText:
                                      'Select a subdivision to auto-fill the address',
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('No subdivision selected'),
                                  ),
                                  ...subdivisions.map((sub) {
                                    final subtitle = sub.fullAddress != null
                                        ? ' - ${sub.fullAddress}'
                                        : '';
                                    return DropdownMenuItem<String?>(
                                      value: sub.id,
                                      child: Text(
                                        '${sub.name}$subtitle',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }),
                                ],
                                onChanged: (value) {
                                  if (value == null) {
                                    setState(() {
                                      _selectedVendorSubdivisionId = null;
                                    });
                                  } else {
                                    final sub = subdivisions.firstWhere(
                                      (s) => s.id == value,
                                    );
                                    setState(() {
                                      _selectedVendorSubdivisionId = value;
                                      if (sub.fullAddress != null) {
                                        _addressController.text =
                                            sub.fullAddress!;
                                      }
                                    });
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),

                    // Salesperson Picker
                    _isLoadingUsers
                        ? const Center(child: CircularProgressIndicator())
                        : StackedField(
                            label: 'Salesperson (Optional)',
                            child: DropdownButtonFormField<String>(
                              borderRadius: AppRadius.cardRadius,
                              value: _selectedSalespersonId,
                              decoration: const InputDecoration(
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
                              onChanged: (value) {
                                setState(() {
                                  _selectedSalespersonId = value;
                                });
                              },
                            ),
                          ),
                    const SizedBox(height: 16),
                    StackedField(
                      label: '$singular Status',
                      child: DropdownButtonFormField<ProjectStatus>(
                        borderRadius: AppRadius.cardRadius,
                        initialValue: _selectedStatus,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.flag),
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
                            setState(() {
                              _selectedStatus = value;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Purchase Order Number
                    StackedField(
                      label: 'Purchase Order Number (Optional)',
                      child: TextFormField(
                        controller: _purchaseOrderController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.receipt_long),
                          hintText: 'e.g., PO-230930',
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Pricing Model',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    StackedField(
                      label: 'Price Type',
                      child: DropdownButtonFormField<PriceType>(
                        borderRadius: AppRadius.cardRadius,
                        initialValue: _selectedPriceType,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.payments),
                        ),
                        items: PriceType.values.map((priceType) {
                          return DropdownMenuItem(
                            value: priceType,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  priceType.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  priceType.description,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedPriceType = value;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Conditional fields based on price type
                    if (_selectedPriceType == PriceType.fixedPrice) ...[
                      StackedField(
                        label: 'Contract Amount',
                        child: TextFormField(
                          controller: _contractAmountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.attach_money),
                            helperText: 'Total fixed price agreed with customer',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null;
                            }
                            final number = double.tryParse(value);
                            if (number == null || number <= 0) {
                              return 'Please enter a valid positive number';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                    if (_selectedPriceType == PriceType.costPlus) ...[
                      StackedField(
                        label: 'Cost Plus Type',
                        child: DropdownButtonFormField<CostPlusType>(
                          borderRadius: AppRadius.cardRadius,
                          initialValue: _selectedCostPlusType,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calculate),
                          ),
                          items: CostPlusType.values.map((type) {
                            return DropdownMenuItem(
                              value: type,
                              child: Text(type.displayName),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedCostPlusType = value;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      StackedField(
                        label: _selectedCostPlusType == CostPlusType.percentage
                            ? 'Fee Percentage'
                            : 'Fixed Fee Amount',
                        child: TextFormField(
                          controller: _costPlusValueController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            prefixIcon: Icon(
                              _selectedCostPlusType == CostPlusType.percentage
                                  ? Icons.percent
                                  : Icons.attach_money,
                            ),
                            helperText:
                                _selectedCostPlusType == CostPlusType.percentage
                                ? 'Percentage to add to total costs'
                                : 'Fixed fee to add to total costs',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Fee is required for cost plus projects';
                            }
                            final number = double.tryParse(value);
                            if (number == null || number <= 0) {
                              return 'Please enter a valid positive number';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      '$singular Timeline (Optional)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _selectStartDate,
                      icon: const Icon(Icons.event),
                      label: Text(
                        _selectedStartDate == null
                            ? 'Set Start Date (optional)'
                            : 'Start: ${_formatDate(_selectedStartDate!)}',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                    if (_selectedStartDate != null) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedStartDate = null;
                          });
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear Start Date'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _selectCompletionDate,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        _selectedCompletionDate == null
                            ? 'Set Target Completion Date (optional)'
                            : 'Target: ${_formatDate(_selectedCompletionDate!)}',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                    if (_selectedCompletionDate != null) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedCompletionDate = null;
                          });
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear Completion Date'),
                      ),
                    ],
                    if (_calculateDuration() != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.infoLight,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 20,
                              color: AppColors.info,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$singular duration: ${_calculateDuration()} days',
                              style: const TextStyle(color: AppColors.info),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Budget & Costs (Optional)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    StackedField(
                      label: 'Estimated Budget',
                      child: TextFormField(
                        controller: _budgetController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.attach_money),
                          helperText:
                              'Optional: Customer-approved budget for this project',
                        ),
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            final number = double.tryParse(value);
                            if (number == null || number < 0) {
                              return 'Please enter a valid positive number';
                            }
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
                            label: 'Material Markup %',
                            child: TextFormField(
                              controller: _materialMarkupController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.percent),
                                helperText: 'Markup on materials',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Required';
                                }
                                final number = double.tryParse(value);
                                if (number == null || number < 0) {
                                  return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StackedField(
                            label: 'Labor Markup %',
                            child: TextFormField(
                              controller: _laborMarkupController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.percent),
                                helperText: 'Markup on labor',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Required';
                                }
                                final number = double.tryParse(value);
                                if (number == null || number < 0) {
                                  return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Custom fields — admin-defined per workspace.
                    // Hidden when zero defs exist.
                    AnimatedBuilder(
                      animation: _customFieldsProvider,
                      builder: (context, _) {
                        final active = _customFieldsProvider.active;
                        final all = _customFieldsProvider.all;
                        if (active.isEmpty &&
                            !all.any((d) =>
                                d.isArchived &&
                                _customFieldValues[d.key] != null)) {
                          return const SizedBox.shrink();
                        }
                        return CustomFieldsSection(
                          activeDefinitions: active,
                          allDefinitions: all,
                          values: _customFieldValues,
                          onChanged: (v) => _customFieldValues = v,
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    if (widget.projectId == null
                        ? context.watch<AuthProvider>().canCreateProjects
                        : context.watch<AuthProvider>().canEditProjects)
                      ElevatedButton(
                        onPressed: _isLoading ? null : _handleSave,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.save),
                                  const SizedBox(width: 8),
                                  Text(
                                    widget.projectId == null
                                        ? 'Create $singular'
                                        : 'Update $singular',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                      ),
                  ],
                ),
              ),
            ),
          );
  }
}
