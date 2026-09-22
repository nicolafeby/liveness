import unittest

import cv2
import numpy as np

from detector import Detector


class DetectorTests(unittest.TestCase):
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
