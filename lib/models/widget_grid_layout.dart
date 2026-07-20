import '../screens/home/dashboard_widget_catalog.dart';
import '../utils/app_logger.dart';
import 'dashboard_config.dart';
import 'widget_catalog_provider.dart';

/// Responsive breakpoints for the v3 grid system.
///
/// Each breakpoint has its own column count and is laid out independently —
/// auto-collapsing a desktop layout to mobile produces ugly results, so users
/// edit each breakpoint as its own canvas.
enum GridBreakpoint {
  mobile(columns: 4),
  tablet(columns: 8),
  desktop(columns: 12);

  const GridBreakpoint({required this.columns});

  final int columns;

  static GridBreakpoint forWidth(double width) {
    if (width >= 1200) return GridBreakpoint.desktop;
    if (width >= 600) return GridBreakpoint.tablet;
    return GridBreakpoint.mobile;
  }

  static GridBreakpoint? fromKey(String? key) {
    switch (key) {
      case 'mobile':
        return GridBreakpoint.mobile;
      case 'tablet':
        return GridBreakpoint.tablet;
      case 'desktop':
        return GridBreakpoint.desktop;
      default:
        return null;
    }
  }

  String get key => name;
}

/// A single widget's position and size in grid units.
class WidgetPlacement {
  final String id;
  final int x; // 0 .. columns-1
  final int y; // 0 .. N
  final int w; // 1 .. columns
  final int h; // 1 .. N

  /// True once the user has explicitly set this widget's width via a resize.
  /// View-mode rendering (masonry fluid expansion / auto-shrink) keeps the
  /// saved width for user-sized placements instead of overriding it to close
  /// gaps — otherwise an intentional downsize silently grows back.
  final bool userSizedW;

  /// True once the user has explicitly set this widget's height via a resize.
  /// autoHeight widgets normally have their slot height overridden in view
  /// mode to match measured content (shrink *and* grow); a user-sized height
  /// opts the cell out of that and renders the saved fixed-height slot
  /// (scrolling internally if content overflows).
  final bool userSizedH;

  const WidgetPlacement({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.userSizedW = false,
    this.userSizedH = false,
  });

  WidgetPlacement copyWith({
    int? x,
    int? y,
    int? w,
    int? h,
    bool? userSizedW,
    bool? userSizedH,
  }) =>
      WidgetPlacement(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        userSizedW: userSizedW ?? this.userSizedW,
        userSizedH: userSizedH ?? this.userSizedH,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        // Omitted when false so pre-existing payloads and this one stay
        // byte-compatible in the common case.
        if (userSizedW) 'us': true,
        if (userSizedH) 'ush': true,
      };

  static WidgetPlacement? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final x = json['x'];
    final y = json['y'];
    final w = json['w'];
    final h = json['h'];
    if (id is! String || x is! int || y is! int || w is! int || h is! int) {
      return null;
    }
    return WidgetPlacement(
      id: id,
      x: x,
      y: y,
      w: w,
      h: h,
      userSizedW: json['us'] == true,
      userSizedH: json['ush'] == true,
    );
  }

  @override
  String toString() => 'WidgetPlacement($id @ $x,$y, ${w}x$h)';
}

/// A single breakpoint's worth of widget placements.
class WidgetGridLayout {
  final GridBreakpoint breakpoint;
  final List<WidgetPlacement> placements;

  const WidgetGridLayout({required this.breakpoint, required this.placements});

  int get columns => breakpoint.columns;

  /// Total row count this layout occupies.
  int get rows {
    if (placements.isEmpty) return 0;
    return placements
        .map((p) => p.y + p.h)
        .fold<int>(0, (max, v) => v > max ? v : max);
  }

  WidgetPlacement? placementOf(String id) {
    for (final p in placements) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Returns a new layout with the given widget id removed.
  WidgetGridLayout without(String id) => WidgetGridLayout(
        breakpoint: breakpoint,
        placements: placements.where((p) => p.id != id).toList(growable: false),
      );

  /// Returns a new layout with [id]'s placement flagged user-sized on the
  /// given axes (see [WidgetPlacement.userSizedW]/[WidgetPlacement.userSizedH]).
  /// Axes not passed keep their current flag.
  WidgetGridLayout markUserSized(
    String id, {
    bool width = false,
    bool height = false,
  }) =>
      WidgetGridLayout(
        breakpoint: breakpoint,
        placements: [
          for (final p in placements)
            p.id == id
                ? p.copyWith(
                    userSizedW: width ? true : null,
                    userSizedH: height ? true : null,
                  )
                : p,
        ],
      );

  /// Vertical compaction: gravity-pack every widget upward, eliminating empty
  /// rows above content. Order is preserved by (y, x) so the visual reading
  /// order doesn't change.
  WidgetGridLayout compacted() {
    final sorted = [...placements]
      ..sort((a, b) {
        final dy = a.y.compareTo(b.y);
        if (dy != 0) return dy;
        return a.x.compareTo(b.x);
      });

    final placed = <WidgetPlacement>[];
    for (final p in sorted) {
      var newY = 0;
      // Slide the widget upward until it would collide with one already placed.
      while (_collidesAny(placed, p.x, newY, p.w, p.h)) {
        newY++;
      }
      placed.add(p.copyWith(y: newY));
    }
    return WidgetGridLayout(breakpoint: breakpoint, placements: placed);
  }

  /// First-fit insertion: scans top-to-bottom, left-to-right for the first
  /// position where (w, h) fits, preferring spots above existing content over
  /// appending at the bottom. Falls back to the next free row if no hole fits.
  WidgetGridLayout withWidget(String id, int w, int h) {
    final clampedW = w.clamp(1, columns);
    final maxRows = rows;
    for (var y = 0; y <= maxRows; y++) {
      for (var x = 0; x <= columns - clampedW; x++) {
        if (!_collidesAny(placements, x, y, clampedW, h)) {
          return WidgetGridLayout(
            breakpoint: breakpoint,
            placements: [
              ...placements,
              WidgetPlacement(id: id, x: x, y: y, w: clampedW, h: h),
            ],
          );
        }
      }
    }
    // Should be unreachable — the y == maxRows row is always free.
    return WidgetGridLayout(
      breakpoint: breakpoint,
      placements: [
        ...placements,
        WidgetPlacement(id: id, x: 0, y: maxRows, w: clampedW, h: h),
      ],
    );
  }

  /// Moves [id] to (newX, newY) and gravity-packs everything else upward
  /// without crossing it. Other widgets that overlap the new position get
  /// pushed past it via compaction.
  WidgetGridLayout move(String id, int newX, int newY) {
    final pinned = placementOf(id);
    if (pinned == null) return this;
    final clampedX = newX.clamp(0, columns - pinned.w);
    final clampedY = newY < 0 ? 0 : newY;
    final updatedPin =
        pinned.copyWith(x: clampedX, y: clampedY);
    final others = placements.where((p) => p.id != id).toList();
    return _compactWithPin(updatedPin, others);
  }

  /// Pins [id] to an arbitrary (x, y, w, h) rect and gravity-packs everything
  /// else around it. Used by the multi-corner resize handles where the
  /// anchor isn't always the top-left (e.g. dragging the top-left corner
  /// changes both x and w simultaneously).
  WidgetGridLayout setPlacement(String id, int x, int y, int w, int h) {
    final pinned = placementOf(id);
    if (pinned == null) return this;
    final clampedW = w.clamp(1, columns);
    final clampedX = x.clamp(0, columns - clampedW);
    final clampedY = y < 0 ? 0 : y;
    final clampedH = h < 1 ? 1 : h;
    final updated = pinned.copyWith(
      x: clampedX,
      y: clampedY,
      w: clampedW,
      h: clampedH,
    );
    final others = placements.where((p) => p.id != id).toList();
    return _compactWithPin(updated, others);
  }

  /// Resizes [id] to (newW, newH), clamped to grid bounds. Other widgets are
  /// gravity-packed around the resized widget.
  WidgetGridLayout resize(
    String id,
    int newW,
    int newH, {
    int minW = 1,
    int minH = 1,
    int? maxW,
    int? maxH,
  }) {
    final pinned = placementOf(id);
    if (pinned == null) return this;
    final upperW = (maxW ?? columns).clamp(minW, columns);
    final clampedW = newW.clamp(minW, upperW);
    final upperH = maxH ?? 9999;
    final clampedH = newH.clamp(minH, upperH);
    // If the new width would push the widget off the right edge, shift it left.
    final shiftedX = (pinned.x + clampedW > columns)
        ? (columns - clampedW).clamp(0, columns - clampedW)
        : pinned.x;
    final updatedPin = pinned.copyWith(x: shiftedX, w: clampedW, h: clampedH);
    final others = placements.where((p) => p.id != id).toList();
    return _compactWithPin(updatedPin, others);
  }

  /// Compaction with a single widget pinned at its declared position. The
  /// pinned widget is placed first; remaining widgets gravity-pack upward in
  /// (y, x) order without colliding with the pin or each other.
  WidgetGridLayout _compactWithPin(
    WidgetPlacement pin,
    List<WidgetPlacement> others,
  ) {
    final sorted = [...others]
      ..sort((a, b) {
        final dy = a.y.compareTo(b.y);
        if (dy != 0) return dy;
        return a.x.compareTo(b.x);
      });
    final placed = <WidgetPlacement>[pin];
    for (final p in sorted) {
      var newY = 0;
      while (_collidesAny(placed, p.x, newY, p.w, p.h)) {
        newY++;
      }
      placed.add(p.copyWith(y: newY));
    }
    return WidgetGridLayout(breakpoint: breakpoint, placements: placed);
  }

  Map<String, dynamic> toJson() => {
        'placements': placements.map((p) => p.toJson()).toList(),
      };

  static WidgetGridLayout fromJson(
    GridBreakpoint breakpoint,
    Map<String, dynamic> json,
  ) {
    final raw = json['placements'];
    final placements = <WidgetPlacement>[];
    var dropped = 0;
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          final p =
              WidgetPlacement.fromJson(Map<String, dynamic>.from(entry));
          if (p != null) {
            placements.add(p);
          } else {
            dropped++;
          }
        } else {
          dropped++;
        }
      }
    }
    if (dropped > 0) {
      // A user with corrupted JSONB would otherwise see widgets vanish with
      // no clue what happened. Logging gives support a trail to follow.
      AppLogger.warning(
        'Dropped malformed widget placements while loading layout',
        metadata: {
          'breakpoint': breakpoint.key,
          'dropped': dropped,
          'kept': placements.length,
        },
      );
    }
    return WidgetGridLayout(breakpoint: breakpoint, placements: placements);
  }
}

bool _collidesAny(
  Iterable<WidgetPlacement> existing,
  int x,
  int y,
  int w,
  int h,
) {
  for (final p in existing) {
    if (_rectsOverlap(p.x, p.y, p.w, p.h, x, y, w, h)) return true;
  }
  return false;
}

bool _rectsOverlap(
  int ax,
  int ay,
  int aw,
  int ah,
  int bx,
  int by,
  int bw,
  int bh,
) {
  if (ax + aw <= bx) return false;
  if (bx + bw <= ax) return false;
  if (ay + ah <= by) return false;
  if (by + bh <= ay) return false;
  return true;
}

/// Top-level v3 widget grid config: per-breakpoint layouts + visibility state.
class WidgetGridConfig {
  static const int currentVersion = 3;

  final int version;
  final Map<GridBreakpoint, WidgetGridLayout> layouts;
  final List<String> hidden;
  final List<String> collapsed;
  final DateTime? updatedAt;

  const WidgetGridConfig({
    this.version = currentVersion,
    this.layouts = const {},
    this.hidden = const [],
    this.collapsed = const [],
    this.updatedAt,
  });

  WidgetGridLayout layoutFor(GridBreakpoint breakpoint) {
    return layouts[breakpoint] ??
        WidgetGridLayout(breakpoint: breakpoint, placements: const []);
  }

  bool isHidden(String id) => hidden.contains(id);
  bool isCollapsed(String id) => collapsed.contains(id);

  WidgetGridConfig copyWith({
    Map<GridBreakpoint, WidgetGridLayout>? layouts,
    List<String>? hidden,
    List<String>? collapsed,
  }) {
    return WidgetGridConfig(
      version: currentVersion,
      layouts: layouts ?? this.layouts,
      hidden: hidden ?? this.hidden,
      collapsed: collapsed ?? this.collapsed,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'layouts': {
          for (final entry in layouts.entries)
            entry.key.key: entry.value.toJson(),
        },
        'hidden': hidden,
        'collapsed': collapsed,
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  static WidgetGridConfig fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) return const WidgetGridConfig();
    final layoutsRaw = json['layouts'];
    final layouts = <GridBreakpoint, WidgetGridLayout>{};
    if (layoutsRaw is Map) {
      for (final entry in layoutsRaw.entries) {
        final bp = GridBreakpoint.fromKey(entry.key.toString());
        if (bp == null) continue;
        if (entry.value is Map) {
          layouts[bp] = WidgetGridLayout.fromJson(
            bp,
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }
    return WidgetGridConfig(
      version: WidgetGridConfig.currentVersion,
      layouts: layouts,
      hidden: (json['hidden'] is List)
          ? List<String>.from(json['hidden'] as List)
          : const [],
      collapsed: (json['collapsed'] is List)
          ? List<String>.from(json['collapsed'] as List)
          : const [],
      updatedAt: json['updated_at'] is String
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  /// Derives a v3 config from a v2 config by walking the ordered widget list
  /// per breakpoint, sizing each widget from the catalog (or the v2 'half'/
  /// 'full' override), placing left-to-right, and compacting upward.
  ///
  /// Hidden widgets keep their hidden status; collapsed state carries over.
  factory WidgetGridConfig.migrateFromV2(
    DashboardWidgetConfig v2,
    WidgetCatalogProvider catalog,
  ) {
    final visibleOrder =
        v2.order.where((id) => !v2.isHidden(id)).toList(growable: false);

    final layouts = <GridBreakpoint, WidgetGridLayout>{};
    for (final bp in GridBreakpoint.values) {
      var layout = WidgetGridLayout(breakpoint: bp, placements: const []);
      for (final id in visibleOrder) {
        final meta = catalog.metaFor(id);
        final w = _widthForBreakpoint(meta, bp, v2.sizeOf(id));
        final h = meta.desktopDefaultH;
        layout = layout.withWidget(id, w, h);
      }
      layouts[bp] = layout.compacted();
    }

    return WidgetGridConfig(
      version: WidgetGridConfig.currentVersion,
      layouts: layouts,
      hidden: List<String>.from(v2.hidden),
      collapsed: List<String>.from(v2.collapsed),
      updatedAt: DateTime.now(),
    );
  }
}

/// Public version of [_widthForBreakpoint] for callers that need to size a
/// widget identically to the migration logic (e.g. when re-inserting a
/// previously-hidden widget into a layout).
int defaultWidthForBreakpoint(
  DashboardWidgetMeta meta,
  GridBreakpoint bp, {
  String v2Size = 'half',
}) =>
    _widthForBreakpoint(meta, bp, v2Size);

/// Maps a widget's catalog default + v2 size override to a column span at the
/// given breakpoint. Mobile is single-column (full width), tablet is 8 cols
/// (half=4, full=8), desktop uses the meta's desktop default verbatim.
int _widthForBreakpoint(
  DashboardWidgetMeta meta,
  GridBreakpoint bp,
  String v2Size,
) {
  final desktopW = meta.desktopDefaultW;
  switch (bp) {
    case GridBreakpoint.desktop:
      // Honour v2 'full' override even if catalog default is half.
      if (v2Size == 'full') return GridBreakpoint.desktop.columns;
      return desktopW.clamp(meta.minW, GridBreakpoint.desktop.columns);
    case GridBreakpoint.tablet:
      // Snap to widths that divide tablet's 8-col grid evenly (2/4/8) so a
      // row of widgets always fills the available width. Proportional
      // scaling produced fractional widths (e.g. desktop 1/3 → tablet
      // 2.67 → 3) that left a trailing grey gap when two widgets only
      // covered 6/8 cols.
      final tabletCols = GridBreakpoint.tablet.columns;
      final int scaled;
      if (v2Size == 'full' || desktopW > 6) {
        scaled = tabletCols; // full row
      } else if (desktopW > 3) {
        scaled = tabletCols ~/ 2; // half row (4 cols) — 2 per row
      } else {
        scaled = tabletCols ~/ 4; // quarter (2 cols) — 4 per row
      }
      return scaled.clamp(meta.minW, tabletCols);
    case GridBreakpoint.mobile:
      return GridBreakpoint.mobile.columns;
  }
}
