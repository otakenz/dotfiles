import numpy as np
import pytest
from helpers import tone, write_wav
from voice_input.audio import measure, tail_dbfs


def test_silence_level(tmp_path):
    lv = measure(write_wav(tmp_path / "s.wav", np.zeros(16000)))
    assert lv.duration_s == 1.0
    assert lv.peak_dbfs == -120.0
    assert lv.mean_dbfs == -120.0
    assert lv.clipped == 0


def test_full_scale_counts_clipping(tmp_path):
    samples = np.zeros(16000)
    samples[::2] = 32767
    lv = measure(write_wav(tmp_path / "c.wav", samples))
    assert lv.peak_dbfs == pytest.approx(0.0, abs=0.01)
    assert lv.clipped == 8000


def test_tone_level(tmp_path):
    lv = measure(write_wav(tmp_path / "t.wav", tone(0.5, -20.0)))
    assert lv.duration_s == 0.5
    assert lv.peak_dbfs == pytest.approx(-20.0, abs=0.1)
    assert lv.mean_dbfs == pytest.approx(-23.0, abs=0.2)


def test_tail_dbfs_reads_last_samples(tmp_path):
    samples = np.concatenate([np.zeros(16000), tone(0.1, -20.0)])
    wav = write_wav(tmp_path / "t.wav", samples)
    assert tail_dbfs(wav) == pytest.approx(-23.0, abs=0.3)


def test_tail_dbfs_short_or_missing(tmp_path):
    assert tail_dbfs(tmp_path / "nope.wav") == -120.0
    header_only = write_wav(tmp_path / "h.wav", np.zeros(0))
    assert tail_dbfs(header_only) == -120.0
