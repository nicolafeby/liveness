"""State machine for a blink and movement challenge."""
from dataclasses import dataclass, field
from threading import Lock
from time import monotonic
from uuid import uuid4

from models import Observation

TTL_SECONDS = 120
MAX_FRAMES = 60
ALIGNMENT_FRAMES = 2


def alignment_instruction(observation: Observation) -> str | None:
    """Return guidance until the detected face is well within the frame."""
    if observation.face_width < 0.20 or observation.face_height < 0.25:
        return "Dekatkan wajah ke kamera"
    if observation.face_width > 0.70 or observation.face_height > 0.75:
        return "Jauhkan wajah dari kamera"
    if observation.face_center_x < 0.40 or observation.face_center_x - observation.face_width / 2 < 0.05:
        return "Geser wajah ke kanan"
    if observation.face_center_x > 0.60 or observation.face_center_x + observation.face_width / 2 > 0.95:
        return "Geser wajah ke kiri"
    if observation.face_center_y < 0.38 or observation.face_center_y - observation.face_height / 2 < 0.05:
        return "Geser wajah ke bawah"
    if observation.face_center_y > 0.62 or observation.face_center_y + observation.face_height / 2 > 0.95:
        return "Geser wajah ke atas"
    return None


@dataclass
class Session:
    created_at: float = field(default_factory=monotonic)
    stage: str = "align"
    baseline_x: float | None = None
    aligned_frames: int = 0
    closed_frames: int = 0
    frames: int = 0
    last_frame_at: float = 0.0

    def advance(self, observation: Observation, now: float) -> dict:
        if self.frames >= MAX_FRAMES or now - self.created_at > TTL_SECONDS:
            self.stage = "failed"
            return self.result()
        if self.last_frame_at and now - self.last_frame_at < 0.08:
            return self.result("Kirim frame dengan interval minimal 80 ms")
        self.last_frame_at = now
        self.frames += 1
        if observation.face_count != 1:
            if self.stage == "align":
                self.aligned_frames = 0
            return self.result("Pastikan tepat satu wajah terlihat")
        if self.stage == "align":
            guidance = alignment_instruction(observation)
            if guidance is not None or not observation.eyes_visible:
                self.aligned_frames = 0
                return self.result(guidance or "Hadap kamera dengan kedua mata terbuka")
            self.aligned_frames += 1
            if self.aligned_frames >= ALIGNMENT_FRAMES:
                self.stage = "open"
            return self.result()
        if self.stage == "open":
            guidance = alignment_instruction(observation)
            if guidance is not None:
                self.stage = "align"
                self.aligned_frames = 0
                return self.result(guidance)
        if self.stage == "open" and observation.eyes_visible:
            self.baseline_x = observation.face_center_x
            self.stage = "blink"
        elif self.stage == "blink" and not observation.eyes_visible:
            self.closed_frames += 1
            if self.closed_frames >= 2:
                self.stage = "reopen"
        elif self.stage == "blink" and observation.eyes_visible:
            self.closed_frames = 0
        elif self.stage == "reopen" and observation.eyes_visible:
            self.stage = "move"
        elif self.stage == "move" and abs(observation.face_center_x - self.baseline_x) >= 0.15:
            self.stage = "passed"
        return self.result()

    def result(self, message: str | None = None) -> dict:
        prompts = {"align": "Posisikan wajah di tengah bingkai",
                   "open": "Hadap kamera dengan kedua mata terbuka",
                   "blink": "Kedipkan mata", "reopen": "Buka kembali kedua mata",
                   "move": "Geser kepala ke kiri atau kanan dalam bingkai",
                   "passed": "Verifikasi selesai", "failed": "Verifikasi gagal"}
        return {"status": self.stage, "passed": self.stage == "passed",
                "instruction": message or prompts[self.stage], "frames_processed": self.frames}


class SessionStore:
    def __init__(self):
        self._sessions: dict[str, Session] = {}
        self._lock = Lock()

    def create(self) -> tuple[str, dict]:
        with self._lock:
            self._prune()
            session_id = uuid4().hex
            session = Session()
            self._sessions[session_id] = session
            return session_id, session.result()

    def advance(self, session_id: str, observation: Observation) -> dict | None:
        with self._lock:
            session = self._sessions.get(session_id)
            if session is None or monotonic() - session.created_at > TTL_SECONDS:
                return None
            if session.stage in ("passed", "failed"):
                return session.result()
            return session.advance(observation, monotonic())

    def get(self, session_id: str) -> dict | None:
        with self._lock:
            session = self._sessions.get(session_id)
            if session is None or monotonic() - session.created_at > TTL_SECONDS:
                return None
            return session.result()

    def _prune(self):
        now = monotonic()
        self._sessions = {key: value for key, value in self._sessions.items()
                          if now - value.created_at <= TTL_SECONDS}
