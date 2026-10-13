#!/bin/bash
# Runs "ollama serve" and pulls every model in OLLAMA_PULL_MODELS that is not
# on the volume yet (first boot only). The API keeps serving if a pull fails;
# Odysseus registers the model once it is listed.
set -uo pipefail

/bin/ollama serve &
server_pid=$!
trap 'kill -TERM "$server_pid" 2>/dev/null; wait "$server_pid"; exit $?' TERM INT

client() { OLLAMA_HOST=127.0.0.1:11434 /bin/ollama "$@"; }

for _ in $(seq 1 120); do
    client list >/dev/null 2>&1 && break
    sleep 1
done

for model in ${OLLAMA_PULL_MODELS//,/ }; do
    if client show "$model" >/dev/null 2>&1; then
        echo "[railway] model $model already present"
    else
        echo "[railway] pulling $model (first boot only)"
        client pull "$model" >/dev/null || echo "[railway] WARNING: pull of $model failed; run 'ollama pull $model' or redeploy"
        echo "[railway] model $model ready"
    fi
done

wait "$server_pid"
