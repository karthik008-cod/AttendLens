import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/nudge_settings_service.dart';
import 'package:mobile/theme/theme.dart';

void showServerSettingsDialog(BuildContext context, {VoidCallback? onSaved}) {
  final urlCtrl = TextEditingController(text: ApiService.baseUrl);
  final templateCtrl = TextEditingController(text: NudgeSettingsService.messageTemplate);
  String selectedChannel = NudgeSettingsService.defaultChannel;
  double currentThreshold = NudgeSettingsService.threshold;
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
            Text('Server & Nudge Settings ⚙️', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1. Server API Connection',
                style: GoogleFonts.outfit(color: AttendLensTheme.accentCyan, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 10),
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
              const SizedBox(height: 24),
              const Divider(color: Colors.white12),
              const SizedBox(height: 14),

              Text(
                '2. Nudge & Shortage Preferences 📲',
                style: GoogleFonts.outfit(color: AttendLensTheme.accentCyan, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Text('Default Nudge Platform', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AttendLensTheme.backgroundDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedChannel,
                    dropdownColor: AttendLensTheme.surfaceDark,
                    icon: const Icon(Icons.arrow_drop_down, color: AttendLensTheme.accentCyan),
                    isExpanded: true,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                    items: const [
                      DropdownMenuItem(value: 'sms', child: Text('Default SMS / Messages App')),
                      DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp Direct')),
                      DropdownMenuItem(value: 'chooser', child: Text('System Share Chooser')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => selectedChannel = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Attendance Shortage Target:', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
                  Text('${currentThreshold.toStringAsFixed(0)}%', style: GoogleFonts.outfit(color: AttendLensTheme.statusAbsent, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              Slider(
                value: currentThreshold,
                min: 50.0,
                max: 90.0,
                divisions: 8,
                activeColor: AttendLensTheme.statusAbsent,
                inactiveColor: Colors.white12,
                label: '${currentThreshold.toStringAsFixed(0)}%',
                onChanged: (val) => setState(() => currentThreshold = val),
              ),
              const SizedBox(height: 10),

              Text('Custom Warning Template ({student_name}, {percentage}, {threshold}, {subject}):', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: templateCtrl,
                maxLines: 4,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AttendLensTheme.backgroundDark,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AttendLensTheme.accentCyan)),
                  contentPadding: const EdgeInsets.all(12),
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

              await NudgeSettingsService.saveSettings(
                channel: selectedChannel,
                newThreshold: currentThreshold,
                template: templateCtrl.text,
              );

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
                  statusMsg = 'Saved URL & Nudge preferences! But server ping failed: ${e.toString().replaceAll('Exception: ', '')}. Check Wi-Fi.';
                });
              }
            },
          ),
        ],
      ),
    ),
  );
}
