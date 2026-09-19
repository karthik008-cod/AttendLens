"""
AttendLens OMR API Endpoints
============================
Handles OMR exam creation, answer key configuration (via photo or manual radio grid),
single & continuous scanning, real-time CTT psychometrics, and Excel/PDF export.
"""

import os
from typing import List, Optional, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel

from app.db.database import get_db, get_next_id
from app.db.omr_models import OMRExam, OMRSubmission
from app.services.omr_engine import process_omr_sheet, extract_key_from_photo
from app.services.omr_analytics import compute_student_score, compute_exam_analytics
from app.services.omr_export_service import generate_omr_excel, generate_omr_pdf
from app.services.omr_sheet_generator import generate_omr_sheet_pdf, generate_omr_for_exam

router = APIRouter(prefix="/omr", tags=["OMR Examination"])

# ── Pydantic Schemas ──────────────────────────────────────────────────────────

class SectionConfig(BaseModel):
    section_id: int
    subject_name: str
    start_q: int
    end_q: int
    num_questions: int
    marks_correct: float = 1.0
    marks_wrong: float = 0.0

class ExamCreateRequest(BaseModel):
    teacher_id: int
    title: str
    exam_date: Optional[str] = None
    total_questions: int = 180
    sections: List[SectionConfig]
    answer_key: Optional[Dict[str, int]] = {}

class KeyUpdateRequest(BaseModel):
    answer_key: Dict[str, int]

# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/exams")
def create_exam(req: ExamCreateRequest, db=Depends(get_db)):
    """Creates a new OMR Exam with sections, question ranges, and marking schemes."""
    exam_id = get_next_id(OMRExam.collection)

    # Compute total max marks
    total_max = 0.0
    for sec in req.sections:
        total_max += (sec.num_questions * sec.marks_correct)

    doc = {
        "id": exam_id,
        "teacher_id": req.teacher_id,
        "title": req.title,
        "exam_date": req.exam_date or "",
        "total_questions": req.total_questions,
        "total_max_marks": round(total_max, 2),
        "sections": [s.model_dump() for s in req.sections],
        "answer_key": req.answer_key or {}
    }
    db[OMRExam.collection].insert_one(doc)
    doc.pop("_id", None)
    return {"success": True, "exam": doc}

@router.get("/exams")
def list_exams(teacher_id: int = Query(...), db=Depends(get_db)):
    """Lists all OMR exams created by a teacher with candidate counts."""
    cursor = db[OMRExam.collection].find({"teacher_id": teacher_id}).sort("id", -1)
    exams = []
    for doc in cursor:
        doc.pop("_id", None)
        sub_count = db[OMRSubmission.collection].count_documents({"exam_id": doc["id"]})
        doc["submission_count"] = sub_count
        exams.append(doc)
    return exams

@router.get("/exams/{exam_id}")
def get_exam(exam_id: int, db=Depends(get_db)):
    """Retrieves an OMR exam's details, sections, and answer key."""
    exam = db[OMRExam.collection].find_one({"id": exam_id})
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    exam.pop("_id", None)
    sub_count = db[OMRSubmission.collection].count_documents({"exam_id": exam_id})
    exam["submission_count"] = sub_count
    return exam

@router.put("/exams/{exam_id}/key")
def update_answer_key(exam_id: int, req: KeyUpdateRequest, db=Depends(get_db)):
    """Updates the answer key (e.g. from manual radio buttons selection)."""
    res = db[OMRExam.collection].update_one(
        {"id": exam_id},
        {"$set": {"answer_key": req.answer_key}}
    )
    if res.matched_count == 0:
        raise HTTPException(status_code=404, detail="Exam not found")
    return {"success": True, "saved_key_count": len(req.answer_key)}

@router.post("/exams/{exam_id}/key-from-photo")
async def extract_key_photo(
    exam_id: int,
    file: UploadFile = File(...),
    db=Depends(get_db)
):
    """Scans a teacher's Key OMR sheet image and updates the exam answer key."""
    exam = db[OMRExam.collection].find_one({"id": exam_id})
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")

    content = await file.read()
    total_q = exam.get("total_questions", 180)
    key_res = extract_key_from_photo(content, total_questions=total_q)

    if not key_res.get("success"):
        raise HTTPException(status_code=400, detail=key_res.get("error", "Key extraction failed"))

    # Update in DB
    extracted_key = key_res["answer_key"]
    db[OMRExam.collection].update_one(
        {"id": exam_id},
        {"$set": {"answer_key": extracted_key}}
    )

    return {
        "success": True,
        "aligned": key_res.get("aligned", False),
        "total_extracted": len(extracted_key),
        "missing_keys": key_res.get("missing_keys", []),
        "multi_keys": key_res.get("multi_keys", []),
        "answer_key": extracted_key
    }

@router.post("/exams/{exam_id}/scan")
async def scan_single_sheet(
    exam_id: int,
    file: UploadFile = File(...),
    student_hall_ticket: Optional[str] = Form(None),
    student_name: Optional[str] = Form(None),
    db=Depends(get_db)
):
    """
    Processes a single student's OMR sheet.
    Evaluates against the exam's answer key and returns an instant score card.
    Also saves submission to DB.
    """
    exam = db[OMRExam.collection].find_one({"id": exam_id})
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")

    content = await file.read()
    total_q = exam.get("total_questions", 180)
    omr_res = process_omr_sheet(content, total_questions=total_q)

    if not omr_res.get("success"):
        raise HTTPException(status_code=400, detail=omr_res.get("error", "OMR detection failed"))

    answers = omr_res["answers"]
    answer_key = exam.get("answer_key", {})
    sections = exam.get("sections", [])

    # Evaluate score
    evaluation = compute_student_score(answers, answer_key, sections, total_q)

    # Determine student identifier
    sub_id = get_next_id(OMRSubmission.collection)
    hall_ticket = student_hall_ticket or f"HT_{1000 + sub_id}"
    name = student_name or f"Candidate {sub_id}"

    # Save submission
    sub_doc = {
        "id": sub_id,
        "exam_id": exam_id,
        "student_hall_ticket": hall_ticket,
        "student_name": name,
        "answers": answers,
        "evaluation": evaluation
    }
    db[OMRSubmission.collection].insert_one(sub_doc)
    sub_doc.pop("_id", None)

    return {
        "success": True,
        "aligned": omr_res.get("aligned", False),
        "submission_id": sub_id,
        "student_hall_ticket": hall_ticket,
        "student_name": name,
        "evaluation": evaluation,
        "answers": answers,
        "marked_counts": omr_res.get("marked_counts", {})
    }

@router.post("/exams/{exam_id}/bulk-scan")
async def bulk_scan_sheets(
    exam_id: int,
    files: List[UploadFile] = File(...),
    db=Depends(get_db)
):
    """Processes multiple OMR sheets for continuous scanning batch sync."""
    exam = db[OMRExam.collection].find_one({"id": exam_id})
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")

    total_q = exam.get("total_questions", 180)
    answer_key = exam.get("answer_key", {})
    sections = exam.get("sections", [])

    results = []
    for file in files:
        try:
            content = await file.read()
            omr_res = process_omr_sheet(content, total_questions=total_q)
            if not omr_res.get("success"):
                continue

            answers = omr_res["answers"]
            evaluation = compute_student_score(answers, answer_key, sections, total_q)
            sub_id = get_next_id(OMRSubmission.collection)
            hall_ticket = f"HT_{1000 + sub_id}"
            name = f"Candidate {sub_id}"

            sub_doc = {
                "id": sub_id,
                "exam_id": exam_id,
                "student_hall_ticket": hall_ticket,
                "student_name": name,
                "answers": answers,
                "evaluation": evaluation
            }
            db[OMRSubmission.collection].insert_one(sub_doc)
            results.append({
                "submission_id": sub_id,
                "student_hall_ticket": hall_ticket,
                "total_score": evaluation["total_score"],
                "percentage": evaluation["percentage"]
            })
        except Exception as e:
            continue

    return {"success": True, "processed_count": len(results), "results": results}

@router.get("/exams/{exam_id}/analytics")
def get_analytics(exam_id: int, db=Depends(get_db)):
    """Computes and returns full psychometric CTT, student ranking, and batch analytics."""
    exam = db[OMRExam.collection].find_one({"id": exam_id})
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    exam.pop("_id", None)

    submissions = list(db[OMRSubmission.collection].find({"exam_id": exam_id}))
    for s in submissions:
        s.pop("_id", None)

    analytics = compute_exam_analytics(exam, submissions)
    return {"success": True, "exam": exam, "analytics": analytics}

@router.get("/exams/{exam_id}/export/excel")
def export_excel(exam_id: int, db=Depends(get_db)):
    """Generates and downloads the comprehensive 5-sheet Excel report."""
    exam = db[OMRExam.collection].find_one({"id": exam_id})
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    exam.pop("_id", None)

    submissions = list(db[OMRSubmission.collection].find({"exam_id": exam_id}))
    for s in submissions:
        s.pop("_id", None)

    analytics = compute_exam_analytics(exam, submissions)
    filepath = generate_omr_excel(exam, analytics)

    filename = os.path.basename(filepath)
    return FileResponse(
        filepath,
        filename=filename,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )

@router.get("/exams/{exam_id}/export/pdf")
def export_pdf(exam_id: int, db=Depends(get_db)):
    """Generates and downloads the formatted PDF assessment report."""
    exam = db[OMRExam.collection].find_one({"id": exam_id})
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    exam.pop("_id", None)

    submissions = list(db[OMRSubmission.collection].find({"exam_id": exam_id}))
    for s in submissions:
        s.pop("_id", None)

    analytics = compute_exam_analytics(exam, submissions)
    filepath = generate_omr_pdf(exam, analytics)

    filename = os.path.basename(filepath)
    return FileResponse(
        filepath,
        filename=filename,
        media_type="application/pdf"
    )

@router.delete("/exams/{exam_id}")
def delete_exam(exam_id: int, db=Depends(get_db)):
    """Deletes an exam and all related submissions."""
    db[OMRExam.collection].delete_one({"id": exam_id})
    db[OMRSubmission.collection].delete_many({"exam_id": exam_id})
    return {"success": True, "message": "Exam deleted"}

# ── OMR Sheet Generation ─────────────────────────────────────────────────────

@router.get("/sheet/generate")
def generate_blank_sheet(
    total_questions: int = Query(180, ge=1, le=180),
    title: str = Query("EXAMINATION"),
    subtitle: str = Query("OMR ANSWER SHEET"),
):
    """
    Generates a blank printable OMR sheet PDF for the given number of questions.
    Always uses the standard 4-column × 45-row (180-position) physical layout.
    Questions beyond total_questions are greyed out on the sheet.
    """
    import tempfile
    pdf_bytes = generate_omr_sheet_pdf(
        title=title,
        subtitle=subtitle,
        total_questions=total_questions,
    )
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".pdf")
    tmp.write(pdf_bytes)
    tmp.close()
    return FileResponse(
        tmp.name,
        filename=f"OMR_Sheet_{total_questions}Q.pdf",
        media_type="application/pdf"
    )

@router.get("/exams/{exam_id}/sheet")
def generate_exam_sheet(exam_id: int, db=Depends(get_db)):
    """
    Generates a printable OMR sheet PDF tailored for a specific exam,
    including section labels, question ranges, and the exam title.
    """
    import tempfile
    exam = db[OMRExam.collection].find_one({"id": exam_id})
    if not exam:
        raise HTTPException(status_code=404, detail="Exam not found")
    exam.pop("_id", None)

    pdf_bytes = generate_omr_for_exam(exam)
    title_clean = "".join(c for c in exam.get("title", "Exam") if c.isalnum() or c in " _-")
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".pdf")
    tmp.write(pdf_bytes)
    tmp.close()
    return FileResponse(
        tmp.name,
        filename=f"OMR_Sheet_{title_clean}.pdf",
        media_type="application/pdf"
    )

