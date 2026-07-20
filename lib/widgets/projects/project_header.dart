import 'dart:async';
import 'dart:math' show max;
import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/customer.dart';
import '../../models/job_type.dart';
import '../../models/price_type.dart';
import '../../models/project.dart';
import '../../models/project_status_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/address_formatter.dart';
import '../../utils/project_terminology.dart';
import '../../widgets/price_type_badge.dart';
import '../../widgets/project_form_popup.dart';
import '../../widgets/projects/save_as_template_dialog.dart';
import '../ai/ai_project_setup_wizard.dart';
import 'compact_progress_bar.dart';
import 'project_picker_tile.dart';

class ProjectHeader extends StatefulWidget {
  final Project project;

  /// When provided, the image + title area becomes clickable and shows a
  /// dropdown to switch to another project.
  final List<Project>? switchableProjects;
  final void Function(Project)? onSwitchProject;

  /// When provided, the progress bar becomes clickable and navigates to tasks.
  final VoidCallback? onTasksTap;

  const ProjectHeader({
    super.key,
    required this.project,
    this.switchableProjects,
    this.onSwitchProject,
    this.onTasksTap,
  });

  @override
  State<ProjectHeader> createState() => _ProjectHeaderState();
}

class _ProjectHeaderState extends State<ProjectHeader> {
  bool _isHovering = false;
  final GlobalKey _titleKey = GlobalKey();
  StreamSubscription<Customer?>? _customerSub;
  bool _customerLoaded = false;
  String? _liveCustomerName;
  String? _liveBusinessPhone;
  String? _liveBusinessEmail;
  ProjectStatus? _pendingStatusFilter;
  JobType? _pendingJobTypeFilter;
  PriceType? _pendingPriceTypeFilter;

  @override
  void initState() {
    super.initState();
    _subscribeToCustomer();
  }

  @override
  void didUpdateWidget(ProjectHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.clientId != widget.project.clientId) {
      _customerSub?.cancel();
      _customerLoaded = false;
      _liveCustomerName = null;
      _liveBusinessPhone = null;
      _liveBusinessEmail = null;
      _subscribeToCustomer();
    }
  }

  void _subscribeToCustomer() {
    final clientId = widget.project.clientId;
    if (clientId == null) return;
    _customerSub = ServiceLocator.customerService
        .watchCustomer(clientId)
        .listen((customer) {
      if (mounted && customer != null) {
        setState(() {
          _customerLoaded = true;
          _liveCustomerName = customer.companyName;
          _liveBusinessPhone = customer.businessPhone;
          _liveBusinessEmail = customer.businessEmail;
        });
      }
    });
  }

  @override
  void dispose() {
    _customerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final address = AddressFormatter.condense(widget.project.address);
    final hasAddress = address.isNotEmpty;
    final serial = widget.project.serialNumber?.trim();
    final hasSerial = serial != null && serial.isNotEmpty;
    final customerName = _customerLoaded ? _liveCustomerName : widget.project.customerName;
    final businessPhone = _liveBusinessPhone;
    final businessEmail = _liveBusinessEmail;

    return LayoutBuilder(
      builder: (context, constraints) {
        final chrome = ChromeColors.of(context);
        final isCompact = constraints.maxWidth < AppBreakpoints.tablet;
        // Account for the clickable header's horizontal padding (6px)
        // when switchable projects are available.
        final leadingPadding = widget.switchableProjects != null ? 6.0 : 0.0;

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 12 : 20,
            vertical: isCompact ? 10 : 14,
          ),
          color: chrome.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Image + Title/Badges + Actions
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _buildClickableHeader(context, isCompact),
                  ),
                  if (!isCompact) ...[
                    const SizedBox(width: 8),
                    MouseRegion(
                      cursor: widget.onTasksTap != null
                          ? SystemMouseCursors.click
                          : MouseCursor.defer,
                      child: GestureDetector(
                        onTap: widget.onTasksTap,
                        child: SizedBox(
                          width: 120,
                          child: CompactProgressBar(project: widget.project),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildActions(context, isCompact),
                  ],
                ],
              ),

              // Row 1b (compact only): Status + Serial + PO + Actions
              if (isCompact) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    _StatusBadge(status: widget.project.status),
                    if (hasSerial) ...[
                      const SizedBox(width: 8),
                      _buildSerialBadge(context, serial),
                    ],
                    if (widget.project.purchaseOrderNumber?.trim().isNotEmpty == true) ...[
                      const SizedBox(width: 8),
                      _buildPOBadge(context, widget.project.purchaseOrderNumber!.trim()),
                    ],
                    const Spacer(),
                    _buildActions(context, isCompact),
                  ],
                ),
              ],

              // Row 2: Address + Customer + Business contacts
              if (hasAddress ||
                  (customerName != null && customerName!.isNotEmpty) ||
                  businessPhone != null ||
                  businessEmail != null) ...[
                const SizedBox(height: 3),
                Padding(
                  padding: EdgeInsets.only(left: isCompact ? 0 : leadingPadding),
                  child: isCompact
                      // Compact: customer above address
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((customerName != null && customerName!.isNotEmpty) ||
                                businessPhone != null ||
                                businessEmail != null) ...[
                              Row(
                                children: [
                                  if (customerName != null && customerName!.isNotEmpty)
                                    Flexible(
                                      child: GestureDetector(
                                        onTap: widget.project.clientId != null
                                            ? () => context.go(
                                                  '/customers/${widget.project.clientId}',
                                                )
                                            : null,
                                        child: MouseRegion(
                                          cursor: widget.project.clientId != null
                                              ? SystemMouseCursors.click
                                              : MouseCursor.defer,
                                          child: Text(
                                            customerName!,
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: chrome.isDark ? AppColors.primaryLight : Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (businessPhone != null) ...[
                                    const SizedBox(width: 8),
                                    _buildBusinessContactIcon(Icons.phone, businessPhone, 'tel', chrome),
                                  ],
                                  if (businessEmail != null) ...[
                                    const SizedBox(width: 6),
                                    _buildBusinessContactIcon(Icons.email_outlined, businessEmail, 'mailto', chrome),
                                  ],
                                ],
                              ),
                            ],
                            if (hasAddress) ...[
                              if (customerName != null &&
                                  customerName!.isNotEmpty)
                                const SizedBox(height: 2),
                              GestureDetector(
                                onTap: () {
                                  final encoded = Uri.encodeComponent(
                                    widget.project.address,
                                  );
                                  launchUrl(
                                    Uri.parse(
                                      'https://www.google.com/maps/search/?api=1&query=$encoded',
                                    ),
                                    mode: LaunchMode.externalApplication,
                                  );
                                },
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: Text(
                                    address,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: chrome.text,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        )
                      // Desktop: address · customer on one line
                      : Row(
                          children: [
                            if (hasAddress) ...[
                              Flexible(
                                child: GestureDetector(
                                  onTap: () {
                                    final encoded = Uri.encodeComponent(
                                      widget.project.address,
                                    );
                                    launchUrl(
                                      Uri.parse(
                                        'https://www.google.com/maps/search/?api=1&query=$encoded',
                                      ),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: Text(
                                      address,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: chrome.text,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (hasAddress &&
                                ((customerName != null && customerName!.isNotEmpty) ||
                                    businessPhone != null ||
                                    businessEmail != null)) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                                child: Text(
                                  '·',
                                  style: TextStyle(
                                    color: chrome.divider,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                            if ((customerName != null && customerName!.isNotEmpty) ||
                                businessPhone != null ||
                                businessEmail != null) ...[
                              if (customerName != null && customerName!.isNotEmpty)
                                GestureDetector(
                                  onTap: widget.project.clientId != null
                                      ? () => context.go(
                                            '/customers/${widget.project.clientId}',
                                          )
                                      : null,
                                  child: MouseRegion(
                                    cursor: widget.project.clientId != null
                                        ? SystemMouseCursors.click
                                        : MouseCursor.defer,
                                    child: Text(
                                      customerName!,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: chrome.isDark ? AppColors.primaryLight : Theme.of(context).colorScheme.primary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              if (businessPhone != null) ...[
                                const SizedBox(width: 8),
                                _buildBusinessContactIcon(Icons.phone, businessPhone, 'tel', chrome),
                              ],
                              if (businessEmail != null) ...[
                                const SizedBox(width: 6),
                                _buildBusinessContactIcon(Icons.email_outlined, businessEmail, 'mailto', chrome),
                              ],
                            ],
                          ],
                        ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildClickableHeader(BuildContext context, bool isCompact) {
    final chrome = ChromeColors.of(context);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: isCompact
              ? _buildCompactTitleBlock(context)
              : _buildDesktopTitleBlock(context),
        ),
        if (widget.switchableProjects != null) ...[
          const SizedBox(width: 4),
          AnimatedOpacity(
            opacity: _isHovering ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: chrome.text,
            ),
          ),
        ],
      ],
    );

    if (widget.switchableProjects == null || widget.onSwitchProject == null) {
      return content;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: _showProjectMenu,
        child: AnimatedContainer(
          key: _titleKey,
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: _isHovering
                ? chrome.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _wrapFilterTap({
    required Widget child,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    if (widget.switchableProjects == null || widget.onSwitchProject == null) {
      return child;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Tooltip(message: tooltip, child: child),
      ),
    );
  }

  void _openFilteredDropdown({
    ProjectStatus? status,
    JobType? jobType,
    PriceType? priceType,
  }) {
    setState(() {
      _pendingStatusFilter = status;
      _pendingJobTypeFilter = jobType;
      _pendingPriceTypeFilter = priceType;
    });
    _showProjectMenu();
  }

  void _showProjectMenu() async {
    final titleBox = _titleKey.currentContext?.findRenderObject() as RenderBox?;
    if (titleBox == null) return;

    final offset = titleBox.localToGlobal(Offset.zero);
    final size = titleBox.size;
    final dropdownWidth = max(280.0, size.width);

    final initialStatus = _pendingStatusFilter;
    final initialJobType = _pendingJobTypeFilter;
    final initialPriceType = _pendingPriceTypeFilter;
    _pendingStatusFilter = null;
    _pendingJobTypeFilter = null;
    _pendingPriceTypeFilter = null;

    final selected = await showGeneralDialog<Project>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, _, __) {
        return Stack(
          children: [
            Positioned(
              left: offset.dx,
              top: offset.dy + size.height + 4,
              width: dropdownWidth,
              child: _ProjectDropdown(
                projects: widget.switchableProjects!,
                currentProjectId: widget.project.id,
                initialStatusFilter: initialStatus,
                initialJobTypeFilter: initialJobType,
                initialPriceTypeFilter: initialPriceType,
              ),
            ),
          ],
        );
      },
    );

    if (selected != null && mounted) {
      widget.onSwitchProject!(selected);
    }
  }

  Widget _buildCompactTitleBlock(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return Tooltip(
      message: widget.project.name,
      child: Text(
        widget.project.name,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: chrome.textActive,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildSerialBadge(BuildContext context, String serial) {
    final chrome = ChromeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: chrome.hover,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        '#$serial',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: chrome.text,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPOBadge(BuildContext context, String po) {
    final chrome = ChromeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: chrome.hover,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        'PO $po',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: chrome.text,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildDesktopTitleBlock(BuildContext context) {
    final chrome = ChromeColors.of(context);
    final serial = widget.project.serialNumber?.trim();
    final hasSerial = serial != null && serial.isNotEmpty;
    final po = widget.project.purchaseOrderNumber?.trim();
    final hasPO = po != null && po.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: widget.project.name,
            child: Text(
              widget.project.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: chrome.textActive,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasSerial) ...[
                    _buildSerialBadge(context, serial),
                    const SizedBox(width: 8),
                  ],
                  if (hasPO) ...[
                    _buildPOBadge(context, po),
                    const SizedBox(width: 8),
                  ],
                  _wrapFilterTap(
                    tooltip: 'Filter by ${widget.project.status.displayName}',
                    onTap: () => _openFilteredDropdown(
                      status: widget.project.status,
                    ),
                    child: _StatusBadge(status: widget.project.status),
                  ),
                  const SizedBox(width: 8),
                  if (widget.project.jobType != null) ...[
                    _wrapFilterTap(
                      tooltip:
                          'Filter by ${widget.project.jobType!.displayName}',
                      onTap: () => _openFilteredDropdown(
                        jobType: widget.project.jobType,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          border: Border.all(
                            color: widget.project.jobType!.color.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.project.jobType!.icon,
                              size: 14,
                              color: widget.project.jobType!.color,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              widget.project.jobType!.displayName,
                              style: TextStyle(
                                color: widget.project.jobType!.color,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _wrapFilterTap(
                    tooltip:
                        'Filter by ${widget.project.priceType.displayName}',
                    onTap: () => _openFilteredDropdown(
                      priceType: widget.project.priceType,
                    ),
                    child: PriceTypeBadge(
                      priceType: widget.project.priceType,
                      compact: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBusinessContactIcon(
    IconData icon,
    String value,
    String scheme,
    ChromeColors chrome,
  ) {
    return GestureDetector(
      onTap: () => launchUrl(Uri(scheme: scheme, path: value)),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Icon(icon, size: 14, color: chrome.text),
      ),
    );
  }

  Widget _buildActions(BuildContext context, bool isCompact) {
    final chrome = ChromeColors.of(context);
    final authProvider = context.watch<AuthProvider>();
    final singular = singularProjectTerminology(context.watch<WorkspaceProvider>().projectTerminology);
    final iconSize = isCompact ? 19.0 : 20.0;
    final density = isCompact ? VisualDensity.standard : VisualDensity.compact;
    final constraints = isCompact
        ? const BoxConstraints(minWidth: 36, minHeight: 36)
        : const BoxConstraints();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.auto_awesome, size: iconSize, color: AppColors.secondaryDark),
          onPressed: () {
            showAiProjectSetupWizard(
              context,
              project: widget.project,
              workspaceId: widget.project.workspaceId,
            );
          },
          tooltip: 'AI Setup Wizard',
          visualDensity: density,
          constraints: constraints,
        ),
        if (authProvider.canEditProjects)
          IconButton(
            icon: Icon(Icons.edit, size: iconSize, color: chrome.text),
            onPressed: () {
              showProjectFormPopup(context, projectId: widget.project.id);
            },
            tooltip: 'Edit $singular',
            visualDensity: density,
            constraints: constraints,
          ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, size: iconSize, color: chrome.text),
          tooltip: 'More actions',
          padding: isCompact ? const EdgeInsets.all(2) : EdgeInsets.zero,
          onSelected: (value) => _onMenuAction(context, value),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'save_template',
              child: Row(
                children: [
                  Icon(Icons.bookmark_add, size: 18),
                  SizedBox(width: 12),
                  Text('Save as Template'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'duplicate',
              child: Row(
                children: [
                  const Icon(Icons.copy, size: 18),
                  const SizedBox(width: 12),
                  Text('Duplicate $singular'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            if (widget.project.status != ProjectStatus.onHold)
              const PopupMenuItem(
                value: 'on_hold',
                child: Row(
                  children: [
                    Icon(Icons.pause_circle_outline, size: 18),
                    SizedBox(width: 12),
                    Text('Put On Hold'),
                  ],
                ),
              ),
            if (widget.project.status != ProjectStatus.complete)
              PopupMenuItem(
                value: 'close',
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 18),
                    const SizedBox(width: 12),
                    Text('Close $singular'),
                  ],
                ),
              ),
            if (widget.project.status != ProjectStatus.canceled)
              PopupMenuItem(
                value: 'cancel',
                child: Row(
                  children: [
                    const Icon(Icons.block, size: 18),
                    const SizedBox(width: 12),
                    Text('Cancel $singular'),
                  ],
                ),
              ),
            if (authProvider.canDeleteProjects) ...[
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Text('Delete $singular', style: TextStyle(color: Colors.red.shade700)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _onMenuAction(BuildContext context, String value) async {
    final project = widget.project;
    final projectService = ServiceLocator.projectService;
    final singular = singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology);

    switch (value) {
      case 'save_template':
        showSaveProjectAsTemplateDialog(
          context,
          projectId: project.id,
          workspaceId: project.workspaceId,
        );
      case 'duplicate':
        try {
          final newProject = await projectService.duplicateProject(project.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$singular duplicated')),
            );
            context.go('/projects/${newProject.id}');
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to duplicate ${singular.toLowerCase()}: $e')),
            );
          }
        }
      case 'on_hold':
        await _confirmStatusChange(
          context,
          title: 'Put On Hold',
          message: 'Are you sure you want to put "${project.name}" on hold?',
          action: () => projectService.updateProject(
            projectId: project.id,
            status: ProjectStatus.onHold,
          ),
          successMessage: '$singular put on hold',
        );
      case 'close':
        await _confirmStatusChange(
          context,
          title: 'Close $singular',
          message: 'Are you sure you want to close "${project.name}"?',
          action: () => projectService.updateProject(
            projectId: project.id,
            status: ProjectStatus.complete,
          ),
          successMessage: '$singular closed',
        );
      case 'cancel':
        await _confirmStatusChange(
          context,
          title: 'Cancel $singular',
          message: 'Are you sure you want to cancel "${project.name}"?',
          action: () => projectService.updateProject(
            projectId: project.id,
            status: ProjectStatus.canceled,
          ),
          successMessage: '$singular canceled',
        );
      case 'delete':
        await _confirmStatusChange(
          context,
          title: 'Delete $singular',
          message:
              'Are you sure you want to permanently delete "${project.name}"? This action cannot be undone.',
          action: () => projectService.deleteProject(project.id),
          successMessage: '$singular deleted',
          isDestructive: true,
          navigateAway: true,
        );
    }
  }

  Future<void> _confirmStatusChange(
    BuildContext context, {
    required String title,
    required String message,
    required Future<void> Function() action,
    required String successMessage,
    bool isDestructive = false,
    bool navigateAway = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: isDestructive
                ? TextButton.styleFrom(foregroundColor: Colors.red)
                : null,
            child: Text(title),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
        if (navigateAway) {
          context.go('/projects');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

class _ProjectDropdown extends StatefulWidget {
  final List<Project> projects;
  final String currentProjectId;
  final ProjectStatus? initialStatusFilter;
  final JobType? initialJobTypeFilter;
  final PriceType? initialPriceTypeFilter;

  const _ProjectDropdown({
    required this.projects,
    required this.currentProjectId,
    this.initialStatusFilter,
    this.initialJobTypeFilter,
    this.initialPriceTypeFilter,
  });

  @override
  State<_ProjectDropdown> createState() => _ProjectDropdownState();
}

class _ProjectDropdownState extends State<_ProjectDropdown> {
  ProjectStatus? _statusFilter;
  JobType? _jobTypeFilter;
  PriceType? _priceTypeFilter;

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.initialStatusFilter;
    _jobTypeFilter = widget.initialJobTypeFilter;
    _priceTypeFilter = widget.initialPriceTypeFilter;
  }

  bool get _hasFilter =>
      _statusFilter != null ||
      _jobTypeFilter != null ||
      _priceTypeFilter != null;

  String? get _filterLabel {
    if (_statusFilter != null) return _statusFilter!.displayName;
    if (_jobTypeFilter != null) return _jobTypeFilter!.displayName;
    if (_priceTypeFilter != null) return _priceTypeFilter!.displayName;
    return null;
  }

  Color? get _filterColor {
    if (_statusFilter != null) return ProjectStatusTheme.colorDark(_statusFilter!);
    if (_jobTypeFilter != null) return _jobTypeFilter!.color;
    return null;
  }

  List<Project> get _filtered {
    return widget.projects.where((p) {
      if (_statusFilter != null && p.status != _statusFilter) return false;
      if (_jobTypeFilter != null && p.jobType != _jobTypeFilter) return false;
      if (_priceTypeFilter != null && p.priceType != _priceTypeFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  void _clearFilter() {
    setState(() {
      _statusFilter = null;
      _jobTypeFilter = null;
      _priceTypeFilter = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    final filtered = _filtered;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasFilter)
                _FilterHeader(
                  label: _filterLabel!,
                  color: _filterColor,
                  count: filtered.length,
                  onClear: _clearFilter,
                ),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.xl,
                        ),
                        child: Text(
                          'No matching projects',
                          style: TextStyle(color: chrome.text),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Scrollbar(
                        thumbVisibility: true,
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final p = filtered[i];
                            final isCurrent = p.id == widget.currentProjectId;
                            return ProjectPickerTile(
                              project: p,
                              isCurrent: isCurrent,
                              onTap: () => Navigator.of(ctx).pop(p),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterHeader extends StatelessWidget {
  final String label;
  final Color? color;
  final int count;
  final VoidCallback onClear;

  const _FilterHeader({
    required this.label,
    required this.color,
    required this.count,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: chrome.hover,
        border: Border(
          bottom: BorderSide(color: chrome.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (color != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              '$label  ·  $count',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: chrome.textActive,
                    fontWeight: FontWeight.w600,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Show all'),
          ),
        ],
      ),
    );
  }
}

/// Small colored badge for project status
class _StatusBadge extends StatelessWidget {
  final ProjectStatus status;

  const _StatusBadge({required this.status});

  Color _color() {
    return ProjectStatusTheme.colorDark(status);
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: color),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          color: AppColors.textOnDark,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}
