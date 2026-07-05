/// Holds teacher data returned by the API.
class TeacherModel {
  final int id;
  final String name;
  final String email;
  final String? institution;
  final String? subjectSpecialization;

  const TeacherModel({
    required this.id,
    required this.name,
    required this.email,
    this.institution,
    this.subjectSpecialization,
  });

  factory TeacherModel.fromJson(Map<String, dynamic> json) => TeacherModel(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String,
        institution: json['institution'] as String?,
        subjectSpecialization: json['subject_specialization'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'institution': institution,
        'subject_specialization': subjectSpecialization,
      };

  /// Display name: first name only for greeting
  String get firstName => name.split(' ').first;

  /// Initials for avatar fallback
  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

/// Singleton holding the currently logged-in teacher session.
/// Backed by SharedPreferences for persistence across app restarts.
class AuthState {
  AuthState._();

  static TeacherModel? _teacher;

  static TeacherModel? get teacher => _teacher;
  static bool get isLoggedIn => _teacher != null;

  static void login(TeacherModel t) => _teacher = t;

  static void logout() => _teacher = null;

  static void restoreFromJson(Map<String, dynamic> json) {
    _teacher = TeacherModel.fromJson(json);
  }
}
