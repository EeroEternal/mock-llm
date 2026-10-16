# mock-llm

**mock-llm** is a high-concurrency, zero-allocation OpenAI-compatible mock upstream server written in Rust. Purpose-built for stress-testing AI gateways and streaming load balancers at 10,000+ concurrent streams, it serves both **HTTP/1.1** and **cleartext HTTP/2 (`h2c`)** on a single port with deterministic TTFT pacing, token intervals, live `/_config` hot-reloading, and fault injection—while keeping mock server CPU overhead near zero.

<p align="center">
  <img src="docs/assets/architecture.svg" alt="mock-llm Architecture" width="100%">
</p>

## Why mock-llm

When benchmarking an AI gateway at 10,000–20,000 concurrent SSE streams (millions of chunks per second), conventional Python/Node/Go mock servers spend more CPU serializing JSON and allocating timers than the gateway under test.

- **Zero-Allocation SSE Frame Engine** — Pre-renders `chat.completion.chunk` frames from constant byte slices and patches only the 13-digit millisecond timestamp (`ts`) in place into a reusable `BytesMut` buffer, paired with `tokio::time::Sleep::reset` timer reuse (~`65k req/s` at `0.14` CPU cores).
- **Single-Port HTTP/1.1 & `h2c` Dual-Stack** — Automatically serves HTTP/1.1 keep-alive and HTTP/2 prior-knowledge (`h2c`) connections on the same listener, advertising `SETTINGS_MAX_CONCURRENT_STREAMS = 250` for realistic HTTP/2 connection pool benchmarking.
- **Live Workload Reconfiguration (`POST /_config`)** — Mutate TTFT delay, token interval, output token count, socket write batching, or randomized `long / mid / short` token distributions between benchmark stages without restarting processes.
- **Deterministic Per-Request Fault & Latency Injection** — Override `ttft`, `output`, `duration`, or inject HTTP `429 Too Many Requests` / `500 Internal Server Error` responses via `x-mock-*` request headers to verify gateway failover and circuit breaking.

| Dimension | **mock-llm (Rust)** | **Python / FastAPI Mock** | **Node.js / Go Naive Mock** |
| :--- | :--- | :--- | :--- |
| **SSE Chunk Assembly** | **In-place byte slice + `ts` patch (0 JSON serialization)** | Per-chunk `json.dumps()` + dict allocation | Per-chunk `JSON.stringify` / `json.Marshal` |
| **Timer Scheduling** | **Single pinned `Sleep::reset` per stream** | New asyncio task / timer per chunk | New `setTimeout` / `time.After` per chunk |
| **Transport Support** | **Single-port auto HTTP/1.1 + `h2c` (`250` streams/conn)** | HTTP/1.1 (or separate h2 flags) | Separate ports or manual h2c wiring |
| **Runtime Control** | **Live `POST /_config` + per-request `x-mock-*` headers** | Process restart required | Custom code required |

## Quick Start

**Option 1 — Docker:**

```bash
docker run -d --name mock-llm -p 8081:8081 \
  -e MOCK_TTFT=500 -e MOCK_OUT_TOKENS=100 -e MOCK_TOKEN_INTERVAL=20 \
  ghcr.io/eeroeternal/mock-llm:latest
```

**Option 2 — Pre-built Binary (or `cargo run --release`):**

```bash
PORT=8081 MOCK_TTFT=500 MOCK_OUT_TOKENS=100 ./mock-llm
```

Send a streaming request, hot-update the workload profile via `POST /_config`, or inject a `429` error via `x-mock-*` headers (full parameter & header tables in [`docs/configuration.md`](docs/configuration.md)):

```bash
# 1. Stream OpenAI SSE chunks
curl -N http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"mock","stream":true,"messages":[{"role":"user","content":"hi"}]}'

# 2. Hot-update TTFT, output tokens, and interval at runtime without restart
curl -X POST "http://127.0.0.1:8081/_config?ttft=200&out_tokens=250&token_interval=10"

# 3. Inject HTTP 429 rate-limit error to test gateway failover
curl -i http://127.0.0.1:8081/v1/chat/completions -H "x-mock-error: rate_limit" -d '{"model":"mock"}'
```

## Documentation

- [Configuration & HTTP Contract](docs/configuration.md) — environment variables, live `POST /_config` query keys, `x-mock-*` request headers, and SSE wire format
- [License](LICENSE) — MIT
