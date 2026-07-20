import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'config/beta_signup_config.dart';
import 'models/file_folder.dart';
import 'models/generated_document.dart';

import 'services/service_locator.dart';
import 'providers/auth_provider.dart' as app_auth;
import 'providers/workspace_provider.dart';
import 'router_refresh_stream.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/password_reset_screen.dart';
import 'screens/auth/email_verification_pending_screen.dart';
import 'screens/auth/email_verified_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/home/home_screen.dart';

import 'screens/projects/projects_table_screen.dart';
import 'screens/projects/project_form_screen.dart';
import 'screens/projects/project_detail_screen.dart';
import 'screens/projects/project_schedule_screen.dart';
import 'screens/projects/project_dashboard_screen.dart';
import 'screens/tasks/task_form_screen.dart';
import 'screens/tasks/all_tasks_screen.dart';
import 'screens/work_orders/all_work_orders_screen.dart';
import 'screens/change_orders/all_change_orders_screen.dart';
import 'models/document_type.dart';
import 'screens/subcontracts/all_subcontracts_screen.dart';
import 'screens/settings/user_management_screen.dart';
import 'screens/projects/project_costing_screen.dart';
import 'screens/projects/budget_list_screen.dart';
import 'screens/customers/customer_list_screen.dart';
import 'screens/opportunities/opportunities_screen.dart';
import 'screens/opportunities/opportunity_form_screen.dart';
import 'screens/opportunities/opportunity_detail_screen.dart';
import 'screens/customers/customer_form_screen.dart';
import 'screens/customers/customer_detail_screen.dart';
import 'screens/vendors/vendor_list_screen.dart';
import 'screens/vendors/vendor_form_screen.dart';
import 'screens/vendors/vendor_detail_screen.dart';
import 'screens/profile/profile_view_screen.dart';
import 'screens/plans/plans_list_screen.dart';
import 'screens/plans/plan_upload_screen.dart';
import 'screens/plans/plan_detail_screen.dart';
import 'screens/plans/floorplan_editor_screen.dart';
import 'screens/plans/scan/room_scan_screen.dart';
import 'screens/projects/budget_view_screen.dart';
import 'screens/time_tracking/admin_timesheet_dashboard.dart';
import 'screens/time_tracking/clock_in_out_screen.dart';
import 'screens/time_tracking/daily_timesheet_screen.dart';
import 'screens/time_tracking/time_approval_screen.dart';
import 'screens/time_tracking/weekly_timesheet_screen.dart';
import 'screens/time_tracking/employee_time_table_screen.dart';
import 'screens/reporting/reporting_dashboard_screen.dart';
import 'screens/financials/financials_screen.dart';
import 'screens/invitations/invitation_acceptance_screen.dart';
import 'screens/invitations/member_welcome_screen.dart';
import 'screens/invitations/user_invitation_screen.dart';
import 'screens/settings/workspace_settings_screen.dart';
import 'screens/settings/workspace_audit_log_screen.dart';
import 'screens/settings/roles_and_permissions_screen.dart';
import 'screens/settings/workspace_settings_profiles_screen.dart';
import 'screens/settings/automation_rules_screen.dart';
import 'screens/settings/api_keys_screen.dart';
import 'screens/settings/asset_category_management_screen.dart';
import 'screens/settings/customer_type_management_screen.dart';
import 'screens/settings/file_tag_manager_screen.dart';
import 'screens/settings/custom_fields_screen.dart';
import 'screens/settings/vendor_type_management_screen.dart';
import 'screens/settings/document_numbering_settings_screen.dart';
import 'screens/messages/messages_list_screen.dart';
import 'screens/messages/new_conversation_screen.dart';
import 'screens/messages/saved_messages_screen.dart';
import 'screens/assets/asset_list_screen.dart';
import 'screens/assets/asset_detail_screen.dart';
import 'screens/assets/asset_form_screen.dart';
import 'screens/inventory/inventory_screen.dart';
import 'screens/vehicles/vehicle_list_screen.dart';
import 'screens/vehicles/vehicle_detail_screen.dart';
import 'screens/vehicles/vehicle_form_screen.dart';
import 'screens/common/qr_scanner_screen.dart';
import 'screens/team/team_screen.dart';
import 'widgets/adaptive_navigation.dart';
import 'screens/ai_assistant/ai_assistant_screen.dart';
import 'screens/ai/ai_plan_review_screen.dart';
import 'screens/client_portal/portal_login_screen.dart';
import 'screens/client_portal/portal_dashboard_screen.dart';
import 'screens/client_portal/portal_project_screen.dart';
import 'screens/client_portal/portal_invoice_list_screen.dart';
import 'screens/client_portal/portal_document_detail_screen.dart';
import 'screens/client_portal/portal_invoice_detail_screen.dart';
import 'screens/client_portal/portal_preview_scope.dart';
import 'screens/catalog/catalog_screen.dart';
import 'screens/catalog/catalog_item_form_screen.dart';
import 'screens/forms/form_builder_screen.dart';
import 'screens/forms/form_detail_screen.dart';
import 'screens/forms/form_submissions_screen.dart';
import 'screens/forms/public_form_screen.dart';
import 'screens/field_forms/field_form_template_list_screen.dart';
import 'screens/field_forms/field_form_template_editor_screen.dart';
import 'screens/field_forms/field_form_fill_screen.dart';
import 'screens/field_forms/field_form_submission_detail_screen.dart';
import 'screens/field_forms/public_field_form_sign_screen.dart';
import 'screens/documents/document_list_screen.dart';
import 'screens/bid_packages/bid_package_screen.dart';
import 'screens/bid_packages/create_bid_package_screen.dart';
import 'screens/documents/document_detail_screen.dart';
import 'screens/documents/public_document_sign_screen.dart';
import 'screens/documents/template_editor_screen.dart';
import 'screens/documents/create_document_screen.dart';
import 'screens/files/workspace_files_screen.dart';
import 'screens/templates/templates_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/help/help_about_screen.dart';
import 'screens/calendar/calendar_screen.dart';
import 'screens/apps/get_the_app_screen.dart';
import 'screens/vendor_portal/vendor_portal_login_screen.dart';
import 'screens/vendor_portal/vendor_portal_dashboard_screen.dart';
import 'screens/vendor_portal/vendor_portal_bids_screen.dart';
import 'screens/vendor_portal/vendor_portal_work_orders_screen.dart';
import 'screens/vendor_portal/vendor_portal_selections_screen.dart';
import 'screens/vendor_portal/vendor_portal_bills_screen.dart';
import 'screens/projects/pay_applications/pay_application_editor_screen.dart';
import 'screens/projects/pay_applications/pay_applications_list_screen.dart';
import 'screens/projects/holdback/holdback_release_editor_screen.dart';
import 'screens/projects/holdback/holdback_releases_list_screen.dart';


/// Wraps a routed screen in a [SelectionArea] so its text is highlightable /
/// copyable (primarily a web affordance). Applied at the route boundary so a
/// single place governs which screens get selectable text. Deliberately NOT
/// applied to the AR room-scan and fullscreen floorplan-editor routes, whose
/// drag/canvas gestures take precedence over text selection.
Widget _selectable(Widget child) => SelectionArea(child: child);

class AppRouter {
  static GoRouter createRouter() {
    final authService = ServiceLocator.authService;

    // Legacy hash-route deep links (/#/vendors, /#/invite/<token>) predate
    // the path URL strategy. The browser reports path '/' for them, which
    // makes GoRouter fall back to initialLocation — so resolve it from the
    // fragment here. Auth-token fragments (#access_token=…) belong to the
    // magic-link consumer in main.dart, not the router.
    var initialLocation = '/login';
    if (kIsWeb) {
      final legacyFragment = Uri.base.fragment;
      if (legacyFragment.startsWith('/') &&
          !legacyFragment.contains('access_token=')) {
        initialLocation = legacyFragment;
      }
    }

    return GoRouter(
      initialLocation: initialLocation,
      refreshListenable: GoRouterRefreshStream(authService.userChanges),
      errorBuilder: (context, state) {
        final location = state.uri.toString();
        final isAuthLinkError =
            location.startsWith('error=') ||
            location.contains('otp_expired') ||
            location.contains('error_code=otp_expired');
        if (isAuthLinkError) {
          return const LoginScreen();
        }

        return AdaptiveNavigation(
          selectedIndex: -1,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_off, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Page not found',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  location,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => GoRouter.of(context).go('/'),
                  child: const Text('Go to Dashboard'),
                ),
              ],
            ),
          ),
        );
      },
      redirect: (context, state) {
        final bool isLoggedIn = authService.currentUser != null;
        final isAuthRoute =
            state.matchedLocation == '/login' ||
            state.matchedLocation == '/signup' ||
            state.matchedLocation == '/password-reset';
        final isVerificationRoute =
            state.matchedLocation == '/verify-email-pending' ||
            state.matchedLocation == '/verify-email';
        final isOnboardingRoute = state.matchedLocation == '/onboarding';
        final isPortalRoute = state.matchedLocation.startsWith('/portal');
        final isVendorPortalRoute =
            state.matchedLocation.startsWith('/vendor-portal');
        final isPublicFormRoute = state.matchedLocation.startsWith('/f/');
        final isDocumentSignRoute = state.matchedLocation.startsWith('/sign/');
        // /apps is the "get the mobile app" page — public on purpose so
        // marketing emails and social posts can link to it without
        // forcing a signup first.
        final isAppsRoute = state.matchedLocation == '/apps';
        final isPublicRoute =
            isAuthRoute ||
            isVerificationRoute ||
            isOnboardingRoute ||
            state.matchedLocation.startsWith('/invite/') ||
            isPortalRoute ||
            isVendorPortalRoute ||
            isPublicFormRoute ||
            isDocumentSignRoute ||
            isAppsRoute;

        // If user is not logged in and trying to access protected route.
        // Carry the original location so the deep link survives the
        // async session restore (the logged-in auth-route branch below
        // honors ?from=).
        if (!isLoggedIn && !isPublicRoute) {
          final fromLocation = state.uri.toString();
          if (fromLocation != '/' && fromLocation.isNotEmpty) {
            return '/login?from=${Uri.encodeComponent(fromLocation)}';
          }
          return '/login';
        }

        // If user is logged in and trying to access auth routes, redirect to home
        // Exception: Don't redirect from /signup - let signup screen handle navigation to verify-email-pending
        if (isLoggedIn && isAuthRoute && state.matchedLocation != '/signup') {
          // Check for 'from' query parameter to redirect back (e.g., after login from invite link)
          final redirectTo = state.uri.queryParameters['from'];
          if (redirectTo != null && redirectTo.startsWith('/')) {
            return redirectTo;
          }
          return '/';
        }

        // If user is logged in and trying to access protected routes, check email verification
        if (isLoggedIn && !isPublicRoute) {
          try {
            final authProvider = context.read<app_auth.AuthProvider>();
            final appUser = authProvider.appUser;
            final isAdminOnlySettingsRoute =
                state.matchedLocation == '/settings/invite' ||
                state.matchedLocation == '/settings/role-templates' ||
                state.matchedLocation == '/settings/permission-matrix';
            final isRestrictedSettingsRoute =
                state.matchedLocation == '/workspaces/settings';

            // Don't run permission gates until the appUser + role
            // templates have hydrated. Otherwise a deep-link/refresh
            // races the provider — `canManageUsers` and
            // `canAccessSettings` momentarily report false for admins
            // and the user gets silently bounced to /. Let the route
            // render; the screens themselves render a "You don't have
            // access" state when permissions truly say no.
            final permissionsHydrated =
                appUser != null && authProvider.rolePermissions != null;

            if (permissionsHydrated &&
                isAdminOnlySettingsRoute &&
                !authProvider.canManageUsers) {
              debugPrint(
                '🔒 ROUTER: Blocking non-admin from ${state.matchedLocation}',
              );
              return '/?denied=${Uri.encodeComponent(state.matchedLocation)}';
            }

            if (permissionsHydrated &&
                isRestrictedSettingsRoute &&
                !authProvider.canAccessSettings) {
              debugPrint(
                '🔒 ROUTER: Blocking restricted user from ${state.matchedLocation}',
              );
              return '/?denied=${Uri.encodeComponent(state.matchedLocation)}';
            }


            final isProjectWriteRoute =
                state.matchedLocation == '/projects/new' ||
                (state.matchedLocation.endsWith('/edit') &&
                    state.matchedLocation.startsWith('/projects/') &&
                    !state.matchedLocation.contains('/tasks/'));
            if (permissionsHydrated &&
                isProjectWriteRoute &&
                !authProvider.canEditProjects) {
              debugPrint(
                '🔒 ROUTER: Blocking project write route ${state.matchedLocation}',
              );
              return '/projects';
            }

            final isTaskWriteRoute =
                state.matchedLocation.endsWith('/tasks/new') ||
                state.matchedLocation.contains('/tasks/') &&
                    state.matchedLocation.endsWith('/edit');
            if (permissionsHydrated &&
                isTaskWriteRoute &&
                !(state.matchedLocation.endsWith('/tasks/new')
                    ? authProvider.canCreateTasks
                    : authProvider.canEditTasks)) {
              debugPrint(
                '🔒 ROUTER: Blocking task write route ${state.matchedLocation}',
              );
              return '/tasks';
            }

            final isAdminTimeTrackingRoute =
                state.matchedLocation == '/time-tracking/dashboard' ||
                state.matchedLocation == '/time-tracking/approvals' ||
                state.matchedLocation == '/time-tracking/employees';
            if (permissionsHydrated &&
                isAdminTimeTrackingRoute &&
                !authProvider.canManageUsers) {
              debugPrint(
                '🔒 ROUTER: Blocking non-admin from ${state.matchedLocation}',
              );
              return '/time-tracking';
            }

            debugPrint(
              '🔒 ROUTER: Checking email verification for route: ${state.matchedLocation}',
            );
            debugPrint(
              '🔒 ROUTER: appUser is ${appUser != null ? "loaded" : "null"}',
            );
            debugPrint('🔒 ROUTER: emailVerified = ${appUser?.emailVerified}');
            // If user data is loaded and email is NOT verified, redirect to verification
            // emailVerified == false means explicitly not verified (new user)
            // emailVerified == null or true means verified (legacy users or verified users)
            if (appUser != null && appUser.emailVerified == false) {
              debugPrint('🔒 ROUTER: Redirecting to /verify-email-pending');
              return '/verify-email-pending';
            }

            // Force first-time admins through onboarding. Without this, an
            // owner who signs in via the password form (instead of clicking
            // the email-verification link) skips /onboarding entirely.
            // Field-tech / non-admin members shouldn't be pushed here — that's
            // the workspace owner's task.
            if (appUser != null && authProvider.canManageUsers) {
              try {
                final workspaceProvider =
                    context.read<WorkspaceProvider>();
                final hasWorkspace =
                    appUser.currentWorkspaceId.isNotEmpty &&
                    workspaceProvider.workspaces.isNotEmpty;
                if (hasWorkspace &&
                    !workspaceProvider.currentWorkspaceOnboardingCompleted) {
                  debugPrint(
                    '🔒 ROUTER: Workspace onboarding incomplete, redirecting to /onboarding',
                  );
                  return '/onboarding';
                }
              } catch (_) {
                // WorkspaceProvider not yet available; let the request through.
              }
            }
          } catch (e) {
            // Provider not available yet, allow through
            debugPrint('🔒 ROUTER: Provider not available - $e');
          }
        }

        return null;
      },
      routes: [
        // Public download landing. Outside the project ShellRoute so
        // unauthenticated marketing visitors don't trigger workspace
        // / nav chrome that depends on a signed-in user.
        GoRoute(
          path: '/apps',
          builder: (context, state) => _selectable(const GetTheAppScreen()),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => _selectable(const LoginScreen()),
        ),
        GoRoute(
          path: '/signup',
          builder: (context, state) {
            final email = state.uri.queryParameters['email'];
            final redirectTo = state.uri.queryParameters['from'];
            final allowSignup = BetaSignupConfig.allowsSignup(
              uri: state.uri,
              redirectTo: redirectTo,
            );
            return _selectable(SignupScreen(
              initialEmail: email,
              redirectTo: redirectTo,
              allowSignup: allowSignup,
            ));
          },
        ),
        GoRoute(
          path: '/password-reset',
          builder: (context, state) => _selectable(const PasswordResetScreen()),
        ),
        GoRoute(
          path: '/verify-email-pending',
          builder: (context, state) => _selectable(
            EmailVerificationPendingScreen(
              initialEmail: state.uri.queryParameters['email'],
              redirectTo: state.uri.queryParameters['from'],
            ),
          ),
        ),
        GoRoute(
          path: '/verify-email',
          builder: (context, state) {
            final token = state.uri.queryParameters['token'];
            final redirectTo = state.uri.queryParameters['from'];
            return _selectable(
                EmailVerifiedScreen(token: token, redirectTo: redirectTo));
          },
        ),
        GoRoute(
          path: '/onboarding',
          redirect: (context, state) {
            // /onboarding is the wizard for fresh workspaces. If the user
            // navigated here directly (browser back, bookmark, link in an
            // email) but their active workspace is already onboarded — and
            // they're not explicitly creating a *new* workspace via the
            // ?newWorkspace=true param — bounce them home instead of
            // restarting the wizard at step 1.
            final isNewWorkspace =
                state.uri.queryParameters['newWorkspace'] == 'true';
            if (isNewWorkspace) return null;
            final workspaceProvider = context.read<WorkspaceProvider>();
            if (workspaceProvider.currentWorkspaceOnboardingCompleted) {
              return '/';
            }
            return null;
          },
          builder: (context, state) {
            final isNewWorkspace =
                state.uri.queryParameters['newWorkspace'] == 'true';
            return _selectable(
                OnboardingScreen(isNewWorkspace: isNewWorkspace));
          },
        ),
        GoRoute(
          path: '/invite/:token',
          builder: (context, state) {
            final token = state.pathParameters['token']!;
            return _selectable(InvitationAcceptanceScreen(token: token));
          },
        ),
        GoRoute(
          path: '/welcome',
          builder: (context, state) {
            final workspaceName =
                state.uri.queryParameters['workspace'] ?? 'your workspace';
            return _selectable(
                MemberWelcomeScreen(workspaceName: workspaceName));
          },
        ),
        // Client Portal routes (public - no login required)
        GoRoute(
          path: '/portal',
          builder: (context, state) {
            final token = state.uri.queryParameters['token'];
            return _selectable(PortalLoginScreen(token: token));
          },
        ),
        GoRoute(
          path: '/portal/dashboard',
          builder: (context, state) => _selectable(
            PortalPreviewScope.wrapRoute(
              context,
              state,
              const PortalDashboardScreen(),
            ),
          ),
        ),
        GoRoute(
          path: '/portal/invoices',
          builder: (context, state) => _selectable(
            PortalPreviewScope.wrapRoute(
              context,
              state,
              const PortalInvoiceListScreen(),
            ),
          ),
        ),
        GoRoute(
          path: '/portal/invoices/:invoiceId',
          builder: (context, state) {
            final invoiceId = state.pathParameters['invoiceId']!;
            return _selectable(PortalPreviewScope.wrapRoute(
              context,
              state,
              PortalInvoiceDetailScreen(invoiceId: invoiceId),
            ));
          },
        ),
        GoRoute(
          path: '/portal/documents/:documentId',
          builder: (context, state) {
            final documentId = state.pathParameters['documentId']!;
            return _selectable(PortalPreviewScope.wrapRoute(
              context,
              state,
              PortalDocumentDetailScreen(documentId: documentId),
            ));
          },
        ),
        GoRoute(
          path: '/portal/projects/:projectId',
          builder: (context, state) {
            final projectId = state.pathParameters['projectId']!;
            return _selectable(PortalPreviewScope.wrapRoute(
              context,
              state,
              PortalProjectScreen(projectId: projectId),
            ));
          },
        ),
        // Vendor Portal routes (public - magic-link auth)
        GoRoute(
          path: '/vendor-portal',
          builder: (context, state) =>
              _selectable(const VendorPortalLoginScreen()),
        ),
        GoRoute(
          path: '/vendor-portal/dashboard',
          builder: (context, state) =>
              _selectable(const VendorPortalDashboardScreen()),
        ),
        GoRoute(
          path: '/vendor-portal/bids',
          builder: (context, state) =>
              _selectable(const VendorPortalBidsScreen()),
        ),
        GoRoute(
          path: '/vendor-portal/work-orders',
          builder: (context, state) =>
              _selectable(const VendorPortalWorkOrdersScreen()),
        ),
        GoRoute(
          path: '/vendor-portal/selections',
          builder: (context, state) =>
              _selectable(const VendorPortalSelectionsScreen()),
        ),
        GoRoute(
          path: '/vendor-portal/bills',
          builder: (context, state) =>
              _selectable(const VendorPortalBillsScreen()),
        ),
        GoRoute(
          path: '/sign/:token',
          builder: (context, state) {
            final token = state.pathParameters['token']!;
            return _selectable(PublicDocumentSignScreen(token: token));
          },
        ),
        GoRoute(
          path: '/sign-form/:token',
          builder: (context, state) {
            final token = state.pathParameters['token']!;
            return _selectable(PublicFieldFormSignScreen(token: token));
          },
        ),
        GoRoute(
          path: '/projects/new',
          builder: (context, state) => _selectable(const ProjectFormScreen()),
        ),
        GoRoute(
          path: '/vendors/new',
          builder: (context, state) => _selectable(const VendorFormScreen()),
        ),
        GoRoute(
          path: '/projects/:id/edit',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return _selectable(ProjectFormScreen(projectId: id));
          },
        ),
        GoRoute(
          path: '/projects/:projectId/pay-applications',
          builder: (context, state) {
            final projectId = state.pathParameters['projectId']!;
            return _selectable(PayApplicationsListScreen(projectId: projectId));
          },
        ),
        GoRoute(
          path: '/projects/:projectId/pay-applications/:payAppId',
          builder: (context, state) {
            final projectId = state.pathParameters['projectId']!;
            final payAppId = state.pathParameters['payAppId']!;
            return _selectable(PayApplicationEditorScreen(
              projectId: projectId,
              payAppId: payAppId,
            ));
          },
        ),
        GoRoute(
          path: '/projects/:projectId/holdback-releases',
          builder: (context, state) {
            final projectId = state.pathParameters['projectId']!;
            return _selectable(HoldbackReleasesListScreen(projectId: projectId));
          },
        ),
        GoRoute(
          path: '/projects/:projectId/holdback-releases/:releaseId',
          builder: (context, state) {
            final projectId = state.pathParameters['projectId']!;
            final releaseId = state.pathParameters['releaseId']!;
            return _selectable(HoldbackReleaseEditorScreen(
              projectId: projectId,
              releaseId: releaseId,
            ));
          },
        ),
        GoRoute(
          path: '/projects/:projectId/tasks/new',
          builder: (context, state) {
            final projectId = state.pathParameters['projectId']!;
            return _selectable(TaskFormScreen(projectId: projectId));
          },
        ),
        GoRoute(
          path: '/projects/:projectId/tasks/:taskId/edit',
          builder: (context, state) {
            final projectId = state.pathParameters['projectId']!;
            final taskId = state.pathParameters['taskId']!;
            return _selectable(
                TaskFormScreen(projectId: projectId, taskId: taskId));
          },
        ),
        GoRoute(
          path: '/projects/:projectId/plans/upload',
          builder: (context, state) {
            final projectId = state.pathParameters['projectId']!;
            final propertyId = state.uri.queryParameters['property'];
            return _selectable(PlanUploadScreen(
              projectId: projectId,
              initialPropertyId: propertyId,
            ));
          },
        ),
        // Room scan flow lives outside the project ShellRoute so the
        // native AR view can use the full screen. Two variants:
        //   * /projects/:projectId/plans/scan  — create a new plan.
        //   * /projects/:projectId/plans/:planId/scan  — append the
        //     scanned room into an existing plan's scene.
        GoRoute(
          path: '/projects/:projectId/plans/scan',
          builder: (context, state) {
            final projectId = state.pathParameters['projectId']!;
            final propertyId = state.uri.queryParameters['property'];
            return RoomScanScreen(
              projectId: projectId,
              propertyId: propertyId,
            );
          },
        ),
        GoRoute(
          path: '/projects/:projectId/plans/:planId/scan',
          builder: (context, state) {
            final projectId = state.pathParameters['projectId']!;
            final planId = state.pathParameters['planId']!;
            return RoomScanScreen(
              projectId: projectId,
              appendToPlanId: planId,
            );
          },
        ),
        // Distraction-free fullscreen editor route lives outside the
        // project ShellRoute. The compact, in-shell variant is mounted
        // inside the shell next to /plans (see below).
        GoRoute(
          path: '/projects/:projectId/plans/:planId/edit/fullscreen',
          builder: (context, state) {
            final projectId = state.pathParameters['projectId']!;
            final planId = state.pathParameters['planId']!;
            return FloorplanEditorScreen(
              projectId: projectId,
              planId: planId,
              fullscreen: true,
            );
          },
        ),
        ShellRoute(
          builder: (context, state, child) {
            // Determine selectedIndex based on current location
            int selectedIndex = 0;
            final location = state.matchedLocation;

            if (location.startsWith('/messages')) {
              selectedIndex = 1; // Inbox
            } else if (location == '/projects' ||
                (location.startsWith('/projects/') &&
                    !location.contains('/edit') &&
                    !location.contains('/new') &&
                    !location.contains('/tasks') &&
                    !location.contains('/costs') &&
                    !location.contains('/budget'))) {
              selectedIndex = 2; // Projects
            } else if (location == '/tasks') {
              selectedIndex = 3; // Tasks
              // Schedule removed - merged into Tasks
            } else if (location.startsWith('/opportunities')) {
              selectedIndex = 23; // Opportunities (P2-1 pipeline)
            } else if (location.startsWith('/customers')) {
              selectedIndex = 4; // Customers
            } else if (location == '/financials' ||
                location == '/budget' ||
                (location.startsWith('/projects/') &&
                    location.contains('/budget'))) {
              selectedIndex = 5; // Financials
            } else if (location.startsWith('/vendors')) {
              selectedIndex = 7; // Vendors
            } else if (location.startsWith('/reports')) {
              selectedIndex = 12; // Reports
            } else if (location == '/team' ||
                location.startsWith('/time-tracking') ||
                location == '/time') {
              selectedIndex = 9; // Team (+ time-tracking)
            } else if ((location.startsWith('/assets') || location.startsWith('/equipment'))) {
              selectedIndex = 10; // Assets (own sidebar entry)
            } else if (location.startsWith('/inventory')) {
              selectedIndex = 20; // Inventory
            } else if (location.startsWith('/vehicles')) {
              selectedIndex = 11; // Vehicles
            } else if (location == '/settings/customer-types') {
              selectedIndex = 4; // Customers
            } else if (location == '/settings/vendor-types') {
              selectedIndex = 7; // Vendors
            } else if (location.startsWith('/settings') ||
                location == '/workspaces/settings') {
              selectedIndex = 13; // Settings
            } else if (location.startsWith('/profile')) {
              selectedIndex = 14; // Profile
            } else if (location.startsWith('/catalog')) {
              selectedIndex = 16; // Catalog
            } else if (location.startsWith('/templates')) {
              selectedIndex = 17; // Templates
            } else if (location.startsWith('/forms')) {
              selectedIndex = 17; // Templates (form routes)
            } else if (location.startsWith('/field-forms')) {
              selectedIndex = 17; // Templates (field form routes)
            } else if (location.startsWith('/files')) {
              selectedIndex = 18; // Files
            } else if (location.startsWith('/documents')) {
              selectedIndex = 18; // Files (Documents is a sub-section of Files)
            } else if (location.startsWith('/calendar')) {
              selectedIndex = 6; // Calendar
            } else if (location.startsWith('/help')) {
              selectedIndex = 19; // Help & About
            }

            // Make in-shell screen content selectable. Wraps the content
            // area only (not the nav chrome) so sidebar taps/drags are
            // unaffected. The floorplan editor is a drawing canvas where
            // pointer drags must not start text selection, so it opts out.
            final isFloorplanEditor =
                location.contains('/plans/') && location.endsWith('/edit');
            return AdaptiveNavigation(
              selectedIndex: selectedIndex,
              child: isFloorplanEditor ? child : _selectable(child),
            );
          },
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: HomeScreen()),
            ),
            GoRoute(
              path: '/calendar',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: CalendarScreen()),
            ),
            GoRoute(
              path: '/projects',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ProjectsTableScreen()),
            ),
            GoRoute(
              path: '/inbox',
              // /inbox is a legacy URL alias — the real concept lives at
              // /messages (the slide-out conversations panel). Redirect
              // rather than silently dropping users on the dashboard.
              redirect: (context, state) => '/messages',
            ),
            GoRoute(
              path: '/jobs',
              redirect: (context, state) => '/projects',
            ),
            GoRoute(
              path: '/jobs/:id',
              redirect: (context, state) {
                final id = state.pathParameters['id']!;
                final query = state.uri.query;
                return '/projects/$id${query.isNotEmpty ? '?$query' : ''}';
              },
            ),
            GoRoute(
              path: '/projects/dashboard',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ProjectDashboardScreen()),
            ),
            GoRoute(
              path: '/projects/:id',
              pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                final tab = state.uri.queryParameters['tab'];
                final taskId = state.uri.queryParameters['taskId'];
                final taskView = state.uri.queryParameters['taskView'];
                final taskMetric = state.uri.queryParameters['taskMetric'];
                final aiSetup = state.uri.queryParameters['aiSetup'] == 'true';
                return NoTransitionPage(
                  child: ProjectDetailScreen(
                    projectId: id,
                    initialTab: tab,
                    initialTaskId: taskId,
                    initialTaskView: taskView,
                    initialTaskMetric: taskMetric,
                    showAiSetup: aiSetup,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/tasks',
              pageBuilder: (context, state) {
                final overdue = state.uri.queryParameters['overdue'] == 'true';
                return NoTransitionPage(
                  child: AllTasksScreen(
                    initialOverdue: overdue,
                    initialView: state.uri.queryParameters['view'],
                  ),
                );
              },
            ),
            GoRoute(
              path: '/budget',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: BudgetListScreen()),
            ),
            GoRoute(
              path: '/work-orders',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: AllWorkOrdersScreen()),
            ),
            GoRoute(
              path: '/subcontracts',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: AllSubcontractsScreen()),
            ),
            GoRoute(
              path: '/change-orders',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: AllChangeOrdersScreen()),
            ),
            GoRoute(
              path: '/financials',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: FinancialsScreen()),
            ),
            GoRoute(
              path: '/projects/:id/schedule',
              pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                return NoTransitionPage(
                  child: ProjectScheduleScreen(projectId: id),
                );
              },
            ),
            GoRoute(
              path: '/projects/:id/costs',
              pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                return NoTransitionPage(
                  child: ProjectCostingScreen(projectId: id),
                );
              },
            ),
            GoRoute(
              path: '/projects/:id/plans',
              pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                final propertyId = state.uri.queryParameters['property'];
                return NoTransitionPage(
                  child: PlansListScreen(
                    projectId: id,
                    initialPropertyId: propertyId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/projects/:projectId/plans/:planId',
              pageBuilder: (context, state) {
                final projectId = state.pathParameters['projectId']!;
                final planId = state.pathParameters['planId']!;
                return NoTransitionPage(
                  child: PlanDetailScreen(projectId: projectId, planId: planId),
                );
              },
            ),
            // Compact editor — inside the project ShellRoute so the
            // project nav stays visible while drawing.
            GoRoute(
              path: '/projects/:projectId/plans/:planId/edit',
              pageBuilder: (context, state) {
                final projectId = state.pathParameters['projectId']!;
                final planId = state.pathParameters['planId']!;
                return NoTransitionPage(
                  child: FloorplanEditorScreen(
                    projectId: projectId,
                    planId: planId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/projects/:id/budget',
              pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                return NoTransitionPage(child: BudgetViewScreen(projectId: id));
              },
            ),
            GoRoute(
              path: '/settings/users',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: UserManagementScreen()),
            ),
            GoRoute(
              path: '/workspaces/new',
              redirect: (context, state) => '/onboarding?newWorkspace=true',
            ),
            GoRoute(
              path: '/workspaces/settings',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: WorkspaceSettingsScreen()),
            ),
            GoRoute(
              path: '/settings/invite',
              pageBuilder: (context, state) {
                final authProvider = Provider.of<app_auth.AuthProvider>(
                  context,
                  listen: false,
                );
                final workspaceId =
                    state.uri.queryParameters['workspaceId'] ??
                    authProvider.appUser?.currentWorkspaceId ??
                    '';
                return NoTransitionPage(
                  child: UserInvitationScreen(workspaceId: workspaceId),
                );
              },
            ),
            GoRoute(
              path: '/settings/audit',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: WorkspaceAuditLogScreen()),
            ),
            GoRoute(
              path: '/settings/role-templates',
              pageBuilder: (context, state) => NoTransitionPage(
                child: buildRolesAndPermissionsForRoute(
                  state.matchedLocation,
                ),
              ),
            ),
            GoRoute(
              path: '/settings/permission-matrix',
              pageBuilder: (context, state) => NoTransitionPage(
                child: buildRolesAndPermissionsForRoute(
                  state.matchedLocation,
                ),
              ),
            ),
            GoRoute(
              path: '/settings/profiles',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: WorkspaceSettingsProfilesScreen(),
              ),
            ),
            GoRoute(
              path: '/settings/automations',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: AutomationRulesScreen()),
            ),
            GoRoute(
              path: '/settings/api-keys',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ApiKeysScreen()),
            ),
            GoRoute(
              path: '/settings/customer-types',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: CustomerTypeManagementScreen()),
            ),
            GoRoute(
              path: '/settings/asset-categories',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: AssetCategoryManagementScreen(),
              ),
            ),
            GoRoute(
              path: '/settings/file-tags',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: FileTagManagerScreen()),
            ),
            GoRoute(
              path: '/settings/custom-fields',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: CustomFieldsScreen()),
            ),
            GoRoute(
              path: '/settings/vendor-types',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: VendorTypeManagementScreen()),
            ),
            GoRoute(
              path: '/settings/document-numbering',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: DocumentNumberingSettingsScreen(),
              ),
            ),
            GoRoute(
              path: '/customers',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: CustomerListScreen()),
            ),
            GoRoute(
              path: '/opportunities',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: OpportunitiesScreen()),
            ),
            GoRoute(
              path: '/opportunities/new',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: OpportunityFormScreen()),
            ),
            GoRoute(
              path: '/opportunities/:id',
              pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                return NoTransitionPage(
                  child: OpportunityDetailScreen(opportunityId: id),
                );
              },
            ),
            GoRoute(
              path: '/opportunities/:id/edit',
              pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                return NoTransitionPage(
                  child: OpportunityFormScreen(opportunityId: id),
                );
              },
            ),
            GoRoute(
              path: '/customers/:id',
              pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                if (id == 'new') {
                  return const NoTransitionPage(child: CustomerFormScreen());
                }
                final openPortalInvite =
                    state.uri.queryParameters['openPortalInvite'] == 'true';
                return NoTransitionPage(
                  child: CustomerDetailScreen(
                    customerId: id,
                    openPortalInvite: openPortalInvite,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/vendors',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: VendorListScreen()),
            ),
            GoRoute(
              path: '/vendors/:id',
              pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                return NoTransitionPage(
                  child: VendorDetailScreen(vendorId: id),
                );
              },
            ),
            // Time Tracking routes
            GoRoute(
              path: '/time-tracking/dashboard',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: AdminTimesheetDashboard()),
            ),
            GoRoute(
              path: '/time-tracking',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ClockInOutScreen()),
            ),
            // Friendly alias — older links and direct URL typing for "/time"
            // used to fall through to the global ErrorWidget.
            GoRoute(
              path: '/time',
              redirect: (_, __) => '/time-tracking',
            ),
            GoRoute(
              path: '/time-tracking/timesheet',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: DailyTimesheetScreen()),
            ),
            GoRoute(
              path: '/time-tracking/history',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: DailyTimesheetScreen()),
            ),
            GoRoute(
              path: '/time-tracking/approvals',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: TimeApprovalScreen()),
            ),
            GoRoute(
              path: '/team',
              pageBuilder: (context, state) {
                final tab = state.uri.queryParameters['tab'];
                final projectId = state.uri.queryParameters['projectId'];
                final memberId = state.uri.queryParameters['memberId'];
                return NoTransitionPage(
                  child: TeamScreen(
                    initialTab: tab,
                    initialProjectId: projectId,
                    initialMemberId: memberId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/time-tracking/weekly',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: WeeklyTimesheetScreen()),
            ),
            GoRoute(
              path: '/time-tracking/employees',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: EmployeeTimeTableScreen()),
            ),
            GoRoute(
              path: '/reports',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ReportingDashboardScreen()),
            ),
            GoRoute(
              path: '/help',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: HelpAboutScreen()),
            ),
            GoRoute(
              path: '/messages',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: MessagesListScreen()),
            ),
            GoRoute(
              path: '/messages/saved',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SavedMessagesScreen()),
            ),
            GoRoute(
              path: '/messages/:conversationId',
              pageBuilder: (context, state) {
                final conversationId = state.pathParameters['conversationId'];

                // Don't treat 'new' as a conversation ID - it's handled separately
                if (conversationId == 'new') {
                  return const NoTransitionPage(child: NewConversationScreen());
                }

                return NoTransitionPage(
                  child: MessagesListScreen(
                    selectedConversationId: conversationId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/notifications',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: NotificationsScreen()),
            ),
            GoRoute(
              path: '/ai-assistant',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: AiAssistantScreen()),
            ),
            GoRoute(
              path: '/projects/:projectId/ai-plan/:planId',
              builder: (context, state) => AiPlanReviewScreen(
                projectId: state.pathParameters['projectId']!,
                planId: state.pathParameters['planId']!,
              ),
            ),
            // Profile routes (inside shell to have navigation)
            GoRoute(
              path: '/profile',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ProfileViewScreen()),
            ),
            GoRoute(
              path: '/profile/:userId',
              pageBuilder: (context, state) {
                final userId = state.pathParameters['userId']!;
                return NoTransitionPage(
                  child: ProfileViewScreen(userId: userId),
                );
              },
            ),
            // Equipment & Assets. Canonical path is /equipment because
            // /assets collides with the Flutter web build's real assets/
            // directory — nginx serves the directory (301 → 403) before the
            // SPA fallback ever runs, so /assets deep-links and refreshes
            // were dead on web. /assets is kept as an in-app redirect alias.
            GoRoute(
              path: '/equipment',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: AssetListScreen()),
              routes: [
                GoRoute(
                  path: 'new',
                  builder: (context, state) => const AssetFormScreen(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return AssetDetailScreen(assetId: id);
                  },
                  routes: [
                    GoRoute(
                      path: 'edit',
                      builder: (context, state) {
                        final id = state.pathParameters['id']!;
                        return AssetFormScreen(assetId: id);
                      },
                    ),
                  ],
                ),
              ],
            ),
            GoRoute(
              path: '/assets',
              redirect: (context, state) => '/equipment',
              routes: [
                GoRoute(
                  path: 'new',
                  redirect: (context, state) => '/equipment/new',
                ),
                GoRoute(
                  path: ':id',
                  redirect: (context, state) =>
                      '/equipment/${state.pathParameters['id']}',
                  routes: [
                    GoRoute(
                      path: 'edit',
                      redirect: (context, state) =>
                          '/equipment/${state.pathParameters['id']}/edit',
                    ),
                  ],
                ),
              ],
            ),
            GoRoute(
              path: '/inventory',
              // Purchase orders moved out of Inventory into the documents-first
              // Financials view; redirect any legacy ?tab=pos deep links there.
              redirect: (context, state) {
                final tabParam = state.uri.queryParameters['tab'];
                if (tabParam == 'pos' || tabParam == 'purchase_orders') {
                  return '/financials';
                }
                return null;
              },
              pageBuilder: (context, state) {
                final tabParam = state.uri.queryParameters['tab'];
                int initialTab = 0;
                switch (tabParam) {
                  case 'suppliers':
                    initialTab = 1;
                    break;
                  case 'rentals':
                    initialTab = 2;
                    break;
                  case 'equipment':
                    initialTab = 3;
                    break;
                  default:
                    initialTab = 0;
                }
                return NoTransitionPage(
                  child: InventoryScreen(initialTabIndex: initialTab),
                );
              },
            ),
            GoRoute(
              path: '/vehicles',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: VehicleListScreen()),
              routes: [
                GoRoute(
                  path: 'new',
                  builder: (context, state) => const VehicleFormScreen(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return VehicleDetailScreen(vehicleId: id);
                  },
                  routes: [
                    GoRoute(
                      path: 'edit',
                      builder: (context, state) {
                        final id = state.pathParameters['id']!;
                        return VehicleFormScreen(vehicleId: id);
                      },
                    ),
                  ],
                ),
              ],
            ),
            GoRoute(
              path: '/catalog',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: CatalogScreen()),
            ),
            GoRoute(
              path: '/catalog/item/new',
              pageBuilder: (context, state) {
                final q = state.uri.queryParameters;
                final levelStr = q['level'];
                return NoTransitionPage(
                  child: CatalogItemFormScreen(
                    initialParentId: q['parent_id'],
                    initialHierarchyLevel:
                        levelStr == null ? null : int.tryParse(levelStr),
                    initialIsGroup: q['kind'] == 'group',
                  ),
                );
              },
            ),
            GoRoute(
              path: '/catalog/item/:id',
              pageBuilder: (context, state) => NoTransitionPage(
                child: CatalogItemFormScreen(
                  itemId: state.pathParameters['id'],
                ),
              ),
            ),
            // Templates route (unified view for form and document templates)
            GoRoute(
              path: '/templates',
              pageBuilder: (context, state) {
                final tabParam = state.uri.queryParameters['tab'];
                final tabIndex = tabParam == 'forms' ? 1 : 0;
                return NoTransitionPage(
                  child: TemplatesScreen(initialTabIndex: tabIndex),
                );
              },
            ),
            // Forms routes
            GoRoute(
              path: '/forms',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: TemplatesScreen(initialTabIndex: 1),
              ),

              routes: [
                GoRoute(
                  path: 'new',
                  builder: (context, state) {
                    final projectId = state.uri.queryParameters['projectId'];
                    return FormBuilderScreen(projectId: projectId);
                  },
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return FormDetailScreen(formId: id);
                  },
                  routes: [
                    GoRoute(
                      path: 'edit',
                      builder: (context, state) {
                        final id = state.pathParameters['id']!;
                        return FormBuilderScreen(formId: id);
                      },
                    ),
                    GoRoute(
                      path: 'submissions',
                      builder: (context, state) {
                        final id = state.pathParameters['id']!;
                        return FormSubmissionsScreen(formId: id);
                      },
                    ),
                  ],
                ),
              ],
            ),
            // Field Forms routes
            GoRoute(
              path: '/field-forms',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: FieldFormTemplateListScreen()),
              routes: [
                GoRoute(
                  path: 'new',
                  builder: (context, state) =>
                      const FieldFormTemplateEditorScreen(),
                ),
                GoRoute(
                  path: 'submissions/:submissionId',
                  builder: (context, state) {
                    final submissionId = state.pathParameters['submissionId']!;
                    return FieldFormSubmissionDetailScreen(
                      submissionId: submissionId,
                    );
                  },
                ),
                GoRoute(
                  path: ':templateId',
                  builder: (context, state) {
                    // Default to editor when navigated directly
                    final templateId = state.pathParameters['templateId']!;
                    return FieldFormTemplateEditorScreen(
                      templateId: templateId,
                    );
                  },
                  routes: [
                    GoRoute(
                      path: 'edit',
                      builder: (context, state) {
                        final templateId = state.pathParameters['templateId']!;
                        return FieldFormTemplateEditorScreen(
                          templateId: templateId,
                        );
                      },
                    ),
                    GoRoute(
                      path: 'fill',
                      builder: (context, state) {
                        final templateId = state.pathParameters['templateId']!;
                        final taskId = state.uri.queryParameters['taskId'];
                        final projectId =
                            state.uri.queryParameters['projectId'];
                        final submissionId =
                            state.uri.queryParameters['submissionId'];
                        return FieldFormFillScreen(
                          templateId: templateId,
                          taskId: taskId,
                          projectId: projectId,
                          submissionId: submissionId,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            // Files route — cross-project file explorer (nav item index 18)
            GoRoute(
              path: '/files',
              pageBuilder: (context, state) {
                final requestedFolder = state.uri.queryParameters['folder'];
                const allowedFolders = {
                  VirtualFolderType.tasks,
                  VirtualFolderType.messages,
                  VirtualFolderType.forms,
                  VirtualFolderType.documents,
                  VirtualFolderType.dailyLogs,
                  VirtualFolderType.inspections,
                  VirtualFolderType.punchList,
                  VirtualFolderType.warranties,
                  VirtualFolderType.plans,
                  VirtualFolderType.specifications,
                };
                final initialVirtualFolder =
                    allowedFolders.contains(requestedFolder)
                        ? requestedFolder
                        : null;
                return NoTransitionPage(
                  child: WorkspaceFilesScreen(
                    initialProjectId: state.uri.queryParameters['projectId'],
                    initialVirtualFolder: initialVirtualFolder,
                    initialSelectedDocumentId:
                        state.uri.queryParameters['documentId'],
                    initialFileId: state.uri.queryParameters['fileId'],
                    initialCommentId:
                        state.uri.queryParameters['commentId'],
                  ),
                );
              },
            ),
            // Documents routes (kept for backward compat — deep links, back nav)
            GoRoute(
              path: '/documents',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: DocumentListScreen()),
              routes: [
                // Alias: /documents/new -> /documents/create
                GoRoute(
                  path: 'new',
                  redirect: (context, state) {
                    final query = state.uri.query;
                    return '/documents/create${query.isNotEmpty ? '?$query' : ''}';
                  },
                ),
                GoRoute(
                  path: 'create',
                  builder: (context, state) {
                    final templateId = state.uri.queryParameters['templateId'];
                    final projectId = state.uri.queryParameters['projectId'];
                    final customerId = state.uri.queryParameters['customerId'];
                    final preferType =
                        state.uri.queryParameters['prefer_type'];
                    final preferredType = preferType == null
                        ? null
                        : DocumentTypeExtension.fromStoredValue(preferType);
                    final extra = state.extra as Map<String, dynamic>?;
                    return CreateDocumentScreen(
                      templateId: templateId,
                      projectId: projectId,
                      customerId: customerId,
                      preferredType: preferredType,
                      existingDocument:
                          extra?['existingDocument'] as GeneratedDocument?,
                      prePopulatedLineItems:
                          extra?['lineItems'] as List<Map<String, dynamic>>?,
                      preSelectedBudgetItemIds:
                          (extra?['selectedBudgetItemIds'] as List<dynamic>?)
                              ?.cast<String>(),
                      preSelectedBudgetItemAmounts:
                          (extra?['budgetItemAmounts'] as Map<String, dynamic>?)
                              ?.map(
                                (key, value) =>
                                    MapEntry(key, (value as num).toDouble()),
                              ),
                      vendorId: extra?['vendorId'] as String?,
                      sourceDocumentId: extra?['sourceDocumentId'] as String?,
                    );
                  },
                ),
                GoRoute(
                  path: 'templates',
                  builder: (context, state) =>
                      const TemplatesScreen(initialTabIndex: 0),
                  routes: [
                    GoRoute(
                      path: 'new',
                      builder: (context, state) => const TemplateEditorScreen(),
                    ),
                    GoRoute(
                      path: ':id/edit',
                      builder: (context, state) {
                        final id = state.pathParameters['id']!;
                        return TemplateEditorScreen(templateId: id);
                      },
                    ),
                  ],
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return DocumentDetailScreen(documentId: id);
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/bid-packages/new',
              builder: (context, state) {
                final projectId =
                    state.uri.queryParameters['projectId'];
                return CreateBidPackageScreen(
                  initialProjectId: projectId,
                );
              },
            ),
            GoRoute(
              path: '/bid-packages/:id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return BidPackageScreen(packageId: id);
              },
            ),
          ],
        ),

        // Customer and Vendor form routes (outside shell for full-screen editing)
        GoRoute(
          path: '/customers/new',
          builder: (context, state) => const CustomerFormScreen(),
        ),
        GoRoute(
          path: '/customers/:id/edit',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return CustomerFormScreen(customerId: id);
          },
        ),

        GoRoute(
          path: '/vendors/:id/edit',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return VendorFormScreen(vendorId: id);
          },
        ),
        // Messaging routes
        GoRoute(
          path: '/messages/new',
          builder: (context, state) => const NewConversationScreen(),
        ),
        GoRoute(
          path: '/messages/conversation/:id',
          redirect: (context, state) =>
              '/messages/${state.pathParameters['id']!}',
        ),
        GoRoute(
          path: '/qr-scanner',
          builder: (context, state) => const QRScannerScreen(),
        ),
        // Public form route (no auth required)
        GoRoute(
          path: '/f/:slug',
          builder: (context, state) {
            final slug = state.pathParameters['slug']!;
            return PublicFormScreen(slug: slug);
          },
        ),
      ],
    );
  }
}
