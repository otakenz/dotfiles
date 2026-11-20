"""HTTP front end for VoiceService, bound to loopback only."""

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 47821
CLIENT_HEADER = "X-Voice-Input"
ROUTES = {
    ("POST", "/start"): "start",
    ("POST", "/stop"): "stop",
    ("POST", "/cancel"): "cancel",
    ("GET", "/health"): "health",
}


def make_server(service, host: str = HOST, port: int = PORT):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self._dispatch("GET")

        def do_POST(self):
            self._dispatch("POST")

        def _dispatch(self, method):
            length = int(self.headers.get("Content-Length") or 0)
            if length:
                self.rfile.read(length)
            if not self._trusted():
                self._reply(403, {"warning": "forbidden"})
                return
            name = ROUTES.get((method, self.path))
            if name is None:
                self._reply(404, {"warning": "not found"})
                return
            try:
                result = getattr(service, name)()
            except Exception as err:  # noqa: BLE001 - any failure → 500
                print(f"voice-input: {name} failed: {err}", file=sys.stderr)
                self._reply(500, {"warning": str(err)})
                return
            self._reply(200, result)

        # Browsers cannot send a custom header cross-origin without a CORS
        # preflight (never answered), and the Host check stops DNS rebinding.
        def _trusted(self):
            if self.headers.get(CLIENT_HEADER) != "1":
                return False
            host = (self.headers.get("Host") or "").rsplit(":", 1)[0]
            return host in ("127.0.0.1", "localhost")

        def _reply(self, status, body):
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *args):
            pass

    return ThreadingHTTPServer((host, port), Handler)
