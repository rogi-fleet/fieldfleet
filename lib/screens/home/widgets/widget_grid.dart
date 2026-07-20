import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/widget_grid_layout.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';
import '../dashboard_edit_controller.dart';
import '../dashboard_widget_catalog.dart';
import 'dashboard_widget_wrapper.dart';

/// User-preference key for the v3 edit-mode coach mark "seen" ack. The `_v2`
/// suffix re-shows the banner once for users who dismissed the original —
/// the editing interactions changed (immediate drag handle) and the copy
/// with them.
const String _kEditCoachSeenKey = 'dashboard_v3_edit_coach_seen_v2';

/// Which corner a resize handle is anchored to. The opposite corner stays
/// fixed during the drag; e.g. dragging the top-left grows the widget upward
/// and leftward (subject to grid bounds + auto-compaction).
enum _ResizeCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Drag-anchor strategy that places the compact feedback card centered under
/// the cursor. The feedback (icon + label) is approximately 160×34px; we
/// return a fixed offset close to its center rather than mirroring the grab
/// point from the much larger source cell.
Offset _centerFeedbackOnPointer(
  Draggable<Object> draggable,
  BuildContext context,
  Offset position,
) {
  return const Offset(80, 17);
}

/// v3 dashboard grid with drag-to-reposition and corner-handle resize.
///
/// In view mode this is a pure renderer that places widgets at their declared
/// (x, y, w, h) on the responsive 12/8/4-column grid. In edit mode each cell
/// becomes a [LongPressDraggable] (drag to move) with a corner resize handle
/// and a remove (X) button overlay. Vertical compaction runs after every move
/// or resize so the layout never accumulates gaps.
class WidgetGrid extends StatefulWidget {
  final DashboardEditController controller;
  final double rowHeight;
  final double gap;
  final Widget Function(String widgetId) widgetBuilder;

  const WidgetGrid({
    super.key,
    required this.controller,
    required this.widgetBuilder,
    this.rowHeight = 56,
    this.gap = 16,
  });

  @override
  State<WidgetGrid> createState() => _WidgetGridState();
}

class _WidgetGridState extends State<WidgetGrid> {
  final GlobalKey _gridKey = GlobalKey();

  // Drag state
  String? _dragId;
  WidgetPlacement? _dragOrigin;
  Offset? _dragStartGlobal;
  Offset? _lastPointerDownGlobal;
  int? _dragTargetX;
  int? _dragTargetY;

  // Resize state
  String? _resizeId;
  WidgetPlacement? _resizeOrigin;
  Offset? _resizeStartGlobal;
  _ResizeCorner? _resizeCorner;
  // Full target rect during resize — corners other than BR change x/y as well.
  int? _resizeTargetX;
  int? _resizeTargetY;
  int? _resizeTargetW;
  int? _resizeTargetH;
  // True while the drag is asking for less (min) or more (max) than the
  // catalog allows on an axis (the clamp in _applyResizeDelta is actively
  // holding the edge). Drives the constrained state of the resize chip +
  // cell border.
  bool _resizeAtMinW = false;
  bool _resizeAtMinH = false;
  bool _resizeAtMaxW = false;
  bool _resizeAtMaxH = false;

  // Auto-scroll heartbeat — fires while dragging near the viewport edge.
  Timer? _scrollTimer;
  double _scrollVelocity = 0;

  // Currently keyboard-focused widget id (for arrow-key nudges in edit mode).
  String? _focusedId;

  // Measured intrinsic content height (px) for cells whose meta declares
  // [DashboardWidgetMeta.autoHeight], stored alongside the cell width the
  // measurement was taken at. Populated by [_AutoHeightCell] after each layout
  // pass; consumed by [_applyAutoHeights] to shrink the cell's `h` so
  // variable-content widgets don't leave trailing dead space inside their grid
  // slot. View-mode only — edit mode keeps the declared `h` so the user can
  // see and adjust the row-aligned slot. Width is tracked so the grow-only
  // floor only applies when the cell width matches: when the user resizes the
  // viewport (or crosses a breakpoint) the prior measurement is stale and any
  // new value should be accepted, even if smaller.
  final Map<String, ({double h, double w})> _measuredAutoHeights = {};

  void _resetDragState() {
    _stopAutoScroll();
    setState(() {
      _dragId = null;
      _dragOrigin = null;
      _dragStartGlobal = null;
      _dragTargetX = null;
      _dragTargetY = null;
    });
  }

  void _resetResizeState() {
    setState(() {
      _resizeId = null;
      _resizeOrigin = null;
      _resizeStartGlobal = null;
      _resizeCorner = null;
      _resizeTargetX = null;
      _resizeTargetY = null;
      _resizeTargetW = null;
      _resizeTargetH = null;
      _resizeAtMinW = false;
      _resizeAtMinH = false;
      _resizeAtMaxW = false;
      _resizeAtMaxH = false;
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Auto-scroll while dragging near the viewport edge
  // ---------------------------------------------------------------------------

  /// Scroll edge band — within this many px of viewport top/bottom, we
  /// auto-scroll while a drag is in progress.
  static const double _autoScrollBand = 80;
  static const double _autoScrollMaxSpeed = 12; // px per tick

  void _startAutoScroll() {
    if (_scrollTimer != null) return;
    _scrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _onAutoScrollTick(),
    );
  }

  void _stopAutoScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _scrollVelocity = 0;
  }

  void _onAutoScrollTick() {
    // Defensive: the timer can fire after the widget has unmounted (e.g. user
    // navigates away mid-drag). Touching `context` after dispose throws.
    if (!mounted) {
      _stopAutoScroll();
      return;
    }
    if (_dragId == null || _scrollVelocity == 0) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    final pos = scrollable.position;
    final newPixels = (pos.pixels + _scrollVelocity)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (newPixels != pos.pixels) {
      pos.jumpTo(newPixels);
    }
  }

  void _updateAutoScrollVelocity(Offset globalCursor) {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) {
      _scrollVelocity = 0;
      return;
    }
    final viewportBox = scrollable.context.findRenderObject() as RenderBox?;
    if (viewportBox == null) {
      _scrollVelocity = 0;
      return;
    }
    final localInViewport = viewportBox.globalToLocal(globalCursor);
    final h = viewportBox.size.height;
    if (localInViewport.dy < _autoScrollBand) {
      final t = 1 - (localInViewport.dy / _autoScrollBand).clamp(0.0, 1.0);
      _scrollVelocity = -_autoScrollMaxSpeed * t;
    } else if (localInViewport.dy > h - _autoScrollBand) {
      final t =
          ((localInViewport.dy - (h - _autoScrollBand)) / _autoScrollBand)
              .clamp(0.0, 1.0);
      _scrollVelocity = _autoScrollMaxSpeed * t;
    } else {
      _scrollVelocity = 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Handles grid-wide shortcuts (undo, escape) for any focused descendant.
      // Per-cell arrow-key navigation lives on _KeyboardEditable's Focus and
      // is consumed there before bubbling up to here.
      onKeyEvent: _handleGlobalKey,
      child: LayoutBuilder(
        builder: (context, outerConstraints) {
          final breakpoint = widget.controller.previewBreakpoint ??
              GridBreakpoint.forWidth(outerConstraints.maxWidth);

          final isPreview = widget.controller.previewBreakpoint != null;
          final canvasWidth = isPreview
              ? _previewCanvasWidth(breakpoint, outerConstraints.maxWidth)
              : outerConstraints.maxWidth;

          Widget grid = LayoutBuilder(
            builder: (context, constraints) =>
                _buildGridCanvas(constraints, breakpoint),
          );
          if (isPreview) {
            grid = Center(
              child: _PreviewFrame(
                breakpoint: breakpoint,
                child: SizedBox(width: canvasWidth, child: grid),
              ),
            );
          }
          return grid;
        },
      ),
    );
  }

  /// Grid-level shortcuts: Cmd/Ctrl+Z undoes; Escape cancels the active
  /// drag/resize, or exits edit mode if nothing is being manipulated.
  KeyEventResult _handleGlobalKey(FocusNode _, KeyEvent event) {
    if (!widget.controller.editMode) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final isUndoChord = (keys.isMetaPressed || keys.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyZ;
    if (isUndoChord) {
      if (widget.controller.canUndo) widget.controller.undo();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_dragId != null) {
        _resetDragState();
        return KeyEventResult.handled;
      }
      if (_resizeId != null) {
        _resetResizeState();
        return KeyEventResult.handled;
      }
      widget.controller.toggleEditMode();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Typical canvas width per device class. When the previewed breakpoint
  /// matches the actual viewport's breakpoint we use the full available
  /// width — otherwise "Desktop preview" on a 1920px screen would render at
  /// 1280px, looking artificially condensed compared to auto mode.
  double _previewCanvasWidth(GridBreakpoint bp, double available) {
    final actualBp = GridBreakpoint.forWidth(available);
    if (bp == actualBp) return available;
    final desired = switch (bp) {
      GridBreakpoint.mobile => 390.0,
      GridBreakpoint.tablet => 820.0,
      GridBreakpoint.desktop => 1280.0,
    };
    return desired.clamp(280.0, available);
  }

  Widget _buildGridCanvas(
    BoxConstraints constraints,
    GridBreakpoint breakpoint,
  ) {
    final savedLayout = widget.controller.gridLayoutFor(breakpoint);

    if (savedLayout.placements.isEmpty && !widget.controller.editMode) {
      return const SizedBox.shrink();
    }

    // Apply autoHeight overrides (view-mode only, no-op until measurements
    // arrive) before computing any positions, so cells below an autoHeight
    // widget pull up to fill its trailing gap.
    final liveLayout = _applyAutoHeights(savedLayout);

    final columns = liveLayout.columns;
    final cellWidth =
        (constraints.maxWidth - widget.gap * (columns - 1)) / columns;

    // Live push preview: when the user is dragging or resizing, simulate
    // the operation against the current layout to see where every widget
    // would land. Render each cell at its previewed position via
    // AnimatedPositioned so the reflow animates smoothly.
    final previewLayout = _computePreviewLayout(liveLayout);

    // View mode packs cells masonry-style: each cell sits directly under the
    // previous cell's *measured* content bottom (not its row-aligned slot
    // bottom), which eliminates the row-rounding dead space that otherwise
    // showed up as visible grey gaps below autoHeight widgets. Edit mode
    // keeps the row-aligned slot grid so drop zones stay readable.
    final masonry = widget.controller.editMode
        ? null
        : _computeMasonryTops(previewLayout, cellWidth);

    final extraRows = widget.controller.editMode ? 2 : 0;
    final renderRows = previewLayout.rows + extraRows;
    final totalHeight = masonry != null
        ? masonry.totalHeight
        : (renderRows == 0
            ? 0.0
            : renderRows * widget.rowHeight +
                (renderRows - 1).clamp(0, 9999) * widget.gap);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.controller.editMode) const _EditCoachMark(),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: totalHeight,
            width: constraints.maxWidth,
            child: Stack(
              key: _gridKey,
              clipBehavior: Clip.none,
              children: [
                if (widget.controller.editMode)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _GridLinesPainter(
                          columns: columns,
                          rows: renderRows,
                          cellWidth: cellWidth,
                          rowHeight: widget.rowHeight,
                          gap: widget.gap,
                          // Theme-aware contrast: dots need to be visible on
                          // both the light dashboard background and any dark
                          // theme. Primary at 18% disappeared on light/grey.
                          color: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? Colors.white.withValues(alpha: 0.22)
                              : AppColors.primary.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
                if (widget.controller.editMode)
                  _buildDropZoneHints(
                    layoutRows: previewLayout.rows,
                    extraRows: extraRows,
                    columns: columns,
                    cellWidth: cellWidth,
                  ),
                if (widget.controller.editMode)
                  _buildDragTarget(
                    breakpoint: breakpoint,
                    cellWidth: cellWidth,
                    columns: columns,
                  ),
                for (final placement in liveLayout.placements)
                  _buildAnimatedCell(
                    originalId: placement.id,
                    renderPlacement:
                        previewLayout.placementOf(placement.id) ?? placement,
                    cellWidth: cellWidth,
                    breakpoint: breakpoint,
                    masonryOverride: masonry?.overrides[placement.id],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Records a measured intrinsic height (px) and the cell width it was taken
  /// at, for an autoHeight cell. Schedules a setState on the next frame so
  /// the layout can be recomputed.
  ///
  /// **Width-aware grow-only:** at the same cell width, smaller follow-up
  /// measurements are ignored — async builders (StreamBuilder/FutureBuilder)
  /// sometimes under-report intrinsic during a loading frame and then
  /// "shrink back" when the next snapshot arrives, and without a floor the
  /// slot collapses while the content keeps painting larger. When the cell
  /// width *changes* (responsive resize, breakpoint crossing) the prior
  /// measurement is stale — content reflows to different line counts — so we
  /// accept any new value, including smaller ones. Bails when both height
  /// and width are unchanged within a half-pixel to avoid feedback loops.
  void _onAutoHeightMeasured(String id, double pixelHeight, double cellWidth) {
    final prior = _measuredAutoHeights[id];
    if (prior != null) {
      final sameWidth = (prior.w - cellWidth).abs() < 1.0;
      if (sameWidth) {
        if ((prior.h - pixelHeight).abs() < 0.5) return;
        if (pixelHeight < prior.h) return; // grow-only at same width
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _measuredAutoHeights[id] = (h: pixelHeight, w: cellWidth);
      });
    });
  }

  /// Shrinks `h` on autoHeight cells to the row count that fits their measured
  /// content, then compacts the layout so cells below pull up to close the
  /// gap. No-ops in edit mode (the user is laying out the dashboard and needs
  /// to see fixed row-aligned slots) and on the first frame before any
  /// measurement has come in.
  WidgetGridLayout _applyAutoHeights(WidgetGridLayout layout) {
    if (widget.controller.editMode) return layout;
    if (_measuredAutoHeights.isEmpty) return layout;
    var changed = false;
    final adjusted = layout.placements.map((p) {
      final meta = widget.controller.catalog.metaFor(p.id);
      final measured = _measuredAutoHeights[p.id]?.h;
      // A user-set height opts the cell out of autoHeight entirely — the
      // saved slot is rendered fixed (scrolling internally on overflow), so
      // growing a feed past its content no longer snaps back.
      if (!meta.autoHeight || measured == null || p.userSizedH) return p;
      // Convert intrinsic px → row units. The +gap on the numerator absorbs
      // the inter-cell gap into the trailing row so a 120px cell at
      // rowHeight=64/gap=16 lands at h=2 (128px) rather than h=3. Grow as
      // well as shrink — the cell renders at intrinsic in view mode, so the
      // override must match it or subsequent cells will overlap.
      final desiredH = ((measured + widget.gap) /
              (widget.rowHeight + widget.gap))
          .ceil()
          .clamp(meta.minH, meta.maxH ?? 9999);
      if (desiredH == p.h) return p;
      changed = true;
      return p.copyWith(h: desiredH);
    }).toList(growable: false);
    if (!changed) return layout;
    return WidgetGridLayout(
      breakpoint: layout.breakpoint,
      placements: adjusted,
    ).compacted();
  }

  /// Pinterest-style masonry packing for view mode.
  ///
  /// Two passes of "tighten" run on top of strict reading order:
  ///
  /// 1. **Fill-gap:** when about to place the natural next widget, scan later
  ///    in the queue for any candidate that fits inside the column gap above
  ///    natural without pushing it down. The first such filler gets hoisted
  ///    up. Keeps reorder shock minimal — order is only disturbed when doing
  ///    so closes a real gap.
  /// 2. **Auto-shrink:** when a full-width widget would land on an imbalanced
  ///    column stack (one column ≥ 100 px taller than the other), the packer
  ///    drops it to half-width in the shorter column instead. The widget's
  ///    declared full width is preserved in saved storage and in edit mode;
  ///    only view-mode rendering uses the narrower span. This closes the
  ///    structural gap that fill-gap alone can't reach when no narrower
  ///    candidate exists later in the queue.
  ///
  /// autoHeight cells use their measured intrinsic height (the probe in
  /// [_AutoHeightCell] reports it); fixed-height cells keep their row-aligned
  /// slot height so non-autoHeight widgets still render at the size their
  /// declared `h` asks for.
  ({
    Map<String, ({double top, double left, double width})> overrides,
    double totalHeight,
  }) _computeMasonryTops(WidgetGridLayout layout, double cellWidth) {
    final columns = layout.columns;
    final columnsTops = List<double>.filled(columns, 0.0);
    final sorted = [...layout.placements]
      ..sort((a, b) {
        final dy = a.y.compareTo(b.y);
        if (dy != 0) return dy;
        return a.x.compareTo(b.x);
      });

    double topForSpan(int x, int w) {
      var t = 0.0;
      for (var c = x; c < x + w; c++) {
        if (columnsTops[c] > t) t = columnsTops[c];
      }
      return t;
    }

    double heightOf(WidgetPlacement p) {
      final meta = widget.controller.catalog.metaFor(p.id);
      final measured = _measuredAutoHeights[p.id]?.h;
      // User-sized heights render as fixed slots, so pack with the slot
      // height even when a (stale) intrinsic measurement exists.
      return (meta.autoHeight && measured != null && !p.userSizedH)
          ? measured
          : p.h * widget.rowHeight + (p.h - 1) * widget.gap;
    }

    /// Drops a full-width widget into the shorter half of the grid when the
    /// column stacks are visibly imbalanced. Threshold (100 px) is high
    /// enough that small uneven stacks render at the user's declared size.
    (int x, int w) chooseSize(WidgetPlacement p) {
      if (p.w < columns) return (p.x, p.w);
      // A width the user set explicitly is rendered as saved — auto-shrink
      // exists to fix scaler-derived widths, not to override intent.
      if (p.userSizedW) return (p.x, p.w);
      final meta = widget.controller.catalog.metaFor(p.id);
      final halfW = columns ~/ 2;
      if (meta.minW > halfW) return (p.x, p.w);
      final natTop = topForSpan(p.x, p.w);
      final minTop =
          columnsTops.fold<double>(natTop, (m, v) => v < m ? v : m);
      if (natTop - minTop < 100) return (p.x, p.w);
      final leftTop = topForSpan(0, halfW);
      final rightTop = topForSpan(halfW, columns - halfW);
      return leftTop <= rightTop
          ? (0, halfW)
          : (halfW, columns - halfW);
    }

    // First pass: grid-unit placements (auto-shrink, fill-gap, masonry).
    final gridOverrides = <String, ({double top, int x, int w})>{};
    final remaining = sorted.toList();

    while (remaining.isNotEmpty) {
      final natural = remaining.first;
      final (natX, natW) = chooseSize(natural);
      final naturalTop = topForSpan(natX, natW);

      // Search later in the queue for a filler that slots into the column
      // gap above [natural] without pushing it lower. Filler candidates also
      // get chooseSize so a later full-width widget can squeeze into the gap
      // as a half-width drop. First fit wins — earliest fill keeps order
      // closest to the user's intent.
      var placeIdx = 0;
      var placeX = natX;
      var placeW = natW;
      for (var i = 1; i < remaining.length; i++) {
        final candidate = remaining[i];
        final (candX, candW) = chooseSize(candidate);
        final candTop = topForSpan(candX, candW);
        if (candTop >= naturalTop) continue;
        final candHeight = heightOf(candidate);
        if (candTop + candHeight + widget.gap > naturalTop) continue;
        placeIdx = i;
        placeX = candX;
        placeW = candW;
        break;
      }

      final toPlace = remaining.removeAt(placeIdx);
      final top = topForSpan(placeX, placeW);
      gridOverrides[toPlace.id] = (top: top, x: placeX, w: placeW);
      final newTop = top + heightOf(toPlace) + widget.gap;
      for (var c = placeX; c < placeX + placeW; c++) {
        columnsTops[c] = newTop;
      }
    }

    // Second pass: expand each widget into the column gap to its right,
    // bounded by the leftmost vertically-overlapping right neighbour (so a
    // widget never reaches into space already claimed by another widget at
    // a different y). Pixel left stays at the widget's saved x; only width
    // grows. This fills the trailing grey gap that appears when saved
    // widget widths don't tile the breakpoint cleanly (e.g. saved 1/3-of-12
    // widgets viewed on tablet's 8-col grid leave a 2-col stub on the right
    // until they expand into it).
    final pxOverrides =
        <String, ({double top, double left, double width})>{};
    final placementsById = {for (final p in layout.placements) p.id: p};

    double heightForId(String id) {
      final placement = placementsById[id];
      if (placement == null) {
        return widget.rowHeight;
      }
      return heightOf(placement);
    }

    for (final entry in gridOverrides.entries) {
      final id = entry.key;
      final p = entry.value;
      final myBottom = p.top + heightForId(id);

      // Find the leftmost x of any vertically-overlapping right neighbour.
      int? maxRightX;
      for (final other in gridOverrides.entries) {
        if (other.key == id) continue;
        final op = other.value;
        if (op.x <= p.x) continue;
        final otherBottom = op.top + heightForId(other.key);
        final vOverlap = op.top < myBottom && otherBottom > p.top;
        if (vOverlap && (maxRightX == null || op.x < maxRightX)) {
          maxRightX = op.x;
        }
      }

      // Three-way decision:
      // 1. Right neighbour exists → fill the column gap up to that
      //    neighbour. Closes the gap *between* two cells that share part
      //    of their vertical range.
      // 2. No right neighbour but anything sits below this cell → fill
      //    to the right edge of the grid. Without this, a top-row cell
      //    paired with a tall column to one side (e.g. TS at w=3 next to
      //    WJD at w=3, on a tablet 8-col grid) would leave 2 cols of
      //    trailing grey that visibly misaligns with the wider rows
      //    below — the symptom of the v2-proportional saved widths on a
      //    new viewport breakpoint.
      // 3. Truly at the bottom (no right neighbour, nothing below) →
      //    keep the saved width so empty-state cards (Budget Burndown,
      //    Recent Notes when blank, etc.) don't balloon to full width.
      //
      // Whichever branch fires, cap the resulting width at the widget's
      // catalog defaultW. The fluid pass exists to close gaps between
      // *saved-width* cells (e.g. when the saved layout's widths come
      // from a different breakpoint's scaler); it shouldn't make a
      // widget render *wider* than its declared default. A tall column
      // on one side of a 3-col layout used to make every widget in the
      // adjacent columns balloon to 2/3 width, defeating the
      // catalog-set 1/3 default.
      final hasContentBelow =
          gridOverrides.values.any((op) => op.top > myBottom);
      // User-sized widths render exactly as saved — the fluid pass exists to
      // close gaps left by scaler-derived widths, and growing a widget the
      // user deliberately shrank reads as the resize being ignored.
      final isUserSized = placementsById[id]?.userSizedW ?? false;
      final catalogMaxW = isUserSized
          ? p.w
          : widget.controller.catalog
              .metaFor(id)
              .desktopDefaultW
              .clamp(p.w, columns - p.x);

      int effectiveW;
      if (maxRightX != null) {
        effectiveW = (maxRightX - p.x).clamp(p.w, catalogMaxW);
      } else if (hasContentBelow) {
        effectiveW = catalogMaxW;
      } else {
        effectiveW = p.w;
      }

      pxOverrides[id] = (
        top: p.top,
        left: p.x * (cellWidth + widget.gap),
        width:
            effectiveW * cellWidth + (effectiveW - 1) * widget.gap,
      );
    }

    final maxBottom =
        columnsTops.fold<double>(0.0, (m, v) => v > m ? v : m);
    return (
      overrides: pxOverrides,
      totalHeight:
          (maxBottom - widget.gap).clamp(0.0, double.infinity),
    );
  }

  /// Computes the layout to render given the current drag/resize state.
  /// Returns the live layout unchanged when no manipulation is in progress.
  WidgetGridLayout _computePreviewLayout(WidgetGridLayout live) {
    if (_dragId != null &&
        _dragTargetX != null &&
        _dragTargetY != null) {
      return live.move(_dragId!, _dragTargetX!, _dragTargetY!);
    }
    if (_resizeId != null &&
        _resizeTargetX != null &&
        _resizeTargetY != null &&
        _resizeTargetW != null &&
        _resizeTargetH != null) {
      return live.setPlacement(
        _resizeId!,
        _resizeTargetX!,
        _resizeTargetY!,
        _resizeTargetW!,
        _resizeTargetH!,
      );
    }
    return live;
  }

  // ---------------------------------------------------------------------------
  // Cell rendering
  // ---------------------------------------------------------------------------

  /// Shared drag-lifecycle handlers used by both drag entry points: the
  /// immediate-drag handle pill and the long-press-anywhere cell body.
  void _onCellDragStarted(String id, WidgetPlacement renderPlacement) {
    setState(() {
      _dragId = id;
      _dragOrigin = renderPlacement;
      _dragStartGlobal = _lastPointerDownGlobal;
      _dragTargetX = renderPlacement.x;
      _dragTargetY = renderPlacement.y;
    });
    _startAutoScroll();
  }

  /// If the user releases outside the DragTarget (common when dragging past
  /// the grid's left edge), onAcceptWithDetails doesn't fire — we'd silently
  /// revert. Commit the last known target here so the user's intent is
  /// preserved.
  void _onCellDragCanceled(GridBreakpoint breakpoint) {
    final id = _dragId;
    final origin = _dragOrigin;
    final tx = _dragTargetX;
    final ty = _dragTargetY;
    if (id != null &&
        origin != null &&
        tx != null &&
        ty != null &&
        (tx != origin.x || ty != origin.y)) {
      widget.controller.moveWidgetTo(id, breakpoint, tx, ty);
    }
    _resetDragState();
  }

  /// The grab strip along a cell's top edge: a real drag handle that starts
  /// moving the widget immediately on grab — no long-press delay — like a
  /// window title bar. The centered pill is the visual cue; the whole strip
  /// is draggable so the target is forgiving. The cell body stays a
  /// [LongPressDraggable] so touch users can also grab anywhere.
  ///
  /// The pill visually overhangs the cell's top by 10px, but the hit area
  /// must stay inside the cell bounds: Stack does not hit-test children
  /// outside its own rect, so an overhanging interactive pill would be dead
  /// over its most clickable half.
  Widget _buildDragHandle({
    required String originalId,
    required WidgetPlacement renderPlacement,
    required GridBreakpoint breakpoint,
    required DashboardWidgetMeta meta,
  }) {
    return Listener(
      onPointerDown: (event) => _lastPointerDownGlobal = event.position,
      // MouseRegion defaults to opaque hit-testing, which is what makes the
      // otherwise-transparent strip grabbable across its full width.
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Draggable<String>(
          data: originalId,
          dragAnchorStrategy: _centerFeedbackOnPointer,
          onDragStarted: () =>
              _onCellDragStarted(originalId, renderPlacement),
          onDraggableCanceled: (_, __) => _onCellDragCanceled(breakpoint),
          onDragCompleted: _resetDragState,
          feedback: _DragFeedback(meta: meta),
          child: Tooltip(
            message: 'Drag to move',
            waitDuration: const Duration(milliseconds: 400),
            child: SizedBox(
              height: 20,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: -10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: IgnorePointer(
                        child: Container(
                          width: 44,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.drag_indicator,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedCell({
    required String originalId,
    required WidgetPlacement renderPlacement,
    required double cellWidth,
    required GridBreakpoint breakpoint,
    ({double top, double left, double width})? masonryOverride,
  }) {
    // Masonry override (view mode only) supplies pre-computed pixel left/top/
    // width — used for auto-shrunk full-width widgets (rendered narrower in
    // the shorter column), fill-gap reorderings, and fluid expansion that
    // distributes leftover row width across the cards in a row so a sub-3-
    // col viewport doesn't leave a grey gap on the right. Edit mode keeps
    // the row grid and the user's declared placement intact.
    final left = masonryOverride?.left ??
        renderPlacement.x * (cellWidth + widget.gap);
    final top = masonryOverride?.top ??
        renderPlacement.y * (widget.rowHeight + widget.gap);
    final width = masonryOverride?.width ??
        renderPlacement.w * cellWidth +
            (renderPlacement.w - 1) * widget.gap;
    final height = renderPlacement.h * widget.rowHeight +
        (renderPlacement.h - 1) * widget.gap;

    final meta = widget.controller.catalog.metaFor(originalId);
    final isBeingDragged = _dragId == originalId;
    final isBeingResized = _resizeId == originalId;
    final isFocused = _focusedId == originalId;

    final cell = _GridCell(
      controller: widget.controller,
      widgetId: originalId,
      widgetBuilder: widget.widgetBuilder,
    );

    if (!widget.controller.editMode) {
      if (meta.autoHeight && !renderPlacement.userSizedH) {
        // autoHeight cells size to their intrinsic content. The probe reports
        // the rendered height; _applyAutoHeights then shrinks `h` so cells
        // below this one pull up to close any trailing gap. We bypass
        // [_GridCell]'s internal SingleChildScrollView here — its viewport
        // can't compute intrinsic dimensions in the scroll axis, and there's
        // no overflow to scroll once the cell shrinks to fit.
        return AnimatedPositioned(
          key: ValueKey(originalId),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: left,
          top: top,
          width: width,
          // height intentionally unset — the child sizes itself.
          child: _AutoHeightCell(
            onHeightChanged: (px, cw) =>
                _onAutoHeightMeasured(originalId, px, cw),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: widget.widgetBuilder(originalId),
            ),
          ),
        );
      }
      return AnimatedPositioned(
        key: ValueKey(originalId),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        left: left,
        top: top,
        width: width,
        height: height,
        child: cell,
      );
    }

    final editableCell = _EditModeCell(
      meta: meta,
      isFocused: isFocused,
      isManipulating: isBeingDragged || isBeingResized,
      activeResize: (isBeingResized &&
              _resizeTargetW != null &&
              _resizeTargetH != null)
          ? (
              w: _resizeTargetW!,
              h: _resizeTargetH!,
              atMinW: _resizeAtMinW,
              atMinH: _resizeAtMinH,
              atMaxW: _resizeAtMaxW,
              atMaxH: _resizeAtMaxH,
            )
          : null,
      onRemove: () => widget.controller.hideWidget(originalId),
      dragHandle: _buildDragHandle(
        originalId: originalId,
        renderPlacement: renderPlacement,
        breakpoint: breakpoint,
        meta: meta,
      ),
      resizeHandleTopLeft: _buildResizeHandle(
        placement: renderPlacement,
        breakpoint: breakpoint,
        cellWidth: cellWidth,
        corner: _ResizeCorner.topLeft,
      ),
      resizeHandleTopRight: _buildResizeHandle(
        placement: renderPlacement,
        breakpoint: breakpoint,
        cellWidth: cellWidth,
        corner: _ResizeCorner.topRight,
      ),
      resizeHandleBottomLeft: _buildResizeHandle(
        placement: renderPlacement,
        breakpoint: breakpoint,
        cellWidth: cellWidth,
        corner: _ResizeCorner.bottomLeft,
      ),
      resizeHandleBottomRight: _buildResizeHandle(
        placement: renderPlacement,
        breakpoint: breakpoint,
        cellWidth: cellWidth,
        corner: _ResizeCorner.bottomRight,
      ),
      child: cell,
    );

    return AnimatedPositioned(
      key: ValueKey(originalId),
      // Skip the implicit animation while the user is actively dragging this
      // widget — the preview position should track the cursor without lag.
      // Other widgets reflowing around it still animate.
      duration: isBeingDragged
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: width,
      height: height,
      child: _KeyboardEditable(
        focused: isFocused,
        onFocusChange: (f) => setState(() {
          if (f) {
            _focusedId = originalId;
          } else if (_focusedId == originalId) {
            _focusedId = null;
          }
        }),
        onMove: (dx, dy) {
          widget.controller.moveWidgetTo(
            originalId,
            breakpoint,
            (renderPlacement.x + dx)
                .clamp(0, breakpoint.columns - renderPlacement.w),
            (renderPlacement.y + dy).clamp(0, 9999),
          );
        },
        onResize: (dw, dh) {
          widget.controller.resizeWidgetTo(
            originalId,
            breakpoint,
            renderPlacement.w + dw,
            renderPlacement.h + dh,
          );
        },
        onRemove: () => widget.controller.hideWidget(originalId),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: _HoverLift(
            enabled: !isBeingDragged && !isBeingResized,
            child: Listener(
              onPointerDown: (event) =>
                  _lastPointerDownGlobal = event.position,
              child: LongPressDraggable<String>(
                data: originalId,
                delay: const Duration(milliseconds: 180),
                // Center the compact feedback card under the cursor instead
                // of mirroring the grab point from the (much larger) cell —
                // childDragAnchorStrategy maps the grab offset relative to
                // the source widget, which leaves the small feedback
                // dangling off to one side.
                dragAnchorStrategy: _centerFeedbackOnPointer,
                hapticFeedbackOnStart: true,
                onDragStarted: () =>
                    _onCellDragStarted(originalId, renderPlacement),
                onDraggableCanceled: (_, __) =>
                    _onCellDragCanceled(breakpoint),
                onDragCompleted: () => _resetDragState(),
                feedback: _DragFeedback(meta: meta),
                // The faded state is driven by isBeingDragged (not just this
                // draggable's own childWhenDragging) so a drag initiated from
                // the handle pill fades the source cell the same way.
                childWhenDragging: _AnimatedDragOpacity(
                  isDragging: isBeingDragged,
                  child: editableCell,
                ),
                child: _AnimatedDragOpacity(
                  isDragging: isBeingDragged,
                  child: editableCell,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResizeHandle({
    required WidgetPlacement placement,
    required GridBreakpoint breakpoint,
    required double cellWidth,
    required _ResizeCorner corner,
  }) {
    final isMobile = breakpoint == GridBreakpoint.mobile;
    // The top-right corner is occupied by the X (remove) button — skip its
    // resize handle to avoid overlap. Users still get TL, BL, BR for diagonal
    // resize, which together cover both x and y in either direction.
    if (corner == _ResizeCorner.topRight) {
      return const SizedBox.shrink();
    }
    // On mobile (4 cols, every widget is full-width) horizontal resize is a
    // no-op, so we only render the bottom-edge handle and give it a
    // vertical-only icon. TL/BL are hidden on mobile.
    if (isMobile && corner != _ResizeCorner.bottomRight) {
      return const SizedBox.shrink();
    }

    return MouseRegion(
      cursor: _cursorForCorner(corner, isMobile),
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        // ImmediateMultiDragGestureRecognizer claims the pointer on touch-down
        // instead of waiting for a slop threshold. Without this, the parent
        // SingleChildScrollView's vertical-drag recognizer wins the arena on
        // mobile and the resize never fires.
        gestures: <Type, GestureRecognizerFactory>{
          ImmediateMultiDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                  ImmediateMultiDragGestureRecognizer>(
            () => ImmediateMultiDragGestureRecognizer(),
            (recognizer) {
              recognizer.onStart = (Offset position) {
                setState(() {
                  _resizeId = placement.id;
                  _resizeOrigin = placement;
                  _resizeStartGlobal = position;
                  _resizeCorner = corner;
                  _resizeTargetX = placement.x;
                  _resizeTargetY = placement.y;
                  _resizeTargetW = placement.w;
                  _resizeTargetH = placement.h;
                });
                return _ResizeDrag(
                  onUpdate: (globalCursor) => _applyResizeDelta(
                    globalCursor,
                    breakpoint,
                    cellWidth,
                  ),
                  onEnd: () {
                    final id = _resizeId;
                    final x = _resizeTargetX;
                    final y = _resizeTargetY;
                    final w = _resizeTargetW;
                    final h = _resizeTargetH;
                    if (id != null &&
                        x != null &&
                        y != null &&
                        w != null &&
                        h != null) {
                      widget.controller
                          .setWidgetPlacement(id, breakpoint, x, y, w, h);
                    }
                    _resetResizeState();
                  },
                  onCancel: _resetResizeState,
                );
              };
            },
          ),
        },
        // Hit area is 36x36; visual is 22x22 (smaller than single-corner
        // because four handles add chrome).
        child: SizedBox(
          width: 36,
          height: 36,
          child: Align(
            alignment: _alignForCorner(corner),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.85),
                borderRadius: _cornerRadius(corner),
              ),
              child: Icon(
                isMobile ? Icons.unfold_more : _iconForCorner(corner),
                size: 13,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Translates the cursor delta into a new (x, y, w, h) for the active
  /// corner and updates the resize-target state. Operates on edges rather
  /// than (x, w) pairs so that clamping at the grid boundary or at a
  /// catalog min/max preserves the opposite-corner anchor — e.g. dragging
  /// the bottom-left past the left edge keeps the right edge fixed.
  void _applyResizeDelta(
    Offset globalCursor,
    GridBreakpoint breakpoint,
    double cellWidth,
  ) {
    final origin = _resizeOrigin;
    final start = _resizeStartGlobal;
    final corner = _resizeCorner;
    if (origin == null || start == null || corner == null) return;
    final meta = widget.controller.catalog.metaFor(origin.id);
    final isMobile = breakpoint == GridBreakpoint.mobile;
    final delta = globalCursor - start;
    final dxCells =
        isMobile ? 0 : (delta.dx / (cellWidth + widget.gap)).round();
    final dyCells = (delta.dy / (widget.rowHeight + widget.gap)).round();

    final movesLeft =
        corner == _ResizeCorner.bottomLeft || corner == _ResizeCorner.topLeft;
    final movesTop =
        corner == _ResizeCorner.topRight || corner == _ResizeCorner.topLeft;

    var left = origin.x;
    var right = origin.x + origin.w;
    var top = origin.y;
    var bottom = origin.y + origin.h;
    if (movesLeft) {
      left = origin.x + dxCells;
    } else {
      right = origin.x + origin.w + dxCells;
    }
    if (movesTop) {
      top = origin.y + dyCells;
    } else {
      bottom = origin.y + origin.h + dyCells;
    }

    // Clamp the moving edges to grid bounds. The opposite (anchor) edge stays
    // put unless the moving edge crosses it, which the min-size step below
    // handles.
    final cols = breakpoint.columns;
    if (left < 0) left = 0;
    if (right > cols) right = cols;
    if (top < 0) top = 0;
    // Bottom has no hard upper limit — the grid can grow vertically.

    // Enforce catalog min/max width by adjusting the moving edge while
    // keeping the anchor fixed.
    final maxW = (meta.maxW ?? cols).clamp(meta.minW, cols);
    // Capture whether the cursor is asking for less than the minimum / more
    // than the maximum on each axis *before* clamping — that's the moment the
    // user needs to be told "this widget can't get smaller/bigger", not after
    // the snap-back. Max flags only fire on a *catalog* cap: the grid edge
    // already reads as a boundary on its own (left/right were clamped to it
    // above), and meta.maxH is the only ceiling height has.
    final atMinW = !isMobile && (right - left) < meta.minW;
    final atMinH = (bottom - top) < meta.minH;
    final atMaxW = !isMobile && meta.maxW != null && (right - left) > maxW;
    final atMaxH = meta.maxH != null && (bottom - top) > meta.maxH!;
    var w = right - left;
    if (w < meta.minW) {
      if (movesLeft) {
        left = right - meta.minW;
        if (left < 0) left = 0;
      } else {
        right = left + meta.minW;
        if (right > cols) right = cols;
      }
    } else if (w > maxW) {
      if (movesLeft) {
        left = right - maxW;
      } else {
        right = left + maxW;
      }
    }

    final maxH = meta.maxH ?? 9999;
    var h = bottom - top;
    if (h < meta.minH) {
      if (movesTop) {
        top = bottom - meta.minH;
        if (top < 0) top = 0;
      } else {
        bottom = top + meta.minH;
      }
    } else if (h > maxH) {
      if (movesTop) {
        top = bottom - maxH;
      } else {
        bottom = top + maxH;
      }
    }

    final newX = left;
    final newY = top;
    final newW = (right - left).clamp(1, cols);
    final newH = (bottom - top) < 1 ? 1 : bottom - top;

    if (newX != _resizeTargetX ||
        newY != _resizeTargetY ||
        newW != _resizeTargetW ||
        newH != _resizeTargetH ||
        atMinW != _resizeAtMinW ||
        atMinH != _resizeAtMinH ||
        atMaxW != _resizeAtMaxW ||
        atMaxH != _resizeAtMaxH) {
      setState(() {
        _resizeTargetX = newX;
        _resizeTargetY = newY;
        _resizeTargetW = newW;
        _resizeTargetH = newH;
        _resizeAtMinW = atMinW;
        _resizeAtMinH = atMinH;
        _resizeAtMaxW = atMaxW;
        _resizeAtMaxH = atMaxH;
      });
    }
  }

  static Alignment _alignForCorner(_ResizeCorner c) => switch (c) {
        _ResizeCorner.topLeft => Alignment.topLeft,
        _ResizeCorner.topRight => Alignment.topRight,
        _ResizeCorner.bottomLeft => Alignment.bottomLeft,
        _ResizeCorner.bottomRight => Alignment.bottomRight,
      };

  static IconData _iconForCorner(_ResizeCorner c) => switch (c) {
        _ResizeCorner.topLeft => Icons.north_west,
        _ResizeCorner.topRight => Icons.north_east,
        _ResizeCorner.bottomLeft => Icons.south_west,
        _ResizeCorner.bottomRight => Icons.south_east,
      };

  static MouseCursor _cursorForCorner(_ResizeCorner c, bool isMobile) {
    if (isMobile) return SystemMouseCursors.resizeUpDown;
    return switch (c) {
      _ResizeCorner.topLeft => SystemMouseCursors.resizeUpLeft,
      _ResizeCorner.topRight => SystemMouseCursors.resizeUpRight,
      _ResizeCorner.bottomLeft => SystemMouseCursors.resizeDownLeft,
      _ResizeCorner.bottomRight => SystemMouseCursors.resizeDownRight,
    };
  }

  static BorderRadius _cornerRadius(_ResizeCorner c) => switch (c) {
        _ResizeCorner.topLeft => const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.xl),
            bottomRight: Radius.circular(8),
          ),
        _ResizeCorner.topRight => const BorderRadius.only(
            topRight: Radius.circular(AppRadius.xl),
            bottomLeft: Radius.circular(8),
          ),
        _ResizeCorner.bottomLeft => const BorderRadius.only(
            bottomLeft: Radius.circular(AppRadius.xl),
            topRight: Radius.circular(8),
          ),
        _ResizeCorner.bottomRight => const BorderRadius.only(
            bottomRight: Radius.circular(AppRadius.xl),
            topLeft: Radius.circular(8),
          ),
      };

  // ---------------------------------------------------------------------------
  // Drag target (full-grid drop area)
  // ---------------------------------------------------------------------------

  Widget _buildDragTarget({
    required GridBreakpoint breakpoint,
    required double cellWidth,
    required int columns,
  }) {
    return Positioned.fill(
      child: DragTarget<String>(
        builder: (context, _, __) => const SizedBox.expand(),
        onMove: (details) {
          if (_dragOrigin == null) return;
          // details.offset is the feedback's top-left, which sits a fixed
          // (80, 17) from the pointer per _centerFeedbackOnPointer. Convert
          // back to pointer space before differencing against
          // _dragStartGlobal (a raw pointer-down position) — comparing the
          // two spaces directly skewed every drop ~half a cell left.
          final cursorGlobal = details.offset + const Offset(80, 17);
          // Fallback: if onDragStarted didn't capture a start position (rare
          // gesture-arena race), use this first onMove as the anchor.
          _dragStartGlobal ??= cursorGlobal;
          final box =
              _gridKey.currentContext?.findRenderObject() as RenderBox?;
          if (box == null) return;
          final localCursor = box.globalToLocal(cursorGlobal);
          final localStart = box.globalToLocal(_dragStartGlobal!);
          final delta = localCursor - localStart;
          final deltaCellsX =
              (delta.dx / (cellWidth + widget.gap)).round();
          final deltaCellsY =
              (delta.dy / (widget.rowHeight + widget.gap)).round();
          final newX = (_dragOrigin!.x + deltaCellsX)
              .clamp(0, columns - _dragOrigin!.w);
          final newY = (_dragOrigin!.y + deltaCellsY).clamp(0, 9999);
          if (newX != _dragTargetX || newY != _dragTargetY) {
            setState(() {
              _dragTargetX = newX;
              _dragTargetY = newY;
            });
          }
          _updateAutoScrollVelocity(cursorGlobal);
        },
        onLeave: (_) => _scrollVelocity = 0,
        onAcceptWithDetails: (details) {
          final id = details.data;
          final tx = _dragTargetX;
          final ty = _dragTargetY;
          if (tx != null && ty != null) {
            widget.controller.moveWidgetTo(id, breakpoint, tx, ty);
          }
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Drop-zone hints in the empty extra rows
  // ---------------------------------------------------------------------------

  Widget _buildDropZoneHints({
    required int layoutRows,
    required int extraRows,
    required int columns,
    required double cellWidth,
  }) {
    if (extraRows == 0) return const SizedBox.shrink();
    final top = layoutRows * (widget.rowHeight + widget.gap);
    final height = extraRows * widget.rowHeight +
        (extraRows - 1).clamp(0, 9999) * widget.gap;
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      height: height,
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
                width: 1.5,
                style: BorderStyle.solid,
              ),
              color: AppColors.primary.withValues(alpha: 0.04),
            ),
            child: Center(
              child: Text(
                'Drop widgets here to add a new row',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.primary.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders a single widget cell using the standard [DashboardWidgetWrapper].
/// Edit-mode affordances (X button, resize handle) are layered on top by
/// [_EditModeCell]. Collapse handling is suppressed because the v3 grid uses
/// fixed cell heights — collapsing inside a fixed cell leaves dead space.
class _GridCell extends StatelessWidget {
  final DashboardEditController controller;
  final String widgetId;
  final Widget Function(String widgetId) widgetBuilder;

  const _GridCell({
    required this.controller,
    required this.widgetId,
    required this.widgetBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final meta = controller.catalog.metaFor(widgetId);
    // Fixed-height cells whose content exceeds the slot show a vertical
    // scrollbar so the user can reach truncated content. [_BubbleWhenFitPhysics]
    // refuses the gesture when the child fits, so the dashboard's page scroll
    // still wins on cells that aren't overflowing. autoHeight cells bypass
    // [_GridCell] entirely and size to their intrinsic content.
    return DashboardWidgetWrapper(
      widgetId: widgetId,
      meta: meta,
      isCollapsed: false,
      editMode: false,
      currentSize: controller.config.sizeOf(widgetId),
      onToggleCollapse: () => controller.toggleCollapse(widgetId),
      onRemove: () => controller.hideWidget(widgetId),
      onToggleSize: () => controller.toggleSize(widgetId),
      showCollapseButton: false,
      child: _CellScrollView(child: widgetBuilder(widgetId)),
    );
  }
}

/// Vertical scroll wrapper for fixed-height grid cells. Renders the child at
/// its natural height; if the child exceeds the cell, an OS-style scrollbar
/// appears and the user can scroll within the cell. If the child fits,
/// [_BubbleWhenFitPhysics] declines the gesture so dashboard page-scroll keeps
/// working as it did before this wrapper existed.
class _CellScrollView extends StatefulWidget {
  final Widget child;

  const _CellScrollView({required this.child});

  @override
  State<_CellScrollView> createState() => _CellScrollViewState();
}

class _CellScrollViewState extends State<_CellScrollView> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        physics: const _BubbleWhenFitPhysics(parent: ClampingScrollPhysics()),
        child: widget.child,
      ),
    );
  }
}

/// Scroll physics that only accept user input when the viewport has something
/// to scroll. When `maxScrollExtent` is zero (child fits the cell), gestures
/// are passed through to ancestors — so the page-level scrollable on the
/// dashboard / project-overview screen still wins on non-overflowing cells.
class _BubbleWhenFitPhysics extends ScrollPhysics {
  const _BubbleWhenFitPhysics({super.parent});

  @override
  _BubbleWhenFitPhysics applyTo(ScrollPhysics? ancestor) {
    return _BubbleWhenFitPhysics(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    if (position.maxScrollExtent <= 0 && position.minScrollExtent >= 0) {
      return false;
    }
    return super.shouldAcceptUserOffset(position);
  }
}

/// Edit-mode visual affordances overlaid on a grid cell: a remove (X) button,
/// corner resize handles, a functional drag handle at top-center, and a subtle
/// scrim/border to signal editability.
///
/// To cut visual noise when every card on the dashboard is editable at once,
/// the corner resize handles and the remove button render dimmed until the
/// pointer hovers this cell (or it's focused/being manipulated). On touch
/// devices hover never fires, so the dimmed-but-functional state is the
/// resting state — still visible, just quieter.
class _EditModeCell extends StatefulWidget {
  final Widget child;
  final DashboardWidgetMeta meta;
  final bool isFocused;
  final bool isManipulating;

  /// Live target size while a corner-resize drag is in progress on this cell
  /// (null otherwise). The at-flags flip true while the drag is pinned at a
  /// catalog min/max on that axis — the chip and border switch to the warning
  /// style so the user sees *why* the cell stopped resizing.
  final ({int w, int h, bool atMinW, bool atMinH, bool atMaxW, bool atMaxH})?
      activeResize;
  final VoidCallback onRemove;
  final Widget dragHandle;
  final Widget resizeHandleTopLeft;
  final Widget resizeHandleTopRight;
  final Widget resizeHandleBottomLeft;
  final Widget resizeHandleBottomRight;

  const _EditModeCell({
    required this.child,
    required this.meta,
    required this.isFocused,
    required this.isManipulating,
    required this.activeResize,
    required this.onRemove,
    required this.dragHandle,
    required this.resizeHandleTopLeft,
    required this.resizeHandleTopRight,
    required this.resizeHandleBottomLeft,
    required this.resizeHandleBottomRight,
  });

  @override
  State<_EditModeCell> createState() => _EditModeCellState();
}

class _EditModeCellState extends State<_EditModeCell> {
  bool _hovered = false;

  Widget _chrome(Widget child) => AnimatedOpacity(
        opacity: (_hovered || widget.isFocused || widget.isManipulating)
            ? 1.0
            : 0.55,
        duration: const Duration(milliseconds: 120),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    // Border weight ramps up: idle 1.5px → focus/manipulate 2.5px,
    // and the colour darkens — gives a clear visual hierarchy without
    // chrome on every cell.
    final borderWidth =
        (widget.isFocused || widget.isManipulating) ? 2.5 : 1.5;
    final borderAlpha = widget.isManipulating
        ? 0.85
        : widget.isFocused
            ? 0.7
            : 0.35;
    final resize = widget.activeResize;
    final constrained = resize != null &&
        (resize.atMinW || resize.atMinH || resize.atMaxW || resize.atMaxH);
    final borderColor = constrained
        ? AppColors.warning.withValues(alpha: 0.95)
        : AppColors.primary.withValues(alpha: borderAlpha);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: widget.child),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(
                    color: borderColor,
                    width: borderWidth,
                  ),
                ),
              ),
            ),
          ),
          if (resize != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(child: _ResizeSizeChip(resize: resize)),
              ),
            ),
          // Functional drag strip along the cell's top edge: grab anywhere on
          // it to move the widget immediately (no long-press). Kept at full
          // opacity — it's the primary "this card is movable" signal. Inset
          // from the corners so the resize handle and × keep their hit areas.
          Positioned(
            top: 0,
            left: 40,
            right: 40,
            height: 20,
            child: widget.dragHandle,
          ),
          // Remove (X) button. The visible circle overhangs the cell's
          // top-right so it doesn't cover the widget header, but the hit area
          // extends into the cell — Stack doesn't hit-test outside its
          // bounds, so a hit area congruent with the overhanging circle
          // would be dead over its outer three quadrants.
          Positioned(
            top: -10,
            right: -10,
            child: _chrome(
              GestureDetector(
                onTap: widget.onRemove,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.close,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(left: 0, top: 0, child: _chrome(widget.resizeHandleTopLeft)),
          Positioned(right: 0, top: 0, child: _chrome(widget.resizeHandleTopRight)),
          Positioned(
              left: 0, bottom: 0, child: _chrome(widget.resizeHandleBottomLeft)),
          Positioned(
              right: 0,
              bottom: 0,
              child: _chrome(widget.resizeHandleBottomRight)),
        ],
      ),
    );
  }
}

/// Floating "4 × 2" badge shown at a cell's center while it's being resized.
/// When the drag is pinned at a catalog minimum or maximum the chip turns
/// amber and names the constrained axis, so a drag that stops responding
/// reads as "hit the widget's size limit" instead of a glitch.
class _ResizeSizeChip extends StatelessWidget {
  final ({int w, int h, bool atMinW, bool atMinH, bool atMaxW, bool atMaxH})
      resize;

  const _ResizeSizeChip({required this.resize});

  /// Names every axis currently pinned at a limit, collapsing same-direction
  /// pairs ("Min size"). A diagonal drag can pin opposite directions at once
  /// (e.g. min width + max height) — both get named.
  String? get _constraintLabel {
    if (resize.atMinW && resize.atMinH) return 'Min size';
    if (resize.atMaxW && resize.atMaxH) return 'Max size';
    final parts = <String>[
      if (resize.atMinW) 'Min width',
      if (resize.atMaxW) 'Max width',
      if (resize.atMinH) 'Min height',
      if (resize.atMaxH) 'Max height',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final label = _constraintLabel;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: label != null ? AppColors.warningDark : Colors.black87,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.md,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            const Icon(Icons.lock_outline, size: 13, color: Colors.white),
            const SizedBox(width: 5),
          ],
          Text(
            label != null
                ? '${resize.w} × ${resize.h} · $label'
                : '${resize.w} × ${resize.h}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              // Tabular figures keep the chip from jittering as digits change
              // mid-drag.
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders an autoHeight cell at its intrinsic content height and reports the
/// measured height back to the grid after every layout pass. The grid uses the
/// measurement to override the cell's row-unit `h` so subsequent cells can
/// pull up and trailing dead space inside variable-content widgets disappears.
class _AutoHeightCell extends StatefulWidget {
  final Widget child;
  // Receives (intrinsic height px, laid-out cell width px) after each layout
  // pass. Width is propagated so the parent can detect width-change events
  // and reset its grow-only floor.
  final void Function(double height, double width) onHeightChanged;

  const _AutoHeightCell({
    required this.child,
    required this.onHeightChanged,
  });

  @override
  State<_AutoHeightCell> createState() => _AutoHeightCellState();
}

class _AutoHeightCellState extends State<_AutoHeightCell> {
  double? _lastReportedH;
  double? _lastReportedW;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight forces the child to lay out at its intrinsic max
    // content height even though the surrounding [Positioned] leaves height
    // unconstrained. Without it, a Column with the default mainAxisSize.max
    // would assert against the unbounded constraint.
    //
    // [_MeasureSize] reports the laid-out size after every layout pass — not
    // just after this widget rebuilds. Descendants like [BudgetBurndownChart]
    // call their own setState when their async data resolves and flips from
    // a compact loading row to the taller no-data/chart state; without a
    // layout-time hook the old (smaller) measurement would stay cached and
    // the next masonry cell would render on top of the grown content.
    return _MeasureSize(
      onLayout: _onLayout,
      child: IntrinsicHeight(child: widget.child),
    );
  }

  void _onLayout(Size size) {
    if (!mounted) return;
    final h = size.height;
    final w = size.width;
    final sameH =
        _lastReportedH != null && (_lastReportedH! - h).abs() < 0.5;
    final sameW =
        _lastReportedW != null && (_lastReportedW! - w).abs() < 0.5;
    if (sameH && sameW) return;
    _lastReportedH = h;
    _lastReportedW = w;
    widget.onHeightChanged(h, w);
  }
}

/// Reports the child's laid-out size after every layout pass, even when no
/// ancestor rebuilds. Used by [_AutoHeightCell] so internal setState in a
/// descendant (e.g. async data arriving) triggers a fresh measurement.
class _MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onLayout;

  const _MeasureSize({required this.onLayout, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderBox(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    _MeasureSizeRenderBox renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

class _MeasureSizeRenderBox extends RenderProxyBox {
  _MeasureSizeRenderBox(this.onLayout);

  ValueChanged<Size> onLayout;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? Size.zero;
    if (_lastSize == newSize) return;
    _lastSize = newSize;
    // Defer to post-frame so the callback's setState doesn't fire during
    // layout (which would assert).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onLayout(newSize);
    });
  }
}

/// [Drag] adapter for the resize handle's [ImmediateMultiDragGestureRecognizer].
/// Forwards update/end/cancel to the closure callbacks captured at touch-down.
class _ResizeDrag extends Drag {
  _ResizeDrag({
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  void update(DragUpdateDetails details) => onUpdate(details.globalPosition);

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() => onCancel();
}

/// Compact drag feedback shown under the cursor while moving a widget. Avoids
/// the visual clutter of dragging a full-size translucent widget.
class _DragFeedback extends StatelessWidget {
  final DashboardWidgetMeta meta;

  const _DragFeedback({required this.meta});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.primary, width: 2),
          boxShadow: AppShadows.md,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(meta.icon, size: 18, color: meta.accentColor),
            const SizedBox(width: 8),
            Text(
              substituteProjectTerminology(
                meta.label,
                context.watch<WorkspaceProvider>().projectTerminology,
              ),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adds a subtle elevation and 1.01x scale on hover in edit mode.
/// Disabled during drag/resize so the manipulation gesture isn't fighting a
/// hover transform underneath.
class _HoverLift extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const _HoverLift({required this.child, required this.enabled});

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final lifted = widget.enabled && _hovering;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: lifted ? 1.01 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: lifted ? AppShadows.md : AppShadows.none,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Drawn around the grid when the user has forced a preview breakpoint.
/// A 4px gutter + dashed-style border + small label makes it obvious the
/// canvas is in preview mode (not the actual viewport).
class _PreviewFrame extends StatelessWidget {
  final GridBreakpoint breakpoint;
  final Widget child;

  const _PreviewFrame({required this.breakpoint, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 28, 4, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 1.5,
          ),
          color: AppColors.primary.withValues(alpha: 0.04),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned(
              top: -22,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      switch (breakpoint) {
                        GridBreakpoint.mobile => Icons.smartphone,
                        GridBreakpoint.tablet => Icons.tablet_mac,
                        GridBreakpoint.desktop => Icons.desktop_windows,
                      },
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Preview · ${switch (breakpoint) {
                        GridBreakpoint.mobile => 'Mobile',
                        GridBreakpoint.tablet => 'Tablet',
                        GridBreakpoint.desktop => 'Desktop',
                      }}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
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
}

/// Animates the opacity transition when a widget enters/leaves the dragging
/// state, instead of snapping abruptly between 100% and 25%.
class _AnimatedDragOpacity extends StatelessWidget {
  final Widget child;
  final bool isDragging;

  const _AnimatedDragOpacity({required this.child, required this.isDragging});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isDragging ? 0.25 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: child,
    );
  }
}

/// Adds keyboard-driven move/resize/remove for a focused cell:
///  - Arrow keys nudge by one grid unit
///  - Shift+Arrow resizes by one grid unit
///  - Delete/Backspace removes
class _KeyboardEditable extends StatelessWidget {
  final Widget child;
  final bool focused;
  final ValueChanged<bool> onFocusChange;
  final void Function(int dx, int dy) onMove;
  final void Function(int dw, int dh) onResize;
  final VoidCallback onRemove;

  const _KeyboardEditable({
    required this.child,
    required this.focused,
    required this.onFocusChange,
    required this.onMove,
    required this.onResize,
    required this.onRemove,
  });

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        shift ? onResize(-1, 0) : onMove(-1, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        shift ? onResize(1, 0) : onMove(1, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        shift ? onResize(0, -1) : onMove(0, -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        shift ? onResize(0, 1) : onMove(0, 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        onRemove();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKey,
      onFocusChange: onFocusChange,
      child: child,
    );
  }
}

/// Paints a faint dotted snap grid: a small dot at every (column, row)
/// intersection. Lets users see where widgets will snap during drag/resize.
class _GridLinesPainter extends CustomPainter {
  final int columns;
  final int rows;
  final double cellWidth;
  final double rowHeight;
  final double gap;
  final Color color;

  _GridLinesPainter({
    required this.columns,
    required this.rows,
    required this.cellWidth,
    required this.rowHeight,
    required this.gap,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rows <= 0 || columns <= 0) return;
    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // Dots at every intersection: column 0..columns, row 0..rows. The outermost
    // dots sit slightly inside the canvas edge so they don't get clipped.
    for (var c = 0; c <= columns; c++) {
      for (var r = 0; r <= rows; r++) {
        final x = (c == 0)
            ? 1.0
            : c * cellWidth + (c - 1) * gap + (c == columns ? -1.0 : gap / 2);
        final y = (r == 0)
            ? 1.0
            : r * rowHeight + (r - 1) * gap + (r == rows ? -1.0 : gap / 2);
        canvas.drawCircle(Offset(x, y), 1.8, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridLinesPainter old) =>
      old.columns != columns ||
      old.rows != rows ||
      old.cellWidth != cellWidth ||
      old.rowHeight != rowHeight ||
      old.gap != gap ||
      old.color != color;
}

/// One-time inline banner that explains the v3 editing affordances. Shown the
/// first time a user enters edit mode after the v3 launch; "Got it" persists
/// the ack via user_preferences so it never appears again.
class _EditCoachMark extends StatefulWidget {
  const _EditCoachMark();

  @override
  State<_EditCoachMark> createState() => _EditCoachMarkState();
}

class _EditCoachMarkState extends State<_EditCoachMark> {
  // null = still loading; true = already dismissed; false = show the banner.
  bool? _seen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs =
          await ServiceLocator.userPreferencesService.getPreferences();
      if (!mounted) return;
      setState(() => _seen = prefs[_kEditCoachSeenKey] == true);
    } catch (_) {
      // If prefs can't be read, default to "seen" so the banner doesn't
      // show on every edit-mode entry under degraded conditions.
      if (!mounted) return;
      setState(() => _seen = true);
    }
  }

  Future<void> _dismiss() async {
    setState(() => _seen = true);
    try {
      await ServiceLocator.userPreferencesService
          .updatePreferenceKey(_kEditCoachSeenKey, true);
    } catch (_) {
      // Non-fatal — the banner is hidden in memory either way; if persistence
      // fails the user just sees it again next session.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_seen != false) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.base),
      child: Card(
        elevation: 0,
        color: AppColors.primary.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.tips_and_updates, color: AppColors.primary, size: 22),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customize your dashboard',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Move a card by dragging the handle at its top edge '
                      '(or long-press anywhere on it). Drag a corner to '
                      'resize. Tap × to remove — hidden cards can be added '
                      'back from Widgets. Press Esc when done.',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: _dismiss,
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
