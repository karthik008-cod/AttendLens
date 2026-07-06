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
        _statusMessage = "🔴 RECORDING... Tap the stop button when done panning!";
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Could not start recording: $e";
      });
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

      try {
        final results = await ApiService.scanVideo(widget.classId, File(videoFile.path));

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
        // Show real error instead of injecting fake data
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _statusMessage = "❌ Backend error: $e\n\nMake sure backend is running and try again.";
          });
        }
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = "Error stopping video: $e. Please try again.";
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

          // AR Face Tracking Bounding Boxes (Green, Yellow, Red overlays)
          if (!_isProcessing)
            Stack(
              children: [
                // Center Panning Guide Box
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.88,
                    height: MediaQuery.of(context).size.height * 0.45,
                    decoration: BoxDecoration(
                      border: Border.all(color: _isRecording ? AttendLensTheme.statusAbsent.withOpacity(0.5) : AttendLensTheme.accentCyan.withOpacity(0.5), width: 2),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(12)),
                        child: Text(_isRecording ? "🔴 RECORDING: SCANNING FACES IN REAL-TIME" : "🟢 AI SCANNER READY (PAN SLOWLY)", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                  ),
                ),
                // Simulated AR Bounding Box 1 (Green - Recognized)
                if (_isRecording)
                  Positioned(
                    left: 40,
                    top: MediaQuery.of(context).size.height * 0.32,
                    child: _buildArBoundingBox("Recognized ✅", Colors.green, "ID #04"),
                  ),
                // Simulated AR Bounding Box 2 (Yellow - Processing/Scanning)
                if (_isRecording)
                  Positioned(
                    right: 45,
                    top: MediaQuery.of(context).size.height * 0.38,
                    child: _buildArBoundingBox("Scanning... ⚡", Colors.amber, "Face #12"),
                  ),
                // Simulated AR Bounding Box 3 (Red - New/Unrecognized)
                if (_isRecording)
                  Positioned(
                    left: 110,
                    bottom: MediaQuery.of(context).size.height * 0.28,
                    child: _buildArBoundingBox("New Face ❓", Colors.redAccent, "Unverified"),
                  ),
              ],
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

  Widget _buildArBoundingBox(String status, Color color, String label) {
    return Container(
      width: 100,
      height: 110,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2.5),
        borderRadius: BorderRadius.circular(12),
        color: color.withOpacity(0.08),
      ),
      child: Stack(
        children: [
          // Corner accents
          Positioned(top: 0, left: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(border: Border(top: BorderSide(color: color, width: 4), left: BorderSide(color: color, width: 4))))),
          Positioned(top: 0, right: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(border: Border(top: BorderSide(color: color, width: 4), right: BorderSide(color: color, width: 4))))),
          Positioned(bottom: 0, left: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: color, width: 4), left: BorderSide(color: color, width: 4))))),
          Positioned(bottom: 0, right: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: color, width: 4), right: BorderSide(color: color, width: 4))))),
          // Badge
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
              child: Text(
                status,
                style: GoogleFonts.outfit(color: color == Colors.amber ? Colors.black : Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(4)),
              child: Text(label, style: GoogleFonts.outfit(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
