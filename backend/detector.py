"""Face and eye observations for a basic challenge."""
import cv2
import numpy as np

from models import Observation


class Detector:
    def __init__(self):
        base = cv2.data.haarcascades
        self.face = cv2.CascadeClassifier(base + "haarcascade_frontalface_default.xml")
        self.eye = cv2.CascadeClassifier(base + "haarcascade_eye.xml")
        if self.face.empty() or self.eye.empty():
            raise RuntimeError("OpenCV Haar cascade tidak tersedia")

    def observe(self, data: bytes) -> Observation:
        image = cv2.imdecode(np.frombuffer(data, dtype=np.uint8), cv2.IMREAD_COLOR)
        if image is None or min(image.shape[:2]) < 100:
            raise ValueError("Gambar tidak valid atau terlalu kecil (minimal 100x100)")
        if image.shape[0] * image.shape[1] > 12_000_000:
            raise ValueError("Resolusi gambar terlalu besar")
        gray = cv2.equalizeHist(cv2.cvtColor(image, cv2.COLOR_BGR2GRAY))
        faces = self.face.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(80, 80))
        if len(faces) != 1:
            return Observation(face_count=len(faces))
        x, y, w, h = faces[0]
        upper = gray[y:y + int(h * 0.55), x:x + w]
        eyes = self.eye.detectMultiScale(upper, scaleFactor=1.1, minNeighbors=5,
                                         minSize=(max(12, w // 12), max(12, h // 12)))
        return Observation(face_count=1, eyes_visible=len(eyes) >= 2,
                           face_center_x=(x + w / 2) / image.shape[1])
