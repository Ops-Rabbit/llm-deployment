#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly TEST_DIR
# shellcheck source=lib/common.sh
source "$TEST_DIR/../lib/common.sh"
# shellcheck source=lib/profiles.sh
source "$TEST_DIR/../lib/profiles.sh"

validate_gguf_path test-profile "quant/model-00001-of-00002.gguf"
if (validate_gguf_path test-profile "../escape.gguf" >/dev/null 2>&1); then
  printf 'FAIL: unsafe parent GGUF path was accepted\n' >&2
  exit 1
fi
if (validate_gguf_path test-profile "/absolute/model.gguf" >/dev/null 2>&1); then
  printf 'FAIL: unsafe absolute GGUF path was accepted\n' >&2
  exit 1
fi

profiles_checked=0
while IFS= read -r profile_name; do
  load_profile "$profile_name"
  profiles_checked=$((profiles_checked + 1))
done < <(list_profiles)

[[ "$profiles_checked" -eq 17 ]] || {
  printf 'FAIL: expected 17 profiles, found %d\n' "$profiles_checked" >&2
  exit 1
}

load_profile qwen38-fp8
[[ "$PROFILE_DEFAULT_RUNTIME" == "sglang" ]]
[[ "$PROFILE_MIN_COMPUTE_CAPABILITY" == "8.9" ]]
[[ " ${PROFILE_VLLM_ARGS[*]} " == *" --enable-auto-tool-choice "* ]]

load_profile qwen38-unsloth-gguf-q4
[[ "$PROFILE_DEFAULT_RUNTIME" == "llamacpp" ]]
[[ "$PROFILE_GGUF_FILENAME" == "Qwen3.8-27B-UD-Q4_K_XL.gguf" ]]
[[ "${#PROFILE_GGUF_FILES[@]}" -eq 1 ]]
[[ " ${PROFILE_LLAMACPP_ARGS[*]} " == *" --jinja "* ]]

load_profile deepseek-v4-flash-0731
[[ "$PROFILE_DEFAULT_RUNTIME" == "sglang" ]]
[[ "$PROFILE_GPU_COUNT" -eq 4 ]]
[[ "$PROFILE_MIN_GPU_MEMORY_MIB" -eq 130000 ]]
[[ "$PROFILE_TRUST_REMOTE_CODE" == "true" ]]
[[ " ${PROFILE_SGLANG_ARGS[*]} " == *" --tool-call-parser deepseekv4 "* ]]
[[ " ${PROFILE_VLLM_ARGS[*]} " == *" --tokenizer-mode deepseek_v4 "* ]]

load_profile deepseek-v4-flash-0731-unsloth-gguf-q4
[[ "$PROFILE_DEFAULT_RUNTIME" == "llamacpp" ]]
[[ "${#PROFILE_GGUF_FILES[@]}" -eq 5 ]]
[[ "${PROFILE_GGUF_FILES[0]}" == "UD-Q4_K_XL/DeepSeek-V4-Flash-0731-UD-Q4_K_XL-00001-of-00005.gguf" ]]
[[ "${PROFILE_GGUF_FILES[4]}" == "UD-Q4_K_XL/DeepSeek-V4-Flash-0731-UD-Q4_K_XL-00005-of-00005.gguf" ]]

load_profile glm-5.2-w4afp8
[[ "$PROFILE_GPU_COUNT" -eq 8 ]]
[[ "$PROFILE_MODEL_FAMILY" == "glm-5.2-w4afp8" ]]

printf 'PASS: %d catalog profiles validated\n' "$profiles_checked"
