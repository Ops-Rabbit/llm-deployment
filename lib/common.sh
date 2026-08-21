#!/usr/bin/env bash

SGLANG_IMAGE_TAG="lmsysorg/sglang:latest"
VLLM_IMAGE_TAG="vllm/vllm-openai:latest"
LLAMACPP_IMAGE_TAG="ghcr.io/ggml-org/llama.cpp:server-cuda"
NVIDIA_TOOLKIT_VERSION="1.19.1-1"
MIN_DATA_GIB=600
MIN_DOCKER_FREE_GIB=80
REQUIRED_GPU_COUNT=8
MIN_GPU_MEMORY_MIB=79000
REQUIRED_GPU_NAME="H100"
MIN_COMPUTE_CAPABILITY=""
MIN_SYSTEM_MEMORY_MIB=0
MIN_DRIVER_VERSION="580.82.07"
DEFAULT_CONTEXT_LENGTH=131072
DEFAULT_LISTEN_ADDRESS="127.0.0.1"
DEFAULT_PORT=8000
INTERNAL_PORT=30000
BACKEND_SOCKET="/run/opsrabbit-llm/backend.sock"

log() {
  printf '[opsrabbit-llm] %s\n' "$*"
}

warn() {
  printf '[opsrabbit-llm] WARNING: %s\n' "$*" >&2
}

die() {
  printf '[opsrabbit-llm] ERROR: %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

validate_ubuntu_2404() {
  local os_release_file=${1:-/etc/os-release}

  [[ -r "$os_release_file" ]] || die "Cannot read ${os_release_file}."

  local id version_id
  id=$(sed -n 's/^ID=//p' "$os_release_file" | tr -d '"')
  version_id=$(sed -n 's/^VERSION_ID=//p' "$os_release_file" | tr -d '"')

  [[ "$id" == "ubuntu" && "$version_id" == "24.04" ]] ||
    die "Ubuntu 24.04 LTS is required; found ${id:-unknown} ${version_id:-unknown}."
}

validate_architecture() {
  local architecture=${1:-$(uname -m)}
  [[ "$architecture" == "x86_64" ]] ||
    die "x86_64 is required; found ${architecture}."
}

validate_ipv4_address() {
  local address=$1
  local octets=()
  local octet

  [[ "$address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die "Listen address must be an IPv4 address; received ${address}."

  IFS='.' read -r -a octets <<<"$address"
  [[ ${#octets[@]} -eq 4 ]] || die "Invalid IPv4 address: ${address}."
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] || die "Invalid IPv4 address: ${address}."
    ((10#$octet <= 255)) || die "Invalid IPv4 address: ${address}."
  done
}

validate_port() {
  local port=$1
  [[ "$port" =~ ^[0-9]+$ ]] || die "Port must be a number."
  ((port >= 1 && port <= 65535)) || die "Port must be between 1 and 65535."
  ((port != INTERNAL_PORT)) || die "Port ${INTERNAL_PORT} is reserved for the internal model server."
}

validate_context_length() {
  local context_length=$1
  [[ "$context_length" =~ ^[0-9]+$ ]] || die "Context length must be a number."
  ((context_length > 0)) || die "Context length must be a positive number."
}

validate_runtime() {
  local runtime=$1
  [[ "$runtime" == "sglang" || "$runtime" == "vllm" || "$runtime" == "llamacpp" ]] ||
    die "Runtime must be sglang, vllm, or llamacpp; received ${runtime}."
}

validate_model_value() {
  local label=$1
  local value=$2
  [[ -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* ]] ||
    die "${label} must be a non-empty single-line value."
}

validate_huggingface_model_id() {
  local model_id=$1
  [[ "$model_id" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] ||
    die "Model must be a Hugging Face ID in organization/name form."
}

validate_model_revision() {
  local revision=$1
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] ||
    die "Model revision must be a full 40-character lowercase commit hash."
}

canonicalize_data_directory() {
  local requested_path=$1
  [[ -d "$requested_path" ]] || die "Data directory does not exist: ${requested_path}. Create and mount it first."

  local normalized_path=${requested_path%/}
  [[ -n "$normalized_path" ]] || normalized_path="/"
  local canonical_path
  canonical_path=$(realpath "$requested_path") || die "Could not resolve data directory: ${requested_path}."
  [[ "$normalized_path" == "$canonical_path" ]] ||
    die "Data directory must be a canonical path with no symbolic links or parent-directory segments; use ${canonical_path}."
  printf '%s\n' "$canonical_path"
}

validate_runtime_args_file() {
  local args_file=$1
  [[ -r "$args_file" ]] || die "Cannot read runtime arguments file: ${args_file}."

  if LC_ALL=C tr -d '\11\12\40-\176' <"$args_file" | grep -q .; then
    die "Runtime arguments file must contain printable ASCII with one argument per line."
  fi

  local runtime_arg runtime_option managed_option
  local managed_options=(
    --api-key --admin-api-key --host --port --model --model-path --revision --served-model-name
    --tensor-parallel-size --tp --tp-size --context-length --max-model-len
    --mem-fraction-static --gpu-memory-utilization --trust-remote-code --log-level
    --config --uds --api-key-file --alias --ctx-size --gpu-layers --n-gpu-layers
    --tensor-split
  )
  while IFS= read -r runtime_arg || [[ -n "$runtime_arg" ]]; do
    [[ -z "$runtime_arg" || "$runtime_arg" == \#* ]] && continue
    runtime_option=${runtime_arg%%=*}
    runtime_option=${runtime_option//_/-}
    if [[ "$runtime_option" == "-tp" ]]; then
      runtime_option="--tp"
    fi
    if [[ "$runtime_option" =~ ^-[A-Za-z] ]]; then
      die "Single-dash runtime option ${runtime_arg} is not allowed; use its full double-dash name."
    fi
    if [[ "$runtime_option" == --* ]]; then
      for managed_option in "${managed_options[@]}"; do
        if [[ "$managed_option" == "$runtime_option"* ]]; then
          die "Runtime argument ${runtime_arg} is or abbreviates an installer-managed option and cannot be used."
        fi
      done
    fi
  done <"$args_file"
}

validate_positive_integer() {
  local label=$1
  local value=$2
  [[ "$value" =~ ^[0-9]+$ ]] && ((value > 0)) || die "${label} must be a positive integer."
}

validate_nonnegative_integer() {
  local label=$1
  local value=$2
  [[ "$value" =~ ^[0-9]+$ ]] || die "${label} must be a non-negative integer."
}

validate_access_value() {
  local access_value=$1
  ((${#access_value} >= 32 && ${#access_value} <= 256)) ||
    die "API key must contain 32-256 URL-safe characters."
  [[ "$access_value" =~ ^[A-Za-z0-9._~-]+$ ]] ||
    die "API key must contain 32-256 URL-safe characters."
}

directory_mode_is_protected() {
  local mode=$1
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  (((8#$mode & 8#022) == 0))
}

validate_data_directory() {
  local data_dir=$1
  local model_cache_dir=${2:-}
  [[ "$data_dir" == /* ]] || die "Data directory must be an absolute path."
  [[ -d "$data_dir" ]] || die "Data directory does not exist: ${data_dir}. Create and mount it first."
  [[ "$data_dir" != "/" ]] || die "The filesystem root cannot be used as the data directory."

  local protected_path owner_uid mode
  protected_path=$data_dir
  while true; do
    [[ ! -L "$protected_path" ]] || die "Data path ancestor cannot be a symbolic link: ${protected_path}."
    [[ -d "$protected_path" ]] || die "Data path ancestor must be a directory: ${protected_path}."
    owner_uid=$(stat -c '%u' "$protected_path")
    mode=$(stat -c '%a' "$protected_path")
    [[ "$owner_uid" == "0" ]] || die "Every data path ancestor must be owned by root: ${protected_path}."
    directory_mode_is_protected "$mode" ||
      die "Data path ancestors must not be writable by group or other users: ${protected_path}."
    [[ "$protected_path" == "/" ]] && break
    protected_path=$(dirname -- "$protected_path")
  done

  for protected_path in "$data_dir/huggingface" "$data_dir/torch" "$data_dir/sglang" "$data_dir/llamacpp"; do
    [[ -e "$protected_path" || -L "$protected_path" ]] || continue
    [[ ! -L "$protected_path" ]] || die "Data path cannot be a symbolic link: ${protected_path}."
    [[ -d "$protected_path" ]] || die "Data path must be a directory: ${protected_path}."
    owner_uid=$(stat -c '%u' "$protected_path")
    mode=$(stat -c '%a' "$protected_path")
    [[ "$owner_uid" == "0" ]] || die "Data path must be owned by root: ${protected_path}."
    directory_mode_is_protected "$mode" ||
      die "Data path must not be writable by group or other users: ${protected_path}."
  done

  local available_kib cache_kib=0 cache_path cache_path_kib
  available_kib=$(df -Pk "$data_dir" | awk 'NR == 2 {print $4}')
  [[ "$available_kib" =~ ^[0-9]+$ ]] || die "Could not determine free space for ${data_dir}."
  if [[ -n "$model_cache_dir" && -d "$model_cache_dir" ]]; then
    cache_path=$model_cache_dir
    cache_path_kib=$(du -skL "$cache_path" | awk '{print $1}')
    [[ "$cache_path_kib" =~ ^[0-9]+$ ]] || die "Could not measure the selected model cache."
    cache_kib=$cache_path_kib
  fi
  validate_effective_capacity_kib "$available_kib" "$cache_kib"
}

validate_docker_storage() {
  local docker_root=$1
  local minimum_gib=${2:-$MIN_DOCKER_FREE_GIB}
  [[ -d "$docker_root" ]] || die "Docker data root does not exist: ${docker_root}."

  local available_kib required_kib
  available_kib=$(df -Pk "$docker_root" | awk 'NR == 2 {print $4}')
  [[ "$available_kib" =~ ^[0-9]+$ ]] || die "Could not determine free space for Docker data root ${docker_root}."
  required_kib=$((minimum_gib * 1024 * 1024))
  ((available_kib >= required_kib)) ||
    die "Docker data root ${docker_root} needs at least ${minimum_gib} GiB free for the latest runtime image; only $((available_kib / 1024 / 1024)) GiB is available."
}

validate_effective_capacity_kib() {
  local available_kib=$1
  local existing_cache_kib=$2
  local required_kib=$((MIN_DATA_GIB * 1024 * 1024))
  local effective_kib=$((available_kib + existing_cache_kib))

  ((effective_kib >= required_kib)) ||
    die "The data filesystem needs ${MIN_DATA_GIB} GiB across free space and existing OpsRabbit model cache; only $((effective_kib / 1024 / 1024)) GiB is available."
}

validate_gpu_csv() {
  local gpu_csv=$1
  local count=0
  local name memory

  while IFS=',' read -r name memory; do
    [[ -n "${name//[[:space:]]/}" ]] || continue
    name=${name#"${name%%[![:space:]]*}"}
    name=${name%"${name##*[![:space:]]}"}
    memory=${memory//[[:space:]]/}
    ((count += 1))
    if [[ -n "$REQUIRED_GPU_NAME" ]]; then
      [[ "$name" == *"$REQUIRED_GPU_NAME"* ]] ||
        die "GPU ${count} is ${name}; its name must contain ${REQUIRED_GPU_NAME}."
    fi
    [[ "$memory" =~ ^[0-9]+$ ]] || die "Could not read memory for GPU ${count}."
    ((memory >= MIN_GPU_MEMORY_MIB)) ||
      die "GPU ${count} has ${memory} MiB; at least ${MIN_GPU_MEMORY_MIB} MiB is required."
  done <<<"$gpu_csv"

  ((count == REQUIRED_GPU_COUNT)) ||
    die "Exactly ${REQUIRED_GPU_COUNT} matching GPUs are required; found ${count}."
}

validate_compute_capability_csv() {
  local capability_csv=$1
  local minimum=$2
  local count=0 capability
  local minimum_major minimum_minor capability_major capability_minor

  [[ "$minimum" =~ ^[0-9]+\.[0-9]+$ ]] ||
    die "Invalid minimum GPU compute capability: ${minimum}."
  IFS='.' read -r minimum_major minimum_minor <<<"$minimum"

  while IFS= read -r capability; do
    capability=${capability//[[:space:]]/}
    [[ -n "$capability" ]] || continue
    ((count += 1))
    [[ "$capability" =~ ^[0-9]+\.[0-9]+$ ]] ||
      die "Could not read compute capability for GPU ${count}."
    IFS='.' read -r capability_major capability_minor <<<"$capability"
    ((10#$capability_major > 10#$minimum_major ||
      (10#$capability_major == 10#$minimum_major && 10#$capability_minor >= 10#$minimum_minor))) ||
      die "GPU ${count} has compute capability ${capability}; ${minimum} or newer is required."
  done <<<"$capability_csv"

  ((count == REQUIRED_GPU_COUNT)) ||
    die "Could not verify compute capability for all ${REQUIRED_GPU_COUNT} GPUs."
}

validate_system_memory() {
  local minimum_mib=$1
  local meminfo_file=${2:-/proc/meminfo}
  ((minimum_mib == 0)) && return 0
  [[ -r "$meminfo_file" ]] || die "Cannot read system memory information from ${meminfo_file}."

  local total_kib
  total_kib=$(awk '/^MemTotal:/ {print $2; exit}' "$meminfo_file")
  [[ "$total_kib" =~ ^[0-9]+$ ]] || die "Could not determine total system memory."
  ((total_kib >= minimum_mib * 1024)) ||
    die "At least ${minimum_mib} MiB of system memory is required; found $((total_kib / 1024)) MiB."
}

validate_gpu_profile() {
  command_exists nvidia-smi || die "nvidia-smi is missing. Install a working NVIDIA driver before running this installer."

  local gpu_csv
  gpu_csv=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits) ||
    die "nvidia-smi failed. Fix the NVIDIA driver before continuing."
  validate_gpu_csv "$gpu_csv"

  if [[ -n "$MIN_COMPUTE_CAPABILITY" ]]; then
    local capability_csv
    capability_csv=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader,nounits) ||
      die "Could not read GPU compute capability."
    validate_compute_capability_csv "$capability_csv" "$MIN_COMPUTE_CAPABILITY"
  fi

  local driver_version
  driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1 | tr -d '[:space:]') ||
    die "Could not read the NVIDIA driver version."
  validate_driver_version "$driver_version"
}

validate_driver_version() {
  local version=$1
  local minimum=${2:-$MIN_DRIVER_VERSION}
  local version_major version_minor version_patch
  local minimum_major minimum_minor minimum_patch

  IFS='.' read -r version_major version_minor version_patch <<<"$version"
  IFS='.' read -r minimum_major minimum_minor minimum_patch <<<"$minimum"
  version_patch=${version_patch:-0}
  minimum_patch=${minimum_patch:-0}

  [[ "$version_major" =~ ^[0-9]+$ && "$version_minor" =~ ^[0-9]+$ && "$version_patch" =~ ^[0-9]+$ ]] ||
    die "Invalid NVIDIA driver version: ${version}."

  if ((10#$version_major > 10#$minimum_major)); then
    return 0
  fi
  if ((10#$version_major == 10#$minimum_major && 10#$version_minor > 10#$minimum_minor)); then
    return 0
  fi
  if ((10#$version_major == 10#$minimum_major && 10#$version_minor == 10#$minimum_minor && 10#$version_patch >= 10#$minimum_patch)); then
    return 0
  fi
  die "NVIDIA driver ${minimum} or newer is required for the selected runtime; found ${version}."
}

port_is_listening() {
  local address=$1
  local port=$2
  command_exists ss || return 1
  ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|\[|:)${address//./\\.}:${port}$|(^|:)${port}$"
}

run_preflight() {
  local data_dir=$1
  local listen_address=$2
  local port=$3
  local context_length=$4
  local model_cache_dir=${5:-}

  validate_ubuntu_2404
  validate_architecture
  validate_ipv4_address "$listen_address"
  validate_port "$port"
  validate_context_length "$context_length"
  validate_system_memory "$MIN_SYSTEM_MEMORY_MIB"
  validate_data_directory "$data_dir" "$model_cache_dir"
  validate_gpu_profile
}
