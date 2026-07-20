import '../screens/home/dashboard_widget_catalog.dart';

/// Abstract interface for a widget catalog that provides metadata
/// for a customizable widget grid (dashboard, project overview, etc.).
abstract class WidgetCatalogProvider {
  /// Default widget order for fresh/reset state.
  List<String> get defaultOrder;

  /// Widget IDs hidden by default on fresh/reset state.
  List<String> get defaultHidden => const [];

  /// Map of widget ID → display label.
  Map<String, String> get labels;

  /// Returns metadata for a given widget ID.
  DashboardWidgetMeta metaFor(String id);
}
