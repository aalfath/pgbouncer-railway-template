# PgBouncer on Railway

A Railway template that deploys [PgBouncer](https://www.pgbouncer.org/) **1.26.1**, the lightweight PostgreSQL connection pooler, in front of a Railway Postgres database.

PgBouncer publishes no official Docker image, so this repo builds the official release tarball (the GitHub release asset, identical to the pgbouncer.org download, SHA-256 checked) on a digest-pinned `debian:trixie-slim` base. Nothing else is downloaded at build time apart from Debian's own packages.

## What the template deploys

| Service | Source | Notes |
|---|---|---|
| **PgBouncer** | this repo (`Dockerfile`, `start.sh`) | Listens on port 6432 (private network) and on a Railway TCP proxy for outside clients. No volume needed: it keeps no data. |
| **Postgres** | Railway's Postgres | Data lives on its volume. |

Connect your apps to `${{PgBouncer.DATABASE_URL}}` instead of `${{Postgres.DATABASE_URL}}`. Outside Railway, use `DATABASE_PUBLIC_URL`.

## How it works

- `start.sh` writes `pgbouncer.ini` and `userlist.txt` from environment variables and starts PgBouncer in the foreground as a non-root user.
- Every database name is forwarded to the same database on the server (`* = host=… port=…`).
- `auth_query` (against `pg_shadow`, run as the Postgres superuser in `PGDATABASE`) lets **every Postgres role log in with its own password**, so new roles work without editing a userlist.
- Clients authenticate with SCRAM-SHA-256. A self-signed certificate is created at start, so clients can use `sslmode=require`. PgBouncer connects to Postgres with TLS when the server offers it.
- The Postgres superuser is also PgBouncer's admin and stats user, so `psql "$DATABASE_URL" -d pgbouncer -c 'SHOW POOLS'` works.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` | references to the `Postgres` service | The upstream server and the superuser PgBouncer uses for `auth_query`. Point them at another Postgres service to pool that one instead. |
| `DATABASE_URL` | `postgresql://…@${{RAILWAY_PRIVATE_DOMAIN}}:6432/…` | Pooled URL for other Railway services. |
| `DATABASE_PUBLIC_URL` | `postgresql://…@${{RAILWAY_TCP_PROXY_DOMAIN}}:${{RAILWAY_TCP_PROXY_PORT}}/…` | Pooled URL for clients outside Railway. |
| `PGBOUNCER_POOL_MODE` | `transaction` | `session`, `transaction` or `statement`. Use `session` for apps that need session state (LISTEN/NOTIFY, session advisory locks, `SET` without `LOCAL`). |
| `PGBOUNCER_DEFAULT_POOL_SIZE` | `20` | Server connections per user/database pair. |
| `PGBOUNCER_MAX_CLIENT_CONN` | `500` | Maximum client connections. |

Any other `PGBOUNCER_<SETTING>` variable becomes the matching `[pgbouncer]` setting in lower case, for example `PGBOUNCER_MAX_DB_CONNECTIONS=80` → `max_db_connections = 80`. See the [configuration reference](https://www.pgbouncer.org/config.html). `PGBOUNCER_USERLIST` adds extra `"user" "password"` lines to the auth file.

## Updates

The template's PgBouncer service builds from this repo's `main` branch. When a new PgBouncer release is pinned here and merged to `main`, Railway shows deployers an "update available" notice and they choose when to apply it. Each version is listed in [CHANGELOG.md](CHANGELOG.md), breaking changes first.

## Local test

```sh
docker build -t pgbouncer-railway .
docker run --rm -e PGHOST=db -e PGUSER=postgres -e PGPASSWORD=secret -e PGDATABASE=postgres -p 6432:6432 pgbouncer-railway
```
