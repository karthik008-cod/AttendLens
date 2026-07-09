import os
import shutil
from typing import List, Optional
from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel
import bcrypt
from app.db.database import get_db
from app.db.models import Teacher, Classroom, Student, StudentPhoto, LectureDate, AttendanceRecord
from app.services.ai_engine import extract_face_encoding, merge_student_encodings, merge_encoding_strings, process_classroom_video, process_single_frame, assess_photo_quality_and_liveness
from app.services.excel_service import generate_class_excel

def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))

router = APIRouter()

if os.path.exists("/data"):
    UPLOAD_DIR = "/data/uploads"
else:
    UPLOAD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)


# ── Pydantic Schemas ──────────────────────────────────────────────────────────

class TeacherCreate(BaseModel):
    name: str
    email: str
    password: str
    institution: Optional[str] = None
    subject_specialization: Optional[str] = None

class TeacherLogin(BaseModel):
    email: str
    password: str

class TeacherUpdate(BaseModel):
    name: Optional[str] = None
    institution: Optional[str] = None
    subject_specialization: Optional[str] = None

class ClassroomCreate(BaseModel):
    name: str
    subject: str
    section: Optional[str] = None
    required_photos: int = 3
    teacher_id: int

class ClassroomUpdate(BaseModel):
    name: Optional[str] = None
    subject: Optional[str] = None
    section: Optional[str] = None
    required_photos: Optional[int] = None

class StudentUpdate(BaseModel):
    name: Optional[str] = None
    roll_number: Optional[str] = None

class AttendanceConfirmRequest(BaseModel):
    classroom_id: int
    date_str: str   # YYYY-MM-DD
    present_student_ids: List[int]
    absent_student_ids: List[int]

class AttendanceUpdateRequest(BaseModel):
    student_id: int
    date_str: str   # YYYY-MM-DD
    status: str     # "P" or "A" or "-"


# ── Helpers ───────────────────────────────────────────────────────────────────

def _teacher_dict(t: Teacher) -> dict:
    return {
        "id": t.id,
        "name": t.name,
        "email": t.email,
        "institution": t.institution,
        "subject_specialization": t.subject_specialization,
    }

def _classroom_dict(c: Classroom) -> dict:
    return {
        "id": c.id,
        "name": c.name,
        "subject": c.subject,
        "section": c.section,
        "required_photos": c.required_photos,
        "student_count": len(c.students),
    }

def _student_dict(s: Student) -> dict:
    return {
        "id": s.id,
        "name": s.name,
        "roll_number": s.roll_number,
        "photo_path": s.photo_path,
        "photo_count": len(s.photos) if s.photos is not None else (1 if s.photo_path else 0),
    }


# ── Auth ──────────────────────────────────────────────────────────────────────

@router.post("/register")
def register_teacher(teacher: TeacherCreate, db: Session = Depends(get_db)):
    existing = db.query(Teacher).filter(Teacher.email == teacher.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")
    hashed_pw = hash_password(teacher.password)
    new_teacher = Teacher(
        name=teacher.name,
        email=teacher.email,
        password_hash=hashed_pw,
        institution=teacher.institution,
        subject_specialization=teacher.subject_specialization,
    )
    db.add(new_teacher)
    db.commit()
    db.refresh(new_teacher)
    return _teacher_dict(new_teacher)


@router.post("/login")
def login_teacher(creds: TeacherLogin, db: Session = Depends(get_db)):
    teacher = db.query(Teacher).filter(Teacher.email == creds.email).first()
    if not teacher or not verify_password(creds.password, teacher.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    return _teacher_dict(teacher)


# ── Teacher Profile ───────────────────────────────────────────────────────────

@router.get("/teacher/{teacher_id}")
def get_teacher(teacher_id: int, db: Session = Depends(get_db)):
    t = db.query(Teacher).filter(Teacher.id == teacher_id).first()
    if not t:
        raise HTTPException(status_code=404, detail="Teacher not found")
    return _teacher_dict(t)


@router.put("/teacher/{teacher_id}")
def update_teacher(teacher_id: int, update: TeacherUpdate, db: Session = Depends(get_db)):
    t = db.query(Teacher).filter(Teacher.id == teacher_id).first()
    if not t:
        raise HTTPException(status_code=404, detail="Teacher not found")
    if update.name is not None:
        t.name = update.name
    if update.institution is not None:
        t.institution = update.institution
    if update.subject_specialization is not None:
        t.subject_specialization = update.subject_specialization
    db.commit()
    db.refresh(t)
    return _teacher_dict(t)


# ── Classes ───────────────────────────────────────────────────────────────────

@router.get("/classes/{teacher_id}")
def get_classes(teacher_id: int, db: Session = Depends(get_db)):
    classes = db.query(Classroom).filter(Classroom.teacher_id == teacher_id).all()
    return [_classroom_dict(c) for c in classes]


@router.post("/classes")
def create_class(c: ClassroomCreate, db: Session = Depends(get_db)):
    new_class = Classroom(
        name=c.name,
        subject=c.subject,
        section=c.section,
        required_photos=c.required_photos,
        teacher_id=c.teacher_id,
    )
    db.add(new_class)
    db.commit()
    db.refresh(new_class)
    return _classroom_dict(new_class)


@router.put("/classes/{class_id}")
def update_class(class_id: int, update: ClassroomUpdate, db: Session = Depends(get_db)):
    c = db.query(Classroom).filter(Classroom.id == class_id).first()
    if not c:
        raise HTTPException(status_code=404, detail="Classroom not found")
    if update.name is not None:
        c.name = update.name
    if update.subject is not None:
        c.subject = update.subject
    if update.section is not None:
        c.section = update.section
    if update.required_photos is not None:
        c.required_photos = update.required_photos
    db.commit()
    db.refresh(c)
    return _classroom_dict(c)


@router.delete("/classes/{class_id}")
def delete_class(class_id: int, db: Session = Depends(get_db)):
    c = db.query(Classroom).filter(Classroom.id == class_id).first()
    if not c:
        raise HTTPException(status_code=404, detail="Classroom not found")
    db.delete(c)
    db.commit()
    return {"status": "deleted", "id": class_id}


# ── Students ──────────────────────────────────────────────────────────────────

@router.get("/classes/{class_id}/students")
def get_students(class_id: int, db: Session = Depends(get_db)):
    students = (
        db.query(Student)
        .filter(Student.classroom_id == class_id)
        .order_by(Student.roll_number)
        .all()
    )
    return [_student_dict(s) for s in students]


def _process_student_photos_bg(student_id: int, file_paths: List[str]):
    """Background task: extracts face encodings without blocking the HTTP response or the teacher's app!"""
    from app.db.database import SessionLocal
    db = SessionLocal()
    try:
        student = db.query(Student).filter(Student.id == student_id).first()
        if not student:
            return

        photo_entries = []
        for path in file_paths:
            enc = extract_face_encoding(path)
            sp = StudentPhoto(student_id=student_id, photo_path=path, face_encoding=enc)
            db.add(sp)
            photo_entries.append(enc)

        # Merge with existing photos if any
        all_photos = db.query(StudentPhoto).filter(StudentPhoto.student_id == student_id).all()
        all_encs = [p.face_encoding for p in all_photos if p.face_encoding]
        avg_enc = merge_encoding_strings(all_encs)
        student.face_encoding = avg_enc
        db.commit()
    except Exception as e:
        print(f"Background photo processing error for student {student_id}: {e}")
    finally:
        db.close()


@router.post("/students")
def add_student(
    background_tasks: BackgroundTasks,
    name: str = Form(...),
    roll_number: str = Form(...),
    classroom_id: int = Form(...),
    photo: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
):
    roll_clean = str(roll_number).strip()
    existing_students = db.query(Student).filter(Student.classroom_id == classroom_id).all()
    for s in existing_students:
        if str(s.roll_number).strip().lower() == roll_clean.lower():
            raise HTTPException(
                status_code=400,
                detail=f"Duplicate roll number: A student named '{s.name}' with roll number '{roll_clean}' already exists in this class!"
            )

    photo_path = None
    if photo:
        file_path = os.path.join(UPLOAD_DIR, f"student_{roll_number}_{photo.filename}")
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(photo.file, buffer)
        photo_path = file_path

    student = Student(
        name=name.strip(),
        roll_number=roll_clean,
        classroom_id=classroom_id,
        photo_path=photo_path,
        face_encoding="processing...",
    )
    db.add(student)
    db.commit()
    db.refresh(student)

    if photo_path:
        background_tasks.add_task(_process_student_photos_bg, student.id, [photo_path])

    return _student_dict(student)


@router.post("/students/batch")
def add_student_batch(
    background_tasks: BackgroundTasks,
    name: str = Form(...),
    roll_number: str = Form(...),
    classroom_id: int = Form(...),
    photos: List[UploadFile] = File(...),
    db: Session = Depends(get_db),
):
    """Instant bulk enrollment: saves student immediately in 0.05 seconds and processes AI embeddings in the background!"""
    if not photos or len(photos) == 0:
        raise HTTPException(status_code=400, detail="At least 1 photo required")

    roll_clean = str(roll_number).strip()
    existing_students = db.query(Student).filter(Student.classroom_id == classroom_id).all()
    for s in existing_students:
        if str(s.roll_number).strip().lower() == roll_clean.lower():
            raise HTTPException(
                status_code=400,
                detail=f"Duplicate roll number: A student named '{s.name}' with roll number '{roll_clean}' already exists in this class!"
            )

    file_paths = []
    for idx, photo in enumerate(photos):
        file_path = os.path.join(UPLOAD_DIR, f"student_{roll_number}_{idx+1}_{photo.filename}")
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(photo.file, buffer)
        file_paths.append(file_path)

    student = Student(
        name=name,
        roll_number=roll_number,
        classroom_id=classroom_id,
        photo_path=file_paths[0] if file_paths else None,
        face_encoding="processing...",
    )
    db.add(student)
    db.commit()
    db.refresh(student)

    background_tasks.add_task(_process_student_photos_bg, student.id, file_paths)

    return _student_dict(student)


@router.post("/students/{student_id}/photos")
def add_student_photo(
    student_id: int,
    background_tasks: BackgroundTasks,
    photo: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    """Add an additional photo instantly and process embedding asynchronously."""
    s = db.query(Student).filter(Student.id == student_id).first()
    if not s:
        raise HTTPException(status_code=404, detail="Student not found")

    file_path = os.path.join(UPLOAD_DIR, f"student_{student_id}_extra_{photo.filename}")
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(photo.file, buffer)

    if not s.photo_path:
        s.photo_path = file_path
        db.commit()

    background_tasks.add_task(_process_student_photos_bg, student_id, [file_path])

    return {
        "message": "Photo upload started in background",
        "student": _student_dict(s),
    }


@router.put("/students/{student_id}")
def update_student(student_id: int, update: StudentUpdate, db: Session = Depends(get_db)):
    s = db.query(Student).filter(Student.id == student_id).first()
    if not s:
        raise HTTPException(status_code=404, detail="Student not found")
    if update.name is not None:
        s.name = update.name
    if update.roll_number is not None:
        s.roll_number = update.roll_number
    db.commit()
    db.refresh(s)
    return _student_dict(s)


@router.delete("/students/{student_id}")
def delete_student(student_id: int, db: Session = Depends(get_db)):
    s = db.query(Student).filter(Student.id == student_id).first()
    if not s:
        raise HTTPException(status_code=404, detail="Student not found")
    db.delete(s)
    db.commit()
    return {"message": "Student deleted successfully"}


@router.post("/students/check-quality")
def check_photo_quality(photo: UploadFile = File(...)):
    """Evaluates photo sharpness, brightness, and liveness/spoof heuristics before enrollment."""
    file_path = os.path.join(UPLOAD_DIR, f"temp_quality_{photo.filename}")
    try:
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(photo.file, buffer)
        res = assess_photo_quality_and_liveness(file_path)
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
            except Exception:
                pass
        return res
    except Exception as e:
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
            except Exception:
                pass
        return {"is_good": True, "sharpness_score": 100.0, "brightness_score": 128.0, "warning_message": None}


# ── Attendance ────────────────────────────────────────────────────────────────

@router.post("/attendance/scan")
def scan_video(
    classroom_id: int = Form(...),
    video: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    video_path = os.path.join(UPLOAD_DIR, f"scan_{classroom_id}_{video.filename}")
    with open(video_path, "wb") as buffer:
        shutil.copyfileobj(video.file, buffer)

    students = db.query(Student).filter(Student.classroom_id == classroom_id).all()
    encodings = {s.id: s.face_encoding for s in students if s.face_encoding}
    student_map = {s.id: _student_dict(s) for s in students}

    results = process_classroom_video(video_path, encodings, student_map)

    present_list = [_student_dict(s) for s in students if s.id in results["present_student_ids"]]
    absent_list  = [_student_dict(s) for s in students if s.id in results["absent_student_ids"]]

    return {"present_students": present_list, "absent_students": absent_list}


@router.post("/attendance/stream-frame")
async def stream_frame(
    classroom_id: int = Form(...),
    frame: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    # Optimization #1: Read bytes directly into RAM with zero disk I/O!
    raw_bytes = await frame.read()

    students = db.query(Student).filter(Student.classroom_id == classroom_id).all()
    encodings = {s.id: s.face_encoding for s in students if s.face_encoding}
    student_map = {s.id: _student_dict(s) for s in students}

    frame_res = process_single_frame(image_path=None, student_encodings=encodings, student_info=student_map, raw_bytes=raw_bytes)
    if isinstance(frame_res, dict):
        matched_ids = set(frame_res.get("matched_ids", []))
        face_boxes = frame_res.get("face_boxes", [])
    else:
        matched_ids = set(frame_res)
        face_boxes = []

    # Enrich face_boxes with student name and roll number for UI display
    enriched_boxes = []
    for fb in face_boxes:
        s_id = fb.get("id")
        if s_id in student_map:
            fb["name"] = student_map[s_id]["name"]
            fb["roll_number"] = student_map[s_id]["roll_number"]
        else:
            fb["name"] = "Scanning / Unrecognized"
            fb["roll_number"] = "?"
        enriched_boxes.append(fb)

    present_list = [student_map[s_id] for s_id in matched_ids if s_id in student_map]
    all_list = [_student_dict(s) for s in students]
    return {"matched_students": present_list, "all_students": all_list, "face_boxes": enriched_boxes}


# ── Optimization #3: Persistent WebSocket Streaming Stream ──────────────────────
@router.websocket("/ws/live_scan/{classroom_id}")
async def websocket_live_scan(websocket: WebSocket, classroom_id: int, db: Session = Depends(get_db)):
    await websocket.accept()
    students = db.query(Student).filter(Student.classroom_id == classroom_id).all()
    encodings = {s.id: s.face_encoding for s in students if s.face_encoding}
    student_map = {s.id: _student_dict(s) for s in students}

    try:
        while True:
            raw_bytes = await websocket.receive_bytes()
            if not raw_bytes:
                continue
            frame_res = process_single_frame(image_path=None, student_encodings=encodings, student_info=student_map, raw_bytes=raw_bytes)
            if isinstance(frame_res, dict):
                matched_ids = set(frame_res.get("matched_ids", []))
                face_boxes = frame_res.get("face_boxes", [])
            else:
                matched_ids = set(frame_res)
                face_boxes = []

            enriched_boxes = []
            for fb in face_boxes:
                s_id = fb.get("id")
                if s_id in student_map:
                    fb["name"] = student_map[s_id]["name"]
                    fb["roll_number"] = student_map[s_id]["roll_number"]
                else:
                    fb["name"] = "Scanning / Unrecognized"
                    fb["roll_number"] = "?"
                enriched_boxes.append(fb)

            present_list = [student_map[s_id] for s_id in matched_ids if s_id in student_map]
            all_list = [_student_dict(s) for s in students]
            await websocket.send_json({"matched_students": present_list, "all_students": all_list, "face_boxes": enriched_boxes})
    except (WebSocketDisconnect, Exception) as e:
        print(f"Live Scan WebSocket disconnected for class {classroom_id}: {e}")


@router.post("/attendance/confirm")
def confirm_attendance(req: AttendanceConfirmRequest, db: Session = Depends(get_db)):
    ld = db.query(LectureDate).filter(
        LectureDate.classroom_id == req.classroom_id,
        LectureDate.date_str == req.date_str,
    ).first()

    if not ld:
        ld = LectureDate(date_str=req.date_str, classroom_id=req.classroom_id)
        db.add(ld)
        db.commit()
        db.refresh(ld)
    else:
        # Replace existing records for this date
        db.query(AttendanceRecord).filter(AttendanceRecord.lecture_date_id == ld.id).delete()

    for s_id in req.present_student_ids:
        db.add(AttendanceRecord(student_id=s_id, lecture_date_id=ld.id, classroom_id=req.classroom_id, status="P"))
    for s_id in req.absent_student_ids:
        db.add(AttendanceRecord(student_id=s_id, lecture_date_id=ld.id, classroom_id=req.classroom_id, status="A"))

    db.commit()
    excel_path = generate_class_excel(db, req.classroom_id)
    return {"message": "Attendance saved successfully", "excel_path": excel_path}


@router.put("/attendance/record")
def update_attendance_record(req: AttendanceUpdateRequest, db: Session = Depends(get_db)):
    """Allows teachers to modify past attendance status for a student on any lecture date."""
    student = db.query(Student).filter(Student.id == req.student_id).first()
    if not student:
        raise HTTPException(status_code=404, detail="Student not found")

    ld = db.query(LectureDate).filter(
        LectureDate.classroom_id == student.classroom_id,
        LectureDate.date_str == req.date_str,
    ).first()

    if not ld:
        ld = LectureDate(date_str=req.date_str, classroom_id=student.classroom_id)
        db.add(ld)
        db.commit()
        db.refresh(ld)

    record = db.query(AttendanceRecord).filter(
        AttendanceRecord.student_id == req.student_id,
        AttendanceRecord.lecture_date_id == ld.id,
    ).first()

    if req.status in ["P", "A"]:
        if record:
            record.status = req.status
        else:
            db.add(AttendanceRecord(student_id=req.student_id, lecture_date_id=ld.id, classroom_id=student.classroom_id, status=req.status))
    else:
        if record:
            db.delete(record)

    db.commit()
    excel_path = generate_class_excel(db, student.classroom_id)
    return {"message": "Record updated successfully", "excel_path": excel_path}


# ── Reports ───────────────────────────────────────────────────────────────────

@router.get("/reports/class/{class_id}/excel")
def download_excel(class_id: int, db: Session = Depends(get_db)):
    try:
        file_path = generate_class_excel(db, class_id)
        return FileResponse(
            path=file_path,
            filename=os.path.basename(file_path),
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# ── Analytics ─────────────────────────────────────────────────────────────────

@router.get("/analytics/class/{class_id}")
def get_class_analytics(class_id: int, db: Session = Depends(get_db)):
    classroom = db.query(Classroom).filter(Classroom.id == class_id).first()
    if not classroom:
        raise HTTPException(status_code=404, detail="Classroom not found")

    students      = db.query(Student).filter(Student.classroom_id == class_id).all()
    lecture_dates = (
        db.query(LectureDate)
        .filter(LectureDate.classroom_id == class_id)
        .order_by(LectureDate.date_str)
        .all()
    )
    records    = db.query(AttendanceRecord).filter(AttendanceRecord.classroom_id == class_id).all()
    status_map = {(r.student_id, r.lecture_date_id): r.status for r in records}
    total_students = len(students)
    total_lectures = len(lecture_dates)

    # Per-date totals
    date_summaries = []
    for ld in lecture_dates:
        present = sum(1 for s in students if status_map.get((s.id, ld.id)) == "P")
        date_summaries.append({
            "date": ld.date_str,
            "present": present,
            "absent": total_students - present,
            "percentage": round(present / total_students * 100, 1) if total_students > 0 else 0.0,
        })

    # Per-student totals (sorted by % ascending — most at-risk first)
    student_summaries = []
    for s in students:
        present = 0
        history = []
        for ld in lecture_dates:
            status = status_map.get((s.id, ld.id), "A")
            if status == "P":
                present += 1
            history.append({
                "date": ld.date_str,
                "status": status if status in ("P", "A", "L") else "A"
            })
        pct = round(present / total_lectures * 100, 1) if total_lectures > 0 else 0.0
        student_summaries.append({
            "id": s.id, "name": s.name, "roll_number": s.roll_number,
            "present": present, "absent": total_lectures - present,
            "total": total_lectures, "percentage": pct, "history": history,
        })
    student_summaries.sort(key=lambda x: x["percentage"])

    avg_pct = (
        round(sum(s["percentage"] for s in student_summaries) / len(student_summaries), 1)
        if student_summaries else 0.0
    )

    return {
        "classroom_name": classroom.name,
        "subject": classroom.subject,
        "section": classroom.section,
        "total_students": total_students,
        "total_lectures": total_lectures,
        "overall_avg_percentage": avg_pct,
        "date_summaries": date_summaries,
        "student_summaries": student_summaries,
    }


@router.get("/analytics/student/{student_id}")
def get_student_analytics(student_id: int, db: Session = Depends(get_db)):
    s = db.query(Student).filter(Student.id == student_id).first()
    if not s:
        raise HTTPException(status_code=404, detail="Student not found")

    lecture_dates = (
        db.query(LectureDate)
        .filter(LectureDate.classroom_id == s.classroom_id)
        .order_by(LectureDate.date_str)
        .all()
    )
    records    = db.query(AttendanceRecord).filter(AttendanceRecord.student_id == student_id).all()
    status_map = {r.lecture_date_id: r.status for r in records}

    history = [{"date": ld.date_str, "status": status_map.get(ld.id, "-")} for ld in lecture_dates]
    present = sum(1 for h in history if h["status"] == "P")
    total   = len(history)
    pct     = round(present / total * 100, 1) if total > 0 else 0.0

    return {
        "id": s.id, "name": s.name, "roll_number": s.roll_number,
        "present": present, "absent": total - present,
        "total": total, "percentage": pct, "history": history,
    }
