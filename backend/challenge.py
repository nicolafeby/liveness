"""State machine for a blink and movement challenge."""
from dataclasses import dataclass, field
from enum import Enum
from statistics import median
from threading import Lock
from time import monotonic
from uuid import uuid4

from models import Observation

TTL_SECONDS = 120
MAX_FRAMES = 180
ALIGNMENT_FRAMES = 2
BLINK_WAIT_FRAMES = 4
MAX_BLINK_SECONDS = 1.5
MOVE_TRACKING_GRACE_SECONDS = 2.0
TURN_YAW_DEGREES = 15.0
FRONT_YAW_DEGREES = 8.0
PASSIVE_MIN_SAMPLES = 5
PASSIVE_LIVE_THRESHOLD = .5
EYES_NOT_VISIBLE = "Mata belum terlihat jelas. Hadap kamera dan pastikan area mata tidak tertutup."
BLINK_NOT_DETECTED = "Kedipan belum terdeteksi. Coba kedip sekali lagi."


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
            ChallengeStage.ALIGN: "Hadapkan wajah ke kamera dan pastikan kedua mata terlihat jelas.",
            ChallengeStage.OPEN: "Hadapkan wajah ke kamera dan pastikan kedua mata terlihat jelas.",
            ChallengeStage.BLINK: "Kedipkan kedua mata sekali.",
            ChallengeStage.REOPEN: "Buka kembali kedua mata",
            ChallengeStage.MOVE: "Menoleh sedikit ke kiri atau kanan",
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
    aligned_frames: int = 0
    closed_frames: int = 0
    blink_closed_at: float | None = None
    reopened_frames: int = 0
    blink_wait_frames: int = 0
    moved_frames: int = 0
    turn_confirmed: bool = False
    returned_frames: int = 0
    baseline_yaw: float | None = None
    move_tracking_lost_at: float | None = None
    frames: int = 0
    last_frame_at: float = 0.0
    passive_samples: list[tuple[float, float, float]] = field(default_factory=list)

    def reset_tracking(self):
        self.stage = ChallengeStage.ALIGN
        self.aligned_frames = 0
        self.closed_frames = 0
        self.blink_closed_at = None
        self.reopened_frames = 0
        self.blink_wait_frames = 0
        self.moved_frames = 0
        self.turn_confirmed = False
        self.returned_frames = 0
        self.baseline_yaw = None
        self.move_tracking_lost_at = None
        self.baseline_x = None
        self.baseline_y = None
        self.baseline_width = None
        self.baseline_height = None
        self.passive_samples.clear()

    def stable_face(self, observation: Observation) -> bool:
        return (self.baseline_y is not None
                and abs(observation.face_center_y - self.baseline_y) <= .10
                and abs(observation.face_width - self.baseline_width) <= .10
                and abs(observation.face_height - self.baseline_height) <= .10)

    def tracking_issue(self, now: float, message: str) -> dict:
        if self.stage == ChallengeStage.MOVE:
            self.moved_frames = 0
            self.returned_frames = 0
            if self.move_tracking_lost_at is None:
                self.move_tracking_lost_at = now
            if now - self.move_tracking_lost_at < MOVE_TRACKING_GRACE_SECONDS:
                return self.result(message)
        self.reset_tracking()
        return self.result(message)

    def advance(self, observation: Observation, now: float) -> dict:
        if self.frames >= MAX_FRAMES or now - self.created_at > TTL_SECONDS:
            self.stage = ChallengeStage.FAILED
            return self.result()
        if self.last_frame_at and now - self.last_frame_at < 0.08:
            return self.result("Kirim frame dengan interval minimal 80 ms")
        self.last_frame_at = now
        self.frames += 1
        if observation.face_count != 1:
            return self.tracking_issue(now, "Pastikan tepat satu wajah terlihat dan hadap kamera")
        if observation.lighting is not None:
            if observation.lighting == "dark":
                return self.tracking_issue(now, "Wajah terlalu gelap, pindah ke tempat yang lebih terang")
            return self.tracking_issue(now, "Wajah terlalu terang, hindari cahaya langsung")
        if observation.passive_scores is None:
            return self.tracking_issue(now, "Frame berwarna diperlukan untuk pemeriksaan anti-spoofing")
        if self.stage != ChallengeStage.MOVE and alignment_instruction(observation) is None:
            self.passive_samples.append(observation.passive_scores)
            if len(self.passive_samples) > 8:
                self.passive_samples.pop(0)
        if self.stage == ChallengeStage.ALIGN:
            guidance = alignment_instruction(observation)
            if guidance is not None or not observation.eyes_visible:
                self.aligned_frames = 0
                return self.result(guidance or EYES_NOT_VISIBLE)
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
        elif self.stage == ChallengeStage.OPEN:
            return self.result(EYES_NOT_VISIBLE)
        elif self.stage in (ChallengeStage.BLINK, ChallengeStage.REOPEN) and (
            not self.stable_face(observation)
            or abs(observation.face_center_x - self.baseline_x) > .10
        ):
            return self.tracking_issue(now, "Jaga wajah tetap pada jarak dan tinggi yang sama")
        elif self.stage == ChallengeStage.BLINK and not observation.eyes_visible:
            self.blink_wait_frames = 0
            self.closed_frames = 1
            self.blink_closed_at = now
            self.stage = ChallengeStage.REOPEN
        elif self.stage == ChallengeStage.BLINK and observation.eyes_visible:
            self.blink_wait_frames += 1
            if self.blink_wait_frames >= BLINK_WAIT_FRAMES:
                self.blink_wait_frames = 0
                return self.result(BLINK_NOT_DETECTED)
        elif self.stage == ChallengeStage.REOPEN:
            if now - self.blink_closed_at > MAX_BLINK_SECONDS:
                self.stage = ChallengeStage.BLINK
                self.closed_frames = 0
                self.blink_closed_at = None
                self.reopened_frames = 0
                return self.result(BLINK_NOT_DETECTED)
            if observation.eyes_visible:
                self.reopened_frames += 1
                if self.reopened_frames >= 2:
                    self.stage = ChallengeStage.MOVE
            else:
                self.reopened_frames = 0
        elif self.stage == ChallengeStage.MOVE:
            if observation.face_yaw is None:
                return self.tracking_issue(now, "Hadapkan wajah ke kamera agar arah wajah terbaca")
            self.move_tracking_lost_at = None
            if self.baseline_yaw is None:
                self.baseline_yaw = observation.face_yaw
                return self.result()
            turn_change = abs(observation.face_yaw - self.baseline_yaw)
            if not self.turn_confirmed:
                if turn_change >= TURN_YAW_DEGREES:
                    self.moved_frames += 1
                    if self.moved_frames >= 2:
                        self.turn_confirmed = True
                else:
                    self.moved_frames = 0
            else:
                guidance = alignment_instruction(observation)
                if (turn_change <= FRONT_YAW_DEGREES
                        and observation.eyes_visible
                        and guidance is None):
                    self.returned_frames += 1
                else:
                    self.returned_frames = 0
                    if turn_change <= FRONT_YAW_DEGREES:
                        return self.result(guidance or "Buka kedua mata dan hadap kamera")
                if self.returned_frames >= 2:
                    if (len(self.passive_samples) >= PASSIVE_MIN_SAMPLES
                            and median(sample[1] for sample in self.passive_samples) >= PASSIVE_LIVE_THRESHOLD):
                        self.stage = ChallengeStage.PASSED
                    else:
                        self.stage = ChallengeStage.FAILED
                        return self.result("Verifikasi gagal, terdeteksi spoofing")
        return self.result()

    def result(self, message: str | None = None) -> dict:
        if message is None and self.stage == ChallengeStage.MOVE:
            message = ("Kembali menghadap kamera" if self.turn_confirmed
                       else "Hadap kamera sebentar" if self.baseline_yaw is None
                       else "Menoleh sedikit ke kiri atau kanan")
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
            session = Session()
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
