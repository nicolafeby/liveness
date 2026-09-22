from dataclasses import dataclass


@dataclass(frozen=True)
class Observation:
    face_count: int
    eyes_visible: bool = False
    face_center_x: float = 0.0
