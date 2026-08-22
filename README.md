# Nextcloud Docker Stack

A small Docker Compose deployment for Nextcloud with MariaDB, Redis, direct HTTPS, FFmpeg, and optional Beszel monitoring.

## Requirements

- Docker Engine with Docker Compose
- OpenSSL
- A Linux host with persistent storage

## Setup

Run the setup script from any directory:

```sh
./scripts/setup.sh
```

On a new installation, the script creates a private `.env`, generates random passwords, prepares storage directories, creates a self-signed TLS certificate, validates the configuration, and starts the core services.

Set the hostname and ports before the first run when the defaults are not suitable:

```sh
NEXTCLOUD_HOST=cloud.example.com HTTP_PORT=80 HTTPS_PORT=443 ./scripts/setup.sh
```

The script does not replace an existing `.env` or certificate. Validate without starting or restarting services with:

```sh
./scripts/setup.sh --check
```

## Existing Installations

The bind mount locations and database credentials in `.env` must match the existing installation. Before applying the new Compose definition:

1. Back up the database, Nextcloud data, configuration, and external storage.
2. Review every path and URL in `.env`.
3. Run `./scripts/setup.sh --check`.
4. Run `docker compose up -d --build` during a maintenance window.
5. Confirm the application with `docker compose exec -u www-data app php occ status`.

Environment variables used for initial administrator creation do not change an existing administrator password.

## HTTPS

Apache listens on ports 80 and 443. HTTP requests redirect to `NEXTCLOUD_URL`.

The generated certificate is intended for local or private deployments and will produce a browser warning. For a trusted certificate, replace the files referenced by `TLS_CERT_PATH` and `TLS_KEY_PATH`, then restart the app service:

```sh
docker compose restart app
```

The certificate must include `TLS_HOST` in its subject alternative names.

## Monitoring

Beszel is isolated in an optional Compose profile:

```sh
./scripts/setup.sh --monitoring
```

Core Nextcloud commands do not start the monitoring service unless the profile is enabled.

## Operations

```sh
docker compose ps
docker compose logs -f app
docker compose exec -u www-data app php occ status
docker compose exec -u www-data app php occ maintenance:mode --on
docker compose exec -u www-data app php occ maintenance:mode --off
docker compose pull
docker compose up -d --build
```

Back up before changing pinned image versions. A complete recovery set includes the MariaDB dump, Nextcloud bind mount, `.env`, TLS material, and any external storage.

## Security

- Never commit `.env`, private keys, certificates, databases, application data, or monitoring state.
- Keep `.env` and TLS private keys readable only by their owner.
- Use unique credentials and rotate any value that has been exposed elsewhere.
- Restrict published ports with a host firewall.
- Use a public CA certificate for internet-facing deployments.
- Run a secret scanner before adding a remote.

The Git and Docker ignore files intentionally exclude all local runtime state from source control and image build contexts.
