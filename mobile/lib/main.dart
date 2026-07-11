import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/models/teacher_model.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/screens/home_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.loadSavedBaseUrl();
  runApp(const AttendLensApp());
}

class AttendLensApp extends StatelessWidget {
  const AttendLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AttendLens',
      debugShowCheckedModeBanner: false,
      theme: AttendLensTheme.darkTheme,
      home: const _SplashRouter(),
    );
  }
}

/// Checks for a persisted session and routes to the correct screen.
class _SplashRouter extends StatefulWidget {
  const _SplashRouter();

  @override
  State<_SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<_SplashRouter> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    await Future.delayed(const Duration(milliseconds: 600)); // brief splash
    final prefs = await SharedPreferences.getInstance();
    final teacherJson = prefs.getString('teacher_data');
    if (teacherJson != null) {
      try {
        AuthState.restoreFromJson(json.decode(teacherJson) as Map<String, dynamic>);
      } catch (_) {}
    }
    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => AuthState.isLoggedIn ? const HomeDashboardScreen() : const LoginScreen(),
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AttendLensTheme.backgroundDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110, height: 110,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: AttendLensTheme.primaryIndigo.withOpacity(0.35), blurRadius: 28, offset: const Offset(0, 10))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/logo.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AttendLensTheme.surfaceDark,
                    child: const Icon(Icons.lens, color: AttendLensTheme.accentCyan, size: 48),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('AttendLens', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            const Text('Teach More. Track Less.', style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8))),
            const SizedBox(height: 48),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: AttendLensTheme.primaryIndigo, strokeWidth: 2.5)),
          ],
        ),
      ),
    );
  }
}
