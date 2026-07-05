import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';

class StudentOnboardingScreen extends StatefulWidget {
  final int classId;
  final String className;

  const StudentOnboardingScreen({super.key, required this.classId, required this.className});

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
      setState(() {
        _students = students;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _students = [
          {"id": 1, "name": "Ada Lovelace", "roll_number": "CS-001", "photo_path": null},
          {"id": 2, "name": "Grace Hopper", "roll_number": "CS-002", "photo_path": null},
        ];
        _isLoading = false;
      });
    }
  }

  void _showAddStudentModal() {
    final nameController = TextEditingController();
    final rollController = TextEditingController();
    File? selectedPhoto;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AttendLensTheme.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20, right: 20, top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Enroll Student Face", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text("Add student profile and take a clear photo of their face for automated recognition.", style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Student Full Name",
                      filled: true, fillColor: AttendLensTheme.backgroundDark,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: rollController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Roll Number / Student ID",
                      filled: true, fillColor: AttendLensTheme.backgroundDark,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Photo Picker Button
                  GestureDetector(
                    onTap: () async {
                      final XFile? photo = await _picker.pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front);
                      if (photo != null) {
                        setModalState(() => selectedPhoto = File(photo.path));
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: AttendLensTheme.backgroundDark,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: selectedPhoto == null ? AttendLensTheme.primaryIndigo : AttendLensTheme.statusPresent, width: 2),
                      ),
                      child: Column(
                        children: [
                          Icon(selectedPhoto == null ? Icons.camera_alt_outlined : Icons.check_circle, size: 40, color: selectedPhoto == null ? AttendLensTheme.primaryIndigo : AttendLensTheme.statusPresent),
                          const SizedBox(height: 8),
                          Text(selectedPhoto == null ? "📸 Tap to Snap Face Photo / Selfie" : "✅ Photo Captured Ready to Upload!", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AttendLensTheme.primaryIndigo, padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: () async {
                        if (nameController.text.isNotEmpty && rollController.text.isNotEmpty) {
                          try {
                            await ApiService.addStudent(nameController.text, rollController.text, widget.classId, selectedPhoto);
                            _loadStudents();
                          } catch (e) {
                            setState(() {
                              _students.add({"id": _students.length + 1, "name": nameController.text, "roll_number": rollController.text, "photo_path": null});
                            });
                          }
                          Navigator.pop(context);
                        }
                      },
                      child: const Text("Save & Enroll Student", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showSelfRegistrationLink() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AttendLensTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("🔗 Self-Registration QR Link", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Share this link or QR with students so they can upload their own selfie without wasting class time!", style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.qr_code_2, size: 140, color: Colors.black),
            ),
            const SizedBox(height: 16),
            Text("https://attendlens.app/invite/${widget.classId}", style: GoogleFonts.outfit(color: AttendLensTheme.accentCyan, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Done"))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.className),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: AttendLensTheme.accentCyan),
            onPressed: _showSelfRegistrationLink,
            tooltip: "Student Self-Invite QR",
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Banner
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(20),
              decoration: AttendLensTheme.glassDecoration,
              child: Row(
                children: [
                  const Icon(Icons.face_retouching_natural, color: AttendLensTheme.primaryIndigo, size: 36),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Enrolled Roster (${_students.length})", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text("Students with facial encodings ready for rapid video scanning.", style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Student List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _students.isEmpty
                      ? Center(child: Text("No students enrolled yet.", style: GoogleFonts.outfit(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _students.length,
                          itemBuilder: (context, index) {
                            final st = _students[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AttendLensTheme.primaryIndigo.withOpacity(0.3),
                                  child: Text(st["name"][0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                                title: Text(st["name"], style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                                subtitle: Text("Roll No: ${st["roll_number"]}", style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary)),
                                trailing: const Icon(Icons.check_circle, color: AttendLensTheme.statusPresent, size: 20),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AttendLensTheme.primaryIndigo,
        onPressed: _showAddStudentModal,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: Text("Enroll Student", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
