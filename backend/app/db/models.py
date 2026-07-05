from sqlalchemy import Column, Integer, String, ForeignKey, Text
from sqlalchemy.orm import relationship
from app.db.database import Base

class Teacher(Base):
    __tablename__ = "teachers"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    email = Column(String, unique=True, index=True)
    password_hash = Column(String)

    classes = relationship("Classroom", back_populates="teacher", cascade="all, delete-orphan")

class Classroom(Base):
    __tablename__ = "classrooms"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    subject = Column(String)
    teacher_id = Column(Integer, ForeignKey("teachers.id"))

    teacher = relationship("Teacher", back_populates="classes")
    students = relationship("Student", back_populates="classroom", cascade="all, delete-orphan")
    lecture_dates = relationship("LectureDate", back_populates="classroom", cascade="all, delete-orphan")
    attendance_records = relationship("AttendanceRecord", back_populates="classroom", cascade="all, delete-orphan")

class Student(Base):
    __tablename__ = "students"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    roll_number = Column(String, index=True)
    photo_path = Column(String, nullable=True)
    face_encoding = Column(Text, nullable=True)  # JSON string of embedding vector
    classroom_id = Column(Integer, ForeignKey("classrooms.id"))

    classroom = relationship("Classroom", back_populates="students")
    attendance_records = relationship("AttendanceRecord", back_populates="student", cascade="all, delete-orphan")

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
    status = Column(String)  # "P" (Present), "A" (Absent), "L" (Late)

    student = relationship("Student", back_populates="attendance_records")
    lecture_date = relationship("LectureDate", back_populates="attendance_records")
    classroom = relationship("Classroom", back_populates="attendance_records")
