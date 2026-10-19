#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")
ENV_FILE="$ROOT_DIR/.env"

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

case "${1:-}" in
    "") profile=""; check_only=false ;;
    --monitoring) profile="monitoring"; check_only=false ;;
    --check) profile=""; check_only=true ;;
    *) fail "Usage: $0 [--monitoring|--check]" ;;
esac

command -v docker >/dev/null 2>&1 || fail "Docker is required."
command -v openssl >/dev/null 2>&1 || fail "OpenSSL is required."
docker compose version >/dev/null 2>&1 || fail "Docker Compose is required."
docker info >/dev/null 2>&1 || fail "Docker is not running."

cd "$ROOT_DIR"

if [ ! -f "$ENV_FILE" ]; then
    umask 077
    host=${NEXTCLOUD_HOST:-localhost}
    http_port=${HTTP_PORT:-8080}
    https_port=${HTTPS_PORT:-8443}

    if [ "$https_port" = "443" ]; then
        public_url="https://$host"
    else
        public_url="https://$host:$https_port"
    fi

    cat > "$ENV_FILE" <<EOF
COMPOSE_PROJECT_NAME=nextcloud

HTTP_PORT=$http_port
HTTPS_PORT=$https_port
TLS_HOST=$host
NEXTCLOUD_URL=$public_url
NEXTCLOUD_TRUSTED_DOMAINS="$host localhost 127.0.0.1"

NEXTCLOUD_DATA_PATH=./data
DATABASE_DATA_PATH=./db
VAULT_PATH=./vault
TLS_CERT_PATH=./certs/tls.crt
TLS_KEY_PATH=./certs/tls.key

MARIADB_ROOT_PASSWORD=$(openssl rand -hex 24)
MARIADB_DATABASE=nextcloud
MARIADB_USER=nextcloud
MARIADB_PASSWORD=$(openssl rand -hex 24)

NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -hex 24)
PHP_MEMORY_LIMIT=1G
PHP_UPLOAD_LIMIT=10G

BESZEL_PORT=8090
BESZEL_URL=http://localhost:8090
BESZEL_DATA_PATH=./beszel_data
BESZEL_SOCKET_PATH=./beszel_socket

LAN_REDIRECT_ENABLED=false
LAN_REDIRECT_HOST=
EOF
    printf 'Created %s\n' "$ENV_FILE"
fi

chmod 600 "$ENV_FILE"
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

[ "$MARIADB_ROOT_PASSWORD" != "change-me" ] || fail "Set MARIADB_ROOT_PASSWORD in .env."
[ "$MARIADB_PASSWORD" != "change-me" ] || fail "Set MARIADB_PASSWORD in .env."
[ "$NEXTCLOUD_ADMIN_PASSWORD" != "change-me" ] || fail "Set NEXTCLOUD_ADMIN_PASSWORD in .env."

: "${LAN_REDIRECT_ENABLED:=false}"
: "${LAN_REDIRECT_HOST:=}"
export LAN_REDIRECT_ENABLED LAN_REDIRECT_HOST
case "$LAN_REDIRECT_ENABLED" in
    true|false) ;;
    *) fail "LAN_REDIRECT_ENABLED must be true or false in .env." ;;
esac
if [ "$LAN_REDIRECT_ENABLED" = "true" ] && [ -z "$LAN_REDIRECT_HOST" ]; then
    fail "Set LAN_REDIRECT_HOST in .env when LAN_REDIRECT_ENABLED=true."
fi

mkdir -p \
    "$NEXTCLOUD_DATA_PATH" \
    "$DATABASE_DATA_PATH" \
    "$VAULT_PATH" \
    "$BESZEL_DATA_PATH" \
    "$BESZEL_SOCKET_PATH" \
    "$(dirname "$TLS_CERT_PATH")" \
    "$(dirname "$TLS_KEY_PATH")"

if [ -f "$TLS_CERT_PATH" ] && [ -f "$TLS_KEY_PATH" ]; then
    openssl x509 -in "$TLS_CERT_PATH" -noout >/dev/null 2>&1 || fail "TLS certificate is invalid."
    openssl pkey -in "$TLS_KEY_PATH" -noout >/dev/null 2>&1 || fail "TLS private key is invalid."
    cert_key=$(openssl x509 -in "$TLS_CERT_PATH" -pubkey -noout | openssl pkey -pubin -outform DER 2>/dev/null | openssl dgst -sha256)
    private_key=$(openssl pkey -in "$TLS_KEY_PATH" -pubout -outform DER 2>/dev/null | openssl dgst -sha256)
    [ "$cert_key" = "$private_key" ] || fail "TLS certificate and private key do not match."
    if [ "$LAN_REDIRECT_ENABLED" = "true" ]; then
        san_text=$(openssl x509 -in "$TLS_CERT_PATH" -noout -ext subjectAltName 2>/dev/null || true)
        case "$LAN_REDIRECT_HOST" in
            *[!0-9.]*) san_kind="DNS:$LAN_REDIRECT_HOST" ;;
            *) san_kind="IP:$LAN_REDIRECT_HOST" ;;
        esac
        if ! printf '%s\n' "$san_text" | grep -qF "$san_kind"; then
            printf 'Warning: existing certificate lacks subjectAltName %s. Delete %s and %s and rerun to regenerate.\n' \
                "$san_kind" "$TLS_CERT_PATH" "$TLS_KEY_PATH" >&2
        fi
    fi
elif [ -e "$TLS_CERT_PATH" ] || [ -e "$TLS_KEY_PATH" ]; then
    fail "Both TLS_CERT_PATH and TLS_KEY_PATH must exist."
else
    case "$TLS_HOST" in
        *[!0-9.]*) subject_alt_name="DNS:$TLS_HOST" ;;
        *) subject_alt_name="IP:$TLS_HOST" ;;
    esac

    if [ "$LAN_REDIRECT_ENABLED" = "true" ]; then
        case "$LAN_REDIRECT_HOST" in
            *[!0-9.]*) subject_alt_name="$subject_alt_name, DNS:$LAN_REDIRECT_HOST" ;;
            *) subject_alt_name="$subject_alt_name, IP:$LAN_REDIRECT_HOST" ;;
        esac
    fi

    umask 077
    openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 365 \
        -subj "/CN=$TLS_HOST" \
        -addext "subjectAltName=$subject_alt_name" \
        -keyout "$TLS_KEY_PATH" \
        -out "$TLS_CERT_PATH" >/dev/null 2>&1
    chmod 600 "$TLS_KEY_PATH"
    chmod 644 "$TLS_CERT_PATH"
    printf 'Created a self-signed certificate for %s\n' "$TLS_HOST"
fi

docker compose config --quiet

if [ "$check_only" = true ]; then
    printf 'Configuration is valid.\n'
    exit 0
fi

if [ "$profile" = "monitoring" ]; then
    docker compose --profile monitoring up -d --build
else
    docker compose up -d --build
fi

printf 'Nextcloud is available at %s\n' "$NEXTCLOUD_URL"
