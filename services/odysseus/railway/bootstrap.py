"""One-time setup of a fresh Odysseus instance on Railway, through its own HTTP API.

Runs in the background next to the app (started by start.sh). It waits for
/api/health on loopback, signs in with the generated admin account and then
applies each step at most once (a marker file per step under
/app/data/.railway-bootstrap/):

* app_public_url  -> the Railway public URL (deep links in alerts)
* ntfy            -> an ntfy integration pointing at the private ntfy service,
                     authenticated with the provisioned access token, and the
                     reminder channel switched to ntfy
* model endpoints -> an OpenAI-compatible provider from LLM_PROVIDER_* and the
                     bundled Ollama service; the first one with a named model
                     (LLM_PROVIDER_MODEL, then OLLAMA_MODEL) becomes the
                     default chat model when none is set

Everything the user later changes in Settings wins: a step that already ran is
never repeated, and a step whose admin login fails (password changed) is
skipped. Secrets are never logged.
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Optional

BASE_URL = "http://127.0.0.1:7000"
STATE_DIR = "/app/data/.railway-bootstrap"
HEALTH_TIMEOUT_SECONDS = 1200


def log(message: str) -> None:
    print(f"[railway-bootstrap] {message}", flush=True)


def env(name: str, default: str = "") -> str:
    return (os.environ.get(name) or default).strip()


class Api:
    """Minimal JSON/form client that carries the session cookie by hand."""

    def __init__(self, base_url: str) -> None:
        self.base_url = base_url
        self.cookie = ""

    def request(
        self,
        method: str,
        path: str,
        json_body: Optional[dict] = None,
        form: Optional[dict] = None,
        timeout: float = 60,
    ) -> tuple[int, Any, Any]:
        headers = {"Accept": "application/json"}
        data = None
        if json_body is not None:
            data = json.dumps(json_body).encode()
            headers["Content-Type"] = "application/json"
        elif form is not None:
            data = urllib.parse.urlencode(form).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        if self.cookie:
            headers["Cookie"] = self.cookie
        req = urllib.request.Request(self.base_url + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                status, raw, resp_headers = resp.status, resp.read(), resp.headers
        except urllib.error.HTTPError as exc:
            status, raw, resp_headers = exc.code, exc.read(), exc.headers
        try:
            body = json.loads(raw.decode() or "null")
        except (ValueError, UnicodeDecodeError):
            body = None
        return status, body, resp_headers

    def login(self, username: str, password: str) -> bool:
        status, body, headers = self.request(
            "POST", "/api/auth/login", json_body={"username": username, "password": password}
        )
        if status != 200 or not isinstance(body, dict) or not body.get("ok"):
            return False
        pairs = []
        for raw_cookie in headers.get_all("Set-Cookie") or []:
            pair = raw_cookie.split(";", 1)[0].strip()
            if "=" in pair:
                pairs.append(pair)
        self.cookie = "; ".join(pairs)
        return bool(self.cookie)


def wait_for(url: str, timeout_seconds: float) -> bool:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=5) as resp:
                if 200 <= resp.status < 300:
                    return True
        except Exception:
            pass
        time.sleep(3)
    return False


def marker_path(step: str) -> str:
    return os.path.join(STATE_DIR, f"{step}.done")


def is_done(step: str) -> bool:
    return os.path.exists(marker_path(step))


def mark_done(step: str) -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    path = marker_path(step)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) + "\n")
    uid, gid = int(env("PUID", "1000")), int(env("PGID", "1000"))
    for target in (STATE_DIR, path):
        try:
            os.chown(target, uid, gid)
        except OSError:
            pass


def get_settings(api: Api) -> dict:
    status, body, _ = api.request("GET", "/api/auth/settings")
    return body if status == 200 and isinstance(body, dict) else {}


def save_settings(api: Api, values: dict) -> bool:
    status, _, _ = api.request("POST", "/api/auth/settings", json_body=values)
    return status == 200


def step_public_url(api: Api) -> None:
    domain = env("RAILWAY_PUBLIC_DOMAIN")
    if not domain or is_done("public-url"):
        return
    if not get_settings(api).get("app_public_url"):
        if not save_settings(api, {"app_public_url": f"https://{domain}"}):
            log("could not set app_public_url")
            return
        log(f"app_public_url set to https://{domain}")
    mark_done("public-url")


def step_ntfy(api: Api) -> None:
    base_url = env("NTFY_INTERNAL_URL").rstrip("/")
    token = env("NTFY_PUBLISH_TOKEN")
    topic = env("NTFY_TOPIC", "odysseus")
    if not base_url or not token or is_done("ntfy"):
        return
    status, body, _ = api.request("GET", "/api/auth/integrations")
    existing = body if status == 200 and isinstance(body, list) else []
    if isinstance(body, dict):
        existing = body.get("integrations") or []
    already = any(
        isinstance(item, dict)
        and item.get("preset") == "ntfy"
        and (item.get("base_url") or "").rstrip("/") == base_url
        for item in existing
    )
    if not already:
        status, _, _ = api.request(
            "POST",
            "/api/auth/integrations",
            json_body={
                "preset": "ntfy",
                "name": "ntfy (Railway)",
                "base_url": base_url,
                "auth_type": "bearer",
                "api_key": token,
                "enabled": True,
            },
        )
        if status != 200:
            log(f"creating the ntfy integration failed (HTTP {status})")
            return
        log(f"ntfy integration created for {base_url}")
    if not save_settings(api, {"reminder_channel": "ntfy", "reminder_ntfy_topic": topic}):
        log("could not switch the reminder channel to ntfy")
        return
    log(f"reminders now go to ntfy topic '{topic}' (plus in-app notifications)")
    mark_done("ntfy")


def ollama_has_model(ollama_url: str, model: str) -> bool:
    try:
        with urllib.request.urlopen(f"{ollama_url}/api/tags", timeout=10) as resp:
            tags = json.loads(resp.read().decode() or "{}")
    except Exception:
        return False
    names = {m.get("name") for m in tags.get("models", []) if isinstance(m, dict)}
    wanted = model if ":" in model else f"{model}:latest"
    return wanted in names or model in names


def register_endpoint(
    api: Api, step: str, name: str, base_url: str, api_key: str, model: str, kind: str
) -> None:
    if is_done(step):
        return
    form = {
        "name": name,
        "base_url": base_url,
        "api_key": api_key,
        "endpoint_kind": kind,
        "shared": "true",
    }
    if model:
        form["pinned_models"] = json.dumps([model])
    status, body, _ = api.request("POST", "/api/model-endpoints", form=form, timeout=120)
    if status != 200 or not isinstance(body, dict) or not body.get("id"):
        detail = body.get("detail") if isinstance(body, dict) else ""
        log(f"registering model endpoint '{name}' failed (HTTP {status}) {detail}".strip())
        return
    log(f"model endpoint '{name}' registered ({base_url})")
    chosen = model  # only an explicitly named model becomes the default
    settings = get_settings(api)
    if chosen and not settings.get("default_model"):
        if save_settings(api, {"default_endpoint_id": body["id"], "default_model": chosen}):
            log(f"default chat model set to '{chosen}' on '{name}'")
    mark_done(step)


def llm_provider_step() -> Optional[tuple[str, str, str, str, str]]:
    api_key = env("LLM_PROVIDER_API_KEY")
    if not api_key:
        return None
    base_url = env("LLM_PROVIDER_BASE_URL", "https://api.openai.com/v1").rstrip("/")
    digest = hashlib.sha256(base_url.encode()).hexdigest()[:12]
    host = urllib.parse.urlparse(base_url).hostname or "provider"
    return f"llm-{digest}", host, base_url, api_key, env("LLM_PROVIDER_MODEL")


def ollama_step() -> Optional[tuple[str, str, str]]:
    ollama_url = env("OLLAMA_BASE_URL").rstrip("/")
    model = env("OLLAMA_MODEL")
    if not ollama_url or not model:
        return None
    digest = hashlib.sha256(f"{ollama_url}|{model}".encode()).hexdigest()[:12]
    return f"ollama-{digest}", ollama_url, model


def pending_steps() -> list[str]:
    pending = []
    if env("RAILWAY_PUBLIC_DOMAIN") and not is_done("public-url"):
        pending.append("public-url")
    if env("NTFY_INTERNAL_URL") and env("NTFY_PUBLISH_TOKEN") and not is_done("ntfy"):
        pending.append("ntfy")
    llm = llm_provider_step()
    if llm and not is_done(llm[0]):
        pending.append(llm[0])
    ollama = ollama_step()
    if ollama and not is_done(ollama[0]):
        pending.append(ollama[0])
    return pending


def run_llm_provider(api: Api) -> None:
    llm = llm_provider_step()
    if llm:
        step, host, base_url, api_key, model = llm
        register_endpoint(api, step, host, base_url, api_key, model, "api")


def run_ollama(api: Api) -> None:
    ollama = ollama_step()
    if not ollama or is_done(ollama[0]):
        return
    step, ollama_url, model = ollama
    wait_seconds = float(env("OLLAMA_WAIT_SECONDS", "3600"))
    log(f"waiting up to {int(wait_seconds)}s for Ollama to serve '{model}'")
    deadline = time.monotonic() + wait_seconds
    while not ollama_has_model(ollama_url, model):
        if time.monotonic() >= deadline:
            log(f"Ollama model '{model}' not available yet; will retry on next start")
            return
        time.sleep(15)
    register_endpoint(api, step, "Ollama (Railway)", f"{ollama_url}/v1", "", model, "local")


def main() -> int:
    pending = pending_steps()
    if not pending:
        return 0
    log(f"pending steps: {', '.join(pending)}")
    if not wait_for(f"{BASE_URL}/api/health", HEALTH_TIMEOUT_SECONDS):
        log("Odysseus did not become healthy; bootstrap skipped")
        return 0
    username = env("ODYSSEUS_ADMIN_USER", "admin").lower()
    password = env("ODYSSEUS_ADMIN_PASSWORD")
    api = Api(BASE_URL)
    if not password or not api.login(username, password):
        log("admin login with ODYSSEUS_ADMIN_PASSWORD failed (changed in the app?); bootstrap skipped")
        return 0
    for step in (step_public_url, step_ntfy, run_llm_provider, run_ollama):
        try:
            step(api)
        except Exception as exc:  # one failed step must not block the others
            log(f"{step.__name__} failed: {type(exc).__name__}: {exc}")
    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
