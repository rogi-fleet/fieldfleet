import 'dart:convert';
import 'dart:typed_data';

import '../models/ai/ai_floorplan_edit.dart';
import '../models/ai/ai_floorplan_plan.dart';
import '../models/floorplan/area.dart';
import '../models/floorplan/layer.dart';
import '../models/floorplan/scene.dart';
import 'ai_service.dart';
import 'floorplan/catalog.dart';

typedef AiFloorplanProgress = void Function(String message);

/// Owns the prompt + parsing for AI text-to-floorplan generation.
/// Reuses [AiService.generateJson] for the LLM call so we get the
/// existing provider fallback + streaming for free.
class AiFloorplanService {
  AiFloorplanService({AiService? ai, Catalog? catalog})
      : _ai = ai ?? AiService(),
        _catalog = catalog ?? defaultCatalog;

  final AiService _ai;
  final Catalog _catalog;

  /// Generate a floorplan plan from a free-text prompt. Throws
  /// [FormatException] if the model returns un-parseable JSON twice.
  Future<AiFloorplanPlan> generate({
    required String prompt,
    AiFloorplanProgress? onProgress,
  }) async {
    final systemPrompt = _buildSystemPrompt(_catalog);
    final raw = await _ai.generateJson(
      systemPrompt: systemPrompt,
      userPrompt: prompt,
      maxTokens: 3000,
      timeout: const Duration(seconds: 120),
      progressMessage: 'Designing floorplan…',
      onProgress: (provider, msg) => onProgress?.call(msg),
    );
    try {
      return _parsePlan(raw);
    } on FormatException {
      // One retry with a stricter prompt.
      onProgress?.call('Re-asking for valid JSON…');
      final retry = await _ai.generateJson(
        systemPrompt: '$systemPrompt\n\n'
            'Your previous response was not valid JSON. '
            'Return ONLY a JSON object matching the schema above. '
            'No prose. No markdown fences.',
        userPrompt: prompt,
        timeout: const Duration(seconds: 120),
        progressMessage: 'Retrying…',
        onProgress: (provider, msg) => onProgress?.call(msg),
      );
      return _parsePlan(retry);
    }
  }

  AiFloorplanPlan _parsePlan(String raw) {
    final decoded = _decodeJsonObject(raw);
    return AiFloorplanPlan.fromJson(decoded);
  }

  /// Vision step for the photo-/PDF-to-floorplan flow: ask the
  /// multimodal endpoint to describe what it sees in [bytes] (a PNG
  /// or JPEG of a room photo, or a rasterized page of a floorplan
  /// PDF) as a brief the existing text generator can consume. The
  /// caller is expected to show the description to the user for
  /// review before passing it to [generate].
  Future<String> describeImage({
    required Uint8List bytes,
    AiFloorplanProgress? onProgress,
  }) {
    return _ai.describeImage(
      imageBase64: base64Encode(bytes),
      systemPrompt: _imageDescribeSystemPrompt,
      userPrompt: 'Describe this space as a floorplan brief:',
      onProgress: (provider, msg) => onProgress?.call(msg),
    );
  }

  /// Edit-in-place: takes the current scene + a free-text edit prompt
  /// ("add a balcony to the south side", "remove the kitchen island")
  /// and returns a list of operations the applier in
  /// `ai_edit_to_scene.dart` knows how to apply.
  Future<AiFloorplanEditBatch> generateEdit({
    required Scene scene,
    required String prompt,
    AiFloorplanProgress? onProgress,
  }) async {
    final systemPrompt = _buildEditSystemPrompt(_catalog, scene);
    final raw = await _ai.generateJson(
      systemPrompt: systemPrompt,
      userPrompt: prompt,
      maxTokens: 1500,
      timeout: const Duration(seconds: 120),
      progressMessage: 'Planning edits…',
      onProgress: (provider, msg) => onProgress?.call(msg),
    );
    try {
      return AiFloorplanEditBatch.fromJson(_decodeJsonObject(raw));
    } on FormatException {
      onProgress?.call('Re-asking for valid JSON…');
      final retry = await _ai.generateJson(
        systemPrompt: '$systemPrompt\n\n'
            'Your previous response was not valid JSON. '
            'Return ONLY a JSON object with an "operations" array. '
            'No prose. No markdown fences.',
        userPrompt: prompt,
        timeout: const Duration(seconds: 120),
        progressMessage: 'Retrying…',
        onProgress: (provider, msg) => onProgress?.call(msg),
      );
      return AiFloorplanEditBatch.fromJson(_decodeJsonObject(retry));
    }
  }

  Map<String, dynamic> _decodeJsonObject(String raw) {
    var json = raw.trim();
    if (json.startsWith('```json')) json = json.substring(7);
    if (json.startsWith('```')) json = json.substring(3);
    if (json.endsWith('```')) json = json.substring(0, json.length - 3);
    json = json.trim();
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Expected a JSON object at the top level',
      );
    }
    return decoded;
  }
}

/// System prompt for the vision describe step. Output is fed back into
/// the text generator, so the description must use the same vocabulary
/// (cardinal walls, standard furniture names) the generator expects.
const String _imageDescribeSystemPrompt = '''
You are a draftsperson preparing a brief for a floorplan generator.
Look at the image and write a SINGLE PARAGRAPH describing the space.

Include, where visible:
- Approximate dimensions in metres (estimate from typical sizes — sofa ~2m, doorway 0.8m, bed ~2m, fridge 0.7m).
- Overall shape (rectangular, L-shaped, open-plan studio, etc.).
- Doors and windows, naming the wall they sit on (north, south, east, or west, taking the camera as facing south).
- Furniture and fixtures by standard name only: sofa, bed, table, chair, desk, shelf, sink, toilet, stove, fridge, bath, shower.
- Where each item sits relative to the walls (e.g. "a sofa on the west wall", "kitchen along the north wall").

Rules:
- Plain prose, one paragraph. No bullet lists, no headings, no markdown.
- Only describe what you can see. Do not invent rooms or fixtures.
- Be concise and factual — this is input to another AI, not a tour.
''';

/// Build the system prompt at runtime so the allowed-prototypes list
/// stays in sync with the catalog (no stale hardcoded list).
String _buildSystemPrompt(Catalog catalog) {
  final prototypes =
      catalog.all.map((e) => e.prototype).toList()..sort();
  return '''
You are a residential and small-commercial floorplan designer. The user gives you a free-text description ("two-bedroom apartment with kitchen island, 8 m × 12 m"). You return a JSON object matching the schema below describing the rooms, doors, windows, and furniture.

CRITICAL RULES:
- Respond with ONLY a JSON object. No prose, no markdown fences, no explanation.
- All measurements are in centimetres unless you set "unit" to "m" (then everything in metres) or "ft".
- Rooms are axis-aligned rectangles. Do not let rooms overlap.
- A typical residential room is 300–500 cm wide; corridors are 100–150 cm.
- Place exterior doors on the outside of the building (no toRoom). Place interior doors between two rooms (set toRoom).
- Place windows on the outside walls of rooms (north/south/east/west faces of the room rect).

JSON SCHEMA:
{
  "unit": "cm" | "m" | "ft",                    // optional, defaults to cm
  "rooms": [
    {
      "name": "Living Room",                    // human-readable
      "x": 0, "y": 0,                           // top-left of the room rect
      "width": 500, "height": 400               // in the chosen unit
    }
  ],
  "doors": [
    {
      "from_room": "Living Room",               // required
      "to_room": "Kitchen" | null,              // null = exterior door
      "offset": 0.5,                            // 0..1 along the host wall
      "width": 90                               // door width
    }
  ],
  "windows": [
    {
      "room": "Bedroom",                        // required
      "wall": "north" | "south" | "east" | "west",
      "offset": 0.5,
      "width": 150
    }
  ],
  "items": [
    {
      "prototype": "sofa",                      // see allowed list below
      "room": "Living Room",
      "position": "center" | "north" | "south" | "east" | "west",
      "rotation": 0                             // radians, optional
    }
  ]
}

ALLOWED ITEM PROTOTYPES (use exact lowercase names):
${prototypes.join(', ')}

ROOM NAMES — prefer these standard names when applicable:
Living Room, Kitchen, Bedroom, Bathroom, Hall, Office, Dining Room,
Closet, Laundry, Entryway, Garage, Patio, Storage

EXAMPLE INPUT: "small studio with bathroom, 6m by 7m"
EXAMPLE OUTPUT:
{
  "unit": "cm",
  "rooms": [
    { "name": "Studio", "x": 0, "y": 0, "width": 600, "height": 500 },
    { "name": "Bathroom", "x": 600, "y": 0, "width": 200, "height": 250 }
  ],
  "doors": [
    { "from_room": "Studio", "to_room": null, "offset": 0.3, "width": 90 },
    { "from_room": "Studio", "to_room": "Bathroom", "offset": 0.5, "width": 70 }
  ],
  "windows": [
    { "room": "Studio", "wall": "north", "offset": 0.5, "width": 200 }
  ],
  "items": [
    { "prototype": "bed", "room": "Studio", "position": "west" },
    { "prototype": "sofa", "room": "Studio", "position": "south" },
    { "prototype": "stove", "room": "Studio", "position": "east" },
    { "prototype": "sink", "room": "Studio", "position": "east" },
    { "prototype": "toilet", "room": "Bathroom", "position": "center" },
    { "prototype": "sink", "room": "Bathroom", "position": "north" }
  ]
}
''';
}

/// Build the system prompt for edit-in-place mode. Includes a JSON
/// summary of the scene's current rooms, doors, and items so the AI
/// knows what already exists and can target operations precisely.
String _buildEditSystemPrompt(Catalog catalog, Scene scene) {
  final layer = scene.selectedLayer;
  final prototypes = catalog.all.map((e) => e.prototype).toList()..sort();

  // Index named rooms: bounding rect + the wall id on each side. Doors,
  // windows, and items resolve their room/wall through this index so
  // the AI sees something like { "from_room": "Kitchen", "to_room":
  // "Living Room", "offset": 0.4 } instead of an opaque hole count.
  final roomGeoms = <_PromptRoom>[];
  for (final area in layer.areas.values) {
    final name = (area.properties['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) continue;
    final geom = _PromptRoom.fromArea(area, layer);
    if (geom != null) roomGeoms.add(geom);
  }

  // Map each line id to the (room, side) it belongs to. A wall shared
  // between two rooms appears under both — enables door from_room /
  // to_room resolution.
  final wallToSides = <String, List<({String room, String side})>>{};
  for (final r in roomGeoms) {
    void register(String? id, String side) {
      if (id == null) return;
      (wallToSides[id] ??= []).add((room: r.name, side: side));
    }
    register(r.northWall, 'north');
    register(r.southWall, 'south');
    register(r.eastWall, 'east');
    register(r.westWall, 'west');
  }

  final doors = <Map<String, Object?>>[];
  final windows = <Map<String, Object?>>[];
  for (final h in layer.holes.values) {
    final sides = wallToSides[h.lineId] ?? const [];
    if (h.prototype == 'window') {
      final s = sides.firstOrNull;
      windows.add({
        'room': s?.room,
        'wall': s?.side,
        'offset': double.parse(h.offset.toStringAsFixed(2)),
        'width': h.width.round(),
      });
    } else {
      // Door: pick the two rooms (or one + exterior).
      final from = sides.isNotEmpty ? sides[0].room : null;
      final to = sides.length > 1 ? sides[1].room : null;
      doors.add({
        'from_room': from,
        'to_room': to,
        'offset': double.parse(h.offset.toStringAsFixed(2)),
        'width': h.width.round(),
      });
    }
  }

  final items = layer.items.values.map((it) {
    final containing = roomGeoms
        .where((r) => r.containsPoint(it.x, it.y))
        .firstOrNull;
    return {
      'prototype': it.prototype,
      'room': containing?.name,
      'position': containing?.relativePosition(it.x, it.y),
    };
  }).toList();

  final rooms = roomGeoms
      .map((r) => {
            'name': r.name,
            'x': r.minX.round(),
            'y': r.minY.round(),
            'width': (r.maxX - r.minX).round(),
            'height': (r.maxY - r.minY).round(),
          })
      .toList();

  final summary = jsonEncode({
    'unit': scene.unit,
    'rooms': rooms,
    'doors': doors,
    'windows': windows,
    'items': items,
  });

  return '''
You are editing an existing floorplan. The current scene is described
below. Apply the user's edit request as a list of operations.

CURRENT SCENE (all measurements in cm):
$summary

CRITICAL RULES:
- Respond with ONLY a JSON object. No prose, no markdown fences.
- Output shape: { "unit": "cm" | "m", "operations": [ ... ] }
- Reference existing rooms by their EXACT names from CURRENT SCENE
  (case-insensitive). Don't invent room names that aren't there
  unless you're adding a new room.
- Output the smallest set of operations that satisfies the request.
  If the user just wants to add one thing, only output that op.
- The "doors", "windows", and "items" arrays in CURRENT SCENE list
  every existing element with its room + position. When removing an
  element, target it precisely (e.g. remove_door with the matching
  from_room/to_room pair, remove_item with the matching prototype +
  room). Don't remove an element the user didn't ask to touch.
- Doors with to_room=null are exterior doors. Items with room=null
  are outside any named room — you can usually ignore them.

ALLOWED OPERATIONS:
- add_room:    { "op": "add_room", "name", "x", "y", "width", "height" }
- remove_room: { "op": "remove_room", "name" }
- rename_room: { "op": "rename_room", "from", "to" }
- add_door:    { "op": "add_door", "from_room", "to_room"?, "offset", "width" }
- remove_door: { "op": "remove_door", "from_room", "to_room"? }
- add_window:  { "op": "add_window", "room", "wall": "north"|"south"|"east"|"west", "offset", "width" }
- add_item:    { "op": "add_item", "prototype", "room", "position": "center"|"north"|"south"|"east"|"west" }
- remove_item: { "op": "remove_item", "prototype", "room"? }

ALLOWED ITEM PROTOTYPES:
${prototypes.join(', ')}

EXAMPLES:
User: "add a bedroom on the east side"
Output: { "operations": [ { "op": "add_room", "name": "Bedroom",
  "x": 700, "y": 0, "width": 400, "height": 400 } ] }

User: "remove the sofa from the living room"
Output: { "operations": [ { "op": "remove_item", "prototype": "sofa",
  "room": "Living Room" } ] }

User: "rename Bedroom to Master Bedroom"
Output: { "operations": [ { "op": "rename_room", "from": "Bedroom",
  "to": "Master Bedroom" } ] }
''';
}

/// Compact room geometry used to enrich the edit prompt with door /
/// window / item positions. Limited to axis-aligned rectangular
/// rooms, which is what `RoomOps.addRectangle` and the AI's add_room
/// op produce; other shapes get a bounding-box approximation.
class _PromptRoom {
  _PromptRoom({
    required this.name,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.northWall,
    required this.southWall,
    required this.eastWall,
    required this.westWall,
  });

  final String name;
  final double minX, minY, maxX, maxY;
  final String? northWall, southWall, eastWall, westWall;

  bool containsPoint(double x, double y) =>
      x >= minX && x <= maxX && y >= minY && y <= maxY;

  /// Map an absolute (x, y) inside the room to a coarse position label
  /// matching the AI's add_item vocabulary: 'center', 'north', 'south',
  /// 'east', 'west'. The center band is the inner 50% of each axis.
  String relativePosition(double x, double y) {
    final w = maxX - minX;
    final h = maxY - minY;
    if (w <= 0 || h <= 0) return 'center';
    final fx = (x - minX) / w;
    final fy = (y - minY) / h;
    final dx = (fx - 0.5).abs();
    final dy = (fy - 0.5).abs();
    if (dx < 0.25 && dy < 0.25) return 'center';
    if (dy >= dx) return fy < 0.5 ? 'north' : 'south';
    return fx < 0.5 ? 'west' : 'east';
  }

  static _PromptRoom? fromArea(Area area, Layer layer) {
    if (area.vertexIds.length < 3) return null;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final id in area.vertexIds) {
      final v = layer.vertices[id];
      if (v == null) return null;
      if (v.x < minX) minX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.x > maxX) maxX = v.x;
      if (v.y > maxY) maxY = v.y;
    }
    if (!minX.isFinite) return null;

    // Find the lineId on each cardinal side by scanning lines whose
    // endpoints both belong to this area's vertex set.
    final vertSet = area.vertexIds.toSet();
    String? northWall, southWall, eastWall, westWall;
    const eps = 1.0;
    for (final entry in layer.lines.entries) {
      final ids = entry.value.vertexIds;
      if (ids.length != 2) continue;
      if (!vertSet.contains(ids[0]) || !vertSet.contains(ids[1])) continue;
      final a = layer.vertices[ids[0]];
      final b = layer.vertices[ids[1]];
      if (a == null || b == null) continue;
      if ((a.y - b.y).abs() < eps) {
        if ((a.y - minY).abs() < eps) {
          northWall = entry.key;
        } else if ((a.y - maxY).abs() < eps) {
          southWall = entry.key;
        }
      } else if ((a.x - b.x).abs() < eps) {
        if ((a.x - minX).abs() < eps) {
          westWall = entry.key;
        } else if ((a.x - maxX).abs() < eps) {
          eastWall = entry.key;
        }
      }
    }
    return _PromptRoom(
      name: (area.properties['name'] as String).trim(),
      minX: minX,
      minY: minY,
      maxX: maxX,
      maxY: maxY,
      northWall: northWall,
      southWall: southWall,
      eastWall: eastWall,
      westWall: westWall,
    );
  }
}
