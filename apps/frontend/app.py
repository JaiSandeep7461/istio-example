from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import URLError
from urllib.request import Request, urlopen
import os

CATALOG_URL = os.getenv("CATALOG_URL", "http://catalog:5678/")
REVIEWS_URL = os.getenv("REVIEWS_URL", "http://reviews:5678/")

class Handler(BaseHTTPRequestHandler):
    def respond(self, status, body):
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/":
            return self.respond(200, "Online shop frontend is healthy. Try /call/catalog and /call/reviews\\n")
        if self.path.startswith("/call/catalog"):
            return self.call_service(CATALOG_URL)
        if self.path.startswith("/call/reviews"):
            return self.call_service(REVIEWS_URL)
        return self.respond(404, "not found\\n")

    def call_service(self, url):
        try:
            req = Request(url, headers={"User-Agent": "istio-lab-frontend/1.0"})
            with urlopen(req, timeout=2) as response:
                return self.respond(response.status, response.read().decode("utf-8", errors="replace"))
        except (URLError, TimeoutError) as exc:
            return self.respond(502, f"upstream request failed: {exc}\\n")

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)

if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
