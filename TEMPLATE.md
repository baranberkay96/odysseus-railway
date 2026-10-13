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
| Local model | `qwen3:1.7b` (Ollama library, Q4_K_M, 1.36 GB, template digest `ae370d88…`), served as the tuned copy `qwen3-cpu:1.7b` | | | 2026-10-13 |

Odysseus has no git tags or GitHub releases; the GHCR image tags follow `APP_VERSION` in `src/constants.py`. Upstream documents `:latest` and `:X.Y.Z` as mutable and recommends `:X.Y.Z-<sha>` pins, but no such tag exists for the 1.0.3 main build, so the manifest-list digest is pinned. Upstream's own compose pins SearXNG to `2026.9.25-12f8b6515` because a broken `latest` once blocked startup; this template pins a newer build by digest for the same reason.

Upgrade Odysseus: `docker buildx imagetools inspect ghcr.io/odysseus-dev/odysseus:<new-version>`, put tag and digest into `services/odysseus/Dockerfile`, back up the Odysseus volume, redeploy. `setup.py` runs on every start and is idempotent.

## Architecture

```
Browser ── HTTPS ──► Odysseus :7000 (public, login) ── volume /app/data
                        │  sqlite app.db, auth.json, .app_key, uploads, settings,
                        │  logs, ssh, huggingface, fastembed, .local (symlinked)
                        ├── http://chromadb.railway.internal:8000  ChromaDB (volume /data)
                        ├── http://searxng.railway.internal:8080   SearXNG (format=json)
                        ├── http://ollama.railway.internal:11434/v1 Ollama qwen3-cpu:1.7b (volume /root/.ollama)
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

`railway/bootstrap.py` waits for `/api/health`, logs in with the generated admin password and applies each step once (markers in `/app/data/.railway-bootstrap/`): `app_public_url` = Railway URL; ntfy integration (private URL, bearer token) + reminder channel `ntfy`, topic `odysseus`; model endpoint for `LLM_PROVIDER_*` when a key is given; model endpoint for Ollama once `OLLAMA_MODEL` (`qwen3-cpu:1.7b`) is listed by Ollama; the default chat model = `LLM_PROVIDER_MODEL` if set, else the Ollama model. It only replaces a default the bootstrap set itself (recorded in `default-model`, or an Ollama model with an earlier registration marker, which moves deploy-1 installs from `qwen3:1.7b` to `qwen3-cpu:1.7b`); a default picked in Settings is never touched. If the admin password was changed in the app, it logs and skips. No secrets are logged.

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

Repo root `/services/ollama`: official image + `railway-entrypoint.sh` + `qwen3-nothink.tmpl`. Private, `PORT=11434`, `OLLAMA_HOST=[::]:11434`, healthcheck `/` (600 s), volume `/root/.ollama`. `OLLAMA_CONTEXT_LENGTH=16384` (Odysseus sends tool instructions, memory and search results), `OLLAMA_FLASH_ATTENTION=1` + `OLLAMA_KV_CACHE_TYPE=q8_0` (about 0.9 GB KV cache at 16k instead of 1.9 GB), `OLLAMA_NUM_PARALLEL=1`, `OLLAMA_MAX_LOADED_MODELS=1`, `OLLAMA_KEEP_ALIVE=30m`, `OLLAMA_GO_TEMPLATE=1`.

Start sequence (every boot):

1. **Thread count.** `OLLAMA_NUM_THREAD` if set (used as is). Otherwise floor(quota / period) of the tightest CPU quota visible in the container (cgroup v2 `cpu.max` of its own cgroup and visible ancestors, then cgroup v1 `cpu.cfs_quota_us` / `cpu.cfs_period_us`), at least 1, or `nproc` when no quota is visible; either way capped at 8. The cap matters because Railway's current plan limits allow up to 48 vCPU per Hobby service (docs.railway.com, pricing/plans), so the quota alone may be 48, the same count that failed; on shared hosts llama.cpp's spin-waiting threads stall when they outnumber the CPU time actually granted, and a 1–4B model gains little beyond 8 threads. The value is exported as `LLAMA_ARG_THREADS`. Ollama 0.40.3 has no thread variable of its own: it runs each model in a llama.cpp `llama-server` subprocess that inherits Ollama's environment (`llm/llama_server.go`, `SetupLlamaServerCommandEnv`), passes `-t` only when a model sets `num_thread`, and llama.cpp b11351 reads `LLAMA_ARG_THREADS` as `-t` (prompt-processing threads default to the same). So the cap applies to every model, including models pulled later.
2. `ollama serve`, then pull `OLLAMA_PULL_MODELS` (`qwen3:1.7b`) if missing.
3. **Tuned model.** `ollama create` `OLLAMA_DEFAULT_MODEL` (`qwen3-cpu:1.7b`) from `OLLAMA_BASE_MODEL` with `num_thread` (same value, as a second safeguard; llama.cpp logs that the flag overrides the env var), `num_ctx` = `OLLAMA_CONTEXT_LENGTH`, and, for qwen3 with `OLLAMA_THINKING=false`, `temperature 0.7`, `top_p 0.8` (Qwen's non-thinking settings; Odysseus sends its own temperature) and the template `qwen3-nothink.tmpl`. Inherited parameters (stop tokens) are kept (`create/manifest.go` merges them). The model is recreated on every start (manifest only, no new weights), so changed settings apply after a redeploy. If creation with the template fails, it retries without it.

Deploy test 1 showed why step 1 is needed: llama.cpp started `n_threads = 48 / 48` on a 96-core EPYC 9655P, generated about 7 tokens in 5 minutes, and Odysseus returned 502 after its 300 s stream timeout. Whether the service's quota was below 48 or the threads lost to host contention is not known; the cap covers both.

**Thinking off.** Qwen3 reasons before it answers by default, which on CPU costs hundreds of hidden tokens per reply. Odysseus 1.0.3 does send `think: false` to Ollama's `/v1` endpoint, but Ollama 0.40.3's OpenAI-compatible request has no `think` field (only `reasoning_effort`, which Odysseus does not send to Ollama), so the flag is dropped and Ollama turns thinking on for the stock qwen3 template (`server/model_thinking.go`, `legacyThinking`, default true). Odysseus' native Ollama path (`/api/chat`) sends no `think` either. The fix is therefore model-side: `qwen3-nothink.tmpl` is the stock qwen3 template (Ollama library, digest `ae370d88…`) with the switch fixed to off: `/no_think` on the last user turn and an empty `<think></think>` block before the answer. It renders byte-for-byte like the stock template with `think=false` (checked with Go `text/template` on six conversations, including a tool call round trip). It has no `.Thinking` field, so Ollama reports no thinking capability and does not switch thinking back on. `OLLAMA_GO_TEMPLATE=1` is required: otherwise Ollama 0.40.3 prefers the GGUF's embedded chat template when it has more capabilities than the Modelfile template (`shouldPreferChatTemplate`), which would restore thinking. The entrypoint defaults it to 1 if the variable is removed.

To re-enable thinking: set `OLLAMA_THINKING=true` on the Ollama service and redeploy it; `qwen3-cpu:1.7b` is recreated with the stock template. The plain `qwen3:1.7b` also stays in Odysseus' model menu (Odysseus lists every Ollama model); it is thread-capped as well but still thinks.

Why `qwen3:1.7b`: smallest Ollama model with tool calling that upstream's code recognises (`qwen3` in Odysseus' tool, thinking and context tables). Expected speed on 8 shared vCPUs (estimate, not measured): first reply 10–40 s, agent turns with tools or web search longer. For production quality add an API provider; the local model stays available.

## Required input

None. Everything boots with generated secrets. Optional: `LLM_PROVIDER_API_KEY` (+ `LLM_PROVIDER_BASE_URL`, `LLM_PROVIDER_MODEL`) to register a cloud provider on first boot; more providers, search API keys (Brave, Tavily, Serper, Google PSE), email and calendar are configured in Settings.

## First login

1. Open the Odysseus URL, sign in as `admin` with `ODYSSEUS_ADMIN_PASSWORD` (Odysseus service, Variables). Settings → change the password.
2. Wait until the Odysseus logs show `[railway-bootstrap] model endpoint 'Ollama (Railway)' registered` and `default chat model set to 'qwen3-cpu:1.7b'` (after the 1.4 GB pull), then chat. Or pick your provider's model.
3. Web search: toggle web search in the chat box; deep research uses the same SearXNG.
4. Alerts: ntfy app → add server `https://{ntfy-domain}` → user `admin` / `NTFY_ADMIN_PASSWORD` → subscribe to `odysseus`. In Odysseus, Settings → Integrations → ntfy (Railway) → Test sends a test push.

## Improvements over market templates

1. **Pinned official image** (1.0.3 by digest) instead of forks built from branches or a third-party `latest` image; ChromaDB, SearXNG, ntfy and Ollama pinned by tag and digest.
2. **Works without an API key**: CPU Ollama with a tool-capable model tuned for Railway CPUs (thread pool sized to the vCPU quota, hidden reasoning off), registered as Odysseus' default model automatically. Optional provider key is registered too.
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
| Ollama (qwen3-cpu:1.7b, 16k ctx) | 0.05 GB (model unloaded after 30 min) | 2.6 GB while loaded / 0.5 avg, 4–8 vCPU bursts while answering | 1.5 GB |

- **Idle** (nobody chatting, model unloaded): ~0.95 GB × $10 + 0.03 vCPU × $20 + 3 GB × $0.15 ≈ **$11/month**.
- **Typical** (one person daily, model loaded about half the day): ~2.9 GB × $10 + 0.7 vCPU × $20 + 4 GB × $0.15 ≈ **$44/month**.
- **API provider only** (Ollama service removed): ≈ **$12–15/month** plus the provider's bill.

Minimum plan: **Hobby**. Ollama needs ~2.6 GB with the model loaded and Odysseus ~1 GB under load, so Trial's 1 GB per service is too small. All volumes fit Hobby's 5 GB per service; larger Ollama models need Pro.

## Verification checklist

**Deploy test 1 (Railway, 2026-10-13, run by the coordinator):** all five services reached SUCCESS; the bootstrap registered the ntfy integration and the Ollama endpoint; auth was enforced. Chat with the local model failed: `POST /api/chat` returned 502 after 300 s (twice), Ollama logged `/v1/chat/completions` 500 after 5m0s with about 7 tokens generated for a 331-token prompt, and `n_threads = 48 / 48`. Fixed by the thread sizing and the thinking-off model above (not yet redeployed).

Local Docker verification was **not run**: the shared Docker daemon froze after the Mac's disk filled up (2026-10-13), and the coordinator stopped all Docker work. Done offline:

- `sh -n` / `bash -n` on all scripts, `py_compile` on the Python files.
- `start.sh` with `/app` remapped to a temp dir: symlinks, password guard, bounded ChromaDB wait, idempotent re-run.
- Ollama entrypoint with fake cgroup trees and a mock `ollama` binary: v2 quota 8 → 8 threads; v2 parent quota 4.5 under a container `max` → 4; v1 quota 2 → 2; 0.5 → 1; no quota visible → 8 (cap); `OLLAMA_NUM_THREAD=3` → 3; invalid override ignored; `LLAMA_ARG_THREADS` and `OLLAMA_GO_TEMPLATE=1` reach `ollama serve`. Generated Modelfiles: thinking off (params + template, template byte-identical to the file), `OLLAMA_THINKING=true` (params only), non-qwen3 base (params only, logged), create failure (retry without template).
- `qwen3-nothink.tmpl` rendered with Go `text/template` (Go Playground) against Ollama's stock qwen3 template with `think=false`: identical output for six conversations, independent of the `Think` / `IsThinkSet` values.
- `bootstrap.py` against a mock Odysseus/Ollama API: login cookie, settings, ntfy integration, both endpoints, markers, second run makes no calls; default model for a fresh install, provider model set, provider key without model, upgrade from deploy 1 (`qwen3:1.7b` → `qwen3-cpu:1.7b`), and a user-chosen default (left unchanged).
- Upstream behaviour was verified by reading Odysseus 1.0.3 (`main` 934d23c), Ollama v0.40.3 and llama.cpp b11351 source, and the pinned images' configs from the registries.

On the next Railway deploy (all **unverified**):

- [x] All five services build/pull and reach SUCCESS (deploy test 1).
- [x] Bootstrap registers the ntfy integration and the Ollama endpoint; login is required (deploy test 1).
- [ ] Odysseus logs show `[railway] ChromaDB is up` and `[ok] Initial admin user created (admin)`.
- [ ] `https://{odysseus-domain}/api/health` 200; `/` redirects to `/login`; `/api/ready` 401 without a session.
- [ ] `GET /api/diagnostics/services` (admin session) reports chromadb, searxng and ntfy as ok.
- [ ] Ollama logs `inference threads: N (source: cgroup-cpu-quota=Q[,capped])`; record Q (the real quota Railway sets) and `model qwen3-cpu:1.7b ready (qwen3:1.7b, N threads, ctx 16384, thinking off)`; on the first chat llama.cpp reports `n_threads = N`, not 48. If the source is `no-quota-visible`, note that instead.
- [ ] Odysseus logs `default chat model set to 'qwen3-cpu:1.7b'` (on the deploy-1 project too, which moves from `qwen3:1.7b`).
- [ ] Time a first chat reply and a follow-up with `qwen3-cpu:1.7b` (target under 60 s / 30 s) and check that the reply has no reasoning block. Put the measured numbers into README and this file.
- [ ] Chat with web search on returns cited results (SearXNG JSON).
- [ ] Save a memory ("remember that my favourite colour is green"), start a new chat, ask about it (ChromaDB vector recall).
- [ ] Settings → Integrations → ntfy (Railway) → Test returns OK; the push arrives in the ntfy web app logged in as `admin`; `curl https://{ntfy-domain}/odysseus/json?poll=1` without credentials is rejected (401/403).
- [ ] Create a note with a reminder 2 minutes ahead; it arrives in ntfy.
- [ ] Redeploy all services: login, chats, memories, ntfy subscriptions and the pulled model persist; the bootstrap logs nothing new (markers present); Ollama recreates `qwen3-cpu:1.7b` without downloading.

## Open questions

- **CPU model speed on Railway is still unmeasured** after the thread fix. If replies take over a minute: try `OLLAMA_NUM_THREAD` one below the vCPU limit (llama.cpp threads spin while waiting and can be throttled when they use exactly the quota), a smaller `OLLAMA_BASE_MODEL` (`qwen3:0.6b`, renaming `OLLAMA_DEFAULT_MODEL`), or drop the Ollama service and make `LLM_PROVIDER_API_KEY` the recommended input.
- **Thread cap of 8** is a judgement call, not measured: fewer threads (4–6) may be faster on a busy host, more may help on Pro with a dedicated quota. The `inference threads` log line shows the quota Railway actually sets; tune with `OLLAMA_NUM_THREAD`.
- **Context budget**: Odysseus assumes 131,072 tokens for any model name containing `qwen3` (`KNOWN_CONTEXT_WINDOWS`), because Ollama's `/v1/models` reports no context length, while the model serves 16,384. Very long sessions can exceed that; Ollama then drops the oldest messages. Not tested.
- **ntfy provisioning** (`ntfy user hash` from piped stdin, `NTFY_AUTH_*` with the generated values, `*` topic ACL) was verified against the v2.30.0 source but not executed.
- **Upstream entrypoint on a Railway volume**: it skips the recursive ownership repair when the volume is a whole filesystem; the start script chowns what it creates. Needs a first-boot check that uid 1000 can write `/app/data/logs` and `/app/data/fastembed`.
- Odysseus image size and cold-start time (Chromium, Node, Docker CLI, build tools are in the image) are not measured; the 900 s healthcheck window is an estimate.
- Google and DuckDuckGo may rate-limit SearXNG from Railway IPs; Brave usually works. Users can add a Brave/Tavily/Serper key in Settings → Search.
- Local leftovers from the aborted test: Docker network `r3-odysseus-net` and volume `r3-odysseus-ollama` were created before Docker froze and could not be removed.
