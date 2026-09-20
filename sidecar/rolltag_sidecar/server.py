import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from .hashutil import content_hash
from .suggest import suggest_tags


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        if not raw:
            return {}
        return json.loads(raw.decode("utf-8"))

    def do_GET(self) -> None:
        if self.path == "/health":
            self._json(200, {"ok": True, "version": "0.1.0"})
            return
        self._json(404, {"error": "not_found"})

    def do_POST(self) -> None:
        try:
            data = self._read_json()
        except json.JSONDecodeError:
            self._json(400, {"error": "invalid_json"})
            return

        if self.path == "/hash":
            path = data.get("path")
            if not path:
                self._json(400, {"error": "missing_path"})
                return
            try:
                self._json(200, {"content_hash": content_hash(path)})
            except OSError as exc:
                self._json(400, {"error": str(exc)})
            return

        if self.path == "/embed":
            self._json(501, {"error": "not_enabled"})
            return

        if self.path == "/suggest_tags":
            provider = data.get("provider")
            api_key = data.get("api_key")
            model = data.get("model") or ""
            frames = data.get("frames") or []
            catalog = data.get("catalog") or {}
            context = data.get("context") or {}
            if provider not in ("gemini", "openai"):
                self._json(400, {"error": "unsupported_provider"})
                return
            try:
                self._json(
                    200,
                    suggest_tags(
                        provider=provider,
                        api_key=api_key or "",
                        model=model,
                        frames=frames,
                        catalog=catalog if isinstance(catalog, dict) else {},
                        context=context if isinstance(context, dict) else None,
                    ),
                )
            except ValueError as exc:
                self._json(400, {"error": str(exc)})
            except Exception as exc:
                self._json(502, {"error": str(exc)[:300]})
            return

        self._json(404, {"error": "not_found"})


def main() -> None:
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    host, port = server.server_address
    print(f"READY {host}:{port}", flush=True)
    server.serve_forever()
