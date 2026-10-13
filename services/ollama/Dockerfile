# CPU Ollama with a first-boot model pull, so Odysseus can chat without any
# API key. Private network only.
FROM ollama/ollama:0.40.3@sha256:adca95a12c2b386a8f9a995e7fa0600e187e3323b5e5522f5a6c3b1ec73eff99

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod 0755 /usr/local/bin/railway-entrypoint.sh

ENV OLLAMA_HOST=[::]:11434
EXPOSE 11434
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
