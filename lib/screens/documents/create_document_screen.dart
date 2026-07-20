import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../models/document_template.dart';
import '../../models/document_type.dart';
import '../../models/template_category.dart';
import '../../models/project.dart';
import '../../models/budget_item.dart';
import '../../models/customer.dart';
import '../../models/customer_contact.dart';
import '../../models/vendor.dart';
import '../../models/vendor_contact.dart';
import '../../widgets/vendor_form_popup.dart';
import '../../models/generated_document.dart';
import '../../models/workspace.dart';
import '../../models/document_line_item.dart';
import '../../models/file_attachment.dart';
import '../../models/file_folder.dart';
import '../../services/ai_service.dart';
import '../../services/service_locator.dart';
import '../../widgets/document_line_item_editor.dart';
import '../../widgets/document_photo_selector.dart';
import '../../widgets/common/draggable_divider.dart';
import '../../widgets/document_preview_widget.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../utils/change_order_validation.dart';
import '../../utils/workspace_gated_loader.dart';
import '../../utils/currency_utils.dart';
import '../../utils/document_template_renderer.dart';
import '../../utils/project_terminology.dart';
import '../../services/geocoding_service.dart';
import '../../providers/workspace_provider.dart';
import '../../widgets/customer_form_popup.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class CreateDocumentScreen extends StatefulWidget {
  final String? templateId;
  final String? projectId;
  final String? customerId;
  final GeneratedDocument? existingDocument;
  final List<Map<String, dynamic>>? prePopulatedLineItems;
  final List<String>? preSelectedBudgetItemIds;
  final Map<String, double>? preSelectedBudgetItemAmounts;

  /// Vendor ID for vendor-side documents (POs, bills).
  final String? vendorId;

  /// Source document ID for document chain tracking (e.g. bid→PO, PO→bill).
  final String? sourceDocumentId;

  /// When provided, pre-selects the first available template whose
  /// [DocumentType] matches. Used by entry points like the change-orders
  /// screen FAB to land the user directly on a typed template picker.
  final DocumentType? preferredType;

  /// When true, skips the Scaffold/AppBar wrapper and the project selector step,
  /// allowing this screen to be hosted inside a parent widget (e.g. project detail tab).
  final bool embedded;

  /// Called when a document is successfully created in embedded mode.
  final void Function(String documentId)? onDocumentCreated;

  /// Called when the user wants to go back in embedded mode.
  final VoidCallback? onBack;

  const CreateDocumentScreen({
    super.key,
    this.templateId,
    this.projectId,
    this.customerId,
    this.existingDocument,
    this.prePopulatedLineItems,
    this.preSelectedBudgetItemIds,
    this.preSelectedBudgetItemAmounts,
    this.vendorId,
    this.sourceDocumentId,
    this.preferredType,
    this.embedded = false,
    this.onDocumentCreated,
    this.onBack,
  });

  @override
  State<CreateDocumentScreen> createState() => _CreateDocumentScreenState();
}

class _CreateDocumentScreenState extends State<CreateDocumentScreen>
    with SingleTickerProviderStateMixin, WorkspaceGatedLoader {
  final _templateService = ServiceLocator.documentTemplateService;
  final _documentService = ServiceLocator.documentService;
  dynamic get _projectService => ServiceLocator.projectService;
  dynamic get _customerService => ServiceLocator.customerService;
  dynamic get _vendorService => ServiceLocator.vendorService;
  final _workspaceService = ServiceLocator.workspaceService;

  bool get _isEditing => widget.existingDocument != null;
  String get _screenTitle => _isEditing ? 'Edit Document' : 'Create Document';
  String get _submitButtonLabel =>
      _isEditing ? 'Update Document' : 'Create Document';
  String get _submitProgressLabel => _isEditing ? 'Updating...' : 'Creating...';
  String get _successMessage => _isEditing
      ? 'Document updated successfully'
      : 'Document created successfully';
  /// True when the active template is a vendor-facing document
  /// (purchase order, bill, expense, request-for-bid, etc.). When true the
  /// "prepared for" party is a Vendor; otherwise it is a Customer.
  bool get _isVendorDocument =>
      _selectedTemplate?.type.isVendorSide ?? false;

  String? get _effectiveVendorId {
    if (_isVendorDocument) {
      return _selectedVendor?.id ??
          widget.vendorId ??
          widget.existingDocument?.vendorId;
    }
    return widget.vendorId ?? widget.existingDocument?.vendorId;
  }

  String? get _outboundCustomerId =>
      _isVendorDocument ? null : _selectedCustomer?.id;
  String? get _outboundCustomerName =>
      _isVendorDocument ? null : _selectedCustomer?.displayName;
  String? get _effectiveSourceDocumentId =>
      widget.sourceDocumentId ?? widget.existingDocument?.sourceDocumentId;

  String _getSingularTerminology() {
    return singularProjectTerminology(
      context.read<WorkspaceProvider>().projectTerminology,
    );
  }

  DocumentTemplate? _selectedTemplate;
  Project? _selectedProject;
  Customer? _selectedCustomer;
  CustomerContact? _selectedCustomerContact;
  Vendor? _selectedVendor;
  VendorContact? _selectedVendorContact;
  List<Vendor> _vendors = [];
  bool _isLoading = false;
  bool _isCreating = false;
  // Validation UI state
  bool _showFieldErrors = false;
  String? _validationMessage;
  late final AnimationController _shakeController;

  // Stable document number suffix generated once per session
  final String _dateSuffix = DateTime.now().millisecondsSinceEpoch
      .toString()
      .substring(7);

  List<DocumentTemplate> _templates = [];
  List<Project> _projects = [];
  List<Customer> _customers = [];

  // Budget item selection (legacy - for backwards compatibility)
  List<String> _selectedBudgetItemIds = [];
  Map<String, double> _budgetItemAmounts = {};
  List<BudgetItem> _budgetItems = [];

  // Enhanced line items system
  List<DocumentLineItem> _lineItems = [];
  LineItemVisibility _lineItemVisibility = LineItemVisibility.all;
  LineItemSourceMode _lineItemSourceMode = LineItemSourceMode.snapshot;

  // Tax settings
  bool _collectTax = false;
  String _taxName = 'Tax';
  double _taxRate = 0;

  // Holdback (retainage) settings — only meaningful for customer invoices.
  bool _applyHoldback = false;
  double _holdbackPercent = 10;
  final _holdbackPercentController = TextEditingController(text: '10');

  // Invoice-level discount (flat, pre-tax). [M004]
  double _discountAmount = 0;
  final _discountController = TextEditingController();

  // Desktop split ratio (0.0–1.0, fraction for preview panel)
  double _splitRatio = 0.55;

  // Attached project files
  List<String> _attachedPhotoIds = [];
  List<FileAttachment> _attachedPhotos = [];

  // Workspace for logo
  Workspace? _workspace;

  // Document dates
  DateTime _documentDate = DateTime.now();
  DateTime _expiryDate = DateTime.now().add(const Duration(days: 30));

  bool get _showExpiryDate => _selectedTemplate?.type.hasExpiryDate ?? true;

  // Address autocomplete state
  final GeocodingService _geocodingService = GeocodingService();
  Timer? _addressSuggestionDebounce;
  List<AddressSuggestion> _addressSuggestions = const [];
  bool _isLoadingAddressSuggestions = false;
  bool _isSettingAddressFromSuggestion = false;
  String? _workspaceCountryCode;

  // AI draft state
  String? _aiDraftScope;
  bool _isGeneratingAiDraft = false;

  // Preview toggle for mobile
  bool _showPreview = false;
  bool _showTemplateDefaultsHint = false;
  bool _showPreviewEditHint = false;

  // Scroll keys for programmatic scrolling
  final _templateSectionKey = GlobalKey();
  final _preparedBySectionKey = GlobalKey();
  final _customerSectionKey = GlobalKey();
  final _footerSectionKey = GlobalKey();
  final _lineItemSectionKey = GlobalKey();
  final _photoSectionKey = GlobalKey();
  final _aiDraftSectionKey = GlobalKey();
  final _editorScrollController = ScrollController();

  // Highlight animation for scroll-to-section
  GlobalKey? _highlightedSectionKey;

  // Tax controllers
  final _taxNameController = TextEditingController(text: 'Tax');
  final _taxRateController = TextEditingController(text: '0');

  // Computed totals
  double get _subtotal => _lineItems
      .where((item) => item.isItem && item.isVisible)
      .fold(0.0, (sum, item) => sum + item.total);

  // Tax base excludes non-taxable lines (per-line is_taxable). [M002]
  double get _taxableSubtotal => _lineItems
      .where((item) => item.isItem && item.isVisible && item.isTaxable)
      .fold(0.0, (sum, item) => sum + item.total);

  double get _taxAmount {
    if (!_collectTax) return 0;
    var base = _taxableSubtotal;
    // Pre-tax discount shrinks the taxable base, apportioned by taxable share.
    if (_discountAmount > 0 && _subtotal > 0) {
      base -= _discountAmount * (_taxableSubtotal / _subtotal);
      if (base < 0) base = 0;
    }
    return base * (_taxRate / 100);
  }

  double get _grandTotal => _subtotal - _discountAmount + _taxAmount;

  // Drives the holdback / retainage editor. AIA contracts sit in the invoice
  // category but are agreements, not bills, so holdback does not apply to them.
  bool get _isInvoiceCategory =>
      _selectedTemplate?.type.isPayableCustomerInvoice ?? false;

  bool get _holdbackEnabled => _applyHoldback && _isInvoiceCategory;

  double get _holdbackAmount =>
      _holdbackEnabled ? _subtotal * (_holdbackPercent / 100) : 0;

  // Contact info helpers (single source of truth for all callers)
  DocumentContactInfo get _preparedByInfo => DocumentContactInfo(
    name: _preparedByNameController.text.trim(),
    organization: _preparedByOrgController.text.trim(),
    phone: _preparedByPhoneController.text.trim(),
    email: _preparedByEmailController.text.trim(),
    address: _preparedByAddressController.text.trim(),
  );

  DocumentContactInfo? get _preparedForInfo {
    if (_isVendorDocument) {
      if (_selectedVendor == null) return null;
      final contact = _resolveSelectedVendorContact(_selectedVendor);
      return DocumentContactInfo(
        name: contact?.name,
        organization: _selectedVendor!.companyName,
        phone: contact?.phone ?? _selectedVendor!.businessPhone,
        email: contact?.email ?? _selectedVendor!.businessEmail,
        address: _selectedVendor!.fullAddress,
      );
    }
    if (_selectedCustomer == null) return null;
    final contact = _resolveSelectedCustomerContact(_selectedCustomer);
    return DocumentContactInfo(
      name: contact?.name,
      organization: _selectedCustomer!.companyName,
      phone: contact?.phone,
      email: contact?.email,
      address: _selectedCustomer!.fullAddress,
    );
  }

  // PREPARED BY controllers
  final _preparedByNameController = TextEditingController();
  final _preparedByOrgController = TextEditingController();
  final _preparedByPhoneController = TextEditingController();
  final _preparedByEmailController = TextEditingController();
  final _preparedByAddressController = TextEditingController();

  // Footer controller
  final _footerController = TextEditingController();

  // Email message controllers
  final _emailSubjectController = TextEditingController();
  final _emailMessageController = TextEditingController();

  // PREPARE preview toggle

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    if (_isEditing) {
      _hydrateFromExistingDocument(widget.existingDocument!);
    } else {
      if (widget.preSelectedBudgetItemIds != null) {
        _selectedBudgetItemIds = List.from(widget.preSelectedBudgetItemIds!);
      }
      if (widget.preSelectedBudgetItemAmounts != null) {
        _budgetItemAmounts = Map.from(widget.preSelectedBudgetItemAmounts!);
      }
      _lineItems = _parseInitialLineItems(widget.prePopulatedLineItems);
    }
    _preparedByAddressController.addListener(_onAddressChanged);
    _setDefaultValues();
  }

  // One-shot: don't reload (and clobber) an in-progress create form if the
  // user happens to switch workspace mid-edit.
  @override
  bool get reloadOnWorkspaceChange => false;

  @override
  void onWorkspaceReady(String workspaceId) {
    // Deferred via WorkspaceGatedLoader so a cold load / hard refresh (appUser
    // briefly null) doesn't leave _loadData unrun with _isLoading stuck true
    // (infinite spinner on the invoice/estimate create screen).
    _loadData();
    _loadWorkspaceCountryCode();
    // Re-apply From defaults now that appUser is available. The initState call
    // ran while appUser was still null on a cold load, leaving the "From" name
    // empty so the create blocked with "Please enter a name in the From
    // section." even though the user is signed in. _setDefaultValues only fills
    // empty fields, so this is idempotent.
    _setDefaultValues();
  }

  void _hydrateFromExistingDocument(GeneratedDocument document) {
    _selectedBudgetItemIds = List<String>.from(document.budgetItemIds);
    _budgetItemAmounts = Map<String, double>.from(
      document.budgetItemAmounts ?? const {},
    );
    _lineItems = document.lineItems
        .map((item) => DocumentLineItem.fromJson(item.toJson()))
        .toList();
    _lineItemVisibility = document.lineItemVisibility;
    _lineItemSourceMode = document.lineItemSourceMode;
    _collectTax = document.collectTax;
    _taxName = (document.taxName != null && document.taxName!.trim().isNotEmpty)
        ? document.taxName!.trim()
        : 'Tax';
    _taxRate = document.taxRate;
    _taxNameController.text = _taxName;
    _taxRateController.text = _taxRate > 0 ? _taxRate.toString() : '0';
    // Hydrate holdback (retainage) state from the existing invoice so the
    // edit flow does not silently clear it.
    if (document.retainagePercent > 0 || document.retainageAmount > 0) {
      _applyHoldback = true;
      _holdbackPercent = document.retainagePercent;
      _holdbackPercentController.text = document.retainagePercent
          .toStringAsFixed(1);
    } else {
      _applyHoldback = false;
    }
    if (document.discountAmount > 0) {
      _discountAmount = document.discountAmount;
      _discountController.text = document.discountAmount.toStringAsFixed(2);
    }
    _attachedPhotoIds = List<String>.from(document.attachedPhotoIds);
    _documentDate = document.createdAt;
    _expiryDate =
        document.dueDate ?? document.createdAt.add(const Duration(days: 30));
    _preparedByNameController.text = document.preparedBy?.name ?? '';
    _preparedByOrgController.text = document.preparedBy?.organization ?? '';
    _preparedByPhoneController.text = document.preparedBy?.phone ?? '';
    _preparedByEmailController.text = document.preparedBy?.email ?? '';
    _preparedByAddressController.text = document.preparedBy?.address ?? '';
    _footerController.text = document.footerContent ?? '';
    _emailSubjectController.text = document.emailSubject ?? '';
    _emailMessageController.text = document.emailMessage ?? '';
  }

  List<DocumentLineItem> _parseInitialLineItems(
    List<Map<String, dynamic>>? prePopulatedLineItems,
  ) {
    if (prePopulatedLineItems == null || prePopulatedLineItems.isEmpty) {
      return [];
    }

    return prePopulatedLineItems.asMap().entries.map((entry) {
      final index = entry.key;
      final row = entry.value;
      if (row.containsKey('id') && row.containsKey('type')) {
        return DocumentLineItem.fromJson(row);
      }

      final quantity = _parseInitialLineItemDouble(row['quantity']) ?? 1.0;
      final amount = _parseInitialLineItemDouble(row['amount']);
      final rate = _parseInitialLineItemDouble(row['rate']);
      final resolvedAmount = amount ?? (rate != null ? rate * quantity : 0.0);
      final unitPrice =
          rate ?? (quantity > 0 ? resolvedAmount / quantity : resolvedAmount);
      return DocumentLineItem(
        id: const Uuid().v4(),
        budgetItemId: row['budgetItemId'] as String?,
        type: DocumentLineItemType.item,
        sortOrder: index,
        name:
            (row['name'] as String?) ??
            (row['description'] as String?) ??
            'Line Item',
        description: row['description'] as String?,
        quantity: quantity,
        unit: row['unit'] as String?,
        unitPrice: unitPrice,
      );
    }).toList();
  }

  double? _parseInitialLineItemDouble(dynamic rawValue) {
    if (rawValue == null) return null;
    if (rawValue is num) return rawValue.toDouble();
    if (rawValue is String) {
      final normalized = rawValue.trim().replaceAll(',', '');
      if (normalized.isEmpty) return null;
      return double.tryParse(normalized);
    }
    return double.tryParse(rawValue.toString());
  }

  @override
  void dispose() {
    _addressSuggestionDebounce?.cancel();
    _shakeController.dispose();
    _preparedByNameController.dispose();
    _preparedByOrgController.dispose();
    _preparedByPhoneController.dispose();
    _preparedByEmailController.dispose();
    _preparedByAddressController.dispose();
    _footerController.dispose();
    _emailSubjectController.dispose();
    _emailMessageController.dispose();
    _editorScrollController.dispose();
    _holdbackPercentController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void _setDefaultValues() {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.appUser;

    // Set default PREPARED BY values from user
    if (_preparedByNameController.text.trim().isEmpty) {
      _preparedByNameController.text = user?.displayName ?? '';
    }
    if (_preparedByEmailController.text.trim().isEmpty) {
      _preparedByEmailController.text = user?.email ?? '';
    }

    // Default email subject
    if (_emailSubjectController.text.trim().isEmpty) {
      _emailSubjectController.text = 'Document for your signature';
    }
    if (_emailMessageController.text.trim().isEmpty) {
      _emailMessageController.text =
          'Please review and sign the attached document at your earliest convenience.\n\n'
          'Click the link below to view and sign the document.';
    }
  }

  Future<void> _pickDocumentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _documentDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        final oldOffset = _expiryDate.difference(_documentDate);
        _documentDate = picked;
        // Preserve the offset between document date and expiry date
        _expiryDate = picked.add(oldOffset);
      });
    }
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate,
      firstDate: _documentDate,
      lastDate: _documentDate.add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }

  void _scrollToSection(GlobalKey key) {
    // On mobile, switch to edit view first
    if (_showPreview) {
      setState(() => _showPreview = false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null || !_editorScrollController.hasClients) return;

      // Calculate the target's position relative to the editor scroll view
      // instead of using Scrollable.ensureVisible, which scrolls ALL ancestor
      // scrollables (including parent TabBarView, causing tab switches).
      final targetBox = ctx.findRenderObject() as RenderBox?;
      final scrollableCtx =
          _editorScrollController.position.context.storageContext;
      final scrollableBox = scrollableCtx.findRenderObject() as RenderBox?;

      if (targetBox != null && scrollableBox != null) {
        final targetOffset = targetBox.localToGlobal(
          Offset.zero,
          ancestor: scrollableBox,
        );
        final scrollOffset = _editorScrollController.offset + targetOffset.dy;
        final clampedOffset = scrollOffset.clamp(
          _editorScrollController.position.minScrollExtent,
          _editorScrollController.position.maxScrollExtent,
        );

        _editorScrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }

      // Flash highlight on target section
      setState(() => _highlightedSectionKey = key);
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && _highlightedSectionKey == key) {
          setState(() => _highlightedSectionKey = null);
        }
      });
    });
  }

  /// Whether the current layout is desktop (side-by-side preview + editor).
  bool get _isDesktopLayout => MediaQuery.of(context).size.width >= AppBreakpoints.desktop;

  /// Edit affordance: on desktop scroll to section; on mobile open a bottom
  /// sheet with the relevant fields so tapping in the preview feels like a
  /// real picker.
  void _editPreparedBy() {
    if (_isDesktopLayout) {
      _showPreparedByEditor();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'From',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _preparedByNameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                    isDense: true,
                  ),
                  onChanged: (_) {
                    _clearValidationErrors();
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _preparedByOrgController,
                  decoration: const InputDecoration(
                    labelText: 'Organization',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.business),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _preparedByPhoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _preparedByEmailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _buildAddressFieldWithSuggestions(_preparedByAddressController),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _editFooter() {
    if (_isDesktopLayout) {
      _scrollToSection(_footerSectionKey);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Footer',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _footerController,
                  decoration: const InputDecoration(
                    labelText: 'Footer Content',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _editTemplateName() {
    if (_isDesktopLayout) {
      _scrollToSection(_templateSectionKey);
      return;
    }
    // On mobile, switch to editor and scroll to template section
    _scrollToSection(_templateSectionKey);
  }

  void _editCustomer() {
    if (_isDesktopLayout) {
      _scrollToSection(_customerSectionKey);
      return;
    }
    _scrollToSection(_customerSectionKey);
  }

  Widget _highlightableSection({
    required GlobalKey key,
    required Widget child,
  }) {
    final isHighlighted = _highlightedSectionKey == key;
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        color: isHighlighted
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
      child: child,
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final workspaceId = authProvider.appUser?.currentWorkspaceId;

      if (workspaceId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Load all data in parallel using 'Once' methods for reliability
      final results = await Future.wait<dynamic>([
        _workspaceService.getWorkspace(workspaceId).first,
        _templateService.getTemplatesOnce(workspaceId),
        _projectService.getProjectsOnce(workspaceId) as Future<List<Project>>,
        _customerService.getCustomersOnce(workspaceId),
        _vendorService.getVendors(workspaceId).first as Future<List<Vendor>>,
      ]);

      if (!mounted) return;

      final workspaceData = results[0];
      final templates = results[1] as List<DocumentTemplate>;
      final projects = results[2] as List<Project>;
      final customers = results[3] as List<Customer>;
      final vendors = (results[4] as List<Vendor>)
          .where((v) => v.isActive)
          .toList();

      setState(() {
        if (workspaceData != null) {
          _workspace = Workspace.fromJson(
            workspaceData as Map<String, dynamic>,
            workspaceId,
          );
          if (_preparedByOrgController.text.isEmpty) {
            _preparedByOrgController.text = _workspace!.name;
          }
          if (_preparedByAddressController.text.isEmpty) {
            final addr = _workspace!.fullCompanyAddress;
            if (addr != null && addr.isNotEmpty) {
              _preparedByAddressController.text = addr.replaceAll('\n', ', ');
            }
          }
          if (!_isEditing) {
            // Apply workspace default tax settings for new documents only.
            _collectTax = _workspace!.defaultTaxEnabled;
            _taxName = _workspace!.defaultTaxName;
            _taxRate = _workspace!.defaultTaxRate;
            _taxNameController.text = _taxName;
            _taxRateController.text = _taxRate > 0 ? _taxRate.toString() : '0';
          }
        }

        _templates = templates;
        // Pre-select template if provided
        if (widget.templateId != null) {
          _selectedTemplate = templates
              .where((t) => t.id == widget.templateId)
              .firstOrNull;

          if (_selectedTemplate != null) {
            _expandedCategories.add(_selectedTemplate!.category);
          }
        } else if (widget.preferredType != null) {
          // Pre-select the first template whose type matches preferredType.
          final preferred = templates
              .where((t) => t.type == widget.preferredType)
              .firstOrNull;
          if (preferred != null) {
            _selectedTemplate = preferred;
            _expandedCategories.add(preferred.category);
          } else if (templates.isNotEmpty) {
            _expandedCategories.add(templates.first.category);
          }
        } else if (templates.isNotEmpty) {
          // Expand first category by default
          _expandedCategories.add(templates.first.category);
        }

        _projects = projects;
        _customers = customers;
        _vendors = vendors;
        if (widget.customerId != null) {
          _selectedCustomer = customers
              .where((customer) => customer.id == widget.customerId)
              .firstOrNull;
          _applyCustomerTaxExemption();
          _selectedCustomerContact = _getDefaultCustomerContact(
            _selectedCustomer,
          );
        }
        // Pre-select vendor for vendor-side documents (POs, bills, …).
        final preselectVendorId =
            widget.vendorId ?? widget.existingDocument?.vendorId;
        if (preselectVendorId != null) {
          _selectedVendor =
              vendors.where((v) => v.id == preselectVendorId).firstOrNull;
          _selectedVendorContact = _getDefaultVendorContact(_selectedVendor);
        }
        // Pre-select project if provided
        if (widget.projectId != null) {
          _selectedProject = projects
              .where((p) => p.id == widget.projectId)
              .firstOrNull;

          // If project has a client, pre-select the customer (for
          // customer-facing documents only).
          if (_selectedProject?.clientId != null &&
              widget.customerId == null &&
              !_isVendorDocument) {
            _loadCustomerForProject(_selectedProject!.clientId!);
          }
        }
        // Seed holdback defaults from the selected project, if any.
        if (!_isEditing && _selectedProject != null) {
          final pct = _selectedProject!.holdbackDefaultPercent;
          if (pct > 0) {
            _applyHoldback = true;
            _holdbackPercent = pct;
            _holdbackPercentController.text = pct.toStringAsFixed(1);
          }
        }
      });

      if (_selectedProject != null) {
        await _loadBudgetItemsForProject(_selectedProject!.id);
        await _loadAttachedPhotosForProject(_selectedProject!.id);
      }

      await _maybeShowTemplateDefaultsHint(workspaceId);
      await _maybeShowPreviewEditHint(workspaceId);
    } catch (e) {
      debugPrint('Error loading document creation data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _maybeShowTemplateDefaultsHint(String workspaceId) async {
    final userId = context.read<AuthProvider>().appUser?.id ?? '';
    final prefs = await SharedPreferences.getInstance();
    final key = 'doc_create_template_defaults_hint_seen_${workspaceId}_$userId';
    final alreadySeen = prefs.getBool(key) ?? false;
    if (alreadySeen || !mounted) return;

    await prefs.setBool(key, true);
    if (!mounted) return;
    setState(() {
      _showTemplateDefaultsHint = true;
    });
  }

  Future<void> _maybeShowPreviewEditHint(String workspaceId) async {
    final userId = context.read<AuthProvider>().appUser?.id ?? '';
    final prefs = await SharedPreferences.getInstance();
    final key = 'doc_create_preview_edit_hint_seen_${workspaceId}_$userId';
    final alreadySeen = prefs.getBool(key) ?? false;
    if (alreadySeen || !mounted) return;

    await prefs.setBool(key, true);
    if (!mounted) return;
    setState(() {
      _showPreviewEditHint = true;
    });
  }

  /// Tax-exempt customers (e.g. municipalities, registered charities) must not
  /// be charged sales tax even though the workspace default collects it. When a
  /// tax-exempt customer is selected on a NEW document, force tax collection
  /// off; when a taxable customer is (re)selected, restore the workspace
  /// default. Editing an existing document leaves its settled tax untouched —
  /// the user can still toggle tax manually after this runs.
  void _applyCustomerTaxExemption() {
    if (_isEditing) return;
    final exempt = _selectedCustomer?.taxExempt ?? false;
    if (exempt) {
      _collectTax = false;
    } else if (_workspace != null) {
      _collectTax = _workspace!.defaultTaxEnabled;
    }
  }

  Future<void> _loadCustomerForProject(String customerId) async {
    final customer = await _customerService.getCustomer(customerId);
    if (mounted && customer != null) {
      setState(() {
        _selectedCustomer = customer;
        _selectedCustomerContact = _getDefaultCustomerContact(customer);
        _applyCustomerTaxExemption();
      });
    }
  }

  Future<void> _refreshCustomers({String? selectCustomerId}) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;
    final customers =
        await _customerService.getCustomersOnce(workspaceId) as List<Customer>;
    if (!mounted) return;
    setState(() {
      _customers = customers;
      if (selectCustomerId != null) {
        _selectedCustomer = customers
            .where((c) => c.id == selectCustomerId)
            .firstOrNull;
        _applyCustomerTaxExemption();
        _selectedCustomerContact = _getDefaultCustomerContact(
          _selectedCustomer,
        );
      }
    });
  }

  CustomerContact? _getDefaultCustomerContact(Customer? customer) {
    if (customer == null) return null;
    final activeContacts = customer.getActiveContacts();
    if (activeContacts.isEmpty) return null;
    return activeContacts.first;
  }

  CustomerContact? _resolveSelectedCustomerContact(Customer? customer) {
    if (customer == null) return null;
    final activeContacts = customer.getActiveContacts();
    if (activeContacts.isEmpty) return null;

    final selected = _selectedCustomerContact;
    if (selected == null) return activeContacts.first;

    for (final contact in activeContacts) {
      if (selected.id != null &&
          contact.id != null &&
          selected.id == contact.id) {
        return contact;
      }
      if ((selected.email ?? '').isNotEmpty &&
          selected.email == contact.email &&
          selected.name == contact.name) {
        return contact;
      }
    }

    return activeContacts.first;
  }

  Future<void> _refreshVendors({String? selectVendorId}) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;
    final vendors = (await (_vendorService.getVendors(workspaceId).first
            as Future<List<Vendor>>))
        .where((v) => v.isActive)
        .toList();
    if (!mounted) return;
    setState(() {
      _vendors = vendors;
      if (selectVendorId != null) {
        _selectedVendor =
            vendors.where((v) => v.id == selectVendorId).firstOrNull;
        _selectedVendorContact = _getDefaultVendorContact(_selectedVendor);
      }
    });
  }

  VendorContact? _getDefaultVendorContact(Vendor? vendor) {
    if (vendor == null) return null;
    return vendor.getPrimaryContact();
  }

  VendorContact? _resolveSelectedVendorContact(Vendor? vendor) {
    if (vendor == null) return null;
    final active = vendor.getActiveContacts();
    if (active.isEmpty) return null;
    final selected = _selectedVendorContact;
    if (selected == null) return active.first;
    for (final c in active) {
      if ((selected.email ?? '').isNotEmpty &&
          selected.email == c.email &&
          selected.name == c.name) {
        return c;
      }
    }
    return active.first;
  }

  /// Returns an error message if the form is invalid, or null if valid.
  String? _validateForm() {
    if (_selectedTemplate == null) {
      return 'Please select a template.';
    }
    if (_preparedByNameController.text.trim().isEmpty) {
      return 'Please enter a name in the "From" section.';
    }
    // Change orders amend an existing contract — every line item must come
    // from a budget item that's already been approved. We block at save
    // time so a user who somehow assembled a free-form CO (older draft,
    // future bypass of the editor's hidden buttons, paste-in) can't ship
    // one through. The editor's import picker enforces the "approved"
    // half of the rule; this check enforces "must be linked to a budget
    // item" for every visible leaf. The predicate lives in
    // `ChangeOrderValidation` so the unit tests use the same logic.
    if (_selectedTemplate!.type == DocumentType.changeOrder) {
      final coMessage = ChangeOrderValidation.messageFor(_lineItems);
      if (coMessage != null) return coMessage;
    }
    return null;
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
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Validates the form, resolves workspace/user, and calls the document
  /// service. Returns the created document, or null if validation failed.
  Future<GeneratedDocument?> _generateDocumentFromForm() async {
    final validationError = _validateForm();
    if (validationError != null) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = validationError;
      });
      _shakeController.forward(from: 0);
      return null;
    }

    // AIA Pay Applications live in their own specialized editor (G702/G703).
    // When the user picks this template, hand off to that editor instead of
    // generating a plain markdown document.
    if (_selectedTemplate!.type == DocumentType.aiaPayApp) {
      if (_selectedProject == null) {
        setState(() {
          _showFieldErrors = true;
          _validationMessage =
              'Please select a project — AIA Pay Applications are project-scoped.';
        });
        _shakeController.forward(from: 0);
        return null;
      }
      if (!mounted) return null;
      context.go('/projects/${_selectedProject!.id}/pay-applications/new');
      return null;
    }

    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final userId = authProvider.appUser?.id;

    if (workspaceId == null || userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to resolve workspace or user.')),
        );
      }
      return null;
    }

    final renderedContent = DocumentTemplateRenderer.render(
      _selectedTemplate!.markdownContent,
      _buildContextData(),
    );
    final selectedBudgetItems = _budgetItems
        .where((item) => _selectedBudgetItemIds.contains(item.id))
        .toList();

    if (_isEditing) {
      final existingDocument = widget.existingDocument!;
      await _documentService.updateDocument(
        documentId: existingDocument.id,
        renderedContent: renderedContent,
        templateId: _selectedTemplate!.id,
        templateName: _selectedTemplate!.name,
        documentType: _selectedTemplate!.type,
        projectId: _selectedProject?.id,
        clearProjectId: _selectedProject == null,
        customerId: _outboundCustomerId,
        clearCustomerId: _outboundCustomerId == null,
        customerName: _outboundCustomerName,
        clearCustomerName: _outboundCustomerName == null,
        documentDate: _documentDate,
        dueDate: _showExpiryDate ? _expiryDate : null,
        clearDueDate: !_showExpiryDate,
        preparedBy: _preparedByInfo,
        preparedFor: _preparedForInfo,
        footerContent: '',
        emailSubject: _emailSubjectController.text.trim(),
        emailMessage: _emailMessageController.text.trim(),
        budgetItems: selectedBudgetItems,
        budgetItemAmounts: _budgetItemAmounts,
        lineItems: _lineItems,
        lineItemVisibility: _lineItemVisibility,
        lineItemSourceMode: _lineItemSourceMode,
        attachedPhotoIds: _attachedPhotoIds,
        collectTax: _collectTax,
        taxName: _collectTax ? _taxName : null,
        taxRate: _collectTax ? _taxRate : 0,
        discountAmount: _discountAmount,
        vendorId: _effectiveVendorId,
        clearVendorId: _effectiveVendorId == null,
        sourceDocumentId: _effectiveSourceDocumentId,
        clearSourceDocumentId: _effectiveSourceDocumentId == null,
        retainagePercent: _holdbackEnabled ? _holdbackPercent : null,
        retainageAmount: _holdbackEnabled ? _holdbackAmount : null,
        clearRetainage: _isInvoiceCategory && !_applyHoldback,
      );
      return existingDocument.copyWith(
        projectId: _selectedProject?.id,
        customerId: _outboundCustomerId,
        customerName: _outboundCustomerName,
        templateId: _selectedTemplate!.id,
        templateName: _selectedTemplate!.name,
        documentType: _selectedTemplate!.type,
        renderedContent: renderedContent,
        createdAt: _documentDate,
        dueDate: _showExpiryDate ? _expiryDate : null,
        preparedBy: _preparedByInfo,
        preparedFor: _preparedForInfo,
        footerContent: '',
        emailSubject: _emailSubjectController.text.trim(),
        emailMessage: _emailMessageController.text.trim(),
        budgetItemIds: selectedBudgetItems.map((item) => item.id).toList(),
        budgetItemAmounts: _budgetItemAmounts,
        lineItems: _lineItems,
        lineItemVisibility: _lineItemVisibility,
        lineItemSourceMode: _lineItemSourceMode,
        attachedPhotoIds: _attachedPhotoIds,
        collectTax: _collectTax,
        taxName: _collectTax ? _taxName : null,
        taxRate: _collectTax ? _taxRate : 0,
        discountAmount: _discountAmount,
        vendorId: _effectiveVendorId,
        sourceDocumentId: _effectiveSourceDocumentId,
      );
    }

    return _documentService.generateDocument(
      workspaceId: workspaceId,
      template: _selectedTemplate!,
      context: _buildContextData(),
      projectId: _selectedProject?.id,
      customerId: _outboundCustomerId,
      customerName: _outboundCustomerName,
      createdBy: userId,
      documentDate: _documentDate,
      dueDate: _showExpiryDate ? _expiryDate : null,
      preparedBy: _preparedByInfo,
      preparedFor: _preparedForInfo,
      footerContent: '',
      emailSubject: _emailSubjectController.text.trim(),
      emailMessage: _emailMessageController.text.trim(),
      budgetItems: selectedBudgetItems,
      budgetItemAmounts: _budgetItemAmounts,
      lineItems: _lineItems,
      lineItemVisibility: _lineItemVisibility,
      lineItemSourceMode: _lineItemSourceMode,
      attachedPhotoIds: _attachedPhotoIds,
      collectTax: _collectTax,
      taxName: _collectTax ? _taxName : null,
      taxRate: _collectTax ? _taxRate : 0,
      discountAmount: _discountAmount,
      vendorId: _effectiveVendorId,
      sourceDocumentId: _effectiveSourceDocumentId,
      retainagePercent: _holdbackEnabled ? _holdbackPercent : null,
      retainageAmount: _holdbackEnabled ? _holdbackAmount : null,
    );
  }

  Future<void> _submitDocument() async {
    final validationError = _validateForm();
    if (validationError != null) {
      setState(() {
        _showFieldErrors = true;
        _validationMessage = validationError;
      });
      _shakeController.forward(from: 0);
      return;
    }

    setState(() => _isCreating = true);
    try {
      final document = await _generateDocumentFromForm();
      if (document == null) return;

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_successMessage)));
        if (widget.embedded && widget.onDocumentCreated != null) {
          widget.onDocumentCreated!(document.id);
        } else if (!_isEditing && document.projectId != null) {
          context.go(
            Uri(
              path: '/files',
              queryParameters: {
                'projectId': document.projectId!,
                'folder': VirtualFolderType.documents,
              },
            ).toString(),
          );
        } else {
          context.go('/documents/${document.id}');
        }
      }
    } catch (e, st) {
      debugPrint('Error saving document: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(
                e,
                action: _isEditing ? 'updating document' : 'creating document',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Map<String, dynamic> _buildContextData() {
    final authProvider = context.read<AuthProvider>();
    final now = _documentDate;
    final dateFormat = DateFormat('MM/dd/yyyy');
    final dateSuffix = _dateSuffix;
    final visibleContextItems = _lineItems
        .where((item) => item.isVisible)
        .toList();
    final visibleLeafItems = visibleContextItems
        .where((item) => item.isItem)
        .toList();
    final scopeDescription =
        _aiDraftScope ?? _selectedProject?.description ?? '';

    Map<String, dynamic> toTemplateLineItem(DocumentLineItem item) {
      final description =
          (item.description != null && item.description!.trim().isNotEmpty)
          ? item.description!.trim()
          : item.name;
      return {
        'id': item.id,
        'name': item.name,
        'description': description,
        'quantity': item.quantity.toStringAsFixed(2),
        'unit': item.unit ?? '',
        'rate': item.unitPrice.toStringAsFixed(2),
        'unitPrice': item.unitPrice.toStringAsFixed(2),
        'amount': item.total.toStringAsFixed(2),
        'total': item.total.toStringAsFixed(2),
        'percentComplete': '100',
      };
    }

    Map<String, dynamic> toSelectionItem(DocumentLineItem item) {
      final selection =
          (item.description != null && item.description!.trim().isNotEmpty)
          ? item.description!.trim()
          : item.name;
      return {
        'itemName': item.name,
        'selection': selection,
        'price': item.total.toStringAsFixed(2),
      };
    }

    List<DocumentLineItem> collectDescendants(String parentId) {
      final directChildren = visibleContextItems
          .where((item) => item.parentId == parentId)
          .toList();
      final all = <DocumentLineItem>[];
      for (final child in directChildren) {
        all.add(child);
        all.addAll(collectDescendants(child.id));
      }
      return all;
    }

    final templateLineItems = visibleLeafItems.map(toTemplateLineItem).toList();
    final categorizedItemIds = <String>{};
    final categories = <Map<String, dynamic>>[];

    for (final group in visibleContextItems.where(
      (item) => item.isGroup && item.parentId == null,
    )) {
      final groupLeafItems = collectDescendants(
        group.id,
      ).where((item) => item.isItem).toList();
      if (groupLeafItems.isEmpty) {
        continue;
      }

      categorizedItemIds.addAll(groupLeafItems.map((item) => item.id));
      categories.add({
        'categoryName': group.name,
        'items': groupLeafItems.map(toSelectionItem).toList(),
      });
    }

    final uncategorizedItems = visibleLeafItems
        .where((item) => !categorizedItemIds.contains(item.id))
        .toList();
    if (uncategorizedItems.isNotEmpty) {
      categories.add({
        'categoryName': 'Selections',
        'items': uncategorizedItems.map(toSelectionItem).toList(),
      });
    }

    String frequencyLabel(DocumentLineItem item) {
      final isWhole =
          (item.quantity - item.quantity.roundToDouble()).abs() < 0.0001;
      final qty = isWhole
          ? item.quantity.toStringAsFixed(0)
          : item.quantity.toStringAsFixed(2);
      return qty == '1' ? 'One-time' : '$qty units';
    }

    final services = visibleLeafItems
        .map(
          (item) => {
            'name': item.name,
            'frequency': frequencyLabel(item),
            'price': item.total.toStringAsFixed(2),
          },
        )
        .toList();
    final taskItems = visibleLeafItems
        .map(
          (item) => {'name': item.name, 'description': item.description ?? ''},
        )
        .toList();
    final actionItems = visibleLeafItems
        .map((item) => {'action': item.name})
        .toList();
    final materialItems = visibleLeafItems
        .map(
          (item) => {
            'name': item.name,
            'quantity': item.quantity.toStringAsFixed(2),
            'cost': item.total.toStringAsFixed(2),
            'notes': item.description ?? '',
          },
        )
        .toList();
    final equipmentItems = visibleLeafItems
        .map(
          (item) => {
            'name': item.name,
            'serialNumber': '',
            'dailyRate': item.unitPrice.toStringAsFixed(2),
            'rentalDays': item.quantity.toStringAsFixed(0),
          },
        )
        .toList();
    final maintenanceItems = visibleLeafItems
        .map(
          (item) => {
            'item': item.name,
            'status': '',
            'notes': item.description ?? '',
          },
        )
        .toList();
    final expenseItems = visibleLeafItems
        .map(
          (item) => {
            'date': dateFormat.format(now),
            'description': item.description?.trim().isNotEmpty == true
                ? item.description!.trim()
                : item.name,
            'category': item.unit ?? '',
            'amount': item.total.toStringAsFixed(2),
          },
        )
        .toList();
    final requirements = visibleLeafItems
        .map((item) => {'requirement': item.name})
        .toList();
    final selectionsTotal = visibleLeafItems.fold<double>(
      0,
      (sum, item) => sum + item.total,
    );
    final workspaceName = _workspace?.name.trim().isNotEmpty == true
        ? _workspace!.name.trim()
        : _preparedByOrgController.text.trim();
    final workspaceAddress =
        _workspace?.fullCompanyAddress?.replaceAll('\n', ', ').trim() ??
        _preparedByAddressController.text.trim();

    final projectTerminology = context
        .read<WorkspaceProvider>()
        .projectTerminology;
    final projectTerminologySingular =
        projectTerminology.endsWith('s') && projectTerminology.length > 1
        ? projectTerminology.substring(0, projectTerminology.length - 1)
        : projectTerminology;

    return {
      'project_terminology': projectTerminologySingular,
      'date': {
        'today': dateFormat.format(now),
        'day': now.day.toString(),
        'month': DateFormat('MMMM').format(now),
        'year': now.year.toString(),
        'time': DateFormat('hh:mm a').format(now),
      },
      'user': {
        'name': authProvider.appUser?.displayName ?? '',
        'email': authProvider.appUser?.email ?? '',
      },
      'workspace': {
        'name': workspaceName,
        'address': workspaceAddress,
        'email': _preparedByEmailController.text.trim(),
        'phone': _preparedByPhoneController.text.trim(),
      },
      if (_selectedProject != null)
        'project': {
          'name': _selectedProject!.name,
          'address': _selectedProject!.address,
          'description': _aiDraftScope ?? _selectedProject!.description ?? '',
          'status': _selectedProject!.status.displayName,
          'startDate': _selectedProject!.startDate != null
              ? dateFormat.format(_selectedProject!.startDate!)
              : '',
          'endDate': _selectedProject!.targetCompletionDate != null
              ? dateFormat.format(_selectedProject!.targetCompletionDate!)
              : '',
          'purchaseOrderNumber': _selectedProject!.purchaseOrderNumber ?? '',
        }
      else if (_aiDraftScope != null)
        'project': {
          'name': '',
          'address': '',
          'description': _aiDraftScope!,
          'status': '',
          'startDate': '',
          'endDate': '',
          'purchaseOrderNumber': '',
        },
      if (!_isVendorDocument && _selectedCustomer != null)
        'customer': {
          'name':
              _resolveSelectedCustomerContact(_selectedCustomer)?.name ??
              _selectedCustomer!.displayName,
          'email':
              _resolveSelectedCustomerContact(_selectedCustomer)?.email ?? '',
          'phone':
              _resolveSelectedCustomerContact(_selectedCustomer)?.phone ?? '',
          'address': _selectedCustomer!.fullAddress ?? '',
          'company': _selectedCustomer!.companyName ?? '',
        },
      if (_isVendorDocument && _selectedVendor != null)
        'vendor': {
          'name':
              _resolveSelectedVendorContact(_selectedVendor)?.name ??
                  _selectedVendor!.displayName,
          'email':
              _resolveSelectedVendorContact(_selectedVendor)?.email ??
                  _selectedVendor!.businessEmail ??
                  '',
          'phone':
              _resolveSelectedVendorContact(_selectedVendor)?.phone ??
                  _selectedVendor!.businessPhone ??
                  '',
          'address': _selectedVendor!.fullAddress ?? '',
          'company': _selectedVendor!.companyName,
        }
      else
        'vendor': {'name': ''},
      // Template-specific placeholders with defaults
      'invoice': {
        'number': 'INV-$dateSuffix',
        'dueDate': dateFormat.format(_expiryDate),
        'billingPeriod': DateFormat('MMMM yyyy').format(now),
        'previousBillings': '0.00',
        'currentAmount': _grandTotal.toStringAsFixed(2),
        'totalBilled': _grandTotal.toStringAsFixed(2),
        'subtotal': _subtotal.toStringAsFixed(2),
        'taxPercent': _taxRate.toStringAsFixed(2),
        'taxAmount': _taxAmount.toStringAsFixed(2),
        'total': _grandTotal.toStringAsFixed(2),
      },
      'contract': {
        'total': _grandTotal.toStringAsFixed(2),
        'originalAmount': _grandTotal.toStringAsFixed(2),
        'newTotal': _grandTotal.toStringAsFixed(2),
        'balance': '0.00',
        'remaining': '0.00',
      },
      'changeOrder': {
        'number': 'CO-$dateSuffix',
        'description': scopeDescription,
        'total': _grandTotal.toStringAsFixed(2),
      },
      'workOrder': {
        'number': 'WO-$dateSuffix',
        'description': scopeDescription,
        'timeReceived': DateFormat('hh:mm a').format(now),
        'emergencyDescription': scopeDescription,
        'dispatchTime': DateFormat('hh:mm a').format(now),
        'completionNotes': '',
        'scheduledDate': dateFormat.format(_documentDate),
        'notes': scopeDescription,
        'nextScheduled': '',
      },
      'quote': {
        'number': 'Q-$dateSuffix',
        'validUntil': dateFormat.format(_expiryDate),
        'description': scopeDescription,
        'total': _grandTotal.toStringAsFixed(2),
      },
      'selections': {
        'total': selectionsTotal.toStringAsFixed(2),
        'notes': scopeDescription,
      },
      'categories': categories,
      'services': services,
      'requirements': requirements,
      'tasks': taskItems,
      'actions': actionItems,
      'materials': materialItems,
      'parts': materialItems,
      'equipment': equipmentItems,
      'maintenanceItems': maintenanceItems,
      'expenses': expenseItems,
      'agreement': {
        'number': 'AGR-$dateSuffix',
        'servicesDescription': scopeDescription,
        'duration': '12 months',
        'paymentTerms': 'Net 30',
        'cancellationPolicy': '30 days written notice required.',
      },
      'rental': {
        'number': 'RENT-$dateSuffix',
        'startDate': dateFormat.format(_documentDate),
        'endDate': dateFormat.format(_expiryDate),
        'total': _grandTotal.toStringAsFixed(2),
      },
      'inspection': {
        'number': 'INSP-$dateSuffix',
        'photoNotes': '',
        'notes': scopeDescription,
        'recommendations': '',
      },
      'inspectionItems': visibleLeafItems
          .map(
            (item) => {
              'item': item.name,
              'status': '',
              'notes': item.description ?? '',
            },
          )
          .toList(),
      'inspector': {'name': authProvider.appUser?.displayName ?? ''},
      'technician': {'name': authProvider.appUser?.displayName ?? ''},
      'assignee': {'name': authProvider.appUser?.displayName ?? ''},
      'auth': {
        'number': 'AUTH-$dateSuffix',
        'emergencyDescription': scopeDescription,
        'workDescription': scopeDescription,
        'minEstimate': _subtotal.toStringAsFixed(2),
        'maxEstimate': _grandTotal.toStringAsFixed(2),
        'damageDescription': scopeDescription,
        'estimate': _grandTotal.toStringAsFixed(2),
        'laborCost': '0.00',
        'materialsTotal': _subtotal.toStringAsFixed(2),
        'total': _grandTotal.toStringAsFixed(2),
      },
      'restorationItems': visibleLeafItems
          .map((item) => {'item': item.name})
          .toList(),
      'credit': {
        'number': 'CR-$dateSuffix',
        'originalInvoice': '',
        'originalBill': '',
        'total': _grandTotal.toStringAsFixed(2),
        'reason': scopeDescription,
      },
      'deposit': {
        'number': 'DEP-$dateSuffix',
        'amount': _grandTotal.toStringAsFixed(2),
        'paymentMethod': '',
      },
      'refund': {
        'number': 'REF-$dateSuffix',
        'originalTransaction': '',
        'total': _grandTotal.toStringAsFixed(2),
        'method': '',
        'reason': scopeDescription,
      },
      'po': {
        'number': 'PO-$dateSuffix',
        'deliveryDate': dateFormat.format(_expiryDate),
        'subtotal': _subtotal.toStringAsFixed(2),
        'tax': _taxAmount.toStringAsFixed(2),
        'total': _grandTotal.toStringAsFixed(2),
        'shippingAddress': workspaceAddress,
        'notes': scopeDescription,
      },
      'rfb': {
        'number': 'RFB-$dateSuffix',
        'dueDate': dateFormat.format(_expiryDate),
        'scopeOfWork': scopeDescription,
        'questionsDueDate': dateFormat.format(
          _documentDate.add(
            Duration(
              days: (_expiryDate.difference(_documentDate).inDays / 2)
                  .round()
                  .clamp(1, 365),
            ),
          ),
        ),
        'contact': _preparedByNameController.text.trim(),
      },
      'bill': {
        'number': 'BILL-$dateSuffix',
        'total': _grandTotal.toStringAsFixed(2),
        'status': 'Unpaid',
      },
      'expense': {'total': _grandTotal.toStringAsFixed(2)},
      // Only include lineItems in template context when the widget won't
      // render them separately (visibility == none). This avoids duplicate
      // pricing in the markdown AND the line-items table.
      'lineItems': _lineItemVisibility == LineItemVisibility.none
          ? templateLineItems
          : <Map<String, dynamic>>[],
      // Flag for templates to conditionally show pricing sections.
      'pricing': _lineItemVisibility == LineItemVisibility.none,
    };
  }

  IconData _getIconForType(DocumentType type) {
    switch (type) {
      case DocumentType.invoice:
      case DocumentType.progressInvoice:
        return Icons.receipt_long;
      case DocumentType.workOrder:
      case DocumentType.workOrderEmergency:
      case DocumentType.workOrderMaintenance:
        return Icons.assignment;
      case DocumentType.quotation:
        return Icons.request_quote;
      case DocumentType.expense:
        return Icons.money_off;
      case DocumentType.bill:
        return Icons.receipt;
      case DocumentType.purchaseOrder:
        return Icons.shopping_cart;
      case DocumentType.custom:
        return Icons.description;
      default:
        return type.category.icon;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= AppBreakpoints.desktop;

    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : isDesktop
        ? _buildDesktopLayout()
        : _showPreview
        ? _buildPreviewPanel()
        : _buildEditorPanel();

    if (widget.embedded) {
      // Embedded mode: no Scaffold/AppBar, just body with a toolbar row
      return Column(
        children: [
          // Toolbar row
          Builder(
            builder: (context) {
              final chrome = ChromeColors.of(context);
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: chrome.background,
                  border: chrome.isDark
                      ? null
                      : Border(bottom: BorderSide(color: chrome.divider)),
                ),
                child: Row(
                  children: [
                    if (widget.onBack != null)
                      IconButton(
                        icon: const Icon(Icons.arrow_back, size: 20),
                        tooltip: 'Back',
                        onPressed: widget.onBack,
                      ),
                    const Spacer(),
                    Text(
                      _screenTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: chrome.textActive,
                      ),
                    ),
                    const Spacer(),
                    if (!isDesktop) ...[
                      IconButton(
                        icon: const Icon(Icons.settings, size: 20),
                        tooltip: 'Settings',
                        onPressed: () => _showSettingsBottomSheet(context),
                      ),
                      IconButton(
                        icon: Icon(_showPreview ? Icons.edit : Icons.preview),
                        tooltip: _showPreview ? 'Edit' : 'Preview',
                        onPressed: () {
                          setState(() => _showPreview = !_showPreview);
                        },
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_screenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (GoRouter.of(context).canPop()) {
              context.pop();
            } else {
              context.go('/documents');
            }
          },
        ),
        actions: [
          if (!isDesktop)
            IconButton(
              icon: const Icon(Icons.settings, size: 20),
              tooltip: 'Settings',
              onPressed: () => _showSettingsBottomSheet(context),
            ),
          if (!isDesktop)
            IconButton(
              icon: Icon(_showPreview ? Icons.edit : Icons.preview),
              tooltip: _showPreview ? 'Edit' : 'Preview',
              onPressed: () {
                setState(() => _showPreview = !_showPreview);
              },
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildDesktopLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 8.0;
        final available = constraints.maxWidth - dividerWidth;
        final previewWidth = (available * _splitRatio).clamp(
          300.0,
          available - 300.0,
        );
        final editorWidth = available - previewWidth;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Inputs and actions (left)
            SizedBox(
              width: editorWidth,
              child: Column(
                children: [
                  Expanded(
                    child: _buildEditorPanel(
                      includeCreateButton: false,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                    ),
                  ),
                  _buildCreateStepActionBar(),
                ],
              ),
            ),
            // Draggable divider
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _splitRatio =
                      ((_splitRatio * available - details.delta.dx) / available)
                          .clamp(300.0 / available, 1.0 - 300.0 / available);
                });
              },
              child: DraggableDivider(width: dividerWidth),
            ),
            // Preview panel (right) — scrolls independently from the editor
            SizedBox(
              width: previewWidth,
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: _buildPreviewPanel(constrained: true),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCreateStepActionBar() {
    final chrome = ChromeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: chrome.background,
        border: chrome.isDark
            ? null
            : Border(top: BorderSide(color: chrome.divider)),
      ),
      child: Row(
        children: [
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
              onPressed: (_isCreating || !context.read<AuthProvider>().canUploadFiles)
                  ? null
                  : () => _submitDocument(),
              icon: _isCreating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_isEditing ? Icons.save : Icons.add, size: 18),
              label: Text(
                _isCreating ? _submitProgressLabel : _submitButtonLabel,
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => StatefulBuilder(
          builder: (context, setSheetState) => SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildSettingsContent(onChanged: () => setSheetState(() {})),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Shared settings content used by the mobile bottom sheet.
  Widget _buildSettingsContent({VoidCallback? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Line Item Visibility',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SegmentedButton<LineItemVisibility>(
          segments: const [
            ButtonSegment(
              value: LineItemVisibility.all,
              label: Text('All', style: TextStyle(fontSize: 12)),
            ),
            ButtonSegment(
              value: LineItemVisibility.topLevel,
              label: Text('Top', style: TextStyle(fontSize: 12)),
            ),
            ButtonSegment(
              value: LineItemVisibility.none,
              label: Text('None', style: TextStyle(fontSize: 12)),
            ),
          ],
          selected: {_lineItemVisibility},
          onSelectionChanged: (selected) {
            setState(() => _lineItemVisibility = selected.first);
            onChanged?.call();
          },
        ),
        const SizedBox(height: 6),
        Text(switch (_lineItemVisibility) {
          LineItemVisibility.all =>
            'Show all line items and groups in the document.',
          LineItemVisibility.topLevel =>
            'Show only top-level groups with totals, hide individual items.',
          LineItemVisibility.none =>
            'Hide the line items table. Pricing from the template text will be used instead.',
        }, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildTaxSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Collect Tax', style: TextStyle(fontSize: 14)),
          value: _collectTax,
          dense: true,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) => setState(() => _collectTax = value),
        ),
        if (_collectTax) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _taxNameController,
            decoration: const InputDecoration(
              labelText: 'Tax Name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) =>
                setState(() => _taxName = value.isEmpty ? 'Tax' : value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _taxRateController,
            decoration: const InputDecoration(
              labelText: 'Tax Rate',
              border: OutlineInputBorder(),
              isDense: true,
              suffix: Text('%'),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) =>
                setState(() => _taxRate = double.tryParse(value) ?? 0),
          ),
        ],
        if (_isInvoiceCategory) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _discountController,
            decoration: const InputDecoration(
              labelText: 'Discount',
              border: OutlineInputBorder(),
              isDense: true,
              prefixText: '\$ ',
              helperText: 'Flat amount, applied before tax',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) =>
                setState(() => _discountAmount = double.tryParse(value) ?? 0),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            children: [
              _buildTotalRow('Subtotal', _subtotal),
              if (_discountAmount > 0) ...[
                const SizedBox(height: 8),
                _buildTotalRow('Discount', -_discountAmount),
              ],
              if (_collectTax && _taxRate > 0) ...[
                const SizedBox(height: 8),
                _buildTotalRow(
                  '$_taxName (${_taxRate.toStringAsFixed(1)}%)',
                  _taxAmount,
                ),
              ],
              const Divider(height: 16),
              _buildTotalRow('Grand Total', _grandTotal, bold: true),
              if (_isInvoiceCategory) ...[
                const Divider(height: 16),
                _buildHoldbackEditor(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHoldbackEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Apply holdback (retainage)',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            Switch(
              value: _applyHoldback,
              onChanged: (value) => setState(() => _applyHoldback = value),
            ),
          ],
        ),
        if (_applyHoldback) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: TextField(
              controller: _holdbackPercentController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Holdback',
                border: OutlineInputBorder(),
                isDense: true,
                suffixText: '%',
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (value) => setState(() {
                final parsed = double.tryParse(value.trim());
                if (parsed != null && parsed >= 0 && parsed <= 100) {
                  _holdbackPercent = parsed;
                }
              }),
            ),
          ),
          const SizedBox(height: 8),
          _buildTotalRow(
            'Holdback withheld (${_holdbackPercent.toStringAsFixed(1)}%)',
            _holdbackAmount,
          ),
        ],
      ],
    );
  }

  String _formatCurrency(double amount) {
    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    return CurrencyUtils.formatCurrency(amount, currencyCode);
  }

  Widget _buildTotalRow(String label, double amount, {bool bold = false}) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(_formatCurrency(amount), style: style),
      ],
    );
  }

  Widget _buildEditorPanel({
    bool includeCreateButton = true,
    EdgeInsetsGeometry padding = const EdgeInsets.all(AppSpacing.xl),
  }) {
    return SingleChildScrollView(
      controller: _editorScrollController,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildValidationBanner(),
          if (_showTemplateDefaultsHint) ...[
            Card(
              color: AppColors.info.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_fix_high,
                      size: 20,
                      color: AppColors.secondaryDark,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Core templates are set up by default. You can customize them under Documents > Templates.',
                        style: TextStyle(
                          color: ChromeColors.of(context).textActive,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() => _showTemplateDefaultsHint = false);
                      },
                      icon: Icon(
                        Icons.close,
                        color: ChromeColors.of(context).textActive,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Grid: Select Template | Date           (row 1)
          //       From            | Select Customer (row 2)
          //       Select Job (alone, !embedded only)(row 3)
          // Each row uses IntrinsicHeight so the two cards align in height.
          // On mobile/tablet, stack vertically.
          Builder(
            builder: (context) {
              Widget cell({
                required String title,
                required IconData icon,
                required bool isComplete,
                bool isRequired = false,
                required Widget card,
                GlobalKey? sectionKey,
              }) {
                final inner = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSectionHeader(
                      title,
                      icon,
                      isComplete: isComplete,
                      isRequired: isRequired,
                    ),
                    const SizedBox(height: 6),
                    card,
                  ],
                );
                if (sectionKey != null) {
                  return _highlightableSection(key: sectionKey, child: inner);
                }
                return inner;
              }

              final templateCell = cell(
                title: 'Select Template',
                icon: Icons.article,
                isComplete: _selectedTemplate != null,
                isRequired: true,
                card: _buildTemplateSelector(),
                sectionKey: _templateSectionKey,
              );
              final dateCell = cell(
                title: 'Date',
                icon: Icons.calendar_today,
                isComplete: true,
                card: _buildDocumentDatesSection(),
              );
              final fromCell = cell(
                title: 'From',
                icon: Icons.business,
                isComplete: _preparedByNameController.text.isNotEmpty,
                isRequired: true,
                card: _buildPreparedBySection(),
                sectionKey: _preparedBySectionKey,
              );
              final projectCell = cell(
                title: 'Select ${_getSingularTerminology()}',
                icon: Icons.folder,
                isComplete: _selectedProject != null,
                card: _buildProjectSelector(),
              );
              final customerCell = cell(
                title: _isVendorDocument
                    ? 'Select Vendor'
                    : 'Select Customer',
                icon: _isVendorDocument
                    ? Icons.local_shipping
                    : Icons.person,
                isComplete: _isVendorDocument
                    ? _selectedVendor != null
                    : _selectedCustomer != null,
                card: _isVendorDocument
                    ? _buildVendorSelector()
                    : _buildCustomerSelector(),
                sectionKey: _customerSectionKey,
              );

              Widget rowOf(Widget left, Widget right) => IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: left),
                        const SizedBox(width: 12),
                        Expanded(child: right),
                      ],
                    ),
                  );

              if (_isDesktopLayout) {
                final rightStack = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    dateCell,
                    const SizedBox(height: 2),
                    fromCell,
                    const SizedBox(height: 2),
                    customerCell,
                  ],
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: templateCell),
                        const SizedBox(width: 12),
                        Expanded(child: rightStack),
                      ],
                    ),
                    if (!widget.embedded) ...[
                      const SizedBox(height: 14),
                      projectCell,
                    ],
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  templateCell,
                  const SizedBox(height: 14),
                  dateCell,
                  const SizedBox(height: 14),
                  fromCell,
                  const SizedBox(height: 14),
                  customerCell,
                  if (!widget.embedded) ...[
                    const SizedBox(height: 14),
                    projectCell,
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 32),

          // Line Items (Optional - only when project is selected)
          if (_selectedProject != null) ...[
            _highlightableSection(
              key: _lineItemSectionKey,
              child: _buildLineItemEditor(),
            ),
            const SizedBox(height: 32),
          ],

          // Attach Files (Optional - only when project is selected)
          if (_selectedProject != null) ...[
            _highlightableSection(
              key: _photoSectionKey,
              child: _buildSectionHeader(
                'Attach Files',
                Icons.attach_file,
                isComplete: _attachedPhotoIds.isNotEmpty,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select photos, PDFs, Word, or Excel files from the ${_getSingularTerminology().toLowerCase()} to include in the document and customer email.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            _buildPhotoSelector(),
            const SizedBox(height: 20),
          ],

          if (includeCreateButton) ...[
            const SizedBox(height: 16),
            _buildMobileActions(),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary action
        AnimatedBuilder(
          animation: _shakeController,
          builder: (context, child) {
            final dx = _shakeController.isAnimating
                ? math.sin(_shakeController.value * math.pi * 4) * 6
                : 0.0;
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: ElevatedButton.icon(
            onPressed: (_isCreating || !context.read<AuthProvider>().canUploadFiles)
                ? null
                : () => _submitDocument(),
            icon: _isCreating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_isEditing ? Icons.save : Icons.add),
            label: Text(
              _isCreating ? _submitProgressLabel : _submitButtonLabel,
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewPanel({bool constrained = false}) {
    // Build rendered content from template
    String renderedContent = '';
    if (_selectedTemplate != null) {
      final contextData = _buildContextData();
      renderedContent = DocumentTemplateRenderer.render(
        _selectedTemplate!.markdownContent,
        contextData,
      );
    }

    final scrollView = SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Document Preview',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: ChromeColors.of(context).textActive,
            ),
          ),
          if (_showPreviewEditHint) ...[
            const SizedBox(height: 8),
            Card(
              color: AppColors.info.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(Icons.touch_app, size: 18, color: AppColors.info),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        kIsWeb ? 'Click any field in the preview to quickly edit it.' : 'Tap any field in the preview to quickly edit it.',
                        style: TextStyle(
                          fontSize: 11,
                          color: ChromeColors.of(context).textActive,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: ChromeColors.of(context).textActive,
                      ),
                      onPressed: () {
                        setState(() => _showPreviewEditHint = false);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          DocumentPreviewWidget(
            logoUrl: _workspace?.avatarUrl,
            templateName: _selectedTemplate?.name ?? 'Document',
            documentDate: _documentDate,
            expiryDate: _showExpiryDate ? _expiryDate : null,
            expiryDateLabel:
                _selectedTemplate?.type.expiryDateLabel ?? 'Expires',
            documentType: _selectedTemplate?.type,
            preparedBy: _preparedByInfo,
            preparedFor: _preparedForInfo,
            renderedContent: renderedContent,
            lineItems: _lineItems,
            lineItemVisibility: _lineItemVisibility,
            attachedPhotos: _attachedPhotos,
            footerContent: '',
            showSignaturePlaceholder: true,
            collectTax: _collectTax,
            taxName: _taxName,
            taxRate: _taxRate,
            discountAmount: _discountAmount,
            retainagePercent: _holdbackEnabled ? _holdbackPercent : 0,
            retainageAmount: _holdbackEnabled ? _holdbackAmount : 0,
            onTemplateNameTap: _editTemplateName,
            onDocumentDateTap: _pickDocumentDate,
            onExpiryDateTap: _showExpiryDate ? _pickExpiryDate : null,
            onPreparedByTap: _editPreparedBy,
            onPreparedForTap: (_isVendorDocument
                    ? _selectedVendor != null
                    : _selectedCustomer != null)
                ? _editCustomer
                : null,
            onFooterTap: null,
            onContentTap: null,
            onLineItemsTap: _selectedProject != null
                ? () => _scrollToSection(_lineItemSectionKey)
                : null,
            onPhotosTap: _selectedProject != null
                ? () => _scrollToSection(_photoSectionKey)
                : null,
          ),
        ],
      ),
    );

    if (!constrained) return scrollView;

    // In desktop side-by-side mode, prevent scroll events from bubbling up
    // to the parent so the preview scrolls independently.
    return NotificationListener<ScrollNotification>(
      onNotification: (_) => true,
      child: scrollView,
    );
  }

  Widget _buildLineItemEditor() {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Budget Sync Mode',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<LineItemSourceMode>(
              borderRadius: AppRadius.cardRadius,
              initialValue: _lineItemSourceMode,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.sync_alt, size: 16),
                isDense: true,
              ),
              selectedItemBuilder: (context) {
                return LineItemSourceMode.values
                    .map(
                      (mode) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          mode.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    )
                    .toList();
              },
              items: LineItemSourceMode.values
                  .map(
                    (mode) => DropdownMenuItem(
                      value: mode,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            mode.displayName,
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            mode.description,
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (mode) {
                if (mode == null) return;
                setState(() => _lineItemSourceMode = mode);
              },
            ),
            const SizedBox(height: 12),
            DocumentLineItemEditor(
              projectId: _selectedProject?.id,
              workspaceId: workspaceId,
              initialItems: _lineItems,
              initialVisibility: _lineItemVisibility,
              documentType: _selectedTemplate?.type,
              onChanged: (items, visibility, _) {
                setState(() {
                  _lineItems = items;
                  _lineItemVisibility = visibility;
                });
              },
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            _buildTaxSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSelector() {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final userId = authProvider.appUser?.id;

    if (workspaceId == null || userId == null || _selectedProject == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: DocumentPhotoSelector(
          workspaceId: workspaceId,
          projectId: _selectedProject!.id,
          uploadedBy: userId,
          initialSelectedIds: _attachedPhotoIds,
          onSelectionChanged: (selectedIds, selectedFiles) {
            setState(() {
              _attachedPhotoIds = selectedIds;
              _attachedPhotos = selectedFiles;
            });
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon, {
    bool isComplete = false,
    bool isRequired = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: isComplete
                  ? AppColors.success.withValues(alpha: 0.1)
                  : Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isComplete ? Icons.check : icon,
              size: 13,
              color: isComplete
                  ? AppColors.success
                  : ChromeColors.of(context).scaffoldAccent,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: ChromeColors.of(context).scaffoldText,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isRequired) ...[
            const SizedBox(width: 6),
            Text(
              '*Required',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTemplateSelector() {
    if (_templates.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              Icon(
                Icons.article_outlined,
                size: 48,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 12),
              const Text('No templates available'),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => context.go('/documents/templates/new'),
                icon: const Icon(Icons.add),
                label: const Text('Create Template'),
              ),
            ],
          ),
        ),
      );
    }

    // Group templates by category
    final groupedByCategory = <TemplateCategory, List<DocumentTemplate>>{};
    for (final template in _templates) {
      groupedByCategory.putIfAbsent(template.category, () => []).add(template);
    }

    return Column(
      children: [
        for (final category in TemplateCategory.values)
          if (groupedByCategory.containsKey(category))
            _buildCategorySection(category, groupedByCategory[category]!),
      ],
    );
  }

  Widget _buildCategorySection(
    TemplateCategory category,
    List<DocumentTemplate> templates,
  ) {
    final isExpanded = _expandedCategories.contains(category);
    final hasSelectedTemplate = templates.any(
      (t) => t.id == _selectedTemplate?.id,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Category header
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCategories.remove(category);
                } else {
                  _expandedCategories.add(category);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: hasSelectedTemplate
                    ? category.color.withValues(alpha: 0.15)
                    : AppColors.surfaceAlt,
                border: Border(
                  left: BorderSide(
                    color: hasSelectedTemplate
                        ? category.color
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: category.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(category.icon, color: category.color, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            category.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.cardBorder,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            '${templates.length}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          // Templates grid
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Calculate how many cards fit per row (min width 180, max 4 columns)
                  final cardWidth = constraints.maxWidth > 800
                      ? (constraints.maxWidth - 48) / 4
                      : constraints.maxWidth > 600
                      ? (constraints.maxWidth - 32) / 3
                      : constraints.maxWidth > 400
                      ? (constraints.maxWidth - 16) / 2
                      : constraints.maxWidth;

                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: templates.map((template) {
                      final isSelected = _selectedTemplate?.id == template.id;
                      return SizedBox(
                        width: cardWidth.clamp(140.0, 220.0),
                        child: _buildTemplateCard(
                          template,
                          isSelected,
                          category,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(
    DocumentTemplate template,
    bool isSelected,
    TemplateCategory category,
  ) {
    return Material(
      color: isSelected ? category.color.withValues(alpha: 0.1) : Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTemplate = isSelected ? null : template;
            _aiDraftScope = null;
          });
        },
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isSelected ? category.color : AppColors.cardBorder,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                _getIconForType(template.type),
                size: 14,
                color: isSelected
                    ? category.color
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  template.name,
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 12,
                    color:
                        isSelected ? category.color : AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 4),
                Icon(Icons.check_circle, size: 14, color: category.color),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Track which categories are expanded
  final Set<TemplateCategory> _expandedCategories = {};

  Widget _buildProjectSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StackedField(
              label: _getSingularTerminology(),
              child: DropdownButtonFormField<Project?>(
                borderRadius: AppRadius.cardRadius,
                key: ValueKey('project-${_selectedProject?.id ?? 'none'}'),
                initialValue: _selectedProject,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText:
                      'Select a ${_getSingularTerminology().toLowerCase()}',
                  hintStyle: const TextStyle(fontSize: 12),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.folder, size: 16),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem<Project?>(
                    value: null,
                    child: Text(
                      'No ${_getSingularTerminology().toLowerCase()}',
                    ),
                  ),
                  ..._projects.map(
                    (project) => DropdownMenuItem<Project?>(
                      value: project,
                      child: Text(project.name),
                    ),
                  ),
                ],
                onChanged: (project) async {
                  if (_selectedProject?.id == project?.id) return;

                  final hasData =
                      _lineItems.isNotEmpty || _attachedPhotoIds.isNotEmpty;
                  if (hasData) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('Change ${_getSingularTerminology()}?'),
                        content: Text(
                          'Switching ${context.read<WorkspaceProvider>().projectTerminology.toLowerCase()} will clear your current line items and attached files.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                  }

                  setState(() {
                    _selectedProject = project;
                    _aiDraftScope = null;
                    _selectedBudgetItemIds = [];
                    _budgetItemAmounts = {};
                    _budgetItems = [];
                    _lineItems = [];
                    _attachedPhotoIds = [];
                    _attachedPhotos = [];

                    if (!_isVendorDocument && project?.clientId != null) {
                      _loadCustomerForProject(project!.clientId!);
                    }
                    if (project != null) {
                      _loadBudgetItemsForProject(project.id);
                    }

                    // Apply this project's default holdback percent (if any)
                    // when creating a new document. On edit, the invoice's
                    // own retainage was already hydrated.
                    if (!_isEditing) {
                      final pct = project?.holdbackDefaultPercent ?? 0;
                      if (pct > 0) {
                        _applyHoldback = true;
                        _holdbackPercent = pct;
                        _holdbackPercentController.text = pct.toStringAsFixed(
                          1,
                        );
                      } else {
                        _applyHoldback = false;
                        _holdbackPercent = 10;
                        _holdbackPercentController.text = '10';
                      }
                    }
                  });
                },
              ),
            ),
            if (_selectedProject != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedProject!.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _selectedProject!.address,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    if (_selectedProject!.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _selectedProject!.description!,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Customer',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_selectedCustomer != null)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    tooltip: 'Edit Customer',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    onPressed: () async {
                      final id = _selectedCustomer!.id;
                      await showCustomerFormPopup(context, customerId: id);
                      _refreshCustomers(selectCustomerId: id);
                    },
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.person_add, size: 18),
                  tooltip: 'New Customer',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  onPressed: () async {
                    await showCustomerFormPopup(context);
                    _refreshCustomers();
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<Customer?>(
              borderRadius: AppRadius.cardRadius,
              key: ValueKey('customer-${_selectedCustomer?.id ?? 'none'}'),
              isExpanded: true,
              initialValue: _selectedCustomer,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'Select a customer',
                hintStyle: TextStyle(fontSize: 12),
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person, size: 16),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<Customer?>(
                  value: null,
                  child: Text('No customer'),
                ),
                ..._customers.map(
                  (customer) => DropdownMenuItem<Customer?>(
                    value: customer,
                    child: Text(
                      customer.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (customer) {
                if (_selectedCustomer?.id == customer?.id) return;

                setState(() {
                  _selectedCustomer = customer;
                  _selectedCustomerContact = _getDefaultCustomerContact(
                    customer,
                  );
                  _applyCustomerTaxExemption();
                });
              },
            ),
            if (_selectedCustomer != null) ...[
              Builder(
                builder: (context) {
                  final activeContacts = _selectedCustomer!.getActiveContacts();
                  final currentContact = _resolveSelectedCustomerContact(
                    _selectedCustomer,
                  );
                  if (activeContacts.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: StackedField(
                      label: 'Customer Contact',
                      child: DropdownButtonFormField<CustomerContact>(
                        borderRadius: AppRadius.cardRadius,
                        key: ValueKey(
                          'customer-contact-${_selectedCustomer!.id}-${currentContact?.id ?? currentContact?.email ?? currentContact?.name}',
                        ),
                        isExpanded: true,
                        initialValue: currentContact,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.contact_phone, size: 16),
                          isDense: true,
                        ),
                        items: activeContacts.map((contact) {
                          final title = contact.isPrimary
                              ? '${contact.name} (Primary)'
                              : contact.name;

                          return DropdownMenuItem<CustomerContact>(
                            value: contact,
                            child: Text(title, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (contact) {
                          setState(() {
                            _selectedCustomerContact = contact;
                          });
                        },
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedCustomer!.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    if ((_resolveSelectedCustomerContact(
                              _selectedCustomer,
                            )?.email ??
                            '')
                        .isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.email,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _resolveSelectedCustomerContact(
                              _selectedCustomer,
                            )!.email!,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if ((_resolveSelectedCustomerContact(
                              _selectedCustomer,
                            )?.phone ??
                            '')
                        .isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.phone,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _resolveSelectedCustomerContact(
                              _selectedCustomer,
                            )!.phone!,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if ((_selectedCustomer!.fullAddress ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _selectedCustomer!.fullAddress!,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentDatesSection() {
    final dateFormat = DateFormat('MMMM dd, yyyy');
    final expiryLabel =
        _selectedTemplate?.type.expiryDateLabel ?? 'Expiry Date';

    final documentDateField = StackedField(
      label: 'Document Date',
      child: InkWell(
        onTap: _pickDocumentDate,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.calendar_today, size: 16),
            isDense: true,
          ),
          child: Text(
            dateFormat.format(_documentDate),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );

    final expiryDateField = StackedField(
      label: expiryLabel,
      child: InkWell(
        onTap: _pickExpiryDate,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.event_busy, size: 16),
            isDense: true,
          ),
          child: Text(
            dateFormat.format(_expiryDate),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );

    final children = <Widget>[documentDateField];
    if (_showExpiryDate) {
      if (_isDesktopLayout) {
        children
          ..clear()
          ..add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: documentDateField),
                  const SizedBox(width: 16),
                  Expanded(child: expiryDateField),
                ],
              ),
            ),
          );
      } else {
        children.add(const SizedBox(height: 16));
        children.add(expiryDateField);
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  /// Lays out [first] and [second] side-by-side on desktop, stacked on mobile.
  List<Widget> _buildFieldPair({
    required Widget first,
    required Widget second,
  }) {
    if (_isDesktopLayout) {
      return [
        Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 16),
            Expanded(child: second),
          ],
        ),
      ];
    }
    return [first, const SizedBox(height: 16), second];
  }

  Future<void> _loadWorkspaceCountryCode() async {
    try {
      final workspaceId = context
          .read<AuthProvider>()
          .appUser
          ?.currentWorkspaceId;
      if (workspaceId == null) return;
      final data = await _workspaceService.getWorkspace(workspaceId).first;
      if (data == null || !mounted) return;
      final country = data['companyCountry'] as String?;
      if (country != null) {
        _workspaceCountryCode = country.length == 2
            ? country
            : null; // already a code or full name; keep simple
      }
    } catch (_) {}
  }

  void _onAddressChanged() {
    if (_isSettingAddressFromSuggestion) return;

    final query = _preparedByAddressController.text.trim();
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
    if (_preparedByAddressController.text.trim() != query) {
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
    final typedQuery = _preparedByAddressController.text.trim();
    _preparedByAddressController.text = suggestion.singleLineAddress(
      typedQuery: typedQuery,
    );
    _preparedByAddressController.selection = TextSelection.fromPosition(
      TextPosition(offset: _preparedByAddressController.text.length),
    );
    setState(() {
      _addressSuggestions = const [];
      _isLoadingAddressSuggestions = false;
    });
    _isSettingAddressFromSuggestion = false;
  }

  Widget _buildAddressFieldWithSuggestions(TextEditingController controller) {
    return Column(
      children: [
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.location_on, size: 16),
            isDense: true,
            hintText: 'Start typing to search addresses...',
            hintStyle: TextStyle(fontSize: 12),
          ),
          maxLines: 2,
          onChanged: (_) => setState(() {}),
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
                  typedQuery: _preparedByAddressController.text.trim(),
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
      ],
    );
  }

  Widget _buildVendorSelector() {
    final activeContacts = _selectedVendor?.getActiveContacts() ?? const [];
    final currentContact = _resolveSelectedVendorContact(_selectedVendor);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Vendor',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                if (_selectedVendor != null)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    tooltip: 'Edit Vendor',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    onPressed: () async {
                      final id = _selectedVendor!.id;
                      await showVendorFormPopup(context, vendorId: id);
                      _refreshVendors(selectVendorId: id);
                    },
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.add_business, size: 18),
                  tooltip: 'New Vendor',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  onPressed: () async {
                    final id = await showVendorFormPopup(context);
                    if (id != null) {
                      _refreshVendors(selectVendorId: id);
                    } else {
                      _refreshVendors();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<Vendor?>(
              borderRadius: AppRadius.cardRadius,
              key: ValueKey('vendor-${_selectedVendor?.id ?? 'none'}'),
              isExpanded: true,
              initialValue: _selectedVendor,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'Select a vendor',
                hintStyle: TextStyle(fontSize: 12),
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_shipping, size: 16),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<Vendor?>(
                  value: null,
                  child: Text('No vendor'),
                ),
                ..._vendors.map(
                  (vendor) => DropdownMenuItem<Vendor?>(
                    value: vendor,
                    child: Text(
                      vendor.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (vendor) {
                if (_selectedVendor?.id == vendor?.id) return;
                setState(() {
                  _selectedVendor = vendor;
                  _selectedVendorContact = _getDefaultVendorContact(vendor);
                });
              },
            ),
            if (_selectedVendor != null) ...[
              if (activeContacts.length > 1) ...[
                const SizedBox(height: 12),
                StackedField(
                  label: 'Vendor Contact',
                  child: DropdownButtonFormField<VendorContact>(
                    borderRadius: AppRadius.cardRadius,
                    key: ValueKey(
                      'vendor-contact-${_selectedVendor!.id}-${currentContact?.email ?? currentContact?.name}',
                    ),
                    isExpanded: true,
                    initialValue: currentContact,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.contact_phone, size: 16),
                      isDense: true,
                    ),
                    items: activeContacts.map((c) {
                      final title =
                          c.isPrimary ? '${c.name} (Primary)' : c.name;
                      return DropdownMenuItem<VendorContact>(
                        value: c,
                        child: Text(title, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (c) {
                      setState(() => _selectedVendorContact = c);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedVendor!.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    if (((currentContact?.email ?? '').isNotEmpty) ||
                        ((_selectedVendor!.businessEmail ?? '').isNotEmpty)) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.email,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              currentContact?.email ??
                                  _selectedVendor!.businessEmail ??
                                  '',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (((currentContact?.phone ?? '').isNotEmpty) ||
                        ((_selectedVendor!.businessPhone ?? '').isNotEmpty)) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.phone,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            currentContact?.phone ??
                                _selectedVendor!.businessPhone ??
                                '',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if ((_selectedVendor!.fullAddress ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.location_on,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _selectedVendor!.fullAddress!,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreparedBySection() {
    final org = _preparedByOrgController.text.trim();
    final name = _preparedByNameController.text.trim();
    final email = _preparedByEmailController.text.trim();
    final phone = _preparedByPhoneController.text.trim();

    final summaryLines = <String>[];
    if (name.isNotEmpty) summaryLines.add(name);
    final contactBits = <String>[];
    if (email.isNotEmpty) contactBits.add(email);
    if (phone.isNotEmpty) contactBits.add(phone);
    if (contactBits.isNotEmpty) summaryLines.add(contactBits.join(' · '));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'From',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: 'Edit From',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  onPressed: _showPreparedByEditor,
                ),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: _showPreparedByEditor,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.cardBorder),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.business, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            org.isEmpty ? 'Add organization' : org,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: org.isEmpty
                                  ? AppColors.textTertiary
                                  : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (summaryLines.isNotEmpty)
                            ...summaryLines.map(
                              (line) => Text(
                                line,
                                style: const TextStyle(fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPreparedByEditor() {
    const fieldStyle = TextStyle(fontSize: 13);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: StatefulBuilder(
            builder: (ctx, setDialogState) => SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'From',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _preparedByOrgController,
                    style: fieldStyle,
                    decoration: const InputDecoration(
                      labelText: 'Organization',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business, size: 18),
                      isDense: true,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _preparedByNameController,
                    style: fieldStyle,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person, size: 18),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      _clearValidationErrors();
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _preparedByPhoneController,
                    style: fieldStyle,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone, size: 18),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _preparedByEmailController,
                    style: fieldStyle,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email, size: 18),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 10),
                  _buildAddressFieldWithSuggestions(
                    _preparedByAddressController,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _buildAiDraftCard() {
    final hasTemplate = _selectedTemplate != null;
    final canGenerate = hasTemplate && !_isGeneratingAiDraft;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 20, color: AppColors.secondaryDark),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI Draft',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    'Auto-generate scope, footer, and email content',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (_aiDraftScope != null) ...[
              InputChip(
                avatar: const Icon(Icons.check_circle, size: 16),
                label: const Text('AI content applied'),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: _clearAiDraft,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Regenerate',
                onPressed: canGenerate ? _generateAiDraft : null,
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: canGenerate ? _generateAiDraft : null,
                icon: _isGeneratingAiDraft
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(
                  _isGeneratingAiDraft ? 'Generating...' : 'Generate',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryDark,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _clearAiDraft() {
    setState(() {
      _aiDraftScope = null;
      _footerController.clear();
      _emailSubjectController.text = 'Document for your signature';
      _emailMessageController.text =
          'Please review and sign the attached document at your earliest convenience.\n\n'
          'Click the link below to view and sign the document.';
    });
  }

  /// Strips `## SECTION_HEADER` lines from streaming text for display.
  static String _stripSectionHeaders(String text) {
    return text
        .replaceAll(RegExp(r'^##\s+\w+\s*$', multiLine: true), '')
        .trim();
  }

  Future<void> _generateAiDraft() async {
    // Warn if user has manually entered content that would be overwritten,
    // but skip the dialog when regenerating (AI content is already applied)
    final isRegenerating = _aiDraftScope != null;
    final hasExistingContent =
        !isRegenerating &&
        (_footerController.text.trim().isNotEmpty ||
            _emailSubjectController.text.trim().isNotEmpty ||
            _emailMessageController.text.trim().isNotEmpty);
    if (hasExistingContent && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Overwrite existing content?'),
          content: const Text(
            'AI generation will replace your current footer and email content. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _isGeneratingAiDraft = true);

    final accumulated = ValueNotifier<String>('');
    var sheetIsOpen = false;

    // Show streaming bottom sheet
    if (mounted) {
      sheetIsOpen = true;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        builder: (sheetContext) {
          return DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.8,
            expand: false,
            builder: (_, scrollController) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: AppColors.secondaryDark,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Generating AI Draft...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: accumulated,
                        builder: (_, text, __) {
                          final display = _stripSectionHeaders(text);
                          return SingleChildScrollView(
                            controller: scrollController,
                            child: Text(
                              display.isEmpty
                                  ? 'Waiting for response...'
                                  : display,
                              style: TextStyle(
                                fontSize: 11,
                                color: display.isEmpty
                                    ? AppColors.textSecondary
                                    : AppColors.textPrimary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ).whenComplete(() {
        sheetIsOpen = false;
      });
    }

    try {
      final workspaceName = _workspace?.name.trim().isNotEmpty == true
          ? _workspace!.name.trim()
          : _preparedByOrgController.text.trim();

      final lineItemNames = _lineItems
          .where((item) => item.isItem && item.isVisible)
          .map((item) => item.name)
          .toList();

      final persona = context.read<WorkspaceProvider>().aiPersonaContext;

      final draft = await AiService().generateDocumentDraft(
        documentTypeName: _selectedTemplate?.type.displayName ?? 'Document',
        projectName: _selectedProject?.name,
        projectAddress: _selectedProject?.address,
        projectDescription: _selectedProject?.description,
        jobType: _selectedProject?.jobType?.displayName,
        customerName: _selectedCustomer?.displayName,
        customerCompany: _selectedCustomer?.companyName,
        workspaceName: workspaceName.isNotEmpty ? workspaceName : null,
        lineItemNames: lineItemNames.isNotEmpty ? lineItemNames : null,
        persona: persona,
        onStream: (_, __, acc) {
          accumulated.value = acc;
        },
      );

      if (!mounted) return;

      if (sheetIsOpen) Navigator.of(context).pop();

      setState(() {
        _aiDraftScope = draft.scopeContent;
        if (draft.footerContent.isNotEmpty) {
          _footerController.text = draft.footerContent;
        }
        if (draft.emailSubject.isNotEmpty) {
          _emailSubjectController.text = draft.emailSubject;
        }
        if (draft.emailMessage.isNotEmpty) {
          _emailMessageController.text = draft.emailMessage;
        }
      });
    } catch (e) {
      if (!mounted) return;

      if (sheetIsOpen) Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI draft failed: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      accumulated.dispose();
      if (mounted) {
        setState(() => _isGeneratingAiDraft = false);
      }
    }
  }

  Widget _buildFooterSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: StackedField(
          label: 'Footer Content',
          child: TextField(
            controller: _footerController,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              hintText:
                  'e.g., Terms and conditions, company registration info...',
              hintStyle: TextStyle(fontSize: 12),
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
              isDense: true,
            ),
            maxLines: 3,
            onChanged: (_) => setState(() {}),
          ),
        ),
      ),
    );
  }

  Future<void> _loadBudgetItemsForProject(String projectId) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    if (workspaceId == null) return;

    try {
      final budgetService = ServiceLocator.budgetService;
      final items = await budgetService
          .getBudgetItems(projectId, workspaceId: workspaceId)
          .first;

      if (mounted) {
        debugPrint(
          'LOAD BUDGET: Setting budget items for project $projectId: ${items.length} items',
        );
        setState(() {
          _budgetItems = items;
          // If we were navigated here with budget items pre-selected (e.g.
          // from the "Add to Invoice" CO swimlane CTA) and we don't yet have
          // line items, materialize the pre-selected items into editable
          // line rows so the user sees them immediately instead of an
          // empty editor.
          if (_lineItems.isEmpty && _selectedBudgetItemIds.isNotEmpty) {
            final selected = _budgetItems
                .where((b) => _selectedBudgetItemIds.contains(b.id))
                .toList();
            if (selected.isNotEmpty) {
              _lineItems = [
                for (var i = 0; i < selected.length; i++)
                  DocumentLineItem(
                    id: 'pre_${selected[i].id}',
                    type: DocumentLineItemType.item,
                    name: selected[i].name,
                    quantity: 1,
                    unitPrice: _budgetItemAmounts[selected[i].id] ??
                        selected[i].approvedPrice,
                    budgetItemId: selected[i].id,
                    sortOrder: i,
                  ),
              ];
            }
          }
        });
      }
    } catch (e) {
      // Budget items are optional, so just log the error
      debugPrint('Error loading budget items: $e');
    }
  }

  Future<void> _loadAttachedPhotosForProject(String projectId) async {
    if (_attachedPhotoIds.isEmpty) return;

    final workspaceId = context
        .read<AuthProvider>()
        .appUser
        ?.currentWorkspaceId;
    if (workspaceId == null) return;

    try {
      final files = await ServiceLocator.storageService
          .getProjectFiles(workspaceId, projectId)
          .first;
      if (!mounted) return;

      setState(() {
        _attachedPhotos = files
            .where((file) => _attachedPhotoIds.contains(file.id))
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading attached document photos: $e');
    }
  }
}
