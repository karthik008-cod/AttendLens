import os
import sys
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.db.database import engine, Base, SessionLocal
from app.db.models import Teacher, Classroom, Student, LectureDate, AttendanceRecord
from app.services.excel_service import generate_class_excel

# Create tables
Base.metadata.create_all(bind=engine)
db = SessionLocal()

try:
    # Check if test teacher exists
    teacher = db.query(Teacher).filter(Teacher.email == "test@school.edu").first()
    if not teacher:
        teacher = Teacher(name="Prof. Alan Turing", email="test@school.edu", password_hash="secret")
        db.add(teacher)
        db.commit()
        db.refresh(teacher)

    # Check if test class exists
    classroom = db.query(Classroom).filter(Classroom.name == "CS101 - Algorithms").first()
    if not classroom:
        classroom = Classroom(name="CS101 - Algorithms", subject="Computer Science", teacher_id=teacher.id)
        db.add(classroom)
        db.commit()
        db.refresh(classroom)

        # Add students
        s1 = Student(name="Ada Lovelace", roll_number="CS-001", classroom_id=classroom.id)
        s2 = Student(name="Grace Hopper", roll_number="CS-002", classroom_id=classroom.id)
        s3 = Student(name="Linus Torvalds", roll_number="CS-003", classroom_id=classroom.id)
        db.add_all([s1, s2, s3])
        db.commit()
        db.refresh(s1); db.refresh(s2); db.refresh(s3)

        # Add 2 lecture dates
        ld1 = LectureDate(date_str="2026-07-01", classroom_id=classroom.id)
        ld2 = LectureDate(date_str="2026-07-02", classroom_id=classroom.id)
        db.add_all([ld1, ld2])
        db.commit()
        db.refresh(ld1); db.refresh(ld2)

        # Add attendance: Ada present both (100%), Grace present 1 (50%), Linus absent both (0%)
        db.add_all([
            AttendanceRecord(student_id=s1.id, lecture_date_id=ld1.id, classroom_id=classroom.id, status="P"),
            AttendanceRecord(student_id=s1.id, lecture_date_id=ld2.id, classroom_id=classroom.id, status="P"),
            AttendanceRecord(student_id=s2.id, lecture_date_id=ld1.id, classroom_id=classroom.id, status="P"),
            AttendanceRecord(student_id=s2.id, lecture_date_id=ld2.id, classroom_id=classroom.id, status="A"),
            AttendanceRecord(student_id=s3.id, lecture_date_id=ld1.id, classroom_id=classroom.id, status="A"),
            AttendanceRecord(student_id=s3.id, lecture_date_id=ld2.id, classroom_id=classroom.id, status="A")
        ])
        db.commit()

    print("Generating Excel report...")
    excel_path = generate_class_excel(db, classroom.id)
    print(f"SUCCESS: Excel generated at -> {excel_path}")
    assert os.path.exists(excel_path), "Excel file was not created!"
except Exception as e:
    print(f"ERROR: {e}")
    raise e
finally:
    db.close()
