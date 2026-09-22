import unittest

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

    def test_observes_raw_luma_frame(self):
        detector = self.detector_with_fixed_face()
        pixels = bytes([120]) * (200 * 200)
        frame = b"LVY1" + (200).to_bytes(2, "big") * 2 + pixels
        observation = detector.observe(frame)
        self.assertEqual(observation.face_count, 1)
        self.assertTrue(observation.eyes_visible)
        self.assertIsNone(observation.lighting)

    def test_rejects_truncated_raw_luma_frame(self):
        frame = b"LVY1" + (200).to_bytes(2, "big") * 2 + bytes(20)
        with self.assertRaises(ValueError):
            Detector().observe(frame)

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
