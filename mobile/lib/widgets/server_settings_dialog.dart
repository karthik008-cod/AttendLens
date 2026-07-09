import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/services/api_service.dart';
import 'package:mobile/theme/theme.dart';

void showServerSettingsDialog(BuildContext context, {VoidCallback? onSaved}) {
  final urlCtrl = TextEditingController(text: ApiService.baseUrl);
  bool isTesting = false;
  String? statusMsg;
  bool isSuccess = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: AttendLensTheme.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Colors.white12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AttendLensTheme.accentCyan.withOpacity(0.15), shape: BoxShape.circle),
              child: const Icon(Icons.settings_input_antenna, color: AttendLensTheme.accentCyan, size: 22),
            ),
            const SizedBox(width: 12),
            Text('Server Settings ⚙️', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your backend API address so you can use AttendLens wirelessly without a USB cable!',
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: urlCtrl,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Backend API URL',
                  labelStyle: GoogleFonts.outfit(color: AttendLensTheme.textSecondary),
                  hintText: 'https://attendlens.onrender.com/api',
                  hintStyle: GoogleFonts.outfit(color: Colors.white30, fontSize: 13),
                  prefixIcon: const Icon(Icons.link, color: AttendLensTheme.accentCyan, size: 20),
                  filled: true,
                  fillColor: AttendLensTheme.backgroundDark,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AttendLensTheme.accentCyan)),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.wifi, color: AttendLensTheme.accentCyan, size: 16),
                        const SizedBox(width: 6),
                        Text('💡 How to connect wirelessly:', style: GoogleFonts.outfit(color: AttendLensTheme.accentCyan, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Connect phone & laptop to same Wi-Fi.\n'
                      '2. Open PowerShell on laptop, run: ipconfig\n'
                      '3. Find your IPv4 (e.g., 192.168.1.15)\n'
                      '4. Enter: http://192.168.1.15:8000/api',
                      style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
              if (statusMsg != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isSuccess ? AttendLensTheme.statusPresent : AttendLensTheme.statusAbsent).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSuccess ? AttendLensTheme.statusPresent : AttendLensTheme.statusAbsent),
                  ),
                  child: Row(
                    children: [
                      Icon(isSuccess ? Icons.check_circle : Icons.error_outline, color: isSuccess ? AttendLensTheme.statusPresent : AttendLensTheme.statusAbsent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(statusMsg!, style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, height: 1.3))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white60, fontSize: 14)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AttendLensTheme.primaryIndigo,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: isTesting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
            label: Text(isTesting ? 'Testing...' : 'Test & Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            onPressed: isTesting ? null : () async {
              final newUrl = urlCtrl.text.trim();
              if (newUrl.isEmpty) return;
              setState(() { isTesting = true; statusMsg = null; });
              try {
                final testUri = Uri.parse(newUrl.replaceAll('/api', '') + '/docs');
                final res = await http.get(testUri).timeout(const Duration(seconds: 3));
                if (res.statusCode == 200 || res.statusCode == 404) {
                  await ApiService.saveBaseUrl(newUrl);
                  setState(() {
                    isTesting = false;
                    isSuccess = true;
                    statusMsg = 'Connected & Saved successfully!';
                  });
                  if (onSaved != null) onSaved();
                  Future.delayed(const Duration(milliseconds: 1000), () {
                    if (ctx.mounted) Navigator.pop(ctx);
                  });
                } else {
                  throw Exception('Server returned status ${res.statusCode}');
                }
              } catch (e) {
                await ApiService.saveBaseUrl(newUrl);
                if (onSaved != null) onSaved();
                setState(() {
                  isTesting = false;
                  isSuccess = false;
                  statusMsg = 'Saved! But test failed: ${e.toString().replaceAll('Exception: ', '')}. Make sure your laptop and phone are on the same Wi-Fi.';
                });
              }
            },
          ),
        ],
      ),
    ),
  );
}
