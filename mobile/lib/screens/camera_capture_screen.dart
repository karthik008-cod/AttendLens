import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';
import 'package:mobile/screens/attendance_review_screen.dart';

class CameraCaptureScreen extends StatefulWidget {
  final int classId;
  final String className;

  const CameraCaptureScreen({super.key, required this.classId, required this.className});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isAiWarmingUp = false;
  String _statusMessage = "Slowly pan across the classroom";
  Timer? _liveStreamTimer;
  bool _isStreamingFrame = false;
  final Map<int, Map<String, dynamic>> _livePresentStudents = {};
  List<Map<String, dynamic>> _allClassStudents = [];
  List<Map<String, dynamic>> _liveFaceBoxes = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadClassStudents();
  }

  @override
  void dispose() {
    _liveStreamTimer?.cancel();
    _cameraController?.dispose();
    ApiService.disconnectLiveScanWs();
    super.dispose();
  }

  Future<void> _loadClassStudents() async {
    try {
      final list = await ApiService.getStudents(widget.classId);
      if (mounted) {
        setState(() {
          _allClassStudents = List<Map<String, dynamic>>.from(list);
        });
      }
    } catch (e) {
      debugPrint("Error loading class students: $e");
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras!.first,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) setState(() {});
      }
    } catch (e) {
      // Ignore in demo mode
    }
  }

  DateTime? _lastFrameSendTime;

  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    
    setState(() {
      _isRecording = true;
      _isAiWarmingUp = true;
      _isStreamingFrame = false;
      _lastFrameSendTime = null;
      _livePresentStudents.clear();
      _liveFaceBoxes.clear();
      _statusMessage = "⏳ Making the AI ready... Initializing ultra-fast stream!";
    });

    // Connect WebSocket (#3)
    try {
      final channel = ApiService.connectLiveScanWs(widget.classId);
      channel.stream.listen((message) {
        if (!mounted || !_isRecording) return;
        try {
          final results = json.decode(message as String);
          final matchedList = List<Map<String, dynamic>>.from(results["matched_students"] ?? []);
          if (results["all_students"] != null) {
            _allClassStudents = List<Map<String, dynamic>>.from(results["all_students"]);
          }
          if (results["face_boxes"] != null) {
            _liveFaceBoxes = List<Map<String, dynamic>>.from(results["face_boxes"]);
          }
          for (var st in matchedList) {
            final stId = int.parse(st["id"].toString());
            if (!_livePresentStudents.containsKey(stId)) {
              _livePresentStudents[stId] = st;
            }
          }
          if (_isRecording) {
            setState(() {
              _isStreamingFrame = false; // Allow next frame to be captured and sent
              _isAiWarmingUp = false;
              if (_livePresentStudents.isEmpty) {
                _statusMessage = "🔴 LIVE SCANNING... Slowly pan camera across student faces!";
              } else {
                _statusMessage = "🔴 LIVE SCANNING: Found ${_livePresentStudents.length} / ${_allClassStudents.length} students!";
              }
            });
          }
        } catch (e) {
          debugPrint("Ws decode error: $e");
          _isStreamingFrame = false;
        }
      });
    } catch (e) {
      debugPrint("WebSocket connect failed, using HTTP fallback: $e");
    }

    _liveStreamTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) async {
      if (!_isRecording || _cameraController == null || !_cameraController!.value.isInitialized) return;

      // Watchdog timeout: if server hasn't replied to previous frame in 2.5s, unlock to send next frame
      if (_isStreamingFrame) {
        if (_lastFrameSendTime != null && DateTime.now().difference(_lastFrameSendTime!).inMilliseconds > 2500) {
          _isStreamingFrame = false;
          if (_isAiWarmingUp && mounted) {
            setState(() {
              _isAiWarmingUp = false;
              _statusMessage = "🔴 LIVE SCANNING... Slowly pan camera across student faces!";
            });
          }
        } else {
          return; // Still waiting for server to finish processing current frame
        }
      }

      _isStreamingFrame = true;
      _lastFrameSendTime = DateTime.now();

      try {
        final XFile photoFile = await _cameraController!.takePicture();
        final List<int> rawBytes = await photoFile.readAsBytes();
        
        // Try WebSocket first with zero disk/TCP overhead (#3 & #1)
        if (!ApiService.sendLiveScanFrameBytes(rawBytes)) {
          // HTTP Fallback
          try {
            final results = await ApiService.streamFrame(widget.classId, File(photoFile.path));
            if (mounted) {
              final matchedList = List<Map<String, dynamic>>.from(results["matched_students"]);
              if (results["all_students"] != null) {
                _allClassStudents = List<Map<String, dynamic>>.from(results["all_students"]);
              }
              if (results["face_boxes"] != null) {
                _liveFaceBoxes = List<Map<String, dynamic>>.from(results["face_boxes"]);
              }
              for (var st in matchedList) {
                final stId = int.parse(st["id"].toString());
                if (!_livePresentStudents.containsKey(stId)) {
                  _livePresentStudents[stId] = st;
                }
              }
              if (_isRecording) {
                setState(() {
                  _isAiWarmingUp = false;
                  if (_livePresentStudents.isEmpty) {
                    _statusMessage = "🔴 LIVE SCANNING... Slowly pan camera across student faces!";
                  } else {
                    _statusMessage = "🔴 LIVE SCANNING: Found ${_livePresentStudents.length} / ${_allClassStudents.length} students!";
                  }
                });
              }
            }
          } finally {
            _isStreamingFrame = false;
          }
        }
      } catch (e) {
        debugPrint("Live stream frame error: $e");
        _isStreamingFrame = false;
      }
    });
  }

  Future<void> _stopRecordingAndAnalyze() async {
    if (!_isRecording) return;
    
    _liveStreamTimer?.cancel();
    _liveStreamTimer = null;
    ApiService.disconnectLiveScanWs();
    
    setState(() {
      _isRecording = false;
      _isProcessing = true;
      _liveFaceBoxes.clear();
      _statusMessage = "⚡ Finalizing live attendance results... Please wait!";
    });

    // Wait up to 3 seconds for any in-flight frame analysis to finish
    int waited = 0;
    while (_isStreamingFrame && waited < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited++;
    }

    // If no students were matched yet (e.g. stopped very quickly), do one final check
    if (_livePresentStudents.isEmpty && _cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final XFile photoFile = await _cameraController!.takePicture();
        final results = await ApiService.streamFrame(widget.classId, File(photoFile.path));
        if (results["matched_students"] != null) {
          final matchedList = List<Map<String, dynamic>>.from(results["matched_students"]);
          if (results["all_students"] != null) {
            _allClassStudents = List<Map<String, dynamic>>.from(results["all_students"]);
          }
          for (var st in matchedList) {
            final stId = int.parse(st["id"].toString());
            _livePresentStudents[stId] = st;
          }
        }
      } catch (e) {
        debugPrint("Final check error: $e");
      }
    }

    final presentList = _livePresentStudents.values.toList();
    final presentIds = _livePresentStudents.keys.toSet();
    final absentList = _allClassStudents.where((st) => !presentIds.contains(int.parse(st["id"].toString()))).toList();

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AttendanceReviewScreen(
            classId: widget.classId,
            className: widget.className,
            initialPresent: presentList,
            initialAbsent: absentList,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview or Fallback Box
          _cameraController != null && _cameraController!.value.isInitialized
              ? SizedBox.expand(child: CameraPreview(_cameraController!))
              : Container(
                  color: AttendLensTheme.backgroundDark,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.videocam_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text("Camera Preview (Simulation Mode)", style: GoogleFonts.outfit(color: Colors.white, fontSize: 18)),
                      ],
                    ),
                  ),
                ),

          // Live AR Face Bounding Box Overlay
          if (_isRecording && _liveFaceBoxes.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: _FaceBoundingBoxPainter(_liveFaceBoxes),
              ),
            ),
          
          // Top Overlay: Class Name & Close Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      children: [
                        const Icon(Icons.school, color: AttendLensTheme.accentCyan, size: 20),
                        const SizedBox(width: 8),
                        Text(widget.className, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),

          // Center Panning Guide Box (AR feedback style)
          if (!_isProcessing)
            Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                height: MediaQuery.of(context).size.height * 0.4,
                decoration: BoxDecoration(
                  border: Border.all(color: _isRecording ? AttendLensTheme.statusAbsent : AttendLensTheme.accentCyan, width: 3),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(12)),
                    child: Text(_isRecording ? "🔴 RECORDING CLASS ROOM" : "🟢 AI SCANNER READY", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ),
            ),

          // Bottom Overlay: Status Message & Record Button
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black.withOpacity(0.0), Colors.black.withOpacity(0.9)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _isRecording ? AttendLensTheme.statusAbsent.withOpacity(0.2) : AttendLensTheme.surfaceDark.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _isRecording ? AttendLensTheme.statusAbsent : Colors.white.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isProcessing || _isAiWarmingUp) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AttendLensTheme.accentCyan)),
                        if (_isProcessing || _isAiWarmingUp) const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            _statusMessage,
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Record / Stop Button
                  if (!_isProcessing)
                    GestureDetector(
                      onTap: _isRecording ? _stopRecordingAndAnalyze : _startRecording,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: _isRecording ? AttendLensTheme.statusAbsent : AttendLensTheme.statusPresent,
                        ),
                        child: Icon(
                          _isRecording ? Icons.stop : Icons.videocam,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceBoundingBoxPainter extends CustomPainter {
  final List<Map<String, dynamic>> boxes;
  _FaceBoundingBoxPainter(this.boxes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final item in boxes) {
      final box = item['box'] as Map<String, dynamic>? ?? {};
      final double left = (box['left'] as num? ?? 0.0).toDouble() * size.width;
      final double top = (box['top'] as num? ?? 0.0).toDouble() * size.height;
      final double width = (box['width'] as num? ?? 0.0).toDouble() * size.width;
      final double height = (box['height'] as num? ?? 0.0).toDouble() * size.height;
      final bool isMatched = item['id'] != null;

      if (width <= 0 || height <= 0) continue;

      final Rect rect = Rect.fromLTWH(left, top, width, height);

      // Ultra-thin 0.7mm pen/pencil style stroke (strokeWidth: 1.0)
      // Red when detecting/unrecognized, Green when recognized
      final Paint borderPaint = Paint()
        ..color = isMatched ? Colors.greenAccent : Colors.redAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawRect(rect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FaceBoundingBoxPainter oldDelegate) => true;
}
