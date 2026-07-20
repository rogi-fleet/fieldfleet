import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/plan.dart';
import '../models/room.dart';
import '../models/wall_opening.dart';
import '../services/database_service.dart';

class FloorPlanLayoutScreen extends StatefulWidget {
  final Plan plan;
  
  const FloorPlanLayoutScreen({Key? key, required this.plan}) : super(key: key);
  
  @override
  State<FloorPlanLayoutScreen> createState() => _FloorPlanLayoutScreenState();
}

class _FloorPlanLayoutScreenState extends State<FloorPlanLayoutScreen> {
  double _scale = 1.0;
  Offset _panOffset = Offset.zero;
  int? _selectedRoomIndex;
  Offset? _dragStartOffset;
  Offset? _roomStartPosition;
  
  // Snapping configuration
  static const double snapTolerance = 0.3; // 30cm tolerance for door snapping
  
  Room? _snapTarget;
  WallOpening? _snapSourceDoor;
  WallOpening? _snapTargetDoor;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Floor Plan Layout", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Reset Layout",
            onPressed: _resetLayout,
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: "Auto Arrange",
            onPressed: _autoArrange,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: "Save Layout",
            onPressed: _saveLayout,
          ),
        ],
      ),
      body: Column(
        children: [
          // Info Banner
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blue.withValues(alpha: 0.1),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Drag rooms to position them. Doors will snap together when aligned.",
                    style: TextStyle(color: Colors.blue[800]),
                  ),
                ),
              ],
            ),
          ),
          
          // Canvas
          Expanded(
            child: GestureDetector(
              onScaleStart: (details) {
                if (details.pointerCount == 1) {
                  // Single finger - check if selecting a room
                  _handleTapDown(details.localFocalPoint);
                }
              },
              onScaleUpdate: (details) {
                if (details.pointerCount == 1 && _selectedRoomIndex != null) {
                  // Dragging a room
                  _handleDrag(details.localFocalPoint);
                } else if (details.pointerCount == 2) {
                  // Two fingers - pan and zoom
                  setState(() {
                    _scale = (_scale * details.scale).clamp(0.1, 5.0);
                    _panOffset += details.focalPointDelta;
                  });
                }
              },
              onScaleEnd: (details) {
                if (_selectedRoomIndex != null) {
                  _applySnap();
                }
                setState(() {
                  _dragStartOffset = null;
                  _roomStartPosition = null;
                  _snapTarget = null;
                  _snapSourceDoor = null;
                  _snapTargetDoor = null;
                });
              },
              child: CustomPaint(
                painter: FloorPlanLayoutPainter(
                  rooms: widget.plan.rooms,
                  scale: _scale,
                  panOffset: _panOffset,
                  selectedRoomIndex: _selectedRoomIndex,
                  snapSourceDoor: _snapSourceDoor,
                  snapTargetDoor: _snapTargetDoor,
                  snapTarget: _snapTarget,
                ),
                child: Container(),
              ),
            ),
          ),
          
          // Zoom Controls
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() => _scale = (_scale / 1.2).clamp(0.1, 5.0)),
                ),
                const SizedBox(width: 16),
                Text("${(_scale * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _scale = (_scale * 1.2).clamp(0.1, 5.0)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  void _handleTapDown(Offset screenPos) {
    // Convert screen position to world position
    Offset worldPos = _screenToWorld(screenPos);
    
    // Check if tapping on a room
    for (int i = widget.plan.rooms.length - 1; i >= 0; i--) {
      Room room = widget.plan.rooms[i];
      if (_isPointInRoom(worldPos, room)) {
        setState(() {
          _selectedRoomIndex = i;
          _dragStartOffset = screenPos;
          _roomStartPosition = Offset(room.layoutPositionX, room.layoutPositionY);
        });
        return;
      }
    }
    
    // Tapped on empty space
    setState(() => _selectedRoomIndex = null);
  }
  
  void _handleDrag(Offset screenPos) {
    if (_selectedRoomIndex == null || _dragStartOffset == null || _roomStartPosition == null) return;
    
    Offset delta = (screenPos - _dragStartOffset!) / _scale;
    Room room = widget.plan.rooms[_selectedRoomIndex!];
    
    setState(() {
      room.layoutPositionX = _roomStartPosition!.dx + delta.dx;
      room.layoutPositionY = _roomStartPosition!.dy + delta.dy;
      
      // Check for snapping
      _checkSnapping(room);
    });
  }
  
  void _checkSnapping(Room room) {
    _snapTarget = null;
    _snapSourceDoor = null;
    _snapTargetDoor = null;
    
    if (room.openings.isEmpty) return;
    
    // For each door in the dragged room
    for (var sourceDoor in room.openings) {
      Offset sourceDoorWorld = _getRoomDoorWorldPosition(room, sourceDoor);
      
      // Check against doors in other rooms
      for (int i = 0; i < widget.plan.rooms.length; i++) {
        if (i == _selectedRoomIndex) continue;
        
        Room otherRoom = widget.plan.rooms[i];
        for (var targetDoor in otherRoom.openings) {
          Offset targetDoorWorld = _getRoomDoorWorldPosition(otherRoom, targetDoor);
          
          double distance = (sourceDoorWorld - targetDoorWorld).distance;
          if (distance < snapTolerance) {
            _snapTarget = otherRoom;
            _snapSourceDoor = sourceDoor;
            _snapTargetDoor = targetDoor;
            return;
          }
        }
      }
    }
  }
  
  void _applySnap() {
    if (_snapTarget == null || _snapSourceDoor == null || _snapTargetDoor == null || _selectedRoomIndex == null) return;
    
    Room room = widget.plan.rooms[_selectedRoomIndex!];
    
    // Calculate offset to align doors
    Offset sourceDoorWorld = _getRoomDoorWorldPosition(room, _snapSourceDoor!);
    Offset targetDoorWorld = _getRoomDoorWorldPosition(_snapTarget!, _snapTargetDoor!);
    
    Offset offset = targetDoorWorld - sourceDoorWorld;
    
    setState(() {
      room.layoutPositionX += offset.dx;
      room.layoutPositionY += offset.dy;
    });
  }
  
  Offset _getRoomDoorWorldPosition(Room room, WallOpening door) {
    // Transform door position from room-local to world coordinates
    double cos = math.cos(room.layoutRotation);
    double sin = math.sin(room.layoutRotation);
    
    double localX = door.position.x;
    double localY = door.position.z;
    
    double rotatedX = localX * cos - localY * sin;
    double rotatedY = localX * sin + localY * cos;
    
    return Offset(
      room.layoutPositionX + rotatedX,
      room.layoutPositionY + rotatedY,
    );
  }
  
  bool _isPointInRoom(Offset worldPos, Room room) {
    if (room.points.isEmpty) return false;
    
    // Simple bounding box check (can be improved with polygon containment)
    List<Offset> transformedPoints = room.points.map((p) {
      double cos = math.cos(room.layoutRotation);
      double sin = math.sin(room.layoutRotation);
      double rotatedX = p.x * cos - p.z * sin;
      double rotatedY = p.x * sin + p.z * cos;
      return Offset(room.layoutPositionX + rotatedX, room.layoutPositionY + rotatedY);
    }).toList();
    
    double minX = transformedPoints.map((p) => p.dx).reduce(math.min);
    double maxX = transformedPoints.map((p) => p.dx).reduce(math.max);
    double minY = transformedPoints.map((p) => p.dy).reduce(math.min);
    double maxY = transformedPoints.map((p) => p.dy).reduce(math.max);
    
    return worldPos.dx >= minX && worldPos.dx <= maxX &&
           worldPos.dy >= minY && worldPos.dy <= maxY;
  }
  
  Offset _screenToWorld(Offset screenPos) {
    return (screenPos - _panOffset) / _scale;
  }
  
  void _resetLayout() {
    setState(() {
      for (var room in widget.plan.rooms) {
        room.layoutPositionX = 0.0;
        room.layoutPositionY = 0.0;
        room.layoutRotation = 0.0;
      }
      _scale = 1.0;
      _panOffset = Offset.zero;
    });
  }
  
  void _autoArrange() {
    // Simple grid layout
    double spacing = 10.0;
    double offsetX = 0.0;
    
    setState(() {
      for (var room in widget.plan.rooms) {
        room.layoutPositionX = offsetX;
        room.layoutPositionY = 0.0;
        room.layoutRotation = 0.0;
        
        // Calculate room width
        if (room.points.isNotEmpty) {
          double maxX = room.points.map((p) => p.x).reduce(math.max);
          double minX = room.points.map((p) => p.x).reduce(math.min);
          offsetX += (maxX - minX) + spacing;
        }
      }
    });
  }
  
  void _saveLayout() async {
    await DatabaseService.savePlan(widget.plan);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Layout saved successfully")),
      );
      Navigator.pop(context);
    }
  }
}

class FloorPlanLayoutPainter extends CustomPainter {
  final List<Room> rooms;
  final double scale;
  final Offset panOffset;
  final int? selectedRoomIndex;
  final WallOpening? snapSourceDoor;
  final WallOpening? snapTargetDoor;
  final Room? snapTarget;
  
  FloorPlanLayoutPainter({
    required this.rooms,
    required this.scale,
    required this.panOffset,
    this.selectedRoomIndex,
    this.snapSourceDoor,
    this.snapTargetDoor,
    this.snapTarget,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    // Background grid
    _drawGrid(canvas, size);
    
    // Draw each room
    for (int i = 0; i < rooms.length; i++) {
      bool isSelected = i == selectedRoomIndex;
      _drawRoom(canvas, rooms[i], isSelected);
    }
    
    // Draw snap indicators
    if (snapSourceDoor != null && snapTargetDoor != null) {
      _drawSnapIndicators(canvas);
    }
  }
  
  void _drawGrid(Canvas canvas, Size size) {
    Paint gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    
    double gridSize = 1.0 * scale; // 1 meter grid
    
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }
    
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }
  }
  
  void _drawRoom(Canvas canvas, Room room, bool isSelected) {
    if (room.points.isEmpty) return;
    
    // Transform points to screen space
    List<Offset> screenPoints = room.points.map((p) {
      return _worldToScreen(Offset(
        room.layoutPositionX + p.x * math.cos(room.layoutRotation) - p.z * math.sin(room.layoutRotation),
        room.layoutPositionY + p.x * math.sin(room.layoutRotation) + p.z * math.cos(room.layoutRotation),
      ));
    }).toList();
    
    // Draw filled polygon
    Path path = Path()..moveTo(screenPoints[0].dx, screenPoints[0].dy);
    for (int i = 1; i < screenPoints.length; i++) {
      path.lineTo(screenPoints[i].dx, screenPoints[i].dy);
    }
    path.close();
    
    Paint fillPaint = Paint()
      ..color = isSelected 
          ? Colors.blue.withValues(alpha: 0.2) 
          : Colors.blueGrey.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(path, fillPaint);
    
    // Draw walls
    Paint wallPaint = Paint()
      ..color = isSelected ? Colors.blue : Colors.black
      ..strokeWidth = isSelected ? 3 : 2
      ..style = PaintingStyle.stroke;
    
    canvas.drawPath(path, wallPaint);
    
    // Draw room label
    TextPainter tp = TextPainter(
      text: TextSpan(
        text: room.label,
        style: TextStyle(
          color: isSelected ? Colors.blue : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 14,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    
    Offset center = screenPoints.reduce((a, b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2));
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    
    // Draw doors
    for (var door in room.openings) {
      _drawDoor(canvas, room, door);
    }
  }
  
  void _drawDoor(Canvas canvas, Room room, WallOpening door) {
    double cos = math.cos(room.layoutRotation);
    double sin = math.sin(room.layoutRotation);
    
    double worldX = room.layoutPositionX + door.position.x * cos - door.position.z * sin;
    double worldY = room.layoutPositionY + door.position.x * sin + door.position.z * cos;
    
    Offset screenPos = _worldToScreen(Offset(worldX, worldY));
    
    Paint doorPaint = Paint()
      ..color = door.type == OpeningType.door ? Colors.brown : Colors.lightBlue
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(screenPos, 4, doorPaint);
  }
  
  void _drawSnapIndicators(Canvas canvas) {
    if (snapSourceDoor == null || snapTargetDoor == null) return;
    
    // Draw connection line between snapping doors
    // (Implementation depends on getting door positions, simplified here)
    
    // Draw snap highlight
    // (Would draw circles or highlights at door positions)
  }
  
  Offset _worldToScreen(Offset worldPos) {
    return worldPos * scale + panOffset;
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
