import unittest

from challenge import Session
from models import Observation


class ChallengeTests(unittest.TestCase):
    @staticmethod
    def face(eyes=True, x=.5, y=.5, width=.35, height=.45, yaw=None):
        return Observation(1, eyes, x, y, width, height, face_yaw=yaw)

    def test_complete_sequence(self):
        session = Session(created_at=1)
        frames = [(1.1, True, .5), (1.2, True, .5), (1.3, True, .5),
                  (1.4, False, .5), (1.5, True, .5), (1.6, True, .5)]
        for now, eyes, center in frames:
            result = session.advance(self.face(eyes, center), now)
        for now, yaw in [(1.7, 0), (1.8, 19), (1.9, 21), (2.0, 5), (2.1, 3)]:
            result = session.advance(self.face(yaw=yaw), now)
        self.assertTrue(result["passed"])

    def test_eye_instructions_and_incomplete_blink(self):
        session = Session(created_at=1)
        self.assertEqual(session.result()["instruction"],
                         "Hadapkan wajah ke kamera dan pastikan kedua mata terlihat jelas.")
        result = session.advance(self.face(False), 1.1)
        self.assertEqual(result["instruction"],
                         "Mata belum terlihat jelas. Hadap kamera dan pastikan area mata tidak tertutup.")
        session.advance(self.face(), 1.2)
        session.advance(self.face(), 1.3)
        result = session.advance(self.face(False), 1.4)
        self.assertEqual(result["instruction"],
                         "Mata belum terlihat jelas. Hadap kamera dan pastikan area mata tidak tertutup.")
        result = session.advance(self.face(), 1.5)
        self.assertEqual(result["instruction"], "Kedipkan kedua mata sekali.")
        session.advance(self.face(False), 1.6)
        result = session.advance(self.face(), 1.7)
        self.assertEqual(result["status"], "reopen")
        result = session.advance(self.face(), 1.8)
        self.assertEqual(result["status"], "move")

    def test_blink_that_does_not_reopen_quickly_must_be_retried(self):
        session = Session(created_at=1)
        for now in (1.1, 1.2, 1.3):
            session.advance(self.face(), now)
        session.advance(self.face(False), 1.4)
        result = session.advance(self.face(), 3.0)
        self.assertEqual(result["instruction"],
                         "Kedipan belum terdeteksi. Coba kedip sekali lagi.")
        self.assertEqual(result["status"], "blink")

    def test_blink_wait_timeout_gives_retry_instruction(self):
        session = Session(created_at=1)
        for now in (1.1, 1.2, 1.3):
            session.advance(self.face(), now)
        for now in (1.4, 1.5, 1.6, 1.7):
            result = session.advance(self.face(), now)
        self.assertEqual(result["instruction"],
                         "Kedipan belum terdeteksi. Coba kedip sekali lagi.")

    def test_reopened_frames_must_be_consecutive(self):
        session = Session(created_at=1)
        for now, eyes in [(1.1, True), (1.2, True), (1.3, True),
                          (1.4, False), (1.5, True), (1.6, False), (1.7, True)]:
            result = session.advance(self.face(eyes), now)
        self.assertEqual(result["status"], "reopen")

    def test_alignment_requires_centered_face_in_two_consecutive_frames(self):
        session = Session(created_at=1)
        result = session.advance(self.face(x=.22, y=.24), 1.1)
        self.assertEqual(result["status"], "align")
        self.assertEqual(result["instruction"], "Geser wajah ke kanan")
        session.advance(self.face(), 1.2)
        result = session.advance(self.face(x=.22), 1.3)
        self.assertEqual(result["status"], "align")
        session.advance(self.face(), 1.4)
        result = session.advance(self.face(), 1.5)
        self.assertEqual(result["status"], "open")

    def test_alignment_rejects_wrong_size_or_closed_eyes(self):
        session = Session(created_at=1)
        self.assertEqual(session.advance(self.face(width=.1), 1.1)["instruction"],
                         "Dekatkan wajah ke kamera")
        self.assertEqual(session.advance(self.face(height=.8), 1.2)["instruction"],
                         "Jauhkan wajah dari kamera")
        self.assertEqual(session.advance(self.face(y=.75), 1.3)["instruction"],
                         "Geser wajah ke atas")
        self.assertEqual(session.advance(self.face(False), 1.4)["status"], "align")

    def test_moving_away_before_blink_requires_realignment(self):
        session = Session(created_at=1)
        session.advance(self.face(), 1.1)
        session.advance(self.face(), 1.2)
        result = session.advance(self.face(x=.2), 1.3)
        self.assertEqual(result["status"], "align")
        self.assertEqual(result["instruction"], "Geser wajah ke kanan")

    def test_multiple_faces_do_not_advance(self):
        session = Session(created_at=1)
        result = session.advance(Observation(2, True, .4), 1.1)
        self.assertEqual(result["status"], "align")

    def test_lost_face_resets_blink_evidence(self):
        session = Session(created_at=1)
        for now, eyes in [(1.1, True), (1.2, True), (1.3, True), (1.4, False)]:
            session.advance(self.face(eyes), now)
        result = session.advance(Observation(0), 1.5)
        self.assertEqual(result["status"], "align")
        self.assertEqual(session.closed_frames, 0)

    def test_size_change_cannot_count_as_blink(self):
        session = Session(created_at=1)
        for now in (1.1, 1.2, 1.3):
            session.advance(self.face(), now)
        result = session.advance(self.face(False, width=.55), 1.4)
        self.assertEqual(result["status"], "align")

    def test_sideways_motion_cannot_count_as_blink(self):
        session = Session(created_at=1)
        for now in (1.1, 1.2, 1.3):
            session.advance(self.face(), now)
        result = session.advance(self.face(False, x=.7), 1.4)
        self.assertEqual(result["status"], "align")

    def test_bad_lighting_resets_progress_and_gives_guidance(self):
        session = Session(created_at=1)
        for now in (1.1, 1.2, 1.3, 1.4):
            session.advance(self.face(), now)
        self.assertEqual(session.stage.value, "blink")
        dark = Observation(1, True, .5, .5, .35, .45, "dark")
        result = session.advance(dark, 1.5)
        self.assertEqual(result["status"], "align")
        self.assertIn("terlalu gelap", result["instruction"])
        self.assertIsNone(session.baseline_x)
        bright = Observation(1, True, .5, .5, .35, .45, "bright")
        result = session.advance(bright, 1.6)
        self.assertIn("terlalu terang", result["instruction"])
        self.assertEqual(session.aligned_frames, 0)

    def test_turn_requires_two_frames_then_return_to_camera(self):
        session = Session(created_at=1)
        for now, eyes in [(1.1, True), (1.2, True), (1.3, True),
                          (1.4, False), (1.5, True), (1.6, True)]:
            session.advance(self.face(eyes), now)
        self.assertIn("Hadap", session.result()["instruction"])
        self.assertFalse(session.advance(self.face(x=.7, yaw=2), 1.7)["passed"])
        self.assertFalse(session.advance(self.face(yaw=-18), 1.8)["passed"])
        self.assertFalse(session.advance(self.face(yaw=0), 1.9)["passed"])
        self.assertFalse(session.advance(self.face(yaw=-18), 2.0)["passed"])
        self.assertFalse(session.advance(self.face(yaw=-20), 2.1)["passed"])
        self.assertIn("Kembali", session.result()["instruction"])
        self.assertFalse(session.advance(self.face(yaw=3), 2.2)["passed"])
        self.assertTrue(session.advance(self.face(yaw=4), 2.3)["passed"])

    def test_brief_tracking_loss_during_move_does_not_repeat_blink(self):
        session = Session(created_at=1)
        for now, eyes in [(1.1, True), (1.2, True), (1.3, True),
                          (1.4, False), (1.5, True), (1.6, True)]:
            session.advance(self.face(eyes), now)
        result = session.advance(Observation(0), 1.7)
        self.assertEqual(result["status"], "move")
        result = session.advance(self.face(x=.7, width=.23), 1.8)
        self.assertEqual(result["status"], "move")
        self.assertIn("arah wajah", result["instruction"])
        self.assertFalse(result["passed"])
        session.advance(self.face(yaw=0), 1.9)
        session.advance(self.face(yaw=18), 2.0)
        session.advance(self.face(yaw=19), 2.1)
        session.advance(self.face(yaw=1), 2.2)
        self.assertTrue(session.advance(self.face(yaw=2), 2.3)["passed"])

    def test_long_tracking_loss_during_move_requires_new_blink(self):
        session = Session(created_at=1)
        for now, eyes in [(1.1, True), (1.2, True), (1.3, True),
                          (1.4, False), (1.5, True), (1.6, True)]:
            session.advance(self.face(eyes), now)
        self.assertEqual(session.advance(Observation(0), 1.7)["status"], "move")
        self.assertEqual(session.advance(Observation(0), 3.8)["status"], "align")

    def test_expiry(self):
        session = Session(created_at=1)
        result = session.advance(self.face(), 122)
        self.assertEqual(result["status"], "failed")


if __name__ == "__main__":
    unittest.main()
