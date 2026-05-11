#!/usr/bin/env bash
# =============================================================================
# Approach C: Raw `llama-server` (llama.cpp at full power) — setup script
#
# WHAT THIS SCRIPT DOES (idempotent):
#   1. Installs llama.cpp via Homebrew if not present (`brew install llama.cpp`).
#   2. Locates a Qwen3-Coder GGUF on disk. Tries in order:
#      a. ~/models/qwen3-coder/Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf
#      b. The DMR-cached file in ~/.docker/models/bundles/<sha>/model/model.gguf
#         (if you ran dmr-setup.sh first and didn't delete the model).
#   3. Launches llama-server in the foreground on port 18080.
#
# THIS IS A SERVER — Ctrl-C kills it. There is no daemon. No `keep-alive`.
# Killing the process fully unloads the model (frees ~17 GB of RAM).
#
# CONFIG NOTES — context-size and parallel:
#   Qwen3-Coder-30B-A3B GGUF has aggressive GQA (4 KV heads, 48 layers,
#   head_dim 128 → ~96 KiB of KV cache per token). With --parallel 1 and
#   --ctx-size 96000:
#       1 slot × 96 K × 96 KiB ≈ 8.8 GB KV cache
#     + ~16.5 GB weights
#     + ~0.7 GB compute buffers
#     ≈ 26 GB total → fits within Apple's ~27 GB Metal wired-memory cap on
#     M3 Pro 36 GB, with ~1 GB margin.
#
#   This is the comparison point for Approach B (DMR), which is forced to
#   4 slots × 24 K context due to a missing CLI knob. Same engine, same
#   GGUF, completely different runtime config.
#
# TO CHANGE CONFIG:
#   Edit CONTEXT_SIZE / PORT below and re-run.
#
# TO SHUT DOWN:
#   Ctrl-C in this terminal. That's it.
#
# DEBUGGING:
#   curl http://localhost:18080/health        # liveness
#   curl http://localhost:18080/metrics       # Prometheus-style metrics
#   curl http://localhost:18080/v1/models     # OpenAI models endpoint
#
# REQUIRES: macOS, Apple Silicon, Homebrew, ~17 GB free RAM, GGUF on disk.
# =============================================================================
set -euo pipefail

PORT=18080
CONTEXT_SIZE=96000
HOST=127.0.0.1
DMR_MODEL_TAG="ai/qwen3-coder:30B-A3B-UD-Q4_K_XL"

echo "=== Approach C: Raw llama-server (llama.cpp at full power) ==="
echo ""

# ---- 1. Install llama.cpp ---------------------------------------------------
echo "[1/4] Checking llama-server..."
if command -v llama-server &>/dev/null; then
  echo "  Already installed: $(llama-server --version 2>&1 | head -1 || echo 'version unknown')"
else
  echo "  Installing via Homebrew..."
  brew install llama.cpp
fi
echo ""

# ---- 2. Locate the GGUF -----------------------------------------------------
echo "[2/4] Locating GGUF..."
GGUF_PATH=""

# Try manual download path first
MANUAL_PATH="$HOME/models/qwen3-coder/Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf"
if [ -f "$MANUAL_PATH" ]; then
  GGUF_PATH="$MANUAL_PATH"
  echo "  Found at manual path: $GGUF_PATH"
fi

# Fall back to DMR-cached bundle.
# Wrap in `|| true` so a missing model / failed pipeline doesn't trip set -e.
if [ -z "$GGUF_PATH" ] && command -v docker &>/dev/null; then
  DMR_HASH=$(
    {
      docker model inspect "$DMR_MODEL_TAG" 2>/dev/null \
        | python3 -c "import sys, json
try:
    d = json.load(sys.stdin)
    print(d['id'].replace('sha256:',''))
except Exception:
    pass
" 2>/dev/null
    } || true
  )
  if [ -n "${DMR_HASH}" ]; then
    CANDIDATE="$HOME/.docker/models/bundles/sha256/$DMR_HASH/model/model.gguf"
    if [ -f "$CANDIDATE" ]; then
      GGUF_PATH="$CANDIDATE"
      echo "  Found in DMR cache: $GGUF_PATH"
    fi
  fi
fi

if [ -z "$GGUF_PATH" ]; then
  echo "  ERROR: GGUF not found in either location."
  echo ""
  echo "  Choose one of these to obtain it:"
  echo ""
  echo "  Option 1 — pull via DMR (requires Docker Desktop):"
  echo "    docker model pull $DMR_MODEL_TAG"
  echo ""
  echo "  Option 2 — download directly from HuggingFace (use 'hf' or 'huggingface-cli'):"
  echo "    mkdir -p ~/models/qwen3-coder"
  echo "    hf download unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF \\"
  echo "      Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf \\"
  echo "      --local-dir ~/models/qwen3-coder"
  echo ""
  echo "  Then re-run this script."
  exit 1
fi
GGUF_SIZE=$(du -h "$GGUF_PATH" | awk '{print $1}')
echo "  Size: $GGUF_SIZE"
echo ""

# ---- 3. Pre-flight port check -----------------------------------------------
echo "[3/4] Checking port ${PORT} is free..."
if lsof -nP -iTCP:${PORT} -sTCP:LISTEN &>/dev/null; then
  echo "  ERROR: Port ${PORT} is already in use:"
  lsof -nP -iTCP:${PORT} -sTCP:LISTEN
  echo "  Stop the conflicting process or change PORT in this script."
  exit 1
fi
echo "  OK"
echo ""

# ---- 4. Launch the server ---------------------------------------------------
echo "[4/4] Starting llama-server (foreground)..."
echo "  Endpoint:     http://${HOST}:${PORT}/v1   (OpenAI-compatible)"
echo "  Health:       http://${HOST}:${PORT}/health"
echo "  Metrics:      http://${HOST}:${PORT}/metrics"
echo "  Model:        ${GGUF_PATH}"
echo "  Slots:        1   (--parallel 1)"
echo "  Context:      ${CONTEXT_SIZE} tokens"
KV_GIB=$(python3 -c "print(round(${CONTEXT_SIZE} * 96 / 1024 / 1024, 2))")
echo "  KV cache:     ~${KV_GIB} GiB  (${CONTEXT_SIZE} tokens × 96 KiB)"
echo ""
echo "  To shut down: Ctrl-C."
echo "  To benchmark: in another terminal, ./bench.sh --only-llama"
echo ""

exec llama-server \
  --model "$GGUF_PATH" \
  --host "$HOST" \
  --port "$PORT" \
  --parallel 1 \
  --ctx-size "$CONTEXT_SIZE" \
  --n-gpu-layers 999 \
  --metrics
