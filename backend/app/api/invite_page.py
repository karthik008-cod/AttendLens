from fastapi import APIRouter, Depends
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.db.models import Classroom

invite_router = APIRouter()


@invite_router.get("/invite/{class_id}", response_class=HTMLResponse)
def student_invite_page(class_id: int, db: Session = Depends(get_db)):
    """Serves a mobile-friendly HTML form for student self-registration."""
    classroom = db.query(Classroom).filter(Classroom.id == class_id).first()
    class_name = classroom.name if classroom else f"Class #{class_id}"
    section_label = f" — Section {classroom.section}" if classroom and classroom.section else ""
    required_photos = classroom.required_photos if classroom else 1

    return HTMLResponse(content=_build_html(class_id, class_name + section_label, required_photos))


def _build_html(class_id: int, class_name: str, required_photos: int) -> str:
    # Embed Python values as JS constants (safe, no JS-brace conflicts)
    js_data = (
        f"const REQUIRED = {required_photos};\n"
        f"const CLASS_ID = {class_id};\n"
        f'const API_BASE = window.location.origin + "/api";\n'
    )

    css = """
      * { margin:0; padding:0; box-sizing:border-box; }
      body { background:#0B0F19; color:#F8FAFC; font-family:'Segoe UI',sans-serif;
             min-height:100vh; display:flex; align-items:center; justify-content:center; padding:20px; }
      .card { background:#151B2B; border:1.5px solid rgba(255,255,255,0.1); border-radius:24px;
              padding:36px 32px; max-width:480px; width:100%; box-shadow:0 20px 60px rgba(0,0,0,0.5); }
      .logo { display:flex; align-items:center; gap:12px; margin-bottom:24px; }
      .logo-icon { width:48px; height:48px; background:linear-gradient(135deg,#6366F1,#8B5CF6);
                   border-radius:12px; display:flex; align-items:center; justify-content:center; font-size:24px; }
      h1 { font-size:22px; font-weight:700; }
      .subtitle { color:#94A3B8; font-size:14px; margin-top:2px; }
      .badge { background:rgba(99,102,241,0.15); border:1px solid rgba(99,102,241,0.4);
               border-radius:20px; padding:8px 16px; display:inline-block; font-size:13px;
               color:#A5B4FC; margin-bottom:24px; }
      label { display:block; font-size:13px; color:#94A3B8; margin-bottom:6px; font-weight:600; }
      input[type=text] { width:100%; background:#0B0F19; border:1.5px solid rgba(255,255,255,0.1);
                          border-radius:12px; padding:14px 16px; color:#F8FAFC; font-size:15px;
                          margin-bottom:20px; outline:none; transition:border-color .2s; }
      input[type=text]:focus { border-color:#6366F1; }
      .tip { background:rgba(6,182,212,0.1); border:1px solid rgba(6,182,212,0.3);
             border-radius:12px; padding:12px 16px; margin-bottom:20px;
             font-size:13px; color:#67E8F9; line-height:1.6; }
      .photo-grid { display:grid; gap:10px; margin-bottom:20px; }
      .slot { background:#0B0F19; border:2px dashed rgba(99,102,241,0.4); border-radius:12px;
              aspect-ratio:1; display:flex; flex-direction:column; align-items:center;
              justify-content:center; cursor:pointer; font-size:26px; transition:all .2s;
              user-select:none; -webkit-tap-highlight-color:transparent; }
      .slot:hover { border-color:#6366F1; }
      .slot.filled { border-color:#10B981; border-style:solid; background:rgba(16,185,129,0.08); }
      .slot span { font-size:11px; color:#94A3B8; margin-top:6px; }
      .slot.filled span { color:#10B981; }
      .btn { width:100%; background:linear-gradient(135deg,#6366F1,#8B5CF6); border:none;
             border-radius:14px; padding:16px; font-size:16px; font-weight:700;
             color:white; cursor:pointer; transition:opacity .2s; margin-top:4px; }
      .btn:hover { opacity:.9; }
      .btn:disabled { opacity:.4; cursor:not-allowed; }
      #successSection { display:none; text-align:center; padding:20px; }
      .check { font-size:64px; margin-bottom:12px; }
      #successSection h2 { font-size:22px; font-weight:700; margin-bottom:8px; color:#10B981; }
      #successSection p { color:#94A3B8; font-size:14px; line-height:1.6; }
    """

    js_logic = """
      let photos = new Array(REQUIRED).fill(null);
      let currentSlot = 0;
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = 'image/*';
      input.capture = 'user';

      function buildGrid() {
        const grid = document.getElementById('photoGrid');
        const cols = Math.min(REQUIRED, 3);
        grid.style.gridTemplateColumns = `repeat(${cols}, 1fr)`;
        grid.innerHTML = '';
        for (let i = 0; i < REQUIRED; i++) {
          const slot = document.createElement('div');
          slot.className = 'slot' + (photos[i] ? ' filled' : '');
          slot.innerHTML = (photos[i] ? '✅' : '📷') + '<span>' + (photos[i] ? 'Photo ' + (i+1) : 'Tap ' + (i+1)) + '</span>';
          slot.onclick = () => { currentSlot = i; input.click(); };
          grid.appendChild(slot);
        }
      }

      input.onchange = (e) => {
        const file = e.target.files[0];
        if (file) {
          photos[currentSlot] = file;
          buildGrid();
          // Auto-advance to next empty slot
          const next = photos.indexOf(null);
          if (next !== -1) currentSlot = next;
        }
        input.value = '';
      };

      buildGrid();

      document.getElementById('regForm').onsubmit = async (e) => {
        e.preventDefault();
        const name = document.getElementById('name').value.trim();
        const roll = document.getElementById('roll').value.trim();
        if (!name || !roll) { alert('Please fill all fields!'); return; }
        const valid = photos.filter(Boolean);
        if (valid.length < REQUIRED) { alert('Please capture all ' + REQUIRED + ' photo(s)!'); return; }

        const btn = document.getElementById('submitBtn');
        btn.disabled = true;
        btn.textContent = '⏳ Uploading...';

        try {
          const fd = new FormData();
          fd.append('name', name);
          fd.append('roll_number', roll);
          fd.append('classroom_id', CLASS_ID);
          fd.append('photo', valid[0]);
          const res = await fetch(API_BASE + '/students', { method: 'POST', body: fd });
          if (!res.ok) throw new Error(await res.text());
          const student = await res.json();

          for (let i = 1; i < valid.length; i++) {
            const fd2 = new FormData();
            fd2.append('photo', valid[i]);
            await fetch(API_BASE + '/students/' + student.id + '/photos', { method: 'POST', body: fd2 });
          }

          document.getElementById('formSection').style.display = 'none';
          document.getElementById('successSection').style.display = 'block';
        } catch (err) {
          btn.disabled = false;
          btn.textContent = '📤 Submit Registration';
          alert('Error: ' + err.message);
        }
      };
    """

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <title>AttendLens — Student Registration</title>
  <style>{css}</style>
</head>
<body>
<div class="card">
  <div id="formSection">
    <div class="logo">
      <div class="logo-icon">🎥</div>
      <div><h1>AttendLens</h1><div class="subtitle">Student Registration</div></div>
    </div>
    <div class="badge">📚 {class_name}</div>
    <div class="tip">
      📸 Upload <strong>{required_photos} clear face photo(s)</strong> in good lighting.<br>
      Face the camera directly — no sunglasses or hats please!
    </div>
    <form id="regForm">
      <label>Full Name</label>
      <input type="text" id="name" placeholder="Enter your full name" required/>
      <label>Roll Number / Student ID</label>
      <input type="text" id="roll" placeholder="e.g. CS-001" required/>
      <label>Face Photos ({required_photos} required)</label>
      <div class="photo-grid" id="photoGrid"></div>
      <button type="submit" class="btn" id="submitBtn">📤 Submit Registration</button>
    </form>
  </div>
  <div id="successSection">
    <div class="check">✅</div>
    <h2>You're Enrolled!</h2>
    <p>Your face has been registered for<br><strong>{class_name}</strong>.<br><br>
    You will now be automatically recognized during attendance scans. You may close this page.</p>
  </div>
</div>
<script>
  {js_data}
  {js_logic}
</script>
</body>
</html>"""
