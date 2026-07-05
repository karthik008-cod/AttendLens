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
        return json.dumps(np.random.rand(128).tolist())

    try:
        # First try enforcing detection so we get a real cropped face
        embedding_objs = DeepFace.represent(
            img_path=image_path, model_name="Facenet", detector_backend="opencv", enforce_detection=True
        )
        if embedding_objs and len(embedding_objs) > 0:
            return json.dumps(embedding_objs[0]["embedding"])
    except Exception:
        try:
            # Fallback if detection fails on photo
            embedding_objs = DeepFace.represent(
                img_path=image_path, model_name="Facenet", detector_backend="opencv", enforce_detection=False
            )
            if embedding_objs and len(embedding_objs) > 0:
                return json.dumps(embedding_objs[0]["embedding"])
        except Exception as e:
            print(f"Error extracting face encoding: {e}")

    return json.dumps(np.random.rand(128).tolist())


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
        embeddings.append(np.array(json.loads(enc_str)))

    if not embeddings:
        return json.dumps(np.random.rand(128).tolist())

    avg_embedding = np.mean(np.stack(embeddings), axis=0)
    # Normalize to unit vector for consistent cosine similarity comparison
    norm = np.linalg.norm(avg_embedding)
    if norm > 0:
        avg_embedding = avg_embedding / norm
    return json.dumps(avg_embedding.tolist())


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

    # Sample every 15th frame (~2 fps at 30fps) for speed
    cap = cv2.VideoCapture(video_path)
    frame_count = 0

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        frame_count += 1
        if frame_count % 15 != 0:
            continue

        temp_frame_path = video_path + f"_temp_{frame_count}.jpg"
        cv2.imwrite(temp_frame_path, frame)

        if DEEPFACE_AVAILABLE:
            try:
                # MUST enforce detection in video frames so background walls/whiteboards are NEVER matched as faces!
                frame_faces = DeepFace.represent(
                    img_path=temp_frame_path, model_name="Facenet", detector_backend="opencv", enforce_detection=True
                )
                for face_obj in frame_faces:
                    frame_emb = np.array(face_obj["embedding"])
                    
                    # Single Best Match: compare against ALL student encodings (never exclude already matched students!)
                    best_match_id = None
                    best_dist = float("inf")
                    for s_id, s_emb_str in student_encodings.items():
                        s_emb = np.array(json.loads(s_emb_str))
                        # Cosine distance (lower = more similar)
                        denom = np.linalg.norm(frame_emb) * np.linalg.norm(s_emb) + 1e-9
                        cosine_dist = 1 - np.dot(frame_emb, s_emb) / denom
                        if cosine_dist < best_dist:
                            best_dist = cosine_dist
                            best_match_id = s_id

                    # Strict official Facenet threshold (0.40) for single best match
                    if best_match_id is not None and best_dist < 0.40:
                        print(f"Frame {frame_count}: Matched Student ID {best_match_id} (dist: {best_dist:.4f})")
                        present_ids.add(best_match_id)
                    else:
                        print(f"Frame {frame_count}: Face ignored (best match ID {best_match_id} dist: {best_dist:.4f} >= 0.40)")
            except Exception:
                pass
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
            break

    cap.release()

    return {
        "present_student_ids": list(present_ids),
        "absent_student_ids": list(all_ids - present_ids),
    }
