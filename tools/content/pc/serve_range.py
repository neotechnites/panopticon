r"""Static file server that honours HTTP Range, for seeking into big local files.

    python serve_range.py <port> --bind <addr> --directory <dir>
"""
import argparse
import contextlib
import http.server
import os
import socket
import urllib.parse
from http import HTTPStatus

COPY_CHUNK = 64 * 1024
INDEX_PAGES = ("index.html", "index.htm")


def parse_range(value, size):
    # "bytes=S-E" | "bytes=S-" | "bytes=-N" -> (start, end) inclusive, end clamped.
    # None means malformed or multi-range: the caller serves the whole file.
    if not value or not value.strip().lower().startswith("bytes="):
        return None
    spec = value.strip()[len("bytes="):].strip()
    if "," in spec or "-" not in spec:
        return None
    first, _, last = spec.partition("-")
    first, last = first.strip(), last.strip()
    try:
        if not first:
            if not last:
                return None
            length = int(last)
            if length <= 0:
                return (size, size)
            return (max(0, size - length), size - 1)
        start = int(first)
        if start < 0:
            return None
        if not last:
            return (start, size - 1)
        end = min(int(last), size - 1)
    except ValueError:
        return None
    if end < start:
        return None
    return (start, end)


class RangeHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    server_version = "PanopticonRange/1.0"
    accept_ranges = False
    range_remaining = None

    def handle_one_request(self):
        self.accept_ranges = False
        self.range_remaining = None
        super().handle_one_request()

    def end_headers(self):
        # Advertise range support on every file response, 200 and 206 alike.
        if self.accept_ranges:
            self.send_header("Accept-Ranges", "bytes")
        super().end_headers()

    def resolved_file(self):
        # The local file this request serves, or None for listings and redirects.
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            if not urllib.parse.urlsplit(self.path).path.endswith("/"):
                return None
            for index in INDEX_PAGES:
                candidate = os.path.join(path, index)
                if os.path.isfile(candidate):
                    return candidate
            return None
        return path if os.path.isfile(path) else None

    def send_head(self):
        self.range_remaining = None
        target = self.resolved_file()
        self.accept_ranges = target is not None
        header = self.headers.get("Range") if target else None
        if header is None:
            return super().send_head()
        try:
            size = os.path.getsize(target)
        except OSError:
            return super().send_head()
        span = parse_range(header, size)
        if span is None:
            return super().send_head()
        start, end = span
        if start >= size:
            self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
            self.send_header("Content-Range", "bytes */%d" % size)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None
        try:
            f = open(target, "rb")
        except OSError:
            self.send_error(HTTPStatus.NOT_FOUND, "File not found")
            return None
        try:
            f.seek(start)
            self.send_response(HTTPStatus.PARTIAL_CONTENT)
            self.send_header("Content-type", self.guess_type(target))
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
            self.send_header("Content-Length", str(end - start + 1))
            self.send_header("Last-Modified",
                             self.date_time_string(os.stat(target).st_mtime))
            self.end_headers()
        except BaseException:
            f.close()
            raise
        self.range_remaining = end - start + 1
        return f

    def copyfile(self, source, outputfile):
        # A 206 copies only its span; the base class would copy the whole file.
        if self.range_remaining is None:
            return super().copyfile(source, outputfile)
        remaining = self.range_remaining
        while remaining > 0:
            chunk = source.read(min(COPY_CHUNK, remaining))
            if not chunk:
                break
            outputfile.write(chunk)
            remaining -= len(chunk)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("port", default=8000, type=int, nargs="?",
                        help="bind to this port (default: %(default)s)")
    parser.add_argument("--bind", metavar="ADDRESS",
                        help="bind to this address (default: all interfaces)")
    parser.add_argument("--directory", default=os.getcwd(),
                        help="serve this directory (default: current directory)")
    args = parser.parse_args()

    class DualStackServer(http.server.ThreadingHTTPServer):

        def server_bind(self):
            with contextlib.suppress(Exception):
                self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            return super().server_bind()

        def finish_request(self, request, client_address):
            self.RequestHandlerClass(request, client_address, self,
                                     directory=args.directory)

    http.server.test(HandlerClass=RangeHTTPRequestHandler,
                     ServerClass=DualStackServer,
                     port=args.port,
                     bind=args.bind)


if __name__ == "__main__":
    main()
