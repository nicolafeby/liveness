import unittest

from challenge import Session
from models import Observation


class ChallengeTests(unittest.TestCase):
    def test_complete_sequence(self):
        session = Session(created_at=1)
        frames = [(1.1, True, .4), (1.2, False, .4),
                  (1.3, False, .4), (1.4, True, .4), (1.5, True, .6)]
        for now, eyes, center in frames:
            result = session.advance(Observation(1, eyes, center), now)
        self.assertTrue(result["passed"])

    def test_closed_frames_must_be_consecutive(self):
        session = Session(created_at=1)
        for now, eyes in [(1.1, True), (1.2, False), (1.3, True), (1.4, False)]:
            result = session.advance(Observation(1, eyes, .4), now)
        self.assertEqual(result["status"], "blink")

    def test_multiple_faces_do_not_advance(self):
        session = Session(created_at=1)
        result = session.advance(Observation(2, True, .4), 1.1)
        self.assertEqual(result["status"], "open")

    def test_expiry(self):
        session = Session(created_at=1)
        result = session.advance(Observation(1, True, .4), 122)
        self.assertEqual(result["status"], "failed")


if __name__ == "__main__":
    unittest.main()
