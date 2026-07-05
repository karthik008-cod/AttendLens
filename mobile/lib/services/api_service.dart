import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  // Default to localhost for Android emulator (10.0.2.2) or local PC IP
  static String baseUrl = 'http://10.0.2.2:8000/api';

  static void setBaseUrl(String url) {
    baseUrl = url;
  }

  // 1. Get Teacher Classes
  static Future<List<dynamic>> getClasses(int teacherId) async {
    final response = await http.get(Uri.parse('$baseUrl/classes/$teacherId'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load classes: ${response.body}');
    }
  }

  // 2. Create Class
  static Future<Map<String, dynamic>> createClass(String name, String subject, int teacherId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/classes'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'name': name,
        'subject': subject,
        'teacher_id': teacherId,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to create class: ${response.body}');
    }
  }

  // 3. Get Students in a Class
  static Future<List<dynamic>> getStudents(int classId) async {
    final response = await http.get(Uri.parse('$baseUrl/classes/$classId/students'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load students: ${response.body}');
    }
  }

  // 4. Add Student with Photo
  static Future<Map<String, dynamic>> addStudent(String name, String rollNumber, int classroomId, File? photo) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/students'));
    request.fields['name'] = name;
    request.fields['roll_number'] = rollNumber;
    request.fields['classroom_id'] = classroomId.toString();

    if (photo != null && await photo.exists()) {
      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));
    }

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to add student: ${response.body}');
    }
  }

  // 5. Scan Classroom Video
  static Future<Map<String, dynamic>> scanVideo(int classroomId, File videoFile) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/attendance/scan'));
    request.fields['classroom_id'] = classroomId.toString();
    request.files.add(await http.MultipartFile.fromPath('video', videoFile.path));

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to process video scan: ${response.body}');
    }
  }

  // 6. Confirm and Save Attendance
  static Future<Map<String, dynamic>> confirmAttendance(int classroomId, String dateStr, List<int> presentIds, List<int> absentIds) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/confirm'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'classroom_id': classroomId,
        'date_str': dateStr,
        'present_student_ids': presentIds,
        'absent_student_ids': absentIds,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to save attendance: ${response.body}');
    }
  }

  // 7. Get Excel Report Download URL
  static String getExcelReportUrl(int classId) {
    return '$baseUrl/reports/class/$classId/excel';
  }
}
