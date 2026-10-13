# Deploy and Host Odysseus with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/odysseus-v1-private-ai-workspace?referralCode=20H68q)

Odysseus is an open-source, self-hosted AI workspace: chat with local or cloud models, agents with tools, deep research, persistent memory, documents, notes, tasks, calendar and email in one web app. This template deploys Odysseus with private web search, a vector store, push alerts and a local model, ready to chat without an API key.

## About Hosting Odysseus

Odysseus is a FastAPI application that keeps its data in SQLite and files on disk, stores memory and document vectors in ChromaDB, searches the web through SearXNG and sends reminders through ntfy. Running it well means pinning the app image, giving each stateful service a volume, starting the app only after its vector store is reachable, keeping login enabled because the agent can run shell and file tools, and connecting at least one language model. This community template runs the official Odysseus 1.0.3 image with all four upstream services, adds a CPU Ollama service with a small model, creates the admin account from a generated password, and registers the model, the ntfy integration and your optional API provider on first boot.

## Common Use Cases

- A private ChatGPT-style workspace for a person or small team, with chats and memory kept in your own Railway project
- Research assistant that searches the web through your own SearXNG instance and writes cited reports
- Personal knowledge base: upload documents, then ask questions answered from ChromaDB-backed retrieval
- Notes, tasks and reminders that reach your phone through the bundled, login-protected ntfy server
- One interface for several providers: the bundled local model plus OpenAI, OpenRouter or any OpenAI-compatible API

## Dependencies for Odysseus Hosting

- Odysseus web app (included, public URL with login)
- ChromaDB vector store, SearXNG metasearch, ntfy push server and Ollama (included, private except ntfy)
- Optional: an API key for an OpenAI-compatible provider for faster and stronger models
- Optional: the ntfy app on Android or iOS to receive alerts on your phone

### Deployment Dependencies

- Odysseus repository and setup guide: https://github.com/odysseus-dev/odysseus and https://github.com/odysseus-dev/odysseus/blob/main/website/setup.md
- Odysseus container image: https://github.com/odysseus-dev/odysseus/pkgs/container/odysseus
- ChromaDB: https://docs.trychroma.com
- SearXNG: https://docs.searxng.org
- ntfy: https://docs.ntfy.sh
- Ollama: https://github.com/ollama/ollama

### Implementation Details

| Service | Source | Purpose |
|---|---|---|
| Odysseus | `ghcr.io/odysseus-dev/odysseus:1.0.3` (digest-pinned) plus a start wrapper | Web UI and API on port 7000, healthcheck `/api/health`, volume `/app/data` |
| ChromaDB | `chromadb/chroma:1.5.9` | Vector memory, document retrieval and semantic skills; private, volume `/data` |
| SearXNG | `searxng/searxng:2026.10.13-22c64b8d3` with JSON output enabled | Web search for chat and deep research; private |
| ntfy | `binwiederhier/ntfy:v2.30.0` with provisioned users | Reminder and alert delivery; public URL, anonymous access denied, volume `/var/lib/ntfy` |
| Ollama | `ollama/ollama:0.40.3`; pulls `qwen3:1.7b` and creates the tuned `qwen3-cpu:1.7b` | Local chat model on CPU, threads sized to the service's vCPU limit, thinking off; private, volume `/root/.ollama` |

**First login**

1. Optional: paste `LLM_PROVIDER_API_KEY` (and `LLM_PROVIDER_BASE_URL` / `LLM_PROVIDER_MODEL` for providers other than OpenAI) when deploying.
2. Open the Odysseus URL and sign in as `admin` with `ODYSSEUS_ADMIN_PASSWORD` from the Odysseus service's Variables tab. Change the password under Settings.
3. The first boot downloads the local model (about 1.4 GB). The Ollama endpoint and `qwen3-cpu:1.7b` appear in the model menu a few minutes after deploy. Pick `qwen3-cpu:1.7b` rather than the plain `qwen3:1.7b`, which keeps qwen3's slow reasoning phase.
4. Alerts: install the ntfy app, add the server `https://{ntfy-domain}`, sign in with `NTFY_ADMIN_USER` / `NTFY_ADMIN_PASSWORD` from the ntfy service, and subscribe to the topic `odysseus`. Reminders from notes and tasks are delivered there and in the browser. On iPhone, set `NTFY_UPSTREAM_BASE_URL` to `https://ntfy.sh` for instant delivery.

**Local model speed**: the bundled model runs on CPU without a GPU. Expect a short answer in roughly 10 to 40 seconds on 8 vCPUs; agent turns with tools or web search take longer. For fast, stronger answers, set `LLM_PROVIDER_API_KEY` (plus `LLM_PROVIDER_BASE_URL` and `LLM_PROVIDER_MODEL` for providers other than OpenAI) and redeploy Odysseus, or add a provider under Settings. The local model then stays available for private chats.

- Threads: at every start the Ollama service sizes its thread pool to its CPU quota, at most 8 threads, because more threads than the CPU time actually granted stall generation. Override with `OLLAMA_NUM_THREAD`.
- Thinking: qwen3 normally reasons silently before it answers, which on CPU can add a minute or more per answer. `qwen3-cpu:1.7b` answers directly. To turn reasoning back on, set `OLLAMA_THINKING=true` on the Ollama service and redeploy it.

**Scaling**: Odysseus keeps SQLite and files on its volume, so it runs as one replica; raise its RAM or CPU instead. Ollama speed depends on vCPUs; give it more CPU, or set `OLLAMA_BASE_MODEL` to a larger model (for example `qwen3:4b`, renaming `OLLAMA_DEFAULT_MODEL` to match) if you raise its memory. ChromaDB, SearXNG and ntfy are light.

**Pinning and upgrades**: the Odysseus image tag and digest are in `services/odysseus/Dockerfile`; the other images are pinned in their Dockerfiles or in the service source. Back up the Odysseus volume, change the tag and digest to a newer release, and redeploy. Upstream's `:latest` and bare version tags move on every push, so keep the digest.

### Why Deploy Odysseus on Railway?

Railway runs the app, its vector store, search engine, notification server and model side by side with private networking, volumes and HTTPS, so you get a complete private AI workspace in one deploy. You pay only for the resources it uses, and you can add API providers or remove the local model at any time.
