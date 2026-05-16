#!/usr/bin/env bash
# =============================================================================
# bench.sh - Benchmark four local LLM engines on the same model
#
# ENGINES UNDER TEST:
#   rapid : Rapid-MLX        (port 8000,  model "qwen3-coder-30b")
#   dmr   : Docker Model Runner (port 12434, llama.cpp backend, GGUF Q4_K_XL)
#   llama : Raw llama-server (port 18080, direct llama.cpp runtime control)
#   omlx  : oMLX             (port 8001,  MLX + SSD KV cache)
#
# USAGE:
#   ./bench.sh                  # benchmark every reachable engine
#   ./bench.sh --only-rapid     # only Rapid-MLX
#   ./bench.sh --only-dmr       # only DMR
#   ./bench.sh --only-llama     # only llama-server
#   ./bench.sh --only-omlx      # only oMLX
#
#   ./bench.sh --quick          # ~25s/engine (1 trial x 500 tok, 1 TTFT, 2 tool calls)
#                                 For informal comparative runs.
#
#   ./bench.sh --trials 5 --max-tokens 2000 --ttft-trials 5 --tool-trials 5
#                                 Override individual settings. Defaults:
#                                 trials=3, max-tokens=500, ttft-trials=3, tool-trials=3.
#
#   ./bench.sh --prefix-replay --endpoint http://localhost:8001/v1 \
#                              --model Qwen3-Coder-30B-A3B-Instruct-4bit
#       Sends a long fixed prefix repeatedly with varying tails. Measures TTFT
#       per trial. Used to detect engines with prefix/SSD KV caching (oMLX).
#       Trials 1-5 sleep 30s between each (allows RAM cache eviction while SSD persists).
#
# PREREQUISITES:
#   The relevant engine must be running. The script issues a `ping` to each
#   endpoint up front; unreachable engines are skipped.
#
#   Hardware: connect power, use "High Performance" energy mode, and close
#   resource-intensive applications. Run engines one at a time on 36 GB; do
#   not attempt to keep all four loaded.
#
# RESULTS:
#   Saved to ./bench-results-<timestamp>.txt and printed at end of run.
# =============================================================================
set -euo pipefail

TRIALS=3            # decode trials per engine
MAX_TOKENS=500      # tokens per decode trial
TTFT_TRIALS=3
TOOL_TRIALS=3
RESULTS_FILE="$(dirname "$0")/bench-results-$(date +%Y%m%d-%H%M%S).txt"

# ---- engine registry --------------------------------------------------------
# Parallel arrays (bash 3.2-compatible; no associative arrays so we work on
# stock macOS bash without requiring Homebrew bash).
ENGINES=(rapid dmr llama omlx)
ENGINE_NAMES=("Rapid-MLX" "DMR" "llama-server" "oMLX")
ENGINE_ENDPOINTS=(
  "http://localhost:8000/v1"
  "http://localhost:12434/engines/v1"
  "http://localhost:18080/v1"
  "http://localhost:8001/v1"
)
ENGINE_MODELS=(
  "qwen3-coder-30b"
  "ai/qwen3-coder:30B-A3B-UD-Q4_K_XL"
  "qwen3-coder"
  "Qwen3-Coder-30B-A3B-Instruct-4bit"
)
# Pattern for `ps aux | awk` to estimate RSS per engine
ENGINE_PS_PATTERNS=(
  "rapid-mlx"
  "model-runner\\|com.docker.virtualization"
  "llama-server"
  "omlx"
)

idx_of() {
  local key="$1"
  local i
  for i in "${!ENGINES[@]}"; do
    if [ "${ENGINES[$i]}" = "$key" ]; then echo "$i"; return 0; fi
  done
  return 1
}

# ---- prompts ---------------------------------------------------------------
LONG_PROMPT="Write a complete TypeScript implementation of a red-black tree with insert, delete, find, and in-order traversal. Include full unit tests using Jest."
SHORT_PROMPT="Explain async/await in Python in one sentence."
WARM_PROMPT="Say hi in one word."
TOOL_PROMPT_BODY="List 3 Python built-in functions as a JSON array of strings."

# ---- helpers ----------------------------------------------------------------

is_reachable() {
  # Query the /models metadata endpoint; it is immediate and does not trigger a
  # model load. (Sending a real /chat/completions request times out on engines that load
  #  the model lazily on first request, e.g. oMLX after a fresh restart.)
  local endpoint="$1"
  curl -sf -o /dev/null --max-time 5 "${endpoint}/models"
}

warm_server() {
  local endpoint="$1" model="$2"
  curl -sf -o /dev/null --max-time 120 -X POST "${endpoint}/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"${WARM_PROMPT}\"}],\"max_tokens\":20}" || true
}

# Decode benchmark: long completion, return "<elapsed_s> <approx_tokens> <tps>"
bench_decode() {
  local endpoint="$1" model="$2"
  local tmpfile start end elapsed tokens tps
  tmpfile=$(mktemp)
  start=$(python3 -c "import time; print(time.time())")
  curl -sN --max-time 600 -X POST "${endpoint}/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"${model}\",
      \"messages\": [{\"role\":\"user\",\"content\":\"${LONG_PROMPT}\"}],
      \"max_tokens\": ${MAX_TOKENS},
      \"stream\": true
    }" > "${tmpfile}" 2>&1
  end=$(python3 -c "import time; print(time.time())")
  elapsed=$(python3 -c "print(round(${end} - ${start}, 2))")
  tokens=$(grep -c '"delta"' "${tmpfile}" 2>/dev/null || echo 0)
  tps=$(python3 -c "print(round(${tokens} / max(${elapsed}, 0.001), 1))" 2>/dev/null || echo 0)
  rm -f "${tmpfile}"
  echo "${elapsed} ${tokens} ${tps}"
}

# TTFT: time to first *content* token (skips role-marker and ping chunks).
bench_ttft() {
  local endpoint="$1" model="$2" prompt="$3"
  python3 - "$endpoint" "$model" "$prompt" <<'PYEOF'
import sys, time, json, urllib.request
endpoint, model, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
payload = json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": 50,
    "stream": True,
}).encode()
req = urllib.request.Request(f"{endpoint}/chat/completions", data=payload,
                              headers={"Content-Type": "application/json"})
start = time.time()
try:
    with urllib.request.urlopen(req, timeout=120) as r:
        for raw in r:
            if not raw.startswith(b"data:"):
                continue
            payload = raw[5:].strip()
            if not payload or payload == b"[DONE]":
                continue
            try:
                obj = json.loads(payload)
            except json.JSONDecodeError:
                continue
            choices = obj.get("choices") or []
            if not choices:
                continue
            delta = choices[0].get("delta") or {}
            content = delta.get("content")
            # Skip the role-marker chunk and any tool_call header without content.
            if content:
                print(round(time.time() - start, 3))
                break
except Exception as e:
    print(f"ERR:{e}")
PYEOF
}

# Tool-call reliability: count successful JSON parses out of TOOL_TRIALS calls
bench_tool_calls() {
  local endpoint="$1" model="$2" count="${TOOL_TRIALS}" success=0
  local i result
  for i in $(seq 1 "${count}"); do
    result=$(curl -sf --max-time 60 -X POST "${endpoint}/chat/completions" \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"${model}\",
        \"messages\": [{\"role\":\"user\",\"content\":\"${TOOL_PROMPT_BODY}\"}],
        \"max_tokens\": 100
      }" 2>/dev/null || echo "FAIL")
    if echo "${result}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" &>/dev/null; then
      success=$((success+1))
    fi
  done
  echo "${success}"
}

mem_rss() {
  local pat="$1" rss_mb
  rss_mb=$(ps aux | awk -v pat="${pat}" '$0 ~ pat && !/awk/ {sum += $6} END {print int(sum/1024)}')
  echo "${rss_mb}"
}

# ---- prefix-replay mode -----------------------------------------------------
# Sends a stable ~3K-token system+tools prefix with a varying short tail across
# 6 trials. Trial 0 is cold; trials 1-5 each preceded by a 30s sleep. Engines
# with prefix/SSD KV caching (oMLX) should show TTFT plummet after trial 0.
prefix_replay() {
  local endpoint="$1" model="$2"
  echo "============================================================"
  echo " Prefix-replay test"
  echo "============================================================"
  echo "  Endpoint: ${endpoint}"
  echo "  Model:    ${model}"
  echo ""
  echo "  6 trials. Trial 0 = cold prefix. Trials 1-5 = same prefix,"
  echo "  varying tail, with 30s sleep between each. Engines with prefix"
  echo "  caching (oMLX) should show TTFT drop sharply after trial 0."
  echo ""

  python3 - "$endpoint" "$model" <<'PYEOF'
import sys, time, json, urllib.request, random, string

endpoint, model = sys.argv[1], sys.argv[2]

# Stable prefix: ~3K tokens. The exact content is immaterial; it only needs to
# remain identical across trials so a prefix cache can match it.
SYSTEM = (
    "You are a senior software engineer reviewing changes to a large "
    "TypeScript and Python codebase. Follow the team style guide rigorously. "
    "Do not modify any files outside the directory under review. Always "
    "explain your reasoning before suggesting changes. "
) + ("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do "
     "eiusmod tempor incididunt ut labore et dolore magna aliqua. " * 180)
TOOLS = (
    "Available tools:\n"
    "- read_file(path: str) -> str\n"
    "- write_file(path: str, content: str) -> None\n"
    "- run_tests(pattern: str) -> TestResult\n"
    "- search_repo(query: str) -> List[Hit]\n"
) + ("Each tool call must be wrapped in <tool_call>...</tool_call>. "
     "Tool arguments must be valid JSON. " * 60)

PREFIX = SYSTEM + "\n\n" + TOOLS

def random_tail(n=200):
    return "".join(random.choices(string.ascii_letters + " ", k=n))

def measure_ttft(messages):
    body = json.dumps({
        "model": model,
        "messages": messages,
        "max_tokens": 5,
        "stream": True,
    }).encode()
    req = urllib.request.Request(f"{endpoint}/chat/completions",
                                  data=body,
                                  headers={"Content-Type": "application/json"})
    t = time.time()
    with urllib.request.urlopen(req, timeout=600) as r:
        for raw in r:
            if not raw.startswith(b"data:"):
                continue
            payload = raw[5:].strip()
            if not payload or payload == b"[DONE]":
                continue
            try:
                obj = json.loads(payload)
            except json.JSONDecodeError:
                continue
            choices = obj.get("choices") or []
            if not choices:
                continue
            delta = choices[0].get("delta") or {}
            content = delta.get("content")
            if content:   # skip role marker / empty deltas
                return time.time() - t
    return -1.0

def trial(i, sleep_first=False):
    if sleep_first:
        print(f"  Trial {i}: sleeping 30s to evict RAM cache... ", end="", flush=True)
        time.sleep(30)
        print("done. ", end="", flush=True)
    else:
        print(f"  Trial {i}: ", end="", flush=True)
    msgs = [
        {"role": "system", "content": PREFIX},
        {"role": "user", "content": random_tail() + "\n\nReply with 'ok'."}
    ]
    ttft = measure_ttft(msgs)
    print(f"TTFT = {ttft:6.2f} s")
    return ttft

results = []
results.append(trial(0, sleep_first=False))
for i in range(1, 6):
    results.append(trial(i, sleep_first=True))

print("")
cold = results[0]
warm_avg = sum(results[1:]) / len(results[1:])
ratio = warm_avg / cold if cold > 0 else float('inf')
print(f"  Cold TTFT (trial 0):     {cold:6.2f} s")
print(f"  Warm TTFT avg (1-5):     {warm_avg:6.2f} s")
print(f"  Warm/cold ratio:         {ratio:.2f}")
print()
if ratio < 0.3:
    print("  → STRONG prefix caching detected (warm < 30% of cold).")
elif ratio < 0.7:
    print("  → Some prefix caching detected (warm < 70% of cold).")
else:
    print("  → No meaningful prefix caching — warm runs are not faster.")
PYEOF
}

# ---- argument parsing -------------------------------------------------------
MODE="bench"
SELECTED=()      # active engines
PR_ENDPOINT=""
PR_MODEL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --only-rapid) SELECTED=(rapid) ;;
    --only-dmr)   SELECTED=(dmr) ;;
    --only-llama) SELECTED=(llama) ;;
    --only-omlx)  SELECTED=(omlx) ;;
    --prefix-replay) MODE="prefix-replay" ;;
    --endpoint)    PR_ENDPOINT="$2"; shift ;;
    --model)       PR_MODEL="$2"; shift ;;
    --quick)       TRIALS=1; MAX_TOKENS=500; TTFT_TRIALS=1; TOOL_TRIALS=2 ;;
    --trials)      TRIALS="$2"; shift ;;
    --max-tokens)  MAX_TOKENS="$2"; shift ;;
    --ttft-trials) TTFT_TRIALS="$2"; shift ;;
    --tool-trials) TOOL_TRIALS="$2"; shift ;;
    -h|--help)
      sed -n '2,40p' "$0"
      exit 0
      ;;
    *) echo "Unknown flag: $1"; exit 2 ;;
  esac
  shift
done

if [ "${MODE}" = "prefix-replay" ]; then
  if [ -z "${PR_ENDPOINT}" ] || [ -z "${PR_MODEL}" ]; then
    echo "ERROR: --prefix-replay requires --endpoint and --model"
    echo "Example:"
    echo "  ./bench.sh --prefix-replay --endpoint http://localhost:8001/v1 \\"
    echo "    --model Qwen3-Coder-30B-A3B-Instruct-4bit"
    exit 2
  fi
  prefix_replay "${PR_ENDPOINT}" "${PR_MODEL}"
  exit 0
fi

# If no --only-* flag is supplied, auto-detect reachable engines.
if [ ${#SELECTED[@]} -eq 0 ]; then
  for e in "${ENGINES[@]}"; do
    i=$(idx_of "$e")
    if is_reachable "${ENGINE_ENDPOINTS[$i]}" "${ENGINE_MODELS[$i]}"; then
      SELECTED+=("$e")
    fi
  done
fi

if [ ${#SELECTED[@]} -eq 0 ]; then
  echo "No engines reachable. Start one of:"
  for e in "${ENGINES[@]}"; do
    i=$(idx_of "$e")
    echo "  $e -> ${ENGINE_ENDPOINTS[$i]} (model: ${ENGINE_MODELS[$i]})"
  done
  exit 1
fi

echo "============================================================"
echo " Local LLM Benchmark"
echo " Date:        $(date)"
echo " Hardware:    $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')"
echo " Engines:     ${SELECTED[*]}"
echo " Decode:      ${TRIALS} trial(s) × ${MAX_TOKENS} max tokens"
echo " TTFT:        ${TTFT_TRIALS} trial(s)"
echo " Tool calls:  ${TOOL_TRIALS} trial(s)"
echo "============================================================"
echo ""

# Per-engine result accumulators
declare -a R_NAME R_TPS R_TTFT R_TOOL R_RSS

# ---- main loop --------------------------------------------------------------
for e in "${SELECTED[@]}"; do
  i=$(idx_of "$e")
  name="${ENGINE_NAMES[$i]}"
  endpoint="${ENGINE_ENDPOINTS[$i]}"
  model="${ENGINE_MODELS[$i]}"
  ps_pattern="${ENGINE_PS_PATTERNS[$i]}"

  echo "--- ${name} (${endpoint}) ---"

  if ! is_reachable "${endpoint}" "${model}"; then
    echo "  UNREACHABLE — skipping"
    R_NAME+=("$name"); R_TPS+=("N/A"); R_TTFT+=("N/A"); R_TOOL+=("N/A"); R_RSS+=("N/A")
    echo ""
    continue
  fi

  echo -n "  Warming... "; warm_server "${endpoint}" "${model}"; echo "done"

  # Decode tok/s, average across trials
  tps_sum=0
  for t in $(seq 1 "${TRIALS}"); do
    read -r elapsed tokens tps < <(bench_decode "${endpoint}" "${model}")
    echo "    [decode trial ${t}] ${elapsed}s, ~${tokens} tok, ${tps} tok/s"
    tps_sum=$(python3 -c "print(${tps_sum} + ${tps})")
  done
  avg_tps=$(python3 -c "print(round(${tps_sum}/${TRIALS}, 1))")
  echo "  Avg decode tok/s: ${avg_tps}"

  # Cold TTFT
  ttft_sum=0; ttft_n=0
  for t in $(seq 1 "${TTFT_TRIALS}"); do
    ttft=$(bench_ttft "${endpoint}" "${model}" "${SHORT_PROMPT}")
    if [[ "${ttft}" =~ ^[0-9.]+$ ]]; then
      echo "    [TTFT trial ${t}] ${ttft}s"
      ttft_sum=$(python3 -c "print(${ttft_sum} + ${ttft})")
      ttft_n=$((ttft_n+1))
    else
      echo "    [TTFT trial ${t}] ${ttft}"
    fi
  done
  if [ "${ttft_n}" -gt 0 ]; then
    avg_ttft=$(python3 -c "print(round(${ttft_sum}/${ttft_n}, 3))")
  else
    avg_ttft="N/A"
  fi
  echo "  Avg TTFT (s): ${avg_ttft}"

  # Tool-call reliability
  tool_ok=$(bench_tool_calls "${endpoint}" "${model}")
  echo "  Tool-call success: ${tool_ok}/${TOOL_TRIALS}"

  # RSS
  rss=$(mem_rss "${ps_pattern}")
  echo "  RSS (MB): ${rss}"

  R_NAME+=("$name"); R_TPS+=("$avg_tps"); R_TTFT+=("$avg_ttft"); R_TOOL+=("${tool_ok}/${TOOL_TRIALS}"); R_RSS+=("${rss}")
  echo ""
done

# ---- summary table ----------------------------------------------------------
echo "============================================================"
echo " RESULTS SUMMARY"
echo "============================================================"
printf "  %-14s %12s %12s %12s %10s\n" "Engine" "decode tok/s" "TTFT (s)" "Tools" "RSS MB"
printf "  %-14s %12s %12s %12s %10s\n" "------" "------------" "--------" "-----" "------"
for k in "${!R_NAME[@]}"; do
  printf "  %-14s %12s %12s %12s %10s\n" \
    "${R_NAME[$k]}" "${R_TPS[$k]}" "${R_TTFT[$k]}" "${R_TOOL[$k]}" "${R_RSS[$k]}"
done
echo ""
echo "Decision criteria: see plan section 'Decision criteria (4-way)'."
echo "Prefix-replay test (run separately for oMLX):"
echo "  ./bench.sh --prefix-replay --endpoint <url> --model <name>"
echo ""

# ---- save results -----------------------------------------------------------
{
  echo "Benchmark run: $(date)"
  echo "Hardware: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')"
  echo "Trials: ${TRIALS}"
  echo ""
  printf "%-14s %12s %12s %12s %10s\n" "Engine" "decode tok/s" "TTFT (s)" "Tools" "RSS MB"
  for k in "${!R_NAME[@]}"; do
    printf "%-14s %12s %12s %12s %10s\n" \
      "${R_NAME[$k]}" "${R_TPS[$k]}" "${R_TTFT[$k]}" "${R_TOOL[$k]}" "${R_RSS[$k]}"
  done
} > "${RESULTS_FILE}"
echo "Results saved to: ${RESULTS_FILE}"
