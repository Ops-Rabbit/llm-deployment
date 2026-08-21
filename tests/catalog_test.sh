#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly TEST_DIR
# shellcheck source=lib/common.sh
source "$TEST_DIR/../lib/common.sh"
# shellcheck source=lib/profiles.sh
source "$TEST_DIR/../lib/profiles.sh"

profiles_checked=0
while IFS= read -r profile_name; do
  load_profile "$profile_name"
  profiles_checked=$((profiles_checked + 1))
done < <(list_profiles)

[[ "$profiles_checked" -eq 11 ]] || {
  printf 'FAIL: expected 11 profiles, found %d\n' "$profiles_checked" >&2
  exit 1
}

load_profile qwen38-fp8
[[ "$PROFILE_DEFAULT_RUNTIME" == "sglang" ]]
[[ "$PROFILE_MIN_COMPUTE_CAPABILITY" == "8.9" ]]
[[ " ${PROFILE_VLLM_ARGS[*]} " == *" --enable-auto-tool-choice "* ]]

load_profile qwen38-unsloth-gguf-q4
[[ "$PROFILE_DEFAULT_RUNTIME" == "llamacpp" ]]
[[ "$PROFILE_GGUF_FILENAME" == "Qwen3.8-27B-UD-Q4_K_XL.gguf" ]]
[[ " ${PROFILE_LLAMACPP_ARGS[*]} " == *" --jinja "* ]]

load_profile h100
[[ "$PROFILE_GPU_COUNT" -eq 8 ]]
[[ "$PROFILE_MODEL_FAMILY" == "glm-5.2-w4afp8" ]]

printf 'PASS: %d catalog profiles validated\n' "$profiles_checked"
