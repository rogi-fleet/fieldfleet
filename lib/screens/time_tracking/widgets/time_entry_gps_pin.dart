import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/theme.dart';
import '../../../widgets/adaptive_map_widget.dart';

/// Small location-pin icon that, on hover or tap, reveals a mini map preview
/// of the GPS coordinates captured for a clock in/out punch.
class TimeEntryGpsPin extends StatefulWidget {
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final double? distanceFromProjectMeters;
  final String label;
  final double iconSize;
  final Color? iconColor;

  const TimeEntryGpsPin({
    super.key,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.distanceFromProjectMeters,
    required this.label,
    this.iconSize = 14,
    this.iconColor,
  });

  bool get _hasLocation => latitude != null && longitude != null;

  @override
  State<TimeEntryGpsPin> createState() => _TimeEntryGpsPinState();
}

class _TimeEntryGpsPinState extends State<TimeEntryGpsPin> {
  final OverlayPortalController _controller = OverlayPortalController();
  final LayerLink _link = LayerLink();
  Timer? _hideTimer;

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && _controller.isShowing) _controller.hide();
    });
  }

  void _cancelHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _show() {
    _cancelHide();
    if (!_controller.isShowing) _controller.show();
  }

  void _toggle() {
    if (_controller.isShowing) {
      _cancelHide();
      _controller.hide();
    } else {
      _show();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget._hasLocation) return const SizedBox.shrink();

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: _buildOverlay,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _show(),
          onExit: (_) => _scheduleHide(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                Icons.location_on_outlined,
                size: widget.iconSize,
                color: widget.iconColor ?? AppColors.info,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return Positioned(
      width: 280,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        offset: const Offset(0, 8),
        followerAnchor: Alignment.topCenter,
        targetAnchor: Alignment.bottomCenter,
        child: TapRegion(
          onTapOutside: (_) {
            if (_controller.isShowing) _controller.hide();
          },
          child: MouseRegion(
            onEnter: (_) => _cancelHide(),
            onExit: (_) => _scheduleHide(),
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.cardBorder),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  color: Theme.of(context).colorScheme.surface,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    AdaptiveMapWidget(
                      latitude: widget.latitude!,
                      longitude: widget.longitude!,
                      height: 160,
                      zoom: 16,
                      markerTitle: widget.label,
                    ),
                    if (widget.accuracyMeters != null ||
                        widget.distanceFromProjectMeters != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.accuracyMeters != null)
                              Text(
                                'Accuracy: ±${widget.accuracyMeters!.toStringAsFixed(0)} m',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            if (widget.distanceFromProjectMeters != null)
                              Text(
                                '${_formatDistance(widget.distanceFromProjectMeters!)} from job site',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }
}
