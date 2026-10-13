# CPU Ollama for Odysseus: first-boot model pull, thread pool sized to the
# service's CPU limit, and a tuned default model (thinking off for qwen3).
# Private network only.
FROM ollama/ollama:0.40.3@sha256:adca95a12c2b386a8f9a995e7fa0600e187e3323b5e5522f5a6c3b1ec73eff99

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY qwen3-nothink.tmpl /opt/railway/qwen3-nothink.tmpl
RUN chmod 0755 /usr/local/bin/railway-entrypoint.sh

ENV OLLAMA_HOST=[::]:11434
EXPOSE 11434
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
