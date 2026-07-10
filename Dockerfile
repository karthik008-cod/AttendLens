# Root Dockerfile for Hugging Face Spaces & Cloud Deployments
FROM python:3.10-slim

# Prevent Python from writing pyc files and enable unbuffered logging
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive

# Install system dependencies required by OpenCV and numerical libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy backend dependencies and install
COPY backend/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir tensorflow-cpu tf-keras opencv-python-headless && \
    pip install --no-cache-dir --no-deps deepface && \
    pip install --no-cache-dir -r requirements.txt

# Copy backend source code
COPY backend/ ./backend/

# Set working directory to backend where app.main resides
WORKDIR /app/backend
RUN mkdir -p uploads && chmod 777 uploads

# Create non-root user for cloud security (required by HuggingFace Spaces)
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Expose standard ports (7860 for HuggingFace Spaces, 8000 for local/Railway)
EXPOSE 7860 8000

# Run Uvicorn production server dynamically on $PORT (or default 7860 for HF Spaces)
CMD ["sh", "-c", "python -m uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-7860}"]
