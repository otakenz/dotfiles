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

    def live_level(self) -> float | None: ...


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
        self._state = "idle"
        self._started_at: float | None = None
        self._warning: str | None = None
        self._warning_at: float | None = None

    def start(self) -> dict:
        with self._lock:
            if self._recording:
                self._recorder.cancel()
                self._recording = False
            try:
                self._recorder.start()
            except RuntimeError:
                self._state = "idle"
                self._remember(NO_AUDIO)
                return {"ok": False, "warning": NO_AUDIO}
            self._recording = True
            self._state = "recording"
            self._started_at = time.monotonic()
            return {"ok": True}

    def stop(self) -> dict:
        with self._lock:
            if not self._recording:
                return {"text": "", "warning": NOT_RECORDING}
            self._recording = False
            self._state = "transcribing"
            began = time.perf_counter()
            try:
                clip = self._recorder.stop()
                if clip is None:
                    result = {"text": "", "warning": NO_AUDIO}
                else:
                    try:
                        result = self._finish(clip, began)
                    finally:
                        clip.unlink(missing_ok=True)
            finally:
                self._state = "idle"
            self._remember(result["warning"])
            return result

    def cancel(self) -> dict:
        with self._lock:
            if self._recording:
                self._recorder.cancel()
                self._recording = False
                self._state = "idle"
            return {"ok": True}

    def status(self) -> dict:
        # No lock: must answer while stop() is transcribing.
        state = self._state
        level = self._recorder.live_level() if state == "recording" else None
        if state == "recording" and level is None:
            state = "stopped"  # time limit reached or parecord exited
        recording = state == "recording"
        started, warning_at = self._started_at, self._warning_at
        return {
            "state": state,
            "level_dbfs": level,
            "elapsed_s": (
                round(time.monotonic() - started, 1)
                if recording and started is not None
                else None
            ),
            "warning": self._warning,
            "warning_age_s": (
                round(time.monotonic() - warning_at, 1)
                if warning_at is not None
                else None
            ),
        }

    def _remember(self, warning: str | None) -> None:
        self._warning = warning
        self._warning_at = time.monotonic() if warning else None

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
