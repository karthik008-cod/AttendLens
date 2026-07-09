"""MongoDB Document Schema & Helper Classes for AttendLens"""

class Teacher:
    collection = "teachers"

class Classroom:
    collection = "classrooms"

class StudentPhoto:
    collection = "student_photos"

class Student:
    collection = "students"

class LectureDate:
    collection = "lecture_dates"

class AttendanceRecord:
    collection = "attendance_records"
