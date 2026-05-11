#!/usr/bin/env bash
# =============================================================================
# Approach B: Docker Model Runner (llama.cpp backend) — setup script
#
# WHAT THIS SCRIPT DOES (idempotent — safe to re-run):
#   1. Verifies Docker + DMR are running.
#   2. Pulls the Qwen3-Coder GGUF (~17 GB) if not already present.
#   3. Sets per-model runtime config (context-size, keep-alive).
#   4. Verifies the OpenAI-compatible API at http://localhost:12434/engines/v1
#
# THIS IS NOT A SERVER. The DMR daemon (managed by Docker Desktop) already
# serves the API on port 12434 the moment Model Runner is enabled. The model
# itself loads into RAM lazily on the first /chat/completions request, and
# unloads after `keep-alive` of idleness. This script just configures it.
#
# CONFIG NOTES — context-size and slots:
#   The Qwen3-Coder-30B-A3B GGUF has aggressive GQA (4 KV heads, 48 layers,
#   head_dim 128 → ~96 KiB of KV cache per token). We pin one slot
#   (`--parallel 1`) and budget a single 96 K-token KV cache (~9 GB), matching
#   the raw-llama-server bench in Approach C exactly.
#
#   `docker model configure` doesn't expose `--parallel` as a first-class flag,
#   but it does pass arbitrary llama.cpp flags after a `--` delimiter — see
#   https://docs.docker.com/ai/model-runner/configuration/. We use that below.
#   (Historical note: an earlier llama.cpp bug — ggml-org/llama.cpp#17989,
#   fixed in PR #17997 — made `--parallel 1` silently initialize 4 slots.
#   DMR inherited the bug at the time, which is what made it look like DMR
#   hardcoded n_slots = 4. Current DMR builds — b9014+ — are past the fix,
#   so this `--parallel 1` is technically redundant, but explicit is safer.)
#
#   Apple's default Metal wired-memory cap is ~75 % of physical RAM
#   (~27 GB on a 36 GB M3 Pro). Budget:
#       ~17 GB weights + ~9 GB KV (96 K × 96 KiB) + ~1 GB compute  ≈ 27 GB
#   That just fits; bumping ctx-size further would need
#   `sudo sysctl iogpu.wired_limit_mb=30720` (30 GB) and is not recommended
#   without understanding the OS-starvation risk.
#
# TO CHANGE CONFIG LATER (no rerun of this script needed):
#   docker model configure --context-size N --keep-alive 30m ${MODEL}
#   docker model unload ${MODEL}     # forces reload with new config on next request
#   docker model configure show ${MODEL}    # verify
#
# TO SHUT DOWN THE MODEL (frees ~17 GB of RAM; daemon stays up, idle):
#   docker model unload ai/qwen3-coder:30B-A3B-UD-Q4_K_XL
#   docker model ps                  # verify nothing loaded
#
# TO TURN OFF THE WHOLE DMR DAEMON (rarely needed):
#   Docker Desktop → Settings → Beta features → uncheck "Model Runner"
#   (or quit Docker Desktop).
#
# DEBUGGING:
#   docker model logs                # llama.cpp inference logs (look for OOM,
#                                      Compute error, GGML_ASSERT, etc.)
#   docker model status              # backend health
#   docker model inspect ${MODEL}    # GGUF metadata + architecture
#
# REQUIRES: Docker Desktop 4.62+, Apple Silicon, Model Runner enabled,
#           "Enable host-side TCP support" on (port 12434).
# =============================================================================
set -euo pipefail

PORT=12434
MODEL="ai/qwen3-coder:30B-A3B-UD-Q4_K_XL"   # GGUF (Unsloth) → llama.cpp backend
ENDPOINT="http://localhost:${PORT}/engines/v1"
CONTEXT_SIZE=96000    # 1 slot × 96K × 96 KiB ≈ 9 GB KV cache — matches Approach C
KEEP_ALIVE="30m"

echo "=== Approach B: Docker Model Runner (llama.cpp) ==="
echo ""

# ---- 1. Check Docker --------------------------------------------------------
echo "[1/5] Checking Docker version..."
docker --version || { echo "ERROR: Docker not found. Install Docker Desktop 4.62+"; exit 1; }
echo ""

# ---- 2. Check Model Runner --------------------------------------------------
echo "[2/5] Checking Docker Model Runner status..."
if ! docker model status &>/dev/null; then
  echo ""
  echo "ERROR: Docker Model Runner is not enabled."
  echo "  -> Open Docker Desktop -> Settings -> Beta features"
  echo "  -> Enable 'Model Runner' -> Apply & Restart"
  exit 1
fi
docker model status
echo ""

# ---- 3. Pull the model ------------------------------------------------------
echo "[3/5] Pulling model (${MODEL}) -- ~17 GB on first run, cached afterwards..."
docker model pull "${MODEL}"
echo ""
echo "Available models:"
docker model list
echo ""

# ---- 4. Configure the model -------------------------------------------------
echo "[4/5] Configuring model (context-size=${CONTEXT_SIZE}, keep-alive=${KEEP_ALIVE})..."
docker model unload "${MODEL}" 2>/dev/null || true
docker model configure --context-size "${CONTEXT_SIZE}" --keep-alive "${KEEP_ALIVE}" "${MODEL}" -- --parallel 1
docker model configure show "${MODEL}"
echo ""

# ---- 5. Verify endpoint -----------------------------------------------------
echo "[5/5] Verifying DMR API at ${ENDPOINT}..."
if curl -sf "${ENDPOINT}/models" >/dev/null 2>&1; then
  echo "  OK -- API reachable at ${ENDPOINT}"
else
  echo "  ERROR: ${ENDPOINT} not reachable."
  echo "  Enable host-side TCP in Docker Desktop:"
  echo "    Settings -> Beta features -> Model Runner -> 'Enable host-side TCP support' (port ${PORT})"
  echo "  Or: docker desktop enable model-runner --tcp ${PORT}"
  exit 1
fi
echo ""
echo "Smoke test (first call is slow -- it loads the ~16 GB model into RAM):"
cat <<EOF
  curl ${ENDPOINT}/chat/completions \\
    -H 'Content-Type: application/json' \\
    -d '{"model":"${MODEL}","messages":[{"role":"user","content":"Write a Python function to reverse a linked list."}]}'
EOF
echo ""
echo "Next: ./bench.sh --only-dmr"
echo "Shut down model when done:  docker model unload ${MODEL}"
