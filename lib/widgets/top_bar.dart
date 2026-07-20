import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/chrome_provider.dart';
import '../providers/workspace_provider.dart';

import '../services/service_locator.dart';
import '../theme/theme.dart';
import 'feedback_dialog.dart';
import 'messaging_popup.dart';
import 'notification_panel.dart';
import 'project_form_popup.dart';
import 'task_form_popup.dart';
import 'customer_form_popup.dart';
import 'vendor_form_popup.dart';
import 'asset_form_popup.dart';
import 'vehicle_form_popup.dart';
import 'project_selector_dialog.dart';
import 'smart_search_bar.dart';
import 'ai_chat_popup.dart';
import 'nav_breadcrumb_bar.dart';
import '../models/project.dart';
import '../utils/safe_router_state.dart';

/// A content header that appears at the top of the main content area
class ContentHeader extends StatefulWidget implements PreferredSizeWidget {
  const ContentHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(AppBreakpoints.topBarHeight);

  @override
  State<ContentHeader> createState() => _ContentHeaderState();
}

class _ContentHeaderState extends State<ContentHeader> {
  // Search controller and handler removed in favor of SmartSearchBar

  PopupMenuItem<void> _buildActionItem(_QuickActionData action) {
    return PopupMenuItem<void>(
      onTap: action.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: action.color.withAlpha(25),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(action.icon, color: action.color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    action.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<void>> _buildPopupMenuItems(BuildContext context) {
    final location = safeRouteUri(context).toString();
    final projectTerminology =
        context.read<WorkspaceProvider>().projectTerminology;
    final singularTerm = projectTerminology.endsWith('s') &&
            projectTerminology.length > 1
        ? projectTerminology.substring(0, projectTerminology.length - 1)
        : projectTerminology;

    // Determine context based on current location
    final isProjectList = location == '/projects';
    final isProjectDetail =
        location.contains('/projects/') && !location.endsWith('/new');
    final isCustomerList = location == '/customers';

    // Build context-specific actions (view-specific, shown at top)
    final List<_QuickActionData> contextActions = [];

    // PROJECT LIST SCREEN
    if (isProjectList) {
      contextActions.add(
        _QuickActionData(
          key: 'project',
          icon: Icons.folder_outlined,
          label: singularTerm,
          description: 'Create a new ${singularTerm.toLowerCase()}',
          color: AppColors.info,
          onTap: () => showProjectFormPopup(context),
        ),
      );
    }
    // PROJECT DETAIL SCREEN: Context-aware actions
    else if (isProjectDetail) {
      final projectIdMatch = RegExp(r'/projects/([^/?]+)').firstMatch(location);
      final projectId = projectIdMatch?.group(1);
      final uri = Uri.parse(location);
      final tab = uri.queryParameters['tab'];
      final subtab = uri.queryParameters['subtab'];

      if (projectId != null && projectId != 'new') {
        // Financials Tab
        if (tab == 'financials') {
          switch (subtab) {
            case 'budget':
              contextActions.add(
                _QuickActionData(
                  key: 'editBudget',
                  icon: Icons.grid_view_rounded,
                  label: 'Edit Budget',
                  description: 'Add or edit budget items',
                  color: AppColors.info,
                  onTap: () => context.go(
                    '/projects/$projectId?tab=financials&subtab=budget',
                  ),
                ),
              );
              break;
            case 'bid-requests':
              contextActions.add(
                _QuickActionData(
                  key: 'bidRequest',
                  icon: Icons.request_quote_outlined,
                  label: 'Bid Request',
                  description: 'Create a bid request',
                  color: AppColors.info,
                  onTap: () =>
                      context.go('/documents/create?projectId=$projectId'),
                ),
              );
              break;
            case 'change-orders':
              contextActions.add(
                _QuickActionData(
                  key: 'changeOrder',
                  icon: Icons.edit_note_outlined,
                  label: 'Change Order',
                  description: 'Create a change order',
                  color: AppColors.success,
                  onTap: () =>
                      context.go('/documents/create?projectId=$projectId'),
                ),
              );
              break;
            case 'invoices':
              contextActions.add(
                _QuickActionData(
                  key: 'invoice',
                  icon: Icons.receipt_outlined,
                  label: 'Invoice',
                  description: 'Create a new invoice',
                  color: AppColors.info,
                  onTap: () =>
                      context.go('/documents/create?projectId=$projectId'),
                ),
              );
              break;
            case 'balance':
              contextActions.add(
                _QuickActionData(
                  key: 'issueRefund',
                  icon: Icons.sync_rounded,
                  label: 'Issue Refund',
                  description: 'Track refund or adjustment',
                  color: AppColors.warning,
                  onTap: () => context.go(
                    '/projects/$projectId?tab=financials&subtab=balance',
                  ),
                ),
              );
              break;
            case 'purchase-orders':
              contextActions.add(
                _QuickActionData(
                  key: 'purchaseOrder',
                  icon: Icons.shopping_cart_outlined,
                  label: 'Purchase Order',
                  description: 'Create a purchase order',
                  color: AppColors.warning,
                  onTap: () =>
                      context.go('/documents/create?projectId=$projectId'),
                ),
              );
              break;
            case 'bills':
              contextActions.add(
                _QuickActionData(
                  key: 'bill',
                  icon: Icons.receipt_long_outlined,
                  label: 'Bill',
                  description: 'Record a new bill',
                  color: AppColors.error,
                  onTap: () =>
                      context.go('/documents/create?projectId=$projectId'),
                ),
              );
              break;
            default:
              contextActions.add(
                _QuickActionData(
                  key: 'editBudget',
                  icon: Icons.grid_view_rounded,
                  label: 'Edit Budget',
                  description: 'Manage project budget',
                  color: AppColors.info,
                  onTap: () => context.go(
                    '/projects/$projectId?tab=financials&subtab=budget',
                  ),
                ),
              );
          }
        }
        // Other Project Tabs
        else {
          contextActions.add(
            _QuickActionData(
              key: 'task',
              icon: Icons.add_task_outlined,
              label: 'Task',
              description: 'Add task to this project',
              color: AppColors.info,
              onTap: () => showTaskFormPopup(context, projectId: projectId),
            ),
          );
          contextActions.add(
            _QuickActionData(
              key: 'message',
              icon: Icons.message_outlined,
              label: 'Message',
              description: 'Message project team',
              color: AppColors.success,
              onTap: () => showMessagingPopup(context),
            ),
          );
          contextActions.add(
            _QuickActionData(
              key: 'logTime',
              icon: Icons.timer_outlined,
              label: 'Log Time',
              description: 'Track hours worked',
              color: AppColors.warning,
              onTap: () =>
                  context.go('/projects/$projectId?tab=time-tracking'),
            ),
          );
          contextActions.add(
            _QuickActionData(
              key: 'uploadFile',
              icon: Icons.upload_file_outlined,
              label: 'Upload File',
              description: 'Add files to project',
              color: AppColors.messageAccent,
              onTap: () => context.go('/projects/$projectId?tab=files'),
            ),
          );
        }
      }
    }
    // CUSTOMER LIST SCREEN
    else if (isCustomerList) {
      contextActions.add(
        _QuickActionData(
          key: 'customer',
          icon: Icons.person_add_outlined,
          label: 'Customer',
          description: 'Add a new customer',
          color: AppColors.info,
          onTap: () => showCustomerFormPopup(context),
        ),
      );
    }
    // VENDOR LIST SCREEN
    else if (location == '/vendors') {
      contextActions.add(
        _QuickActionData(
          key: 'vendor',
          icon: Icons.store_outlined,
          label: 'Vendor',
          description: 'Add a new vendor',
          color: AppColors.info,
          onTap: () => showVendorFormPopup(context),
        ),
      );
    }
    // ASSET LIST SCREEN
    else if (location == '/assets' || location == '/equipment') {
      contextActions.add(
        _QuickActionData(
          key: 'asset',
          icon: Icons.inventory_2_outlined,
          label: 'Equipment',
          description: 'Add new equipment',
          color: AppColors.info,
          onTap: () => showAssetFormPopup(context),
        ),
      );
    }
    // VEHICLE LIST SCREEN
    else if (location == '/vehicles') {
      contextActions.add(
        _QuickActionData(
          key: 'vehicle',
          icon: Icons.directions_car_outlined,
          label: 'Vehicle',
          description: 'Add a new vehicle',
          color: AppColors.info,
          onTap: () => showVehicleFormPopup(context),
        ),
      );
    }
    // INVOICE LIST SCREEN
    else if (location == '/invoices') {
      contextActions.add(
        _QuickActionData(
          key: 'invoice',
          icon: Icons.receipt_outlined,
          label: 'Invoice',
          description: 'Create a new invoice',
          color: AppColors.info,
          onTap: () => _showWithProjectSelector(
            context,
            (projectId) =>
                context.go('/documents/create?projectId=$projectId'),
          ),
        ),
      );
    }
    // TEAM SCREEN
    else if (location == '/team') {
      final authProvider = context.read<AuthProvider>();
      final canInviteMembers =
          authProvider.canManageUsers || authProvider.canAccessSettings;
      if (canInviteMembers) {
        contextActions.add(
          _QuickActionData(
            key: 'inviteMember',
            icon: Icons.group_add_outlined,
            label: 'Invite Member',
            description: 'Invite a new team member',
            color: AppColors.info,
            onTap: () {
              final workspaceId =
                  authProvider.appUser?.currentWorkspaceId ?? '';
              context.go('/settings/invite?workspaceId=$workspaceId');
            },
          ),
        );
      }
    }
    // FINANCIALS SCREEN
    else if (location == '/financials') {
      contextActions.add(
        _QuickActionData(
          key: 'bidRequest',
          icon: Icons.request_quote_outlined,
          label: 'Bid Request',
          description: 'Create a bid request',
          color: AppColors.info,
          onTap: () => _showWithProjectSelector(
            context,
            (projectId) =>
                context.go('/documents/create?projectId=$projectId'),
          ),
        ),
      );
      contextActions.add(
        _QuickActionData(
          key: 'changeOrder',
          icon: Icons.edit_note_outlined,
          label: 'Change Order',
          description: 'Create a change order',
          color: AppColors.success,
          onTap: () => _showWithProjectSelector(
            context,
            (projectId) =>
                context.go('/documents/create?projectId=$projectId'),
          ),
        ),
      );
      contextActions.add(
        _QuickActionData(
          key: 'purchaseOrder',
          icon: Icons.shopping_cart_outlined,
          label: 'Purchase Order',
          description: 'Create a purchase order',
          color: AppColors.warning,
          onTap: () => _showWithProjectSelector(
            context,
            (projectId) =>
                context.go('/documents/create?projectId=$projectId'),
          ),
        ),
      );
      contextActions.add(
        _QuickActionData(
          key: 'bill',
          icon: Icons.receipt_long_outlined,
          label: 'Bill',
          description: 'Create a new bill',
          color: AppColors.error,
          onTap: () => _showWithProjectSelector(
            context,
            (projectId) =>
                context.go('/documents/create?projectId=$projectId'),
          ),
        ),
      );
    }
    // TASKS VIEW
    else if (location == '/tasks') {
      contextActions.add(
        _QuickActionData(
          key: 'task',
          icon: Icons.add_task_outlined,
          label: 'Task',
          description: 'Create a new task',
          color: AppColors.info,
          onTap: () => _showWithProjectSelector(
            context,
            (projectId) => showTaskFormPopup(context, projectId: projectId),
          ),
        ),
      );
    }
    // DEFAULT / DASHBOARD: contextActions stays empty

    // Default global actions (always shown below separator)
    final List<_QuickActionData> defaultActions = [
      _QuickActionData(
        key: 'project',
        icon: Icons.folder_outlined,
        label: singularTerm,
        description: 'Create a new ${singularTerm.toLowerCase()}',
        color: AppColors.info,
        onTap: () => showProjectFormPopup(context),
      ),
      _QuickActionData(
        key: 'task',
        icon: Icons.add_task_outlined,
        label: 'Task',
        description: 'Create a new task',
        color: AppColors.success,
        onTap: () => _showWithProjectSelector(
          context,
          (projectId) => showTaskFormPopup(context, projectId: projectId),
        ),
      ),
      _QuickActionData(
        key: 'customer',
        icon: Icons.person_add_outlined,
        label: 'Customer',
        description: 'Add a new customer',
        color: AppColors.warning,
        onTap: () => showCustomerFormPopup(context),
      ),
      _QuickActionData(
        key: 'message',
        icon: Icons.message_outlined,
        label: 'Message',
        description: 'Start a conversation',
        color: AppColors.messageAccent,
        onTap: () => showMessagingPopup(context),
      ),
      _QuickActionData(
        key: 'invoice',
        icon: Icons.receipt_outlined,
        label: 'Invoice',
        description: 'Create a new invoice',
        color: AppColors.error,
        onTap: () => _showWithProjectSelector(
          context,
          (projectId) => context.go('/documents/create?projectId=$projectId'),
        ),
      ),
      _QuickActionData(
        key: 'vendor',
        icon: Icons.store_outlined,
        label: 'Vendor',
        description: 'Add a new vendor',
        color: AppColors.financialAccent,
        onTap: () => showVendorFormPopup(context),
      ),
    ];

    // Filter default actions to remove duplicates already in context section
    final contextKeys = contextActions.map((a) => a.key).toSet();
    final filteredDefaults =
        defaultActions.where((a) => !contextKeys.contains(a.key)).toList();

    return [
      const PopupMenuItem<void>(
        enabled: false,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Text(
            'Add new',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.black,
            ),
          ),
        ),
      ),
      const PopupMenuDivider(),
      ...contextActions.map(_buildActionItem),
      if (contextActions.isNotEmpty && filteredDefaults.isNotEmpty)
        const PopupMenuDivider(),
      ...filteredDefaults.map(_buildActionItem),
    ];
  }

  Future<void> _showWithProjectSelector(
    BuildContext context,
    Function(String) onProjectSelected,
  ) async {
    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';

    if (workspaceId.isEmpty) return;

    final project = await showDialog<Project>(
      context: context,
      builder: (context) => ProjectSelectorDialog(workspaceId: workspaceId),
    );

    if (project != null) {
      onProjectSelected(project.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.appUser;
    final chrome = ChromeColors.of(context);
    final location = safeRouteUri(context).toString();
    final activeProjectId =
        RegExp(r'/projects/([^/?]+)').firstMatch(location)?.group(1);

    return Container(
      height: AppBreakpoints.topBarHeight,
      decoration: BoxDecoration(
        color: chrome.isDark
            ? AppColors.sidebarBg.withAlpha(242) // slight translucency
            : AppColors.surface.withAlpha(242),
        border: Border(
          bottom: BorderSide(
            color: chrome.isDark
                ? AppColors.glassBorder
                : const Color(0x0A000000), // 4 % black — barely there
            width: 0.5,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        child: LayoutBuilder(
          builder: (context, c) {
            // Adaptive breadcrumb: full trail on roomy desktops, just buttons
            // on narrower content widths so we don't crowd out the search box.
            final showFullTrail = c.maxWidth >= 1100;
            final crumbWidth = showFullTrail ? 360.0 : 132.0;
            return Row(
              children: [
                // Back / Forward / Home + (optional) breadcrumb trail
                SizedBox(
                  width: crumbWidth,
                  child: NavBreadcrumbBar(compact: !showFullTrail),
                ),
                const SizedBox(width: 12),
                // Search Bar
                Expanded(
                  flex: 2,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: currentUser != null
                        ? SmartSearchBar(
                            workspaceId: currentUser.currentWorkspaceId,
                            projectId: activeProjectId == 'new'
                                ? null
                                : activeProjectId,
                            expanded: true,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                const Spacer(),
            IconButton(
              icon: const Icon(Icons.feedback_outlined),
              tooltip: 'Send feedback',
              iconSize: 21,
              style: IconButton.styleFrom(
                foregroundColor: chrome.text,
              ),
              onPressed: () => showFeedbackDialog(context),
            ),
            const SizedBox(width: 2),
            IconButton(
              icon: const Icon(Icons.auto_awesome_outlined),
              tooltip: 'AI Assistant',
              iconSize: 21,
              style: IconButton.styleFrom(
                foregroundColor: AppColors.secondaryDark,
              ),
              onPressed: () => showAiChatPopup(
                context,
                projectId: activeProjectId == 'new' ? null : activeProjectId,
              ),
            ),
            const SizedBox(width: 2),
            // Dark/Light mode toggle
            Builder(builder: (context) {
              final chromeProvider = context.watch<ChromeProvider>();
              return IconButton(
                icon: Icon(
                  chromeProvider.isDarkChrome
                      ? Icons.light_mode
                      : Icons.dark_mode,
                ),
                tooltip: chromeProvider.isDarkChrome
                    ? 'Switch to light mode'
                    : 'Switch to dark mode',
                iconSize: 21,
                style: IconButton.styleFrom(
                  foregroundColor: chrome.textActive,
                ),
                onPressed: () {
                  chromeProvider.setDarkChrome(!chromeProvider.isDarkChrome);
                },
              );
            }),
            const SizedBox(width: 2),
            // Time/Clock Icon
            IconButton(
              icon: const Icon(Icons.access_time_outlined),
              tooltip: 'Time',
              iconSize: 21,
              style: IconButton.styleFrom(
                foregroundColor: chrome.text,
              ),
              onPressed: () {
                context.go('/time-tracking');
              },
            ),
            const SizedBox(width: 2),
            // Inbox Icon
            if (currentUser != null)
              StreamBuilder<int>(
                stream: ServiceLocator.messageService.getTotalUnreadCount(
                  workspaceId: currentUser.currentWorkspaceId,
                  userId: currentUser.id,
                ),
                builder: (context, snapshot) {
                  final unreadCount = snapshot.data ?? 0;
                  return IconButton(
                    icon: Badge(
                      label: Text('$unreadCount'),
                      isLabelVisible: unreadCount > 0,
                      backgroundColor: AppColors.error,
                      textColor: AppColors.textOnPrimary,
                      child: const Icon(Icons.chat_bubble_outline),
                    ),
                    iconSize: 21,
                    style: IconButton.styleFrom(
                      foregroundColor: chrome.text,
                    ),
                    tooltip: 'Inbox',
                    onPressed: () => showMessagingPopup(context),
                  );
                },
              ),
            const SizedBox(width: 2),
            // Notification Icon
            if (currentUser != null)
              StreamBuilder<int>(
                stream: ServiceLocator.notificationService.getUnreadCount(
                  userId: currentUser.id,
                  workspaceId: currentUser.currentWorkspaceId,
                ),
                builder: (context, snapshot) {
                  final unreadCount = snapshot.data ?? 0;
                  return IconButton(
                    icon: Badge(
                      label: Text('$unreadCount'),
                      isLabelVisible: unreadCount > 0,
                      backgroundColor: AppColors.error,
                      textColor: AppColors.textOnPrimary,
                      child: const Icon(Icons.notifications_outlined),
                    ),
                    iconSize: 21,
                    style: IconButton.styleFrom(
                      foregroundColor: chrome.text,
                    ),
                    tooltip: 'Notifications',
                    onPressed: () => showNotificationPanel(context),
                  );
                },
              ),
            const SizedBox(width: AppSpacing.sm),
            // Quick Add Button (+ icon)
            PopupMenuButton<void>(
              offset: const Offset(0, 52),
              itemBuilder: (context) => _buildPopupMenuItems(context),
              child: Container(
                decoration: BoxDecoration(
                  color: chrome.isDark ? AppColors.primaryLight : AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: AppColors.textOnPrimary,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'New',
                      style: TextStyle(
                        color: AppColors.textOnPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md), // Right padding
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QuickActionData {
  final String key;
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  _QuickActionData({
    required this.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });
}
