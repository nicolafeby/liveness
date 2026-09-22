"""Face and eye observations for a basic challenge."""
import cv2
import numpy as np

from models import Observation


class Detector:
    def __init__(self):
        base = cv2.data.haarcascades
        self.face = cv2.CascadeClassifier(base + "haarcascade_frontalface_default.xml")
        self.eye = cv2.CascadeClassifier(base + "haarcascade_eye.xml")
        self.eye_glasses = cv2.CascadeClassifier(base + "haarcascade_eye_tree_eyeglasses.xml")
        self.clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(4, 4))
        if self.face.empty() or self.eye.empty() or self.eye_glasses.empty():
            raise RuntimeError("OpenCV Haar cascade tidak tersedia")

    @staticmethod
    def has_eye_pair(candidates, face_width: int, face_height: int) -> bool:
        ordered = sorted(candidates, key=lambda eye: eye[0] + eye[2] / 2)
        for index, (x1, y1, w1, h1) in enumerate(ordered):
            center_x1 = x1 + w1 / 2
            center_y1 = y1 + h1 / 2
            if not .10 <= center_x1 / face_width < .50:
                continue
            for x2, y2, w2, h2 in ordered[index + 1:]:
                center_x2 = x2 + w2 / 2
                center_y2 = y2 + h2 / 2
                if (.50 < center_x2 / face_width <= .90
                        and .20 <= (center_x2 - center_x1) / face_width <= .70
                        and abs(center_y2 - center_y1) / face_height <= .15):
                    return True
        return False

    def eyes_visible(self, face_gray: np.ndarray) -> bool:
        height, width = face_gray.shape
        upper = face_gray[:int(height * .60), :]
        candidates = []
        min_size = (max(12, width // 12), max(12, height // 12))
        for image in (upper, self.clahe.apply(upper)):
            for cascade in (self.eye, self.eye_glasses):
                eyes = cascade.detectMultiScale(image, scaleFactor=1.08,
                                                minNeighbors=3, minSize=min_size)
                candidates.extend(tuple(map(int, eye)) for eye in eyes)
                if self.has_eye_pair(candidates, width, height):
                    return True
        return False

    def observe(self, data: bytes) -> Observation:
        if data.startswith(b"LVY1"):
            if len(data) < 8:
                raise ValueError("Frame luminans tidak valid")
            width = int.from_bytes(data[4:6], "big")
            height = int.from_bytes(data[6:8], "big")
            if min(width, height) < 100 or width * height > 5_000_000 or len(data) != 8 + width * height:
                raise ValueError("Frame luminans tidak valid")
            luminance = np.frombuffer(data, dtype=np.uint8, offset=8).reshape(height, width)
        else:
            image = cv2.imdecode(np.frombuffer(data, dtype=np.uint8), cv2.IMREAD_COLOR)
            if image is None:
                raise ValueError("Gambar tidak valid atau terlalu kecil (minimal 100x100)")
            luminance = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        if min(luminance.shape[:2]) < 100:
            raise ValueError("Gambar tidak valid atau terlalu kecil (minimal 100x100)")
        if luminance.shape[0] * luminance.shape[1] > 12_000_000:
            raise ValueError("Resolusi gambar terlalu besar")
        gray = cv2.equalizeHist(luminance)
        faces = self.face.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(80, 80))
        if len(faces) != 1:
            return Observation(face_count=len(faces))
        x, y, w, h = faces[0]
        # Measure the central face region before histogram equalization, which
        # would hide underexposure and overexposure from the quality check.
        face_light = luminance[y + h // 5:y + 4 * h // 5,
                               x + w // 5:x + 4 * w // 5]
        median_light = float(np.median(face_light))
        if median_light < 55 or np.mean(face_light < 25) > .45:
            lighting = "dark"
        elif median_light > 205 or np.mean(face_light > 245) > .45:
            lighting = "bright"
        else:
            lighting = None
        face_gray = gray[y:y + h, x:x + w]
        return Observation(face_count=1, eyes_visible=self.eyes_visible(face_gray),
                           face_center_x=(x + w / 2) / luminance.shape[1],
                           face_center_y=(y + h / 2) / luminance.shape[0],
                           face_width=w / luminance.shape[1],
                           face_height=h / luminance.shape[0], lighting=lighting)
