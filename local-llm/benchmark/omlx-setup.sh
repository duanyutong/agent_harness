#!/usr/bin/env bash
# =============================================================================
# Approach D: oMLX (MLX engine + SSD-backed KV cache) - setup script
#
# WHAT THIS SCRIPT DOES (idempotent):
#   1. Installs oMLX via Homebrew tap (`jundot/omlx`).
#   2. Downloads the MLX 4-bit weights for Qwen3-Coder-30B-A3B-Instruct
#      from Hugging Face into ~/models/Qwen3-Coder-30B-A3B-Instruct-4bit/
#      (skipped if already present).
#   3. Launches `omlx serve` in the foreground on port 8001.
#
# WHY 8001 (not 8000): Rapid-MLX (Approach A) defaults to 8000. We select a
# non-conflicting port so a partly configured Rapid-MLX environment does not
# conflict, and so Zed configurations for both can coexist.
#
# WHY oMLX EXISTS IN THIS BENCH (and not just A):
#   oMLX wraps the same MLX runtime as Rapid-MLX but adds a two-tier KV cache:
#   RAM hot tier + SSD cold tier (persisted as safetensors). For agent
#   workflows where a multi-K-token system prompt, tool definitions, and
#   open-file context are resent every turn, this reduces cached TTFT from
#   30-90 s to 1-3 s. Raw decode tok/s is expected to be in Rapid-MLX's range;
#   the SSD cache is the differentiator. Run the prefix-replay test to
#   exercise it: `./bench.sh --prefix-replay --endpoint http://localhost:8001/v1`.
#
# CONFIG NOTES:
#   - PORT=8001 — pick a different port to coexist with Rapid-MLX on :8000.
#   - MODEL_DIR=~/models — oMLX scans subdirectories here for MLX models.
#   - The model name in API calls = the directory name on disk.
#
# TO CHANGE THE MODEL:
#   Place another MLX-format model directory under MODEL_DIR. oMLX serves the
#   subdirectories it finds. List them with: `omlx list` (or via the
#   admin dashboard at http://localhost:${PORT}/admin).
#
# TO SHUT DOWN:
#   - Foreground (this script): Ctrl-C.
#   - Background daemon (if you ran `brew services start omlx`):
#       brew services stop omlx
#
# TO DELETE DOWNLOADED WEIGHTS (frees ~17 GB):
#   rm -rf ~/models/Qwen3-Coder-30B-A3B-Instruct-4bit
#   # (and remove the SSD KV cache if you want to fully reset:)
#   rm -rf ~/Library/Application\ Support/omlx/cache
#
# DEBUGGING:
#   omlx --version
#   curl http://localhost:8001/v1/models    # list models served
#   open http://localhost:8001/admin         # GUI for cache + model management
#
# REQUIRES: macOS, Apple Silicon, Homebrew, ~17 GB free disk + ~17 GB free
#           RAM, plus headroom on disk for the SSD KV cache (5-50 GB depending
#           on session variety).
# =============================================================================
set -euo pipefail

PORT=8001
MODEL_NAME="Qwen3-Coder-30B-A3B-Instruct-4bit"
MODEL_REPO="mlx-community/${MODEL_NAME}"
MODEL_DIR="$HOME/models"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

echo "=== Approach D: oMLX (MLX engine + SSD-backed KV cache) ==="
echo ""

# ---- 1. Install oMLX --------------------------------------------------------
echo "[1/4] Checking oMLX..."
if command -v omlx &>/dev/null; then
  echo "  Already installed and linked: $(omlx --version 2>&1 | head -1 || echo 'version unknown')"
else
  # If brew has it but it is not linked (common after a prior install stopped
  # mid-build, or with parallel brew runs), link it. Otherwise, install it.
  if brew list --formula --full-name 2>/dev/null | grep -q '^jundot/omlx/omlx$'; then
    echo "  Found installed but unlinked. Running brew link..."
    brew link --overwrite jundot/omlx/omlx
  else
    echo "  Tapping jundot/omlx and installing (this can take 5-15 min for native wheels)..."
    brew tap jundot/omlx https://github.com/jundot/omlx 2>&1 | tail -3
    brew install omlx
    brew link --overwrite jundot/omlx/omlx 2>/dev/null || true
  fi

  if ! command -v omlx &>/dev/null; then
    echo "  ERROR: omlx still not on PATH after install + link."
    echo "  If a brew install is still running in another terminal, wait for it"
    echo "  to finish, then run:  brew link --overwrite jundot/omlx/omlx"
    exit 1
  fi
fi
echo ""

# ---- 2. Find a HuggingFace CLI ----------------------------------------------
# The HF CLI was renamed from `huggingface-cli` to `hf` in 2025. Either works
# for downloading; the syntax is identical for `download REPO --local-dir DIR`.
echo "[2/4] Checking HuggingFace CLI..."
HF_CLI=""
if command -v hf &>/dev/null; then
  HF_CLI="hf"
elif command -v huggingface-cli &>/dev/null; then
  HF_CLI="huggingface-cli"
else
  echo "  ERROR: neither 'hf' nor 'huggingface-cli' on PATH."
  echo "  Install one of:"
  echo "    pip install -U 'huggingface_hub[cli]'   # provides 'hf' (new) and 'huggingface-cli' (legacy)"
  echo "    brew install huggingface-cli            # legacy CLI only"
  exit 1
fi
echo "  Using: ${HF_CLI}  ($(${HF_CLI} --version 2>&1 | head -1))"
echo ""

# ---- 3. Download the MLX weights --------------------------------------------
echo "[3/4] Ensuring MLX weights at ${MODEL_PATH}..."
if [ -f "$MODEL_PATH/config.json" ] && [ -d "$MODEL_PATH" ]; then
  SIZE=$(du -sh "$MODEL_PATH" 2>/dev/null | awk '{print $1}')
  echo "  Already present (${SIZE}). Skipping download."
else
  mkdir -p "$MODEL_DIR"
  echo "  Downloading ${MODEL_REPO} (~17 GB) to ${MODEL_PATH} via ${HF_CLI}..."
  "$HF_CLI" download "$MODEL_REPO" --local-dir "$MODEL_PATH"
  echo "  Done. Size: $(du -sh "$MODEL_PATH" | awk '{print $1}')"
fi
echo ""

# ---- 4. Pre-flight port check + launch --------------------------------------
echo "[4/4] Checking port ${PORT} is free..."
if lsof -nP -iTCP:${PORT} -sTCP:LISTEN &>/dev/null; then
  echo "  ERROR: Port ${PORT} is already in use:"
  lsof -nP -iTCP:${PORT} -sTCP:LISTEN
  echo "  Stop the conflicting process. If it's a previous oMLX daemon,"
  echo "  run: brew services stop omlx"
  exit 1
fi
echo "  OK"
echo ""

echo "Starting oMLX (foreground)..."
echo "  Endpoint: http://localhost:${PORT}/v1   (OpenAI-compatible)"
echo "  Admin:    http://localhost:${PORT}/admin"
echo "  Model:    ${MODEL_NAME}   (use this exact string as 'model' in API calls)"
echo ""
echo "  To shut down: Ctrl-C."
echo "  To benchmark:"
echo "    in another terminal: ./bench.sh --only-omlx"
echo "    prefix-replay test:  ./bench.sh --prefix-replay --endpoint http://localhost:${PORT}/v1 --model ${MODEL_NAME}"
echo ""

exec omlx serve --model-dir "$MODEL_DIR" --port "$PORT"
