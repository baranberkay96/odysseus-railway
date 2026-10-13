#!/bin/sh
# Railway start wrapper for the official Odysseus image.
#
# 1. Keeps every path upstream's docker-compose persists on the single
#    Railway volume (/app/data): logs, SSH identity, HuggingFace cache and
#    user-installed Python packages are symlinked into it.
# 2. Refuses to start without a usable admin password, so a public URL never
#    exposes the first-run setup page.
# 3. Waits (bounded) for ChromaDB: Odysseus connects to its vector store once
#    at startup and stays degraded until the next restart if it is missing.
# 4. Starts the one-time bootstrap (ntfy integration, model endpoints) in the
#    background, then hands over to upstream's entrypoint unchanged
#    (setup.py, ownership repair, privilege drop, uvicorn).
set -eu

DATA_DIR=/app/data
APP_UID="${PUID:-1000}"
APP_GID="${PGID:-1000}"
log() { echo "[railway] $*"; }

mkdir -p "$DATA_DIR"

# --- 1. persist upstream's extra mount points inside the volume ------------
# Upstream's entrypoint skips the recursive ownership repair when the volume
# is a whole filesystem, so everything created here as root is handed to the
# app user (uvicorn runs as PUID:PGID after gosu).
link_into_volume() {
    src="$1"
    dst="$2"
    if [ ! -d "$dst" ]; then
        mkdir -p "$dst"
        chown "$APP_UID:$APP_GID" "$dst" 2>/dev/null || true
    fi
    if [ -L "$src" ]; then
        return 0
    fi
    if [ -d "$src" ]; then
        # Keep anything the image ships there; never overwrite volume files.
        cp -an "$src/." "$dst/" 2>/dev/null || true
        chown -R "$APP_UID:$APP_GID" "$dst" 2>/dev/null || true
        rm -rf "$src"
    fi
    mkdir -p "$(dirname "$src")"
    ln -s "$dst" "$src"
}

link_into_volume /app/logs "$DATA_DIR/logs"
link_into_volume /app/.ssh "$DATA_DIR/ssh"
link_into_volume /app/.cache/huggingface "$DATA_DIR/huggingface"
link_into_volume /app/.local "$DATA_DIR/local"
chmod 700 "$DATA_DIR/ssh" 2>/dev/null || true
if [ -n "${FASTEMBED_CACHE_PATH:-}" ] && [ ! -d "$FASTEMBED_CACHE_PATH" ]; then
    mkdir -p "$FASTEMBED_CACHE_PATH"
    chown "$APP_UID:$APP_GID" "$FASTEMBED_CACHE_PATH" 2>/dev/null || true
fi

# --- 2. never boot a public instance without an admin -----------------------
auth_enabled="$(printf '%s' "${AUTH_ENABLED:-true}" | tr '[:upper:]' '[:lower:]')"
if [ "$auth_enabled" != "false" ] && [ ! -s "$DATA_DIR/auth.json" ]; then
    pw="${ODYSSEUS_ADMIN_PASSWORD:-}"
    if [ "${#pw}" -lt 8 ]; then
        log "ERROR: ODYSSEUS_ADMIN_PASSWORD must be set (8+ characters) before the first boot."
        log "Without it the first visitor of the public URL could create the admin account."
        exit 1
    fi
fi

# --- 3. wait for ChromaDB (vector memory, RAG, semantic skills) -------------
wait_secs="${WAIT_FOR_SERVICES_SECONDS:-300}"
if [ -n "${CHROMADB_HOST:-}" ] && [ "$wait_secs" -gt 0 ] 2>/dev/null; then
    log "waiting up to ${wait_secs}s for ChromaDB at ${CHROMADB_HOST}:${CHROMADB_PORT:-8000}"
    if python /opt/railway/wait_http.py \
        "http://${CHROMADB_HOST}:${CHROMADB_PORT:-8000}/api/v2/heartbeat" "$wait_secs"; then
        log "ChromaDB is up"
    else
        log "WARNING: ChromaDB not reachable; vector memory stays degraded until the next restart"
    fi
fi

# --- 4. one-time bootstrap through the app's own API, then upstream entrypoint
python /opt/railway/bootstrap.py &

exec /usr/local/bin/entrypoint.sh "$@"
