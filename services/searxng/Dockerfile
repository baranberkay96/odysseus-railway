# Private SearXNG metasearch for Odysseus' web search and deep research.
# Railway cannot bind-mount config files, so the settings are baked in.
# Pinned tag + digest (SearXNG publishes date-stamped rolling builds only).
FROM searxng/searxng:2026.10.13-22c64b8d3@sha256:9b61996edcc679fb6665290f95fda15389a14eda6060e41a25c63ab2758f2436

COPY --chown=searxng:searxng settings.yml /etc/searxng/settings.yml

EXPOSE 8080
