from sqlalchemy import Column, Integer, String, ForeignKey, Text
from sqlalchemy.orm import relationship
from app.db.database import Base


class Teacher(Base):
    __tablename__ = "teachers"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    email = Column(String, unique=True, index=True)
    password_hash = Column(String)
    institution = Column(String, nullable=True)             # School / University name
    subject_specialization = Column(String, nullable=True)  # e.g. "Mathematics"

    classes = relationship("Classroom", back_populates="teacher", cascade="all, delete-orphan")


class Classroom(Base):
    __tablename__ = "classrooms"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    subject = Column(String)
    section = Column(String, nullable=True)        # e.g. "A", "B", "Morning"
    required_photos = Column(Integer, default=3)   # How many face photos needed per student
    teacher_id = Column(Integer, ForeignKey("teachers.id"))

    teacher = relationship("Teacher", back_populates="classes")
    students = relationship("Student", back_populates="classroom", cascade="all, delete-orphan")
    lecture_dates = relationship("LectureDate", back_populates="classroom", cascade="all, delete-orphan")
    attendance_records = relationship("AttendanceRecord", back_populates="classroom", cascade="all, delete-orphan")


class StudentPhoto(Base):
    """Stores individual photos for a student. Multiple photos → better recognition accuracy."""
    __tablename__ = "student_photos"

    id = Column(Integer, primary_key=True, index=True)
    student_id = Column(Integer, ForeignKey("students.id"))
    photo_path = Column(String)
    face_encoding = Column(Text, nullable=True)  # Per-photo embedding (JSON)

    student = relationship("Student", back_populates="photos")


class Student(Base):
    __tablename__ = "students"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    roll_number = Column(String, index=True)
    photo_path = Column(String, nullable=True)   # Primary / first photo path
    face_encoding = Column(Text, nullable=True)  # AVERAGED encoding across all photos (JSON)
    classroom_id = Column(Integer, ForeignKey("classrooms.id"))

    classroom = relationship("Classroom", back_populates="students")
    attendance_records = relationship("AttendanceRecord", back_populates="student", cascade="all, delete-orphan")
    photos = relationship("StudentPhoto", back_populates="student", cascade="all, delete-orphan")


class LectureDate(Base):
    __tablename__ = "lecture_dates"

    id = Column(Integer, primary_key=True, index=True)
    date_str = Column(String, index=True)  # YYYY-MM-DD format
    classroom_id = Column(Integer, ForeignKey("classrooms.id"))

    classroom = relationship("Classroom", back_populates="lecture_dates")
    attendance_records = relationship("AttendanceRecord", back_populates="lecture_date", cascade="all, delete-orphan")


class AttendanceRecord(Base):
    __tablename__ = "attendance_records"

    id = Column(Integer, primary_key=True, index=True)
    student_id = Column(Integer, ForeignKey("students.id"))
    lecture_date_id = Column(Integer, ForeignKey("lecture_dates.id"))
    classroom_id = Column(Integer, ForeignKey("classrooms.id"))
    status = Column(String)  # "P" (Present) or "A" (Absent)

    student = relationship("Student", back_populates="attendance_records")
    lecture_date = relationship("LectureDate", back_populates="attendance_records")
    classroom = relationship("Classroom", back_populates="attendance_records")
