import unittest

from challenge import Session
from models import Observation


class ChallengeTests(unittest.TestCase):
    @staticmethod
    def face(eyes=True, x=.5, y=.5, width=.35, height=.45):
        return Observation(1, eyes, x, y, width, height)

    def test_complete_sequence(self):
        session = Session(created_at=1)
        frames = [(1.1, True, .5), (1.2, True, .5), (1.3, True, .5),
                  (1.4, False, .5), (1.5, False, .5), (1.6, True, .5),
                  (1.7, True, .7)]
        for now, eyes, center in frames:
            result = session.advance(self.face(eyes, center), now)
        self.assertTrue(result["passed"])

    def test_closed_frames_must_be_consecutive(self):
        session = Session(created_at=1)
        for now, eyes in [(1.1, True), (1.2, True), (1.3, True),
                          (1.4, False), (1.5, True), (1.6, False)]:
            result = session.advance(self.face(eyes), now)
        self.assertEqual(result["status"], "blink")

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

    def test_expiry(self):
        session = Session(created_at=1)
        result = session.advance(self.face(), 122)
        self.assertEqual(result["status"], "failed")


if __name__ == "__main__":
    unittest.main()
