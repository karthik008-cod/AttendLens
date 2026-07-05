import 'package:flutter/material.dart';
import 'package:mobile/theme/theme.dart';
import 'package:mobile/screens/class_dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const ClassDashboardScreen(),
    );
  }
}
