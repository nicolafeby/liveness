"""State machine for a blink and movement challenge."""
from dataclasses import dataclass, field
from enum import Enum
from secrets import choice
from threading import Lock
from time import monotonic
from uuid import uuid4

from models import Observation

TTL_SECONDS = 120
MAX_FRAMES = 60
ALIGNMENT_FRAMES = 2


class ChallengeStage(str, Enum):
    ALIGN = "align"
    OPEN = "open"
    BLINK = "blink"
    REOPEN = "reopen"
    MOVE = "move"
    PASSED = "passed"
    FAILED = "failed"

    @property
    def instruction(self) -> str:
        return {
            ChallengeStage.ALIGN: "Posisikan wajah di tengah bingkai",
            ChallengeStage.OPEN: "Hadap kamera dengan kedua mata terbuka",
            ChallengeStage.BLINK: "Kedipkan mata",
            ChallengeStage.REOPEN: "Buka kembali kedua mata",
            ChallengeStage.MOVE: "Geser kepala ke kiri atau kanan dalam bingkai",
            ChallengeStage.PASSED: "Verifikasi selesai",
            ChallengeStage.FAILED: "Verifikasi gagal",
        }[self]

    @property
    def is_finished(self) -> bool:
        return self in (ChallengeStage.PASSED, ChallengeStage.FAILED)


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
    stage: ChallengeStage = ChallengeStage.ALIGN
    baseline_x: float | None = None
    baseline_y: float | None = None
    baseline_width: float | None = None
    baseline_height: float | None = None
    move_direction: int = 1
    aligned_frames: int = 0
    closed_frames: int = 0
    moved_frames: int = 0
    frames: int = 0
    last_frame_at: float = 0.0

    def reset_tracking(self):
        self.stage = ChallengeStage.ALIGN
        self.aligned_frames = 0
        self.closed_frames = 0
        self.moved_frames = 0
        self.baseline_x = None
        self.baseline_y = None
        self.baseline_width = None
        self.baseline_height = None

    def stable_face(self, observation: Observation) -> bool:
        return (self.baseline_y is not None
                and abs(observation.face_center_y - self.baseline_y) <= .10
                and abs(observation.face_width - self.baseline_width) <= .10
                and abs(observation.face_height - self.baseline_height) <= .10)

    def advance(self, observation: Observation, now: float) -> dict:
        if self.frames >= MAX_FRAMES or now - self.created_at > TTL_SECONDS:
            self.stage = ChallengeStage.FAILED
            return self.result()
        if self.last_frame_at and now - self.last_frame_at < 0.08:
            return self.result("Kirim frame dengan interval minimal 80 ms")
        self.last_frame_at = now
        self.frames += 1
        if observation.face_count != 1:
            self.reset_tracking()
            return self.result("Pastikan tepat satu wajah terlihat")
        if observation.lighting is not None:
            self.reset_tracking()
            if observation.lighting == "dark":
                return self.result("Wajah terlalu gelap, pindah ke tempat yang lebih terang")
            return self.result("Wajah terlalu terang, hindari cahaya langsung")
        if self.stage == ChallengeStage.ALIGN:
            guidance = alignment_instruction(observation)
            if guidance is not None or not observation.eyes_visible:
                self.aligned_frames = 0
                return self.result(guidance or "Hadap kamera dengan kedua mata terbuka")
            self.aligned_frames += 1
            if self.aligned_frames >= ALIGNMENT_FRAMES:
                self.stage = ChallengeStage.OPEN
            return self.result()
        if self.stage == ChallengeStage.OPEN:
            guidance = alignment_instruction(observation)
            if guidance is not None:
                self.reset_tracking()
                return self.result(guidance)
        if self.stage == ChallengeStage.OPEN and observation.eyes_visible:
            self.baseline_x = observation.face_center_x
            self.baseline_y = observation.face_center_y
            self.baseline_width = observation.face_width
            self.baseline_height = observation.face_height
            self.stage = ChallengeStage.BLINK
        elif self.stage in (ChallengeStage.BLINK, ChallengeStage.REOPEN, ChallengeStage.MOVE) and (
            not self.stable_face(observation)
            or (self.stage != ChallengeStage.MOVE
                and abs(observation.face_center_x - self.baseline_x) > .10)
        ):
            self.reset_tracking()
            return self.result("Jaga wajah tetap pada jarak dan tinggi yang sama")
        elif self.stage == ChallengeStage.BLINK and not observation.eyes_visible:
            self.closed_frames += 1
            if self.closed_frames >= 2:
                self.stage = ChallengeStage.REOPEN
        elif self.stage == ChallengeStage.BLINK and observation.eyes_visible:
            self.closed_frames = 0
        elif self.stage == ChallengeStage.REOPEN and observation.eyes_visible:
            self.stage = ChallengeStage.MOVE
        elif self.stage == ChallengeStage.MOVE:
            if (observation.eyes_visible
                    and (observation.face_center_x - self.baseline_x) * self.move_direction >= .15):
                self.moved_frames += 1
                if self.moved_frames >= 2:
                    self.stage = ChallengeStage.PASSED
            else:
                self.moved_frames = 0
        return self.result()

    def result(self, message: str | None = None) -> dict:
        if message is None and self.stage == ChallengeStage.MOVE:
            message = ("Geser kepala ke kanan dalam bingkai" if self.move_direction == 1
                       else "Geser kepala ke kiri dalam bingkai")
        return {"status": self.stage.value, "passed": self.stage == ChallengeStage.PASSED,
                "instruction": message or self.stage.instruction, "frames_processed": self.frames}


class SessionStore:
    def __init__(self):
        self._sessions: dict[str, Session] = {}
        self._lock = Lock()

    def create(self) -> tuple[str, dict]:
        with self._lock:
            self._prune()
            session_id = uuid4().hex
            session = Session(move_direction=choice((-1, 1)))
            self._sessions[session_id] = session
            return session_id, session.result()

    def advance(self, session_id: str, observation: Observation) -> dict | None:
        with self._lock:
            session = self._sessions.get(session_id)
            if session is None or monotonic() - session.created_at > TTL_SECONDS:
                return None
            if session.stage.is_finished:
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
