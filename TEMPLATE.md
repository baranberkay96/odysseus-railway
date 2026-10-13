# Odysseus v1 Private AI Workspace: Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **Odysseus v1 Private AI Workspace** (upstream `APP_VERSION = "1.0.3"`) |
| Description | Self-hosted AI workspace with web search, vector memory and alerts. (67 chars) |
| Category | AI/ML |
| Tags | odysseus, ai-workspace, ai-agents, llm, ollama, searxng, chromadb, ntfy, self-hosted, rag |
| Icon | `https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/odysseus.svg` (200 OK; same sail logo as upstream's favicon) |

The description is delivered as written: web search = bundled SearXNG, vector memory = ChromaDB + local FastEmbed embeddings, alerts = bundled ntfy with a pre-wired Odysseus integration.

## Base market template

Three market templates exist (all 2026-06, 4–13 active projects). None pins a version, none has a healthcheck, and none can chat without manual provider setup.

- **Base: `odysseus` (XavTo fork)**. It had the right service set (Odysseus, ChromaDB, SearXNG, ntfy) and volumes for the app, ChromaDB and SearXNG. Problems: builds an unreviewed fork from its default branch, `chromadb/chroma:latest` and unpinned `binwiederhier/ntfy`, ntfy on a public domain **without any authentication** (anyone can read or publish), `SECURE_COOKIES` forced, no wait for ChromaDB, HuggingFace cache / SSH identity / logs not persisted.
- `odysseus-pewdiepie` (Shinyduo fork, 12 active): fork builds for all three custom services, ChromaDB 1.0.21 (old), ntfy volume mounted at `/app/data` (ntfy does not use it), ntfy only private (alerts cannot reach a phone), "PewDiePie" naming.
- `odysseus-1` (13 active): third-party image `xiaosong233/odysseus-railway:latest`, **no volume for the app** (accounts, chats and keys are lost on redeploy), ChromaDB dev build `1.5.10.dev82` without a volume, SearXNG `2026.6.2` (upstream issue #1414: crashes on boot) without the JSON output Odysseus needs, no ntfy.

## Pinned versions

| Service | Image / source | Version | Released | Checked |
|---|---|---|---|---|
| Odysseus | `services/odysseus/Dockerfile`: `FROM ghcr.io/odysseus-dev/odysseus:1.0.3@sha256:4aa6e607d2108bd7b5f37ee1a0841dc56e6bbac36e9ccd5e1705aff7ea36fb04` | 1.0.3 (main `934d23c`) | 2026-09-05 | 2026-10-13 |
| ChromaDB | `chromadb/chroma:1.5.9@sha256:1e0b73a187a28757c572acba508c46f48c9e8b0acaf5c20e6d95cdedce1acdf6` | 1.5.9 (matches `chromadb-client` 1.5.9 in the app image) | 2026-05-05 | 2026-10-13 |
| SearXNG | `services/searxng/Dockerfile`: `searxng/searxng:2026.10.13-22c64b8d3@sha256:9b61996e…2436` | rolling build 2026.10.13 | 2026-10-13 | 2026-10-13 |
| ntfy | `services/ntfy/Dockerfile`: `binwiederhier/ntfy:v2.30.0@sha256:8563a39d…23f0` | 2.30.0 | 2026-10-12 | 2026-10-13 |
| Ollama | `services/ollama/Dockerfile`: `ollama/ollama:0.40.3@sha256:adca95a1…ff99` | 0.40.3 | 2026-10-11 | 2026-10-13 |
| Local model | `qwen3:1.7b` (Ollama library, Q4_K_M, 1.36 GB) | | | 2026-10-13 |

Odysseus has no git tags or GitHub releases; the GHCR image tags follow `APP_VERSION` in `src/constants.py`. Upstream documents `:latest` and `:X.Y.Z` as mutable and recommends `:X.Y.Z-<sha>` pins, but no such tag exists for the 1.0.3 main build, so the manifest-list digest is pinned. Upstream's own compose pins SearXNG to `2026.9.25-12f8b6515` because a broken `latest` once blocked startup; this template pins a newer build by digest for the same reason.

Upgrade Odysseus: `docker buildx imagetools inspect ghcr.io/odysseus-dev/odysseus:<new-version>`, put tag and digest into `services/odysseus/Dockerfile`, back up the Odysseus volume, redeploy. `setup.py` runs on every start and is idempotent.

## Architecture

```
Browser ── HTTPS ──► Odysseus :7000 (public, login) ── volume /app/data
                        │  sqlite app.db, auth.json, .app_key, uploads, settings,
                        │  logs, ssh, huggingface, fastembed, .local (symlinked)
                        ├── http://chromadb.railway.internal:8000  ChromaDB (volume /data)
                        ├── http://searxng.railway.internal:8080   SearXNG (format=json)
                        ├── http://ollama.railway.internal:11434/v1 Ollama qwen3:1.7b (volume /root/.ollama)
                        ├── https://{provider}/v1                  optional API provider
                        └── http://ntfy.railway.internal:8080      ntfy publish (token, write-only)
Phone / ntfy web ── HTTPS ──► ntfy :8080 (public, login, deny-all anonymous; volume /var/lib/ntfy)
```

## Services

### Odysseus

| Setting | Value |
|---|---|
| Source | repo `baranberkay96/odysseus-railway`, root `/services/odysseus` (thin Dockerfile on the official image) |
| Start | image ENTRYPOINT `/opt/railway/start.sh`, CMD `uvicorn app:app --host 0.0.0.0 --port 7000` (upstream's command) |
| Healthcheck | `/api/health` (auth-exempt liveness route), timeout 900 s (covers the 300 s ChromaDB wait, `setup.py`, ownership repair and app import) |
| Public domain | yes, port 7000; `PORT=7000` |
| Volume | `/app/data` |
| Restart | ON_FAILURE, 10 |

`railway/start.sh` (runs before upstream's entrypoint, which is kept unchanged):
1. Symlinks `/app/logs`, `/app/.ssh`, `/app/.cache/huggingface`, `/app/.local` into the volume, mirroring upstream compose's extra bind mounts (Railway allows one volume per service), and hands the new directories to PUID 1000.
2. Exits with an error if auth is on, no `auth.json` exists and `ODYSSEUS_ADMIN_PASSWORD` is shorter than 8 characters. Upstream's `setup.py` failure is non-fatal (`|| true`), which would otherwise leave the public `/api/auth/setup` page open to the first visitor.
3. Waits up to `WAIT_FOR_SERVICES_SECONDS` (300) for ChromaDB's `/api/v2/heartbeat`. Odysseus opens its vector store once at import and stays degraded until restart if ChromaDB is not up yet (`src/memory_vector.py` has no reconnect); Railway starts services in parallel.
4. Starts `railway/bootstrap.py` in the background and `exec`s upstream's `entrypoint.sh` (setup.py, ownership repair, gosu to uid 1000, uvicorn).

`railway/bootstrap.py` waits for `/api/health`, logs in with the generated admin password and applies each step once (markers in `/app/data/.railway-bootstrap/`): `app_public_url` = Railway URL; ntfy integration (private URL, bearer token) + reminder channel `ntfy`, topic `odysseus`; model endpoint for `LLM_PROVIDER_*` when a key is given; model endpoint for Ollama once `qwen3:1.7b` is pulled; the default chat model = `LLM_PROVIDER_MODEL` if set, else the Ollama model, only if no default exists. If the admin password was changed in the app, it logs and skips. No secrets are logged.

Key variables: `ODYSSEUS_ADMIN_USER=admin`, `ODYSSEUS_ADMIN_PASSWORD=${{secret(32, alnum)}}`, `AUTH_ENABLED=true`, `LOCALHOST_BYPASS=false`, `DATABASE_URL=sqlite:////app/data/app.db`, `CHROMADB_HOST/PORT`, `SEARXNG_INSTANCE`, `OLLAMA_BASE_URL`, `OLLAMA_MODEL`, `LLM_PROVIDER_API_KEY/BASE_URL/MODEL` (optional), `NTFY_INTERNAL_URL`, `NTFY_PUBLISH_TOKEN`, `NTFY_TOPIC`, `ALLOWED_ORIGINS`, `OAUTH_REDIRECT_BASE_URL` and `GOOGLE_OAUTH_REDIRECT_URI` (public URL; Railway's proxy is not a trusted forwarder for uvicorn, so request-derived URLs would be `http://`), `FASTEMBED_MODEL`, `FASTEMBED_CACHE_PATH=/app/data/fastembed`.

`SECURE_COOKIES` is left unset on purpose: upstream derives `Secure` from `X-Forwarded-Proto`, which Railway sends, while the loopback bootstrap login still works over plain HTTP.

### ChromaDB

Image `chromadb/chroma:1.5.9` (digest-pinned), private, `PORT=8000`, healthcheck `/api/v2/heartbeat` (300 s), volume **`/data`**. Chroma 1.x persists to `/data` (`persist_path` in the image's `/config.yaml`); upstream compose mounts `/chroma/chroma`, the 0.x path, so its vectors are not persisted. Listens on 0.0.0.0 (image default); Odysseus' Python client falls back to IPv4.

### SearXNG

Repo root `/services/searxng`: official image + `settings.yml` (`use_default_settings`, formats `html` + `json`, limiter off, image proxy off). Private, `PORT=8080`, healthcheck `/healthz` (300 s), no volume (settings baked in; `SEARXNG_SECRET=${{secret(48)}}` overrides the secret key). Granian binds `::` (image default, dual-stack). Odysseus queries the engines `google,brave,duckduckgo` (upstream default `SEARXNG_GENERAL_ENGINES`).

### ntfy

Repo root `/services/ntfy`: official image + `railway-start.sh`. Public domain on port 8080 (`PORT=8080`, `NTFY_LISTEN_HTTP=:8080`), healthcheck `/v1/health` (300 s), volume `/var/lib/ntfy` (user DB, message cache 72 h, attachments). `NTFY_AUTH_DEFAULT_ACCESS=deny-all`, `NTFY_ENABLE_LOGIN=true`, `NTFY_REQUIRE_LOGIN=true`, `NTFY_BEHIND_PROXY=true`, `NTFY_BASE_URL=https://${{RAILWAY_PUBLIC_DOMAIN}}`.

The start script hashes `NTFY_ADMIN_PASSWORD` with `ntfy user hash` and provisions `admin` (role admin, for the phone/web app) and `odysseus` (role user, ACL `*:wo` write-only, token `NTFY_ODYSSEUS_TOKEN` = `tk_` + `${{secret(29, a-z0-9)}}`). Odysseus reads the token by reference and stores it encrypted. `NTFY_UPSTREAM_BASE_URL` is empty (no third-party relay); set `https://ntfy.sh` for instant iOS delivery.

### Ollama

Repo root `/services/ollama`: official image + first-boot pull of `OLLAMA_PULL_MODELS` (`qwen3:1.7b`). Private, `PORT=11434`, `OLLAMA_HOST=[::]:11434`, healthcheck `/` (600 s), volume `/root/.ollama`. `OLLAMA_CONTEXT_LENGTH=16384` (Odysseus sends tool schemas, memory and search results), `OLLAMA_FLASH_ATTENTION=1` + `OLLAMA_KV_CACHE_TYPE=q8_0` (about 0.9 GB KV cache at 16k instead of 1.9 GB), `OLLAMA_NUM_PARALLEL=1`, `OLLAMA_MAX_LOADED_MODELS=1`, `OLLAMA_KEEP_ALIVE=30m`.

Why `qwen3:1.7b`: smallest Ollama model with tool calling that upstream's code handles explicitly. Odysseus detects Ollama on port 11434 and sends `think: false` for Qwen3 (`src/llm_core.py`), so no hidden reasoning tokens are generated on CPU. Expected speed on 8 shared vCPUs (estimate, not measured): first reply 20–40 s (prompt of a few thousand tokens), follow-ups 10–20 s. For production quality add an API provider; the local model stays available.

## Required input

None. Everything boots with generated secrets. Optional: `LLM_PROVIDER_API_KEY` (+ `LLM_PROVIDER_BASE_URL`, `LLM_PROVIDER_MODEL`) to register a cloud provider on first boot; more providers, search API keys (Brave, Tavily, Serper, Google PSE), email and calendar are configured in Settings.

## First login

1. Open the Odysseus URL, sign in as `admin` with `ODYSSEUS_ADMIN_PASSWORD` (Odysseus service, Variables). Settings → change the password.
2. Wait until the Odysseus logs show `[railway-bootstrap] model endpoint 'Ollama (Railway)' registered` (after the 1.4 GB pull), then chat. Or pick your provider's model.
3. Web search: toggle web search in the chat box; deep research uses the same SearXNG.
4. Alerts: ntfy app → add server `https://{ntfy-domain}` → user `admin` / `NTFY_ADMIN_PASSWORD` → subscribe to `odysseus`. In Odysseus, Settings → Integrations → ntfy (Railway) → Test sends a test push.

## Improvements over market templates

1. **Pinned official image** (1.0.3 by digest) instead of forks built from branches or a third-party `latest` image; ChromaDB, SearXNG, ntfy and Ollama pinned by tag and digest.
2. **Works without an API key**: CPU Ollama with a tool-capable model, registered as Odysseus' default model automatically. Optional provider key is registered too.
3. **Alerts that reach a phone, safely**: ntfy public but login-only (`deny-all` for anonymous), admin user plus a write-only publisher token for Odysseus, integration and reminder channel pre-configured. Market: either no auth on a public ntfy, or ntfy unreachable from phones.
4. **Correct persistence**: ChromaDB at `/data` (Chroma 1.x path), ntfy user DB + message cache on a volume, Odysseus logs, SSH identity, HuggingFace and FastEmbed caches and Cookbook installs on the app volume (upstream compose parity).
5. **Startup ordering**: Odysseus waits for ChromaDB so vector memory is not left degraded (Rule 8.5); generous healthcheck window.
6. **Healthchecks and `PORT` on every HTTP service** (Rule 8.1); Ollama, SearXNG and ntfy listen dual-stack.
7. **Safe auth defaults**: generated admin password, refuse to boot without one, signup stays off (upstream default), `LOCALHOST_BYPASS=false`, cookie security derived from the proxy scheme, OAuth redirect URLs pinned to the public HTTPS origin.
8. **SearXNG that works for Odysseus**: JSON output enabled, current pinned build (market `odysseus-1` used the build that crashes on boot).

## Resource estimate (not measured, see Open questions)

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month.

| Service | Idle RAM / CPU | Typical RAM / CPU | Volume |
|---|---|---|---|
| Odysseus | 0.6 GB / 0.02 | 1.2 GB / 0.2 (Chromium for the browser tool adds ~0.4 GB while used) | 1–2 GB |
| ChromaDB | 0.1 GB / ~0 | 0.25 GB / 0.02 | 0.1–1 GB |
| SearXNG | 0.15 GB / ~0 | 0.2 GB / 0.02 | – |
| ntfy | 0.03 GB / ~0 | 0.05 GB / ~0 | < 0.1 GB |
| Ollama (qwen3:1.7b, 16k ctx) | 0.05 GB (model unloaded after 30 min) | 2.6 GB while loaded / 0.5 avg, 4–8 vCPU bursts while answering | 1.5 GB |

- **Idle** (nobody chatting, model unloaded): ~0.95 GB × $10 + 0.03 vCPU × $20 + 3 GB × $0.15 ≈ **$11/month**.
- **Typical** (one person daily, model loaded about half the day): ~2.9 GB × $10 + 0.7 vCPU × $20 + 4 GB × $0.15 ≈ **$44/month**.
- **API provider only** (Ollama service removed): ≈ **$12–15/month** plus the provider's bill.

Minimum plan: **Hobby**. Ollama needs ~2.6 GB with the model loaded and Odysseus ~1 GB under load, so Trial's 1 GB per service is too small. All volumes fit Hobby's 5 GB per service; larger Ollama models need Pro.

## Verification checklist

Local verification was **not run** for this package: the shared Docker daemon froze after the Mac's disk filled up (2026-10-13), and the coordinator stopped all Docker work. No image was built and no container was started. Done offline: `sh -n`/`bash -n` on all scripts, `py_compile` on the Python files, `start.sh` exercised with `/app` remapped to a temp dir (symlinks, password guard, bounded ChromaDB wait, idempotent re-run), `bootstrap.py` exercised against a mock Odysseus/Ollama API (login cookie, settings, ntfy integration, both endpoints, default-model rules, markers, second run is a no-op). Upstream behaviour was verified by reading the 1.0.3 source and the pinned images' configs from the registries.

On first Railway deploy (all **unverified**):

- [ ] All five services build/pull and reach SUCCESS; Odysseus logs show `[railway] ChromaDB is up` and `[ok] Initial admin user created (admin)`.
- [ ] `https://{odysseus-domain}/api/health` 200; `/` redirects to `/login`; `/api/ready` 401 without a session.
- [ ] Login as `admin` with `ODYSSEUS_ADMIN_PASSWORD`; `GET /api/diagnostics/services` (admin session) reports chromadb, searxng and ntfy as ok.
- [ ] Ollama logs `model qwen3:1.7b ready`; Odysseus logs `model endpoint 'Ollama (Railway)' registered` and `default chat model set`. Time a first chat reply and a follow-up (target under 60 s / 30 s).
- [ ] Chat with web search on returns cited results (SearXNG JSON).
- [ ] Save a memory ("remember that my favourite colour is green"), start a new chat, ask about it (ChromaDB vector recall).
- [ ] Settings → Integrations → ntfy (Railway) → Test returns OK; the push arrives in the ntfy web app logged in as `admin`; `curl https://{ntfy-domain}/odysseus/json?poll=1` without credentials is rejected (401/403).
- [ ] Create a note with a reminder 2 minutes ahead; it arrives in ntfy.
- [ ] Redeploy all services: login, chats, memories, ntfy subscriptions and the pulled model persist; the bootstrap logs nothing new (markers present).

## Open questions

- **CPU model speed on Railway is unmeasured.** If the first reply takes well over a minute, either switch `OLLAMA_DEFAULT_MODEL` to a smaller model (`qwen3:0.6b`) or drop the Ollama service and make `LLM_PROVIDER_API_KEY` the recommended input. Ollama sizes its thread pool from the host's cores, which may exceed the service's vCPU quota on Railway.
- **ntfy provisioning** (`ntfy user hash` from piped stdin, `NTFY_AUTH_*` with the generated values, `*` topic ACL) was verified against the v2.30.0 source but not executed.
- **Upstream entrypoint on a Railway volume**: it skips the recursive ownership repair when the volume is a whole filesystem; the start script chowns what it creates. Needs a first-boot check that uid 1000 can write `/app/data/logs` and `/app/data/fastembed`.
- Odysseus image size and cold-start time (Chromium, Node, Docker CLI, build tools are in the image) are not measured; the 900 s healthcheck window is an estimate.
- Google and DuckDuckGo may rate-limit SearXNG from Railway IPs; Brave usually works. Users can add a Brave/Tavily/Serper key in Settings → Search.
- Local leftovers from the aborted test: Docker network `r3-odysseus-net` and volume `r3-odysseus-ollama` were created before Docker froze and could not be removed.
