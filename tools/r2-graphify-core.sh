#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-"$ROOT/reverse/smartisan-8.5.3-core"}"
JADX_OUT="$OUT/jadx"

if [[ ! -d "$JADX_OUT" ]]; then
  echo "missing jadx output: $JADX_OUT" >&2
  echo "run tools/r2-reverse-core-system.sh first" >&2
  exit 1
fi

# First pass is intentionally AST-only to avoid surprise LLM cost on a huge
# decompiled Android corpus. Semantic graph expansion can be run later on a
# smaller target set once the core package boundaries are clear.
unset OPENAI_API_KEY
unset ANTHROPIC_API_KEY
unset GEMINI_API_KEY
unset KIMI_API_KEY
unset DEEPSEEK_API_KEY

graphify extract "$JADX_OUT" --out "$OUT" --no-cluster --max-workers 6
graphify cluster-only "$OUT" --no-viz

echo "graph: $OUT/graphify-out/graph.json"
echo "report: $OUT/graphify-out/GRAPH_REPORT.md"
