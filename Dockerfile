FROM rust:1.95-bookworm AS builder

WORKDIR /work

COPY Cargo.toml Cargo.lock /work/
COPY src /work/src

RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 takos
RUN mkdir -p /var/lib/takos/agent \
  && chown -R takos:takos /var/lib/takos

COPY --from=builder /work/target/release/takos-agent /usr/local/bin/takos-agent

ENV PORT=8080 \
  TAKOS_AGENT_DATA_DIR=/tmp/takos-agent

USER takos
WORKDIR /app

CMD ["/usr/local/bin/takos-agent"]
