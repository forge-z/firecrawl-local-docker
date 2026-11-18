# Firecrawl Local em Rust (NAO e a stack apps/api do Firecrawl)
# Build multiplo: o compilador Rust nao fica na imagem final.
FROM rust:1-bookworm AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates git build-essential pkg-config libssl-dev cmake clang \
    && rm -rf /var/lib/apt/lists/*

# Commit conhecido que contem Firecrawl Local v0.1.1; altere conscientemente.
ARG FIRECRAWL_REF=d339a06385844136521b85b9300f0953da67a67a
WORKDIR /build
RUN git init firecrawl \
    && cd firecrawl \
    && git remote add origin https://github.com/firecrawl/firecrawl.git \
    && git fetch --depth 1 origin "${FIRECRAWL_REF}" \
    && git checkout --detach FETCH_HEAD

WORKDIR /build/firecrawl/apps/local
# Limita paralelismo da compilacao para reduzir picos no Beelink.
ENV CARGO_BUILD_JOBS=2
RUN cargo build --release --locked

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates chromium chromium-sandbox curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 firecrawl \
    && useradd --uid 10001 --gid 10001 --create-home --shell /bin/sh firecrawl \
    && install -d -o firecrawl -g firecrawl /home/firecrawl/.firecrawl

COPY --from=builder /build/firecrawl/apps/local/target/release/firecrawl-local /usr/local/bin/firecrawl-local
COPY --chmod=0755 entrypoint.sh /usr/local/bin/firecrawl-entrypoint

ENV HOME=/home/firecrawl \
    FIRECRAWL_LOCAL_HOME=/home/firecrawl/.firecrawl \
    FIRECRAWL_CHROME_PATH=/usr/bin/chromium \
    FIRECRAWL_LOCAL_BROWSER=auto \
    FIRECRAWL_CLOUD=off

USER firecrawl
WORKDIR /home/firecrawl
EXPOSE 3002
ENTRYPOINT ["/usr/local/bin/firecrawl-entrypoint"]
