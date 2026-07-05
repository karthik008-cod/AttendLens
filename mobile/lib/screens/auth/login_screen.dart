import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:mobile/models/teacher_model.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';
import 'package:mobile/screens/home_dashboard_screen.dart';
import 'package:mobile/screens/auth/signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _obscurePass = true;
  bool _isLoading = false;
  String? _errorMsg;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passController.text.isEmpty) {
      setState(() => _errorMsg = 'Please fill in all fields');
      return;
    }
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final data = await ApiService.login(_emailController.text.trim(), _passController.text);
      final teacher = TeacherModel.fromJson(data);
      AuthState.login(teacher);

      // Persist session
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('teacher_data', json.encode(teacher.toJson()));

      if (mounted) {
        Navigator.pushReplacement(context, _fadeRoute(const HomeDashboardScreen()));
      }
    } catch (e) {
      setState(() { _errorMsg = e.toString().replaceAll('Exception: ', ''); });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  PageRoute _fadeRoute(Widget page) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: const Duration(milliseconds: 400),
    transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
  );

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
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),

                  // Logo
                  Center(
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AttendLensTheme.primaryIndigo, AttendLensTheme.primaryPurple]),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [BoxShadow(color: AttendLensTheme.primaryIndigo.withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 8))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset('assets/logo.jpg', width: 80, height: 80, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Text('🎥', style: TextStyle(fontSize: 38)))),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Center(child: Text('AttendLens', style: GoogleFonts.outfit(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white))),
                  Center(child: Text('AI-Powered Attendance System', style: GoogleFonts.outfit(fontSize: 14, color: AttendLensTheme.textSecondary))),
                  const SizedBox(height: 48),

                  Text('Welcome back 👋', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Sign in to your teacher account', style: GoogleFonts.outfit(fontSize: 14, color: AttendLensTheme.textSecondary)),
                  const SizedBox(height: 32),

                  // Error Banner
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

                  // Email
                  _FieldLabel('Email Address'),
                  _inputField(controller: _emailController, hint: 'teacher@school.edu', keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 20),

                  // Password
                  _FieldLabel('Password'),
                  _inputField(
                    controller: _passController,
                    hint: '••••••••',
                    obscure: _obscurePass,
                    suffix: IconButton(
                      icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AttendLensTheme.textSecondary, size: 20),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Sign In Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isLoading ? null : _login,
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: _isLoading ? null : const LinearGradient(colors: [AttendLensTheme.primaryIndigo, AttendLensTheme.primaryPurple]),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: _isLoading
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                              : Text('Sign In', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Sign Up Link
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.outfit(fontSize: 14, color: AttendLensTheme.textSecondary),
                          children: [
                            const TextSpan(text: "Don't have an account? "),
                            TextSpan(text: 'Create one', style: GoogleFonts.outfit(color: AttendLensTheme.primaryIndigo, fontWeight: FontWeight.bold)),
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
