const faceapi = require('@vladmandic/face-api');
const canvas = require('canvas');
const http = require('http');
const fs = require('fs');
const path = require('path');

// Monkey patch face-api with node canvas
const { Canvas, Image, ImageData } = canvas;
faceapi.env.monkeyPatch({ Canvas, Image, ImageData });

const MODELS_DIR = path.join(__dirname, 'models');
const PORT = 8001;

// In-memory cache for student face descriptors
const studentDescriptorCache = new Map();

async function loadModels() {
  console.log('⚡ [FastEngine] Loading neural network models from:', MODELS_DIR);
  await faceapi.nets.tinyFaceDetector.loadFromDisk(MODELS_DIR);
  await faceapi.nets.ssdMobilenetv1.loadFromDisk(MODELS_DIR);
  await faceapi.nets.faceLandmark68Net.loadFromDisk(MODELS_DIR);
  await faceapi.nets.faceRecognitionNet.loadFromDisk(MODELS_DIR);
  console.log('✅ [FastEngine] Models loaded successfully! Ready for lightning-fast scanning.');
}

async function getStudentDescriptor(studentId, photoPath) {
  if (!photoPath || !fs.existsSync(photoPath)) return null;
  if (studentDescriptorCache.has(studentId)) {
    return studentDescriptorCache.get(studentId);
  }

  try {
    const img = await canvas.loadImage(photoPath);
    // Try TinyFaceDetector first for speed, fallback to SSD Mobilenet if needed
    let detection = await faceapi.detectSingleFace(img, new faceapi.TinyFaceDetectorOptions())
      .withFaceLandmarks()
      .withFaceDescriptor();

    if (!detection) {
      detection = await faceapi.detectSingleFace(img, new faceapi.SsdMobilenetv1Options())
        .withFaceLandmarks()
        .withFaceDescriptor();
    }

    if (detection) {
      studentDescriptorCache.set(studentId, detection.descriptor);
      console.log(`🧠 [FastEngine] Cached face descriptor for Student ID ${studentId}`);
      return detection.descriptor;
    }
  } catch (err) {
    console.error(`❌ [FastEngine] Error processing photo for Student ${studentId}:`, err.message);
  }
  return null;
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'POST' && req.url === '/recognize') {
    let body = '';
    req.on('data', chunk => { body += chunk.toString(); });
    req.on('end', async () => {
      try {
        const { frame_path, students } = JSON.parse(body);
        if (!frame_path || !fs.existsSync(frame_path)) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ error: 'Frame file not found', matched_ids: [] }));
        }

        const t0 = Date.now();
        // 1. Ensure all students in classroom have cached descriptors
        const studentMap = new Map();
        for (const s of (students || [])) {
          const desc = await getStudentDescriptor(s.id, s.photo_path);
          if (desc) studentMap.set(s.id, desc);
        }

        // 2. Load live camera frame and detect faces using ultra-fast TinyFaceDetector
        const liveImg = await canvas.loadImage(frame_path);
        const detections = await faceapi.detectAllFaces(liveImg, new faceapi.TinyFaceDetectorOptions({ inputSize: 416, scoreThreshold: 0.3 }))
          .withFaceLandmarks()
          .withFaceDescriptors();

        const matchedIds = new Set();
        const THRESHOLD = 0.55; // Euclidean distance threshold for high accuracy

        for (const face of detections) {
          let bestId = null;
          let bestDist = Infinity;

          for (const [sId, sDesc] of studentMap.entries()) {
            const dist = faceapi.euclideanDistance(face.descriptor, sDesc);
            if (dist < bestDist) {
              bestDist = dist;
              bestId = sId;
            }
          }

          if (bestId !== null && bestDist < THRESHOLD) {
            console.log(`🎯 [FastEngine] Live Match: Student ID ${bestId} (dist: ${bestDist.toFixed(4)} < ${THRESHOLD})`);
            matchedIds.add(bestId);
          }
        }

        const elapsed = Date.now() - t0;
        console.log(`⚡ [FastEngine] Scanned frame in ${elapsed}ms | Found ${matchedIds.size} students`);

        // Clean up temp live frame file
        try { fs.unlinkSync(frame_path); } catch (_) {}

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ matched_ids: Array.from(matchedIds), elapsed_ms: elapsed }));
      } catch (err) {
        console.error('❌ [FastEngine] Recognition error:', err);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message, matched_ids: [] }));
      }
    });
  } else {
    res.writeHead(404);
    res.end();
  }
});

loadModels().then(() => {
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`🚀 [FastEngine] High-Speed JavaScript Recognition Service listening on http://127.0.0.1:${PORT}`);
  });
}).catch(err => {
  console.error('❌ [FastEngine] Failed to load models:', err);
  process.exit(1);
});
