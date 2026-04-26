FROM rust:1.94-bookworm AS builder

WORKDIR /work

COPY takos-agent-engine/Cargo.toml /work/takos-agent-engine/Cargo.toml
COPY takos-agent-engine/Cargo.lock /work/takos-agent-engine/Cargo.lock
COPY takos-agent-engine/src /work/takos-agent-engine/src
COPY takos-agent/Cargo.toml /work/takos-agent/Cargo.toml
COPY takos-agent/Cargo.lock /work/takos-agent/Cargo.lock
COPY takos-agent/src /work/takos-agent/src

RUN cargo build --manifest-path /work/takos-agent/Cargo.toml --release

FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 takos
RUN mkdir -p /var/lib/takos/agent \
  && chown -R takos:takos /var/lib/takos

COPY --from=builder /work/takos-agent/target/release/takos-agent /usr/local/bin/takos-agent

ENV PORT=8080 \
  TAKOS_AGENT_DATA_DIR=/tmp/takos-agent

USER takos
WORKDIR /app

CMD ["/usr/local/bin/takos-agent"]
