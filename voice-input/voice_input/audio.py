"""Level of a 16-bit mono WAV clip."""

import math
import wave
from dataclasses import dataclass
from pathlib import Path

import numpy as np

SILENT_DBFS = -120.0


@dataclass(frozen=True)
class Level:
    duration_s: float
    peak_dbfs: float
    mean_dbfs: float
    clipped: int


def _dbfs(value: float) -> float:
    if value <= 0:
        return SILENT_DBFS
    return max(SILENT_DBFS, 20 * math.log10(value / 32767))


def measure(wav: Path) -> Level:
    with wave.open(str(wav), "rb") as w:
        rate = w.getframerate()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")
    samples = data.astype(np.float64)
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    rms = float(np.sqrt(np.mean(samples**2))) if samples.size else 0.0
    clipped = int(np.count_nonzero((data == 32767) | (data == -32768)))
    return Level(
        duration_s=data.size / rate,
        peak_dbfs=round(_dbfs(peak), 2),
        mean_dbfs=round(_dbfs(rms), 2),
        clipped=clipped,
    )


def tail_dbfs(wav: Path, seconds: float = 0.1) -> float:
    """RMS level of the last `seconds` of a 16 kHz mono WAV still being
    written; reads only the tail, since the header sizes are not final."""
    want = int(seconds * 16000) * 2
    try:
        with wav.open("rb") as f:
            size = f.seek(0, 2)
            if size <= 44:
                return SILENT_DBFS
            start = max(44, size - want)
            start -= (start - 44) % 2
            f.seek(start)
            data = np.frombuffer(f.read(), dtype="<i2")
    except FileNotFoundError:
        return SILENT_DBFS
    if not data.size:
        return SILENT_DBFS
    rms = float(np.sqrt(np.mean(data.astype(np.float64) ** 2)))
    return round(_dbfs(rms), 2)
