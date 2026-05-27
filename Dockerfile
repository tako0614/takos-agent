FROM rust:1.94-bookworm AS builder

WORKDIR /work/takos/agent

COPY takos/agent/Cargo.toml takos/agent/Cargo.lock ./
COPY takos/agent/src ./src
COPY takos-agent-engine /work/takos-agent-engine

RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 takos
RUN mkdir -p /tmp/takos-agent \
  && chown -R takos:takos /tmp/takos-agent

COPY --from=builder /work/takos/agent/target/release/takos-agent /usr/local/bin/takos-agent

ENV PORT=8080 \
  TAKOS_AGENT_DATA_DIR=/tmp/takos-agent

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -f http://localhost:8080/health || exit 1

USER takos
WORKDIR /app

CMD ["/usr/local/bin/takos-agent"]
