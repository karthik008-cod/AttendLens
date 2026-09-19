import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/models/teacher_model.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';
import 'package:mobile/screens/omr/omr_exam_setup_screen.dart';
import 'package:mobile/screens/omr/omr_scanner_screen.dart';
import 'package:mobile/screens/omr/omr_analytics_screen.dart';

class OmrHubScreen extends StatefulWidget {
  const OmrHubScreen({super.key});

  @override
  State<OmrHubScreen> createState() => _OmrHubScreenState();
}

class _OmrHubScreenState extends State<OmrHubScreen> {
  List<dynamic> _exams = [];
  bool _isLoading = true;

  TeacherModel get _teacher => AuthState.teacher!;

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  Future<void> _loadExams() async {
    setState(() => _isLoading = true);
    try {
      final exams = await ApiService.getOmrExams(_teacher.id);
      if (mounted) setState(() { _exams = exams; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteExam(int examId, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AttendLensTheme.surfaceDark,
        title: Text('Delete Exam?', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "$title"? All scanned submissions and analytics will be removed.', style: GoogleFonts.outfit(color: Colors.white70)),
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
        await ApiService.deleteOmrExam(examId);
        _loadExams();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AttendLensTheme.backgroundDark,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadExams,
          color: AttendLensTheme.primaryIndigo,
          child: CustomScrollView(
            slivers: [
              // ── Header Banner ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AttendLensTheme.primaryIndigo.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AttendLensTheme.primaryIndigo.withOpacity(0.4)),
                                ),
                                child: const Icon(Icons.document_scanner, color: AttendLensTheme.accentCyan, size: 28),
                              ),
                              const SizedBox(width: 14),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Scan OMR', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                                  Text('EXAM EVALUATION & PSYCHOMETRICS', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700, color: AttendLensTheme.accentCyan, letterSpacing: 1.5)),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.white70),
                            onPressed: _loadExams,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Create multi-section exams, scan OMR sheets in single or continuous mode, and get instant CTT item analysis, rankings & reports.',
                        style: GoogleFonts.outfit(fontSize: 13, color: AttendLensTheme.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AttendLensTheme.primaryIndigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 4,
                          ),
                          icon: const Icon(Icons.add, size: 20),
                          label: Text('Create New Exam', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const OmrExamSetupScreen()),
                          ).then((_) => _loadExams()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Exam List Header ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Your Examinations', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('${_exams.length} Exams', style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.textSecondary)),
                    ],
                  ),
                ),
              ),

              // ── Exams List ────────────────────────────────────────────────
              if (_isLoading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AttendLensTheme.primaryIndigo)))
              else if (_exams.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.assignment_outlined, size: 64, color: Colors.white24),
                      const SizedBox(height: 16),
                      Text('No OMR Exams yet', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 6),
                      Text('Tap "Create New Exam" to set up your first exam', style: GoogleFonts.outfit(fontSize: 13, color: AttendLensTheme.textSecondary)),
                    ]),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final ex = _exams[index];
                      final sections = (ex['sections'] as List<dynamic>?) ?? [];
                      final subCount = ex['submission_count'] ?? 0;
                      final totalQ = ex['total_questions'] ?? 180;
                      final maxMarks = ex['total_max_marks'] ?? 0;

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: Container(
                          decoration: AttendLensTheme.glassDecoration,
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(ex['title'] ?? 'Exam', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.calendar_today, size: 12, color: AttendLensTheme.textSecondary),
                                            const SizedBox(width: 4),
                                            Text(ex['exam_date'] ?? '', style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.textSecondary)),
                                            const SizedBox(width: 12),
                                            const Icon(Icons.help_outline, size: 12, color: AttendLensTheme.accentCyan),
                                            const SizedBox(width: 4),
                                            Text('$totalQ Questions ($maxMarks M)', style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.accentCyan)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
                                    onPressed: () => _deleteExam(ex['id'], ex['title'] ?? 'Exam'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Section chips
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: sections.map((sec) {
                                  final name = sec['subject_name'] ?? 'Section';
                                  final qRange = 'Q${sec['start_q']}-${sec['end_q']}';
                                  final mScheme = '+${sec['marks_correct']}/-${sec['marks_wrong']}';
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AttendLensTheme.primaryIndigo.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AttendLensTheme.primaryIndigo.withOpacity(0.3)),
                                    ),
                                    child: Text('$name ($qRange, $mScheme)', style: GoogleFonts.outfit(fontSize: 11, color: Colors.white70)),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),

                              // Action buttons
                              Row(
                                children: [
                                  // Scan Button
                                  Expanded(
                                    flex: 3,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AttendLensTheme.statusPresent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                                      label: Text('Scan OMR', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => OmrScannerScreen(exam: ex)),
                                      ).then((_) => _loadExams()),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Analytics Button
                                  Expanded(
                                    flex: 3,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AttendLensTheme.accentCyan,
                                        side: BorderSide(color: AttendLensTheme.accentCyan.withOpacity(0.4)),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      icon: const Icon(Icons.bar_chart, size: 18),
                                      label: Text('Analytics ($subCount)', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => OmrAnalyticsScreen(exam: ex)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: _exams.length,
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ),
    );
  }
}
