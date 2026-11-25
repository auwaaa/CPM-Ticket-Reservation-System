#!/usr/bin/env bash
# run_checks.sh - Run SPIN safety and LTL liveness checks and log metrics.
# Usage: ./scripts/run_checks.sh <model.pml> [ltl_property_name]

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <model.pml> [ltl_name]"
    exit 1
fi

MODEL_PATH="$1"
LTL_NAME="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="$REPO_ROOT/results"
METRICS_FILE="$RESULTS_DIR/metrics.csv"

if [ ! -f "$MODEL_PATH" ]; then
    echo "Error: Model file not found: $MODEL_PATH"
    exit 1
fi

mkdir -p "$RESULTS_DIR"
if [ ! -f "$METRICS_FILE" ]; then
    echo "timestamp,model,mode,ltl_property,errors,states_stored,transitions,memory_mb,elapsed_sec" > "$METRICS_FILE"
fi

MODEL_BASE="$(basename "$MODEL_PATH" .pml)"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cleanup() {
    rm -f pan pan.c pan.h pan.b pan.m pan.p pan.t _spin_nvr.tmp
}
trap cleanup EXIT

extract_and_log() {
    local mode="$1"
    local ltl_prop="$2"
    local log_file="$3"

    local errors states transitions memory elapsed
    errors="$(grep -oE 'errors: [0-9]+' "$log_file" | awk '{print $2}' | tail -n1 || echo "NA")"
    states="$(grep -oE '[0-9]+ states, stored' "$log_file" | awk '{print $1}' | tail -n1 || echo "NA")"
    transitions="$(grep -oE '[0-9]+ transitions' "$log_file" | awk '{print $1}' | tail -n1 || echo "NA")"
    memory="$(grep -oE '[0-9]+\.[0-9]+[[:space:]]+total actual memory usage' "$log_file" | awk '{print $1}' | tail -n1 || echo "NA")"
    elapsed="$(grep -oE 'elapsed time [0-9]+\.[0-9]+ seconds' "$log_file" | awk '{print $3}' | tail -n1 || echo "NA")"

    echo "$TIMESTAMP,$MODEL_BASE,$mode,$ltl_prop,$errors,$states,$transitions,$memory,$elapsed" >> "$METRICS_FILE"
}

echo "=== [1/3] Generating verifier with spin -a: $MODEL_PATH ==="
spin -a "$MODEL_PATH"

echo "=== [2/3] Safety check (-DSAFETY) ==="
gcc -O2 -DSAFETY -o pan pan.c
SAFETY_LOG="$RESULTS_DIR/${MODEL_BASE}_safety.log"
./pan -E | tee "$SAFETY_LOG"
extract_and_log "safety" "none" "$SAFETY_LOG"

echo "=== [3/3] Liveness / acceptance-cycle check (-a -f) ==="
gcc -O2 -o pan pan.c
LIVENESS_LOG="$RESULTS_DIR/${MODEL_BASE}_liveness.log"
if [ -n "$LTL_NAME" ]; then
    ./pan -a -f -N "$LTL_NAME" | tee "$LIVENESS_LOG"
    extract_and_log "liveness" "$LTL_NAME" "$LIVENESS_LOG"
else
    ./pan -a -f | tee "$LIVENESS_LOG"
    extract_and_log "liveness" "default" "$LIVENESS_LOG"
fi

echo "=== Done. Metrics appended to $METRICS_FILE ==="
