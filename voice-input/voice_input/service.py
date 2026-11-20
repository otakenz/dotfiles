"""Start/stop logic between the recorder and the transcriber."""

import threading
import time
from dataclasses import asdict
from pathlib import Path
from typing import Protocol

from .audio import measure
from .config import apply_replacements, load_replacements, load_vocab

MIN_DURATION_S = 0.3
MIN_PEAK_DBFS = -45.0
NO_AUDIO = "no audio – check mic"
NO_SPEECH = "no speech"
NOT_RECORDING = "not recording"


class Recorder(Protocol):
    def start(self) -> None: ...

    def stop(self) -> Path | None: ...

    def cancel(self) -> None: ...


class Transcriber(Protocol):
    def transcribe(self, wav: Path, prompt: str) -> str: ...


class VoiceService:
    def __init__(
        self, recorder: Recorder, transcriber: Transcriber, config_dir: Path
    ):
        self._recorder = recorder
        self._transcriber = transcriber
        self._config_dir = config_dir
        self._lock = threading.Lock()
        self._recording = False

    def start(self) -> dict:
        with self._lock:
            if self._recording:
                self._recorder.cancel()
                self._recording = False
            try:
                self._recorder.start()
            except RuntimeError:
                return {"ok": False, "warning": NO_AUDIO}
            self._recording = True
            return {"ok": True}

    def stop(self) -> dict:
        with self._lock:
            if not self._recording:
                return {"text": "", "warning": NOT_RECORDING}
            self._recording = False
            began = time.perf_counter()
            clip = self._recorder.stop()
            if clip is None:
                return {"text": "", "warning": NO_AUDIO}
            try:
                return self._finish(clip, began)
            finally:
                clip.unlink(missing_ok=True)

    def cancel(self) -> dict:
        with self._lock:
            if self._recording:
                self._recorder.cancel()
                self._recording = False
            return {"ok": True}

    def health(self) -> dict:
        return {"ok": True, "recording": self._recording}

    def _finish(self, clip: Path, began: float) -> dict:
        level = measure(clip)
        text, warning = "", None
        if level.duration_s < MIN_DURATION_S:
            pass
        elif level.peak_dbfs < MIN_PEAK_DBFS:
            warning = NO_AUDIO
        else:
            prompt = load_vocab(self._config_dir / "vocab.txt")
            raw = self._transcriber.transcribe(clip, prompt)
            rules = load_replacements(self._config_dir / "replacements.txt")
            text = apply_replacements(raw, rules)
            if not text:
                warning = NO_SPEECH
        return {
            "text": text,
            "warning": warning,
            **asdict(level),
            "seconds": round(time.perf_counter() - began, 2),
        }
