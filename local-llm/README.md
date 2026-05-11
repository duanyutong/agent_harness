# Local LLM Setup for M3 Pro (Bleeding Edge, May 2026)

## Result (decided 2026-05-11): Rapid-MLX wins

After head-to-head benchmarking on the actual hardware, **Rapid-MLX** is the daily-driver choice for this setup. Summary numbers (Qwen3-Coder-30B-A3B-Instruct, M3 Pro 36 GB, 5 trials × 1000 max-tokens):

| Engine           | Decode tok/s | Cold TTFT (s) | Warm TTFT (s)                | RSS working set (MB) | Cache type                   |
| ---------------- | ------------ | ------------- | ---------------------------- | -------------------- | ---------------------------- |
| **Rapid-MLX** ✅ | **51.2**     | 13.46         | **0.97** (immediate)         | **326**              | RAM prompt cache             |
| llama-server     | 46.6         | 16.24         | **0.70** (immediate)         | 25,809               | RAM prompt cache (8 GB ring) |
| oMLX             | 50.4         | 11.87         | 1.32 (**after 3 cold runs**) | 2,876                | RAM + SSD 2-tier             |

**Why Rapid-MLX:** highest decode, lowest RSS, instant warm-cache hit, simplest install. llama-server is faster on warm TTFT but burns 26 GB of RAM pre-allocating its 96 K KV cache — not worth it unless you actively use that much context per turn. oMLX is genuinely interesting (the SSD tier survives restarts) but has a bizarre 3-cold-run warm-up policy that costs you the first few minutes of every fresh-prefix session, plus the slowest warm TTFT of the three.

See **Benchmark methodology and results** below for the full data. Daily-use scripts live in `serve/`; full bench in `benchmark/`.

---

## Context

User has: **MacBook Pro M3 with 36GB unified RAM**, prefers **docker-compose** for everything else in dev workflow.

Goal: Run the best quality-performance coding model locally with extreme optimization (DS4-style philosophy generalized). User prefers bleeding-edge tools over conservative defaults.

---

## Decision: Benchmark Three Candidates Head-to-Head

Public data is insufficient to pick a winner. We install three approaches and benchmark them on this machine with the same model family and prompts. The three-way structure separates two questions: _engine choice_ (MLX vs llama.cpp) and _SSD-backed KV caching for repeated prefixes_.

DMR (Docker Model Runner) was considered and **explicitly excluded** — see "Background: Why Other Options Were Rejected" for the full reasoning. Short version: DMR hard-wires llama.cpp to 4 concurrent slots with no CLI knob to disable it, which on 36 GB Apple Silicon forces a ~75 % tax on the KV-cache budget. Approach C runs the same llama.cpp engine on the same GGUF without that tax, and is the strictly-better way to evaluate llama.cpp on this hardware.

### What we're actually comparing

| Engine                              | Approach                       | Model format                    | Backend                         | Differentiator                                           |
| ----------------------------------- | ------------------------------ | ------------------------------- | ------------------------------- | -------------------------------------------------------- |
| **Rapid-MLX** (Approach A)          | Native Metal, host-side daemon | MLX 4-bit                       | MLX runtime                     | Mature MLX wrapper, tool-call parsers per model          |
| **Raw `llama-server`** (Approach C) | Native Metal, host-side daemon | GGUF Q4_K_XL (Unsloth)          | llama.cpp                       | llama.cpp at full power: `--parallel 1 --ctx-size 96000` |
| **oMLX** (Approach D)               | Native Metal, host-side daemon | MLX 4-bit (_same weights as A_) | MLX runtime + two-tier KV cache | SSD-backed KV cache → cached TTFT 1-3 s vs 30-90 s       |

### Why these three approaches

Independent benchmarking ([famstack.dev](https://famstack.dev/guides/mlx-vs-gguf-part-2-isolating-variables/)) shows that on Qwen3 30B-A3B, MLX and llama.cpp essentially tie on raw decode (~55-58 tok/s). The "MLX is 3-4× faster" marketing is mostly comparing against Ollama's slow wrapper, not raw llama.cpp. The genuinely different optimization vector is **cached TTFT for repeated prompt prefixes** — exactly what coding agents pay all the time on every turn. That's where Approach D (oMLX) earns its slot.

The three-way bench separates two questions:

| Comparison                       | Tells us                                                                                                                               |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| A vs C                           | Is the **MLX runtime** materially faster than llama.cpp on raw decode for this model? (Likely a tie on this model — see famstack.dev.) |
| A vs D (or A with prefix replay) | Is **SSD-backed KV caching** for repeated prefixes a game-changer for agent workflows?                                                 |

If A ≈ D on raw decode, A is redundant — D supersedes it. Keep A only if you specifically want a baseline for "MLX without the SSD cache"; for picking a winner, D alone covers the MLX side. (A also has Rapid-MLX's tool-call parsers, which the bench doesn't measure but you may care about.)

### Why no clear public winner

| Engine                            | Public single-user benchmark on Qwen3-Coder-30B-A3B                  |
| --------------------------------- | -------------------------------------------------------------------- |
| **Rapid-MLX** (Approach A)        | Self-published: ~130 tok/s on M4 Pro 64GB (3x Ollama)                |
| **Raw llama-server** (Approach C) | No published benchmarks for this exact model on M3 Pro               |
| **oMLX** (Approach D)             | No M3 Pro number. Cached-TTFT claim: 1-3 s vs 30-90 s without cache. |
| Reference: Ollama 0.19+ MLX       | ~43 tok/s on M4 Pro 64GB (same comparison)                           |

### Common to all three approaches

- **Model family**: Qwen3-Coder-30B-A3B-Instruct (MoE: 30.5 B total / 3.3 B active)
  - 256K native context (1M with Yarn)
  - SOTA agentic coding in the 36 GB-feasible tier
  - Tool calling fixed May 2026 across llama.cpp/Ollama/MLX
  - **B and C use the exact same GGUF file** (Unsloth Q4_K_XL); A uses the equivalent MLX 4-bit conversion. The benchmark is therefore not strictly weights-identical between A and B/C — that's an unavoidable consequence of MLX and GGUF being different on-disk formats.
- **OpenAI-compatible API**: all three engines expose `http://localhost:PORT/v1`
- **Expected M3 Pro throughput**: ~50-65 % of M4 Max numbers due to ~150 GB/s bandwidth

### Trade-offs accepted

- **Bleeding edge risk**: All three engines launched in 2026 and are pre-v1.0
- **Local quality cap**: Still meaningfully worse than Claude Sonnet / GPT-5 for complex multi-step agentic flows
- **Setup before benchmark**: We install all three before deciding
- **Quantization mismatch**: A's MLX 4-bit and B/C's GGUF Q4_K_XL are different quantization schemes of the same base weights. Q4_K_XL ("Ultra-Dynamic" Unsloth quant) is generally a few % higher quality than vanilla 4-bit; treat A vs B/C as engine-and-quant comparisons, not pure engine comparisons

---

## Approach A: Rapid-MLX Native + Docker-Compose Hybrid

**Design**: Rapid-MLX runs natively on host (with Metal access). docker-compose services talk to it via `host.docker.internal:8000`.

### A.1 — Install Rapid-MLX

```bash
brew install raullenchai/rapid-mlx/rapid-mlx

# Verify
rapid-mlx doctor
rapid-mlx models
```

Alternates: `pip install rapid-mlx` (Python 3.10+) or `curl -fsSL https://raullenchai.github.io/Rapid-MLX/install.sh | bash`.

### A.2 — Serve the model

> **Alias trap — verify before running.** Rapid-MLX exposes two confusingly-named aliases for Qwen3-Coder:
>
> - `qwen3-coder` → `lmstudio-community/Qwen3-Coder-Next-MLX-4bit` — a _different, much larger_ MoE model (~40 GB on disk).
> - `qwen3-coder-30b` → `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` — the 30B model that matches DMR's GGUF (~17 GB on disk).
>
> Always confirm with `rapid-mlx info <alias>` before serving. Use **`qwen3-coder-30b`** for parity with Approaches B and C.

```bash
# First run auto-downloads ~17 GB from Hugging Face into ~/.cache/huggingface/.
rapid-mlx serve qwen3-coder-30b --prefill-step-size 8192 --port 8000
```

`--prefill-step-size 8192` is recommended for Qwen3-Coder's long-context architecture per Rapid-MLX docs.

Smoke test:

```bash
curl -X POST "http://localhost:8000/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-coder-30b",
    "messages": [{"role": "user", "content": "Write a Python function to reverse a linked list."}]
  }'
```

### A.3 — Persist as launchd service (optional)

`~/Library/LaunchAgents/com.rapid-mlx.server.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.rapid-mlx.server</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/rapid-mlx</string>
    <string>serve</string>
    <string>qwen3-coder-30b</string>
    <string>--prefill-step-size</string><string>8192</string>
    <string>--port</string><string>8000</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/rapid-mlx.log</string>
  <key>StandardErrorPath</key><string>/tmp/rapid-mlx.err</string>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.rapid-mlx.server.plist
```

### A.4 — docker-compose clients (if needed)

Other services in your docker-compose can hit the host-side daemon:

```yaml
services:
  your-app:
    environment:
      - OPENAI_BASE_URL=http://host.docker.internal:8000/v1
      - OPENAI_API_KEY=not-needed
      - OPENAI_MODEL=qwen3-coder-30b
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

---

## Approach C: Raw `llama-server`

**Design**: Run llama.cpp's reference HTTP server directly on the host with `--parallel 1 --ctx-size 96000`. This is llama.cpp at full power on this hardware — one slot, the entire ~9 GB KV-cache budget, 96 K usable context per turn. (Compare DMR, which forces 4 slots × 24 K — see "Background: Why Other Options Were Rejected".)

### C.1 — Install llama.cpp

```bash
brew install llama.cpp     # ships with `llama-server`, Metal-accelerated by default

# Verify
llama-server --version
```

Alternatives (if Homebrew lags upstream): build from source per [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) with `cmake -DGGML_METAL=on`.

### C.2 — Locate the GGUF

`llama-server-setup.sh` will discover the GGUF automatically — it tries, in order, a manual download path and (as a fallback) DMR's content-addressed cache if you happen to have the model pulled there. To get the file:

```bash
# Direct download from HuggingFace (recommended — no Docker needed):
mkdir -p ~/models/qwen3-coder
hf download unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF \
  Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf \
  --local-dir ~/models/qwen3-coder
```

(If you already have the file in DMR's cache from prior experimentation, the setup script will pick it up there and skip the download.)

### C.3 — Run the server

```bash
llama-server \
  --model "$GGUF_PATH" \
  --host 127.0.0.1 \
  --port 18080 \
  --parallel 1 \
  --ctx-size 96000 \
  --n-gpu-layers 999 \
  --metrics
```

Flag rationale:

- `--parallel 1`: single slot, all KV budget goes to one stream
- `--ctx-size 96000`: ~96 K tokens × 96 KiB ≈ 9 GB KV cache (the entire budget for one slot — vs DMR's 4-way split that gives only 24 K per slot, see Background)
- `--n-gpu-layers 999`: explicit "everything on Metal"; the default does this anyway on Apple Silicon but no harm being explicit
- `--metrics`: exposes Prometheus-style metrics at `/metrics` for benchmarking
- `--host 127.0.0.1`: bind to loopback only (don't expose to LAN)
- `--port 18080`: avoids conflicts with Rapid-MLX (8000) and oMLX (8001)

Server runs in the foreground. Endpoint: `http://localhost:18080/v1` (OpenAI-compatible).

To shut down: Ctrl-C. There is no daemon — kill the process and the model is fully unloaded.

Smoke test:

```bash
curl -X POST "http://localhost:18080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-coder",
    "messages": [{"role": "user", "content": "Write a Python function to reverse a linked list."}]
  }'
```

`llama-server` accepts any value for `model` — it serves whatever GGUF was loaded on the command line.

### C.4 — docker-compose clients

Same hybrid model as Approach A (server lives on the host):

```yaml
services:
  your-app:
    environment:
      - OPENAI_BASE_URL=http://host.docker.internal:18080/v1
      - OPENAI_API_KEY=not-needed
      - OPENAI_MODEL=qwen3-coder
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

### C.5 — Optional: persist as launchd service

Same pattern as section A.3 — write a plist invoking `/opt/homebrew/bin/llama-server` with the flags above. Skip this until C wins the benchmark.

---

## Approach D: oMLX (MLX engine + SSD-backed KV cache)

**Design**: oMLX wraps the same MLX runtime as Rapid-MLX but adds a two-tier KV cache (RAM hot tier + SSD cold tier, persisted as safetensors). For the agentic coding workload — where a multi-K-token system prompt + tool definitions + open-file context get re-sent every turn — this is supposed to drop **cached TTFT from 30-90 s to 1-3 s**. Raw decode tok/s is expected to be in the same ballpark as Rapid-MLX (both are MLX-based); D's edge is on warm-cache TTFT, not throughput.

> **Why D was added after A**: independent benchmarking ([famstack.dev: MLX vs llama.cpp](https://famstack.dev/guides/mlx-vs-gguf-part-2-isolating-variables/)) shows that on Qwen3 30B-A3B, MLX and llama.cpp essentially tie on raw decode (~55-58 tok/s). The 3-4x "MLX is faster" claims compare against Ollama's slow wrapper, not raw llama.cpp. The interesting differentiator for coding agents is **cached TTFT with prefix reuse**, which is exactly what oMLX is built for.

### D.1 — Install oMLX

```bash
brew tap jundot/omlx https://github.com/jundot/omlx
brew install omlx

# Verify
omlx --version
```

### D.2 — Get the MLX-format weights

oMLX expects MLX-format model directories under a `--model-dir`. Two paths to get them:

```bash
# Option 1: Download via the oMLX admin dashboard (after starting the server)
#   open http://localhost:8001/admin → search "Qwen3-Coder-30B-A3B" → Download
# Option 2: Download via huggingface-cli, drop into ~/models
mkdir -p ~/models
huggingface-cli download mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit \
  --local-dir ~/models/Qwen3-Coder-30B-A3B-Instruct-4bit
```

Reuses the same MLX 4-bit weights Rapid-MLX downloads (`mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`). If you've already run Approach A, those weights are at `~/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit`. You can either re-download to `~/models/` (oMLX's expected layout) or symlink the snapshot dir.

### D.3 — Run the server

```bash
omlx serve --model-dir ~/models --port 8001
```

Port 8001 to avoid colliding with Rapid-MLX (8000) if both are configured. oMLX picks the model up by directory name. To run as a persistent background daemon instead:

```bash
brew services start omlx
brew services stop omlx     # to stop later
```

Endpoint: `http://localhost:8001/v1` (OpenAI-compatible).
Admin dashboard: `http://localhost:8001/admin` (browser).

Smoke test:

```bash
curl -X POST "http://localhost:8001/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3-Coder-30B-A3B-Instruct-4bit",
    "messages": [{"role": "user", "content": "Write a Python function to reverse a linked list."}]
  }'
```

The model name is the directory name under `--model-dir`.

### D.4 — How to actually benchmark D's value

The standard `bench.sh` decode/TTFT numbers will _not_ show D's advantage — they measure cold/warm runs of distinct prompts. D's KV cache pays off when the _same prompt prefix_ is replayed across turns. Add a dedicated test:

```text
1. Send a 3K-token system prompt + tool defs + 4K-token user message → measure TTFT (this is "cold" for D's SSD cache).
2. Wait 30 s (long enough that the cache evicts from RAM but stays on SSD).
3. Send the same system prompt + tool defs + a slightly modified 4K-token user message → measure TTFT.
4. Repeat (3) 5 times with varying tail content.
```

Expect D's runs 2-6 to drop dramatically vs A on the same prompt prefix. If they don't, the SSD cache isn't kicking in or your workload doesn't benefit from it.

### D.5 — docker-compose clients

Same hybrid pattern as A:

```yaml
services:
  your-app:
    environment:
      - OPENAI_BASE_URL=http://host.docker.internal:8001/v1
      - OPENAI_API_KEY=not-needed
      - OPENAI_MODEL=Qwen3-Coder-30B-A3B-Instruct-4bit
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

### D.6 — Disk usage warning

The SSD cache grows with prompt-prefix variety. oMLX defaults are sane (LRU eviction) but if you do a lot of varied long-context work, expect 5-50 GB of cache to accumulate. Inspect/clear via the admin dashboard.

---

## Benchmark Methodology (Run After All Three Approaches Installed)

**Goal**: Pick the winner using _our_ hardware and _our_ workload, not vendor self-reports.

### Setup

- One engine running at a time (36 GB RAM = only one ~17 GB model resident at once). Ports for reference: Rapid-MLX :8000, DMR :12434, llama-server :18080.
- Model family: Qwen3-Coder-30B-A3B-Instruct. Approach A = MLX 4-bit; B and C = the _same_ GGUF Q4_K_XL file.
- Cold cache before each run (kill/unload+reload between runs)
- Warm GPU (one throwaway request to discard cold-start overhead)
- Power: plugged in, "High Performance" energy mode, lid open
- Background: close other heavy apps (Chrome with 50 tabs, Slack, Zoom etc.)

### Metrics to collect

| Metric                    | Why it matters                                              | How to measure                                            |
| ------------------------- | ----------------------------------------------------------- | --------------------------------------------------------- |
| **Cold TTFT**             | First-prompt latency (matters for ad-hoc agent invocations) | curl with `time`, fresh process                           |
| **Cached TTFT**           | Repeat-edit latency (Rapid-MLX's headline claim)            | Same prompt twice, measure 2nd                            |
| **Decode tok/s**          | Sustained generation speed (the headline number)            | Long completion, `completion_tokens / wall_clock`         |
| **Tool-call reliability** | Function-calling robustness                                 | 20 prompts requiring function calls; count parse failures |
| **Memory footprint**      | Headroom on 36GB                                            | `vm_stat` + `ps` for server processes                     |
| **Sustained quality**     | Does 4-bit hold up over long sessions?                      | Subjective: 30-min coding session                         |

### Suggested benchmark script (rough)

```bash
#!/usr/bin/env bash
# bench.sh — point at either endpoint
ENDPOINT="${1:-http://localhost:8000/v1}"
MODEL="${2:-qwen3-coder}"

# Decode tok/s on a long completion
time curl -sN -X POST "$ENDPOINT/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\":\"user\",\"content\":\"Write a complete TypeScript implementation of a red-black tree with insert, delete, find, and in-order traversal. Include tests.\"}],
    \"max_tokens\": 2000,
    \"stream\": true
  }" | tee /tmp/bench-out.txt
# Parse tokens from streaming response, divide by wall time
```

Run 3 trials each, take median. Also test with [linusvwe/MLXBench](https://github.com/linusvwe/MLXBench) if it gains Rapid-MLX support (currently covers Ollama / vllm-mlx / DMR).

### Decision criteria (3-way)

Apply in order — the first matching rule decides the winner.

1. **Cached-TTFT question (D's specific value prop).** Run the prefix-replay test (section D.4) on D, then on C and (optionally) A.
   - If D's cached TTFT is <5 s and the others are >15 s, **Approach D wins** — for an agent workflow, that gap dominates everything else.
   - If everyone has comparable cached TTFT, fall through to (2).
2. **Engine question.** Compare the best MLX score (max of A, D) vs C on decode tok/s.
   - If MLX wins by >20 %, the MLX-side winner from (1) takes it.
   - If llama.cpp (C) wins by >20 %, **Approach C wins.**
   - Otherwise, both engines are competitive; fall through to (3).
3. **Tie-breakers, applied in order:**
   - Tool-call reliability: pick the one with fewer parse failures
   - Cold TTFT: pick the lower one
   - RSS at idle: pick the smaller one if everything else is equal

### Recorded results (Mon 2026-05-11, M3 Pro 36 GB)

Model: Qwen3-Coder-30B-A3B-Instruct (MLX 4-bit for A and D, GGUF Q4_K_XL Unsloth for C — same base weights). 5 decode trials × 1000 max-tokens, 5 TTFT trials, 10 tool-call trials.

**Standard bench:**

| Metric                 | Rapid-MLX | llama-server | oMLX  |
| ---------------------- | --------- | ------------ | ----- |
| Decode tok/s           | **51.2**  | 46.6         | 50.4  |
| TTFT (s, short prompt) | 0.087     | **0.082**    | 0.300 |
| Tool-call success      | 10/10     | 10/10        | 10/10 |
| RSS (MB, working set)  | **326**   | 25,809       | 2,876 |

All three are within ~10 % on decode — the famstack.dev prediction held (MLX ≈ llama.cpp on Qwen3 30B-A3B). RSS comparison reflects allocation strategy, not absolute memory cost: llama-server pre-allocates the 96 K KV cache (~9 GB) and loads weights non-mmap; MLX engines mmap weights + lazy-alloc KV per request, so `ps` only sees the working set.

**Prefix-replay (6 K-token shared prefix, 6 trials, 30 s sleep between):**

| Engine           | Trial 0 (cold) | T1    | T2    | T3   | T4   | T5   | Warm avg   | Speedup                              |
| ---------------- | -------------- | ----- | ----- | ---- | ---- | ---- | ---------- | ------------------------------------ |
| **llama-server** | 16.24 s        | 0.70  | 0.72  | 0.74 | 0.69 | 0.67 | **0.70 s** | 23×                                  |
| **Rapid-MLX**    | 13.46 s        | 1.00  | 0.93  | 1.00 | 0.94 | 0.98 | 0.97 s     | 14×                                  |
| **oMLX**         | 11.87 s        | 11.91 | 11.92 | 1.23 | 1.35 | 1.32 | 5.55 s\*   | only 9× — and only after 3 cold runs |

_\* oMLX's average is inflated because trials 1-2 stayed cold. After the cache engages at trial 3, sustained warm TTFT is ~1.3 s._

**Findings:**

1. **All three engines have effective prefix caching.** The "oMLX is uniquely good at this" framing was wrong. llama.cpp's RAM prompt cache (8 GB ring buffer per PR 16391) and Rapid-MLX's RAM prompt cache both hit instantly on trial 1.
2. **oMLX has a 3-cold-run warm-up policy.** Trials 0, 1, 2 all paid full ~12 s prefill cost; only trial 3 saw the cache. Most likely cause is a block-level write-threshold heuristic (the startup logs show `block_size=256 tokens, max_blocks=100000` paged-SSD cache — likely promotes blocks to SSD only after N hits to avoid SSD write amplification). The effect on real-world use: you pay the cold-prefill cost not just on session 1 but for ~3 sessions of every new prefix.
3. **llama-server has the lowest warm TTFT** (0.70 s) but loses on RSS.
4. **oMLX's SSD durability is real** (we saw 26 cache files survive an oMLX restart between runs) but this benchmark didn't exercise it — 30 s of idle doesn't evict the RAM caches in any of the three engines. SSD persistence only matters across restarts or under heavy memory pressure, neither of which a "load it once, use it all day" desktop hits.

**Decision:** Rapid-MLX wins on the all-around criteria (highest decode + lowest RSS + instant cache + simplest setup). llama-server is the second choice if you need >32 K of _actively used_ context per turn. oMLX is fine technology but its caching policy is a poor fit for short-session iteration.

---

## Background: Why Other Options Were Rejected

### Docker Model Runner (DMR) — initially Approach B, dropped

DMR runs llama.cpp as a Docker-managed host-side daemon, with an OpenAI-compatible API on `http://localhost:12434/engines/v1`. Strictly inferior to Approach C (raw `llama-server`) for solo dev on Apple Silicon, for the following reasons:

1. **`n_slots = 4` was an upstream llama.cpp bug, fixed before our bench ran.** Initial investigation here concluded DMR hardcoded `n_slots = 4` because `docker model configure --help` doesn't expose a `--parallel`/`--n-slots` knob (only `--context-size`, `--keep-alive`, `--mode`, plus sampling/threading/GPU flags — see [Configuration options](https://docs.docker.com/ai/model-runner/configuration/)). That was the wrong diagnosis. The actual root cause is [llama.cpp #17989](https://github.com/ggml-org/llama.cpp/issues/17989) (opened 2025-12-13, closed via [PR #17997](https://github.com/ggml-org/llama.cpp/pull/17997)): llama-server itself initialized 4 slots even when `--parallel 1` was passed, contradicting its own docs. Both engines we tested are well past the fix — Homebrew `llama.cpp` is build b9090, DMR was bumped to b9102 on 2026-05-11 (DMR's recent cadence is weekly bumps from `ghcr.io/ggml-org/llama.cpp` images). So this bug is not currently a reason to prefer one over the other.
2. **DMR still doesn't expose `--parallel` in `docker model configure`**, but the escape hatch is `runtime_flags: ["--parallel", "1"]` in compose ([DMR #108](https://github.com/docker/model-runner/issues/108) shows a user passing it through; logs confirm the flag reaches the llama-server invocation). On Linux this is flaky per [DMR #726](https://github.com/docker/model-runner/issues/726). The practical friction: any unusual llama.cpp flag means dropping into `runtime_flags:` rather than a first-class CLI argument.
3. **Default `--context-size = 128 K` is unsafe on this hardware.** Empirically, out of the box DMR allocates enough KV cache to exceed Apple's ~27 GB Metal wired-memory cap. Every request 500s with `kIOGPUCommandBufferCallbackErrorOutOfMemory` (visible in `docker model logs`) until you run `docker model configure --context-size 24576`. (The previous version of this section attributed this to `4 × context-size` multiplication; with `kv_unified = true` that math is probably wrong — single 128 K × 96 KiB ≈ 12 GB KV plus the ~17 GB weights plus Metal overhead is itself enough to cross the cap. Either way, the OOM is real.)
4. **DMR's `vllm` backend doesn't apply here.** vLLM in DMR requires safetensors/MLX-format models. Docker Hub publishes Qwen3-Coder only as GGUF, which DMR routes to llama.cpp. The original "DMR + vllm-metal" pitch isn't available for this model.

**Why our bench didn't hit the slot bug:** both engines are post-fix builds (Homebrew b9090, DMR b9014 at bench time, b9102 same-day). Additionally, the bench is single-user — even with the pre-fix behavior (`n_parallel = 4` cosmetic + `kv_unified = true`), the working-set RSS would look the same because the 4 slots share one KV pool. The bug primarily affects multi-concurrent-request throughput, not single-stream benchmarks. Either way, llama-server's startup banner (which would have shown `n_slots = N`) isn't captured in our bench logs — we'd only have known by logging stderr.

The remaining argument for DMR — `model-runner.docker.internal` DNS for sibling docker-compose services — only matters if you have other containers that need to hit the LLM. For a solo dev setup, Approach C still wins on configuration ergonomics (any llama.cpp flag is just a CLI argument, not a `runtime_flags:` array) and absence of the Docker Desktop daemon, but the gap is smaller than the original "hardcoded 4 slots" framing suggested.

(`dmr-setup.sh` and `bench.sh --only-dmr` remain in the repo for anyone who does want to compare — they're just not part of the recommended bench.)

### DS4 (antirez's DeepSeek V4 Flash engine)

Specialized C+Metal engine, philosophy match. **Rejected**: Requires 128GB+ RAM minimum.

### Qwen 2.5 Coder 14B

Smaller, would fit easily. **Rejected**: Tool calling unreliable; lacks reliable thinking-mode support in current client tooling.

### Devstral Small 2 (24B)

Strong agentic coder, 68% SWE-bench Verified, Apache 2.0. Solid second fallback if Qwen3-Coder underperforms in our benchmark.

### GPT-OSS 20B

OpenAI's open model, native MXFP4, ~12GB. Decent but loses to Qwen3-Coder on multilingual code generation and reasoning depth.

### Pure MLX-LM server (no Rapid-MLX wrapper)

Works but MLX team explicitly says "not recommended for production" (basic security only). Tool calling support is weaker than Rapid-MLX's specialized parsers.

### vllm-mlx (independent project, not what DMR uses)

Has published benchmarks but its single-user perf is _worse_ than Ollama on M4 Pro DeepSeek V3. Wins big at concurrency, irrelevant for single dev.

### Plain Docker container (any engine)

**Rejected**: Docker on macOS runs in a Linux VM with no Metal GPU passthrough. CPU-only fallback → 5-6x slower, unusable.

### Frontier open models (GLM-5, DeepSeek V4, Qwen 3.6-Plus, Kimi K2.6)

All require 200GB+ RAM.

---

## M3 vs M4 Performance Context

Memory bandwidth (the LLM inference bottleneck):

- **M3 Pro: ~150 GB/s** (your hardware)
- M3 Max: 400 GB/s
- M4 Pro: 273 GB/s
- M4 Max: 546 GB/s

Critical insight: M3 Max outperforms M4 Pro for token generation because bandwidth dominates compute. Your M3 Pro is the weakest tier here — expect roughly 50-65% of M4 Max throughput on the same model.

---

## Repository layout

```text
agent_hardess/
├── README.md           ← this file (decision, methodology, results)
├── benchmark/          ← scripts and results used to pick the winner
│   ├── README.md       ← how to reproduce the bench
│   ├── bench.sh
│   ├── {rapid-mlx,llama-server,omlx,dmr}-setup.sh
│   └── results/
│       └── bench-results-*.txt
└── serve/              ← daily-use launcher for the winner (Rapid-MLX)
    ├── README.md       ← quick start
    ├── start.sh
    └── com.rapid-mlx.server.plist
```

## Daily use

The winner is **Rapid-MLX**. See [`serve/README.md`](serve/README.md) for the quick start and instructions for running it as a launchd background daemon.

## Reproducing the benchmark

See [`benchmark/README.md`](benchmark/README.md). All four candidates can be re-tested independently:

```bash
cd benchmark/
./rapid-mlx-setup.sh        # or llama-server-setup.sh / omlx-setup.sh / dmr-setup.sh
./bench.sh --only-rapid     # in another terminal
./bench.sh --prefix-replay --endpoint http://localhost:8000/v1 --model qwen3-coder-30b
```

Past results from the run that produced the decision are in `benchmark/results/`.

---

## Sources

### Rapid-MLX (Approach A)

- [Rapid-MLX GitHub Repository](https://github.com/raullenchai/Rapid-MLX)
- [Rapid-MLX for Cline on Apple Silicon (2-4x faster discussion)](https://github.com/cline/cline/discussions/9940)

### Docker Model Runner (DMR — considered, dropped — see Background)

- [Docker Model Runner Documentation](https://docs.docker.com/ai/model-runner/)
- [Docker Model Runner GA Announcement](https://www.docker.com/blog/announcing-docker-model-runner-ga/)
- [Docker Model Runner Configuration Options](https://docs.docker.com/ai/model-runner/configuration/) — full documented flag list (no `--parallel`/`--n-slots`)
- [llama.cpp #17989 — `--parallel 1` initializes 4 slots, while docs say default is 1](https://github.com/ggml-org/llama.cpp/issues/17989) — upstream bug, root cause of the "DMR hardcoded n_slots = 4" misdiagnosis
- [llama.cpp PR #17997 — fix for #17989](https://github.com/ggml-org/llama.cpp/pull/17997)
- [DMR #108 — Parallel requests against same model](https://github.com/docker/model-runner/issues/108) — confirms `runtime_flags: ["--parallel", N]` reaches the llama-server invocation
- [DMR #726 — Runtime_flags are ignored on Linux in certain cases](https://github.com/docker/model-runner/issues/726)

### Raw `llama-server` (Approach C)

- [llama.cpp GitHub Repository (ggml-org)](https://github.com/ggml-org/llama.cpp)
- [llama-server documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- [Unsloth Qwen3-Coder GGUF](https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF)
- [Homebrew formula: llama.cpp](https://formulae.brew.sh/formula/llama.cpp)

### Benchmark methodology references

- [MLXBench (Ollama vs vllm-mlx vs DMR benchmark tool)](https://github.com/linusvwe/MLXBench)
- [Two Paths to vLLM on Apple Silicon: vllm-metal vs vllm-mlx](https://blog.labs.purplemaia.org/two-paths-to-vllm-on-apple-silicon-vllm-metal-vs-vllm-mlx/)
- [2026 Mac Inference Framework Benchmarks (MACGPU)](https://macgpu.com/en/blog/2026-mac-inference-framework-vllm-mlx-ollama-llamacpp-benchmark.html)
- [MLX vs Ollama on Apple Silicon — Real Benchmarks 2026](https://willitrunai.com/blog/mlx-vs-ollama-apple-silicon-benchmarks)
- [Comparative Study of MLX/MLC-LLM/Ollama/llama.cpp (ArXiv)](https://arxiv.org/pdf/2511.05502)

### Qwen3-Coder-30B-A3B (the model)

- [Qwen3-Coder-30B-A3B-Instruct on Hugging Face](https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct)
- [Qwen3-Coder MLX 4-bit (lmstudio-community)](https://huggingface.co/lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-4bit)
- [Qwen3-Coder on Ollama Library](https://ollama.com/library/qwen3-coder:30b)
- [Qwen3-Coder How to Run Locally (Unsloth)](https://unsloth.ai/docs/models/tutorials/qwen3-coder-how-to-run-locally)
- [Qwen3-Coder Hardware Requirements & Performance](https://www.arsturn.com/blog/running-qwen3-coder-30b-at-full-context-memory-requirements-performance-tips)
- [Qwen3-Coder GitHub (QwenLM)](https://github.com/QwenLM/Qwen3-Coder)

### Fallback engine: Ollama 0.19+ MLX

- [Ollama is Now Powered by MLX on Apple Silicon (official blog)](https://ollama.com/blog/mlx)
- [Ollama 0.19 MLX Review — 2x Faster on Apple Silicon](https://andrew.ooo/posts/ollama-mlx-apple-silicon-review/)

### Background research

- [DS4 by antirez: Dedicated Inference Engine for DeepSeek V4 Flash](https://pasqualepillitteri.it/en/news/2253/ds4-antirez-deepseek-v4-flash-inference-engine)
- [DS4 GitHub Repository](https://github.com/antirez/ds4)
- [Apple Silicon GPUs, Docker and Ollama: Pick two (Chariot Solutions)](https://chariotsolutions.com/blog/post/apple-silicon-gpus-docker-and-ollama-pick-two/)
- [Best Open-Source LLMs for Agentic Coding 2026](https://www.mindstudio.ai/blog/best-open-source-llms-agentic-coding-2026)
- [Best Local Coding LLMs for Apple Silicon 24GB (April 2026)](https://willitrunai.com/blog/best-local-coding-llms-apple-silicon-24gb)
- [Mac M1 vs M2 vs M3 vs M4 for Running LLMs — Real Tests](https://mljourney.com/mac-m1-vs-m2-vs-m3-vs-m4-for-running-llms-real-tests/)
- [Devstral Small 2 Guide (fallback model)](https://www.aimadetools.com/blog/devstral-small-2-guide/)
- [LLM Coding Benchmark May 2026](https://akitaonrails.com/en/2026/04/24/llm-benchmarks-parte-3-deepseek-kimi-mimo/)
