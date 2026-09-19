"""
AttendLens OMR Sheet PDF Generator
===================================
Generates pixel-perfect, printable OMR answer sheets that align with the
coordinate system used by omr_engine.py.

CRITICAL SPECIFICATIONS (must match omr_engine.py geometry):
  • Warped target: 1200 × 1650 px  →  A4 at ~100 DPI
  • Bubble grid area: y ∈ [13.5%, 96.5%], x ∈ [5%, 95%]
  • 4 columns, 45 rows each  →  180 questions max
  • Each column: [Q# ~22%] [Options ~75%] with 4 equally spaced bubbles
  • Options area starts at 22% into each column, spans 75%
  • Bubble centres at 50% of each option spacing cell

The sheet is generated as A4 portrait PDF at 72 DPI (ReportLab default).
All coordinates are mapped proportionally from the 1200×1650 pixel grid.
"""

import io
import os
import math
from typing import List, Dict, Any, Optional, Tuple
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas
from reportlab.lib.colors import black, white, Color, HexColor

# ── A4 page in points (72 DPI) ───────────────────────────────────────────────
PAGE_W, PAGE_H = A4  # 595.28 × 841.89 pt

# ── Margins ──────────────────────────────────────────────────────────────────
# We use a printable area that mirrors the warp target proportions (1200:1650)
# within A4 with a border thick enough for contour detection.
BORDER_MARGIN = 18 * mm        # outer margin from page edge to thick border
BORDER_THICKNESS = 1.8 * mm    # thickness of the outer border (for contour detection)

# Inner area (the warped rectangle = what the engine sees)
INNER_LEFT = BORDER_MARGIN + BORDER_THICKNESS
INNER_TOP = BORDER_MARGIN + BORDER_THICKNESS
INNER_W = PAGE_W - 2 * (BORDER_MARGIN + BORDER_THICKNESS)
INNER_H = PAGE_H - 2 * (BORDER_MARGIN + BORDER_THICKNESS)

# ── Grid geometry (fractional, matching omr_engine.py) ───────────────────────
GRID_TOP_FRAC = 0.135
GRID_BOTTOM_FRAC = 0.965
GRID_LEFT_FRAC = 0.05
GRID_RIGHT_FRAC = 0.95

NUM_COLS = 4
Q_PER_COL = 45
OPTIONS_PER_Q = 4

# Within each column
Q_NUM_FRAC = 0.22        # question number area (left side of column)
OPTIONS_AREA_FRAC = 0.75  # bubble options area

# Bubble sizing
BUBBLE_RADIUS_MM = 2.0 * mm  # Radius of each bubble circle (reduced to prevent overlap)

# Header geometry fractions (relative to inner area)
HEADER_TOP_FRAC = 0.015
HEADER_HEIGHT_FRAC = 0.11  # header block height

# Colours
DARK_GREY = HexColor("#333333")
MED_GREY = HexColor("#666666")
LIGHT_GREY = HexColor("#CCCCCC")


def _inner_x(frac: float) -> float:
    """Convert fractional x (0..1 within warped image) to PDF x coordinate."""
    return INNER_LEFT + (frac * INNER_W)


def _inner_y(frac: float) -> float:
    """Convert fractional y (0..1 within warped image) to PDF y coordinate.
    PDF y goes bottom-up, warped y goes top-down, so we invert."""
    return (INNER_TOP + INNER_H) - (frac * INNER_H)


def generate_omr_sheet_pdf(
    title: str = "EXAMINATION",
    subtitle: str = "OMR ANSWER SHEET",
    total_questions: int = 180,
    sections: Optional[List[Dict[str, Any]]] = None,
    output_path: Optional[str] = None,
    footer_text: str = "ZPHS KISTAPUR",
) -> bytes:
    """
    Generates a printable OMR answer sheet PDF.

    Args:
        title: Main title text (e.g. institution name)
        subtitle: Sub-title text (e.g. exam name)
        total_questions: Number of questions (1-180). Bubbles beyond this are
                         greyed out / not printed, but the full 180-grid layout
                         is always maintained.
        sections: Optional list of section dicts for labelling:
                  [{"subject_name": "Maths", "start_q": 1, "end_q": 30}, ...]
        output_path: If provided, writes to this file path. Always returns bytes.

    Returns:
        PDF file content as bytes.
    """
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    c.setTitle(f"{title} - OMR Sheet")

    # ── 1. Draw thick outer border (critical for contour detection) ──────────
    c.setStrokeColor(black)
    c.setLineWidth(BORDER_THICKNESS)
    c.rect(
        BORDER_MARGIN + BORDER_THICKNESS / 2,
        BORDER_MARGIN + BORDER_THICKNESS / 2,
        PAGE_W - 2 * BORDER_MARGIN - BORDER_THICKNESS,
        PAGE_H - 2 * BORDER_MARGIN - BORDER_THICKNESS,
    )

    # ── 2. Corner alignment markers (solid black squares) ────────────────────
    marker_size = 5 * mm
    corners = [
        (INNER_LEFT + 2*mm, _inner_y(0) - 2*mm - marker_size),                       # top-left
        (INNER_LEFT + INNER_W - 2*mm - marker_size, _inner_y(0) - 2*mm - marker_size), # top-right
        (INNER_LEFT + 2*mm, _inner_y(1) + 2*mm),                                      # bottom-left
        (INNER_LEFT + INNER_W - 2*mm - marker_size, _inner_y(1) + 2*mm),               # bottom-right
    ]
    c.setFillColor(black)
    for cx_pos, cy_pos in corners:
        c.rect(cx_pos, cy_pos, marker_size, marker_size, fill=1, stroke=0)

    # ── 3. Header section ────────────────────────────────────────────────────
    header_y_top = _inner_y(HEADER_TOP_FRAC)
    header_y_bottom = _inner_y(HEADER_TOP_FRAC + HEADER_HEIGHT_FRAC)
    header_center_x = INNER_LEFT + INNER_W / 2

    # Title
    c.setFillColor(black)
    c.setFont("Helvetica-Bold", 14)
    c.drawCentredString(header_center_x, header_y_top - 16, title.upper())

    # Subtitle
    c.setFont("Helvetica-Bold", 10)
    c.drawCentredString(header_center_x, header_y_top - 30, subtitle.upper())

    # Hall Ticket No. field (thin outline)
    field_y = header_y_top - 52
    field_left = INNER_LEFT + INNER_W * 0.05
    c.setFont("Helvetica", 9)
    c.drawString(field_left, field_y, "Hall Ticket No.:")
    box_x = field_left + 72
    c.setLineWidth(0.4)  # Thin outline for fields
    c.rect(box_x, field_y - 4, 140, 16, stroke=1, fill=0)

    # Name field (thin outline)
    name_left = INNER_LEFT + INNER_W * 0.50
    c.drawString(name_left, field_y, "Name of the Student:")
    c.rect(name_left + 95, field_y - 4, 140, 16, stroke=1, fill=0)

    # Section labels
    if sections:
        sec_y = header_y_top - 72
        c.setFont("Helvetica-Bold", 8)
        for i, sec in enumerate(sections):
            sec_name = sec.get("subject_name", f"Section {i+1}")
            start_q = sec.get("start_q", "?")
            end_q = sec.get("end_q", "?")
            label = f"SECTION {i+1}: {sec_name.upper()} (Q{start_q}-Q{end_q})"
            sec_x = INNER_LEFT + INNER_W * (0.05 + (i % 2) * 0.48)
            c.drawString(sec_x, sec_y, label)
            if i % 2 == 1:
                sec_y -= 14

    # Draw a separator line under the header
    sep_y = _inner_y(GRID_TOP_FRAC - 0.005)
    c.setStrokeColor(DARK_GREY)
    c.setLineWidth(0.8)
    c.line(_inner_x(GRID_LEFT_FRAC), sep_y, _inner_x(GRID_RIGHT_FRAC), sep_y)

    # ── 4. Column separators and part labels ─────────────────────────────────
    grid_left = _inner_x(GRID_LEFT_FRAC)
    grid_right = _inner_x(GRID_RIGHT_FRAC)
    grid_top = _inner_y(GRID_TOP_FRAC)
    grid_bottom = _inner_y(GRID_BOTTOM_FRAC)
    grid_w = grid_right - grid_left
    col_w = grid_w / NUM_COLS

    c.setStrokeColor(MED_GREY)
    c.setLineWidth(0.5)
    for col_idx in range(1, NUM_COLS):
        cx = grid_left + col_idx * col_w
        c.line(cx, grid_top, cx, grid_bottom)

    # Outer grid border
    c.setStrokeColor(DARK_GREY)
    c.setLineWidth(0.8)
    c.rect(grid_left, grid_bottom, grid_w, grid_top - grid_bottom, stroke=1, fill=0)

    # NOTE: Section labels are already shown in the header area.
    # No duplicate labels above the grid columns.

    # ── 5. Option header row (A B C D) ───────────────────────────────────────
    c.setFont("Helvetica-Bold", 6.5)
    c.setFillColor(MED_GREY)
    option_labels = ["A", "B", "C", "D"]
    option_header_y = grid_top - 10

    for col_idx in range(NUM_COLS):
        col_x = grid_left + col_idx * col_w
        opt_area_start = col_x + col_w * Q_NUM_FRAC
        opt_area_w = col_w * OPTIONS_AREA_FRAC
        opt_spacing = opt_area_w / OPTIONS_PER_Q

        for opt_idx in range(OPTIONS_PER_Q):
            opt_cx = opt_area_start + opt_idx * opt_spacing + opt_spacing * 0.5
            c.drawCentredString(opt_cx, option_header_y, option_labels[opt_idx])

    # ── 6. Draw bubble grid ──────────────────────────────────────────────────
    grid_h_frac = GRID_BOTTOM_FRAC - GRID_TOP_FRAC
    row_h_frac = grid_h_frac / Q_PER_COL

    current_q = 1
    for col_idx in range(NUM_COLS):
        col_x = grid_left + col_idx * col_w

        for row_idx in range(Q_PER_COL):
            q_num = col_idx * Q_PER_COL + row_idx + 1
            if q_num > 180:
                break

            # y fraction for the centre of this row
            row_center_frac = GRID_TOP_FRAC + row_idx * row_h_frac + row_h_frac * 0.5
            row_y = _inner_y(row_center_frac)

            is_active = q_num <= total_questions

            # Question number
            q_num_x = col_x + 4
            if is_active:
                c.setFillColor(black)
                c.setFont("Helvetica-Bold", 7)
            else:
                c.setFillColor(LIGHT_GREY)
                c.setFont("Helvetica", 6.5)
            c.drawString(q_num_x, row_y - 2.5, str(q_num))

            # Bubbles
            opt_area_start = col_x + col_w * Q_NUM_FRAC
            opt_area_w = col_w * OPTIONS_AREA_FRAC
            opt_spacing = opt_area_w / OPTIONS_PER_Q

            for opt_idx in range(OPTIONS_PER_Q):
                opt_cx = opt_area_start + opt_idx * opt_spacing + opt_spacing * 0.5

                if is_active:
                    # Active bubble: clear circle with dark border
                    c.setStrokeColor(black)
                    c.setLineWidth(0.6)
                    c.setFillColor(white)
                    c.circle(opt_cx, row_y, BUBBLE_RADIUS_MM, stroke=1, fill=1)
                else:
                    # Inactive: very light grey, thin border
                    c.setStrokeColor(LIGHT_GREY)
                    c.setLineWidth(0.3)
                    c.setFillColor(white)
                    c.circle(opt_cx, row_y, BUBBLE_RADIUS_MM, stroke=1, fill=1)

    # ── 7. Instructions footer ───────────────────────────────────────────────
    footer_y = _inner_y(0.975)
    c.setFont("Helvetica", 5.5)
    c.setFillColor(MED_GREY)
    c.drawCentredString(
        header_center_x, footer_y,
        "Fill bubbles completely with dark pencil or pen  •  Do not fold or crease  •  "
        "Erase cleanly if corrected  •  Generated by AttendLens"
    )

    # School / institution name at the bottom
    if footer_text:
        c.setFont("Helvetica-Bold", 8)
        c.setFillColor(DARK_GREY)
        c.drawCentredString(header_center_x, footer_y - 12, footer_text.upper())

    # ── Finalize ─────────────────────────────────────────────────────────────
    c.showPage()
    c.save()
    pdf_bytes = buf.getvalue()

    if output_path:
        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(pdf_bytes)

    return pdf_bytes


def generate_omr_for_exam(exam_doc: Dict[str, Any], output_path: Optional[str] = None) -> bytes:
    """
    Convenience wrapper: generates an OMR sheet PDF from an exam document.
    The exam_doc should match the shape stored in MongoDB (ExamCreateRequest).
    """
    title = exam_doc.get("title", "EXAMINATION")
    total_q = exam_doc.get("total_questions", 180)
    sections = exam_doc.get("sections", [])

    return generate_omr_sheet_pdf(
        title=title,
        subtitle="OMR ANSWER SHEET",
        total_questions=total_q,
        sections=sections,
        output_path=output_path,
    )
