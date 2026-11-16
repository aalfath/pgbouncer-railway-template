#!/bin/sh
# Writes pgbouncer.ini and userlist.txt from environment variables, then
# starts PgBouncer in the foreground.
set -eu

: "${PGHOST:?PGHOST must point at the Postgres server (e.g. \${{Postgres.RAILWAY_PRIVATE_DOMAIN}})}"
: "${PGUSER:?PGUSER must be set}"
: "${PGPASSWORD:?PGPASSWORD must be set}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:-postgres}"

CONF_DIR=/etc/pgbouncer
INI="$CONF_DIR/pgbouncer.ini"
USERLIST="$CONF_DIR/userlist.txt"
TLS_DIR="$CONF_DIR/tls"

# Defaults; every PGBOUNCER_<SETTING> variable overrides or adds the
# matching [pgbouncer] setting (PGBOUNCER_POOL_MODE -> pool_mode).
: "${PGBOUNCER_LISTEN_ADDR:=*}"
: "${PGBOUNCER_LISTEN_PORT:=6432}"
: "${PGBOUNCER_POOL_MODE:=transaction}"
: "${PGBOUNCER_MAX_CLIENT_CONN:=500}"
: "${PGBOUNCER_DEFAULT_POOL_SIZE:=20}"
: "${PGBOUNCER_MAX_PREPARED_STATEMENTS:=200}"
: "${PGBOUNCER_AUTH_TYPE:=scram-sha-256}"
: "${PGBOUNCER_AUTH_USER:=$PGUSER}"
: "${PGBOUNCER_AUTH_DBNAME:=$PGDATABASE}"
: "${PGBOUNCER_ADMIN_USERS:=$PGUSER}"
: "${PGBOUNCER_STATS_USERS:=$PGUSER}"
: "${PGBOUNCER_IGNORE_STARTUP_PARAMETERS:=extra_float_digits}"
: "${PGBOUNCER_SERVER_TLS_SSLMODE:=prefer}"
: "${PGBOUNCER_CLIENT_TLS_SSLMODE:=prefer}"
: "${PGBOUNCER_UNIX_SOCKET_DIR:=/tmp}"
export PGBOUNCER_LISTEN_ADDR PGBOUNCER_LISTEN_PORT PGBOUNCER_POOL_MODE \
  PGBOUNCER_MAX_CLIENT_CONN PGBOUNCER_DEFAULT_POOL_SIZE PGBOUNCER_MAX_PREPARED_STATEMENTS \
  PGBOUNCER_AUTH_TYPE PGBOUNCER_AUTH_USER PGBOUNCER_AUTH_DBNAME PGBOUNCER_ADMIN_USERS \
  PGBOUNCER_STATS_USERS PGBOUNCER_IGNORE_STARTUP_PARAMETERS PGBOUNCER_SERVER_TLS_SSLMODE \
  PGBOUNCER_CLIENT_TLS_SSLMODE PGBOUNCER_UNIX_SOCKET_DIR

# Self-signed certificate so clients can use sslmode=require.
if [ "$PGBOUNCER_CLIENT_TLS_SSLMODE" != "disable" ] && [ -z "${PGBOUNCER_CLIENT_TLS_CERT_FILE:-}" ]; then
  mkdir -p "$TLS_DIR"
  if [ ! -s "$TLS_DIR/server.crt" ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=pgbouncer" \
      -keyout "$TLS_DIR/server.key" -out "$TLS_DIR/server.crt" >/dev/null 2>&1
    chmod 600 "$TLS_DIR/server.key"
  fi
  export PGBOUNCER_CLIENT_TLS_KEY_FILE="$TLS_DIR/server.key"
  export PGBOUNCER_CLIENT_TLS_CERT_FILE="$TLS_DIR/server.crt"
fi

# Quote a value for userlist.txt (double any double quote).
q() { printf '"%s"' "$(printf '%s' "$1" | sed 's/"/""/g')"; }

umask 077
{
  printf '%s %s\n' "$(q "$PGUSER")" "$(q "$PGPASSWORD")"
  # Optional extra entries, one '"user" "password-or-SCRAM-secret"' per line.
  if [ -n "${PGBOUNCER_USERLIST:-}" ]; then printf '%s\n' "$PGBOUNCER_USERLIST"; fi
} > "$USERLIST"

{
  echo "[databases]"
  # Any database name is forwarded to the same database on the server.
  echo "* = host=$PGHOST port=$PGPORT"
  echo
  echo "[pgbouncer]"
  echo "auth_file = $USERLIST"
  # auth_query lets every Postgres role log in with its own password.
  echo "auth_query = ${PGBOUNCER_AUTH_QUERY:-SELECT usename, passwd FROM pg_catalog.pg_shadow WHERE usename=\$1}"
  env | grep '^PGBOUNCER_' | grep -v -e '^PGBOUNCER_USERLIST=' -e '^PGBOUNCER_AUTH_QUERY=' | sort | while IFS='=' read -r key value; do
    name=$(printf '%s' "${key#PGBOUNCER_}" | tr 'A-Z' 'a-z')
    printf '%s = %s\n' "$name" "$value"
  done
} > "$INI"

echo "PgBouncer $(pgbouncer --version | head -n1 | awk '{print $2}'): pool_mode=$PGBOUNCER_POOL_MODE, upstream $PGHOST:$PGPORT, listening on port $PGBOUNCER_LISTEN_PORT"
exec pgbouncer "$INI"
