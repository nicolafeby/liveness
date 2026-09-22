"""HTTP API for a basic camera liveness challenge."""
from fastapi import FastAPI, File, HTTPException, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.concurrency import run_in_threadpool
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from challenge import ChallengeStage, SessionStore, TTL_SECONDS
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


def observe_frame(data: bytes, allow_luma: bool = False, detect_turn: bool = False):
    if not data or len(data) > MAX_IMAGE_BYTES:
        raise ValueError("Gambar harus berukuran 1 byte sampai 5 MB")
    if not (data.startswith(b"\xff\xd8\xff") or data.startswith(b"\x89PNG\r\n\x1a\n")
            or (allow_luma and data.startswith(b"LVY1"))):
        raise ValueError("Gunakan gambar JPEG atau PNG")
    return detector.observe(data, detect_turn=detect_turn)


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
        state = sessions.get(session_id)
        observation = await run_in_threadpool(
            observe_frame, data, False, state is not None and state["status"] == ChallengeStage.MOVE.value)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    result = sessions.advance(session_id, observation)
    if result is None:
        raise HTTPException(status_code=404, detail="Sesi tidak ditemukan atau kedaluwarsa")
    return success("Frame berhasil diproses", result)


@app.websocket("/sessions/{session_id}/stream")
async def stream_frames(websocket: WebSocket, session_id: str):
    state = sessions.get(session_id)
    if state is None:
        await websocket.close(code=4404, reason="Sesi tidak ditemukan atau kedaluwarsa")
        return
    if ChallengeStage(state["status"]).is_finished:
        await websocket.close(code=4409, reason="Sesi sudah selesai")
        return
    await websocket.accept()
    await websocket.send_json({"success": True, "message": "Sesi terhubung",
                               "data": state, "errors": None})
    try:
        while True:
            message = await websocket.receive()
            if message["type"] == "websocket.disconnect":
                break
            data = message.get("bytes")
            if data is None:
                await websocket.send_json({"success": False,
                                           "message": "Kirim frame JPEG atau PNG sebagai pesan biner",
                                           "data": None, "errors": None})
                continue
            try:
                state = sessions.get(session_id)
                observation = await run_in_threadpool(
                    observe_frame, data, True, state is not None and state["status"] == ChallengeStage.MOVE.value)
            except ValueError as exc:
                await websocket.send_json({"success": False, "message": str(exc),
                                           "data": None, "errors": None})
                continue
            result = sessions.advance(session_id, observation)
            if result is None:
                await websocket.close(code=4404, reason="Sesi tidak ditemukan atau kedaluwarsa")
                break
            await websocket.send_json({"success": True, "message": "Frame berhasil diproses",
                                       "data": result, "errors": None})
            if ChallengeStage(result["status"]).is_finished:
                await websocket.close(code=1000)
                break
    except WebSocketDisconnect:
        pass
