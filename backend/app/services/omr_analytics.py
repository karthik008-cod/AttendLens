"""
AttendLens OMR Analytics Engine — Classical Test Theory (CTT) & Psychometrics
==============================================================================
Computes comprehensive educational assessment analytics:
- Student performance (Score, Rank, Percentile, Accuracy, Penalty Ratio, Subject scores)
- Item analysis (Difficulty p-value, 27% Extreme Group DI, Distractors, Point-Biserial, Decision Tags)
- Exam/Batch analytics (Mean, Median, Std Dev, KR-20 Reliability, Histogram Bins, Risk Flags)
"""

import math
from typing import Dict, Any, List, Optional
import numpy as np

def compute_student_score(
    answers: Dict[str, Any],
    answer_key: Dict[str, int],
    sections: List[Dict[str, Any]],
    total_questions: int
) -> Dict[str, Any]:
    """
    Evaluates a single student's answers against the answer key and sectional marking scheme.
    """
    # Create question-to-section lookup
    # Each section: { "section_id": 1, "subject_name": "Maths", "start_q": 1, "end_q": 20, "marks_correct": 4.0, "marks_wrong": 1.0 }
    q_to_section: Dict[int, Dict[str, Any]] = {}
    for sec in sections:
        start_q = sec.get("start_q", 1)
        end_q = sec.get("end_q", total_questions)
        for q in range(start_q, end_q + 1):
            q_to_section[q] = sec

    total_score = 0.0
    gross_score = 0.0
    marks_lost = 0.0
    correct_count = 0
    wrong_count = 0
    unattempted_count = 0
    multi_count = 0
    total_max_marks = 0.0

    # Subject breakdown accumulator
    subj_stats: Dict[str, Dict[str, Any]] = {}
    for sec in sections:
        subj = sec.get("subject_name", f"Section {sec.get('section_id', 1)}")
        subj_stats[subj] = {
            "subject": subj,
            "score": 0.0,
            "max_marks": 0.0,
            "correct": 0,
            "wrong": 0,
            "unattempted": 0,
            "multi": 0,
            "accuracy": 0.0,
            "percentage": 0.0
        }

    for q_num in range(1, total_questions + 1):
        q_str = str(q_num)
        sec_info = q_to_section.get(q_num, {
            "subject_name": "General",
            "marks_correct": 1.0,
            "marks_wrong": 0.0
        })
        subj = sec_info.get("subject_name", "General")
        m_correct = float(sec_info.get("marks_correct", 1.0))
        m_wrong = float(sec_info.get("marks_wrong", 0.0))

        total_max_marks += m_correct
        if subj in subj_stats:
            subj_stats[subj]["max_marks"] += m_correct

        key_ans = answer_key.get(q_str)
        stud_ans = answers.get(q_str)

        if stud_ans is None:
            unattempted_count += 1
            if subj in subj_stats:
                subj_stats[subj]["unattempted"] += 1
        elif stud_ans == "MULTI":
            multi_count += 1
            wrong_count += 1
            total_score -= m_wrong
            marks_lost += m_wrong
            if subj in subj_stats:
                subj_stats[subj]["multi"] += 1
                subj_stats[subj]["wrong"] += 1
                subj_stats[subj]["score"] -= m_wrong
        else:
            # Numeric answer (1, 2, 3, 4)
            try:
                stud_ans_int = int(stud_ans)
            except (ValueError, TypeError):
                stud_ans_int = -1

            if key_ans is not None and stud_ans_int == int(key_ans):
                correct_count += 1
                total_score += m_correct
                gross_score += m_correct
                if subj in subj_stats:
                    subj_stats[subj]["correct"] += 1
                    subj_stats[subj]["score"] += m_correct
            else:
                wrong_count += 1
                total_score -= m_wrong
                marks_lost += m_wrong
                if subj in subj_stats:
                    subj_stats[subj]["wrong"] += 1
                    subj_stats[subj]["score"] -= m_wrong

    attempted_count = correct_count + wrong_count
    attempt_rate = (attempted_count / total_questions * 100.0) if total_questions > 0 else 0.0
    accuracy = (correct_count / attempted_count * 100.0) if attempted_count > 0 else 0.0
    percentage = (total_score / total_max_marks * 100.0) if total_max_marks > 0 else 0.0
    penalty_ratio = (marks_lost / gross_score * 100.0) if gross_score > 0 else 0.0

    # Finalize subject stats
    for subj, sdata in subj_stats.items():
        s_att = sdata["correct"] + sdata["wrong"]
        sdata["accuracy"] = round((sdata["correct"] / s_att * 100.0), 1) if s_att > 0 else 0.0
        sdata["percentage"] = round((sdata["score"] / sdata["max_marks"] * 100.0), 1) if sdata["max_marks"] > 0 else 0.0
        sdata["score"] = round(sdata["score"], 2)

    return {
        "total_score": round(total_score, 2),
        "gross_score": round(gross_score, 2),
        "total_max_marks": round(total_max_marks, 2),
        "percentage": round(percentage, 2),
        "correct_count": correct_count,
        "wrong_count": wrong_count,
        "unattempted_count": unattempted_count,
        "multi_count": multi_count,
        "attempted_count": attempted_count,
        "attempt_rate": round(attempt_rate, 2),
        "accuracy": round(accuracy, 2),
        "marks_lost": round(marks_lost, 2),
        "penalty_ratio": round(penalty_ratio, 2),
        "subject_breakdown": list(subj_stats.values())
    }

def compute_exam_analytics(
    exam_doc: Dict[str, Any],
    submissions: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """
    Computes complete CTT Item Analysis, Student Rankings & Percentiles,
    Batch Statistics, Histogram, KR-20 Reliability, and Student Risk Flags.
    """
    total_questions = exam_doc.get("total_questions", 180)
    answer_key = exam_doc.get("answer_key", {})
    sections = exam_doc.get("sections", [])
    N = len(submissions)

    if N == 0:
        return {
            "batch_summary": {
                "total_students": 0,
                "mean_score": 0.0,
                "median_score": 0.0,
                "std_dev": 0.0,
                "highest_score": 0.0,
                "lowest_score": 0.0,
                "pass_rate": 0.0,
                "kr20_reliability": 0.0,
                "average_difficulty": 0.0,
                "average_discrimination": 0.0
            },
            "students": [],
            "item_analysis": [],
            "score_distribution": [],
            "subject_batch_performance": []
        }

    # 1. Evaluate all students
    evaluated_students: List[Dict[str, Any]] = []
    for sub in submissions:
        ans = sub.get("answers", {})
        eval_res = compute_student_score(ans, answer_key, sections, total_questions)
        student_entry = {
            "id": sub.get("id"),
            "student_hall_ticket": sub.get("student_hall_ticket", "Unknown"),
            "student_name": sub.get("student_name", "Student"),
            "answers": ans,
            **eval_res
        }
        evaluated_students.append(student_entry)

    # 2. Sort by Total Score descending
    evaluated_students.sort(key=lambda s: s["total_score"], reverse=True)

    # 3. Calculate Ranks (Standard Competition Ranking "1224") & Percentiles
    scores_array = [s["total_score"] for s in evaluated_students]
    for idx, s in enumerate(evaluated_students):
        # Rank: 1-indexed rank of first student with equal score
        rank = scores_array.index(s["total_score"]) + 1
        s["rank"] = rank

        # Percentile: (B + 0.5 * E) / N * 100
        B = sum(1 for sc in scores_array if sc < s["total_score"])
        E = sum(1 for sc in scores_array if sc == s["total_score"])
        pr = ((B + 0.5 * E) / N) * 100.0
        s["percentile"] = round(pr, 2)

    # 4. Batch Summary Statistics
    mean_score = float(np.mean(scores_array))
    median_score = float(np.median(scores_array))
    std_dev = float(np.std(scores_array)) if N > 1 else 0.0
    var_score = float(np.var(scores_array)) if N > 1 else 0.0
    highest_score = float(np.max(scores_array))
    lowest_score = float(np.min(scores_array))

    max_marks = evaluated_students[0]["total_max_marks"] if evaluated_students else 100.0
    pass_mark = max_marks * 0.40  # 40% passing standard
    passed_count = sum(1 for sc in scores_array if sc >= pass_mark)
    pass_rate = round((passed_count / N * 100.0), 2)

    # 5. Score Distribution Histogram (10 Bins)
    bins = [
        {"range": "0-10%", "min": 0, "max": 10, "count": 0},
        {"range": "11-20%", "min": 10, "max": 20, "count": 0},
        {"range": "21-30%", "min": 20, "max": 30, "count": 0},
        {"range": "31-40%", "min": 30, "max": 40, "count": 0},
        {"range": "41-50%", "min": 40, "max": 50, "count": 0},
        {"range": "51-60%", "min": 50, "max": 60, "count": 0},
        {"range": "61-70%", "min": 60, "max": 70, "count": 0},
        {"range": "71-80%", "min": 70, "max": 80, "count": 0},
        {"range": "81-90%", "min": 80, "max": 90, "count": 0},
        {"range": "91-100%", "min": 90, "max": 100.1, "count": 0},
    ]
    for s in evaluated_students:
        pct = s["percentage"]
        for b in bins:
            if b["min"] <= pct < b["max"] or (b["range"] == "91-100%" and pct >= 90):
                b["count"] += 1
                break

    # 6. Item Analysis (Classical Test Theory)
    # Kelley's 27% Extreme Groups
    n_extreme = max(1, int(round(0.27 * N)))
    upper_group = evaluated_students[:n_extreme]
    lower_group = evaluated_students[-n_extreme:] if N >= 2 else evaluated_students[:n_extreme]

    # Map question to subject
    q_to_subj: Dict[int, str] = {}
    for sec in sections:
        start_q = sec.get("start_q", 1)
        end_q = sec.get("end_q", total_questions)
        for q in range(start_q, end_q + 1):
            q_to_subj[q] = sec.get("subject_name", f"Section {sec.get('section_id', 1)}")

    item_analysis: List[Dict[str, Any]] = []
    p_values: List[float] = []
    di_values: List[float] = []
    sum_pq = 0.0

    for q_num in range(1, total_questions + 1):
        q_str = str(q_num)
        key_opt = answer_key.get(q_str)
        key_int = int(key_opt) if key_opt is not None else None

        # Count choices across all students, upper group, lower group
        choice_counts = {1: 0, 2: 0, 3: 0, 4: 0, "MULTI": 0, "BLANK": 0}
        upper_counts = {1: 0, 2: 0, 3: 0, 4: 0}
        lower_counts = {1: 0, 2: 0, 3: 0, 4: 0}

        correct_students_scores: List[float] = []

        for s in evaluated_students:
            ans = s["answers"].get(q_str)
            if ans is None:
                choice_counts["BLANK"] += 1
            elif ans == "MULTI":
                choice_counts["MULTI"] += 1
            else:
                try:
                    ans_i = int(ans)
                    if ans_i in choice_counts:
                        choice_counts[ans_i] += 1
                    if key_int is not None and ans_i == key_int:
                        correct_students_scores.append(s["total_score"])
                except (ValueError, TypeError):
                    choice_counts["BLANK"] += 1

        for s in upper_group:
            ans = s["answers"].get(q_str)
            try:
                ans_i = int(ans)
                if ans_i in upper_counts:
                    upper_counts[ans_i] += 1
            except (ValueError, TypeError):
                pass

        for s in lower_group:
            ans = s["answers"].get(q_str)
            try:
                ans_i = int(ans)
                if ans_i in lower_counts:
                    lower_counts[ans_i] += 1
            except (ValueError, TypeError):
                pass

        # 1. Difficulty Index p
        correct_count = choice_counts.get(key_int, 0) if key_int is not None else 0
        p = correct_count / N
        p_values.append(p)
        sum_pq += (p * (1.0 - p))

        # Interpretation for Difficulty
        if p > 0.80:
            diff_label = "Very Easy"
        elif p >= 0.60:
            diff_label = "Easy"
        elif p >= 0.40:
            diff_label = "Moderate / Ideal"
        elif p >= 0.20:
            diff_label = "Hard"
        else:
            diff_label = "Very Hard"

        # 2. Discrimination Index DI (Extreme Group)
        ru = upper_counts.get(key_int, 0) if key_int is not None else 0
        rl = lower_counts.get(key_int, 0) if key_int is not None else 0
        di = (ru - rl) / n_extreme
        di = round(di, 3)
        di_values.append(di)

        if di >= 0.40:
            disc_label = "Excellent"
        elif di >= 0.30:
            disc_label = "Good"
        elif di >= 0.20:
            disc_label = "Marginal"
        elif di >= 0.00:
            disc_label = "Poor"
        else:
            disc_label = "Negative (Defective)"

        # 3. Point-Biserial Correlation
        # r_pbis = (X_1 - X) / sigma_X * sqrt(p * (1 - p))
        if std_dev > 0 and len(correct_students_scores) > 0 and 0.0 < p < 1.0:
            mean_correct = float(np.mean(correct_students_scores))
            r_pbis = ((mean_correct - mean_score) / std_dev) * math.sqrt(p * (1.0 - p))
            r_pbis = round(r_pbis, 3)
        else:
            r_pbis = 0.0

        # 4. Distractor Analysis
        distractors: Dict[str, Any] = {}
        nfd_count = 0
        for opt in [1, 2, 3, 4]:
            cnt = choice_counts.get(opt, 0)
            pct = round((cnt / N * 100.0), 1)
            is_key = (key_int is not None and opt == key_int)
            u_pct = round((upper_counts.get(opt, 0) / n_extreme * 100.0), 1)
            l_pct = round((lower_counts.get(opt, 0) / n_extreme * 100.0), 1)

            flag = "Functional"
            if not is_key:
                if pct < 5.0:
                    flag = "Non-Functional (<5%)"
                    nfd_count += 1
                elif u_pct > l_pct:
                    flag = "Misleading (Chosen by Top Students)"

            distractors[str(opt)] = {
                "count": cnt,
                "pct": pct,
                "upper_pct": u_pct,
                "lower_pct": l_pct,
                "is_key": is_key,
                "flag": flag
            }

        # 5. Automated Decision Tag
        if di < 0.0:
            decision = "CHECK KEY / DISCARD"
        elif di < 0.20 or p < 0.15 or p > 0.90 or nfd_count >= 2:
            decision = "REVISE"
        elif di >= 0.30 and 0.25 <= p <= 0.80 and nfd_count <= 1:
            decision = "KEEP (HIGH QUALITY)"
        else:
            decision = "KEEP (ACCEPTABLE)"

        item_analysis.append({
            "question_number": q_num,
            "subject": q_to_subj.get(q_num, "General"),
            "key": key_int,
            "p_value": round(p, 3),
            "difficulty_label": diff_label,
            "discrimination_index": di,
            "discrimination_label": disc_label,
            "point_biserial": r_pbis,
            "nfd_count": nfd_count,
            "decision": decision,
            "distractors": distractors
        })

    # 7. Paper-Level Metrics & KR-20 Reliability
    avg_difficulty = round(float(np.mean(p_values)), 3) if p_values else 0.0
    avg_discrimination = round(float(np.mean(di_values)), 3) if di_values else 0.0

    # KR-20 = (K / (K - 1)) * (1 - sum(p * q) / var_X)
    if total_questions > 1 and var_score > 0:
        kr20 = (total_questions / (total_questions - 1)) * (1.0 - (sum_pq / var_score))
        kr20 = max(0.0, min(1.0, round(kr20, 3)))
    else:
        kr20 = 0.0

    # 8. Student Risk Flags
    for s in evaluated_students:
        flags = []
        if s["percentage"] < 35.0:
            flags.append("Critical Failure (<35%)")
        if s["penalty_ratio"] > 20.0:
            flags.append(f"High Negative Loss ({s['penalty_ratio']}%)")
        if s["attempt_rate"] > 85.0 and s["accuracy"] < 35.0:
            flags.append("Chronic Guessing")
        for sb in s["subject_breakdown"]:
            if sb["percentage"] < 30.0 and s["percentage"] >= 40.0:
                flags.append(f"{sb['subject']} Deficit (<30%)")
        s["risk_flags"] = flags

    # 9. Subject-level Batch Performance
    subject_batch: Dict[str, Dict[str, Any]] = {}
    for s in evaluated_students:
        for sb in s["subject_breakdown"]:
            subj = sb["subject"]
            if subj not in subject_batch:
                subject_batch[subj] = {
                    "subject": subj,
                    "scores": [],
                    "accuracies": [],
                    "max_marks": sb["max_marks"]
                }
            subject_batch[subj]["scores"].append(sb["score"])
            subject_batch[subj]["accuracies"].append(sb["accuracy"])

    subject_batch_summary = []
    for subj, sdata in subject_batch.items():
        subject_batch_summary.append({
            "subject": subj,
            "average_score": round(float(np.mean(sdata["scores"])), 2),
            "average_accuracy": round(float(np.mean(sdata["accuracies"])), 1),
            "max_marks": sdata["max_marks"]
        })

    return {
        "batch_summary": {
            "total_students": N,
            "mean_score": round(mean_score, 2),
            "median_score": round(median_score, 2),
            "std_dev": round(std_dev, 2),
            "highest_score": round(highest_score, 2),
            "lowest_score": round(lowest_score, 2),
            "pass_rate": pass_rate,
            "kr20_reliability": kr20,
            "average_difficulty": avg_difficulty,
            "average_discrimination": avg_discrimination,
            "max_possible_marks": max_marks
        },
        "students": evaluated_students,
        "item_analysis": item_analysis,
        "score_distribution": bins,
        "subject_batch_performance": subject_batch_summary
    }
