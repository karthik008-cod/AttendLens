import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';

class StudentOnboardingScreen extends StatefulWidget {
  final int classId;
  final String className;
  final int requiredPhotos;

  const StudentOnboardingScreen({
    super.key,
    required this.classId,
    required this.className,
    this.requiredPhotos = 3,
  });

  @override
  State<StudentOnboardingScreen> createState() => _StudentOnboardingScreenState();
}

class _StudentOnboardingScreenState extends State<StudentOnboardingScreen> {
  List<dynamic> _students = [];
  bool _isLoading = true;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    try {
      final students = await ApiService.getStudents(widget.classId);
      if (mounted) setState(() { _students = students; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Add Student Flow ───────────────────────────────────────────────────────

  void _showAddStudentFlow() {
    final nameCtrl = TextEditingController();
    final rollCtrl = TextEditingController();
    List<File?> photos = List.filled(widget.requiredPhotos, null);
    bool isUploading = false;
    String? errorMsg;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AttendLensTheme.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          int capturedCount = photos.where((p) => p != null).length;
          bool allDone = capturedCount == widget.requiredPhotos;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 24, right: 24, top: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),

                Text('Enroll Student', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('Face photos power automatic attendance recognition.', style: GoogleFonts.outfit(fontSize: 13, color: AttendLensTheme.textSecondary)),
                const SizedBox(height: 20),

                // Name
                TextField(
                  controller: nameCtrl,
                  style: GoogleFonts.outfit(color: Colors.white),
                  textCapitalization: TextCapitalization.words,
                  decoration: _inputDeco('Full Name', Icons.person_outline),
                ),
                const SizedBox(height: 14),

                // Roll number
                TextField(
                  controller: rollCtrl,
                  style: GoogleFonts.outfit(color: Colors.white),
                  decoration: _inputDeco('Roll Number / Student ID', Icons.badge_outlined),
                ),
                const SizedBox(height: 20),

                // Photo grid
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Face Photos', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AttendLensTheme.textSecondary)),
                    Text('$capturedCount / ${widget.requiredPhotos}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: allDone ? AttendLensTheme.statusPresent : AttendLensTheme.accentCyan)),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 84,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.requiredPhotos,
                    itemBuilder: (_, i) {
                      final photo = photos[i];
                      return GestureDetector(
                        onTap: () async {
                          final picked = await _picker.pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front, imageQuality: 85);
                          if (picked != null) setModal(() => photos[i] = File(picked.path));
                        },
                        child: Container(
                          width: 80, height: 80,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: AttendLensTheme.backgroundDark,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: photo != null ? AttendLensTheme.statusPresent : AttendLensTheme.primaryIndigo.withOpacity(0.5), width: 2),
                            image: photo != null ? DecorationImage(image: FileImage(photo), fit: BoxFit.cover) : null,
                          ),
                          child: photo == null
                              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  const Icon(Icons.camera_alt_outlined, color: AttendLensTheme.primaryIndigo, size: 24),
                                  const SizedBox(height: 4),
                                  Text('${i + 1}', style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.textSecondary)),
                                ])
                              : Align(
                                  alignment: Alignment.topRight,
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(Icons.check_circle, color: AttendLensTheme.statusPresent, size: 18, shadows: const [Shadow(blurRadius: 4, color: Colors.black)]),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),

                if (errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(errorMsg!, style: GoogleFonts.outfit(color: AttendLensTheme.statusAbsent, fontSize: 13)),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: allDone ? AttendLensTheme.primaryIndigo : Colors.grey.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: (isUploading) ? null : () async {
                      if (nameCtrl.text.isEmpty || rollCtrl.text.isEmpty) {
                        setModal(() => errorMsg = 'Please fill name and roll number');
                        return;
                      }
                      if (!allDone) {
                        setModal(() => errorMsg = 'Please capture all ${widget.requiredPhotos} photos');
                        return;
                      }
                      setModal(() => isUploading = true);
                      try {
                        // Upload student with first photo
                        final studentData = await ApiService.addStudent(nameCtrl.text, rollCtrl.text, widget.classId, photos[0]);
                        final studentId = studentData['id'] as int;
                        // Upload additional photos
                        for (int i = 1; i < photos.length; i++) {
                          if (photos[i] != null) await ApiService.addStudentPhoto(studentId, photos[i]!);
                        }
                        _loadStudents();
                        if (mounted) Navigator.pop(ctx);
                      } catch (e) {
                        // Fallback: add locally for demo
                        setState(() => _students.add({'id': _students.length + 1, 'name': nameCtrl.text, 'roll_number': rollCtrl.text, 'photo_count': capturedCount}));
                        if (mounted) Navigator.pop(ctx);
                      }
                    },
                    child: isUploading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : Text(allDone ? 'Save & Enroll Student' : 'Capture all photos first', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Edit Student ──────────────────────────────────────────────────────────

  void _showEditSheet(dynamic student) {
    final nameCtrl = TextEditingController(text: student['name']);
    final rollCtrl = TextEditingController(text: student['roll_number']);
    bool isSaving = false;

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
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Text('Edit Student', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),
              TextField(controller: nameCtrl, style: GoogleFonts.outfit(color: Colors.white), textCapitalization: TextCapitalization.words, decoration: _inputDeco('Full Name', Icons.person_outline)),
              const SizedBox(height: 14),
              TextField(controller: rollCtrl, style: GoogleFonts.outfit(color: Colors.white), decoration: _inputDeco('Roll Number', Icons.badge_outlined)),
              const SizedBox(height: 24),
              Row(children: [
                // Delete button
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AttendLensTheme.statusAbsent, side: const BorderSide(color: AttendLensTheme.statusAbsent), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text('Delete', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      _confirmDelete(student);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Save button
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AttendLensTheme.primaryIndigo, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: isSaving ? null : () async {
                      setModal(() => isSaving = true);
                      try {
                        await ApiService.updateStudent(student['id'], name: nameCtrl.text, rollNumber: rollCtrl.text);
                        _loadStudents();
                      } catch (_) {
                        setState(() {
                          final idx = _students.indexWhere((s) => s['id'] == student['id']);
                          if (idx >= 0) { _students[idx]['name'] = nameCtrl.text; _students[idx]['roll_number'] = rollCtrl.text; }
                        });
                      }
                      if (mounted) Navigator.pop(ctx);
                    },
                    child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text('Save Changes', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(dynamic student) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AttendLensTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Student?', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('This will permanently remove ${student['name']} and all their attendance records.', style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AttendLensTheme.statusAbsent),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ApiService.deleteStudent(student['id']);
              } catch (_) {}
              setState(() => _students.removeWhere((s) => s['id'] == student['id']));
              _loadStudents();
            },
            child: Text('Delete', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── QR / Invite Link ──────────────────────────────────────────────────────

  void _showInviteDialog() {
    final inviteUrl = ApiService.getInviteUrl(widget.classId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AttendLensTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('🔗 Student Self-Registration', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Share this QR or link so students can register their own face photos from any device.', style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(data: inviteUrl, version: QrVersions.auto, size: 160),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () { Clipboard.setData(ClipboardData(text: inviteUrl)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied!'))); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: AttendLensTheme.backgroundDark, borderRadius: BorderRadius.circular(10), border: Border.all(color: AttendLensTheme.primaryIndigo.withOpacity(0.5))),
                child: Row(children: [
                  Expanded(child: Text(inviteUrl, style: GoogleFonts.outfit(color: AttendLensTheme.accentCyan, fontSize: 11), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy, color: Colors.grey, size: 16),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Text('Tap URL to copy', style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey)),
          ],
        ),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.className),
        actions: [
          IconButton(icon: const Icon(Icons.qr_code_2, color: AttendLensTheme.accentCyan), onPressed: _showInviteDialog, tooltip: 'Student Self-Register Link'),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.grey), onPressed: _loadStudents),
        ],
      ),
      body: Column(
        children: [
          // Banner
          Container(
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            padding: const EdgeInsets.all(16),
            decoration: AttendLensTheme.glassDecoration,
            child: Row(children: [
              const Icon(Icons.face_retouching_natural, color: AttendLensTheme.primaryIndigo, size: 34),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_students.length} Students Enrolled', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('${widget.requiredPhotos} photo(s) required • Long-press to edit', style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.textSecondary)),
              ])),
            ]),
          ),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AttendLensTheme.primaryIndigo))
                : _students.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Text('👤', style: TextStyle(fontSize: 56)),
                        const SizedBox(height: 12),
                        Text('No students yet', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 6),
                        Text('Tap + below to enroll the first student', style: GoogleFonts.outfit(fontSize: 13, color: AttendLensTheme.textSecondary)),
                      ]))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        itemCount: _students.length,
                        itemBuilder: (_, i) {
                          final st = _students[i];
                          final photoCount = st['photo_count'] as int? ?? 0;
                          return GestureDetector(
                            onLongPress: () => _showEditSheet(st),
                            child: Dismissible(
                              key: Key('student_${st['id']}'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(color: AttendLensTheme.statusAbsent.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                                child: const Icon(Icons.delete_outline, color: AttendLensTheme.statusAbsent, size: 28),
                              ),
                              confirmDismiss: (_) async {
                                bool confirmed = false;
                                await showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: AttendLensTheme.surfaceDark,
                                    title: Text('Delete ${st['name']}?', style: GoogleFonts.outfit(color: Colors.white)),
                                    actions: [
                                      TextButton(onPressed: () { Navigator.pop(ctx); }, child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: AttendLensTheme.statusAbsent),
                                        onPressed: () { confirmed = true; Navigator.pop(ctx); },
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                return confirmed;
                              },
                              onDismissed: (_) async {
                                try { await ApiService.deleteStudent(st['id']); } catch (_) {}
                                setState(() => _students.removeAt(i));
                              },
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  leading: CircleAvatar(
                                    radius: 24,
                                    backgroundColor: AttendLensTheme.primaryIndigo.withOpacity(0.2),
                                    child: Text(st['name'][0].toUpperCase(), style: GoogleFonts.outfit(color: AttendLensTheme.primaryIndigo, fontWeight: FontWeight.bold, fontSize: 18)),
                                  ),
                                  title: Text(st['name'], style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                                  subtitle: Text('Roll: ${st['roll_number']}', style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 12)),
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    _photoBadge(photoCount, widget.requiredPhotos),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.more_vert, color: Colors.grey, size: 20),
                                  ]),
                                  onTap: () => _showEditSheet(st),
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
        backgroundColor: AttendLensTheme.primaryIndigo,
        onPressed: _showAddStudentFlow,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: Text('Enroll Student', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _photoBadge(int count, int required) {
    final done = count >= required;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (done ? AttendLensTheme.statusPresent : AttendLensTheme.statusLate).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (done ? AttendLensTheme.statusPresent : AttendLensTheme.statusLate).withOpacity(0.5)),
      ),
      child: Text('📸 $count/$required', style: GoogleFonts.outfit(fontSize: 11, color: done ? AttendLensTheme.statusPresent : AttendLensTheme.statusLate, fontWeight: FontWeight.w600)),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: AttendLensTheme.textSecondary, size: 20),
    filled: true, fillColor: AttendLensTheme.backgroundDark,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AttendLensTheme.primaryIndigo)),
  );
}
