"""HTTP API for a basic camera liveness challenge."""
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from challenge import SessionStore, TTL_SECONDS
from detector import Detector
from responses import (http_exception_handler, success,
                       unexpected_exception_handler, validation_exception_handler)

app = FastAPI(title="Liveness Detection API", version="0.1.0")
app.add_exception_handler(StarletteHTTPException, http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(Exception, unexpected_exception_handler)
detector = Detector()
sessions = SessionStore()
MAX_IMAGE_BYTES = 5 * 1024 * 1024


@app.get("/health")
def health():
    return success("Layanan aktif", {"status": "ok"})


@app.post("/sessions", status_code=201)
def create_session():
    session_id, state = sessions.create()
    return success("Sesi berhasil dibuat",
                   {"session_id": session_id, "expires_in_seconds": TTL_SECONDS, **state}, 201)


@app.post("/sessions/{session_id}/frames")
async def submit_frame(session_id: str, image: UploadFile = File(...)):
    if image.content_type not in ("image/jpeg", "image/png"):
        raise HTTPException(status_code=415, detail="Gunakan gambar JPEG atau PNG")
    data = await image.read(MAX_IMAGE_BYTES + 1)
    if not data or len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Gambar harus berukuran 1 byte sampai 5 MB")
    try:
        observation = detector.observe(data)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    result = sessions.advance(session_id, observation)
    if result is None:
        raise HTTPException(status_code=404, detail="Sesi tidak ditemukan atau kedaluwarsa")
    return success("Frame berhasil diproses", result)
