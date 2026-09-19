import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';
import 'package:mobile/screens/omr/omr_analytics_screen.dart';

class OmrScannerScreen extends StatefulWidget {
  final Map<String, dynamic> exam;

  const OmrScannerScreen({super.key, required this.exam});

  @override
  State<OmrScannerScreen> createState() => _OmrScannerScreenState();
}

class _OmrScannerScreenState extends State<OmrScannerScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraReady = false;
  bool _isCapturing = false;

  // Mode: true = Continuous Scan, false = Single Scan
  bool _isContinuousMode = true;

  // Continuous scan state
  int _scannedCount = 0;
  String? _lastScannedToast;
  final List<Map<String, dynamic>> _sessionSubmissions = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
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
        if (mounted) setState(() => _isCameraReady = true);
      }
    } catch (e) {
      debugPrint("Camera init error: $e");
    }
  }

  Future<void> _captureSheet({File? directFile}) async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      File fileToScan;
      if (directFile != null) {
        fileToScan = directFile;
      } else {
        if (_cameraController == null || !_cameraController!.value.isInitialized) {
          setState(() => _isCapturing = false);
          return;
        }
        final xFile = await _cameraController!.takePicture();
        fileToScan = File(xFile.path);
      }

      final examId = widget.exam['id'];
      final res = await ApiService.scanSingleOmr(examId, fileToScan);

      if (res['success'] == true) {
        final eval = res['evaluation'];
        final ht = res['student_hall_ticket'] ?? 'Candidate';
        final score = eval['total_score'];
        final maxM = eval['total_max_marks'];

        setState(() {
          _scannedCount++;
          _sessionSubmissions.add(res);
          _lastScannedToast = '✓ Sheet #$_scannedCount: $ht ($score/$maxM)';
        });

        if (!_isContinuousMode) {
          // Single Scan Mode: Show immediate detailed result modal
          if (mounted) _showSingleScanResultModal(res);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: $e'), backgroundColor: AttendLensTheme.statusAbsent),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (picked != null) {
      _captureSheet(directFile: File(picked.path));
    }
  }

  void _finishAndGoToAnalytics() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => OmrAnalyticsScreen(exam: widget.exam)),
    );
  }

  void _showSingleScanResultModal(Map<String, dynamic> res) {
    final eval = res['evaluation'] ?? {};
    final ht = res['student_hall_ticket'] ?? 'Unknown';
    final name = res['student_name'] ?? 'Candidate';
    final score = eval['total_score'] ?? 0;
    final maxM = eval['total_max_marks'] ?? 0;
    final pct = eval['percentage'] ?? 0;
    final acc = eval['accuracy'] ?? 0;
    final att = eval['attempt_rate'] ?? 0;
    final pen = eval['penalty_ratio'] ?? 0;
    final subjects = (eval['subject_breakdown'] as List<dynamic>?) ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AttendLensTheme.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('Hall Ticket: $ht', style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.textSecondary)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AttendLensTheme.statusPresent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AttendLensTheme.statusPresent.withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$score / $maxM', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('$pct%', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: AttendLensTheme.statusPresent)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Performance metrics row
            Row(
              children: [
                _metricTile('Accuracy', '$acc%', AttendLensTheme.accentCyan),
                const SizedBox(width: 8),
                _metricTile('Attempt Rate', '$att%', Colors.white70),
                const SizedBox(width: 8),
                _metricTile('Penalty Loss', '$pen%', pen > 20 ? AttendLensTheme.statusAbsent : Colors.white70),
              ],
            ),
            const SizedBox(height: 18),

            // Subject breakdown
            Text('Subject Performance', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            ...subjects.map((s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(s['subject'] ?? 'Subject', style: GoogleFonts.outfit(fontSize: 13, color: Colors.white70)),
                  Text('${s['score']} / ${s['max_marks']} (${s['accuracy']}%)', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: AttendLensTheme.accentCyan)),
                ],
              ),
            )),
            const SizedBox(height: 24),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Scan Next Sheet', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AttendLensTheme.primaryIndigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _finishAndGoToAnalytics();
                    },
                    child: Text('View Analytics', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricTile(String label, String val, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AttendLensTheme.backgroundDark,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(val, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.outfit(fontSize: 10, color: AttendLensTheme.textSecondary)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera Preview ────────────────────────────────────────────────
          if (_isCameraReady && _cameraController != null)
            Positioned.fill(
              child: AspectRatio(
                aspectRatio: _cameraController!.value.aspectRatio,
                child: CameraPreview(_cameraController!),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: AttendLensTheme.primaryIndigo)),

          // ── Viewfinder Alignment Guide Overlay ────────────────────────────
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.86,
                  height: MediaQuery.of(context).size.height * 0.65,
                  decoration: BoxDecoration(
                    border: Border.all(color: AttendLensTheme.accentCyan.withOpacity(0.7), width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      // Target crosshairs or corner brackets
                      Positioned(
                        top: 12, left: 12,
                        child: Text('Align OMR Sheet Inside Frame', style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.accentCyan, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Top Bar Controls ──────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(widget.exam['title'] ?? 'OMR Scan', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      IconButton(
                        icon: const Icon(Icons.photo_library, color: Colors.white),
                        tooltip: 'Upload from Gallery',
                        onPressed: _pickFromGallery,
                      ),
                    ],
                  ),

                  // Mode Toggle
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => _isContinuousMode = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: _isContinuousMode ? AttendLensTheme.primaryIndigo : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text('Continuous Scan', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _isContinuousMode = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: !_isContinuousMode ? AttendLensTheme.primaryIndigo : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text('Single Scan', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Non-blocking toast notification in continuous scan mode
                  if (_lastScannedToast != null)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AttendLensTheme.statusPresent.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
                      ),
                      child: Text(
                        _lastScannedToast!,
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Prominent "Scan Completed" Button (Continuous Mode) ───────────
          if (_isContinuousMode)
            Positioned(
              top: 120,
              right: 16,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AttendLensTheme.accentCyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  elevation: 8,
                ),
                icon: const Icon(Icons.check_circle, size: 20, color: Colors.black),
                label: Text(
                  'Scan Completed ($_scannedCount)',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: _finishAndGoToAnalytics,
              ),
            ),

          // ── Bottom Capture Shutter Button ─────────────────────────────────
          Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isCapturing ? null : () => _captureSheet(),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    color: _isCapturing ? AttendLensTheme.statusAbsent : Colors.white24,
                  ),
                  child: Center(
                    child: _isCapturing
                        ? const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : Container(
                            width: 62,
                            height: 62,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
