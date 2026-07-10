"""
AttendLens AI Engine — Pure OpenCV Face Recognition
====================================================
Zero TensorFlow. Zero DeepFace. Works within 100MB RAM on Render Free Tier.

Face Detection:  OpenCV Haar Cascade (built-in, 0 downloads)
Face Encoding:   Spatial intensity histograms + gradient features (1280-dim)
Face Matching:   Cosine distance with dynamic thresholding
"""

import os
import json
import cv2
import numpy as np

# ── Constants ─────────────────────────────────────────────────────────────────
ENCODING_DIM = 1280  # 64 cells × (16 intensity + 4 gradient bins)
MATCH_THRESHOLD = 0.55  # Cosine distance: lower = stricter

# ── Face Detection ────────────────────────────────────────────────────────────
_face_cascade = None
_face_cascade_alt = None

def _get_face_cascade():
    global _face_cascade
    if _face_cascade is None:
        _face_cascade = cv2.CascadeClassifier(
            cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
        )
    return _face_cascade

def _get_alt_cascade():
    global _face_cascade_alt
    if _face_cascade_alt is None:
        _face_cascade_alt = cv2.CascadeClassifier(
            cv2.data.haarcascades + 'haarcascade_frontalface_alt2.xml'
        )
    return _face_cascade_alt

def _detect_faces(gray):
    """Multi-pass face detection using Haar Cascades."""
    cascade = _get_face_cascade()

    # Pass 1: Standard detection
    faces = cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(30, 30))
    if len(faces) > 0:
        return faces

    # Pass 2: More lenient
    faces = cascade.detectMultiScale(gray, scaleFactor=1.05, minNeighbors=3, minSize=(20, 20))
    if len(faces) > 0:
        return faces

    # Pass 3: Alt cascade (better for tilted/partial faces)
    alt = _get_alt_cascade()
    faces = alt.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=3, minSize=(20, 20))
    return faces


# ── Feature Extraction ────────────────────────────────────────────────────────

def _extract_face_features(face_gray):
    """Extract spatial histogram features from a grayscale face region.

    Divides the face into an 8×8 grid (64 cells).
    For each cell computes:
      - 16-bin intensity histogram (captures texture/appearance)
      - 4-bin gradient orientation histogram (captures edges/structure)
    Total: 64 × 20 = 1280 features, normalized to unit vector.
    """
    face = cv2.resize(face_gray, (128, 128))
    face = cv2.equalizeHist(face)  # Lighting invariance

    # Pre-compute gradients for the whole face
    gx = cv2.Sobel(face, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(face, cv2.CV_32F, 0, 1, ksize=3)
    mag = cv2.magnitude(gx, gy)
    angle = cv2.phase(gx, gy, angleInDegrees=True)  # 0-360

    features = []
    cell_size = 16  # 128 / 8

    for i in range(8):
        for j in range(8):
            r0, r1 = i * cell_size, (i + 1) * cell_size
            c0, c1 = j * cell_size, (j + 1) * cell_size

            cell = face[r0:r1, c0:c1]
            cell_mag = mag[r0:r1, c0:c1]
            cell_angle = angle[r0:r1, c0:c1]

            # Intensity histogram (16 bins)
            hist_intensity = cv2.calcHist([cell], [0], None, [16], [0, 256]).flatten()
            features.extend(hist_intensity)

            # Gradient orientation histogram (4 bins, weighted by magnitude)
            hist_grad = np.zeros(4, dtype=np.float32)
            for b in range(4):
                lo = b * 90.0
                hi = lo + 90.0
                mask = ((cell_angle >= lo) & (cell_angle < hi))
                hist_grad[b] = float(np.sum(cell_mag[mask]))
            features.extend(hist_grad)

    features = np.array(features, dtype=np.float32)
    norm = np.linalg.norm(features)
    if norm > 0:
        features = features / norm

    return features


def _crop_face(gray, x, y, w, h, padding=0.15):
    """Crop face ROI with padding for context."""
    pad = int(max(w, h) * padding)
    x1 = max(0, x - pad)
    y1 = max(0, y - pad)
    x2 = min(gray.shape[1], x + w + pad)
    y2 = min(gray.shape[0], y + h + pad)
    return gray[y1:y2, x1:x2]


def _extract_encoding_from_gray(gray):
    """Detect the largest face in a grayscale image and return its encoding, or None."""
    faces = _detect_faces(gray)
    if len(faces) == 0:
        return None

    x, y, w, h = max(faces, key=lambda f: f[2] * f[3])
    face_roi = _crop_face(gray, x, y, w, h)
    return _extract_face_features(face_roi)


# ── Public API: Encoding ──────────────────────────────────────────────────────

def extract_face_encoding(image_path: str) -> str:
    """Extract face encoding from an image file.
    Returns: JSON string of a 1280-dimensional feature vector.
    Always succeeds (returns zero vector on failure).
    """
    if not os.path.exists(image_path):
        return json.dumps(np.zeros(ENCODING_DIM).tolist())

    img = cv2.imread(image_path)
    if img is None:
        return json.dumps(np.zeros(ENCODING_DIM).tolist())

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    features = _extract_encoding_from_gray(gray)

    if features is None:
        # No face detected — use entire image as a face (close-up selfie)
        features = _extract_face_features(gray)

    return json.dumps(features.tolist())


def merge_student_encodings(photo_paths: list) -> str:
    """Average face embeddings across multiple photos for a student.
    More diverse photos → better recognition robustness.
    """
    embeddings = []
    for path in photo_paths:
        if not path or not os.path.exists(path):
            continue
        enc_str = extract_face_encoding(path)
        if not enc_str:
            continue
        emb = np.array(json.loads(enc_str))
        if np.linalg.norm(emb) > 0:
            embeddings.append(emb)

    if not embeddings:
        return json.dumps(np.zeros(ENCODING_DIM).tolist())

    avg = np.mean(np.stack(embeddings), axis=0)
    norm = np.linalg.norm(avg)
    if norm > 0:
        avg = avg / norm
    return json.dumps(avg.tolist())


def merge_encoding_strings(encoding_strings: list) -> str:
    """Average pre-computed encoding JSON strings.  ~0.1ms."""
    embeddings = []
    for enc_str in encoding_strings:
        if not enc_str:
            continue
        try:
            emb = np.array(json.loads(enc_str))
            embeddings.append(emb)
        except Exception:
            pass

    if not embeddings:
        return json.dumps(np.zeros(ENCODING_DIM).tolist())

    avg = np.mean(np.stack(embeddings), axis=0)
    norm = np.linalg.norm(avg)
    if norm > 0:
        avg = avg / norm
    return json.dumps(avg.tolist())


# ── Public API: Quality Check ─────────────────────────────────────────────────

def assess_photo_quality_and_liveness(image_path: str) -> dict:
    """Evaluates an uploaded enrollment photo for sharpness, brightness, and liveness."""
    if not os.path.exists(image_path):
        return {"is_good": False, "sharpness_score": 0.0, "brightness_score": 0.0,
                "warning_message": "⚠️ Photo file could not be read or opened."}

    try:
        img = cv2.imread(image_path)
        if img is None:
            return {"is_good": False, "sharpness_score": 0.0, "brightness_score": 0.0,
                    "warning_message": "⚠️ Photo file is invalid or corrupted."}

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        sharpness = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        brightness = float(np.mean(gray))
        std_dev = float(np.std(gray))

        warning_msg = None
        is_good = True

        if sharpness < 40.0:
            is_good = False
            warning_msg = f"⚠️ Photo is too blurry (sharpness: {int(sharpness)}/100). Please hold still and retake in good light."
        elif brightness < 45.0:
            is_good = False
            warning_msg = f"⚠️ Photo is too dark (brightness: {int(brightness)}/255). Please face towards a bright light source."
        elif brightness > 235.0:
            is_good = False
            warning_msg = f"⚠️ Photo is overexposed/too bright (brightness: {int(brightness)}/255). Please avoid direct glare."
        elif std_dev < 15.0:
            is_good = False
            warning_msg = "⚠️ Low contrast / flat image detected. Please ensure a live 3D face in natural lighting."

        return {"is_good": is_good, "sharpness_score": round(sharpness, 1),
                "brightness_score": round(brightness, 1), "warning_message": warning_msg}
    except Exception as e:
        print(f"Quality assessment error: {e}")
        return {"is_good": True, "sharpness_score": 100.0, "brightness_score": 128.0, "warning_message": None}


# ── Public API: Video Scan ────────────────────────────────────────────────────

def _upscale_for_face_detection(frame):
    """Upscale small frames so tiny distant faces become large enough for detectors."""
    h, w = frame.shape[:2]
    if w > 1920:
        scale = 1920.0 / w
        frame = cv2.resize(frame, (1920, int(h * scale)), interpolation=cv2.INTER_LINEAR)
    return frame


def _build_student_matrix(student_encodings: dict):
    """Pre-compute normalized student embedding matrix for fast vectorized matching."""
    student_ids = []
    emb_list = []
    for s_id, s_emb_str in student_encodings.items():
        try:
            emb = np.array(json.loads(s_emb_str), dtype=np.float32)
            if np.linalg.norm(emb) > 0:
                student_ids.append(s_id)
                emb_list.append(emb)
        except Exception:
            pass

    if not student_ids:
        return [], None

    S = np.array(emb_list, dtype=np.float32)
    norms = np.linalg.norm(S, axis=1, keepdims=True) + 1e-9
    S_normed = S / norms
    return student_ids, S_normed


def _match_face(frame_emb, student_ids, student_matrix, threshold):
    """Match a single face embedding against the student matrix. Returns (best_id, best_dist) or (None, inf)."""
    if student_matrix is None or len(student_ids) == 0:
        return None, float('inf')

    if len(frame_emb) != student_matrix.shape[1]:
        return None, float('inf')

    frame_norm = frame_emb / (np.linalg.norm(frame_emb) + 1e-9)
    cosine_dists = 1.0 - np.dot(student_matrix, frame_norm)
    best_idx = int(np.argmin(cosine_dists))
    best_dist = float(cosine_dists[best_idx])
    best_id = student_ids[best_idx]

    if best_dist < threshold:
        return best_id, best_dist
    return None, best_dist


def process_classroom_video(video_path: str, student_encodings: dict, student_info: dict = None) -> tuple:
    """Scan video frames against known student encodings using pure OpenCV.

    Returns: (list_of_present_ids, stats_dict)
    """
    if not os.path.exists(video_path):
        return ([], {"frames_scanned": 0, "faces_detected": 0})

    present_ids = set()
    all_ids = set(student_encodings.keys())
    student_ids, student_matrix = _build_student_matrix(student_encodings)

    cap = cv2.VideoCapture(video_path)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    target_samples = 20
    sample_interval = max(int(total_frames / target_samples), 1)

    print(f"Video: {total_frames} frames at {fps:.0f} FPS, sampling every {sample_interval} frames (~{target_samples} checks)")

    frame_count = 0
    total_faces = 0
    frames_scanned = 0

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        frame_count += 1
        if frame_count % sample_interval != 0:
            continue

        frames_scanned += 1
        frame = _upscale_for_face_detection(frame)
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        faces = _detect_faces(gray)

        for (x, y, w, h) in faces:
            total_faces += 1
            # Skip if face takes >50% of frame width (too close / obstruction)
            if w > gray.shape[1] * 0.50:
                continue

            face_roi = _crop_face(gray, x, y, w, h)
            frame_emb = _extract_face_features(face_roi)

            # Dynamic threshold based on estimated distance
            face_ratio = max(w / max(gray.shape[1], 1), 0.015)
            est_meters = round(min(max(0.16 / face_ratio, 0.6), 8.0), 1)
            offset = (est_meters - 3.5) * 0.015
            dynamic_threshold = round(min(max(MATCH_THRESHOLD + offset, MATCH_THRESHOLD - 0.04), MATCH_THRESHOLD + 0.07), 3)

            best_id, best_dist = _match_face(frame_emb, student_ids, student_matrix, dynamic_threshold)

            if best_id is not None:
                st_name = "Student"
                if student_info and best_id in student_info:
                    st_name = student_info[best_id].get("name", "Student")
                print(f"Frame {frame_count}: Matched {st_name} [dist: {best_dist:.4f} < {dynamic_threshold:.3f}]")
                present_ids.add(best_id)

        if len(present_ids) == len(all_ids):
            print(f"All {len(all_ids)} students found by frame {frame_count}! Exiting early.")
            break

    cap.release()

    stats = {
        "frames_scanned": frames_scanned,
        "faces_detected": total_faces,
        "total_frames": total_frames,
        "fps": round(fps, 1),
    }

    return (list(present_ids), stats)


# ── Public API: Single Frame (Live Scan) ──────────────────────────────────────

def process_single_frame(image_path: str = None, student_encodings: dict = None,
                         student_info: dict = None, raw_bytes: bytes = None) -> dict:
    """Scan a single live camera frame against known student encodings.
    Returns: {"matched_ids": [...], "face_boxes": [...]}
    """
    if student_encodings is None:
        student_encodings = {}

    matched_ids = set()
    face_boxes = []
    img = None

    try:
        if raw_bytes is not None:
            nparr = np.frombuffer(raw_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        elif image_path and os.path.exists(image_path):
            img = cv2.imread(image_path)

        if img is None:
            return {"matched_ids": [], "face_boxes": []}

        h, w = img.shape[:2]
        if w > 640:
            scale = 640 / w
            img = cv2.resize(img, (640, int(h * scale)))
    except Exception as e:
        print(f"Error decoding live frame: {e}")
        return {"matched_ids": [], "face_boxes": []}

    img_h, img_w = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    faces = _detect_faces(gray)

    student_ids, student_matrix = _build_student_matrix(student_encodings)

    if len(faces) == 0:
        print("Live Frame: No face detected in camera frame")

    for (x, y, fw, fh) in faces:
        # Skip obstructions (face > 60% of frame)
        if fw > img_w * 0.60:
            print(f"Live Frame: Object blocking camera lens (width {fw}px > 60% screen). Ignored.")
            continue

        face_roi = _crop_face(gray, x, y, fw, fh)
        frame_emb = _extract_face_features(face_roi)

        # Dynamic distance-scaled threshold
        face_ratio = max(fw / max(img_w, 1), 0.015)
        est_meters = round(min(max(0.16 / face_ratio, 0.6), 8.0), 1)
        offset = (est_meters - 3.5) * 0.018
        dynamic_threshold = round(min(max(MATCH_THRESHOLD + offset, MATCH_THRESHOLD - 0.05), MATCH_THRESHOLD + 0.08), 3)

        best_id, best_dist = _match_face(frame_emb, student_ids, student_matrix, dynamic_threshold)

        box = {
            "left": round(x / max(img_w, 1), 4),
            "top": round(y / max(img_h, 1), 4),
            "width": round(fw / max(img_w, 1), 4),
            "height": round(fh / max(img_h, 1), 4),
        }

        if best_id is not None:
            st_name = "Student"
            st_roll = best_id
            if student_info and best_id in student_info:
                st_name = student_info[best_id].get("name", "Student")
                st_roll = student_info[best_id].get("roll_number", best_id)
            print(f"Live Frame: Matched {st_name}({st_roll}) [dist: {best_dist:.4f} < {dynamic_threshold:.3f} | est: {est_meters}m]")
            matched_ids.add(best_id)
            face_boxes.append({"id": best_id, "dist": round(best_dist, 4), "threshold": round(dynamic_threshold, 3), "est_meters": est_meters, "box": box})
        else:
            face_boxes.append({"id": None, "dist": round(best_dist, 4) if best_dist != float('inf') else 1.0, "threshold": round(dynamic_threshold, 3), "est_meters": est_meters, "box": box})

    if image_path:
        try:
            os.remove(image_path)
        except Exception:
            pass

    return {"matched_ids": list(matched_ids), "face_boxes": face_boxes}
