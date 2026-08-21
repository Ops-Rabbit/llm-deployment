#!/usr/bin/env bash

PROFILE_CATALOG_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../profiles" && pwd)
readonly PROFILE_CATALOG_DIR

list_profiles() {
  local profile_file
  for profile_file in "$PROFILE_CATALOG_DIR"/*.conf; do
    [[ -e "$profile_file" ]] || continue
    basename -- "$profile_file" .conf
  done | sort
}

reset_profile() {
  PROFILE_MODEL_ID=""
  PROFILE_MODEL_REVISION=""
  PROFILE_SERVED_MODEL_NAME=""
  PROFILE_MODEL_FAMILY=""
  PROFILE_DEFAULT_RUNTIME=""
  PROFILE_ALLOWED_RUNTIMES=""
  PROFILE_GPU_COUNT=1
  PROFILE_GPU_NAME=""
  PROFILE_MIN_GPU_MEMORY_MIB=1
  PROFILE_MIN_COMPUTE_CAPABILITY=""
  PROFILE_MIN_SYSTEM_MEMORY_MIB=0
  PROFILE_MIN_DATA_GIB=1
  PROFILE_CONTEXT_LENGTH=32768
  PROFILE_SGLANG_MEM_FRACTION="0.85"
  PROFILE_GPU_MEMORY_UTILIZATION="0.85"
  PROFILE_TRUST_REMOTE_CODE=false
  PROFILE_REQUIRES_CUSTOM_MODEL=false
  PROFILE_PRESERVE_FAMILY_ON_MODEL_OVERRIDE=false
  PROFILE_GGUF_FILENAME=""
  PROFILE_GGUF_FILES=()
  PROFILE_MTP_MODE=""
  PROFILE_SGLANG_ARGS=()
  PROFILE_SGLANG_ENV=()
  PROFILE_VLLM_ARGS=()
  PROFILE_VLLM_ENV=()
  PROFILE_LLAMACPP_ARGS=()
  PROFILE_LLAMACPP_ENV=()
}

load_profile() {
  local profile_name=$1
  [[ "$profile_name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] ||
    die "Invalid profile name: ${profile_name}."

  local profile_file="$PROFILE_CATALOG_DIR/${profile_name}.conf"
  [[ -f "$profile_file" ]] || {
    local available_profiles
    available_profiles=$(list_profiles | paste -sd, -)
    die "Unknown profile ${profile_name}. Available profiles: ${available_profiles}."
  }

  reset_profile
  # Profile files are version-controlled, root-reviewed installer data.
  # shellcheck source=/dev/null
  source "$profile_file"

  validate_model_value "Profile model family" "$PROFILE_MODEL_FAMILY"
  validate_model_value "Profile default runtime" "$PROFILE_DEFAULT_RUNTIME"
  validate_model_value "Profile allowed runtimes" "$PROFILE_ALLOWED_RUNTIMES"
  validate_runtime "$PROFILE_DEFAULT_RUNTIME"
  runtime_is_allowed "$PROFILE_DEFAULT_RUNTIME" "$PROFILE_ALLOWED_RUNTIMES" ||
    die "Profile ${profile_name} does not allow its default runtime ${PROFILE_DEFAULT_RUNTIME}."
  validate_positive_integer "Profile GPU count" "$PROFILE_GPU_COUNT"
  validate_positive_integer "Profile minimum GPU memory" "$PROFILE_MIN_GPU_MEMORY_MIB"
  validate_nonnegative_integer "Profile minimum system memory" "$PROFILE_MIN_SYSTEM_MEMORY_MIB"
  validate_positive_integer "Profile minimum data size" "$PROFILE_MIN_DATA_GIB"
  validate_context_length "$PROFILE_CONTEXT_LENGTH"
  if [[ -n "$PROFILE_MIN_COMPUTE_CAPABILITY" ]]; then
    [[ "$PROFILE_MIN_COMPUTE_CAPABILITY" =~ ^[0-9]+\.[0-9]+$ ]] ||
      die "Profile ${profile_name} has an invalid compute-capability floor."
  fi
  [[ "$PROFILE_SGLANG_MEM_FRACTION" =~ ^0\.[0-9]+$ || "$PROFILE_SGLANG_MEM_FRACTION" == "1.0" ]] ||
    die "Profile ${profile_name} has an invalid SGLang memory fraction."
  [[ "$PROFILE_GPU_MEMORY_UTILIZATION" =~ ^0\.[0-9]+$ || "$PROFILE_GPU_MEMORY_UTILIZATION" == "1.0" ]] ||
    die "Profile ${profile_name} has an invalid vLLM memory utilization."
  [[ "$PROFILE_TRUST_REMOTE_CODE" == "true" || "$PROFILE_TRUST_REMOTE_CODE" == "false" ]] ||
    die "Profile ${profile_name} has an invalid trust-remote-code setting."
  [[ "$PROFILE_REQUIRES_CUSTOM_MODEL" == "true" || "$PROFILE_REQUIRES_CUSTOM_MODEL" == "false" ]] ||
    die "Profile ${profile_name} has an invalid custom-model setting."
  [[ "$PROFILE_PRESERVE_FAMILY_ON_MODEL_OVERRIDE" == "true" || "$PROFILE_PRESERVE_FAMILY_ON_MODEL_OVERRIDE" == "false" ]] ||
    die "Profile ${profile_name} has an invalid model-family override setting."

  if [[ "$PROFILE_REQUIRES_CUSTOM_MODEL" != "true" ]]; then
    validate_huggingface_model_id "$PROFILE_MODEL_ID"
    validate_model_revision "$PROFILE_MODEL_REVISION"
    validate_model_value "Profile served model name" "$PROFILE_SERVED_MODEL_NAME"
  fi
  if [[ -n "$PROFILE_GGUF_FILENAME" && ${#PROFILE_GGUF_FILES[@]} -gt 0 ]]; then
    die "Profile ${profile_name} must use either PROFILE_GGUF_FILENAME or PROFILE_GGUF_FILES, not both."
  fi
  if [[ -n "$PROFILE_GGUF_FILENAME" ]]; then
    PROFILE_GGUF_FILES=("$PROFILE_GGUF_FILENAME")
  fi
  local gguf_file
  for gguf_file in "${PROFILE_GGUF_FILES[@]}"; do
    validate_gguf_path "$profile_name" "$gguf_file"
  done
}

validate_gguf_path() {
  local profile_name=$1
  local gguf_path=$2
  [[ "$gguf_path" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*\.gguf$ ]] ||
    die "Profile ${profile_name} contains an unsafe GGUF path."
  [[ "/$gguf_path/" != *"/../"* && "/$gguf_path/" != *"/./"* ]] ||
    die "Profile ${profile_name} contains an unsafe GGUF path."
}

runtime_is_allowed() {
  local requested_runtime=$1
  local allowed_runtimes=$2
  local allowed_runtime
  for allowed_runtime in $allowed_runtimes; do
    [[ "$requested_runtime" == "$allowed_runtime" ]] && return 0
  done
  return 1
}
