import 'package:flutter/material.dart';
import '../models/plan.dart';
import '../models/room.dart';
import '../widgets/blueprint_editor.dart';
import '../services/database_service.dart';
import 'floor_plan_layout_screen.dart';
import 'scanner_screen.dart';

class PlanEditorScreen extends StatefulWidget {
  final Plan plan;
  const PlanEditorScreen({Key? key, required this.plan}) : super(key: key);

  @override
  State<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends State<PlanEditorScreen> {
  
  void _addNewRoom() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text("Scan Room (AR)"),
              onTap: () {
                Navigator.pop(ctx);
                _navigateToScanner();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text("Draw Room Manually"),
              onTap: () {
                Navigator.pop(ctx);
                _navigateToManualDraw();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScannerScreen(plan: widget.plan),
      ),
    ).then((_) => setState(() {}));
  }

  void _navigateToManualDraw() {
    final newRoom = Room(
      id: DateTime.now().toIso8601String(),
      label: "New Room ${widget.plan.rooms.length + 1}",
      points: [],
      source: RoomSource.manualDraw,
    );
    _editRoom(newRoom);
  }

  void _editRoom(Room room) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BlueprintEditor(
          room: room,
          onSave: (updatedRoom) async {
            // Find and update room in plan, or add if new
            final index = widget.plan.rooms.indexWhere((r) => r.id == updatedRoom.id);
            if (index != -1) {
              widget.plan.rooms[index] = updatedRoom;
            } else {
              widget.plan.rooms.add(updatedRoom);
            }
            await DatabaseService.savePlan(widget.plan);
            setState(() {});
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.plan.name),
        actions: [
          if (widget.plan.rooms.length >= 2)
            IconButton(
              icon: const Icon(Icons.grid_view),
              tooltip: "Floor Plan Layout",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FloorPlanLayoutScreen(plan: widget.plan),
                  ),
                ).then((_) => setState(() {}));
              },
            ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // TODO: Implement plan export
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Plan Summary / Map View (Placeholder for now)
          Container(
            height: 200,
            color: Colors.grey[200],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.map, size: 48, color: Colors.grey),
                  const SizedBox(height: 8),
                  Text("${widget.plan.rooms.length} Rooms Scanned"),
                ],
              ),
            ),
          ),
          
          // Room List
          Expanded(
            child: widget.plan.rooms.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.room_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          "No rooms yet",
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Tap + to add your first room",
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: widget.plan.rooms.length,
                    itemBuilder: (context, index) {
                      final room = widget.plan.rooms[index];
                      final isArScan = room.source == RoomSource.arScan;
                      
                      return Dismissible(
                        key: Key(room.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white, size: 32),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Delete Room?"),
                              content: Text("Are you sure you want to delete '${room.label}'?"),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text("Cancel"),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  child: const Text("Delete"),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (direction) async {
                          setState(() {
                            widget.plan.rooms.removeAt(index);
                          });
                          await DatabaseService.savePlan(widget.plan);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("'${room.label}' deleted")),
                            );
                          }
                        },
                        child: Opacity(
                          opacity: room.isVisible ? 1.0 : 0.5,
                          child: Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            elevation: 2,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isArScan ? Colors.blue : Colors.green,
                                child: Icon(
                                  isArScan ? Icons.camera_alt : Icons.edit,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                room.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  decoration: room.isVisible ? null : TextDecoration.lineThrough,
                                ),
                              ),
                              subtitle: Row(
                                children: [
                                  Icon(Icons.architecture, size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text("${room.points.length} corners"),
                                  const SizedBox(width: 12),
                                  Icon(Icons.attach_file, size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text("${room.attachments.length} items"),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Visibility toggle
                                  Switch(
                                    value: room.isVisible,
                                    onChanged: (value) async {
                                      setState(() {
                                        room.isVisible = value;
                                      });
                                      await DatabaseService.savePlan(widget.plan);
                                    },
                                    activeThumbColor: Colors.blue,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isArScan ? "AR" : "Manual",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () => _editRoom(room),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewRoom,
        icon: const Icon(Icons.add_location_alt),
        label: const Text("Add Room"),
      ),
    );
  }
}
