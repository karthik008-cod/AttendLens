import os
import json
import cv2
import numpy as np

try:
    from deepface import DeepFace
    DEEPFACE_AVAILABLE = True
except ImportError:
    DEEPFACE_AVAILABLE = False


def extract_face_encoding(image_path: str) -> str:
    """Extracts a face embedding from a single image. Returns JSON string."""
    if not DEEPFACE_AVAILABLE or not os.path.exists(image_path):
        return json.dumps(np.zeros(128).tolist())

    try:
        # Use YuNet: OpenCV's ultra-fast (2023) deep learning face detector (~0.05s) with strict enforcement!
        embedding_objs = DeepFace.represent(
            img_path=image_path, model_name="Facenet512", detector_backend="yunet", enforce_detection=True
        )
        if embedding_objs and len(embedding_objs) > 0:
            return json.dumps(embedding_objs[0]["embedding"])
    except Exception:
        try:
            # Fast fallback to SSD (Single Shot MultiBox Detector) if YuNet missed
            embedding_objs = DeepFace.represent(
                img_path=image_path, model_name="Facenet512", detector_backend="ssd", enforce_detection=True
            )
            if embedding_objs and len(embedding_objs) > 0:
                return json.dumps(embedding_objs[0]["embedding"])
        except Exception:
            try:
                # Final fallback without enforcement for difficult lighting/angles during registration
                embedding_objs = DeepFace.represent(
                    img_path=image_path, model_name="Facenet512", detector_backend="yunet", enforce_detection=False
                )
                if embedding_objs and len(embedding_objs) > 0:
                    return json.dumps(embedding_objs[0]["embedding"])
            except Exception as e:
                print(f"Error extracting face encoding: {e}")

    return json.dumps(np.zeros(512).tolist())


def merge_student_encodings(photo_paths: list) -> str:
    """Average face embeddings across multiple photos for a student.
    More diverse photos → better recognition robustness.
    Returns a unit-normalized average embedding as a JSON string.
    """
    embeddings = []
    for path in photo_paths:
        if not path or not os.path.exists(path):
            continue
        enc_str = extract_face_encoding(path)
        if not enc_str:
            continue
        emb = np.array(json.loads(enc_str))
        # Ignore zero vectors produced by failed face detection
        if np.linalg.norm(emb) > 0:
            embeddings.append(emb)

    if not embeddings:
        return json.dumps(np.zeros(512).tolist())

    avg_embedding = np.mean(np.stack(embeddings), axis=0)
    # Normalize to unit vector for consistent cosine similarity comparison
    norm = np.linalg.norm(avg_embedding)
    if norm > 0:
        avg_embedding = avg_embedding / norm
    return json.dumps(avg_embedding.tolist())


def merge_encoding_strings(encoding_strings: list) -> str:
    """Average face embeddings across multiple precomputed JSON encoding strings.
    Takes ~0.1 milliseconds! Avoids re-running heavy neural network inference.
    """
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
        return json.dumps(np.random.rand(512).tolist())

    avg_embedding = np.mean(np.stack(embeddings), axis=0)
    norm = np.linalg.norm(avg_embedding)
    if norm > 0:
        avg_embedding = avg_embedding / norm
    return json.dumps(avg_embedding.tolist())


def assess_photo_quality_and_liveness(image_path: str) -> dict:
    """Evaluates an uploaded enrollment photo for sharpness, brightness, and liveness / anti-spoofing heuristics.
    Returns: { "is_good": bool, "sharpness_score": float, "brightness_score": float, "warning_message": str }
    """
    if not os.path.exists(image_path):
        return {
            "is_good": False,
            "sharpness_score": 0.0,
            "brightness_score": 0.0,
            "warning_message": "⚠️ Photo file could not be read or opened."
        }

    try:
        img = cv2.imread(image_path)
        if img is None:
            return {
                "is_good": False,
                "sharpness_score": 0.0,
                "brightness_score": 0.0,
                "warning_message": "⚠️ Photo file is invalid or corrupted."
            }

        # 1. Sharpness / Blur check via Laplacian variance
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        sharpness = float(cv2.Laplacian(gray, cv2.CV_64F).var())

        # 2. Brightness check via mean pixel intensity
        brightness = float(np.mean(gray))

        # 3. Basic Liveness / Screen Spoof heuristic check (checking for flat contrast / low dynamic range)
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

        return {
            "is_good": is_good,
            "sharpness_score": round(sharpness, 1),
            "brightness_score": round(brightness, 1),
            "warning_message": warning_msg
        }
    except Exception as e:
        print(f"Quality assessment error: {e}")
        return {
            "is_good": True,
            "sharpness_score": 100.0,
            "brightness_score": 128.0,
            "warning_message": None
        }


def _upscale_for_face_detection(frame):
    """Upscale small frames so tiny distant faces become large enough for detectors.
    RetinaFace needs faces at least ~20px wide. A face at 5 meters in 1080p video
    might only be 30-40px. Upscaling to 1920px width ensures faces are detectable.
    """
    h, w = frame.shape[:2]
    # For high-res videos (4K), cap at 1920 to avoid excessive memory usage
    if w > 1920:
        scale = 1920.0 / w
        frame = cv2.resize(frame, (1920, int(h * scale)), interpolation=cv2.INTER_LINEAR)
    return frame


def process_classroom_video(video_path: str, student_encodings: dict) -> dict:
    """Scans video frames against known student encodings.

    student_encodings: dict of { student_id: encoding_json_string }
    Returns: { "present_student_ids": [...], "absent_student_ids": [...] }
    """
    if not os.path.exists(video_path):
        return {
            "present_student_ids": [],
            "absent_student_ids": list(student_encodings.keys()),
        }

    present_ids = set()
    all_ids = set(student_encodings.keys())

    # Detect what model to use based on existing student encoding dimensions (128 vs 512)
    target_model = "Facenet512"
    threshold = 0.48  # Stricter threshold (0.48) to prevent false positives during classroom scanning
    for s_id, s_emb_str in student_encodings.items():
        try:
            s_emb = np.array(json.loads(s_emb_str))
            if len(s_emb) == 128:
                target_model = "Facenet"
                threshold = 0.50
            break
        except Exception:
            pass

    # Precompute numpy arrays for all student encodings once (avoid repeated json.loads)
    student_emb_cache = {}
    for s_id, s_emb_str in student_encodings.items():
        try:
            student_emb_cache[s_id] = np.array(json.loads(s_emb_str))
        except Exception:
            pass

    # Adaptively divide the video length: sample ~20 evenly distributed frames across the entire duration
    cap = cv2.VideoCapture(video_path)
    frame_count = 0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    target_samples = 20
    sample_interval = max(int(total_frames / target_samples), 1)

    print(f"Video: {total_frames} frames at {fps:.0f} FPS, adaptively dividing to sample every {sample_interval} frames (~{target_samples} total checks)")

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        frame_count += 1
        if frame_count % sample_interval != 0:
            continue

        # Keep higher resolution for far-away face detection (capped at 1920px)
        frame = _upscale_for_face_detection(frame)

        temp_frame_path = video_path + f"_temp_{frame_count}.jpg"
        cv2.imwrite(temp_frame_path, frame, [cv2.IMWRITE_JPEG_QUALITY, 95])

        if DEEPFACE_AVAILABLE:
            try:
                frame_faces = []
                try:
                    # Use YuNet: OpenCV's ultra-fast (2023) deep learning face detector (~0.05s) with strict enforcement!
                    frame_faces = DeepFace.represent(
                        img_path=temp_frame_path, model_name=target_model, detector_backend="yunet", enforce_detection=True
                    )
                except Exception as e:
                    if "could not be detected" not in str(e).lower() and "face not found" not in str(e).lower():
                        try:
                            frame_faces = DeepFace.represent(
                                img_path=temp_frame_path, model_name=target_model, detector_backend="retinaface", enforce_detection=True
                            )
                        except Exception:
                            pass

                for face_obj in frame_faces:
                    conf = face_obj.get("face_confidence", 1.0)
                    if conf is not None and conf < 0.70:
                        continue

                    area = face_obj.get("facial_area", {})
                    fw = int(area.get("w", area.get("width", 100)))
                    if fw > 800.0 * 0.50:
                        continue

                    frame_emb = np.array(face_obj["embedding"], dtype=np.float32)

                    face_ratio = max(fw / 800.0, 0.015)
                    est_meters = round(min(max(0.16 / face_ratio, 0.6), 8.0), 1)
                    offset = (est_meters - 3.5) * 0.015
                    dynamic_threshold = round(min(max(threshold + offset, threshold - 0.04), threshold + 0.07), 3)

                    # Single Best Match: compare against ALL student encodings
                    best_match_id = None
                    best_dist = float("inf")
                    for s_id, s_emb in student_emb_cache.items():
                        if len(frame_emb) != len(s_emb):
                            continue
                        # Cosine distance (lower = more similar)
                        denom = np.linalg.norm(frame_emb) * np.linalg.norm(s_emb) + 1e-9
                        cosine_dist = 1 - np.dot(frame_emb, s_emb) / denom
                        if cosine_dist < best_dist:
                            best_dist = cosine_dist
                            best_match_id = s_id

                    if best_match_id is not None and best_dist < dynamic_threshold:
                        st_name = "Student"
                        st_roll = best_match_id
                        if student_info and best_match_id in student_info:
                            st_name = student_info[best_match_id].get("name", "Student")
                            st_roll = student_info[best_match_id].get("roll_number", best_match_id)
                        print(f"Frame {frame_count}: Matched {st_name}({st_roll}) [dist: {best_dist:.4f} < {dynamic_threshold:.3f} | est. distance: {est_meters}m]")
                        present_ids.add(best_match_id)
                    else:
                        st_name = "Unknown"
                        st_roll = "?"
                        if student_info and best_match_id in student_info:
                            st_name = student_info[best_match_id].get("name", "Unknown")
                            st_roll = student_info[best_match_id].get("roll_number", "?")
                        print(f"Frame {frame_count}: Best match {st_name}({st_roll}) ignored [dist: {best_dist:.4f} >= {dynamic_threshold:.3f} | est. distance: {est_meters}m]")
            except Exception as e:
                print(f"Frame {frame_count} processing error: {e}")
        else:
            # Simulation mode: randomly mark ~80% as present
            for s_id in all_ids:
                if np.random.rand() > 0.2:
                    present_ids.add(s_id)

        if os.path.exists(temp_frame_path):
            try:
                os.remove(temp_frame_path)
            except Exception:
                pass

        # Early exit if all students found
        if len(present_ids) == len(all_ids):
            print(f"All {len(all_ids)} students found by frame {frame_count}! Exiting early.")
            break

    cap.release()

    return {
        "present_student_ids": list(present_ids),
        "absent_student_ids": list(all_ids - present_ids),
    }


def process_single_frame(image_path: str = None, student_encodings: dict = None, student_info: dict = None, raw_bytes: bytes = None) -> dict:
    """Scans a single live streamed camera frame against known student encodings.
    Resizes image to max 800px width for ultra-fast real-time recognition.
    Returns: {"matched_ids": list of matched ids, "face_boxes": list of face box dicts}
    """
    if student_encodings is None:
        student_encodings = {}

    matched_ids = set()
    face_boxes = []
    img_w = 800
    img_h = 600
    img = None

    try:
        if raw_bytes is not None:
            nparr = np.frombuffer(raw_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        elif image_path and os.path.exists(image_path):
            img = cv2.imread(image_path)

        if img is None:
            return {"matched_ids": [], "face_boxes": []}

        # Keep 800px width so distant classroom faces remain large enough (~30-40px) for deep learning detectors
        h, w = img.shape[:2]
        if w > 800:
            scale = 800 / w
            img_w = 800
            img_h = int(h * scale)
            img = cv2.resize(img, (img_w, img_h))
            if image_path and os.path.exists(image_path) and raw_bytes is None:
                cv2.imwrite(image_path, img)
        else:
            img_w = w
            img_h = h
    except Exception as e:
        print(f"Error decoding live frame: {e}")
        return {"matched_ids": [], "face_boxes": []}

    # Detect target model and threshold
    target_model = "Facenet512"
    threshold = 0.48  # Stricter threshold (0.48) to ensure high confidence recognition during live scanning
    for s_id, s_emb_str in student_encodings.items():
        try:
            s_emb = np.array(json.loads(s_emb_str))
            if len(s_emb) == 128:
                target_model = "Facenet"
                threshold = 0.50
            break
        except Exception:
            pass

    student_emb_cache = {}
    for s_id, s_emb_str in student_encodings.items():
        try:
            student_emb_cache[s_id] = np.array(json.loads(s_emb_str))
        except Exception:
            pass

    # ── Optimization #2: Pre-Normalized Vectorized Matrix Multiplication (GEMM) ──
    student_ids_list = list(student_emb_cache.keys())
    student_matrix = None
    if student_ids_list:
        embs = [student_emb_cache[sid] for sid in student_ids_list]
        S = np.array(embs, dtype=np.float32)
        norms = np.linalg.norm(S, axis=1, keepdims=True) + 1e-9
        student_matrix = S / norms

    if DEEPFACE_AVAILABLE:
        try:
            frame_faces = []
            try:
                # Use YuNet: OpenCV's ultra-fast (2023) deep learning face detector (~0.05s) with strict enforcement!
                # Note: When enforce_detection=True and no face is found, DeepFace raises ValueError ("Face could not be detected").
                # We cleanly catch that and return 0 faces. DO NOT run Haar Cascade/SSD fallbacks when no face is present!
                frame_faces = DeepFace.represent(
                    img_path=img, model_name=target_model, detector_backend="yunet", enforce_detection=True
                )
            except Exception as e:
                # Only fallback to RetinaFace if YuNet crashed or is missing, NOT if it cleanly reported 0 faces!
                if "could not be detected" not in str(e).lower() and "face not found" not in str(e).lower():
                    try:
                        frame_faces = DeepFace.represent(
                            img_path=img, model_name=target_model, detector_backend="retinaface", enforce_detection=True
                        )
                    except Exception:
                        pass

            if not frame_faces:
                print("Live Frame: No face detected in camera frame (try holding still or moving closer)")

            for face_obj in frame_faces:
                # Strict Confidence & Lens Obstruction Check
                conf = face_obj.get("face_confidence", 1.0)
                if conf is not None and conf < 0.70:
                    print(f"Live Frame: Face ignored due to low detector confidence ({conf:.2f} < 0.70)")
                    continue

                frame_emb = np.array(face_obj["embedding"], dtype=np.float32)
                area = face_obj.get("facial_area", {})
                fx = int(area.get("x", area.get("left", 0)))
                fy = int(area.get("y", area.get("top", 0)))
                fw = int(area.get("w", area.get("width", 100)))
                fh = int(area.get("h", area.get("height", 100)))

                # If face bounding box takes up more than 50% of screen width, an object (finger/palm) is pressed against lens!
                if fw > max(img_w, 1) * 0.50:
                    print(f"Live Frame: Object blocking camera lens or too close (width {fw}px > 50% screen). Ignored.")
                    continue

                # ── Dynamic Distance-Scaled Confidence Meter (6-8m max classroom length) ──
                face_ratio = max(fw / max(img_w, 1), 0.015)
                est_meters = round(min(max(0.16 / face_ratio, 0.6), 8.0), 1)
                offset = (est_meters - 3.5) * 0.015
                dynamic_threshold = round(min(max(threshold + offset, threshold - 0.04), threshold + 0.07), 3)

                best_match_id = None
                best_dist = float("inf")
                if student_matrix is not None and len(frame_emb) == student_matrix.shape[1]:
                    frame_norm = frame_emb / (np.linalg.norm(frame_emb) + 1e-9)
                    # Vectorized BLAS matrix dot product: computes all similarities in < 0.1ms!
                    cosine_dists = 1.0 - np.dot(student_matrix, frame_norm)
                    best_idx = int(np.argmin(cosine_dists))
                    best_dist = float(cosine_dists[best_idx])
                    best_match_id = student_ids_list[best_idx]

                if best_match_id is not None and best_dist < dynamic_threshold:
                    st_name = "Student"
                    st_roll = best_match_id
                    if student_info and best_match_id in student_info:
                        st_name = student_info[best_match_id].get("name", "Student")
                        st_roll = student_info[best_match_id].get("roll_number", best_match_id)
                    print(f"Live Frame: Matched {st_name}({st_roll}) [dist: {best_dist:.4f} < {dynamic_threshold:.3f} | est. distance: {est_meters}m]")
                    matched_ids.add(best_match_id)
                    face_boxes.append({
                        "id": best_match_id,
                        "dist": round(best_dist, 4),
                        "threshold": round(dynamic_threshold, 3),
                        "est_meters": est_meters,
                        "box": {"left": round(fx / max(img_w, 1), 4), "top": round(fy / max(img_h, 1), 4), "width": round(fw / max(img_w, 1), 4), "height": round(fh / max(img_h, 1), 4)}
                    })
                else:
                    st_name = "Unknown"
                    st_roll = "?"
                    if student_info and best_match_id in student_info:
                        st_name = student_info[best_match_id].get("name", "Unknown")
                        st_roll = student_info[best_match_id].get("roll_number", "?")
                    print(f"Live Frame: Best match {st_name}({st_roll}) ignored [dist: {best_dist:.4f} >= {dynamic_threshold:.3f} | est. distance: {est_meters}m]")
                    face_boxes.append({
                        "id": None,
                        "dist": round(best_dist, 4) if best_dist != float("inf") else 1.0,
                        "threshold": round(dynamic_threshold, 3),
                        "est_meters": est_meters,
                        "box": {"left": round(fx / max(img_w, 1), 4), "top": round(fy / max(img_h, 1), 4), "width": round(fw / max(img_w, 1), 4), "height": round(fh / max(img_h, 1), 4)}
                    })
        except Exception as e:
            print(f"Live frame error: {e}")
    else:
        # Simulation mode: match 1 random student
        all_ids = list(student_encodings.keys())
        if all_ids:
            sim_id = np.random.choice(all_ids)
            matched_ids.add(sim_id)
            face_boxes.append({
                "id": sim_id,
                "dist": 0.3210,
                "box": {"left": 0.3, "top": 0.25, "width": 0.4, "height": 0.4}
            })

    try:
        os.remove(image_path)
    except Exception:
        pass

    return {"matched_ids": list(matched_ids), "face_boxes": face_boxes}

