#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_DIR
cd "$REPO_DIR"

tests_run=0

expect_failure_contains() {
  local description=$1
  local expected=$2
  shift 2

  local output
  if output=$("$@" 2>&1); then
    printf 'FAIL: expected failure: %s\n' "$description" >&2
    exit 1
  fi
  grep -Fq -- "$expected" <<<"$output" || {
    printf 'FAIL: %s did not report: %s\n' "$description" "$expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  }
  tests_run=$((tests_run + 1))
}

expect_failure_contains \
  "unknown profile" \
  "Profile must be h100 or a100" \
  ./install.sh --data-dir / --profile other --check-only

expect_failure_contains \
  "A100 profile selects vLLM and pinned defaults" \
  "Selected profile a100: vllm, lowbitcoffee/GLM-5.2-W4A16@55c92ae85b7ec564c94634964b6f5efe5c09a844, 8x A100, 32768-token context." \
  ./install.sh --data-dir / --profile a100 --check-only

expect_failure_contains \
  "built-in A100 checkpoint rejects SGLang" \
  "The GLM-5.2 A100 W4A16 profile is verified only with vLLM" \
  ./install.sh --data-dir / --profile a100 --runtime sglang --check-only

expect_failure_contains \
  "custom A100-profile model keeps explicit runtime" \
  "Selected profile a100: sglang, example/model@0123456789abcdef0123456789abcdef01234567, 8x A100, 32768-token context." \
  ./install.sh --data-dir / --profile a100 --runtime sglang \
  --model example/model --model-revision 0123456789abcdef0123456789abcdef01234567 --check-only

printf 'PASS: %d profile checks\n' "$tests_run"
