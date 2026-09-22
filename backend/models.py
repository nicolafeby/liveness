from dataclasses import dataclass


@dataclass(frozen=True)
class Observation:
    face_count: int
    eyes_visible: bool = False
    face_center_x: float = 0.0
    face_center_y: float = 0.0
    face_width: float = 0.0
    face_height: float = 0.0
    lighting: str | None = None
