import asyncio
import itertools
import unittest
from unittest.mock import patch

import main
from challenge import SessionStore
from models import Observation


class FakeWebSocket:
    def __init__(self, messages):
        self.messages = iter(messages)
        self.sent = []
        self.close_code = None
        self.accepted = False

    async def accept(self):
        self.accepted = True

    async def receive(self):
        return next(self.messages)

    async def send_json(self, value):
        self.sent.append(value)

    async def close(self, code, reason=None):
        self.close_code = code


class StreamTests(unittest.TestCase):
    def test_raw_color_is_only_accepted_for_stream(self):
        pixels = bytes([120]) * (200 * 200 * 3)
        frame = b"LVC1" + (200).to_bytes(2, "big") * 2 + pixels
        with patch.object(main.detector, "observe", return_value=Observation(0)):
            self.assertEqual(main.observe_frame(frame, allow_luma=True).face_count, 0)
            with self.assertRaises(ValueError):
                main.observe_frame(frame)

    def test_stream_advances_challenge_and_reports_invalid_frame(self):
        store = SessionStore()
        session_id, _ = store.create()
        jpeg = b"\xff\xd8\xff" + b"frame"
        messages = [{"type": "websocket.receive", "text": "bad"},
                    {"type": "websocket.receive", "bytes": b"not an image"},
                    *[{"type": "websocket.receive", "bytes": jpeg} for _ in range(11)]]
        socket = FakeWebSocket(messages)
        observations = [Observation(1, eyes, .5, .5, .35, .45, face_yaw=yaw, passive_scores=(.005, .99, .005))
                        for eyes, yaw in [(True, None), (True, None), (True, None),
                                          (False, None), (True, None), (True, None),
                                          (True, 0), (True, 19), (True, 20),
                                          (True, 3), (True, 2)]]

        async def run():
            with patch.object(main, "sessions", store), patch.object(
                main.detector, "observe", side_effect=observations
            ):
                # The challenge requires at least 80 ms between accepted frames.
                clock = itertools.count(start=0, step=.1)
                with patch("challenge.monotonic", side_effect=lambda: next(clock)):
                    await main.stream_frames(socket, session_id)

        asyncio.run(run())
        self.assertTrue(socket.accepted)
        self.assertEqual(socket.sent[0]["data"]["status"], "align")
        self.assertFalse(socket.sent[1]["success"])
        self.assertFalse(socket.sent[2]["success"])
        self.assertTrue(socket.sent[-1]["data"]["passed"])
        self.assertEqual(socket.close_code, 1000)

    def test_unknown_session_is_rejected(self):
        socket = FakeWebSocket([])
        asyncio.run(main.stream_frames(socket, "missing"))
        self.assertFalse(socket.accepted)
        self.assertEqual(socket.close_code, 4404)


if __name__ == "__main__":
    unittest.main()
