import sys
import time

import pytest
from voice_input.recorder import ParecordRecorder

# Stands in for parecord: writes its last argument as a WAV of 0.5 s of
# silence once it gets SIGINT, or exits at once with "fail".
FAKE = r"""
import signal, sys, time, wave
out = sys.argv[-1]
if "fail" in sys.argv:
    sys.exit(1)
def done(*_):
    with wave.open(out, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
        w.writeframes(b"\0\0" * 8000)
    sys.exit(0)
signal.signal(signal.SIGINT, done)
while True:
    time.sleep(0.05)
"""


@pytest.fixture
def fake(tmp_path):
    script = tmp_path / "fake_parecord.py"
    script.write_text(FAKE)
    return (sys.executable, str(script))


def test_start_stop_returns_wav(tmp_path, fake):
    rec = ParecordRecorder(command=fake, workdir=tmp_path)
    rec.start()
    clip = rec.stop()
    assert clip is not None
    assert clip.stat().st_size == 44 + 16000


def test_start_raises_when_recorder_exits(tmp_path, fake):
    rec = ParecordRecorder(command=(*fake, "fail"), workdir=tmp_path)
    with pytest.raises(RuntimeError):
        rec.start()


def test_max_duration_stops_by_itself(tmp_path, fake):
    rec = ParecordRecorder(command=fake, workdir=tmp_path, max_s=0.5)
    rec.start()
    time.sleep(1.0)
    assert rec._proc.poll() is not None
    clip = rec.stop()
    assert clip is not None
    assert clip.exists()


def test_cancel_removes_clip(tmp_path, fake):
    rec = ParecordRecorder(command=fake, workdir=tmp_path)
    rec.start()
    rec.cancel()
    assert list(tmp_path.glob("*.wav")) == []


def test_stop_without_start_is_none(tmp_path, fake):
    assert ParecordRecorder(command=fake, workdir=tmp_path).stop() is None


# Writes a header and 0.5 s of silence at once, then keeps recording.
LIVE = r"""
import signal, sys, time, wave
w = wave.open(sys.argv[-1], "wb")
w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
w.writeframes(b"\0\0" * 8000)
w._file.flush()
signal.signal(signal.SIGINT, lambda *_: (w.close(), sys.exit(0)))
while True:
    time.sleep(0.05)
"""


def test_live_level_while_recording(tmp_path):
    script = tmp_path / "live.py"
    script.write_text(LIVE)
    rec = ParecordRecorder(
        command=(sys.executable, str(script)), workdir=tmp_path
    )
    assert rec.live_level() is None
    rec.start()
    assert rec.live_level() == -120.0
    rec.stop()
    assert rec.live_level() is None


def test_live_level_none_after_auto_stop(tmp_path, fake):
    rec = ParecordRecorder(command=fake, workdir=tmp_path, max_s=0.3)
    rec.start()
    time.sleep(0.8)
    assert rec.live_level() is None
    assert rec.stop() is not None
