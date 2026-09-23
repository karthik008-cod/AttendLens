import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile/models/teacher_model.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';
import 'package:mobile/screens/omr/omr_scanner_screen.dart';

class OmrExamSetupScreen extends StatefulWidget {
  const OmrExamSetupScreen({super.key});

  @override
  State<OmrExamSetupScreen> createState() => _OmrExamSetupScreenState();
}

class _OmrExamSetupScreenState extends State<OmrExamSetupScreen> {
  final _titleCtrl = TextEditingController(text: 'NMMS State Level Mock');
  final _dateCtrl = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));

  // Sections configuration
  // Each section: { 'subject_name': 'Maths', 'num_questions': 20, 'marks_correct': 1.0, 'marks_wrong': 0.0 }
  final List<Map<String, dynamic>> _sections = [
    {
      'subject_name': 'Mental Ability (MAT)',
      'num_questions': 90,
      'marks_correct': 1.0,
      'marks_wrong': 0.0,
    },
    {
      'subject_name': 'Scholastic Aptitude (SAT)',
      'num_questions': 90,
      'marks_correct': 1.0,
      'marks_wrong': 0.0,
    },
  ];

  // Key configuration
  int _keyInputMode = 1; // 0: Key Photo Scan, 1: Manual Radio Grid
  final Map<int, int> _manualKey = {}; // q_num -> option (1, 2, 3, 4)
  File? _keyPhotoFile;
  bool _isSaving = false;

  int get _totalQuestions => _sections.fold(0, (sum, s) => sum + ((s['num_questions'] as int?) ?? 0));

  double get _totalMaxMarks {
    double total = 0.0;
    for (final s in _sections) {
      final nq = (s['num_questions'] as int?) ?? 0;
      final mc = (s['marks_correct'] as num?)?.toDouble() ?? 1.0;
      total += (nq * mc);
    }
    return total;
  }

  void _addSection() {
    setState(() {
      _sections.add({
        'subject_name': 'Subject ${_sections.length + 1}',
        'num_questions': 20,
        'marks_correct': 1.0,
        'marks_wrong': 0.0,
      });
    });
  }

  void _removeSection(int index) {
    if (_sections.length <= 1) return;
    setState(() {
      _sections.removeAt(index);
    });
  }

  Future<void> _pickKeyPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 90);
    if (picked != null) {
      setState(() => _keyPhotoFile = File(picked.path));
    }
  }

  List<Map<String, dynamic>> _buildResolvedSections() {
    final List<Map<String, dynamic>> resolved = [];
    int currentQ = 1;
    for (int i = 0; i < _sections.length; i++) {
      final s = _sections[i];
      final nq = (s['num_questions'] as int?) ?? 20;
      final startQ = currentQ;
      final endQ = currentQ + nq - 1;
      resolved.add({
        'section_id': i + 1,
        'subject_name': s['subject_name'] ?? 'Section ${i + 1}',
        'start_q': startQ,
        'end_q': endQ,
        'num_questions': nq,
        'marks_correct': (s['marks_correct'] as num?)?.toDouble() ?? 1.0,
        'marks_wrong': (s['marks_wrong'] as num?)?.toDouble() ?? 0.0,
      });
      currentQ = endQ + 1;
    }
    return resolved;
  }

  Future<void> _saveAndProceed() async {
    if (_titleCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an exam title')));
      return;
    }
    if (_totalQuestions <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Total questions must be greater than 0')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final teacherId = AuthState.teacher!.id;
      final resolvedSections = _buildResolvedSections();

      // Convert manual key map to string keys
      final Map<String, int> answerKey = {};
      _manualKey.forEach((q, opt) => answerKey[q.toString()] = opt);

      final res = await ApiService.createOmrExam(
        teacherId: teacherId,
        title: _titleCtrl.text.trim(),
        examDate: _dateCtrl.text.trim(),
        totalQuestions: _totalQuestions,
        sections: resolvedSections,
        answerKey: answerKey,
      );

      final exam = res['exam'];
      final examId = exam['id'];

      // If user selected Key Photo upload, extract key from photo now
      if (_keyInputMode == 0 && _keyPhotoFile != null) {
        try {
          final keyRes = await ApiService.uploadOmrKeyPhoto(examId, _keyPhotoFile!);
          exam['answer_key'] = keyRes['answer_key'];
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Warning: Key photo extraction: $e')));
          }
        }
      }

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => OmrScannerScreen(exam: exam)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error creating exam: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedSections = _buildResolvedSections();

    return Scaffold(
      backgroundColor: AttendLensTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AttendLensTheme.surfaceDark,
        elevation: 0,
        title: Text('Setup OMR Exam', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Exam Basic Details Card ────────────────────────────────────
              Container(
                decoration: AttendLensTheme.glassDecoration,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Exam Information', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _titleCtrl,
                      style: GoogleFonts.outfit(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Exam Title',
                        hintText: 'e.g. NMMS State Level Mock 2026',
                        prefixIcon: const Icon(Icons.title, color: AttendLensTheme.accentCyan),
                        filled: true,
                        fillColor: AttendLensTheme.backgroundDark,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _dateCtrl,
                            style: GoogleFonts.outfit(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Exam Date',
                              prefixIcon: const Icon(Icons.calendar_today, color: AttendLensTheme.textSecondary),
                              filled: true,
                              fillColor: AttendLensTheme.backgroundDark,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: AttendLensTheme.primaryIndigo.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AttendLensTheme.primaryIndigo.withOpacity(0.4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('$_totalQuestions Questions', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: AttendLensTheme.accentCyan)),
                              Text('$_totalMaxMarks Max Marks', style: GoogleFonts.outfit(fontSize: 11, color: AttendLensTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Section 1: Subject Sections Configurator ──────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Exam Sections & Subjects', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 2),
                        Text('Divide questions by subject with individual marking', style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AttendLensTheme.primaryIndigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text('Add Section', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _addSection,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Section Cards
              ...List.generate(_sections.length, (idx) {
                final sec = _sections[idx];
                final resSec = resolvedSections[idx];
                final qRange = 'Q ${resSec['start_q']} to ${resSec['end_q']}';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: AttendLensTheme.glassDecoration,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AttendLensTheme.primaryIndigo.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('Section ${idx + 1}: $qRange', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: AttendLensTheme.accentCyan)),
                          ),
                          if (_sections.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                              onPressed: () => _removeSection(idx),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Subject Name
                      TextFormField(
                        initialValue: sec['subject_name'],
                        style: GoogleFonts.outfit(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Subject Name',
                          hintText: 'e.g. Maths, Science, Social',
                          prefixIcon: const Icon(Icons.book_outlined, color: AttendLensTheme.textSecondary, size: 18),
                          filled: true,
                          fillColor: AttendLensTheme.backgroundDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        onChanged: (v) => sec['subject_name'] = v,
                      ),
                      const SizedBox(height: 10),

                      // Questions count & Marking scheme row
                      Row(
                        children: [
                          // Number of questions
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              initialValue: '${sec['num_questions']}',
                              keyboardType: TextInputType.number,
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'Questions',
                                labelStyle: GoogleFonts.outfit(fontSize: 12),
                                prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                prefixIcon: const Icon(Icons.format_list_numbered, color: AttendLensTheme.textSecondary, size: 16),
                                filled: true,
                                fillColor: AttendLensTheme.backgroundDark,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                              ),
                              onChanged: (v) {
                                final n = int.tryParse(v);
                                if (n != null && n > 0) {
                                  setState(() => sec['num_questions'] = n);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Correct marks
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              initialValue: '${sec['marks_correct']}',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: '+ Mark',
                                labelStyle: GoogleFonts.outfit(fontSize: 12),
                                prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                prefixIcon: const Icon(Icons.check_circle_outline, color: AttendLensTheme.statusPresent, size: 16),
                                filled: true,
                                fillColor: AttendLensTheme.backgroundDark,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                              ),
                              onChanged: (v) {
                                final n = double.tryParse(v);
                                if (n != null) sec['marks_correct'] = n;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Negative marks
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              initialValue: '${sec['marks_wrong']}',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: '- Penalty',
                                labelStyle: GoogleFonts.outfit(fontSize: 12),
                                prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                prefixIcon: const Icon(Icons.remove_circle_outline, color: AttendLensTheme.statusAbsent, size: 16),
                                filled: true,
                                fillColor: AttendLensTheme.backgroundDark,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                              ),
                              onChanged: (v) {
                                final n = double.tryParse(v);
                                if (n != null) sec['marks_wrong'] = n;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 20),

              // ── Section 2: Answer Key Setup ───────────────────────────────
              Text('Answer Key Configuration', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Select how you want to provide the correct answers', style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.textSecondary)),
              const SizedBox(height: 14),

              // Toggle Mode (Key Photo vs Manual Radio Grid)
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _keyInputMode = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _keyInputMode == 0 ? AttendLensTheme.primaryIndigo : AttendLensTheme.surfaceDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _keyInputMode == 0 ? AttendLensTheme.primaryIndigo : Colors.white12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                            const SizedBox(width: 8),
                            Text('Scan Key Photo', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _keyInputMode = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _keyInputMode == 1 ? AttendLensTheme.primaryIndigo : AttendLensTheme.surfaceDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _keyInputMode == 1 ? AttendLensTheme.primaryIndigo : Colors.white12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.radio_button_checked, size: 18, color: Colors.white),
                            const SizedBox(width: 8),
                            Text('Manual Radio Grid', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Mode 0: Photo Upload Card
              if (_keyInputMode == 0)
                Container(
                  decoration: AttendLensTheme.glassDecoration,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upload Filled Key OMR Sheet', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 6),
                      Text('Capture or upload a photo of the teacher\'s filled OMR answer key.', style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.textSecondary)),
                      const SizedBox(height: 16),
                      if (_keyPhotoFile != null) ...[
                        Container(
                          height: 160,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AttendLensTheme.accentCyan),
                            image: DecorationImage(image: FileImage(_keyPhotoFile!), fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AttendLensTheme.accentCyan,
                                side: BorderSide(color: AttendLensTheme.accentCyan.withOpacity(0.4)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.camera_alt),
                              label: Text('Camera', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                              onPressed: () => _pickKeyPhoto(ImageSource.camera),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withOpacity(0.3)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.photo_library),
                              label: Text('Gallery', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                              onPressed: () => _pickKeyPhoto(ImageSource.gallery),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )

              // Mode 1: Manual Radio Buttons Matrix
              else
                Container(
                  decoration: AttendLensTheme.glassDecoration,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Select Correct Options', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          Text('${_manualKey.length} / $_totalQuestions Keyed', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: AttendLensTheme.accentCyan)),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Quick actions
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                for (int i = 1; i <= _totalQuestions; i++) {
                                  _manualKey[i] = (i % 4) + 1; // Pattern 2,3,4,1
                                }
                              });
                            },
                            child: Text('Auto-fill Sample', style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.accentCyan)),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() => _manualKey.clear()),
                            child: Text('Clear All', style: GoogleFonts.outfit(fontSize: 12, color: AttendLensTheme.statusAbsent)),
                          ),
                        ],
                      ),

                      // Question rows (scrollable or limited list)
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _totalQuestions,
                        separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.08), height: 1),
                        itemBuilder: (ctx, idx) {
                          final qNum = idx + 1;
                          final selectedOpt = _manualKey[qNum];

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 44,
                                  child: Text('Q$qNum', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 13)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [1, 2, 3, 4].map((opt) {
                                      final isSelected = selectedOpt == opt;
                                      return GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            if (isSelected) {
                                              _manualKey.remove(qNum);
                                            } else {
                                              _manualKey[qNum] = opt;
                                            }
                                          });
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 150),
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: isSelected ? AttendLensTheme.statusPresent : AttendLensTheme.backgroundDark,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: isSelected ? AttendLensTheme.statusPresent : Colors.white24, width: 1.5),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '$opt',
                                              style: GoogleFonts.outfit(
                                                color: isSelected ? Colors.white : Colors.white70,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 30),

              // ── Submit Button ─────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AttendLensTheme.primaryIndigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 6,
                  ),
                  icon: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.arrow_forward),
                  label: Text(
                    _isSaving ? 'Saving Exam...' : 'Save & Start Scanning',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isSaving ? null : _saveAndProceed,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
