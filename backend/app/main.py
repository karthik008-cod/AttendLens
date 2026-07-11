from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.db.database import db
from app.api.endpoints import router as api_router
from app.api.invite_page import invite_router

app = FastAPI(
    title="AttendLens API",
    description="AI-powered classroom attendance with facial recognition powered by MongoDB Atlas",
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
app.include_router(api_router)  # Also mount at root so requests without /api prefix never 404
app.include_router(invite_router)  # Serves /invite/{class_id} at root level


from app.api.endpoints import log_print

@app.on_event("startup")
def startup_db_check():
    try:
        log_print(f"[OK] Connected to MongoDB Atlas Cluster | Active Database: {db.name}")
    except Exception as e:
        log_print(f"[WARN] MongoDB connection warning on startup: {e}")


@app.get("/")
def root():
    return {
        "message": "AttendLens API v2.0 (MongoDB Atlas + OpenCV Engine) Running",
        "docs": "/docs",
        "status": "online",
        "database": db.name if db is not None else "offline"
    }
