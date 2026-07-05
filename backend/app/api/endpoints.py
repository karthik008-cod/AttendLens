import os
import shutil
from typing import List, Optional
from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel
from app.db.database import get_db
from app.db.models import Teacher, Classroom, Student, LectureDate, AttendanceRecord
from app.services.ai_engine import extract_face_encoding, process_classroom_video
from app.services.excel_service import generate_class_excel

router = APIRouter()

UPLOAD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

class TeacherCreate(BaseModel):
    name: str
    email: str
    password: str

class ClassroomCreate(BaseModel):
    name: str
    subject: str
    teacher_id: int

class AttendanceConfirmRequest(BaseModel):
    classroom_id: int
    date_str: str  # YYYY-MM-DD
    present_student_ids: List[int]
    absent_student_ids: List[int]

@router.post("/register")
def register_teacher(teacher: TeacherCreate, db: Session = Depends(get_db)):
    existing = db.query(Teacher).filter(Teacher.email == teacher.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")
    new_teacher = Teacher(name=teacher.name, email=teacher.email, password_hash=teacher.password)
    db.add(new_teacher)
    db.commit()
    db.refresh(new_teacher)
    return {"id": new_teacher.id, "name": new_teacher.name, "email": new_teacher.email}

@router.get("/classes/{teacher_id}")
def get_classes(teacher_id: int, db: Session = Depends(get_db)):
    classes = db.query(Classroom).filter(Classroom.teacher_id == teacher_id).all()
    return [{"id": c.id, "name": c.name, "subject": c.subject, "student_count": len(c.students)} for c in classes]

@router.post("/classes")
def create_class(c: ClassroomCreate, db: Session = Depends(get_db)):
    new_class = Classroom(name=c.name, subject=c.subject, teacher_id=c.teacher_id)
    db.add(new_class)
    db.commit()
    db.refresh(new_class)
    return {"id": new_class.id, "name": new_class.name, "subject": new_class.subject}

@router.get("/classes/{class_id}/students")
def get_students(class_id: int, db: Session = Depends(get_db)):
    students = db.query(Student).filter(Student.classroom_id == class_id).order_by(Student.roll_number).all()
    return [{"id": s.id, "name": s.name, "roll_number": s.roll_number, "photo_path": s.photo_path} for s in students]

@router.post("/students")
def add_student(
    name: str = Form(...),
    roll_number: str = Form(...),
    classroom_id: int = Form(...),
    photo: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db)
):
    photo_path = None
    face_enc = None
    
    if photo:
        file_path = os.path.join(UPLOAD_DIR, f"student_{roll_number}_{photo.filename}")
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(photo.file, buffer)
        photo_path = file_path
        face_enc = extract_face_encoding(file_path)
        
    student = Student(
        name=name,
        roll_number=roll_number,
        classroom_id=classroom_id,
        photo_path=photo_path,
        face_encoding=face_enc
    )
    db.add(student)
    db.commit()
    db.refresh(student)
    return {"id": student.id, "name": student.name, "roll_number": student.roll_number}

@router.post("/attendance/scan")
def scan_video(
    classroom_id: int = Form(...),
    video: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    video_path = os.path.join(UPLOAD_DIR, f"scan_{classroom_id}_{video.filename}")
    with open(video_path, "wb") as buffer:
        shutil.copyfileobj(video.file, buffer)
        
    students = db.query(Student).filter(Student.classroom_id == classroom_id).all()
    encodings = {s.id: s.face_encoding for s in students if s.face_encoding}
    
    results = process_classroom_video(video_path, encodings)
    
    present_list = [{"id": s.id, "name": s.name, "roll_number": s.roll_number} for s in students if s.id in results["present_student_ids"]]
    absent_list = [{"id": s.id, "name": s.name, "roll_number": s.roll_number} for s in students if s.id in results["absent_student_ids"]]
    
    return {"present_students": present_list, "absent_students": absent_list}

@router.post("/attendance/confirm")
def confirm_attendance(req: AttendanceConfirmRequest, db: Session = Depends(get_db)):
    ld = db.query(LectureDate).filter(LectureDate.classroom_id == req.classroom_id, LectureDate.date_str == req.date_str).first()
    if not ld:
        ld = LectureDate(date_str=req.date_str, classroom_id=req.classroom_id)
        db.add(ld)
        db.commit()
        db.refresh(ld)
    else:
        db.query(AttendanceRecord).filter(AttendanceRecord.lecture_date_id == ld.id).delete()
        
    for s_id in req.present_student_ids:
        db.add(AttendanceRecord(student_id=s_id, lecture_date_id=ld.id, classroom_id=req.classroom_id, status="P"))
    for s_id in req.absent_student_ids:
        db.add(AttendanceRecord(student_id=s_id, lecture_date_id=ld.id, classroom_id=req.classroom_id, status="A"))
        
    db.commit()
    excel_path = generate_class_excel(db, req.classroom_id)
    return {"message": "Attendance saved successfully", "excel_path": excel_path}

@router.get("/reports/class/{class_id}/excel")
def download_excel(class_id: int, db: Session = Depends(get_db)):
    try:
        file_path = generate_class_excel(db, class_id)
        return FileResponse(
            path=file_path,
            filename=os.path.basename(file_path),
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
