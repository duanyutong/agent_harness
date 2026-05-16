# Benchmarking the Local-LLM Candidates

Reproducible head-to-head benchmark used to select the engine. See [`../README.md`](../README.md) for the full write-up and decision.

## Engines under test

| Engine       | Setup script            | Port  | Notes                                                                                                  |
| ------------ | ----------------------- | ----- | ------------------------------------------------------------------------------------------------------ |
| Rapid-MLX    | `rapid-mlx-setup.sh`    | 8000  | MLX runtime — the selected engine                                                                      |
| llama-server | `llama-server-setup.sh` | 18080 | llama.cpp with full configuration control (1 slot × 96 K context)                                      |
| oMLX         | `omlx-setup.sh`         | 8001  | MLX + SSD-backed 2-tier KV cache                                                                       |
| DMR          | `dmr-setup.sh`          | 12434 | Docker Model Runner — **considered, rejected** (see README §Background); kept here for reproducibility |

## One-time Preparation

```bash
chmod +x *.sh
```

Before each benchmark round: plug in, use "High Performance" energy mode, and close Chrome, Slack, and Zoom. Run one engine at a time; 36 GB RAM permits only one approximately 17 GB model to remain resident.

## Standard Benchmark (decode tok/s, TTFT, tool-call reliability, RSS)

```bash
./bench.sh --only-rapid                          # Rapid-MLX (port 8000)
./bench.sh --only-llama                          # llama-server (port 18080)
./bench.sh --only-omlx                           # oMLX (port 8001)
./bench.sh --only-dmr                            # DMR (port 12434) — for reference
```

Defaults: 3 trials × 500 max-tokens, 3 TTFT trials, 3 tool-call trials → ~1 min/engine.

For a more reliable median: `--trials 5 --max-tokens 1000 --ttft-trials 5 --tool-trials 10` → ~3 min/engine.

For an approximate check: `--quick` → ~25 s/engine.

## Prefix-replay test (does the engine cache repeated prefixes?)

```bash
./bench.sh --prefix-replay --endpoint <url> --model <name>
```

Sends a stable ~6 K-token prefix with varying tails across 6 trials (1 cold + 5 warm, 30 s sleep between). Reports cold/warm TTFT and a verdict.

For each engine:

```bash
./bench.sh --prefix-replay --endpoint http://localhost:8000/v1 --model qwen3-coder-30b           # Rapid-MLX
./bench.sh --prefix-replay --endpoint http://localhost:18080/v1 --model qwen3-coder               # llama-server
./bench.sh --prefix-replay --endpoint http://localhost:8001/v1 --model Qwen3-Coder-30B-A3B-Instruct-4bit  # oMLX
```

Useful for measuring the cache durability of each engine independent of decode speed.

## Output

Each run writes `results/bench-results-YYYYMMDD-HHMMSS.txt`. Prior runs are stored in [`results/`](results/), including both historical runs before bug fixes and the final clean numbers used in the decision.

## Re-running from a clean slate

If you want to invalidate any persisted caches between runs (e.g., to test cold prefill on oMLX):

```bash
# oMLX SSD cache
rm -rf ~/.omlx/cache

# HuggingFace download cache (DON'T do this — it'll force a 17 GB re-download)
# rm -rf ~/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/

# DMR's model
docker model rm ai/qwen3-coder:30B-A3B-UD-Q4_K_XL
```
