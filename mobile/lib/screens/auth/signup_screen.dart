import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:mobile/models/teacher_model.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';
import 'package:mobile/screens/home_dashboard_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _institutionController = TextEditingController();
  final _subjectController = TextEditingController();
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _confirmPassController = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _nameController.dispose();
    _institutionController.dispose();
    _subjectController.dispose();
    _emailController.dispose();
    _passController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final name = _nameController.text.trim();
    final institution = _institutionController.text.trim();
    final subject = _subjectController.text.trim();
    final email = _emailController.text.trim();
    final pass = _passController.text;
    final confirm = _confirmPassController.text;

    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _errorMsg = 'Name, email and password are required');
      return;
    }
    if (pass != confirm) {
      setState(() => _errorMsg = 'Passwords do not match');
      return;
    }
    if (pass.length < 6) {
      setState(() => _errorMsg = 'Password must be at least 6 characters');
      return;
    }

    setState(() { _isLoading = true; _errorMsg = null; });

    try {
      final data = await ApiService.register(
        name: name,
        email: email,
        password: pass,
        institution: institution.isEmpty ? null : institution,
        subjectSpecialization: subject.isEmpty ? null : subject,
      );
      final teacher = TeacherModel.fromJson(data);
      AuthState.login(teacher);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('teacher_data', json.encode(teacher.toJson()));

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeDashboardScreen(),
            transitionDuration: const Duration(milliseconds: 400),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
          ),
          (_) => false,
        );
      }
    } catch (e) {
      setState(() => _errorMsg = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF060911), AttendLensTheme.backgroundDark, Color(0xFF0D1526)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 20),

                // Header
                Text('Create Account 🎓', style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text('Join AttendLens and simplify your classroom.', style: GoogleFonts.outfit(fontSize: 14, color: AttendLensTheme.textSecondary)),
                const SizedBox(height: 32),

                // Error
                if (_errorMsg != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AttendLensTheme.statusAbsent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AttendLensTheme.statusAbsent.withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: AttendLensTheme.statusAbsent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_errorMsg!, style: GoogleFonts.outfit(color: AttendLensTheme.statusAbsent, fontSize: 13))),
                    ]),
                  ),
                  const SizedBox(height: 20),
                ],

                _FieldLabel('Full Name *'),
                _inputField(controller: _nameController, hint: 'Dr. Alan Turing', icon: Icons.person_outline),
                const SizedBox(height: 18),

                _FieldLabel('University / School Name'),
                _inputField(controller: _institutionController, hint: 'MIT, IIT Bombay, etc.', icon: Icons.school_outlined),
                const SizedBox(height: 18),

                _FieldLabel('Subject Specialization'),
                _inputField(controller: _subjectController, hint: 'e.g. Computer Science, Physics', icon: Icons.auto_stories_outlined),
                const SizedBox(height: 18),

                _FieldLabel('Email Address *'),
                _inputField(controller: _emailController, hint: 'teacher@school.edu', icon: Icons.mail_outline, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 18),

                _FieldLabel('Password *'),
                _inputField(
                  controller: _passController, hint: 'Min. 6 characters', icon: Icons.lock_outline, obscure: _obscurePass,
                  suffix: IconButton(
                    icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AttendLensTheme.textSecondary, size: 20),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
                const SizedBox(height: 18),

                _FieldLabel('Confirm Password *'),
                _inputField(
                  controller: _confirmPassController, hint: 'Re-enter password', icon: Icons.lock_outline, obscure: _obscureConfirm,
                  suffix: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AttendLensTheme.textSecondary, size: 20),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                const SizedBox(height: 32),

                // Create Account Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _isLoading ? null : _signUp,
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: _isLoading ? null : const LinearGradient(colors: [AttendLensTheme.primaryIndigo, AttendLensTheme.primaryPurple]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        child: _isLoading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                            : Text('Create Account', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: RichText(
                      text: TextSpan(
                        style: GoogleFonts.outfit(fontSize: 14, color: AttendLensTheme.textSecondary),
                        children: [
                          const TextSpan(text: 'Already have an account? '),
                          TextSpan(text: 'Sign In', style: GoogleFonts.outfit(color: AttendLensTheme.primaryIndigo, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _FieldLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AttendLensTheme.textSecondary)),
  );

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    IconData? icon,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffix,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.outfit(color: AttendLensTheme.textSecondary.withOpacity(0.5)),
          prefixIcon: icon != null ? Icon(icon, color: AttendLensTheme.textSecondary, size: 20) : null,
          filled: true,
          fillColor: AttendLensTheme.surfaceDark,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AttendLensTheme.primaryIndigo, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          suffixIcon: suffix,
        ),
      );
}
