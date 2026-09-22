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
