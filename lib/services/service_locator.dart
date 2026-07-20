import 'supabase/auth_service.dart' as supabase_auth;
import 'supabase/field_form_service.dart' as supabase_field_form;
import 'supabase/user_service.dart' as supabase_user;
import 'supabase/workspace_service.dart' as supabase_workspace;
import 'supabase/workspace_member_service.dart' as supabase_member;
import 'supabase/invitation_service.dart' as supabase_invitation;
import 'supabase/project_service.dart' as supabase_project;
import 'supabase/task_service.dart' as supabase_task;
import 'supabase/schedule_baseline_service.dart' as supabase_schedule_baseline;
import 'supabase/task_comment_service.dart' as supabase_task_comment;
import 'supabase/storage_service.dart' as supabase_storage;
import 'supabase/folder_service.dart' as supabase_folder;
import 'supabase/file_tag_service.dart' as supabase_file_tag;
import 'supabase/file_comment_service.dart' as supabase_file_comment;
import 'supabase/file_markup_service.dart' as supabase_file_markup;
import 'supabase/file_event_service.dart' as supabase_file_event;
import 'supabase/custom_field_definition_service.dart'
    as supabase_custom_field_definition;
import 'supabase/plan_service.dart' as supabase_plan;
import 'supabase/floorplan_scene_service.dart' as supabase_floorplan_scene;
import 'supabase/floorplan_generation_service.dart'
    as supabase_floorplan_generation;
import 'ai_floorplan_service.dart' as ai_floorplan;
import 'supabase/asset_service.dart' as supabase_asset;
import 'supabase/skill_service.dart' as supabase_skill;
import 'supabase/customer_service.dart' as supabase_customer;
import 'supabase/customer_tag_service.dart' as supabase_customer_tag;
import 'supabase/customer_type_service.dart' as supabase_customer_type;
import 'supabase/customer_location_service.dart' as supabase_customer_location;
import 'supabase/vendor_type_service.dart' as supabase_vendor_type;
import 'supabase/vendor_service.dart' as supabase_vendor;
import 'supabase/vendor_subdivision_service.dart'
    as supabase_vendor_subdivision;
import 'supabase/client_portal_service.dart' as supabase_client_portal;
import 'supabase/opportunity_service.dart' as supabase_opportunity;
import 'supabase/specification_service.dart' as supabase_specification;
import 'supabase/vendor_portal_service.dart' as supabase_vendor_portal;
import 'supabase/budget_service.dart' as supabase_budget;
import 'supabase/selection_service.dart' as supabase_selection;
import 'supabase/selection_document_service.dart' as supabase_selection_doc;
import 'supabase/work_order_service.dart' as supabase_work_order;
import 'supabase/subcontract_service.dart' as supabase_subcontract;
import 'supabase/budget_template_service.dart' as supabase_budget_template;
import 'supabase/cost_service.dart' as supabase_cost;
import 'supabase/cost_category_service.dart' as supabase_cost_category;
import 'supabase/property_service.dart' as supabase_property;
import 'supabase/area_service.dart' as supabase_area;
import 'supabase/property_contents_service.dart' as supabase_contents;
import 'supabase/property_note_service.dart' as supabase_property_note;
import 'supabase/project_note_service.dart' as supabase_project_note;
import 'supabase/bid_package_service.dart' as supabase_bid_package;
import 'supabase/document_service.dart' as supabase_document;
import 'supabase/document_po_receiving_service.dart'
    as supabase_document_po_receiving;
import 'supabase/document_template_service.dart' as supabase_doc_template;
import 'supabase/form_service.dart' as supabase_form;
import 'supabase/message_service.dart' as supabase_message;
import 'supabase/time_entry_service.dart' as supabase_time_entry;
import 'supabase/time_entry_template_service.dart'
    as supabase_time_entry_template;
import 'supabase/reporting_service.dart' as supabase_reporting;
import 'supabase/dashboard_service.dart' as supabase_dashboard;
import 'supabase/daily_summary_service.dart' as supabase_daily_summary;
import 'supabase/catalog_service.dart' as supabase_catalog;
import 'supabase/vehicle_service.dart' as supabase_vehicle;
import 'supabase/search_service.dart' as supabase_search;
import 'supabase/analytics_service.dart' as supabase_analytics;
import 'supabase/budget_task_link_service.dart' as supabase_budget_task_link;
import 'supabase/capacity_planning_service.dart' as supabase_capacity;
import 'supabase/notification_service.dart' as supabase_notification;
import 'supabase/user_preferences_service.dart' as supabase_user_prefs;
import 'view_prefs_service.dart';
import 'supabase/role_template_service.dart' as supabase_role_template;
import 'supabase/workspace_settings_profile_service.dart'
    as supabase_workspace_settings_profile;
import 'supabase/ai_copilot_service.dart' as supabase_ai_copilot;
import 'supabase/automation_service.dart' as supabase_automation;
import 'supabase/project_template_service.dart' as supabase_project_template;
import 'supabase/task_group_template_service.dart' as supabase_task_group_template;
import 'supabase/workflow_template_service.dart' as supabase_workflow_template;
import 'supabase/feedback_service.dart' as supabase_feedback;
import 'supabase/inventory/inventory_supplier_service.dart'
    as supabase_inv_supplier;
import 'supabase/inventory/inventory_item_service.dart' as supabase_inv_item;
import 'supabase/inventory/inventory_stock_movement_service.dart'
    as supabase_inv_movement;
import 'supabase/inventory/equipment_rental_service.dart'
    as supabase_equipment_rental;
import 'supabase/project_modules/project_modules_services.dart' as pm_svc;
export 'supabase/project_modules/project_modules_services.dart' show
  ProjectWarrantyService, ProjectDailyLogService,
  ProjectInspectionService, ProjectPunchListService;

/// Service locator for the Supabase runtime.
class ServiceLocator {
  ServiceLocator._();

  // ============================================================================
  // Authentication & Users
  // ============================================================================

  static dynamic get authService => supabase_auth.SupabaseAuthService();

  static dynamic get userService => supabase_user.SupabaseUserService();

  static dynamic get workspaceService =>
      supabase_workspace.SupabaseWorkspaceService();

  static dynamic get workspaceMemberService =>
      supabase_member.SupabaseWorkspaceMemberService();

  static dynamic get roleTemplateService =>
      supabase_role_template.SupabaseRoleTemplateService();

  static dynamic get workspaceSettingsProfileService =>
      supabase_workspace_settings_profile.SupabaseWorkspaceSettingsProfileService();

  static dynamic get invitationService =>
      supabase_invitation.SupabaseInvitationService();

  // ============================================================================
  // Projects & Tasks
  // ============================================================================

  static dynamic get projectService =>
      supabase_project.SupabaseProjectService();

  static supabase_selection.SupabaseSelectionService get selectionService =>
      supabase_selection.SupabaseSelectionService();

  static supabase_selection_doc.SelectionDocumentService
      get selectionDocumentService =>
          supabase_selection_doc.SelectionDocumentService();

  static supabase_work_order.SupabaseWorkOrderService get workOrderService =>
      supabase_work_order.SupabaseWorkOrderService();

  static supabase_subcontract.SupabaseSubcontractService get subcontractService =>
      supabase_subcontract.SupabaseSubcontractService();

  static dynamic get taskService => supabase_task.SupabaseTaskService();

  static supabase_schedule_baseline.ScheduleBaselineService
  get scheduleBaselineService =>
      supabase_schedule_baseline.ScheduleBaselineService();

  static dynamic get taskCommentService =>
      supabase_task_comment.SupabaseTaskCommentService();

  static dynamic get planService => supabase_plan.SupabasePlanService();

  static supabase_floorplan_scene.SupabaseFloorplanSceneService
  get floorplanSceneService =>
      supabase_floorplan_scene.SupabaseFloorplanSceneService();

  static supabase_floorplan_generation.SupabaseFloorplanGenerationService
  get floorplanGenerationService =>
      supabase_floorplan_generation.SupabaseFloorplanGenerationService();

  static ai_floorplan.AiFloorplanService get aiFloorplanService =>
      ai_floorplan.AiFloorplanService();

  /// Asset service requires workspaceId - use assetServiceFor() instead
  static supabase_asset.SupabaseAssetService assetServiceFor(
    String workspaceId,
  ) => supabase_asset.SupabaseAssetService(workspaceId: workspaceId);

  static dynamic get skillService => supabase_skill.SupabaseSkillService();

  static supabase_project_template.SupabaseProjectTemplateService
  get projectTemplateService =>
      supabase_project_template.SupabaseProjectTemplateService();

  static supabase_task_group_template.SupabaseTaskGroupTemplateService
  get taskGroupTemplateService =>
      supabase_task_group_template.SupabaseTaskGroupTemplateService();

  static supabase_workflow_template.SupabaseWorkflowTemplateService
  get workflowTemplateService =>
      supabase_workflow_template.SupabaseWorkflowTemplateService();

  // ============================================================================
  // Storage
  // ============================================================================

  static dynamic get storageService =>
      supabase_storage.SupabaseStorageService();

  static dynamic get folderService => supabase_folder.SupabaseFolderService();

  static supabase_file_tag.SupabaseFileTagService get fileTagService =>
      supabase_file_tag.SupabaseFileTagService();

  static supabase_file_comment.SupabaseFileCommentService
  get fileCommentService =>
      supabase_file_comment.SupabaseFileCommentService();

  static supabase_file_markup.SupabaseFileMarkupService get fileMarkupService =>
      supabase_file_markup.SupabaseFileMarkupService();

  static supabase_file_event.SupabaseFileEventService get fileEventService =>
      supabase_file_event.SupabaseFileEventService();

  static supabase_custom_field_definition.SupabaseCustomFieldDefinitionService
  get customFieldDefinitionService =>
      supabase_custom_field_definition.SupabaseCustomFieldDefinitionService();

  // ============================================================================
  // CRM
  // ============================================================================

  static dynamic get customerService =>
      supabase_customer.SupabaseCustomerService();

  static dynamic get customerTagService =>
      supabase_customer_tag.SupabaseCustomerTagService();

  static supabase_customer_type.SupabaseCustomerTypeService
  get customerTypeService =>
      supabase_customer_type.SupabaseCustomerTypeService();

  static supabase_vendor_type.SupabaseVendorTypeService get vendorTypeService =>
      supabase_vendor_type.SupabaseVendorTypeService();

  static supabase_customer_location.SupabaseCustomerLocationService
  get customerLocationService =>
      supabase_customer_location.SupabaseCustomerLocationService();

  static supabase_vendor_subdivision.SupabaseVendorSubdivisionService
  get vendorSubdivisionService =>
      supabase_vendor_subdivision.SupabaseVendorSubdivisionService();

  static dynamic get vendorService => supabase_vendor.SupabaseVendorService();

  static dynamic get clientPortalService =>
      supabase_client_portal.SupabaseClientPortalService();

  static supabase_vendor_portal.SupabaseVendorPortalService
  get vendorPortalService =>
      supabase_vendor_portal.SupabaseVendorPortalService();

  static supabase_opportunity.SupabaseOpportunityService get opportunityService =>
      supabase_opportunity.SupabaseOpportunityService();

  static supabase_specification.SupabaseSpecificationService
      get specificationService =>
          supabase_specification.SupabaseSpecificationService();

  // ============================================================================
  // Financial
  // ============================================================================

  static dynamic get budgetService => supabase_budget.SupabaseBudgetService();

  static dynamic get budgetTemplateService =>
      supabase_budget_template.SupabaseBudgetTemplateService();

  static dynamic get costService => supabase_cost.SupabaseCostService();

  static dynamic get costCategoryService =>
      supabase_cost_category.SupabaseCostCategoryService();


  static supabase_budget_task_link.SupabaseBudgetTaskLinkService
  get budgetTaskLinkService =>
      supabase_budget_task_link.SupabaseBudgetTaskLinkService();

  // ============================================================================
  // Property / Restoration
  // ============================================================================

  static dynamic get propertyService =>
      supabase_property.SupabasePropertyService();

  static dynamic get areaService => supabase_area.SupabaseAreaService();

  static dynamic get propertyContentsService =>
      supabase_contents.SupabasePropertyContentsService();

  static dynamic get propertyNoteService =>
      supabase_property_note.SupabasePropertyNoteService();

  static supabase_project_note.SupabaseProjectNoteService
  get projectNoteService => supabase_project_note.SupabaseProjectNoteService();

  // ============================================================================
  // Documents
  // ============================================================================

  static dynamic get documentService =>
      supabase_document.SupabaseDocumentService();

  static supabase_document_po_receiving.DocumentPoReceivingService
      get documentPoReceivingService =>
          supabase_document_po_receiving.DocumentPoReceivingService();

  static supabase_bid_package.BidPackageService get bidPackageService =>
      supabase_bid_package.BidPackageService();

  static dynamic get documentTemplateService =>
      supabase_doc_template.SupabaseDocumentTemplateService();

  static dynamic get formService => supabase_form.SupabaseFormService();

  static supabase_field_form.FieldFormService get fieldFormService =>
      supabase_field_form.FieldFormService();

  // ============================================================================
  // Messaging
  // ============================================================================

  static supabase_message.SupabaseMessageService get messageService =>
      supabase_message.SupabaseMessageService();

  // ============================================================================
  // Time & Reporting
  // ============================================================================

  static dynamic get timeEntryService =>
      supabase_time_entry.SupabaseTimeEntryService();

  static dynamic get timeEntryTemplateService =>
      supabase_time_entry_template.SupabaseTimeEntryTemplateService();

  static dynamic get reportingService =>
      supabase_reporting.SupabaseReportingService();

  static dynamic get dashboardService =>
      supabase_dashboard.SupabaseDashboardService();

  static supabase_capacity.SupabaseCapacityPlanningService
  get capacityPlanningService =>
      supabase_capacity.SupabaseCapacityPlanningService();

  static dynamic get dailySummaryService =>
      supabase_daily_summary.SupabaseDailySummaryService();

  // ============================================================================
  // Supporting
  // ============================================================================

  static dynamic get catalogService =>
      supabase_catalog.SupabaseCatalogService();

  static supabase_vehicle.SupabaseVehicleService vehicleServiceFor(
    String workspaceId,
  ) {
    // Vehicle service requires workspace ID in constructor
    return supabase_vehicle.SupabaseVehicleService(workspaceId: workspaceId);
  }

  static dynamic get searchService => supabase_search.SupabaseSearchService();

  static dynamic get analyticsService =>
      supabase_analytics.SupabaseAnalyticsService();


  static dynamic get aiCopilotService =>
      supabase_ai_copilot.SupabaseAiCopilotService();

  static dynamic get automationService =>
      supabase_automation.SupabaseAutomationService();


  // ============================================================================
  // Notifications
  // ============================================================================

  static supabase_notification.SupabaseNotificationService
  get notificationService =>
      supabase_notification.SupabaseNotificationService();

  // ============================================================================
  // User Preferences
  // ============================================================================

  static supabase_user_prefs.SupabaseUserPreferencesService
  get userPreferencesService =>
      supabase_user_prefs.SupabaseUserPreferencesService();

  /// Singleton — holds in-memory cache, debounce timers, and per-user state.
  static final SupabaseViewPrefsService _viewPrefsService =
      SupabaseViewPrefsService();

  static SupabaseViewPrefsService get viewPrefsService => _viewPrefsService;

  // ============================================================================
  // Feedback
  // ============================================================================

  static supabase_feedback.SupabaseFeedbackService get feedbackService =>
      supabase_feedback.SupabaseFeedbackService();

  // ============================================================================
  // Inventory (consumables + suppliers + purchase orders + equipment rentals)
  // ============================================================================

  static supabase_inv_supplier.SupabaseInventorySupplierService
      inventorySupplierServiceFor(String workspaceId) =>
          supabase_inv_supplier.SupabaseInventorySupplierService(
            workspaceId: workspaceId,
          );

  static supabase_inv_item.SupabaseInventoryItemService inventoryItemServiceFor(
    String workspaceId,
  ) =>
      supabase_inv_item.SupabaseInventoryItemService(workspaceId: workspaceId);

  static supabase_inv_movement.SupabaseInventoryStockMovementService
      inventoryStockMovementServiceFor(String workspaceId) =>
          supabase_inv_movement.SupabaseInventoryStockMovementService(
            workspaceId: workspaceId,
          );

  static supabase_equipment_rental.SupabaseEquipmentRentalService
      equipmentRentalServiceFor(String workspaceId) =>
          supabase_equipment_rental.SupabaseEquipmentRentalService(
            workspaceId: workspaceId,
          );

  // ============================================================================
  // Project modules (warranties, daily logs, inspections, punch lists)
  // ============================================================================
  static pm_svc.ProjectWarrantyService projectWarrantyServiceFor({
    required String workspaceId, required String projectId,
  }) => pm_svc.ProjectWarrantyService(
    workspaceId: workspaceId, projectId: projectId);

  static pm_svc.ProjectDailyLogService projectDailyLogServiceFor({
    required String workspaceId, required String projectId,
  }) => pm_svc.ProjectDailyLogService(
    workspaceId: workspaceId, projectId: projectId);

  static pm_svc.ProjectInspectionService projectInspectionServiceFor({
    required String workspaceId, required String projectId,
  }) => pm_svc.ProjectInspectionService(
    workspaceId: workspaceId, projectId: projectId);

  static pm_svc.ProjectPunchListService projectPunchListServiceFor({
    required String workspaceId, required String projectId,
  }) => pm_svc.ProjectPunchListService(
    workspaceId: workspaceId, projectId: projectId);

}
