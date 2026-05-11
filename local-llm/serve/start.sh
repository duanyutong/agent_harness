#!/usr/bin/env bash
# =============================================================================
# Daily-use launcher for Rapid-MLX serving Qwen3-Coder-30B-A3B-Instruct.
#
# This is the minimal day-to-day server. No install/doctor/check steps —
# assumes Rapid-MLX is already installed and the model is in the HF cache.
# (For first-time setup or reinstall, use ../benchmark/rapid-mlx-setup.sh.)
#
# Endpoint:    http://localhost:8000/v1   (OpenAI-compatible)
# Model name:  qwen3-coder-30b
# Shutdown:    Ctrl-C in this terminal.
#
# To run as a background daemon: install the launchd plist from this dir:
#   cp com.rapid-mlx.server.plist ~/Library/LaunchAgents/
#   launchctl load ~/Library/LaunchAgents/com.rapid-mlx.server.plist
#
# To unload the daemon:
#   launchctl unload ~/Library/LaunchAgents/com.rapid-mlx.server.plist
# =============================================================================
set -euo pipefail

PORT=8000
MODEL="qwen3-coder-30b"   # → mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit

if ! command -v rapid-mlx &>/dev/null; then
  echo "ERROR: rapid-mlx not on PATH."
  echo "Run ../benchmark/rapid-mlx-setup.sh once to install it."
  exit 1
fi

if lsof -nP -iTCP:${PORT} -sTCP:LISTEN &>/dev/null; then
  echo "ERROR: Port ${PORT} is already in use:"
  lsof -nP -iTCP:${PORT} -sTCP:LISTEN
  echo "Stop the conflicting process first."
  exit 1
fi

echo "Starting Rapid-MLX on :${PORT}..."
echo "  Endpoint: http://localhost:${PORT}/v1"
echo "  Model:    ${MODEL}"
echo "  Stop:     Ctrl-C"
echo ""
exec rapid-mlx serve "${MODEL}" --prefill-step-size 8192 --port "${PORT}"
