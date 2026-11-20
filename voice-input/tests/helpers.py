import wave
from pathlib import Path

import numpy as np

RATE = 16000


def write_wav(path: Path, samples) -> Path:
    data = np.clip(np.asarray(samples), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    return path


def tone(seconds: float, dbfs: float) -> np.ndarray:
    t = np.arange(int(seconds * RATE)) / RATE
    return 32767 * 10 ** (dbfs / 20) * np.sin(2 * np.pi * 440 * t)
