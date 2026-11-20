import json
import threading
import urllib.error
import urllib.request

import pytest
from voice_input.server import make_server


class FakeService:
    def __init__(self):
        self.stop_error = None
        self.calls = []

    def start(self):
        self.calls.append("start")
        return {"ok": True}

    def stop(self):
        if self.stop_error:
            raise self.stop_error
        return {"text": "hi", "warning": None}

    def cancel(self):
        return {"ok": True}

    def health(self):
        return {"ok": True, "recording": False}


@pytest.fixture
def served():
    svc = FakeService()
    server = make_server(svc, port=0)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield svc, server, f"http://127.0.0.1:{server.server_address[1]}"
    server.shutdown()
    server.server_close()


def call(url, method, headers=None):
    if headers is None:
        headers = {"X-Voice-Input": "1"}
    req = urllib.request.Request(url, method=method, data=b"", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as err:
        body = err.read()
        return err.code, json.loads(body) if body else None


def test_routes_return_service_json(served):
    _, _, base = served
    assert call(base + "/start", "POST") == (200, {"ok": True})
    assert call(base + "/stop", "POST") == (
        200,
        {"text": "hi", "warning": None},
    )
    assert call(base + "/cancel", "POST") == (200, {"ok": True})
    assert call(base + "/health", "GET") == (
        200,
        {"ok": True, "recording": False},
    )


def test_unknown_path_is_404(served):
    _, _, base = served
    assert call(base + "/nope", "POST")[0] == 404
    assert call(base + "/start", "GET")[0] == 404


def test_service_error_is_500_with_warning(served):
    svc, _, base = served
    svc.stop_error = RuntimeError("boom")
    assert call(base + "/stop", "POST") == (500, {"warning": "boom"})


def test_non_ascii_text_survives(served):
    svc, _, base = served
    svc.stop = lambda: {"text": "naïve – ok", "warning": None}
    assert call(base + "/stop", "POST")[1]["text"] == "naïve – ok"


def test_binds_loopback_only(served):
    _, server, _ = served
    assert server.server_address[0] == "127.0.0.1"


def test_request_without_client_header_is_rejected(served):
    svc, _, base = served
    assert call(base + "/start", "POST", headers={})[0] == 403
    assert svc.calls == []


def test_foreign_host_header_is_rejected(served):
    svc, _, base = served
    headers = {"X-Voice-Input": "1", "Host": "evil.example:47821"}
    assert call(base + "/start", "POST", headers=headers)[0] == 403
    assert svc.calls == []


def test_localhost_host_header_is_accepted(served):
    _, server, base = served
    port = server.server_address[1]
    headers = {"X-Voice-Input": "1", "Host": f"localhost:{port}"}
    assert call(base + "/start", "POST", headers=headers)[0] == 200
