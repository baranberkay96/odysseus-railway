#!/bin/bash
# Ollama on Railway CPU for Odysseus.
#
# 1. Sizes the inference thread pool: the service's CPU quota, at most 8
#    (OLLAMA_NUM_THREAD overrides). Ollama's llama.cpp runner otherwise starts
#    one thread per visible core (48 on Railway), far more than the CPU time
#    it gets, and generation stalls almost completely. The count is exported as
#    LLAMA_ARG_THREADS, which Ollama passes to every llama-server it starts,
#    so it applies to every model, including ones pulled later.
# 2. Runs "ollama serve" and pulls OLLAMA_PULL_MODELS on first boot.
# 3. (Re)creates OLLAMA_DEFAULT_MODEL from OLLAMA_BASE_MODEL on every start
#    with num_thread, num_ctx and, for qwen3 with OLLAMA_THINKING=false, a chat
#    template that answers without the hidden reasoning phase. Odysseus uses
#    this model. The API keeps serving if a step fails.
set -uo pipefail

CGROUP_ROOT=/sys/fs/cgroup
PROC_CGROUP=/proc/self/cgroup
NOTHINK_TEMPLATE=/opt/railway/qwen3-nothink.tmpl
# Upper bound for the automatic thread count. Railway shows up to 48 CPUs
# per container; on shared hosts llama.cpp's spin-waiting threads degrade
# sharply when they outnumber the CPU time actually granted, and a 1-4B model
# gains little beyond 8 threads. OLLAMA_NUM_THREAD can set any value.
AUTO_THREAD_CAP=8

log() { echo "[railway] $*"; }

# floor(quota/period) of the tightest CPU quota visible to this container
# (cgroup v2 cpu.max of the own cgroup and its visible ancestors, then
# cgroup v1 cfs quota). Prints nothing when every level is unlimited.
cgroup_cpu_limit() {
    local best="" quota period dir rel d

    consider() {
        [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] || return 0
        (( $2 > 0 )) || return 0
        local n=$(( $1 / $2 ))
        (( n < 1 )) && n=1
        if [[ -z "$best" ]] || (( n < best )); then best=$n; fi
    }

    if [[ -r "$CGROUP_ROOT/cgroup.controllers" ]]; then
        rel="$(awk -F: '$1 == "0" { print $3; exit }' "$PROC_CGROUP" 2>/dev/null)"
        dir="$CGROUP_ROOT${rel%/}"
        while [[ "$dir" == "$CGROUP_ROOT"* ]]; do
            if [[ -r "$dir/cpu.max" ]]; then
                read -r quota period < "$dir/cpu.max" && consider "$quota" "$period"
            fi
            [[ "$dir" == "$CGROUP_ROOT" ]] && break
            dir="$(dirname "$dir")"
        done
    fi
    for d in "$CGROUP_ROOT/cpu" "$CGROUP_ROOT/cpu,cpuacct" "$CGROUP_ROOT/cpuacct,cpu"; do
        if [[ -r "$d/cpu.cfs_quota_us" && -r "$d/cpu.cfs_period_us" ]]; then
            consider "$(cat "$d/cpu.cfs_quota_us")" "$(cat "$d/cpu.cfs_period_us")"
        fi
    done
    [[ -n "$best" ]] && echo "$best"
    return 0
}

# Prints "<threads> <source>".
resolve_threads() {
    local n source
    if [[ "${OLLAMA_NUM_THREAD:-}" =~ ^[1-9][0-9]*$ ]]; then
        echo "$OLLAMA_NUM_THREAD OLLAMA_NUM_THREAD"
        return
    fi
    n="$(cgroup_cpu_limit)"
    if [[ -n "$n" ]]; then
        source="cgroup-cpu-quota=$n"
    else
        n="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
        source="no-quota-visible,nproc=$n"
    fi
    if (( n > AUTO_THREAD_CAP )); then
        echo "$AUTO_THREAD_CAP $source,capped"
    else
        echo "$n $source"
    fi
}

read -r THREADS THREAD_SOURCE < <(resolve_threads)
export LLAMA_ARG_THREADS="$THREADS"
# Render chats with the Modelfile TEMPLATE. Without this, Ollama 0.40 may
# prefer the GGUF's embedded template over the thinking-off template.
export OLLAMA_GO_TEMPLATE="${OLLAMA_GO_TEMPLATE:-1}"
log "inference threads: $THREADS (source: $THREAD_SOURCE)"

/bin/ollama serve &
server_pid=$!
trap 'kill -TERM "$server_pid" 2>/dev/null; wait "$server_pid"; exit $?' TERM INT

client() { OLLAMA_HOST=127.0.0.1:11434 /bin/ollama "$@"; }

for _ in $(seq 1 120); do
    client list >/dev/null 2>&1 && break
    sleep 1
done

pull_models() {
    local model
    for model in ${OLLAMA_PULL_MODELS//,/ }; do
        if client show "$model" >/dev/null 2>&1; then
            log "model $model already present"
        else
            log "pulling $model (first boot only)"
            if client pull "$model" >/dev/null; then
                log "model $model ready"
            else
                log "WARNING: pull of $model failed; redeploy to retry"
            fi
        fi
    done
}

create_default_model() {
    local base="${OLLAMA_BASE_MODEL:-}" name="${OLLAMA_DEFAULT_MODEL:-}"
    local ctx="${OLLAMA_CONTEXT_LENGTH:-16384}" thinking dir params
    thinking="$(printf '%s' "${OLLAMA_THINKING:-false}" | tr '[:upper:]' '[:lower:]')"
    if [[ -z "$base" || -z "$name" || "$name" == "$base" ]]; then
        return 0
    fi
    if ! client show "$base" >/dev/null 2>&1; then
        log "WARNING: base model $base is missing; $name not created"
        return 0
    fi
    dir="$(mktemp -d)"
    params="PARAMETER num_thread $THREADS"$'\n'"PARAMETER num_ctx $ctx"
    {
        echo "FROM $base"
        echo "$params"
        if [[ "$thinking" != "true" && "$base" == qwen3:* && -s "$NOTHINK_TEMPLATE" ]]; then
            # Qwen's recommended sampling for non-thinking mode.
            echo "PARAMETER temperature 0.7"
            echo "PARAMETER top_p 0.8"
            printf 'TEMPLATE """%s"""\n' "$(cat "$NOTHINK_TEMPLATE")"
        fi
    } > "$dir/Modelfile"
    if [[ "$thinking" != "true" && "$base" != qwen3:* ]]; then
        log "OLLAMA_THINKING=false only changes qwen3 models; $name keeps $base's template"
    fi

    if client create "$name" -f "$dir/Modelfile" >/dev/null; then
        if grep -q '^TEMPLATE' "$dir/Modelfile"; then
            log "model $name ready ($base, $THREADS threads, ctx $ctx, thinking off)"
        else
            log "model $name ready ($base, $THREADS threads, ctx $ctx, model's own template)"
        fi
    else
        log "WARNING: creating $name failed; retrying with thread and context settings only"
        printf 'FROM %s\n%s\n' "$base" "$params" > "$dir/Modelfile"
        if client create "$name" -f "$dir/Modelfile" >/dev/null; then
            log "model $name ready ($base, $THREADS threads, ctx $ctx, model's own template)"
        else
            log "WARNING: creating $name failed; Odysseus cannot use it until the next start"
        fi
    fi
    rm -rf "$dir"
}

pull_models
create_default_model

wait "$server_pid"
