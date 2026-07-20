import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'package:image_picker/image_picker.dart';

import '../models_and_math.dart';
import '../services/database_service.dart';
import '../widgets/ar_overlays.dart';
import '../widgets/glass_container.dart';
import '../widgets/mini_map_painter.dart';
import 'plan_editor_screen.dart';

class ScannerScreen extends StatefulWidget {
  final Plan plan;
  const ScannerScreen({Key? key, required this.plan}) : super(key: key);
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  ARSessionManager? arSessionManager;
  ARObjectManager? arObjectManager;
  ARAnchorManager? arAnchorManager;
  
  List<RoomPoint> _points = [];
  List<Attachment> _attachments = [];
  List<ARNode> _nodes = [];
  List<ARNode> _attachmentNodes = [];
  bool _planeDetected = false;
  String? _currentRoomLabel;
  int _currentFloorLevel = 0;
  double? _floorBaseHeight;
  List<double> _ceilingHeights = [];
  
  late stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _isListening = false;
  
  String _guidanceMessage = "Scan floor to detect planes...";
  Color _guidanceColor = Colors.white;
  DateTime? _lastTapTime;
  RoomPoint? _lastTapPosition;
  double? _lastHitDistance;

  bool _isScanningFloor = true;
  double _scanProgress = 0.0;
  bool _showTutorial = true;
  bool _planeHitDetected = false;
  double? _currentHitDistance;
  bool _isSaving = false;

  double? _ghostLineLength;
  bool _isGhostLineSnapped = false;
  ARNode? _cursorNode;
  
  AttachmentType? _pendingAttachmentType;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }
  
  Future<void> _initSpeech() async {
    _speech = stt.SpeechToText();
    _speechAvailable = await _speech.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    arSessionManager?.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontal,
          ),
          
          FloorScanningOverlay(
            isScanning: _isScanningFloor,
            scanProgress: _scanProgress,
          ),

          CrosshairOverlay(
            isPlaneDetected: _planeHitDetected,
            distance: _currentHitDistance,
            ghostLineLength: _ghostLineLength,
            isSnapped: _isGhostLineSnapped,
          ),
          
          // TOP HUD: Guidance & Stats (Refined)
          Positioned(
            top: 60, left: 16, right: 16,
            child: Column(
              children: [
                // Guidance Pill
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getGuidanceIcon(), color: _guidanceColor, size: 18),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _guidanceMessage,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Stats Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_ceilingHeights.isNotEmpty)
                      GlassContainer(
                        opacity: 0.4,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('FLOOR ${_currentFloorLevel + 1}', 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text('CEILING: ${(_ceilingHeights.reduce((a, b) => a + b) / _ceilingHeights.length).toStringAsFixed(2)}m',
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    const Spacer(),
                    if (_points.isNotEmpty)
                      Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CustomPaint(painter: MiniMapPainter(_points)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // BOTTOM CONTROLS (Refined)
          Positioned(
            bottom: 40, left: 24, right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildControlButton(
                  icon: Icons.undo_rounded,
                  label: "Undo",
                  onTap: () { 
                    if (_points.isNotEmpty) {
                      setState(() {
                        _points.removeLast();
                        if (_nodes.isNotEmpty) {
                          arObjectManager!.removeNode(_nodes.last);
                          _nodes.removeLast();
                        }
                        if (_ceilingHeights.isNotEmpty) _ceilingHeights.removeLast();
                      });
                    }
                  },
                ),
                
                _buildControlButton(
                  icon: Icons.add_circle_outline,
                  label: "Tools",
                  onTap: _showToolsMenu,
                ),

                GestureDetector(
                  onTap: _showRoomLabelDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))
                      ]
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.label_outline, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _currentRoomLabel ?? "Label Room",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                
                FloatingActionButton(
                  heroTag: "done",
                  backgroundColor: const Color(0xFF00C853),
                  elevation: 4,
                  onPressed: _isSaving ? null : _finishScan,
                  child: _isSaving 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_rounded, size: 32),
                ),
              ],
            ),
          ),
          
          // Back Button
          Positioned(
            top: 50, left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
      bottomSheet: _showTutorial ? TutorialOverlay(onDismiss: () => setState(() => _showTutorial = false)) : null,
    );
  }
  
  Widget _buildControlButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Icon(icon, color: const Color(0xFF1A237E), size: 24),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
      ],
    );
  }

  void _onARViewCreated(ARSessionManager sm, ARObjectManager om, ARAnchorManager am, ARLocationManager lm) {
    arSessionManager = sm; arObjectManager = om; arAnchorManager = am;
    arSessionManager!.onInitialize(showFeaturePoints: false, showPlanes: true);
    arObjectManager!.onInitialize();
    arSessionManager!.onPlaneOrPointTap = _handleTap;
    _startScanningLoop();
  }

  void _startScanningLoop() {
    Future.doWhile(() async {
      if (!mounted) return false;
      try {
        Matrix4? pose = await arSessionManager!.getCameraPose();
        if (pose != null) {
          vector.Vector3 origin = vector.Vector3(pose.getColumn(3).x, pose.getColumn(3).y, pose.getColumn(3).z);
          vector.Vector3 forward = vector.Vector3(-pose.getColumn(2).x, -pose.getColumn(2).y, -pose.getColumn(2).z).normalized();
          
          if (_floorBaseHeight != null) {
             double t = (_floorBaseHeight! - origin.y) / forward.y;
             if (t > 0) {
               vector.Vector3 intersection = origin + forward * t;
               if (_points.isNotEmpty) {
                 RoomPoint currentPos = RoomPoint(intersection.x, intersection.z, y: _floorBaseHeight!);
                 RoomPoint lastPoint = _points.last;
                 double dist = currentPos.distanceTo(lastPoint);
                 
                 bool snapped = false;
                 if (_points.length >= 2) {
                    RoomPoint p1 = _points[_points.length - 2];
                    RoomPoint p2 = _points.last;
                    double prevAngle = math.atan2(p2.z - p1.z, p2.x - p1.x);
                    double currAngle = math.atan2(currentPos.z - p2.z, currentPos.x - p2.x);
                    double diff = (currAngle - prevAngle).abs();
                    while (diff > math.pi) diff -= 2 * math.pi;
                    diff = diff.abs();
                    if ((diff - math.pi / 2).abs() < 0.1) snapped = true;
                 }
                 
                 if (mounted) {
                   setState(() {
                     _ghostLineLength = dist;
                     _isGhostLineSnapped = snapped;
                     _currentHitDistance = t; 
                     _planeHitDetected = true; 
                   });
                 }
               } else {
                 if (mounted) {
                    setState(() {
                      _currentHitDistance = t;
                      _planeHitDetected = true;
                    });
                 }
               }
               
               if (_cursorNode == null) {
                  _cursorNode = ARNode(
                    type: NodeType.webGLB,
                    uri: "https://github.com/KhronosGroup/glTF-Sample-Models/raw/master/2.0/Box/glTF-Binary/Box.glb",
                    scale: vector.Vector3(0.2, 0.01, 0.2),
                    position: intersection,
                    rotation: vector.Vector4(1.0, 0.0, 0.0, 0.0),
                  );
                  await arObjectManager!.addNode(_cursorNode!);
               } else {
                  _cursorNode!.position = intersection;
                  arObjectManager!.removeNode(_cursorNode!);
                  _cursorNode = ARNode(
                    type: NodeType.webGLB,
                    uri: "https://github.com/KhronosGroup/glTF-Sample-Models/raw/master/2.0/Box/glTF-Binary/Box.glb",
                    scale: vector.Vector3(0.2, 0.01, 0.2),
                    position: intersection,
                    rotation: vector.Vector4(1.0, 0.0, 0.0, 0.0),
                  );
                  await arObjectManager!.addNode(_cursorNode!);
               }
             } else {
               if (_cursorNode != null) {
                 arObjectManager!.removeNode(_cursorNode!);
                 _cursorNode = null;
               }
             }
          }
        }
      } catch (e) {
        // Ignore
      }

      await Future.delayed(const Duration(milliseconds: 50));
      
      if (_planeDetected && _isScanningFloor) {
        if (mounted) {
          setState(() {
            _scanProgress += 0.05;
            if (_scanProgress >= 1.0) {
              _isScanningFloor = false;
              _updateGuidance("Floor detected! Tap corners to measure.", Colors.green);
            }
          });
        }
      }
      return true;
    });
  }

  Future<void> _handleTap(List<ARHitTestResult> hits) async {
    if (hits.isEmpty) return;
    
    if (_pendingAttachmentType != null) {
      var hit = hits.first;
      var transform = hit.worldTransform;
      
      String data = "";
      if (_pendingAttachmentType == AttachmentType.photo) {
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(source: ImageSource.camera);
        if (image == null) {
          setState(() => _pendingAttachmentType = null);
          return;
        }
        data = image.path;
      } else if (_pendingAttachmentType == AttachmentType.note) {
        String? text = await _showInputDialog("Enter Note");
        if (text == null || text.isEmpty) {
          setState(() => _pendingAttachmentType = null);
          return;
        }
        data = text;
      } else if (_pendingAttachmentType == AttachmentType.moisture) {
        String? text = await _showInputDialog("Moisture Value (e.g. 15%)");
        if (text == null || text.isEmpty) {
          setState(() => _pendingAttachmentType = null);
          return;
        }
        data = text;
      }

      var attachment = Attachment.fromVector3(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: _pendingAttachmentType!,
        position: hit.worldTransform.getTranslation(),
        data: data,
        timestamp: DateTime.now(),
      );

      setState(() {
        _attachments.add(attachment);
        _pendingAttachmentType = null;
      });

      _addAttachmentNode(attachment);
      return;
    }

    final hit = hits.firstWhere(
      (r) => r.type == ARHitTestResultType.plane, 
      orElse: () => ARHitTestResult(ARHitTestResultType.undefined, 0, Matrix4.identity())
    );
    if (hit.type != ARHitTestResultType.plane) {
      _updateGuidance("No plane detected - scan floor", Colors.orange);
      return;
    }

    setState(() => _planeDetected = true);

    var t = hit.worldTransform;
    double yPos = t.entry(1, 3);
    var raw = RoomPoint(t.entry(0, 3), t.entry(2, 3), y: yPos);
    
    if (_floorBaseHeight == null) {
      _floorBaseHeight = yPos;
    }
    
    double elevationChange = (yPos - _floorBaseHeight!).abs();
    if (elevationChange > 1.5 && _points.isNotEmpty) {
      if (yPos > _floorBaseHeight!) {
        _currentFloorLevel++;
      } else {
        _currentFloorLevel--;
      }
      _floorBaseHeight = yPos;
      _updateGuidance("Floor level changed to ${_currentFloorLevel + 1}", Colors.blue);
    }
    
    double estimatedCeilingHeight = 1.5 + (2.4 - yPos.abs());
    if (estimatedCeilingHeight > 1.5 && estimatedCeilingHeight < 5.0) {
      _ceilingHeights.add(estimatedCeilingHeight);
    }
    
    double hitDistance = math.sqrt(
      math.pow(t.entry(0, 3), 2) + 
      math.pow(t.entry(1, 3), 2) + 
      math.pow(t.entry(2, 3), 2)
    );
    
    _analyzeScanQuality(raw, hitDistance);

    RoomPoint? prev = _points.isNotEmpty ? _points.last : null;
    RoomPoint finalPoint = GeometryEngine.applySnapping(raw, prev);
    
    if (_points.length >= 2) {
      RoomPoint p1 = _points[_points.length - 2];
      RoomPoint p2 = _points.last;
      
      double v1x = p2.x - p1.x;
      double v1z = p2.z - p1.z;
      
      double v2x = finalPoint.x - p2.x;
      double v2z = finalPoint.z - p2.z;
      
      double angle1 = math.atan2(v1z, v1x);
      double angle2 = math.atan2(v2z, v2x);
      
      double diff = angle2 - angle1;
      while (diff <= -math.pi) diff += 2 * math.pi;
      while (diff > math.pi) diff -= 2 * math.pi;
      
      double targetAngle = angle2;
      bool snapped90 = false;
      
      if ((diff.abs() - math.pi / 2).abs() < 0.15) {
        if (diff > 0) targetAngle = angle1 + math.pi / 2;
        else targetAngle = angle1 - math.pi / 2;
        snapped90 = true;
      } else if ((diff.abs() - math.pi).abs() < 0.15 || diff.abs() < 0.15) {
        if (diff.abs() < 1.5) targetAngle = angle1;
        else targetAngle = angle1 + math.pi;
        snapped90 = true;
      }
      
      if (snapped90) {
        double length = math.sqrt(v2x * v2x + v2z * v2z);
        double newX = p2.x + length * math.cos(targetAngle);
        double newZ = p2.z + length * math.sin(targetAngle);
        finalPoint = RoomPoint(newX, newZ, y: finalPoint.y);
        HapticFeedback.heavyImpact();
        _updateGuidance("Snapped to 90°", Colors.blue);
      }
    }
    
    finalPoint.roomLabel = _currentRoomLabel;
    finalPoint.floorLevel = _currentFloorLevel;
    finalPoint.y = yPos;

    if (_points.length >= 3 && GeometryEngine.isClosingLoop(finalPoint, _points.first)) {
      _finishScan();
      return;
    }

    var anchor = ARPlaneAnchor(transformation: hit.worldTransform);
    bool? added = await arAnchorManager!.addAnchor(anchor);
    if (added == true) {
      await _addEnhancedCornerMarker(finalPoint, anchor);
      setState(() => _points.add(finalPoint));
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Corner ${_points.length} added ✓'),
          duration: const Duration(milliseconds: 800),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _analyzeScanQuality(RoomPoint currentPoint, double hitDistance) {
    final now = DateTime.now();
    
    if (hitDistance < 0.5) {
      _updateGuidance("Step back - too close to surface ⚠", Colors.orange);
      HapticFeedback.lightImpact();
      return;
    }
    
    if (_lastTapTime != null && _lastTapPosition != null) {
      final timeDiff = now.difference(_lastTapTime!).inMilliseconds;
      final distance = currentPoint.distanceTo(_lastTapPosition!);
      
      if (timeDiff < 1000 && distance > 1.0) {
        _updateGuidance("Slow down - moving too quickly ⚠", Colors.orange);
        HapticFeedback.lightImpact();
        _lastTapTime = now;
        _lastTapPosition = currentPoint;
        _lastHitDistance = hitDistance;
        return;
      }
      
      if (distance > 0.3 && distance < 2.0 && timeDiff > 500) {
        _updateGuidance("Good scan quality ✓", Colors.green);
      }
    }
    
    if (hitDistance > 3.0) {
      _updateGuidance("Point camera down more ⚠", Colors.orange);
      HapticFeedback.lightImpact();
    } else if (hitDistance >= 0.5 && hitDistance <= 2.5) {
      _updateGuidance("Excellent coverage ✓", Colors.green);
    }
    
    _lastTapTime = now;
    _lastTapPosition = currentPoint;
    _lastHitDistance = hitDistance;
  }
  
  void _updateGuidance(String message, Color color) {
    setState(() {
      _guidanceMessage = message;
      _guidanceColor = color;
    });
  }
  
  IconData _getGuidanceIcon() {
    if (_guidanceColor == Colors.green) return Icons.check_circle;
    if (_guidanceColor == Colors.orange) return Icons.warning;
    if (_guidanceColor == Colors.red) return Icons.error;
    return Icons.info;
  }

  void _showToolsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassContainer(
        opacity: 0.9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text("Add Photo", style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _addAttachment(AttachmentType.photo); },
            ),
            ListTile(
              leading: const Icon(Icons.note_add, color: Colors.yellow),
              title: const Text("Add Note", style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _addAttachment(AttachmentType.note); },
            ),
            ListTile(
              leading: const Icon(Icons.water_drop, color: Colors.red),
              title: const Text("Moisture Reading", style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _addAttachment(AttachmentType.moisture); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addAttachment(AttachmentType type) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Tap on a surface to place the attachment icon")),
    );
    setState(() {
      _pendingAttachmentType = type;
    });
  }

  Future<void> _addEnhancedCornerMarker(RoomPoint point, ARPlaneAnchor anchor) async {
    var sphereNode = ARNode(
      type: NodeType.webGLB,
      uri: "https://github.com/KhronosGroup/glTF-Sample-Models/raw/master/2.0/Sphere/glTF-Binary/Sphere.glb",
      scale: vector.Vector3(0.1, 0.1, 0.1),
      position: vector.Vector3(0, 0, 0),
      rotation: vector.Vector4(1.0, 0.0, 0.0, 0.0),
    );
    await arObjectManager!.addNode(sphereNode, planeAnchor: anchor);
    _nodes.add(sphereNode);
  }

  Future<void> _addAttachmentNode(Attachment att) async {
    var node = ARNode(
      type: NodeType.webGLB,
      uri: "https://github.com/KhronosGroup/glTF-Sample-Models/raw/master/2.0/Box/glTF-Binary/Box.glb",
      scale: vector.Vector3(0.08, 0.08, 0.08),
      position: att.position,
      rotation: vector.Vector4(1.0, 0.0, 0.0, 0.0),
    );
    arObjectManager!.addNode(node);
    _attachmentNodes.add(node);
  }

  Future<String?> _showInputDialog(String title) async {
    String val = "";
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          autofocus: true,
          onChanged: (v) => val = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          TextButton(onPressed: () => Navigator.pop(ctx, val), child: const Text("OK")),
        ],
      ),
    );
  }

  void _showRoomLabelDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              const Text("Set Room Label"),
              const Spacer(),
              if (_speechAvailable)
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening ? Colors.red : Colors.blue,
                  ),
                  onPressed: () async {
                    if (_isListening) {
                      await _speech.stop();
                      setState(() => _isListening = false);
                    } else {
                      bool available = await _speech.initialize();
                      if (available) {
                        setState(() => _isListening = true);
                        _speech.listen(
                          onResult: (result) {
                            String spokenText = result.recognizedWords.toLowerCase();
                            String? matchedRoom = _matchRoomType(spokenText);
                            if (matchedRoom != null) {
                              this.setState(() => _currentRoomLabel = matchedRoom);
                              Navigator.pop(context);
                              _speech.stop();
                              setState(() => _isListening = false);
                            }
                          },
                        );
                      }
                    }
                  },
                ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isListening)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Listening... Say a room name",
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                )
              else
                const Text("Select room type:"),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  'Bedroom', 'Bathroom', 'Kitchen', 'Living Room',
                  'Dining Room', 'Office', 'Laundry', 'Garage', 'Hallway'
                ].map((label) => ElevatedButton(
                  onPressed: () {
                    this.setState(() => _currentRoomLabel = label);
                    Navigator.pop(context);
                  },
                  child: Text(label),
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (_isListening) {
                  _speech.stop();
                  setState(() => _isListening = false);
                }
                Navigator.pop(context);
              },
              child: const Text("Cancel"),
            ),
          ],
        ),
      ),
    );
  }
  
  String? _matchRoomType(String spokenText) {
    const roomTypes = [
      'bedroom', 'bathroom', 'kitchen', 'living room',
      'dining room', 'office', 'laundry', 'garage', 'hallway'
    ];
    
    for (var room in roomTypes) {
      if (spokenText.contains(room)) {
        return room.split(' ').map((word) => 
          word[0].toUpperCase() + word.substring(1)
        ).join(' ');
      }
    }
    return null;
  }

  void _finishScan() async {
    if (_points.length < 3) {
      _updateGuidance("Need at least 3 points to close room", Colors.red);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final room = Room(
        id: DateTime.now().toIso8601String(),
        label: _currentRoomLabel ?? "Room ${widget.plan.rooms.length + 1}",
        points: List.from(_points),
        attachments: List.from(_attachments),
        floorLevel: _currentFloorLevel,
        ceilingHeight: _ceilingHeights.isNotEmpty 
            ? _ceilingHeights.reduce((a, b) => a + b) / _ceilingHeights.length 
            : 2.4,
        source: RoomSource.arScan,
      );

      widget.plan.rooms.add(room);
      await DatabaseService.savePlan(widget.plan);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PlanEditorScreen(plan: widget.plan),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error saving room: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}
