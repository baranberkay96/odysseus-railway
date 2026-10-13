"""Wait until an HTTP URL answers 2xx. Usage: wait_http.py URL TIMEOUT_SECONDS.

Exit code 0 when the URL answered in time, 1 otherwise. Private DNS names on
Railway may not resolve for the first seconds of a deploy, so every error is
retried until the deadline.
"""
import sys
import time
import urllib.request


def main() -> int:
    url = sys.argv[1]
    deadline = time.monotonic() + float(sys.argv[2])
    while True:
        try:
            with urllib.request.urlopen(url, timeout=5) as resp:
                if 200 <= resp.status < 300:
                    return 0
        except Exception:
            pass
        if time.monotonic() >= deadline:
            return 1
        time.sleep(3)


if __name__ == "__main__":
    sys.exit(main())
