# Daily-use serving: Rapid-MLX

Runs `Qwen3-Coder-30B-A3B-Instruct` (MLX 4-bit) on `http://localhost:8000/v1`. Selected after benchmarking against llama-server and oMLX — see [../README.md](../README.md) for the full comparison.

## Quick start

```bash
./start.sh
```

This starts the server in the foreground. Press Ctrl-C to stop it.

## Run as a background daemon

```bash
cp com.rapid-mlx.server.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.rapid-mlx.server.plist
```

Stop:

```bash
launchctl unload ~/Library/LaunchAgents/com.rapid-mlx.server.plist
```

Logs: `/tmp/rapid-mlx.log` and `/tmp/rapid-mlx.err`.

## Zed config

Add to `~/.config/zed/settings.json`:

```json
{
  "language_models": {
    "openai_compatible": {
      "Rapid-MLX (Local)": {
        "api_url": "http://localhost:8000/v1",
        "available_models": [
          {
            "name": "qwen3-coder-30b",
            "display_name": "Qwen3-Coder (Rapid-MLX, local)",
            "max_tokens": 65536,
            "capabilities": {
              "tools": true,
              "images": false,
              "parallel_tool_calls": true,
              "prompt_cache_key": false,
              "chat_completions": true,
              "interleaved_reasoning": false
            }
          }
        ]
      }
    }
  }
}
```

`max_tokens: 65536` is a conservative practical limit for M3 Pro 36 GB. The KV cache fills lazily, but memory pressure is expected above approximately 64 K tokens. Raise to `262144` to expose the model's full native context, at the risk of OOM during long sessions.

## docker-compose clients requiring access to the LLM

Rapid-MLX runs on the host, not in Docker. Other containers reach it via `host.docker.internal`:

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

## Smoke test

```bash
curl -sS http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3-coder-30b","messages":[{"role":"user","content":"Write a Python function to reverse a linked list."}]}' \
  | python3 -m json.tool
```

## Uninstall / replace

To switch engines later, for example to llama-server or oMLX, use the setup scripts for all four candidates in [`../benchmark/`](../benchmark/). Each script is self-contained.
