"""voice-input serve | check"""

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

from .server import CLIENT_HEADER, HOST, PORT, make_server

BASE = f"http://{HOST}:{PORT}"
CONFIG_DIR = Path.home() / ".config/voice-input"


def serve() -> int:
    from .recorder import ParecordRecorder
    from .service import VoiceService
    from .transcriber import WhisperTranscriber, default_model_dir

    service = VoiceService(
        ParecordRecorder(),
        WhisperTranscriber(default_model_dir()),
        CONFIG_DIR,
    )
    server = make_server(service)
    print(f"voice-input: ready on {BASE}", file=sys.stderr, flush=True)
    server.serve_forever()
    return 0


def _post(path: str, timeout: float) -> dict:
    req = urllib.request.Request(
        BASE + path, method="POST", data=b"", headers={CLIENT_HEADER: "1"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def check() -> int:
    try:
        started = _post("/start", 2)
    except (urllib.error.URLError, OSError):
        print(
            "voice service not running – systemctl --user status voice-input"
        )
        return 1
    if not started.get("ok"):
        print(f"warning: {started.get('warning')}")
        return 1
    try:
        input("Recording… speak, then press Enter. ")
    except (KeyboardInterrupt, EOFError):
        _post("/cancel", 2)
        print()
        return 1
    result = _post("/stop", 20)
    for key in ("peak_dbfs", "mean_dbfs", "clipped", "duration_s"):
        print(f"{key}: {result.get(key)}")
    print(f"seconds: {result.get('seconds')}")
    print(f"warning: {result.get('warning')}")
    print(f"text: {result.get('text')}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="voice-input")
    parser.add_argument("command", choices=["serve", "check"])
    args = parser.parse_args()
    return serve() if args.command == "serve" else check()


if __name__ == "__main__":
    sys.exit(main())
