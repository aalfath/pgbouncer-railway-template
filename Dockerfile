# PgBouncer for Railway, built from the official release tarball
# (GitHub release asset, same file and SHA-256 as on pgbouncer.org).
# PgBouncer publishes no official Docker image, so this builds the upstream
# release (checksum-pinned) on a digest-pinned Debian base.
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

FROM ${DEBIAN_IMAGE} AS build
ARG PGBOUNCER_VERSION=1.26.1
ARG PGBOUNCER_SHA256=00886a2994b4844cd37110970df777772cfc42a74c400522c82fba509a3f42d9
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl build-essential pkg-config \
      libevent-dev libssl-dev libc-ares-dev \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN curl -fsSLo pgbouncer.tar.gz "https://github.com/pgbouncer/pgbouncer/releases/download/pgbouncer_$(echo "${PGBOUNCER_VERSION}" | tr . _)/pgbouncer-${PGBOUNCER_VERSION}.tar.gz" \
 && echo "${PGBOUNCER_SHA256}  pgbouncer.tar.gz" | sha256sum -c - \
 && tar xzf pgbouncer.tar.gz --strip-components=1 \
 && ./configure --prefix=/usr/local --with-cares --with-openssl \
 && make -j"$(nproc)" pgbouncer \
 && install -m 0755 -s pgbouncer /usr/local/bin/pgbouncer

FROM ${DEBIAN_IMAGE}
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates openssl libevent-2.1-7t64 libssl3t64 libc-ares2 \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system pgbouncer \
 && useradd --system --gid pgbouncer --home-dir /etc/pgbouncer --shell /usr/sbin/nologin pgbouncer \
 && mkdir -p /etc/pgbouncer \
 && chown pgbouncer:pgbouncer /etc/pgbouncer
COPY --from=build /usr/local/bin/pgbouncer /usr/local/bin/pgbouncer
COPY --chmod=0755 start.sh /usr/local/bin/start-pgbouncer
RUN pgbouncer --version
USER pgbouncer
EXPOSE 6432
ENTRYPOINT ["/usr/local/bin/start-pgbouncer"]
