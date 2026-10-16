FROM rust:1.93-bookworm AS builder
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release --locked --bin mock-llm

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/target/release/mock-llm /usr/local/bin/mock-llm
ENV PORT=8081 \
    MOCK_TTFT=500 \
    MOCK_OUT_TOKENS=50 \
    MOCK_TOKEN_INTERVAL=20 \
    MOCK_BATCH=1
EXPOSE 8081
ENTRYPOINT ["mock-llm"]
