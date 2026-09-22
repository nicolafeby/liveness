import unittest
from threading import Lock

import cv2
import numpy as np

from detector import Detector


class DetectorTests(unittest.TestCase):
    @staticmethod
    def detector_with_fixed_face():
        class FakeCascade:
            def __init__(self, detections):
                self.detections = detections

            def detectMultiScale(self, *args, **kwargs):
                return self.detections

        detector = Detector.__new__(Detector)
        detector.face = FakeCascade([(40, 20, 80, 100)])
        detector.eye = FakeCascade([(10, 10, 20, 20), (40, 10, 20, 20)])
        detector.eye_glasses = FakeCascade([])
        detector.clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(4, 4))
        detector.passive_scores = lambda *args: (.005, .99, .005)
        return detector

    def test_reports_normalized_face_position_and_size(self):
        detector = self.detector_with_fixed_face()
        encoded, data = cv2.imencode(".jpg", np.zeros((200, 200, 3), dtype=np.uint8))
        self.assertTrue(encoded)
        observation = detector.observe(data.tobytes())
        self.assertEqual(observation.face_count, 1)
        self.assertTrue(observation.eyes_visible)
        self.assertAlmostEqual(observation.face_center_x, .4)
        self.assertAlmostEqual(observation.face_center_y, .35)
        self.assertAlmostEqual(observation.face_width, .4)
        self.assertAlmostEqual(observation.face_height, .5)

    def test_face_lighting_is_measured_before_equalization(self):
        detector = self.detector_with_fixed_face()
        for intensity, expected in [(20, "dark"), (120, None), (245, "bright")]:
            image = np.full((200, 200, 3), intensity, dtype=np.uint8)
            encoded, data = cv2.imencode(".jpg", image)
            self.assertTrue(encoded)
            self.assertEqual(detector.observe(data.tobytes()).lighting, expected)

    def test_observes_raw_color_frame(self):
        detector = self.detector_with_fixed_face()
        pixels = bytes([120]) * (200 * 200 * 3)
        frame = b"LVC1" + (200).to_bytes(2, "big") * 2 + pixels
        observation = detector.observe(frame)
        self.assertEqual(observation.face_count, 1)
        self.assertTrue(observation.eyes_visible)
        self.assertIsNone(observation.lighting)
        self.assertEqual(observation.passive_scores, (.005, .99, .005))

    def test_rejects_truncated_raw_color_frame(self):
        frame = b"LVC1" + (200).to_bytes(2, "big") * 2 + bytes(20)
        with self.assertRaises(ValueError):
            Detector().observe(frame)

    def test_rejects_legacy_luma_frame(self):
        frame = b"LVY1" + (200).to_bytes(2, "big") * 2 + bytes([120]) * 40000
        with self.assertRaisesRegex(ValueError, "berwarna"):
            Detector().observe(frame)

    def test_passive_model_returns_three_probabilities(self):
        detector = Detector()
        image = np.full((200, 200, 3), 120, dtype=np.uint8)
        scores = detector.passive_scores(image, 60, 50, 80, 100)
        self.assertEqual(len(scores), 3)
        self.assertAlmostEqual(sum(scores), 1, places=5)

    def test_passive_model_receives_unnormalized_crop_without_black_padding(self):
        class FakeNet:
            def setInput(self, blob):
                self.blob = blob

            def forward(self):
                return np.array([[0, 1, 0]], dtype=np.float32)

        detector = Detector.__new__(Detector)
        detector.passive_net = FakeNet()
        detector._passive_lock = Lock()
        image = np.full((200, 200, 3), 120, dtype=np.uint8)
        detector.passive_scores(image, 0, 0, 80, 100)
        self.assertEqual(detector.passive_net.blob.shape, (1, 3, 80, 80))
        self.assertTrue(np.all(detector.passive_net.blob == 120))

    def test_turn_mode_handles_frame_without_face(self):
        detector = Detector()
        image = np.full((200, 200, 3), 120, dtype=np.uint8)
        _, data = cv2.imencode(".jpg", image)
        observation = detector.observe(data.tobytes(), detect_turn=True)
        self.assertEqual(observation.face_count, 0)
        self.assertIsNone(observation.face_yaw)

    def test_yaw_proxy_uses_nose_relative_to_eyes(self):
        face = np.zeros(15, dtype=np.float32)
        face[4:10] = [20, 20, 80, 20, 50, 50]
        self.assertAlmostEqual(Detector.yaw_from_landmarks(face), 0)
        face[8] = 65
        self.assertGreater(Detector.yaw_from_landmarks(face), 15)

    def test_eye_pair_can_combine_primary_and_fallback_detections(self):
        detector = self.detector_with_fixed_face()

        class FakeCascade:
            def __init__(self, eyes):
                self.eyes = eyes

            def detectMultiScale(self, *args, **kwargs):
                return self.eyes

        detector.eye = FakeCascade([(10, 10, 20, 20)])
        detector.eye_glasses = FakeCascade([(40, 12, 20, 20)])
        image = np.full((200, 200, 3), 120, dtype=np.uint8)
        _, data = cv2.imencode(".jpg", image)
        self.assertTrue(detector.observe(data.tobytes()).eyes_visible)

    def test_two_detections_on_same_side_do_not_count_as_two_eyes(self):
        detector = self.detector_with_fixed_face()
        detector.eye.detections = [(5, 10, 20, 20), (15, 12, 20, 20)]
        image = np.full((200, 200, 3), 120, dtype=np.uint8)
        _, data = cv2.imencode(".jpg", image)
        self.assertFalse(detector.observe(data.tobytes()).eyes_visible)

    def test_detections_at_different_heights_do_not_count_as_eye_pair(self):
        detector = self.detector_with_fixed_face()
        detector.eye.detections = [(10, 5, 20, 20), (40, 35, 20, 20)]
        image = np.full((200, 200, 3), 120, dtype=np.uint8)
        _, data = cv2.imencode(".jpg", image)
        self.assertFalse(detector.observe(data.tobytes()).eyes_visible)

    def test_decodes_jpeg_and_reports_no_face_for_blank_frame(self):
        detector = Detector()
        encoded, data = cv2.imencode(".jpg", np.zeros((200, 200, 3), dtype=np.uint8))
        self.assertTrue(encoded)
        observation = detector.observe(data.tobytes())
        self.assertEqual(observation.face_count, 0)

    def test_rejects_invalid_image(self):
        with self.assertRaises(ValueError):
            Detector().observe(b"invalid")


if __name__ == "__main__":
    unittest.main()
