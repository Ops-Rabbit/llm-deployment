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
  "Unknown profile other" \
  ./install.sh --data-dir / --profile other --check-only

expect_failure_contains \
  "profile selection is required" \
  "--profile is required" \
  ./install.sh --data-dir / --check-only

expect_failure_contains \
  "legacy hardware profile name is removed" \
  "Unknown profile h100" \
  ./install.sh --data-dir / --profile h100 --check-only

expect_failure_contains \
  "second legacy hardware profile name is removed" \
  "Unknown profile a100" \
  ./install.sh --data-dir / --profile a100 --check-only

expect_failure_contains \
  "GLM-5.2 W4AFP8 profile selects SGLang and pinned defaults" \
  "Selected profile glm-5.2-w4afp8: sglang, PhalaCloud/GLM-5.2-W4AFP8@e42e1aee344f812b6fb73f503bfbe6a227727396, 8x H100, 131072-token context." \
  ./install.sh --data-dir / --profile glm-5.2-w4afp8 --check-only

expect_failure_contains \
  "GLM-5.2 W4A16 profile selects vLLM and pinned defaults" \
  "Selected profile glm-5.2-w4a16: vllm, lowbitcoffee/GLM-5.2-W4A16@55c92ae85b7ec564c94634964b6f5efe5c09a844, 8x A100, 32768-token context." \
  ./install.sh --data-dir / --profile glm-5.2-w4a16 --check-only

expect_failure_contains \
  "built-in A100 checkpoint rejects SGLang" \
  "Profile glm-5.2-w4a16 supports runtime(s) vllm" \
  ./install.sh --data-dir / --profile glm-5.2-w4a16 --runtime sglang --check-only

expect_failure_contains \
  "custom model based on GLM-5.2 W4A16 keeps explicit runtime" \
  "Selected profile glm-5.2-w4a16: sglang, example/model@0123456789abcdef0123456789abcdef01234567, 8x A100, 32768-token context." \
  ./install.sh --data-dir / --profile glm-5.2-w4a16 --runtime sglang \
  --model example/model --model-revision 0123456789abcdef0123456789abcdef01234567 --check-only

expect_failure_contains \
  "official Qwen BF16 profile" \
  "Selected profile qwen38-bf16: sglang, Qwen/Qwen3.8-27B@1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0, 1x NVIDIA GPU, 32768-token context." \
  ./install.sh --data-dir / --profile qwen38-bf16 --check-only

expect_failure_contains \
  "official Qwen FP8 profile" \
  "Selected profile qwen38-fp8: sglang, Qwen/Qwen3.8-27B-FP8@017b9c7af6b5689d5dd426a76e0bc077eb5ca20a, 1x NVIDIA GPU, 32768-token context." \
  ./install.sh --data-dir / --profile qwen38-fp8 --check-only

expect_failure_contains \
  "Unsloth Qwen NVFP4 profile" \
  "Selected profile qwen38-unsloth-nvfp4: sglang, unsloth/Qwen3.8-27B-NVFP4@7d6f8d4d72f56b92b3cdbf22f156b90e1bab0108, 1x NVIDIA GPU, 32768-token context." \
  ./install.sh --data-dir / --profile qwen38-unsloth-nvfp4 --check-only

expect_failure_contains \
  "Unsloth Qwen Q4 GGUF profile" \
  "Selected profile qwen38-unsloth-gguf-q4: llamacpp, unsloth/Qwen3.8-27B-GGUF@4ca720788d1e01f1bff70c033e0d0028fd02e502, 1x NVIDIA GPU, 32768-token context." \
  ./install.sh --data-dir / --profile qwen38-unsloth-gguf-q4 --check-only

expect_failure_contains \
  "DeepSeek V4 Flash 0731 native profile" \
  "Selected profile deepseek-v4-flash-0731: sglang, deepseek-ai/DeepSeek-V4-Flash-0731@7872f01b1d1fe23eabc4c98b48bffcef5a386062, 4x NVIDIA GPU, 32768-token context." \
  ./install.sh --data-dir / --profile deepseek-v4-flash-0731 --check-only

expect_failure_contains \
  "DeepSeek V4 Flash 0731 supports vLLM" \
  "Selected profile deepseek-v4-flash-0731: vllm, deepseek-ai/DeepSeek-V4-Flash-0731@7872f01b1d1fe23eabc4c98b48bffcef5a386062, 4x NVIDIA GPU, 32768-token context." \
  ./install.sh --data-dir / --profile deepseek-v4-flash-0731 --runtime vllm --check-only

expect_failure_contains \
  "DeepSeek V4 Flash 0423 H100 profile" \
  "Selected profile deepseek-v4-flash-0423: sglang, deepseek-ai/DeepSeek-V4-Flash@60d8d70770c6776ff598c94bb586a859a38244f1, 8x NVIDIA GPU, 32768-token context." \
  ./install.sh --data-dir / --profile deepseek-v4-flash-0423 --check-only

expect_failure_contains \
  "DeepSeek V4 Flash 0731 Unsloth Q4 GGUF profile" \
  "Selected profile deepseek-v4-flash-0731-unsloth-gguf-q4: llamacpp, unsloth/DeepSeek-V4-Flash-0731-GGUF@fbbb5b93fb787c21338159b0af3318bb3f4d9768, 1x NVIDIA GPU, 32768-token context." \
  ./install.sh --data-dir / --profile deepseek-v4-flash-0731-unsloth-gguf-q4 --check-only

expect_failure_contains \
  "DeepSeek GGUF rejects an incompatible runtime" \
  "Profile deepseek-v4-flash-0731-unsloth-gguf-q4 supports runtime(s) llamacpp" \
  ./install.sh --data-dir / --profile deepseek-v4-flash-0731-unsloth-gguf-q4 --runtime vllm --check-only

expect_failure_contains \
  "GGUF profile rejects an incompatible runtime" \
  "Profile qwen38-unsloth-gguf-q4 supports runtime(s) llamacpp" \
  ./install.sh --data-dir / --profile qwen38-unsloth-gguf-q4 --runtime vllm --check-only

expect_failure_contains \
  "INT4 requires an explicitly pinned checkpoint" \
  "Profile qwen38-int4 requires --model and --model-revision" \
  ./install.sh --data-dir / --profile qwen38-int4 --check-only

expect_failure_contains \
  "INT4 accepts an explicitly pinned checkpoint" \
  "Selected profile qwen38-int4: vllm, example/Qwen3.8-27B-AWQ@0123456789abcdef0123456789abcdef01234567, 1x NVIDIA GPU, 32768-token context." \
  ./install.sh --data-dir / --profile qwen38-int4 \
  --model example/Qwen3.8-27B-AWQ \
  --model-revision 0123456789abcdef0123456789abcdef01234567 --check-only

expect_failure_contains \
  "Unsloth FP8 uses the Qwen FP8 behavior profile" \
  "Selected profile qwen38-fp8: vllm, unsloth/Qwen3.8-27B-FP8@d51e38f6f2b5877bb91e06ba231e41ffc63bde6f, 1x NVIDIA GPU, 32768-token context." \
  ./install.sh --data-dir / --profile qwen38-fp8 --runtime vllm \
  --model unsloth/Qwen3.8-27B-FP8 \
  --model-revision d51e38f6f2b5877bb91e06ba231e41ffc63bde6f --check-only

printf 'PASS: %d profile checks\n' "$tests_run"
