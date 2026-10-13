# NOTICE: Odysseus v1 Private AI Workspace template

## Software used

| Component | Source | License | How it is used |
|---|---|---|---|
| Odysseus | `ghcr.io/odysseus-dev/odysseus:1.0.3@sha256:4aa6e607…36fb04` (official image, built from `main` commit `934d23c`), https://github.com/odysseus-dev/odysseus | AGPL-3.0 (repository LICENSE; third-party notices ship inside the image under `/app/licenses`) | Run unmodified. `services/odysseus/railway/*` wraps upstream's `docker/entrypoint.sh` and calls the app's public HTTP API; no Odysseus file is changed or copied. |
| ChromaDB | `chromadb/chroma:1.5.9` | Apache-2.0 | Run unmodified |
| SearXNG | `searxng/searxng:2026.10.13-22c64b8d3` | AGPL-3.0 | Run unmodified with a settings file written for this template |
| ntfy | `binwiederhier/ntfy:v2.30.0` | Apache-2.0 or GPL-2.0 (dual) | Run unmodified behind a start script written for this template |
| Ollama | `ollama/ollama:0.40.3` | MIT | Run unmodified behind a start script written for this template |
| Qwen3 1.7B model | Ollama library `qwen3:1.7b`, pulled at runtime | Apache-2.0 | Downloaded by the Ollama service on first boot, not redistributed here |
| all-MiniLM-L6-v2 (FastEmbed) | Hugging Face, downloaded by Odysseus at runtime | Apache-2.0 | Upstream default embedding model |

**AGPL-3.0 note.** Odysseus and SearXNG are licensed under the GNU Affero General Public License v3. This template runs their official images without modification, and their complete source is available at the upstream repositories linked above. If you modify Odysseus or SearXNG and let other people use the modified version over a network, the AGPL requires you to offer them the corresponding source code.

Product names belong to their owners. This is a community template, not affiliated with the Odysseus project, Chroma, SearXNG, ntfy or Ollama.

## Files in this package

All files were written for this template:

- `services/odysseus/Dockerfile`, `railway/start.sh`, `railway/wait_http.py`, `railway/bootstrap.py`: volume layout, ChromaDB wait, admin-password guard, and a one-time bootstrap through Odysseus' own API (`/api/auth/login`, `/api/auth/settings`, `/api/auth/integrations`, `/api/model-endpoints`).
- `services/searxng/Dockerfile`, `settings.yml`: SearXNG defaults plus JSON output. Upstream Odysseus ships an equivalent minimal settings file (`config/searxng/settings.yml`); this one was written independently and adds Railway-specific options (limiter and image proxy off, private-only instance).
- `services/ntfy/Dockerfile`, `railway-start.sh`: hashes the generated passwords with `ntfy user hash` and provisions users, an ACL and the publish token through ntfy's documented `NTFY_AUTH_USERS` / `NTFY_AUTH_ACCESS` / `NTFY_AUTH_TOKENS` options.
- `services/ollama/Dockerfile`, `railway-entrypoint.sh`: first-boot model pull (same approach as this template collection's Open WebUI + Ollama package).

## Upstream files and docs checked (2026-10-13)

- `odysseus-dev/odysseus` default branch `dev` (local copy) and `main` (release branch, `APP_VERSION = "1.0.3"` in `src/constants.py`, commit `934d23c`, 2026-09-05): `docker-compose.yml`, `Dockerfile`, `docker/entrypoint.sh`, `setup.py`, `app.py` (auth exemptions, `/api/health`, `/api/ready`), `.env.example`, `src/constants.py`, `src/chroma_client.py`, `src/memory_vector.py`, `src/app_initializer.py`, `src/model_discovery.py`, `src/llm_core.py` (Ollama `think: false` handling), `src/integrations.py`, `src/settings.py`, `src/url_safety.py`, `src/readiness.py`, `core/auth.py`, `core/middleware.py`, `routes/auth_routes.py`, `routes/model_routes.py`, `routes/note/note_routes.py`, `services/search/providers.py`, `config/searxng/settings.yml`, `.github/workflows/docker-publish.yml` (tag scheme), `SECURITY.md`, `website/setup.md`, `website/configuration-reference.md`.
- GHCR tag list for `ghcr.io/odysseus-dev/odysseus`: `latest` = `1.0.3` = digest `sha256:4aa6e607…`, created 2026-09-05. The documented immutable `X.Y.Z-<sha>` main tags are not published for 1.0.3, hence the digest pin.
- ChromaDB release 1.5.9 (GitHub release, 2026-05-05; `latest` points to it); PyPI `chromadb-client` 1.5.9 is the newest client, matching the server.
- ntfy v2.30.0 source: `cmd/serve.go` (provisioning parsers, `upstream-base-url` default empty), `cmd/user.go` (`user hash`), `user/` (token format `tk_` + 29 characters); `docs/config.md`.
- SearXNG image config (`GRANIAN_HOST=::`, port 8080).

## Market templates and repositories reviewed

| Template / repo | License | Use |
|---|---|---|
| `odysseus-1` (image `xiaosong233/odysseus-railway:latest`) | n/a (third-party image) | Variable set reviewed. Nothing copied. |
| `odysseus-pewdiepie` (`Shinyduo/odysseus` fork plus `Shinyduo/odysseus-searxng`, `Shinyduo/odysseus-ntfy`) | Fork carries upstream's earlier MIT LICENSE; the Railway-specific files have no separate license | Read only. No files or text copied. |
| `odysseus` (`XavTo/odysseus` fork, `railway/searxng`) | Fork carries upstream's AGPL-3.0 LICENSE | Read only. No files or text copied. |

No README text from other templates was reused.
