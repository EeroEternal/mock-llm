# Configuration & HTTP Contract

`mock-llm` exposes two endpoints on a single dual-stack (HTTP/1.1 + `h2c`) TCP listener:

- `POST /v1/chat/completions` — OpenAI-compatible streaming (`text/event-stream`) and non-streaming (`application/json`) responses.
- `POST /_config` — Live runtime configuration inspection and hot-reload without restarting the process.

## 1. Environment Variables & `POST /_config` Query Keys

All workload parameters can be initialized via environment variables at startup and mutated at runtime via `POST /_config?<key>=<val>`:

| Env Variable | `/_config` Key | Default | Description |
| :--- | :--- | :--- | :--- |
| `PORT` | *(env only)* | `8081` | TCP listen port on `0.0.0.0` |
| `MOCK_TTFT` | `ttft` | `500` | Pre-first-token delay in ms |
| `MOCK_OUT_TOKENS` | `out_tokens` | `50` | Number of content SSE frames emitted per stream |
| `MOCK_TOKEN_INTERVAL` | `token_interval` | `0` | Inter-frame interval in ms (`0` falls back to `MOCK_STREAM_DEFAULT_INTERVAL`) |
| `MOCK_STREAM_DEFAULT_INTERVAL` | *(env only)* | `20` | Fallback interval in ms when `token_interval = 0` |
| `MOCK_BATCH` | `batch` | `1` | Coalesce every `N` content frames into a single socket write (byte-identical payload) |
| `MOCK_TOTAL_DELAY` | `total_delay` | `0` | Additional delay in ms for non-streaming responses (`ttft + total_delay`) |
| `MOCK_RESPONSE_SIZE` | `response_size` | `0` | Total content byte budget (`0` = 4 bytes per frame) |
| `MOCK_MAX_DURATION` | `max_duration` | `0` | Max streaming duration in ms before frame truncation (`0` = unlimited) |
| `MOCK_MIX` | `mix` | `0` | When `1`, sample `out_tokens` across `long` / `mid` / `short` tiers by percentage |
| `MOCK_LONG_PCT` / `MID_PCT` / `SHORT_PCT` | `long_pct` / `mid_pct` / `short_pct` | `20` / `30` / `50` | Percentage weights when `mix = 1` |
| `MOCK_LONG_OUT` / `MID_OUT` / `SHORT_OUT` | `long_out` / `mid_out` / `short_out` | `500` / `250` / `100` | Output token counts for each tier when `mix = 1` |

### Live Reconfiguration Examples

```bash
# Inspect current runtime state
curl -X POST "http://127.0.0.1:8081/_config"

# Switch to a 500ms TTFT, 250-token, 50 tok/s (20ms interval) streaming profile
curl -X POST "http://127.0.0.1:8081/_config?ttft=500&out_tokens=250&token_interval=20&batch=1"

# Enable mixed workload distribution (20% 500-tok, 30% 250-tok, 50% 100-tok)
curl -X POST "http://127.0.0.1:8081/_config?mix=1&long_pct=20&mid_pct=30&short_pct=50"
```

## 2. Per-Request Override & Fault Injection Headers

Any individual request to `POST /v1/chat/completions` can override the global configuration or trigger deterministic upstream errors using `x-mock-*` headers:

| Header | Example | Effect |
| :--- | :--- | :--- |
| `x-mock-ttft` | `x-mock-ttft: 100` | Override `ttft` (ms) for this request |
| `x-mock-delay` | `x-mock-delay: 50` | Override `total_delay` (ms) for this request |
| `x-mock-output` | `x-mock-output: 500` | Override `out_tokens` for this request |
| `x-mock-size` | `x-mock-size: 4096` | Override `response_size` (bytes) for this request |
| `x-mock-duration` | `x-mock-duration: 2000` | Override `max_duration` (ms) for this request |
| `x-mock-error` | `rate_limit` or `500` | Immediately return HTTP `429 Too Many Requests` or `500 Internal Server Error` |

## 3. SSE Wire Format & Timestamp Patching

Each emitted SSE chunk embeds a 13-digit Unix millisecond timestamp (`"ts":1710000000000`) patched in-place into a pre-allocated buffer so load generators (`k6`, `locust`, etc.) can measure exact one-way transit latency without JSON serialization overhead on the mock server:

```text
data: {"id":"chatcmpl-mock","object":"chat.completion.chunk","model":"mock","ts":1710000000000,"choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

data: {"id":"chatcmpl-mock","object":"chat.completion.chunk","model":"mock","ts":1710000000020,"choices":[{"index":0,"delta":{"content":"tok "},"finish_reason":null}]}

data: {"id":"chatcmpl-mock","object":"chat.completion.chunk","model":"mock","ts":1710000000040,"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```
