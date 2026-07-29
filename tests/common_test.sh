#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly TEST_DIR
# shellcheck source=lib/common.sh
source "$TEST_DIR/../lib/common.sh"

tests_run=0

pass() {
  tests_run=$((tests_run + 1))
}

expect_success() {
  local description=$1
  shift
  if ("$@" >/dev/null 2>&1); then
    pass
  else
    printf 'FAIL: expected success: %s\n' "$description" >&2
    exit 1
  fi
}

expect_failure() {
  local description=$1
  shift
  if ("$@" >/dev/null 2>&1); then
    printf 'FAIL: expected failure: %s\n' "$description" >&2
    exit 1
  fi
  pass
}

make_gpu_csv() {
  local count=$1
  local name=${2:-NVIDIA H100 80GB HBM3}
  local memory=${3:-81559}
  local index
  for ((index = 0; index < count; index++)); do
    printf '%s, %s\n' "$name" "$memory"
  done
}

temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT

printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"$temporary_directory/ubuntu-24.04"
printf 'ID=ubuntu\nVERSION_ID="22.04"\n' >"$temporary_directory/ubuntu-22.04"
mkdir "$temporary_directory/data-dir"
ln -s "$temporary_directory/data-dir" "$temporary_directory/data-link"

expect_success "Ubuntu 24.04 is accepted" validate_ubuntu_2404 "$temporary_directory/ubuntu-24.04"
expect_failure "Ubuntu 22.04 is rejected" validate_ubuntu_2404 "$temporary_directory/ubuntu-22.04"
canonical_repo_dir=$(realpath "$TEST_DIR/..")
expect_success "canonical data directory" canonicalize_data_directory "$canonical_repo_dir"
expect_failure "symlinked data directory" canonicalize_data_directory "$temporary_directory/data-link"
expect_success "x86_64 is accepted" validate_architecture x86_64
expect_failure "arm64 is rejected" validate_architecture arm64

for address in 127.0.0.1 0.0.0.0 10.0.4.12 192.168.1.20; do
  expect_success "valid IPv4 ${address}" validate_ipv4_address "$address"
done
for address in localhost 10.1.2 10.1.2.999 '10.1.2.-1'; do
  expect_failure "invalid IPv4 ${address}" validate_ipv4_address "$address"
done

expect_success "valid API port" validate_port 8000
expect_failure "zero port" validate_port 0
expect_failure "too-large port" validate_port 65536
expect_failure "internal port collision" validate_port "$INTERNAL_PORT"

expect_success "minimum context" validate_context_length 8192
expect_success "default context" validate_context_length "$DEFAULT_CONTEXT_LENGTH"
expect_success "custom larger context" validate_context_length 262144
expect_failure "zero context" validate_context_length 0

expect_success "generated-style API key" validate_access_value 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
expect_failure "short API key" validate_access_value short
expect_failure "unsafe API key characters" validate_access_value '01234567890123456789012345678901"bad'

valid_gpus=$(make_gpu_csv 8)
seven_gpus=$(make_gpu_csv 7)
wrong_gpu=$(make_gpu_csv 8 'NVIDIA A100-SXM4-80GB')
small_gpu=$(make_gpu_csv 8 'NVIDIA H100 PCIe' 64000)
expect_success "eight H100 80 GB GPUs" validate_gpu_csv "$valid_gpus"
expect_failure "seven GPUs" validate_gpu_csv "$seven_gpus"
expect_failure "wrong GPU family" validate_gpu_csv "$wrong_gpu"
expect_failure "insufficient GPU memory" validate_gpu_csv "$small_gpu"

expect_success "current SGLang CUDA driver" validate_driver_version 580.82.07
expect_failure "older SGLang CUDA driver" validate_driver_version 575.57.08
expect_success "newer NVIDIA driver" validate_driver_version 580.82.07
expect_success "minimum CUDA 13.0 Update 2 driver" validate_driver_version 580.95.05 580.95.05
expect_failure "older CUDA 13.0 driver" validate_driver_version 580.82.07 580.95.05
expect_failure "older NVIDIA driver" validate_driver_version 570.172.08
expect_failure "malformed NVIDIA driver" validate_driver_version unknown
expect_success "SGLang runtime" validate_runtime sglang
expect_success "vLLM runtime" validate_runtime vllm
expect_failure "unknown runtime" validate_runtime other
expect_success "single-line model ID" validate_model_value Model org/model-name
expect_failure "empty model ID" validate_model_value Model ''
expect_failure "multiline model ID" validate_model_value Model $'org/model\nbad'
expect_success "Hugging Face model ID" validate_huggingface_model_id org/model-name
expect_failure "local model path" validate_huggingface_model_id /models/model-name
expect_success "full immutable model revision" validate_model_revision 0123456789abcdef0123456789abcdef01234567
expect_failure "mutable model revision" validate_model_revision main
expect_failure "abbreviated model revision" validate_model_revision 0123456789abcdef

required_capacity_kib=$((MIN_DATA_GIB * 1024 * 1024))
expect_success "fresh filesystem capacity" validate_effective_capacity_kib "$required_capacity_kib" 0
expect_success "rerun credits existing model cache" validate_effective_capacity_kib $((200 * 1024 * 1024)) $((400 * 1024 * 1024))
expect_failure "combined storage remains too small" validate_effective_capacity_kib $((100 * 1024 * 1024)) $((400 * 1024 * 1024))

printf '%s\n' '# optional tuning' '--dtype' 'bfloat16' >"$temporary_directory/runtime-args"
printf '%s\n' '--api-key=unsafe' >"$temporary_directory/runtime-args-reserved"
printf '%s\n' '--hos' '0.0.0.0' >"$temporary_directory/runtime-args-abbreviated"
printf '%s\n' '--api_key=unsafe' >"$temporary_directory/runtime-args-underscore"
printf '%s\n' '-tp' '1' >"$temporary_directory/runtime-args-short"
printf '%s\n' '-m' 'unsafe/model' >"$temporary_directory/runtime-args-other-short"
printf '%s\n' '--config' '/tmp/unsafe.json' >"$temporary_directory/runtime-args-config"
printf '%s\r\n' '--dtype' >"$temporary_directory/runtime-args-crlf"
expect_success "safe runtime arguments" validate_runtime_args_file "$temporary_directory/runtime-args"
expect_failure "managed runtime argument" validate_runtime_args_file "$temporary_directory/runtime-args-reserved"
expect_failure "abbreviated managed runtime argument" validate_runtime_args_file "$temporary_directory/runtime-args-abbreviated"
expect_failure "underscore managed runtime argument" validate_runtime_args_file "$temporary_directory/runtime-args-underscore"
expect_failure "short managed runtime argument" validate_runtime_args_file "$temporary_directory/runtime-args-short"
expect_failure "single-dash runtime argument" validate_runtime_args_file "$temporary_directory/runtime-args-other-short"
expect_failure "runtime configuration override" validate_runtime_args_file "$temporary_directory/runtime-args-config"
expect_failure "non-Unix runtime arguments" validate_runtime_args_file "$temporary_directory/runtime-args-crlf"

printf 'PASS: %d checks\n' "$tests_run"
