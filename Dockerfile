FROM rust:1.94-bookworm AS builder

WORKDIR /work

COPY agent-engine/Cargo.toml /work/agent-engine/Cargo.toml
COPY agent-engine/Cargo.lock /work/agent-engine/Cargo.lock
COPY agent-engine/src /work/agent-engine/src
COPY agent/Cargo.toml /work/agent/Cargo.toml
COPY agent/Cargo.lock /work/agent/Cargo.lock
COPY agent/src /work/agent/src

RUN cargo build --manifest-path /work/agent/Cargo.toml --release

FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 takos
RUN mkdir -p /var/lib/takos/agent \
  && chown -R takos:takos /var/lib/takos

COPY --from=builder /work/agent/target/release/takos-agent /usr/local/bin/takos-agent

ENV PORT=8080 \
  TAKOS_AGENT_DATA_DIR=/tmp/takos-agent

USER takos
WORKDIR /app

CMD ["/usr/local/bin/takos-agent"]
