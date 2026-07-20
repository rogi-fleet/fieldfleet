import 'package:flutter/material.dart';

import '../../models/floorplan/scene.dart';
import '../../utils/floorplan/id_broker.dart';
import 'scene_builder.dart';

/// One starter layout the user can pick from when creating a floorplan.
class FloorplanPreset {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Scene Function(IdBroker ids, String defaultName) build;

  const FloorplanPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.build,
  });
}

/// Curated starter layouts. All dimensions are in cm — the editor's unit
/// picker can switch the display later. Sizes are intentionally
/// approximate, not architecturally exact, so first-time users have
/// something recognizable to start adjusting from.
///
/// Special-case presets whose [FloorplanPreset.build] is unused (returns an
/// empty scene as a fallback) — the picker recognises them by id and runs
/// a different flow:
///
///   * `ai`, `ai_image`, `ai_pdf` — collect a prompt / image / PDF, then
///     dispatch an AI generation.
///   * `scan` — open the native room-scan screen (mobile only). The scan
///     flow creates its own plan + scene, so the caller skips the normal
///     create-plan-then-upsert-scene path entirely.
final List<FloorplanPreset> defaultPresets = [
  FloorplanPreset(
    id: 'scan',
    name: 'Scan a room',
    description:
        'Walk a room with your phone camera. Mobile only — uses LiDAR on '
        'iPhone Pro and ARCore on Android.',
    icon: Icons.view_in_ar_outlined,
    build: _buildBlank,
  ),
  FloorplanPreset(
    id: 'ai',
    name: 'Generate from text',
    description:
        'Describe what you want — AI sketches a floorplan you can edit.',
    icon: Icons.auto_awesome,
    build: _buildBlank,
  ),
  FloorplanPreset(
    id: 'ai_image',
    name: 'Generate from photo',
    description:
        'Upload a photo of a space — AI describes it and sketches a floorplan.',
    icon: Icons.image_search,
    build: _buildBlank,
  ),
  FloorplanPreset(
    id: 'ai_pdf',
    name: 'Generate from PDF',
    description:
        'Upload a floorplan PDF — AI reads it and rebuilds it as an editable scene.',
    icon: Icons.picture_as_pdf_outlined,
    build: _buildBlank,
  ),
  FloorplanPreset(
    id: 'blank',
    name: 'Blank canvas',
    description: 'Start from scratch.',
    icon: Icons.crop_square,
    build: _buildBlank,
  ),
  FloorplanPreset(
    id: 'small_room',
    name: 'Small room',
    description: '4 m × 5 m room with one door — ideal for a single space.',
    icon: Icons.square_outlined,
    build: _buildSmallRoom,
  ),
  FloorplanPreset(
    id: 'studio',
    name: 'Studio apartment',
    description: '6 m × 7 m studio with bathroom + kitchenette.',
    icon: Icons.apartment,
    build: _buildStudio,
  ),
  FloorplanPreset(
    id: 'one_bed',
    name: '1-bedroom apartment',
    description: 'Living room, kitchen, bedroom, bathroom.',
    icon: Icons.king_bed_outlined,
    build: _buildOneBed,
  ),
  FloorplanPreset(
    id: 'office',
    name: 'Open-plan office',
    description: 'Open work area + 2 private offices + meeting room.',
    icon: Icons.business_center_outlined,
    build: _buildOffice,
  ),
];

// ---------------------------------------------------------------------------
// Builders. All measurements in cm.
// ---------------------------------------------------------------------------

Scene _buildBlank(IdBroker ids, String name) {
  return SceneBuilder(ids: ids).build(name: name);
}

Scene _buildSmallRoom(IdBroker ids, String name) {
  final b = SceneBuilder(ids: ids);
  final loop = b.addWallLoop(const [
    (x: 200, y: 200),
    (x: 600, y: 200),
    (x: 600, y: 700),
    (x: 200, y: 700),
  ]);
  // South wall (loop[3]→loop[0]) gets a door at its midpoint. The wall
  // ids returned by addWallLoop aren't surfaced; instead, find the wall
  // connecting the south corners by querying the scene.
  // Simplest: add the door inline via a fresh wall lookup is overkill —
  // use the convention that wall i connects loop[i] to loop[i+1 mod n].
  // Builder.addWallLoop adds them in order; the last (closing) wall is
  // the 4th. We re-derive its id below.
  final southWallId = b.linesByVertices(loop[3], loop[0]);
  if (southWallId != null) {
    b.addHole(
      lineId: southWallId,
      prototype: 'door',
      offset: 0.5,
      width: 90,
    );
  }
  return b.build(name: name);
}

Scene _buildStudio(IdBroker ids, String name) {
  final b = SceneBuilder(ids: ids);
  // Outer shell: 7 m × 6 m
  final outer = b.addWallLoop(const [
    (x: 200, y: 200),
    (x: 900, y: 200),
    (x: 900, y: 800),
    (x: 200, y: 800),
  ]);
  // Bathroom partition (interior wall splitting off the bottom-right
  // 2.5 m × 2.5 m corner).
  final partA = b.addVertex(650, 800);
  final partB = b.addVertex(650, 550);
  final partC = b.addVertex(900, 550);
  b.addWall(partA, partB);
  b.addWall(partB, partC);

  // Front door on the south wall (outer[3]→outer[0]).
  final southWallId = b.linesByVertices(outer[3], outer[0]);
  if (southWallId != null) {
    b.addHole(
      lineId: southWallId,
      prototype: 'door',
      offset: 0.3,
      width: 90,
    );
  }
  // Bathroom door on the bathroom partition wall (partA→partB).
  final bathroomDoor = b.linesByVertices(partA, partB);
  if (bathroomDoor != null) {
    b.addHole(
      lineId: bathroomDoor,
      prototype: 'door',
      offset: 0.5,
      width: 70,
    );
  }
  // Big window on the north wall (outer[1]→outer[2]).
  final northWallId = b.linesByVertices(outer[1], outer[2]);
  if (northWallId != null) {
    b.addHole(
      lineId: northWallId,
      prototype: 'window',
      offset: 0.5,
      width: 200,
    );
  }
  // Kitchenette: sink + stove on the east wall, bed on west.
  b.addItem(prototype: 'sink', x: 870, y: 250, rotation: 0);
  b.addItem(prototype: 'stove', x: 870, y: 350, rotation: 0);
  b.addItem(prototype: 'toilet', x: 850, y: 720, rotation: 0);
  b.addItem(prototype: 'bed', x: 350, y: 350, rotation: 0);
  b.addItem(prototype: 'sofa', x: 500, y: 700, rotation: 0);
  return b.build(name: name);
}

Scene _buildOneBed(IdBroker ids, String name) {
  final b = SceneBuilder(ids: ids);
  // Outer shell: 10 m × 8 m
  final outer = b.addWallLoop(const [
    (x: 200, y: 200),
    (x: 1200, y: 200),
    (x: 1200, y: 1000),
    (x: 200, y: 1000),
  ]);
  // Vertical partition splits east third into bedroom + bathroom.
  final pTop = b.addVertex(900, 200);
  final pMid = b.addVertex(900, 1000);
  b.addWall(pTop, pMid);
  // Horizontal partition cuts the east third into bedroom (top) +
  // bathroom (bottom).
  final pEast = b.addVertex(900, 700);
  final pBath = b.addVertex(1200, 700);
  b.addWall(pEast, pBath);

  // Front door on south wall.
  final southWallId = b.linesByVertices(outer[3], outer[0]);
  if (southWallId != null) {
    b.addHole(
      lineId: southWallId,
      prototype: 'door',
      offset: 0.25,
      width: 90,
    );
  }
  // Bedroom door on partition (pTop → pEast).
  final bedroomDoor = b.linesByVertices(pTop, pEast);
  if (bedroomDoor != null) {
    b.addHole(
      lineId: bedroomDoor,
      prototype: 'door',
      offset: 0.5,
      width: 80,
    );
  }
  // Bathroom door (pEast → pMid).
  final bathDoor = b.linesByVertices(pEast, pMid);
  if (bathDoor != null) {
    b.addHole(
      lineId: bathDoor,
      prototype: 'door',
      offset: 0.5,
      width: 70,
    );
  }
  // Living-room windows on the north wall (outer[1]→outer[2]).
  final northWallId = b.linesByVertices(outer[1], outer[2]);
  if (northWallId != null) {
    b.addHole(
      lineId: northWallId,
      prototype: 'window',
      offset: 0.3,
      width: 150,
    );
  }
  // Furniture
  b.addItem(prototype: 'sofa', x: 400, y: 350, rotation: 0);
  b.addItem(prototype: 'table', x: 400, y: 500, rotation: 0);
  b.addItem(prototype: 'chair', x: 320, y: 500, rotation: 0);
  b.addItem(prototype: 'chair', x: 480, y: 500, rotation: 0);
  // Kitchen along south-west
  b.addItem(prototype: 'stove', x: 250, y: 950, rotation: 0);
  b.addItem(prototype: 'sink', x: 350, y: 950, rotation: 0);
  // Bedroom
  b.addItem(prototype: 'bed', x: 1050, y: 350, rotation: 0);
  // Bathroom
  b.addItem(prototype: 'toilet', x: 1150, y: 850, rotation: 0);
  b.addItem(prototype: 'sink', x: 1050, y: 950, rotation: 0);
  return b.build(name: name);
}

Scene _buildOffice(IdBroker ids, String name) {
  final b = SceneBuilder(ids: ids);
  // Outer shell: 12 m × 8 m
  final outer = b.addWallLoop(const [
    (x: 200, y: 200),
    (x: 1400, y: 200),
    (x: 1400, y: 1000),
    (x: 200, y: 1000),
  ]);
  // Two private offices along the west, meeting room along the east.
  final office1A = b.addVertex(500, 200);
  final office1B = b.addVertex(500, 500);
  final office1C = b.addVertex(200, 500);
  b.addWall(office1A, office1B);
  b.addWall(office1B, office1C);

  final office2A = b.addVertex(500, 500);
  final office2B = b.addVertex(500, 800);
  final office2C = b.addVertex(200, 800);
  b.addWall(office2A, office2B);
  b.addWall(office2B, office2C);

  final meetingA = b.addVertex(1100, 200);
  final meetingB = b.addVertex(1100, 600);
  final meetingC = b.addVertex(1400, 600);
  b.addWall(meetingA, meetingB);
  b.addWall(meetingB, meetingC);

  // Front door
  final southWallId = b.linesByVertices(outer[3], outer[0]);
  if (southWallId != null) {
    b.addHole(
      lineId: southWallId,
      prototype: 'door',
      offset: 0.5,
      width: 100,
    );
  }
  // Office doors face the open area.
  final office1Door = b.linesByVertices(office1A, office1B);
  if (office1Door != null) {
    b.addHole(
      lineId: office1Door,
      prototype: 'door',
      offset: 0.6,
      width: 80,
    );
  }
  final office2Door = b.linesByVertices(office2A, office2B);
  if (office2Door != null) {
    b.addHole(
      lineId: office2Door,
      prototype: 'door',
      offset: 0.6,
      width: 80,
    );
  }
  final meetingDoor = b.linesByVertices(meetingA, meetingB);
  if (meetingDoor != null) {
    b.addHole(
      lineId: meetingDoor,
      prototype: 'door',
      offset: 0.4,
      width: 80,
    );
  }
  // Big windows on north + south.
  final northWallId = b.linesByVertices(outer[1], outer[2]);
  if (northWallId != null) {
    b.addHole(
      lineId: northWallId,
      prototype: 'window',
      offset: 0.25,
      width: 180,
    );
    b.addHole(
      lineId: northWallId,
      prototype: 'window',
      offset: 0.7,
      width: 180,
    );
  }
  // Furniture
  // Office 1
  b.addItem(prototype: 'table', x: 350, y: 350, width: 140, height: 70);
  b.addItem(prototype: 'chair', x: 350, y: 430);
  // Office 2
  b.addItem(prototype: 'table', x: 350, y: 650, width: 140, height: 70);
  b.addItem(prototype: 'chair', x: 350, y: 730);
  // Meeting room — long table + chairs
  b.addItem(
      prototype: 'table', x: 1250, y: 400, width: 220, height: 100);
  b.addItem(prototype: 'chair', x: 1170, y: 350);
  b.addItem(prototype: 'chair', x: 1170, y: 450);
  b.addItem(prototype: 'chair', x: 1330, y: 350);
  b.addItem(prototype: 'chair', x: 1330, y: 450);
  // Open area — clusters of desks
  for (final dx in [800.0, 950.0]) {
    for (final dy in [400.0, 600.0, 800.0]) {
      b.addItem(prototype: 'table', x: dx, y: dy, width: 120, height: 60);
      b.addItem(prototype: 'chair', x: dx, y: dy + 50);
    }
  }
  return b.build(name: name);
}
