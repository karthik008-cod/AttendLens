from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.db.database import engine, Base
from app.api.endpoints import router as api_router

# Create SQLite database tables automatically
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="AttendLens API",
    description="Lightweight backend for AttendLens classroom attendance",
    version="1.0.0"
)

# Allow mobile devices on local network to access API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix="/api")

@app.get("/")
def root():
    return {"message": "AttendLens API Running", "docs": "/docs", "status": "online"}
