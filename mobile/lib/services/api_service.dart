import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiService {
  static String baseUrl = 'http://127.0.0.1:8000/api';
  static WebSocketChannel? _liveWsChannel;

  static WebSocketChannel connectLiveScanWs(int classroomId) {
    _liveWsChannel?.sink.close();
    final wsUrl = baseUrl.replaceAll('http://', 'ws://').replaceAll('https://', 'wss://');
    _liveWsChannel = WebSocketChannel.connect(Uri.parse('$wsUrl/ws/live_scan/$classroomId'));
    return _liveWsChannel!;
  }

  static bool sendLiveScanFrameBytes(List<int> bytes) {
    if (_liveWsChannel != null) {
      _liveWsChannel!.sink.add(bytes);
      return true;
    }
    return false;
  }

  static void disconnectLiveScanWs() {
    _liveWsChannel?.sink.close();
    _liveWsChannel = null;
  }

  static void setBaseUrl(String url) => baseUrl = url;

  static Future<void> loadSavedBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('saved_base_url');
      if (saved != null && saved.isNotEmpty) {
        baseUrl = saved;
      }
    } catch (_) {}
  }

  static Future<void> saveBaseUrl(String url) async {
    baseUrl = url;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_base_url', url);
    } catch (_) {}
  }

  // ── Auth ────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? institution,
    String? subjectSpecialization,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'name': name,
        'email': email,
        'password': password,
        'institution': institution,
        'subject_specialization': subjectSpecialization,
      }),
    );
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception(json.decode(res.body)['detail'] ?? 'Registration failed');
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception(json.decode(res.body)['detail'] ?? 'Invalid credentials');
  }

  static Future<Map<String, dynamic>> updateTeacher(
    int teacherId, {
    String? name,
    String? institution,
    String? subjectSpecialization,
  }) async {
    final res = await http.put(
      Uri.parse('$baseUrl/teacher/$teacherId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        if (name != null) 'name': name,
        if (institution != null) 'institution': institution,
        if (subjectSpecialization != null) 'subject_specialization': subjectSpecialization,
      }),
    );
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Failed to update profile');
  }

  // ── Classes ─────────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getClasses(int teacherId) async {
    final res = await http.get(Uri.parse('$baseUrl/classes/$teacherId'));
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Failed to load classes');
  }

  static Future<Map<String, dynamic>> createClass({
    required String name,
    required String subject,
    String? section,
    int requiredPhotos = 3,
    required int teacherId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/classes'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'name': name,
        'subject': subject,
        'section': section,
        'required_photos': requiredPhotos,
        'teacher_id': teacherId,
      }),
    );
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Failed to create class');
  }

  static Future<Map<String, dynamic>> updateClass(
    int classId, {
    String? name,
    String? subject,
    String? section,
    int? requiredPhotos,
  }) async {
    final res = await http.put(
      Uri.parse('$baseUrl/classes/$classId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        if (name != null) 'name': name,
        if (subject != null) 'subject': subject,
        if (section != null) 'section': section,
        if (requiredPhotos != null) 'required_photos': requiredPhotos,
      }),
    );
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Failed to update class');
  }

  static Future<void> deleteClass(int classId) async {
    final res = await http.delete(Uri.parse('$baseUrl/classes/$classId'));
    if (res.statusCode != 200) {
      throw Exception('Failed to delete class');
    }
  }

  // ── Students ────────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getStudents(int classId) async {
    final res = await http.get(Uri.parse('$baseUrl/classes/$classId/students'));
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Failed to load students');
  }

  static Future<Map<String, dynamic>> addStudent(
    String name,
    String rollNumber,
    int classroomId,
    File? photo,
  ) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/students'));
    request.fields['name'] = name;
    request.fields['roll_number'] = rollNumber;
    request.fields['classroom_id'] = classroomId.toString();
    if (photo != null && await photo.exists()) {
      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));
    }
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 200) return json.decode(res.body);
    try {
      final errData = json.decode(res.body);
      if (errData['detail'] != null) throw Exception(errData['detail']);
    } catch (e) {
      if (e.toString().contains('Exception: ')) rethrow;
    }
    throw Exception('Failed to add student: ${res.body}');
  }

  static Future<Map<String, dynamic>> addStudentBatch(
    String name,
    String rollNumber,
    int classroomId,
    List<File> photos,
  ) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/students/batch'));
    request.fields['name'] = name;
    request.fields['roll_number'] = rollNumber;
    request.fields['classroom_id'] = classroomId.toString();
    for (final photo in photos) {
      if (await photo.exists()) {
        request.files.add(await http.MultipartFile.fromPath('photos', photo.path));
      }
    }
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 200) return json.decode(res.body);
    try {
      final errData = json.decode(res.body);
      if (errData['detail'] != null) throw Exception(errData['detail']);
    } catch (e) {
      if (e.toString().contains('Exception: ')) rethrow;
    }
    throw Exception('Failed to add student in batch: ${res.body}');
  }

  static Future<void> addStudentPhoto(int studentId, File photo) async {
    var request = http.MultipartRequest(
        'POST', Uri.parse('$baseUrl/students/$studentId/photos'));
    request.files.add(await http.MultipartFile.fromPath('photo', photo.path));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw Exception('Failed to upload photo');
  }

  static Future<Map<String, dynamic>> updateStudent(
    int studentId, {
    String? name,
    String? rollNumber,
  }) async {
    final res = await http.put(
      Uri.parse('$baseUrl/students/$studentId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        if (name != null) 'name': name,
        if (rollNumber != null) 'roll_number': rollNumber,
      }),
    );
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Failed to update student');
  }

  static Future<void> deleteStudent(int studentId) async {
    final res = await http.delete(Uri.parse('$baseUrl/students/$studentId'));
    if (res.statusCode != 200) throw Exception('Failed to delete student');
  }

  static Future<Map<String, dynamic>> checkPhotoQuality(File photo) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/students/check-quality'));
    request.files.add(await http.MultipartFile.fromPath('photo', photo.path));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 200) return json.decode(res.body);
    return {'is_good': true, 'sharpness_score': 100.0, 'brightness_score': 128.0, 'warning_message': null};
  }

  // ── Attendance ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> scanVideo(int classroomId, File videoFile) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/attendance/scan'));
    request.fields['classroom_id'] = classroomId.toString();
    request.files.add(await http.MultipartFile.fromPath('video', videoFile.path));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Failed to scan video');
  }

  static Future<Map<String, dynamic>> streamFrame(int classroomId, File frameFile) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/attendance/stream-frame'));
    request.fields['classroom_id'] = classroomId.toString();
    request.files.add(await http.MultipartFile.fromPath('frame', frameFile.path));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Failed to stream frame');
  }

  static Future<Map<String, dynamic>> confirmAttendance(
    int classroomId,
    String dateStr,
    List<int> presentIds,
    List<int> absentIds,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/attendance/confirm'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'classroom_id': classroomId,
        'date_str': dateStr,
        'present_student_ids': presentIds,
        'absent_student_ids': absentIds,
      }),
    );
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Failed to save attendance');
  }

  static Future<Map<String, dynamic>> updatePastAttendance(int studentId, String dateStr, String status) async {
    final res = await http.put(
      Uri.parse('$baseUrl/attendance/record'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'student_id': studentId,
        'date_str': dateStr,
        'status': status,
      }),
    );
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Failed to update past record');
  }

  // ── Reports ─────────────────────────────────────────────────────────────────

  static String getExcelReportUrl(int classId) => '$baseUrl/reports/class/$classId/excel';

  // ── Analytics ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getClassAnalytics(int classId) async {
    final res = await http.get(Uri.parse('$baseUrl/analytics/class/$classId'));
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Failed to load analytics');
  }

  static Future<Map<String, dynamic>> getStudentAnalytics(int studentId) async {
    final res = await http.get(Uri.parse('$baseUrl/analytics/student/$studentId'));
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Failed to load student analytics');
  }

  /// Returns the student self-registration URL for a class
  static String getInviteUrl(int classId) {
    final serverBase = baseUrl.replaceFirst('/api', '');
    return '$serverBase/invite/$classId';
  }
}
