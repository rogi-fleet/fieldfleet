import 'package:flutter/widgets.dart';

/// Owns the [TransformationController] for the floorplan canvas and
/// exposes imperative zoom commands so out-of-canvas UI (status bar
/// buttons, future keyboard shortcuts) can drive the same view.
///
/// Anchors zoom at the viewport center when the canvas has reported its
/// size; otherwise falls back to the matrix origin.
class FloorplanViewportController {
  static const double minScale = 0.1;
  static const double maxScale = 8.0;
  static const double _step = 1.25;

  final TransformationController transform = TransformationController();

  Size _viewportSize = Size.zero;

  /// Called by the canvas as it lays out so zoom buttons can anchor at
  /// the visible center instead of the matrix origin.
  void setViewportSize(Size size) {
    _viewportSize = size;
  }

  double get scale => transform.value.getMaxScaleOnAxis();

  void zoomIn() => _scaleBy(_step);
  void zoomOut() => _scaleBy(1 / _step);

  void _scaleBy(double factor) {
    final current = scale;
    final target = (current * factor).clamp(minScale, maxScale);
    final applied = target / current;
    if ((applied - 1.0).abs() < 1e-4) return;

    final focal = _viewportSize == Size.zero
        ? Offset.zero
        : Offset(_viewportSize.width / 2, _viewportSize.height / 2);

    final pre = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(applied, applied, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
    transform.value = pre.multiplied(transform.value);
  }

  /// Fit a scene of the given size into the current viewport, centered.
  /// No-op until [setViewportSize] has been called at least once.
  void fitToScene(double sceneWidth, double sceneHeight) {
    if (_viewportSize == Size.zero ||
        sceneWidth <= 0 ||
        sceneHeight <= 0) {
      return;
    }
    const padding = 32.0;
    final available = Size(
      (_viewportSize.width - padding * 2).clamp(1.0, double.infinity),
      (_viewportSize.height - padding * 2).clamp(1.0, double.infinity),
    );
    final fit = (available.width / sceneWidth)
        .clamp(minScale, maxScale)
        .toDouble();
    final fitH = (available.height / sceneHeight)
        .clamp(minScale, maxScale)
        .toDouble();
    final s = fit < fitH ? fit : fitH;
    final tx = (_viewportSize.width - sceneWidth * s) / 2;
    final ty = (_viewportSize.height - sceneHeight * s) / 2;
    transform.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  void resetView() {
    transform.value = Matrix4.identity();
  }

  void dispose() {
    transform.dispose();
  }
}
