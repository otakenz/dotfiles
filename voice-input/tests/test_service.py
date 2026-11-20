import shutil
import threading
import time

import pytest
from helpers import tone, write_wav
from voice_input.service import VoiceService

SOME_IP_RULE = r"\bSOME[\s,-]+IP\b => SOME/IP" + "\n"


class FakeRecorder:
    def __init__(self, tmp_path, samples=None, fail=False):
        self.src = (
            write_wav(tmp_path / "src.wav", samples)
            if samples is not None
            else None
        )
        self.tmp_path = tmp_path
        self.fail = fail
        self.cancels = 0

    def start(self):
        if self.fail:
            raise RuntimeError("parecord exited")

    def stop(self):
        if self.src is None:
            return None
        clip = self.tmp_path / "clip.wav"
        shutil.copy(self.src, clip)
        return clip

    def cancel(self):
        self.cancels += 1

    def live_level(self):
        return -30.0


class FakeTranscriber:
    def __init__(self, text="hello", gate=None):
        self.text = text
        self.gate = gate
        self.prompts = []

    def transcribe(self, wav, prompt):
        self.prompts.append(prompt)
        if self.gate is not None:
            self.gate.wait(5)
        return self.text


@pytest.fixture
def config_dir(tmp_path):
    d = tmp_path / "config"
    d.mkdir()
    return d


def make(tmp_path, config_dir, samples=None, text="hello", **kw):
    if samples is None:
        samples = tone(1.0, -20.0)
    rec = FakeRecorder(tmp_path, samples, kw.pop("fail", False))
    tr = FakeTranscriber(text, kw.pop("gate", None))
    return VoiceService(rec, tr, config_dir), rec, tr


def test_short_clip_is_discarded(tmp_path, config_dir):
    svc, _, tr = make(tmp_path, config_dir, tone(0.2, -20.0))
    svc.start()
    out = svc.stop()
    assert out["text"] == ""
    assert out["warning"] is None
    assert tr.prompts == []


def test_quiet_clip_warns_no_audio(tmp_path, config_dir):
    svc, _, tr = make(tmp_path, config_dir, tone(1.0, -60.0))
    svc.start()
    out = svc.stop()
    assert out["text"] == ""
    assert out["warning"] == "no audio – check mic"
    assert tr.prompts == []


def test_transcript_gets_vocab_and_replacements(tmp_path, config_dir):
    (config_dir / "vocab.txt").write_text("OpenCode\n")
    (config_dir / "replacements.txt").write_text(SOME_IP_RULE)
    svc, _, tr = make(tmp_path, config_dir, text=" the SOME IP proxy ")
    svc.start()
    out = svc.stop()
    assert out["text"] == "the SOME/IP proxy"
    assert out["warning"] is None
    assert tr.prompts == ["OpenCode."]
    assert out["duration_s"] == 1.0
    for key in ("peak_dbfs", "mean_dbfs", "clipped", "seconds"):
        assert key in out


def test_clip_is_deleted_after_stop(tmp_path, config_dir):
    svc, _, _ = make(tmp_path, config_dir)
    svc.start()
    svc.stop()
    assert not (tmp_path / "clip.wav").exists()


def test_config_reread_each_stop(tmp_path, config_dir):
    svc, _, _ = make(tmp_path, config_dir, text="foo")
    svc.start()
    assert svc.stop()["text"] == "foo"
    (config_dir / "replacements.txt").write_text("foo => bar\n")
    svc.start()
    assert svc.stop()["text"] == "bar"


def test_empty_transcript_warns_no_speech(tmp_path, config_dir):
    svc, _, _ = make(tmp_path, config_dir, text="  ")
    svc.start()
    out = svc.stop()
    assert out["text"] == ""
    assert out["warning"] == "no speech"


def test_stop_without_start(tmp_path, config_dir):
    svc, _, _ = make(tmp_path, config_dir)
    assert svc.stop() == {"text": "", "warning": "not recording"}


def test_cancel_without_start(tmp_path, config_dir):
    svc, _, _ = make(tmp_path, config_dir)
    assert svc.cancel() == {"ok": True}


def test_start_reports_recorder_failure(tmp_path, config_dir):
    svc, _, _ = make(tmp_path, config_dir, fail=True)
    assert svc.start() == {"ok": False, "warning": "no audio – check mic"}
    assert svc.health() == {"ok": True, "recording": False}


def test_second_start_restarts(tmp_path, config_dir):
    svc, rec, _ = make(tmp_path, config_dir)
    assert svc.start() == {"ok": True}
    assert svc.start() == {"ok": True}
    assert rec.cancels == 1
    assert svc.health()["recording"] is True


def test_cancel_stops_recording(tmp_path, config_dir):
    svc, rec, _ = make(tmp_path, config_dir)
    svc.start()
    svc.cancel()
    assert rec.cancels == 1
    assert svc.health()["recording"] is False


def test_calls_are_serialized(tmp_path, config_dir):
    gate = threading.Event()
    svc, _, _ = make(tmp_path, config_dir, gate=gate)
    svc.start()
    stopper = threading.Thread(target=svc.stop)
    stopper.start()
    time.sleep(0.1)
    done = threading.Event()
    starter = threading.Thread(target=lambda: (svc.start(), done.set()))
    starter.start()
    time.sleep(0.2)
    assert not done.is_set()
    gate.set()
    stopper.join(5)
    starter.join(5)
    assert done.is_set()


IDLE = {
    "state": "idle",
    "level_dbfs": None,
    "elapsed_s": None,
    "warning": None,
    "warning_age_s": None,
}


def test_status_idle(tmp_path, config_dir):
    svc, _, _ = make(tmp_path, config_dir)
    assert svc.status() == IDLE


def test_status_recording_has_level_and_elapsed(tmp_path, config_dir):
    svc, _, _ = make(tmp_path, config_dir)
    svc.start()
    st = svc.status()
    assert st["state"] == "recording"
    assert st["level_dbfs"] == -30.0
    assert 0.0 <= st["elapsed_s"] < 1.0


def test_status_keeps_last_warning(tmp_path, config_dir):
    svc, _, _ = make(tmp_path, config_dir, tone(1.0, -60.0))
    svc.start()
    svc.stop()
    st = svc.status()
    assert st["state"] == "idle"
    assert st["warning"] == "no audio – check mic"
    assert st["warning_age_s"] >= 0.0


def test_status_ignores_not_recording(tmp_path, config_dir):
    svc, _, _ = make(tmp_path, config_dir)
    svc.stop()
    assert svc.status() == IDLE


def test_status_during_transcription_does_not_block(tmp_path, config_dir):
    gate = threading.Event()
    svc, _, _ = make(tmp_path, config_dir, gate=gate)
    svc.start()
    stopper = threading.Thread(target=svc.stop)
    stopper.start()
    time.sleep(0.1)
    began = time.perf_counter()
    st = svc.status()
    assert time.perf_counter() - began < 0.5
    assert st["state"] == "transcribing"
    gate.set()
    stopper.join(5)
    assert svc.status()["state"] == "idle"


def test_status_reports_capture_stopped(tmp_path, config_dir):
    svc, rec, _ = make(tmp_path, config_dir)
    rec.live_level = lambda: None
    svc.start()
    st = svc.status()
    assert st["state"] == "stopped"
    assert st["level_dbfs"] is None
    assert st["elapsed_s"] is None
