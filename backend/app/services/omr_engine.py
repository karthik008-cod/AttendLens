"""
AttendLens OMR Engine — Computer Vision Optical Mark Recognition
================================================================
Robust, pure-OpenCV OMR processor for multiple-choice examinations.
Supports 1 to 180 questions on a fixed 4-column × 45-row physical layout
(like NMMS, JEE, NEET), perspective warp alignment, adaptive bubble
density detection, multi-mark and unattempted detection, and answer key
extraction.
"""

import cv2
import numpy as np
import logging
from typing import Dict, Any, List, Optional, Tuple

logger = logging.getLogger("omr_engine")

# ── Configuration Constants ──────────────────────────────────────────────────
WARP_WIDTH = 1200
WARP_HEIGHT = 1650
BUBBLE_FILL_THRESHOLD = 0.35      # Minimum density to count as filled
BUBBLE_DIFF_THRESHOLD = 0.12      # Difference required over 2nd highest to avoid multi-mark

# ── Physical layout constants (must match omr_sheet_generator.py) ────────────
PHYSICAL_COLS = 4
PHYSICAL_ROWS_PER_COL = 45

def _order_points(pts: np.ndarray) -> np.ndarray:
    """Orders coordinates as: top-left, top-right, bottom-right, bottom-left."""
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]   # top-left has smallest sum
    rect[2] = pts[np.argmax(s)]   # bottom-right has largest sum

    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)] # top-right has smallest diff
    rect[3] = pts[np.argmax(diff)] # bottom-left has largest diff
    return rect

def align_omr_sheet(image: np.ndarray) -> Tuple[np.ndarray, bool]:
    """
    Finds the largest 4-corner contour (the OMR sheet boundaries)
    and warps perspective to a clean WARP_WIDTH x WARP_HEIGHT rectangle.
    Returns (warped_image, success_flag).
    """
    h, w = image.shape[:2]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image.copy()
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edged = cv2.Canny(blurred, 50, 150)

    # Find contours
    contours, _ = cv2.findContours(edged.copy(), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:5]

    sheet_contour = None
    for c in contours:
        peri = cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, 0.02 * peri, True)
        # Area must be at least 25% of total image
        if len(approx) == 4 and cv2.contourArea(c) > (0.25 * w * h):
            sheet_contour = approx
            break

    if sheet_contour is not None:
        pts = sheet_contour.reshape(4, 2)
        rect = _order_points(pts)
        dst = np.array([
            [0, 0],
            [WARP_WIDTH - 1, 0],
            [WARP_WIDTH - 1, WARP_HEIGHT - 1],
            [0, WARP_HEIGHT - 1]
        ], dtype="float32")
        M = cv2.getPerspectiveTransform(rect, dst)
        warped = cv2.warpPerspective(image, M, (WARP_WIDTH, WARP_HEIGHT))
        return warped, True
    else:
        # Fallback: Resize directly to standard dimensions
        resized = cv2.resize(image, (WARP_WIDTH, WARP_HEIGHT))
        return resized, False

def extract_hall_ticket_box(warped: np.ndarray) -> Optional[np.ndarray]:
    """Extracts the Hall Ticket No. box region (top-left) from the aligned sheet."""
    # In standard NMMS sheet, Hall ticket box is approx: x: 15% to 45%, y: 5% to 9%
    h, w = warped.shape[:2]
    y1, y2 = int(h * 0.05), int(h * 0.10)
    x1, x2 = int(w * 0.15), int(w * 0.48)
    return warped[y1:y2, x1:x2]

def process_omr_sheet(
    image_bytes: bytes,
    total_questions: int = 180,
    options_per_q: int = 4
) -> Dict[str, Any]:
    """
    Core OMR processing function.
    Reads image, aligns sheet, segments bubble grid, evaluates marked options.

    The bubble grid on the printed sheet is ALWAYS a fixed 4-column × 45-row
    layout (180 positions). The engine always reads at these fixed positions.
    Only answers for questions 1..total_questions are reported; remaining
    positions are silently ignored.

    Returns:
      {
        "success": bool,
        "aligned": bool,
        "answers": { "1": 2, "2": 4, "3": null, "4": "MULTI", ... },
        "marked_counts": { "single": 140, "unattempted": 35, "multi": 5 },
        "fill_metrics": { "1": [0.72, 0.04, 0.08, 0.02], ... }
      }
    """
    # Clamp total_questions to valid range
    total_questions = max(1, min(180, total_questions))

    # 1. Decode image
    nparr = np.frombuffer(image_bytes, np.uint8)
    image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    if image is None:
        return {"success": False, "error": "Could not decode image"}

    # 2. Align sheet
    warped, aligned = align_omr_sheet(image)

    # 3. Preprocess for bubble thresholding
    gray = cv2.cvtColor(warped, cv2.COLOR_BGR2GRAY)
    # Enhance contrast with CLAHE
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)
    # Otsu thresholding: dark pencil/pen marks become white (255), white paper becomes black (0)
    _, thresh = cv2.threshold(enhanced, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    # 4. Layout geometry — ALWAYS use the fixed 4-col × 45-row physical grid
    num_cols = PHYSICAL_COLS
    q_per_col = PHYSICAL_ROWS_PER_COL

    # In NMMS 180 sheet, the bubble area spans approx:
    # y: 13.5% to 96.5% of sheet
    # x: 5% to 95% of sheet
    grid_top = int(WARP_HEIGHT * 0.135)
    grid_bottom = int(WARP_HEIGHT * 0.965)
    grid_left = int(WARP_WIDTH * 0.05)
    grid_right = int(WARP_WIDTH * 0.95)

    grid_height = grid_bottom - grid_top
    grid_width = grid_right - grid_left
    col_width = grid_width / num_cols

    answers: Dict[str, Any] = {}
    fill_metrics: Dict[str, List[float]] = {}
    single_count = 0
    unattempted_count = 0
    multi_count = 0

    for col_idx in range(num_cols):
        col_x_start = grid_left + (col_idx * col_width)
        # In each column, questions are arranged vertically with fixed row spacing
        row_height = grid_height / q_per_col

        for row_idx in range(q_per_col):
            # Physical question number on the sheet (col-major order)
            q_num = col_idx * q_per_col + row_idx + 1

            # Skip positions beyond 180 (shouldn't happen) and beyond total_questions
            if q_num > 180:
                break
            if q_num > total_questions:
                continue  # Skip this bubble position — don't read it

            q_y_center = grid_top + (row_idx * row_height) + (row_height * 0.5)

            # Inside each question row, 4 bubbles are spaced horizontally:
            # [Q Num space ~22%] [Bubble A ~18.75%] [B] [C] [D]
            options_area_start = col_x_start + (col_width * 0.22)
            options_area_width = col_width * 0.75
            opt_spacing = options_area_width / options_per_q

            bubble_scores: List[float] = []
            bubble_radius = int(min(row_height, opt_spacing) * 0.32)
            bubble_radius = max(bubble_radius, 4)

            for opt_idx in range(options_per_q):
                opt_x = int(options_area_start + (opt_idx * opt_spacing) + (opt_spacing * 0.5))
                opt_y = int(q_y_center)

                # Sample circular ROI
                y1 = max(0, opt_y - bubble_radius)
                y2 = min(WARP_HEIGHT, opt_y + bubble_radius)
                x1 = max(0, opt_x - bubble_radius)
                x2 = min(WARP_WIDTH, opt_x + bubble_radius)

                roi = thresh[y1:y2, x1:x2]
                if roi.size == 0:
                    bubble_scores.append(0.0)
                    continue

                # Create circular mask
                mask = np.zeros(roi.shape, dtype=np.uint8)
                cv2.circle(mask, (mask.shape[1] // 2, mask.shape[0] // 2), bubble_radius, 255, -1)

                # Calculate mean pixel fill within mask
                total_mask_pixels = cv2.countNonZero(mask)
                if total_mask_pixels > 0:
                    filled_pixels = cv2.countNonZero(cv2.bitwise_and(roi, roi, mask=mask))
                    density = filled_pixels / total_mask_pixels
                else:
                    density = 0.0

                bubble_scores.append(round(density, 3))

            fill_metrics[str(q_num)] = bubble_scores

            # Determine choice:
            sorted_indices = sorted(range(len(bubble_scores)), key=lambda k: bubble_scores[k], reverse=True)
            top_idx = sorted_indices[0]
            top_score = bubble_scores[top_idx]
            second_score = bubble_scores[sorted_indices[1]] if len(bubble_scores) > 1 else 0.0

            if top_score < BUBBLE_FILL_THRESHOLD:
                # None filled
                answers[str(q_num)] = None
                unattempted_count += 1
            elif (second_score >= BUBBLE_FILL_THRESHOLD) and ((top_score - second_score) < BUBBLE_DIFF_THRESHOLD):
                # Multiple filled
                answers[str(q_num)] = "MULTI"
                multi_count += 1
            else:
                # Valid single choice (1-indexed: 1, 2, 3, 4)
                answers[str(q_num)] = top_idx + 1
                single_count += 1

    return {
        "success": True,
        "aligned": aligned,
        "total_questions": total_questions,
        "answers": answers,
        "marked_counts": {
            "single": single_count,
            "unattempted": unattempted_count,
            "multi": multi_count
        },
        "fill_metrics": fill_metrics
    }

def extract_key_from_photo(
    image_bytes: bytes,
    total_questions: int = 180,
    options_per_q: int = 4
) -> Dict[str, Any]:
    """
    Extracts answer key from a teacher's filled key OMR sheet.
    Returns:
      {
        "success": bool,
        "answer_key": { "1": 2, "2": 1, ... },
        "missing_keys": [45, 92],  # questions where no bubble was detected
        "multi_keys": [12]         # questions where multiple bubbles were detected
      }
    """
    res = process_omr_sheet(image_bytes, total_questions, options_per_q)
    if not res.get("success"):
        return res

    answers = res["answers"]
    answer_key: Dict[str, int] = {}
    missing_keys: List[int] = []
    multi_keys: List[int] = []

    for q_str, ans in answers.items():
        q_num = int(q_str)
        if ans is None:
            missing_keys.append(q_num)
        elif ans == "MULTI":
            multi_keys.append(q_num)
            # Default to highest density or leave for teacher confirmation
            top_idx = int(np.argmax(res["fill_metrics"][q_str])) + 1
            answer_key[q_str] = top_idx
        else:
            answer_key[q_str] = int(ans)

    return {
        "success": True,
        "aligned": res["aligned"],
        "answer_key": answer_key,
        "missing_keys": missing_keys,
        "multi_keys": multi_keys,
        "total_questions": total_questions
    }
