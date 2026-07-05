import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';
import 'package:mobile/screens/student_onboarding_screen.dart';
import 'package:mobile/screens/camera_capture_screen.dart';

class ClassDashboardScreen extends StatefulWidget {
  const ClassDashboardScreen({super.key});

  @override
  State<ClassDashboardScreen> createState() => _ClassDashboardScreenState();
}

class _ClassDashboardScreenState extends State<ClassDashboardScreen> {
  List<dynamic> _classes = [];
  bool _isLoading = true;
  final int _defaultTeacherId = 1; // Default teacher for demo

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoading = true);
    try {
      final classes = await ApiService.getClasses(_defaultTeacherId);
      setState(() {
        _classes = classes;
        _isLoading = false;
      });
    } catch (e) {
      // If backend is offline or first launch, show mock classes or empty
      setState(() {
        _classes = [
          {"id": 1, "name": "CS101 - Algorithms", "subject": "Computer Science", "student_count": 3},
          {"id": 2, "name": "PHY204 - Quantum Mechanics", "subject": "Physics", "student_count": 0},
        ];
        _isLoading = false;
      });
    }
  }

  void _showAddClassDialog() {
    final nameController = TextEditingController();
    final subjectController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AttendLensTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Create New Class", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Class Name (e.g. CS101)",
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                filled: true,
                fillColor: AttendLensTheme.backgroundDark,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: subjectController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Subject / Department",
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                filled: true,
                fillColor: AttendLensTheme.backgroundDark,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AttendLensTheme.primaryIndigo),
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                try {
                  await ApiService.createClass(
                    name: nameController.text,
                    subject: subjectController.text,
                    teacherId: _defaultTeacherId,
                  );
                  _loadClasses();
                } catch (e) {
                  // Fallback local add for demo
                  setState(() {
                    _classes.add({
                      "id": _classes.length + 1,
                      "name": nameController.text,
                      "subject": subjectController.text,
                      "student_count": 0
                    });
                  });
                }
                Navigator.pop(context);
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  void _showServerIpDialog() {
    final ipController = TextEditingController(text: ApiService.baseUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AttendLensTheme.surfaceDark,
        title: Text("Server Backend URL", style: GoogleFonts.outfit(color: Colors.white)),
        content: TextField(
          controller: ipController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: "http://192.168.1.X:8000/api"),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              ApiService.setBaseUrl(ipController.text);
              Navigator.pop(context);
              _loadClasses();
            },
            child: const Text("Save & Reconnect"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("AttendLens 🎥", style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text("Teacher Dashboard • Fast & Effortless", style: GoogleFonts.outfit(fontSize: 14, color: AttendLensTheme.textSecondary)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_ethernet, color: AttendLensTheme.accentCyan, size: 28),
                    onPressed: _showServerIpDialog,
                    tooltip: "Configure Backend IP",
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Quick Action Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: AttendLensTheme.gradientButtonDecoration,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Ready for Today's Class?", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text("Select a class below or create a new one to take attendance in seconds.", style: GoogleFonts.outfit(fontSize: 13, color: Colors.white.withOpacity(0.8))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AttendLensTheme.primaryIndigo),
                      onPressed: _showAddClassDialog,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text("Add Class"),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Classes List Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("My Classrooms", style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  IconButton(icon: const Icon(Icons.refresh, color: Colors.grey), onPressed: _loadClasses),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Classes Grid / List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AttendLensTheme.primaryIndigo))
                  : _classes.isEmpty
                      ? Center(
                          child: Text("No classes yet. Tap '+ Add Class' above!", style: GoogleFonts.outfit(color: Colors.grey, fontSize: 16)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          itemCount: _classes.length,
                          itemBuilder: (context, index) {
                            final cls = _classes[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: AttendLensTheme.glassDecoration,
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(cls["name"], style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AttendLensTheme.primaryIndigo.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: AttendLensTheme.primaryIndigo.withOpacity(0.5)),
                                          ),
                                          child: Text("${cls["student_count"]} Students", style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.accentCyan, fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text("Subject: ${cls["subject"]}", style: GoogleFonts.outfit(color: AttendLensTheme.textSecondary, fontSize: 14)),
                                    const SizedBox(height: 18),
                                    // Action Buttons Row
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AttendLensTheme.statusPresent,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                            ),
                                            icon: const Icon(Icons.videocam, size: 20),
                                            label: const Text("Take Attendance"),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(builder: (context) => CameraCaptureScreen(classId: cls["id"], className: cls["name"])),
                                              );
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          flex: 1,
                                          child: OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              side: BorderSide(color: Colors.white.withOpacity(0.3)),
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                            ),
                                            icon: const Icon(Icons.people_outline, size: 18),
                                            label: const Text("Students"),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(builder: (context) => StudentOnboardingScreen(classId: cls["id"], className: cls["name"])),
                                              ).then((_) => _loadClasses());
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
