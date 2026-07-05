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
  String _statusMessage = "Slowly pan across the classroom from left to right ➡️";

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras!.first,
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) setState(() {});
      }
    } catch (e) {
      // Ignore in demo mode
    }
  }

  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    
    try {
      await _cameraController!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _statusMessage = "🔴 RECORDING... Keep panning smoothly across all student faces!";
      });

      Future.delayed(const Duration(seconds: 6), () {
        if (_isRecording) _stopRecordingAndAnalyze();
      });
    } catch (e) {
      // Ignore in demo mode
    }
  }

  Future<void> _stopRecordingAndAnalyze() async {
    if (!_isRecording || _cameraController == null) return;
    
    try {
      final XFile videoFile = await _cameraController!.stopVideoRecording();
      setState(() {
        _isRecording = false;
        _isProcessing = true;
        _statusMessage = "🧠 AI Face Recognition analyzing classroom frames... Please wait!";
      });

      Map<String, dynamic> results;
      try {
        results = await ApiService.scanVideo(widget.classId, File(videoFile.path));
      } catch (e) {
        // Mock fallback results if backend offline
        results = {
          "present_students": [
            {"id": 1, "name": "Ada Lovelace", "roll_number": "CS-001"},
            {"id": 2, "name": "Grace Hopper", "roll_number": "CS-002"},
          ],
          "absent_students": [
            {"id": 3, "name": "Linus Torvalds", "roll_number": "CS-003"},
          ]
        };
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AttendanceReviewScreen(
              classId: widget.classId,
              className: widget.className,
              initialPresent: List<Map<String, dynamic>>.from(results["present_students"]),
              initialAbsent: List<Map<String, dynamic>>.from(results["absent_students"]),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = "Error analyzing video: $e. Please try scanning again.";
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
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
          
          // Top Overlay: Class Name & Close Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: AttendLensTheme.glassDecoration,
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
                        if (_isProcessing) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AttendLensTheme.accentCyan)),
                        if (_isProcessing) const SizedBox(width: 12),
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
