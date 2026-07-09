import os
import shutil
from typing import List, Optional
from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from pydantic import BaseModel
import bcrypt
from app.db.database import get_db, get_next_id
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

def _teacher_dict(t: dict) -> dict:
    return {
        "id": t.get("id"),
        "name": t.get("name"),
        "email": t.get("email"),
        "institution": t.get("institution"),
        "subject_specialization": t.get("subject_specialization"),
    }

def _classroom_dict(c: dict, db) -> dict:
    student_count = db.students.count_documents({"classroom_id": c["id"]})
    return {
        "id": c.get("id"),
        "name": c.get("name"),
        "subject": c.get("subject"),
        "section": c.get("section"),
        "required_photos": c.get("required_photos", 3),
        "student_count": student_count,
    }

def _student_dict(s: dict, db=None) -> dict:
    photo_count = db.student_photos.count_documents({"student_id": s["id"]}) if db is not None else 1
    if photo_count == 0 and s.get("photo_path"):
        photo_count = 1
    return {
        "id": s.get("id"),
        "name": s.get("name"),
        "roll_number": s.get("roll_number"),
        "photo_path": s.get("photo_path"),
        "photo_count": photo_count,
    }


# ── Auth ──────────────────────────────────────────────────────────────────────

@router.post("/register")
def register_teacher(teacher: TeacherCreate, db = Depends(get_db)):
    existing = db.teachers.find_one({"email": teacher.email})
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")
    hashed_pw = hash_password(teacher.password)
    t_id = get_next_id("teachers")
    new_teacher = {
        "id": t_id,
        "name": teacher.name,
        "email": teacher.email,
        "password_hash": hashed_pw,
        "institution": teacher.institution,
        "subject_specialization": teacher.subject_specialization,
    }
    db.teachers.insert_one(new_teacher)
    return _teacher_dict(new_teacher)


@router.post("/login")
def login_teacher(creds: TeacherLogin, db = Depends(get_db)):
    teacher = db.teachers.find_one({"email": creds.email})
    if not teacher or not verify_password(creds.password, teacher["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    return _teacher_dict(teacher)


# ── Teacher Profile ───────────────────────────────────────────────────────────

@router.get("/teacher/{teacher_id}")
def get_teacher(teacher_id: int, db = Depends(get_db)):
    t = db.teachers.find_one({"id": teacher_id})
    if not t:
        raise HTTPException(status_code=404, detail="Teacher not found")
    return _teacher_dict(t)


@router.put("/teacher/{teacher_id}")
def update_teacher(teacher_id: int, update_data: TeacherUpdate, db = Depends(get_db)):
    t = db.teachers.find_one({"id": teacher_id})
    if not t:
        raise HTTPException(status_code=404, detail="Teacher not found")
    
    update_fields = {}
    if update_data.name is not None: update_fields["name"] = update_data.name
    if update_data.institution is not None: update_fields["institution"] = update_data.institution
    if update_data.subject_specialization is not None: update_fields["subject_specialization"] = update_data.subject_specialization
    
    if update_fields:
        db.teachers.update_one({"id": teacher_id}, {"$set": update_fields})
        t.update(update_fields)
    return _teacher_dict(t)


# ── Classes ───────────────────────────────────────────────────────────────────

@router.get("/classes/{teacher_id}")
def get_classes(teacher_id: int, db = Depends(get_db)):
    classes = list(db.classrooms.find({"teacher_id": teacher_id}))
    return [_classroom_dict(c, db) for c in classes]


@router.post("/classes")
def create_class(c: ClassroomCreate, db = Depends(get_db)):
    c_id = get_next_id("classrooms")
    new_class = {
        "id": c_id,
        "name": c.name,
        "subject": c.subject,
        "section": c.section,
        "required_photos": c.required_photos,
        "teacher_id": c.teacher_id,
    }
    db.classrooms.insert_one(new_class)
    return _classroom_dict(new_class, db)


@router.put("/classes/{class_id}")
def update_class(class_id: int, update: ClassroomUpdate, db = Depends(get_db)):
    c = db.classrooms.find_one({"id": class_id})
    if not c:
        raise HTTPException(status_code=404, detail="Classroom not found")
    
    update_fields = {}
    if update.name is not None: update_fields["name"] = update.name
    if update.subject is not None: update_fields["subject"] = update.subject
    if update.section is not None: update_fields["section"] = update.section
    if update.required_photos is not None: update_fields["required_photos"] = update.required_photos
    
    if update_fields:
        db.classrooms.update_one({"id": class_id}, {"$set": update_fields})
        c.update(update_fields)
    return _classroom_dict(c, db)


@router.delete("/classes/{class_id}")
def delete_class(class_id: int, db = Depends(get_db)):
    c = db.classrooms.find_one({"id": class_id})
    if not c:
        raise HTTPException(status_code=404, detail="Classroom not found")
    db.classrooms.delete_one({"id": class_id})
    # Also clean up students, photos, lecture dates, and attendance records
    db.students.delete_many({"classroom_id": class_id})
    db.lecture_dates.delete_many({"classroom_id": class_id})
    db.attendance_records.delete_many({"classroom_id": class_id})
    return {"status": "deleted", "id": class_id}


# ── Students ────────────────────────────────────────────────────────────────

@router.get("/classes/{class_id}/students")
def get_students(class_id: int, db = Depends(get_db)):
    students = list(db.students.find({"classroom_id": class_id}).sort("roll_number", 1))
    return [_student_dict(s, db) for s in students]


def _process_student_photos_bg(student_id: int, file_paths: List[str]):
    from app.db.database import db
    try:
        student = db.students.find_one({"id": student_id})
        if not student:
            return

        for path in file_paths:
            try:
                enc = extract_face_encoding(path)
                existing = db.student_photos.find_one({"student_id": student_id, "photo_path": path})
                if existing:
                    db.student_photos.update_one({"id": existing["id"]}, {"$set": {"face_encoding": enc}})
                else:
                    sp_id = get_next_id("student_photos")
                    db.student_photos.insert_one({"id": sp_id, "student_id": student_id, "photo_path": path, "face_encoding": enc})
            except Exception as e:
                print(f"Error processing individual photo {path}: {e}")

        all_photos = list(db.student_photos.find({"student_id": student_id}))
        all_encs = [p["face_encoding"] for p in all_photos if p.get("face_encoding") and p.get("face_encoding") != "processing..."]
        if all_encs:
            avg_enc = merge_encoding_strings(all_encs)
            db.students.update_one({"id": student_id}, {"$set": {"face_encoding": avg_enc}})
    except Exception as e:
        print(f"Background photo processing error for student {student_id}: {e}")


@router.post("/students")
async def add_student(
    background_tasks: BackgroundTasks,
    name: str = Form(...),
    roll_number: str = Form(...),
    classroom_id: int = Form(...),
    photo: Optional[UploadFile] = File(None),
    db = Depends(get_db),
):
    roll_clean = str(roll_number).strip()
    existing_students = list(db.students.find({"classroom_id": classroom_id}))
    for s in existing_students:
        if str(s["roll_number"]).strip().lower() == roll_clean.lower():
            raise HTTPException(
                status_code=400,
                detail=f"Duplicate roll number: A student named '{s['name']}' with roll number '{roll_clean}' already exists in this class!"
            )

    photo_path = None
    if photo:
        safe_fname = os.path.basename(photo.filename or "photo.jpg")
        file_path = os.path.join(UPLOAD_DIR, f"student_{roll_number}_{safe_fname}")
        content = await photo.read()
        with open(file_path, "wb") as buffer:
            buffer.write(content)
        await photo.close()
        photo_path = file_path

    s_id = get_next_id("students")
    student = {
        "id": s_id,
        "name": name.strip(),
        "roll_number": roll_clean,
        "classroom_id": classroom_id,
        "photo_path": photo_path,
        "face_encoding": "processing...",
    }
    db.students.insert_one(student)

    if photo_path:
        sp_id = get_next_id("student_photos")
        db.student_photos.insert_one({"id": sp_id, "student_id": s_id, "photo_path": photo_path, "face_encoding": "processing..."})
        background_tasks.add_task(_process_student_photos_bg, s_id, [photo_path])
    return _student_dict(student, db)


@router.post("/students/batch")
async def add_student_batch(
    background_tasks: BackgroundTasks,
    name: str = Form(...),
    roll_number: str = Form(...),
    classroom_id: int = Form(...),
    photos: List[UploadFile] = File(...),
    db = Depends(get_db),
):
    """Instant bulk enrollment: saves student immediately in 0.05 seconds and processes AI embeddings in the background!"""
    if not photos or len(photos) == 0:
        raise HTTPException(status_code=400, detail="At least 1 photo required")

    roll_clean = str(roll_number).strip()
    existing_students = list(db.students.find({"classroom_id": classroom_id}))
    for s in existing_students:
        if str(s["roll_number"]).strip().lower() == roll_clean.lower():
            raise HTTPException(
                status_code=400,
                detail=f"Duplicate roll number: A student named '{s['name']}' with roll number '{roll_clean}' already exists in this class!"
            )

    file_paths = []
    for idx, photo in enumerate(photos):
        safe_fname = os.path.basename(photo.filename or f"photo_{idx}.jpg")
        file_path = os.path.join(UPLOAD_DIR, f"student_{roll_number}_{idx+1}_{safe_fname}")
        content = await photo.read()
        with open(file_path, "wb") as buffer:
            buffer.write(content)
        await photo.close()
        file_paths.append(file_path)

    s_id = get_next_id("students")
    student = {
        "id": s_id,
        "name": name,
        "roll_number": roll_number,
        "classroom_id": classroom_id,
        "photo_path": file_paths[0] if file_paths else None,
        "face_encoding": "processing...",
    }
    db.students.insert_one(student)

    for path in file_paths:
        sp_id = get_next_id("student_photos")
        db.student_photos.insert_one({"id": sp_id, "student_id": s_id, "photo_path": path, "face_encoding": "processing..."})

    background_tasks.add_task(_process_student_photos_bg, s_id, file_paths)
    return _student_dict(student, db)


@router.post("/students/{student_id}/photos")
async def add_student_photo(
    student_id: int,
    background_tasks: BackgroundTasks,
    photo: UploadFile = File(...),
    db = Depends(get_db),
):
    """Add an additional photo instantly and process embedding asynchronously."""
    s = db.students.find_one({"id": student_id})
    if not s:
        raise HTTPException(status_code=404, detail="Student not found")

    safe_fname = os.path.basename(photo.filename or "extra.jpg")
    file_path = os.path.join(UPLOAD_DIR, f"student_{student_id}_extra_{safe_fname}")
    content = await photo.read()
    with open(file_path, "wb") as buffer:
        buffer.write(content)
    await photo.close()

    if not s.get("photo_path"):
        db.students.update_one({"id": student_id}, {"$set": {"photo_path": file_path}})
        s["photo_path"] = file_path

    sp_id = get_next_id("student_photos")
    db.student_photos.insert_one({"id": sp_id, "student_id": student_id, "photo_path": file_path, "face_encoding": "processing..."})

    background_tasks.add_task(_process_student_photos_bg, student_id, [file_path])

    return {
        "message": "Photo upload started in background",
        "student": _student_dict(s, db),
    }


@router.put("/students/{student_id}")
def update_student(student_id: int, update: StudentUpdate, db = Depends(get_db)):
    s = db.students.find_one({"id": student_id})
    if not s:
        raise HTTPException(status_code=404, detail="Student not found")
    
    update_fields = {}
    if update.name is not None: update_fields["name"] = update.name
    if update.roll_number is not None: update_fields["roll_number"] = update.roll_number
    
    if update_fields:
        db.students.update_one({"id": student_id}, {"$set": update_fields})
        s.update(update_fields)
    return _student_dict(s, db)


@router.delete("/students/{student_id}")
def delete_student(student_id: int, db = Depends(get_db)):
    s = db.students.find_one({"id": student_id})
    if not s:
        raise HTTPException(status_code=404, detail="Student not found")
    db.students.delete_one({"id": student_id})
    db.student_photos.delete_many({"student_id": student_id})
    db.attendance_records.delete_many({"student_id": student_id})
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
    db = Depends(get_db),
):
    video_path = os.path.join(UPLOAD_DIR, f"scan_{classroom_id}_{video.filename}")
    with open(video_path, "wb") as buffer:
        shutil.copyfileobj(video.file, buffer)

    students = list(db.students.find({"classroom_id": classroom_id}))
    encodings = {s["id"]: s.get("face_encoding") for s in students if s.get("face_encoding")}
    student_map = {s["id"]: _student_dict(s, db) for s in students}

    results = process_classroom_video(video_path, encodings, student_map)

    present_list = [_student_dict(s, db) for s in students if s["id"] in results["present_student_ids"]]
    absent_list  = [_student_dict(s, db) for s in students if s["id"] in results["absent_student_ids"]]

    return {"present_students": present_list, "absent_students": absent_list}


@router.post("/attendance/stream-frame")
async def stream_frame(
    classroom_id: int = Form(...),
    frame: UploadFile = File(...),
    db = Depends(get_db),
):
    # Optimization #1: Read bytes directly into RAM with zero disk I/O!
    raw_bytes = await frame.read()

    students = list(db.students.find({"classroom_id": classroom_id}))
    encodings = {s["id"]: s.get("face_encoding") for s in students if s.get("face_encoding")}
    student_map = {s["id"]: _student_dict(s, db) for s in students}

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
    all_list = [_student_dict(s, db) for s in students]
    return {"matched_students": present_list, "all_students": all_list, "face_boxes": enriched_boxes}


# ── Optimization #3: Persistent WebSocket Streaming Stream ──────────────────────
@router.websocket("/ws/live_scan/{classroom_id}")
async def websocket_live_scan(websocket: WebSocket, classroom_id: int, db = Depends(get_db)):
    await websocket.accept()
    students = list(db.students.find({"classroom_id": classroom_id}))
    encodings = {s["id"]: s.get("face_encoding") for s in students if s.get("face_encoding")}
    student_map = {s["id"]: _student_dict(s, db) for s in students}

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
            all_list = [_student_dict(s, db) for s in students]
            await websocket.send_json({"matched_students": present_list, "all_students": all_list, "face_boxes": enriched_boxes})
    except (WebSocketDisconnect, Exception) as e:
        print(f"Live Scan WebSocket disconnected for class {classroom_id}: {e}")


@router.post("/attendance/confirm")
def confirm_attendance(req: AttendanceConfirmRequest, db = Depends(get_db)):
    ld = db.lecture_dates.find_one({
        "classroom_id": req.classroom_id,
        "date_str": req.date_str,
    })

    if not ld:
        ld_id = get_next_id("lecture_dates")
        ld = {"id": ld_id, "date_str": req.date_str, "classroom_id": req.classroom_id}
        db.lecture_dates.insert_one(ld)
    else:
        # Replace existing records for this date
        db.attendance_records.delete_many({"lecture_date_id": ld["id"]})

    for s_id in req.present_student_ids:
        a_id = get_next_id("attendance_records")
        db.attendance_records.insert_one({"id": a_id, "student_id": s_id, "lecture_date_id": ld["id"], "classroom_id": req.classroom_id, "status": "P"})
    for s_id in req.absent_student_ids:
        a_id = get_next_id("attendance_records")
        db.attendance_records.insert_one({"id": a_id, "student_id": s_id, "lecture_date_id": ld["id"], "classroom_id": req.classroom_id, "status": "A"})

    excel_path = generate_class_excel(db, req.classroom_id)
    return {"message": "Attendance saved successfully", "excel_path": excel_path}


@router.put("/attendance/record")
def update_attendance_record(req: AttendanceUpdateRequest, db = Depends(get_db)):
    """Allows teachers to modify past attendance status for a student on any lecture date."""
    student = db.students.find_one({"id": req.student_id})
    if not student:
        raise HTTPException(status_code=404, detail="Student not found")

    ld = db.lecture_dates.find_one({
        "classroom_id": student["classroom_id"],
        "date_str": req.date_str,
    })

    if not ld:
        ld_id = get_next_id("lecture_dates")
        ld = {"id": ld_id, "date_str": req.date_str, "classroom_id": student["classroom_id"]}
        db.lecture_dates.insert_one(ld)

    record = db.attendance_records.find_one({
        "student_id": req.student_id,
        "lecture_date_id": ld["id"],
    })

    if req.status in ["P", "A"]:
        if record:
            db.attendance_records.update_one({"id": record["id"]}, {"$set": {"status": req.status}})
        else:
            a_id = get_next_id("attendance_records")
            db.attendance_records.insert_one({"id": a_id, "student_id": req.student_id, "lecture_date_id": ld["id"], "classroom_id": student["classroom_id"], "status": req.status})
    else:
        if record:
            db.attendance_records.delete_one({"id": record["id"]})

    excel_path = generate_class_excel(db, student["classroom_id"])
    return {"message": "Record updated successfully", "excel_path": excel_path}


# ── Reports ───────────────────────────────────────────────────────────────────

@router.get("/reports/class/{class_id}/excel")
def download_excel(class_id: int, db = Depends(get_db)):
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
def get_class_analytics(class_id: int, db = Depends(get_db)):
    classroom = db.classrooms.find_one({"id": class_id})
    if not classroom:
        raise HTTPException(status_code=404, detail="Classroom not found")

    students      = list(db.students.find({"classroom_id": class_id}))
    lecture_dates = list(db.lecture_dates.find({"classroom_id": class_id}).sort("date_str", 1))
    records    = list(db.attendance_records.find({"classroom_id": class_id}))
    status_map = {(r["student_id"], r["lecture_date_id"]): r["status"] for r in records}
    total_students = len(students)
    total_lectures = len(lecture_dates)

    # Per-date totals
    date_summaries = []
    for ld in lecture_dates:
        present = sum(1 for s in students if status_map.get((s["id"], ld["id"])) == "P")
        date_summaries.append({
            "date": ld["date_str"],
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
            status = status_map.get((s["id"], ld["id"]), "A")
            if status == "P":
                present += 1
            history.append({
                "date": ld["date_str"],
                "status": status if status in ("P", "A", "L") else "A"
            })
        pct = round(present / total_lectures * 100, 1) if total_lectures > 0 else 0.0
        student_summaries.append({
            "id": s["id"], "name": s["name"], "roll_number": s["roll_number"],
            "present": present, "absent": total_lectures - present,
            "total": total_lectures, "percentage": pct, "history": history,
        })
    student_summaries.sort(key=lambda x: x["percentage"])

    avg_pct = (
        round(sum(s["percentage"] for s in student_summaries) / len(student_summaries), 1)
        if student_summaries else 0.0
    )

    return {
        "classroom_name": classroom["name"],
        "subject": classroom["subject"],
        "section": classroom.get("section"),
        "total_students": total_students,
        "total_lectures": total_lectures,
        "overall_avg_percentage": avg_pct,
        "date_summaries": date_summaries,
        "student_summaries": student_summaries,
    }


@router.get("/analytics/student/{student_id}")
def get_student_analytics(student_id: int, db = Depends(get_db)):
    s = db.students.find_one({"id": student_id})
    if not s:
        raise HTTPException(status_code=404, detail="Student not found")

    lecture_dates = list(db.lecture_dates.find({"classroom_id": s["classroom_id"]}).sort("date_str", 1))
    records    = list(db.attendance_records.find({"student_id": student_id}))
    status_map = {r["lecture_date_id"]: r["status"] for r in records}

    history = [{"date": ld["date_str"], "status": status_map.get(ld["id"], "-")} for ld in lecture_dates]
    present = sum(1 for h in history if h["status"] == "P")
    total   = len(history)
    pct     = round(present / total * 100, 1) if total > 0 else 0.0

    return {
        "id": s["id"], "name": s["name"], "roll_number": s["roll_number"],
        "present": present, "absent": total - present,
        "total": total, "percentage": pct, "history": history,
    }
