---
title: AttendLens-Backend
emoji: 🎓
colorFrom: blue
colorTo: indigo
sdk: docker
pinned: false
---

# AttendLens AI Backend API 🚀

An advanced, enterprise-grade AI Attendance Tracking & Management API powered by **FastAPI**, **MongoDB Atlas Cloud Cluster**, and **OpenCV / dlib Face Recognition Engine**.

## Features 🌟
- **Real-Time Video & Frame Scanning**: Processes classroom feeds in milliseconds using optimized zero-disk-I/O memory streaming.
- **Persistent Cloud Database (MongoDB Atlas)**: Stores teacher profiles, classrooms, student encodings (`512-dim / 128-dim average embeddings`), and daily attendance status (`P/A/L`).
- **Auto-Increment Integer IDs**: Guarantees 100% zero-crash compatibility with Flutter / Dart mobile client applications.
- **Excel Report Generator**: Automatically formats and exports multi-colored, production-ready `.xlsx` attendance spreadsheets.
- **Interactive API Documentation**: Access `/docs` (Swagger UI) directly when deployed on Hugging Face Spaces or custom endpoints.

## Endpoints Summary 📡
- `POST /auth/signup` / `POST /auth/login` — Teacher authentication.
- `GET/POST/PUT/DELETE /classes` — Classroom management (`name, subject, section, required photos`).
- `GET/POST/DELETE /students` — Student enrollment with instant photo quality checks (`blur, liveness heuristics`) and background embedding extraction.
- `POST /attendance/scan` & `POST /attendance/stream-frame` — Live classroom attendance scanning.
- `GET /reports/class/{id}/excel` — Download live spreadsheet reports.
- `GET /analytics/class/{id}` & `GET /analytics/student/{id}` — Deep attendance trend analytics.
