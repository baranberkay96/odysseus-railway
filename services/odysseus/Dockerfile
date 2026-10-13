# Odysseus for Railway: the official image, unchanged, plus a small start
# wrapper (volume layout, dependency wait, one-time bootstrap).
#
# Pinned to upstream release 1.0.3 (main branch commit 934d23c, built
# 2026-09-05). The bare :1.0.3 tag moves on every push to main, so the
# manifest-list digest is pinned as well. Upgrade: replace tag and digest with
# a newer release from https://github.com/odysseus-dev/odysseus/pkgs/container/odysseus
# (`docker buildx imagetools inspect ghcr.io/odysseus-dev/odysseus:<tag>`).
FROM ghcr.io/odysseus-dev/odysseus:1.0.3@sha256:4aa6e607d2108bd7b5f37ee1a0841dc56e6bbac36e9ccd5e1705aff7ea36fb04

COPY railway/ /opt/railway/
RUN chmod 0755 /opt/railway/start.sh

EXPOSE 7000
ENTRYPOINT ["/opt/railway/start.sh"]
# Same command as upstream: uvicorn on 0.0.0.0 (IPv4, which Railway's
# healthcheck and private network use) and port 7000 (PORT=7000 in Railway).
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7000"]
