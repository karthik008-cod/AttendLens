import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/models/teacher_model.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';
import 'package:mobile/screens/student_onboarding_screen.dart';
import 'package:mobile/screens/camera_capture_screen.dart';
import 'package:mobile/screens/analytics_screen.dart';
import 'package:mobile/screens/auth/login_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  List<dynamic> _classes = [];
  bool _isLoading = true;

  TeacherModel get _teacher => AuthState.teacher!;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoading = true);
    try {
      final classes = await ApiService.getClasses(_teacher.id);
      if (mounted) setState(() { _classes = classes; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _totalStudents => _classes.fold(0, (sum, c) => sum + ((c['student_count'] as int?) ?? 0));

  // ── Create Class Dialog ────────────────────────────────────────────────────

  void _showCreateClassDialog() {
    final nameCtrl    = TextEditingController();
    final subjectCtrl = TextEditingController();
    final sectionCtrl = TextEditingController();
    int requiredPhotos = 3;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AttendLensTheme.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 24, right: 24, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Text('Create New Class', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),
              _sheetField(nameCtrl, 'Class Name', 'e.g. CS101 — Algorithms', Icons.class_outlined),
              const SizedBox(height: 14),
              _sheetField(subjectCtrl, 'Subject / Department', 'e.g. Computer Science', Icons.book_outlined),
              const SizedBox(height: 14),
              _sheetField(sectionCtrl, 'Section (optional)', 'e.g. A, B, Morning', Icons.tag),
              const SizedBox(height: 20),
              Text('Photos required per student', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AttendLensTheme.textSecondary)),
              const SizedBox(height: 10),
              Row(
                children: List.generate(5, (i) {
                  final n = i + 1;
                  final selected = requiredPhotos == n;
                  return GestureDetector(
                    onTap: () => setModal(() => requiredPhotos = n),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 10),
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: selected ? AttendLensTheme.primaryIndigo : AttendLensTheme.backgroundDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? AttendLensTheme.primaryIndigo : Colors.white12),
                      ),
                      child: Center(child: Text('$n', style: GoogleFonts.outfit(color: selected ? Colors.white : AttendLensTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 16))),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text('More photos = better face recognition accuracy', style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.textSecondary)),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    backgroundColor: AttendLensTheme.primaryIndigo,
                  ),
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty) return;
                    try {
                      await ApiService.createClass(
                        name: nameCtrl.text,
                        subject: subjectCtrl.text,
                        section: sectionCtrl.text.isEmpty ? null : sectionCtrl.text,
                        requiredPhotos: requiredPhotos,
                        teacherId: _teacher.id,
                      );
                      _loadClasses();
                    } catch (_) {
                      setState(() {
                        _classes.add({
                          'id': _classes.length + 1,
                          'name': nameCtrl.text,
                          'subject': subjectCtrl.text,
                          'section': sectionCtrl.text.isEmpty ? null : sectionCtrl.text,
                          'required_photos': requiredPhotos,
                          'student_count': 0,
                        });
                      });
                    }
                    if (mounted) Navigator.pop(ctx);
                  },
                  child: Text('Create Class', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Edit Class Dialog ──────────────────────────────────────────────────────

  void _showEditClassDialog(dynamic cls) {
    final nameCtrl    = TextEditingController(text: cls['name'] ?? '');
    final subjectCtrl = TextEditingController(text: cls['subject'] ?? '');
    final sectionCtrl = TextEditingController(text: cls['section'] ?? '');
    int requiredPhotos = cls['required_photos'] ?? 3;
    final int classId = cls['id'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AttendLensTheme.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 24, right: 24, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Edit Class', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AttendLensTheme.statusAbsent),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: AttendLensTheme.surfaceDark,
                          title: Text('Delete Class?', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                          content: Text('Are you sure you want to delete "${cls['name']}"? All attendance data will be removed.', style: GoogleFonts.outfit(color: Colors.white70)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white70))),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AttendLensTheme.statusAbsent),
                              onPressed: () => Navigator.pop(c, true),
                              child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        try {
                          await ApiService.deleteClass(classId);
                        } catch (_) {}
                        _loadClasses();
                        if (mounted) Navigator.pop(ctx);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _sheetField(nameCtrl, 'Class Name', 'e.g. CS101 — Algorithms', Icons.class_outlined),
              const SizedBox(height: 14),
              _sheetField(subjectCtrl, 'Subject / Department', 'e.g. Computer Science', Icons.book_outlined),
              const SizedBox(height: 14),
              _sheetField(sectionCtrl, 'Section (optional)', 'e.g. A, B, Morning', Icons.tag),
              const SizedBox(height: 20),
              Text('Photos required per student', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AttendLensTheme.textSecondary)),
              const SizedBox(height: 10),
              Row(
                children: List.generate(5, (i) {
                  final n = i + 1;
                  final selected = requiredPhotos == n;
                  return GestureDetector(
                    onTap: () => setModal(() => requiredPhotos = n),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 10),
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: selected ? AttendLensTheme.primaryIndigo : AttendLensTheme.backgroundDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? AttendLensTheme.primaryIndigo : Colors.white12),
                      ),
                      child: Center(child: Text('$n', style: GoogleFonts.outfit(color: selected ? Colors.white : AttendLensTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 16))),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    backgroundColor: AttendLensTheme.primaryIndigo,
                  ),
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty) return;
                    try {
                      await ApiService.updateClass(
                        classId,
                        name: nameCtrl.text,
                        subject: subjectCtrl.text,
                        section: sectionCtrl.text.isEmpty ? null : sectionCtrl.text,
                        requiredPhotos: requiredPhotos,
                      );
                    } catch (_) {}
                    _loadClasses();
                    if (mounted) Navigator.pop(ctx);
                  },
                  child: Text('Save Changes', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Profile Sheet ──────────────────────────────────────────────────────────

  void _showProfileSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AttendLensTheme.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            CircleAvatar(
              radius: 36,
              backgroundColor: AttendLensTheme.primaryIndigo.withOpacity(0.2),
              child: Text(_teacher.initials, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AttendLensTheme.primaryIndigo)),
            ),
            const SizedBox(height: 14),
            Text(_teacher.name, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            Text(_teacher.email, style: GoogleFonts.outfit(fontSize: 13, color: AttendLensTheme.textSecondary)),
            if (_teacher.institution != null) ...[
              const SizedBox(height: 4),
              Text(_teacher.institution!, style: GoogleFonts.outfit(fontSize: 13, color: AttendLensTheme.accentCyan)),
            ],
            const SizedBox(height: 28),
            // Server URL config
            ListTile(
              tileColor: AttendLensTheme.backgroundDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: const Icon(Icons.settings_ethernet, color: AttendLensTheme.accentCyan),
              title: Text('Backend Server URL', style: GoogleFonts.outfit(color: Colors.white)),
              subtitle: Text(ApiService.baseUrl, style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.textSecondary)),
              onTap: () { Navigator.pop(ctx); _showServerDialog(); },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AttendLensTheme.statusAbsent,
                  side: const BorderSide(color: AttendLensTheme.statusAbsent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.logout),
                label: Text('Sign Out', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  AuthState.logout();
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('teacher_data');
                  if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showServerDialog() {
    final ctrl = TextEditingController(text: ApiService.baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AttendLensTheme.surfaceDark,
        title: Text('Backend URL', style: GoogleFonts.outfit(color: Colors.white)),
        content: TextField(controller: ctrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'http://192.168.X.X:8000/api')),
        actions: [
          ElevatedButton(onPressed: () { ApiService.setBaseUrl(ctrl.text); Navigator.pop(ctx); _loadClasses(); }, child: const Text('Save & Reconnect')),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadClasses,
          color: AttendLensTheme.primaryIndigo,
          child: CustomScrollView(
            slivers: [
              // ── Hero Header ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1a1060), Color(0xFF0B0F19)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // App Title / Logo Header
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset('assets/logo.jpg', width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.lens, color: AttendLensTheme.accentCyan, size: 36)),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('AttendLens', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
                              Text('SEE . RECORD . RELY.', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700, color: AttendLensTheme.accentCyan, letterSpacing: 2.5)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_greeting, style: GoogleFonts.outfit(fontSize: 14, color: AttendLensTheme.textSecondary)),
                            Text(_teacher.firstName, style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                          ]),
                          GestureDetector(
                            onTap: _showProfileSheet,
                            child: CircleAvatar(
                              radius: 26,
                              backgroundColor: AttendLensTheme.primaryIndigo.withOpacity(0.3),
                              child: Text(_teacher.initials, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                      if (_teacher.institution != null) ...[
                        const SizedBox(height: 4),
                        Text(_teacher.institution!, style: GoogleFonts.outfit(fontSize: 13, color: AttendLensTheme.accentCyan)),
                      ],
                      const SizedBox(height: 24),

                      // Stats Row
                      Row(children: [
                        _statCard('${_classes.length}', 'Classes', Icons.class_outlined),
                        const SizedBox(width: 12),
                        _statCard('$_totalStudents', 'Students', Icons.people_outline),
                        const SizedBox(width: 12),
                        _statCard('AI', 'Powered', Icons.face_retouching_natural),
                      ]),
                    ],
                  ),
                ),
              ),

              // ── Quick Take Attendance ─────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: AttendLensTheme.gradientButtonDecoration,
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Ready for class?', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text('Tap a class below to take attendance in seconds.', style: GoogleFonts.outfit(fontSize: 12, color: Colors.white70)),
                      ])),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AttendLensTheme.primaryIndigo, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('New Class'),
                        onPressed: _showCreateClassDialog,
                      ),
                    ]),
                  ),
                ),
              ),

              // ── Section Header ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('My Classrooms', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      IconButton(icon: const Icon(Icons.refresh, color: Colors.grey, size: 22), onPressed: _loadClasses),
                    ],
                  ),
                ),
              ),

              // ── Classes List ──────────────────────────────────────────────
              if (_isLoading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AttendLensTheme.primaryIndigo)))
              else if (_classes.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('📚', style: TextStyle(fontSize: 56)),
                      const SizedBox(height: 16),
                      Text('No classes yet', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 6),
                      Text('Tap "New Class" to get started', style: GoogleFonts.outfit(fontSize: 14, color: AttendLensTheme.textSecondary)),
                    ]),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: _ClassCard(
                        cls: _classes[index],
                        onAttendance: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => CameraCaptureScreen(classId: _classes[index]['id'], className: _classes[index]['name']),
                        )).then((_) => _loadClasses()),
                        onStudents: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => StudentOnboardingScreen(
                            classId: _classes[index]['id'],
                            className: _classes[index]['name'],
                            requiredPhotos: _classes[index]['required_photos'] ?? 3,
                          ),
                        )).then((_) => _loadClasses()),
                        onAnalytics: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AnalyticsScreen(classId: _classes[index]['id'], className: _classes[index]['name']),
                        )),
                        onDownload: () => _downloadSheet(_classes[index]['id'], _classes[index]['name']),
                        onEdit: () => _showEditClassDialog(_classes[index]),
                      ),
                    ),
                    childCount: _classes.length,
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(String value, String label, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(children: [
        Icon(icon, color: AttendLensTheme.accentCyan, size: 22),
        const SizedBox(height: 6),
        Text(value, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.textSecondary)),
      ]),
    ),
  );

  Future<void> _downloadSheet(int classId, String className) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator(color: AttendLensTheme.accentCyan)),
      );
      final url = ApiService.getExcelReportUrl(classId);
      final response = await http.get(Uri.parse(url));
      if (mounted) Navigator.pop(context);
      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/Attendance_${className.replaceAll(' ', '_')}.xlsx');
        await file.writeAsBytes(response.bodyBytes);
        await Share.shareXFiles([XFile(file.path)], text: 'AttendLens Attendance ($className)');
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: ${response.statusCode}')));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _sheetField(TextEditingController ctrl, String label, String hint, IconData icon) => TextField(
    controller: ctrl,
    style: GoogleFonts.outfit(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: GoogleFonts.outfit(color: AttendLensTheme.textSecondary.withOpacity(0.5), fontSize: 13),
      prefixIcon: Icon(icon, color: AttendLensTheme.textSecondary, size: 20),
      filled: true, fillColor: AttendLensTheme.backgroundDark,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AttendLensTheme.primaryIndigo)),
    ),
  );
}

// ── Class Card Widget ──────────────────────────────────────────────────────────

class _ClassCard extends StatelessWidget {
  final dynamic cls;
  final VoidCallback onAttendance;
  final VoidCallback onStudents;
  final VoidCallback onAnalytics;
  final VoidCallback onDownload;
  final VoidCallback onEdit;

  const _ClassCard({required this.cls, required this.onAttendance, required this.onStudents, required this.onAnalytics, required this.onDownload, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final section = cls['section'] as String?;
    final reqPhotos = cls['required_photos'] ?? 3;

    return Container(
      decoration: AttendLensTheme.glassDecoration,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cls['name'], style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(cls['subject'] ?? '', style: GoogleFonts.outfit(fontSize: 13, color: AttendLensTheme.textSecondary)),
                  ]),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: AttendLensTheme.primaryIndigo.withOpacity(0.2), borderRadius: BorderRadius.circular(20), border: Border.all(color: AttendLensTheme.primaryIndigo.withOpacity(0.4))),
                      child: Text('${cls['student_count']} Students', style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.accentCyan, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: onEdit,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.edit, color: Colors.white70, size: 16),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (section != null || reqPhotos != null) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                if (section != null) _chip('§ $section', AttendLensTheme.primaryPurple),
                _chip('📸 $reqPhotos photos', AttendLensTheme.accentCyan),
              ]),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AttendLensTheme.statusPresent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.videocam, size: 18),
                  label: Text('Attend', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: onAttendance,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withOpacity(0.25)), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: onStudents,
                  child: const Icon(Icons.people_outline, size: 18),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: AttendLensTheme.accentCyan, side: BorderSide(color: AttendLensTheme.accentCyan.withOpacity(0.4)), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: onAnalytics,
                  child: const Icon(Icons.bar_chart, size: 18),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: AttendLensTheme.statusPresent, side: BorderSide(color: AttendLensTheme.statusPresent.withOpacity(0.4)), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: onDownload,
                  child: const Icon(Icons.download, size: 18),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.3))),
    child: Text(label, style: GoogleFonts.outfit(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
  );
}
