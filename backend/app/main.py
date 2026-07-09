from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.db.database import engine, Base
from app.api.endpoints import router as api_router
from app.api.invite_page import invite_router

# Auto-create all tables (new tables added: student_photos, new columns on existing tables)
# NOTE: If upgrading an existing DB, delete backend/data/attendlens.db to regenerate schema.
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="AttendLens API",
    description="AI-powered classroom attendance with facial recognition",
    version="2.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix="/api")
app.include_router(invite_router)  # Serves /invite/{class_id} at root level


@app.get("/")
def root():
    return {"message": "AttendLens API v2.0 Running", "docs": "/docs", "status": "online"}
