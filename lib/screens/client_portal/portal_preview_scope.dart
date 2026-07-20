import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/theme.dart';

/// Provides the optional "preview as customer" id (a customer UUID) to portal
/// screens. When non-null, portal RPCs are called with the preview parameter
/// so a workspace member can see what that customer would see.
///
/// Placed at each portal route builder by reading `?preview=<uuid>` from the
/// route URI.
class PortalPreviewScope extends InheritedWidget {
  final String? previewCustomerId;

  const PortalPreviewScope({
    super.key,
    required this.previewCustomerId,
    required super.child,
  });

  bool get isPreview => previewCustomerId != null && previewCustomerId!.isNotEmpty;

  static String? of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PortalPreviewScope>();
    final id = scope?.previewCustomerId;
    return (id != null && id.isNotEmpty) ? id : null;
  }

  /// Convenience wrapper for portal route builders.
  static Widget wrapRoute(BuildContext context, GoRouterState state, Widget child) {
    final preview = state.uri.queryParameters['preview'];
    return PortalPreviewScope(
      previewCustomerId: preview,
      child: child,
    );
  }

  /// Append `?preview=<id>` to a portal path when in preview mode. Use when
  /// navigating between portal screens inside a preview session so the mode
  /// is preserved.
  static String appendPreview(BuildContext context, String path) {
    final id = of(context);
    if (id == null) return path;
    final sep = path.contains('?') ? '&' : '?';
    return '$path${sep}preview=$id';
  }

  @override
  bool updateShouldNotify(PortalPreviewScope oldWidget) =>
      oldWidget.previewCustomerId != previewCustomerId;
}

/// Yellow banner shown atop portal screens when previewing as a customer.
class PortalPreviewBanner extends StatelessWidget {
  final String? customerName;
  const PortalPreviewBanner({super.key, this.customerName});

  @override
  Widget build(BuildContext context) {
    final preview = PortalPreviewScope.of(context);
    if (preview == null) return const SizedBox.shrink();

    return Material(
      color: const Color(0xFFFFF4CE),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
          child: Row(
            children: [
              const Icon(Icons.visibility, size: 18, color: Color(0xFF8A6D00)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  customerName == null
                      ? 'Preview mode — you are viewing the portal as this customer.'
                      : 'Preview mode — viewing the portal as $customerName.',
                  style: const TextStyle(
                    color: Color(0xFF6B5400),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Exit preview',
                    style: TextStyle(color: Color(0xFF8A6D00))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
