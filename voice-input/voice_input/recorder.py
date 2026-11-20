"""Mic recording with parecord (WSLg exposes the Windows mic as RDPSource)."""

import itertools
import os
import signal
import subprocess
import threading
import time
from pathlib import Path

from .audio import tail_dbfs

STARTUP_CHECK_S = 0.2


def _parecord(device: str) -> tuple[str, ...]:
    return (
        "parecord",
        f"--device={device}",
        "--rate=16000",
        "--channels=1",
        "--file-format=wav",
    )


class ParecordRecorder:
    def __init__(
        self,
        device: str = "RDPSource",
        max_s: float = 120.0,
        command: tuple[str, ...] | None = None,
        workdir: Path | None = None,
    ):
        self._command = command or _parecord(device)
        self._max_s = max_s
        runtime = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
        self._workdir = workdir or Path(runtime)
        self._counter = itertools.count()
        self._proc: subprocess.Popen | None = None
        self._timer: threading.Timer | None = None
        self._clip: Path | None = None

    def start(self) -> None:
        self.cancel()
        n = next(self._counter)
        clip = self._workdir / f"voice-input-{os.getpid()}-{n}.wav"
        proc = subprocess.Popen(
            [*self._command, str(clip)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(STARTUP_CHECK_S)
        if proc.poll() is not None:
            clip.unlink(missing_ok=True)
            raise RuntimeError(f"recorder exited with {proc.returncode}")
        self._proc, self._clip = proc, clip
        self._timer = threading.Timer(self._max_s, self._interrupt)
        self._timer.daemon = True
        self._timer.start()

    def stop(self) -> Path | None:
        if self._proc is None:
            return None
        self._end()
        clip, self._clip = self._clip, None
        return clip if clip is not None and clip.exists() else None

    def cancel(self) -> None:
        if self._proc is None:
            return
        self._end()
        if self._clip is not None:
            self._clip.unlink(missing_ok=True)
        self._clip = None

    def live_level(self) -> float | None:
        clip, proc = self._clip, self._proc
        if proc is None or clip is None or proc.poll() is not None:
            return None
        return tail_dbfs(clip)

    def _interrupt(self) -> None:
        proc = self._proc
        if proc is not None and proc.poll() is None:
            proc.send_signal(signal.SIGINT)

    def _end(self) -> None:
        if self._timer is not None:
            self._timer.cancel()
        self._interrupt()
        try:
            self._proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self._proc.kill()
            self._proc.wait()
        self._proc, self._timer = None, None
