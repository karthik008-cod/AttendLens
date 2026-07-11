import 'package:shared_preferences/shared_preferences.dart';

class NudgeSettingsService {
  static String defaultChannel = 'sms'; // 'sms' | 'whatsapp' | 'chooser'
  static double threshold = 75.0;       // target shortage percentage (e.g. 75.0, 65.0, 80.0)
  static String messageTemplate = 
      '🚨 AttendLens Academic Warning:\n\nHello {student_name} (Roll No: {roll_no}),\n\nYour attendance is currently at {percentage}% ({present} Present / {total} Total sessions), which falls below our mandatory {threshold}% requirement for {subject}.\n\nPlease attend upcoming classes regularly to avoid shortage penalties.';

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      defaultChannel = prefs.getString('nudge_default_channel') ?? 'sms';
      threshold = prefs.getDouble('nudge_shortage_threshold') ?? 75.0;
      final savedTemplate = prefs.getString('nudge_message_template');
      if (savedTemplate != null && savedTemplate.trim().isNotEmpty) {
        messageTemplate = savedTemplate;
      }
    } catch (_) {}
  }

  static Future<void> saveSettings({
    required String channel,
    required double newThreshold,
    required String template,
  }) async {
    defaultChannel = channel;
    threshold = newThreshold;
    messageTemplate = template.trim().isEmpty ? messageTemplate : template.trim();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('nudge_default_channel', defaultChannel);
      await prefs.setDouble('nudge_shortage_threshold', threshold);
      await prefs.setString('nudge_message_template', messageTemplate);
    } catch (_) {}
  }

  static String buildMessage({
    required String studentName,
    required String rollNumber,
    required double percentage,
    required int present,
    required int total,
    String subject = 'your class',
  }) {
    return messageTemplate
        .replaceAll('{student_name}', studentName)
        .replaceAll('{roll_no}', rollNumber)
        .replaceAll('{percentage}', percentage.toStringAsFixed(1))
        .replaceAll('{present}', present.toString())
        .replaceAll('{total}', total.toString())
        .replaceAll('{threshold}', threshold.toStringAsFixed(0))
        .replaceAll('{subject}', subject);
  }
}
