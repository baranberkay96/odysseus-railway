#!/bin/sh
# Starts ntfy as a private, login-protected server for Odysseus alerts.
#
# ntfy provisions users declaratively from NTFY_AUTH_USERS, but that variable
# needs bcrypt hashes, which a Railway template cannot generate. This wrapper
# hashes the generated passwords at every start (ntfy updates provisioned
# users in place) and provisions:
#   - NTFY_ADMIN_USER (role admin): log in with it from the ntfy web app or
#     the Android/iOS app to receive alerts;
#   - "odysseus" (role user, write-only on all topics) with the access token
#     NTFY_ODYSSEUS_TOKEN, which Odysseus uses to publish reminders.
# Anonymous access is denied (NTFY_AUTH_DEFAULT_ACCESS=deny-all).
set -eu

hash_password() {
    printf '%s\n%s\n' "$1" "$1" | ntfy user hash 2>/dev/null
}

admin_user="${NTFY_ADMIN_USER:-admin}"
admin_password="${NTFY_ADMIN_PASSWORD:-}"
publisher_token="${NTFY_ODYSSEUS_TOKEN:-}"

if [ -z "${NTFY_AUTH_USERS:-}" ]; then
    if [ "${#admin_password}" -lt 8 ]; then
        echo "[railway] ERROR: NTFY_ADMIN_PASSWORD must be set (8+ characters)" >&2
        exit 1
    fi
    users="${admin_user}:$(hash_password "$admin_password"):admin"
    if [ -n "$publisher_token" ]; then
        # The publisher only authenticates with its token; its password is
        # random and never stored.
        publisher_password="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
        users="${users},odysseus:$(hash_password "$publisher_password"):user"
        export NTFY_AUTH_ACCESS="${NTFY_AUTH_ACCESS:-odysseus:*:wo}"
        export NTFY_AUTH_TOKENS="${NTFY_AUTH_TOKENS:-odysseus:${publisher_token}:Odysseus reminders}"
    fi
    export NTFY_AUTH_USERS="$users"
fi

mkdir -p "$(dirname "${NTFY_AUTH_FILE:-/var/lib/ntfy/user.db}")" \
         "$(dirname "${NTFY_CACHE_FILE:-/var/lib/ntfy/cache.db}")" \
         "${NTFY_ATTACHMENT_CACHE_DIR:-/var/lib/ntfy/attachments}"

exec ntfy serve "$@"
