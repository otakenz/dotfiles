"""faster-whisper large-v3-turbo on the GPU, loaded once."""

from pathlib import Path

import numpy as np

MODELS = Path.home() / ".local/share/voice-input/models"
TURBO = "models--mobiuslabsgmbh--faster-whisper-large-v3-turbo"


def default_model_dir() -> Path:
    found = sorted((MODELS / TURBO / "snapshots").glob("*"))
    if not found:
        raise FileNotFoundError(f"no model under {MODELS / TURBO}")
    return found[-1]


class WhisperTranscriber:
    def __init__(self, model_dir: Path):
        from faster_whisper import WhisperModel

        self._model = WhisperModel(
            str(model_dir), device="cuda", compute_type="float16"
        )
        # The first call initialises CUDA kernels; do it before the user waits.
        segments, _ = self._model.transcribe(
            np.zeros(16000, dtype=np.float32), language="en"
        )
        list(segments)

    def transcribe(self, wav: Path, prompt: str) -> str:
        segments, _ = self._model.transcribe(
            str(wav),
            language="en",
            beam_size=5,
            vad_filter=True,
            initial_prompt=prompt or None,
        )
        return " ".join(s.text.strip() for s in segments).strip()
