"""Face, eye, and head-turn observations for a camera challenge."""
from math import atan2, degrees
from pathlib import Path
from threading import Lock

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
        model_path = Path(__file__).with_name("face_detection_yunet_2023mar.onnx")
        self.turn_detector = cv2.FaceDetectorYN.create(str(model_path), "", (320, 320), score_threshold=.7)
        self._turn_lock = Lock()
        self.passive_net = cv2.dnn.readNetFromONNX(str(Path(__file__).with_name("minifasnet_v2.onnx")))
        self._passive_lock = Lock()
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

    @staticmethod
    def lighting_for_face(luminance: np.ndarray, x: int, y: int, w: int, h: int) -> str | None:
        face_light = luminance[y + h // 5:y + 4 * h // 5,
                               x + w // 5:x + 4 * w // 5]
        median_light = float(np.median(face_light))
        if median_light < 55 or np.mean(face_light < 25) > .45:
            return "dark"
        if median_light > 205 or np.mean(face_light > 245) > .45:
            return "bright"
        return None

    def passive_scores(self, image: np.ndarray, x: int, y: int, w: int, h: int) -> tuple[float, float, float]:
        # Match the upstream 2.7x crop and unnormalized BGR float32 input.
        height, width = image.shape[:2]
        scale = min((height - 1) / h, (width - 1) / w, 2.7)
        crop_w, crop_h = w * scale, h * scale
        x0 = min(max(0, x + w / 2 - crop_w / 2), width - 1 - crop_w)
        y0 = min(max(0, y + h / 2 - crop_h / 2), height - 1 - crop_h)
        left, top = int(x0), int(y0)
        right, bottom = int(x0 + crop_w), int(y0 + crop_h)
        crop = image[top:bottom + 1, left:right + 1]
        blob = cv2.dnn.blobFromImage(crop, scalefactor=1, size=(80, 80), swapRB=False)
        with self._passive_lock:
            self.passive_net.setInput(blob)
            logits = self.passive_net.forward().reshape(-1)
        probabilities = np.exp(logits - np.max(logits))
        probabilities /= probabilities.sum()
        return tuple(float(value) for value in probabilities)

    def observe_turn(self, image: np.ndarray, luminance: np.ndarray) -> Observation:
        height, width = luminance.shape
        with self._turn_lock:
            self.turn_detector.setInputSize((width, height))
            _, faces = self.turn_detector.detect(image)
        face_count = 0 if faces is None else len(faces)
        if face_count != 1:
            return Observation(face_count=face_count)
        face = faces[0]
        x0 = max(0, min(width - 1, int(face[0])))
        y0 = max(0, min(height - 1, int(face[1])))
        x1 = max(x0 + 1, min(width, int(face[0] + face[2])))
        y1 = max(y0 + 1, min(height, int(face[1] + face[3])))
        yaw = self.yaw_from_landmarks(face)
        return Observation(
            face_count=1,
            face_center_x=(x0 + x1) / (2 * width),
            face_center_y=(y0 + y1) / (2 * height),
            face_width=(x1 - x0) / width,
            face_height=(y1 - y0) / height,
            lighting=self.lighting_for_face(luminance, x0, y0, x1 - x0, y1 - y0),
            face_yaw=yaw,
            passive_scores=self.passive_scores(image, x0, y0, x1 - x0, y1 - y0),
        )

    @staticmethod
    def yaw_from_landmarks(face: np.ndarray) -> float | None:
        """Estimate signed turn from nose displacement along the eye line."""
        eye_dx = float(face[6] - face[4])
        eye_dy = float(face[7] - face[5])
        eye_distance_sq = eye_dx * eye_dx + eye_dy * eye_dy
        if eye_distance_sq < 25:
            return None
        nose_dx = float(face[8] - (face[4] + face[6]) / 2)
        nose_dy = float(face[9] - (face[5] + face[7]) / 2)
        normalized_offset = (nose_dx * eye_dx + nose_dy * eye_dy) / eye_distance_sq
        return degrees(atan2(2 * normalized_offset, 1))

    def observe(self, data: bytes, detect_turn: bool = False) -> Observation:
        if data.startswith(b"LVC1"):
            if len(data) < 8:
                raise ValueError("Frame warna tidak valid")
            width = int.from_bytes(data[4:6], "big")
            height = int.from_bytes(data[6:8], "big")
            if min(width, height) < 100 or width * height > 1_500_000 or len(data) != 8 + 3 * width * height:
                raise ValueError("Frame warna tidak valid")
            image = np.frombuffer(data, dtype=np.uint8, offset=8).reshape(height, width, 3)
        else:
            if data.startswith(b"LVY1"):
                raise ValueError("Frame luminans tidak mendukung anti-spoofing; kirim frame berwarna")
            image = cv2.imdecode(np.frombuffer(data, dtype=np.uint8), cv2.IMREAD_COLOR)
            if image is None:
                raise ValueError("Gambar tidak valid atau terlalu kecil (minimal 100x100)")
        luminance = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        if min(luminance.shape[:2]) < 100:
            raise ValueError("Gambar tidak valid atau terlalu kecil (minimal 100x100)")
        if luminance.shape[0] * luminance.shape[1] > 12_000_000:
            raise ValueError("Resolusi gambar terlalu besar")
        if detect_turn:
            return self.observe_turn(image, luminance)
        gray = cv2.equalizeHist(luminance)
        faces = self.face.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(80, 80))
        if len(faces) != 1:
            return Observation(face_count=len(faces))
        x, y, w, h = faces[0]
        # Measure the central face region before histogram equalization, which
        # would hide underexposure and overexposure from the quality check.
        lighting = self.lighting_for_face(luminance, x, y, w, h)
        face_gray = gray[y:y + h, x:x + w]
        return Observation(face_count=1, eyes_visible=self.eyes_visible(face_gray),
                           face_center_x=(x + w / 2) / luminance.shape[1],
                           face_center_y=(y + h / 2) / luminance.shape[0],
                           face_width=w / luminance.shape[1],
                           face_height=h / luminance.shape[0], lighting=lighting,
                           passive_scores=self.passive_scores(image, x, y, w, h))
