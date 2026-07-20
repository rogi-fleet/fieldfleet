import 'package:flutter/material.dart';

/// Shadow tokens for the FieldFleet design system.
///
/// Inspired by Apple's layered shadow approach:
/// a wide soft ambient layer + a tight key-light layer,
/// producing a natural depth without harsh directional edges.
abstract final class AppShadows {
  static const List<BoxShadow> none = [];

  /// Cards at rest — soft ambient + tight key light.
  static const List<BoxShadow> sm = [
    BoxShadow(
      color: Color(0x12000000), // 7 % black ambient
      blurRadius: 20,
      spreadRadius: -1,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x08000000), // 3 % black key
      blurRadius: 6,
      spreadRadius: 0,
      offset: Offset(0, 1),
    ),
  ];

  /// Elevated interactive elements — hover / focus / popover.
  static const List<BoxShadow> md = [
    BoxShadow(
      color: Color(0x1A000000), // 10 % black ambient
      blurRadius: 36,
      spreadRadius: -2,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x0C3B4CDB), // 5 % cool-blue accent layer
      blurRadius: 20,
      spreadRadius: 0,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x07000000), // 3 % key light
      blurRadius: 4,
      spreadRadius: 0,
      offset: Offset(0, 1),
    ),
  ];

  /// Modals, overlays, bottom-sheets, dialogs.
  static const List<BoxShadow> lg = [
    BoxShadow(
      color: Color(0x24000000), // 14 % black deep ambient
      blurRadius: 60,
      spreadRadius: -6,
      offset: Offset(0, 20),
    ),
    BoxShadow(
      color: Color(0x143B4CDB), // 8 % cool-blue glow
      blurRadius: 28,
      spreadRadius: -2,
      offset: Offset(0, 10),
    ),
    BoxShadow(
      color: Color(0x08000000), // 3 % key
      blurRadius: 8,
      spreadRadius: 0,
      offset: Offset(0, 2),
    ),
  ];

  /// Sidebar / navigation panel depth.
  static const List<BoxShadow> sidebar = [
    BoxShadow(
      color: Color(0x28000000),
      blurRadius: 32,
      spreadRadius: 0,
      offset: Offset(4, 0),
    ),
    BoxShadow(
      color: Color(0x10000000),
      blurRadius: 8,
      spreadRadius: 0,
      offset: Offset(1, 0),
    ),
  ];
}
