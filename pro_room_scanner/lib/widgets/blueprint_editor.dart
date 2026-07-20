import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models_and_math.dart';
import '../exporters.dart';
import '../cost_estimator.dart';
import 'blueprint_painter.dart';
import '../models/room.dart';

class BlueprintEditor extends StatefulWidget {
  final Room room;
  final Function(Room) onSave; // Callback to save changes back to project
  
  const BlueprintEditor({
    Key? key, 
    required this.room,
    required this.onSave,
  }) : super(key: key);

  @override
  State<BlueprintEditor> createState() => _BlueprintEditorState();
}

// History State for Undo/Redo
class _HistoryState {
  final List<RoomPoint> points;
  final List<WallOpening> openings;
  final List<Attachment> attachments;
  
  _HistoryState({
    required this.points,
    required this.openings,
    required this.attachments,
  });
  
  _HistoryState.copy(_BlueprintEditorState state)
    : points = List.from(state._points),
      openings = List.from(state._openings),
      attachments = List.from(state._attachments);
}

enum EditorMode {
  idle,
  drawing, // Adding corners manually
  editing, // Moving corners
  placingOpening, // Placing a door/window
}

class _BlueprintEditorState extends State<BlueprintEditor> {
  late List<RoomPoint> _points;
  late List<WallOpening> _openings;
  late List<Attachment> _attachments;
  
  bool _rectified = false;
  AppUnit _unit = AppUnit.meters;
  
  // Editor State
  EditorMode _mode = EditorMode.idle;
  
  // Selection
  int? _selectedCornerIndex;
  int? _selectedOpeningIndex;
  
  // Dragging
  int? _draggingCornerIndex;
  int? _draggingOpeningIndex;
  
  // Placement Mode
  OpeningType? _placingType;
  WallOpening? _ghostOpening; // The opening following the cursor
  
  // Magnifier State
  Offset? _touchPos;
  
  // Undo/Redo History
  final List<_HistoryState> _undoStack = [];
  final List<_HistoryState> _redoStack = [];
  
  final GlobalKey _gridKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _points = List.from(widget.room.points);
    _openings = List.from(widget.room.openings);
    _attachments = List.from(widget.room.attachments);
    _saveStateToHistory();
  }
  
  void _saveStateToHistory() {
    _undoStack.add(_HistoryState.copy(this));
    _redoStack.clear();
  }
  
  void _undo() {
    if (_undoStack.length <= 1) return;
    _redoStack.add(_undoStack.removeLast());
    final previousState = _undoStack.last;
    setState(() {
      _points = List.from(previousState.points);
      _openings = List.from(previousState.openings);
      _attachments = List.from(previousState.attachments);
      _selectedCornerIndex = null;
      _selectedOpeningIndex = null;
      _ghostOpening = null;
      _mode = EditorMode.idle;
    });
  }
  
  void _redo() {
    if (_redoStack.isEmpty) return;
    final nextState = _redoStack.removeLast();
    _undoStack.add(nextState);
    setState(() {
      _points = List.from(nextState.points);
      _openings = List.from(nextState.openings);
      _attachments = List.from(nextState.attachments);
      _selectedCornerIndex = null;
      _selectedOpeningIndex = null;
    });
  }

  void _saveChanges() {
    widget.room.points = _points;
    widget.room.openings = _openings;
    widget.room.attachments = _attachments;
    widget.onSave(widget.room);
  }

  // --- Geometry Helpers ---

  (double, double, double) _getTransform(Size size) {
    if (_points.isEmpty) {
      double scale = math.min(size.width / 5, size.height / 5);
      return (scale, size.width / 2, size.height / 2);
    }

    double minX = double.infinity, maxX = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;
    for (var p in _points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.z < minZ) minZ = p.z;
      if (p.z > maxZ) maxZ = p.z;
    }

    double w = maxX - minX;
    double h = maxZ - minZ;
    if (w == 0) w = 1; if (h == 0) h = 1;

    double padding = 60;
    double scale = math.min((size.width - padding) / w, (size.height - padding) / h);
    double dx = (size.width - (w * scale)) / 2 - (minX * scale);
    double dy = (size.height - (h * scale)) / 2 - (minZ * scale);
    
    return (scale, dx, dy);
  }

  RoomPoint _screenToWorld(Offset screenPos, Size size) {
    var (scale, dx, dy) = _getTransform(size);
    double x = (screenPos.dx - dx) / scale;
    double z = (screenPos.dy - dy) / scale;
    return RoomPoint(x, z);
  }
  
  Offset _worldToScreen(RoomPoint p, Size size) {
    var (scale, dx, dy) = _getTransform(size);
    return Offset(p.x * scale + dx, p.z * scale + dy);
  }

  int? _findNearestCorner(Offset tapPos, Size canvasSize, {double radius = 40}) {
    if (_points.isEmpty) return null;
    int? nearestIndex;
    double minDistance = double.infinity;

    for (int i = 0; i < _points.length; i++) {
      final cornerPos = _worldToScreen(_points[i], canvasSize);
      final distance = (tapPos - cornerPos).distance;
      if (distance < minDistance && distance < radius) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    return nearestIndex;
  }
  
  int? _findTappedOpening(Offset tapPos, Size canvasSize) {
    if (_openings.isEmpty) return null;
    for (int i = 0; i < _openings.length; i++) {
      Offset opPos = _worldToScreen(_openings[i].position, canvasSize);
      if ((tapPos - opPos).distance < 30) { // Increased hit radius for openings
        return i;
      }
    }
    return null;
  }

  // --- Interaction Handlers ---

  void _handlePanStart(DragStartDetails d) {
    final RenderBox? box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = d.localPosition;
    
    setState(() => _touchPos = localPos);

    if (_mode == EditorMode.editing) {
      // Check if we grabbed a corner
      int? cornerIndex = _findNearestCorner(localPos, box.size);
      if (cornerIndex != null) {
        _draggingCornerIndex = cornerIndex;
        _selectedCornerIndex = cornerIndex;
        _selectedOpeningIndex = null;
        _saveStateToHistory(); // Save before drag starts
        return;
      }
    }
    
    // Check if we grabbed an opening (in any mode, or maybe just idle/editing?)
    // Let's allow moving openings in idle or editing
    if (_mode == EditorMode.idle || _mode == EditorMode.editing) {
      int? openingIndex = _findTappedOpening(localPos, box.size);
      if (openingIndex != null) {
        _draggingOpeningIndex = openingIndex;
        _selectedOpeningIndex = openingIndex;
        _selectedCornerIndex = null;
        _saveStateToHistory();
        return;
      }
    }
  }

  void _handlePanUpdate(DragUpdateDetails d) {
    final RenderBox? box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = d.localPosition;
    
    setState(() => _touchPos = localPos);

    if (_mode == EditorMode.placingOpening && _placingType != null) {
      _updateGhostOpening(localPos, box.size);
    } else if (_draggingCornerIndex != null) {
      setState(() {
        _points[_draggingCornerIndex!] = _screenToWorld(localPos, box.size);
      });
    } else if (_draggingOpeningIndex != null) {
      _moveOpening(_draggingOpeningIndex!, localPos, box.size);
    }
  }

  void _handlePanEnd(DragEndDetails d) {
    setState(() {
      _touchPos = null;
      _draggingCornerIndex = null;
      _draggingOpeningIndex = null;
    });
  }

  void _handleTapUp(TapUpDetails d) {
    final RenderBox? box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = d.localPosition;

    if (_mode == EditorMode.drawing) {
      setState(() {
        _points.add(_screenToWorld(localPos, box.size));
      });
    } else if (_mode == EditorMode.placingOpening) {
      if (_ghostOpening != null) {
        _saveStateToHistory();
        setState(() {
          _openings.add(_ghostOpening!);
          _ghostOpening = null;
          _mode = EditorMode.idle; // Exit placement mode after one placement? Or stay? Let's exit for now.
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Opening placed"), duration: Duration(milliseconds: 500)),
        );
      }
    } else {
      // Select corner or opening
      int? cornerIndex = _findNearestCorner(localPos, box.size);
      int? openingIndex = _findTappedOpening(localPos, box.size);
      
      setState(() {
        if (cornerIndex != null) {
          _selectedCornerIndex = cornerIndex;
          _selectedOpeningIndex = null;
          // If in editing mode, we are already ready to drag.
        } else if (openingIndex != null) {
          _selectedOpeningIndex = openingIndex;
          _selectedCornerIndex = null;
        } else {
          // Deselect all
          _selectedCornerIndex = null;
          _selectedOpeningIndex = null;
        }
      });
    }
  }
  
  void _handleLongPressStart(LongPressStartDetails d) {
    final RenderBox? box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = d.localPosition;
    
    int? cornerIndex = _findNearestCorner(localPos, box.size);
    if (cornerIndex != null) {
      // Show context menu for corner
      _showCornerMenu(d.globalPosition, cornerIndex);
    }
  }

  // --- Logic ---

  void _updateGhostOpening(Offset screenPos, Size size) {
    RoomPoint worldPos = _screenToWorld(screenPos, size);
    var (bestPos, bestRot) = _snapToWall(worldPos);
    
    if (bestPos != null) {
      setState(() {
        _ghostOpening = WallOpening(
          position: bestPos,
          rotation: bestRot,
          type: _placingType!,
          width: 0.9,
        );
      });
    }
  }

  void _moveOpening(int index, Offset screenPos, Size size) {
    RoomPoint worldPos = _screenToWorld(screenPos, size);
    var (bestPos, bestRot) = _snapToWall(worldPos);
    
    if (bestPos != null) {
      setState(() {
        _openings[index] = WallOpening(
          position: bestPos,
          rotation: bestRot,
          type: _openings[index].type,
          width: _openings[index].width,
        );
      });
    }
  }

  (RoomPoint?, double) _snapToWall(RoomPoint worldPos) {
    if (_points.length < 2) return (null, 0.0);

    double minDist = double.infinity;
    RoomPoint? bestPos;
    double bestRot = 0;

    for (int i = 0; i < _points.length; i++) {
      RoomPoint p1 = _points[i];
      RoomPoint p2 = _points[(i + 1) % _points.length];

      RoomPoint projected = GeometryEngine.projectPointOnSegment(worldPos, p1, p2);
      double dist = worldPos.distanceTo(projected);

      if (dist < minDist) {
        minDist = dist;
        bestPos = projected;
        bestRot = math.atan2(p2.z - p1.z, p2.x - p1.x);
      }
    }
    return (bestPos, bestRot);
  }

  void _showCornerMenu(Offset globalPos, int index) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy),
      items: [
        const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text("Delete Corner")])),
      ],
    ).then((value) {
      if (value == 'delete') {
        _deleteCorner(index);
      }
    });
  }

  void _deleteCorner(int index) {
    if (_points.length <= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot delete corner: room must have at least 3 corners"), backgroundColor: Colors.red),
      );
      return;
    }
    _saveStateToHistory();
    setState(() {
      _points.removeAt(index);
      _selectedCornerIndex = null;
    });
  }

  void _startPlacingOpening(OpeningType type) {
    setState(() {
      _mode = EditorMode.placingOpening;
      _placingType = type;
      _selectedCornerIndex = null;
      _selectedOpeningIndex = null;
      _ghostOpening = null; // Will appear when dragging/tapping
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Tap or drag on a wall to place."), duration: Duration(seconds: 2)),
    );
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    double area = GeometryEngine.calculateArea(_points);
    int floorLevel = _points.isNotEmpty ? _points.first.floorLevel : 0;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("Floor ${floorLevel + 1} Plan"),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _undoStack.length > 1 ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: _redoStack.isNotEmpty ? _redo : null,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              _saveChanges();
              Navigator.pop(context);
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'properties') _showRoomPropertiesDialog();
              if (val == 'units') setState(() => _unit = _unit == AppUnit.meters ? AppUnit.feet : AppUnit.meters);
              if (val == 'estimate') CostEstimator.showEstimateDialog(context, _points);
              if (val.startsWith('export_')) _handleExport(val.substring(7));
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'properties', child: Text("Room Properties")),
              const PopupMenuItem(value: 'units', child: Text("Toggle Units")),
              const PopupMenuItem(value: 'estimate', child: Text("Cost Estimator")),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'export_pdf', child: Text("Export PDF")),
              const PopupMenuItem(value: 'export_dxf', child: Text("Export DXF")),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          GestureDetector(
            onPanStart: _handlePanStart,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            onTapUp: _handleTapUp,
            onLongPressStart: _handleLongPressStart,
            child: Container(
              key: _gridKey,
              color: Colors.white,
              width: double.infinity,
              height: double.infinity,
              child: CustomPaint(
                painter: BlueprintPainter(
                  _points,
                  _openings,
                  _unit,
                  _selectedOpeningIndex,
                  attachments: _attachments,
                  selectedCornerIndex: _selectedCornerIndex,
                  ghostOpening: _ghostOpening,
                ),
              ),
            ),
          ),
          
          // Stats
          Positioned(
            top: 16, left: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(UnitConverter.formatArea(area, _unit), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          
          // Magnifier
          if (_touchPos != null)
            Positioned(
              left: _touchPos!.dx - 50,
              top: _touchPos!.dy - 100,
              child: const RawMagnifier(
                decoration: MagnifierDecoration(
                  shape: CircleBorder(side: BorderSide(color: Color(0xFF1A237E), width: 3)),
                  shadows: [BoxShadow(blurRadius: 8, color: Colors.black26)],
                ),
                size: Size(100, 100),
                magnificationScale: 2.0,
              ),
            ),

          // Toolbar
          Positioned(
            bottom: 32, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [const BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildToolButton(
                      icon: Icons.pan_tool,
                      active: _mode == EditorMode.idle,
                      onTap: () => setState(() => _mode = EditorMode.idle),
                      tooltip: "Pan / Select",
                    ),
                    _buildToolButton(
                      icon: Icons.edit_location_alt,
                      active: _mode == EditorMode.editing,
                      onTap: () => setState(() => _mode = EditorMode.editing),
                      tooltip: "Move Corners",
                    ),
                    _buildToolButton(
                      icon: Icons.add_circle_outline,
                      active: _mode == EditorMode.drawing,
                      onTap: () => setState(() => _mode = EditorMode.drawing),
                      tooltip: "Add Corners",
                    ),
                    Container(width: 1, height: 24, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),
                    _buildToolButton(
                      icon: Icons.door_sliding_outlined,
                      active: _mode == EditorMode.placingOpening && _placingType == OpeningType.door,
                      onTap: () => _startPlacingOpening(OpeningType.door),
                      tooltip: "Add Door",
                    ),
                    _buildToolButton(
                      icon: Icons.window_outlined,
                      active: _mode == EditorMode.placingOpening && _placingType == OpeningType.window,
                      onTap: () => _startPlacingOpening(OpeningType.window),
                      tooltip: "Add Window",
                    ),
                    if (_selectedCornerIndex != null || _selectedOpeningIndex != null) ...[
                      Container(width: 1, height: 24, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),
                      _buildToolButton(
                        icon: Icons.delete_outline,
                        active: false,
                        color: Colors.redAccent,
                        onTap: () {
                          if (_selectedCornerIndex != null) _deleteCorner(_selectedCornerIndex!);
                          if (_selectedOpeningIndex != null) {
                            _saveStateToHistory();
                            setState(() {
                              _openings.removeAt(_selectedOpeningIndex!);
                              _selectedOpeningIndex = null;
                            });
                          }
                        },
                        tooltip: "Delete Selected",
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildToolButton({required IconData icon, required bool active, required VoidCallback onTap, Color? color, String? tooltip}) {
    return IconButton(
      icon: Icon(icon),
      color: color ?? (active ? Colors.amber : Colors.white70),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }

  void _showRoomPropertiesDialog() {
    // Implementation similar to original
    final labelController = TextEditingController(text: widget.room.label);
    int selectedFloor = widget.room.floorLevel;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Room Properties"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: labelController,
              decoration: const InputDecoration(labelText: "Room Name"),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: selectedFloor,
              decoration: const InputDecoration(labelText: "Floor Level"),
              items: List.generate(5, (i) => i).map((floor) {
                return DropdownMenuItem(value: floor, child: Text("Floor ${floor + 1}"));
              }).toList(),
              onChanged: (value) {
                if (value != null) selectedFloor = value;
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                widget.room.label = labelController.text;
                widget.room.floorLevel = selectedFloor;
              });
              Navigator.pop(ctx);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _handleExport(String format) async {
    // ... (Export logic same as original)
     ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Generating export...")),
    );
    
    try {
      String? path;
      if (format == 'pdf') {
        await Exporter.generatePdfReport(_points, GeometryEngine.calculateArea(_points), _attachments);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("PDF Report saved to Downloads"), backgroundColor: Colors.green),
        );
      } else if (format == 'dxf') {
        path = await Exporter.generateDxf(_points, "room");
      }
      
      if (path != null) {
        await Share.shareXFiles([XFile(path)], text: 'Room Scan Export');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Export failed: $e"), backgroundColor: Colors.red),
      );
    }
  }
}
