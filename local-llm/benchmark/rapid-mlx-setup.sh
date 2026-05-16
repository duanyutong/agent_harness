#!/usr/bin/env bash
# =============================================================================
# Approach A: Rapid-MLX (native Metal, host-side daemon) - setup script
#
# WHAT THIS SCRIPT DOES:
#   1. Installs rapid-mlx via Homebrew (idempotent; skips if already present).
#   2. Runs `rapid-mlx doctor` for a quick environment health check.
#   3. Starts `rapid-mlx serve` in the foreground on port 8000. On first run,
#      this downloads ~17 GB of MLX 4-bit weights from Hugging Face into
#      `~/.cache/huggingface/hub/`. Subsequent runs use the cache.
#
# CRITICAL: ALIAS DISTINCTION.
#   The Rapid-MLX alias `qwen3-coder` (no suffix) routes to
#   `lmstudio-community/Qwen3-Coder-Next-MLX-4bit` — a *different*, much larger
#   MoE model that requires a ~40 GB download. The 30B model that matches DMR
#   (Approach B / C) is exposed as `qwen3-coder-30b` and resolves to
#   `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` (~17 GB on disk).
#   Verify with `rapid-mlx info <alias>` before changing MODEL below.
#
# TO CHANGE THE MODEL:
#   Edit MODEL= below and re-run. First request after a model swap will
#   re-download from HF.
#
# TO SHUT DOWN:
#   Ctrl-C in this terminal. Server is foreground; killing the process fully
#   unloads the model.
#
# TO DELETE DOWNLOADED WEIGHTS (frees ~17 GB):
#   rm -rf ~/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit
#   rm -rf ~/.cache/huggingface/hub/.locks/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit
#
# DEBUGGING:
#   rapid-mlx doctor          # Metal / Python environment check
#   rapid-mlx info <alias>    # Show the Hugging Face repository for an alias
#   rapid-mlx models          # List all aliases and suffix tier indicators
#
# REQUIRES: macOS, Apple Silicon, Homebrew, ~17 GB free disk + ~17 GB free RAM.
# =============================================================================
set -euo pipefail

PORT=8000
MODEL="qwen3-coder-30b"   # -> mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit (~17 GB).
                          # Do NOT use unsuffixed "qwen3-coder"; it is the 80B Next model (40+ GB).
ENDPOINT="http://localhost:${PORT}/v1"

echo "=== Approach A: Rapid-MLX (native Metal) ==="
echo ""

# ---- 1. Install Rapid-MLX ---------------------------------------------------
echo "[1/3] Installing Rapid-MLX via Homebrew..."
if command -v rapid-mlx &>/dev/null; then
  echo "  Already installed: $(rapid-mlx --version 2>/dev/null || echo 'version unknown')"
else
  brew install raullenchai/rapid-mlx/rapid-mlx
fi
echo ""

# ---- 2. Doctor check --------------------------------------------------------
echo "[2/3] Running rapid-mlx doctor..."
rapid-mlx doctor || true   # non-fatal; surface warnings
echo ""
echo "Resolved alias for '${MODEL}':"
rapid-mlx info "${MODEL}" 2>&1 | head -3 || true
echo ""

# ---- 3. Start inference server ----------------------------------------------
echo "[3/3] Starting Rapid-MLX server on port ${PORT}..."
echo "  Endpoint (OpenAI-compatible): ${ENDPOINT}"
echo "  First run downloads ~17 GB from Hugging Face into ~/.cache/huggingface/."
echo "  Server runs in foreground. Open a new terminal for the smoke test."
echo "  To stop: Ctrl-C in this terminal."
echo ""
rapid-mlx serve "${MODEL}" --prefill-step-size 8192 --port "${PORT}"
