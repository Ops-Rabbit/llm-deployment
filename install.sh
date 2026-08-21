#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/profiles.sh
source "$SCRIPT_DIR/lib/profiles.sh"

DATA_DIR=""
PROFILE=""
MODEL_WAS_SET=false
REVISION_WAS_SET=false
SERVED_NAME_WAS_SET=false
TRUST_WAS_SET=false
RUNTIME_ARGS_FILE=""
LISTEN_ADDRESS=$DEFAULT_LISTEN_ADDRESS
PORT=$DEFAULT_PORT
MTP_ENABLED=false
CHECK_ONLY=false
ACCESS_FILE=""
STARTUP_TIMEOUT=14400
ORIGINAL_ARGS=("$@")

usage() {
  cat <<'EOF'
Install a selected model profile with an authenticated OpenAI-compatible API.

Usage:
  sudo ./install.sh --profile NAME --data-dir PATH [options]
  ./install.sh --profile NAME --data-dir PATH --check-only [options]

Required:
  --profile NAME            Deployment profile; run --list-profiles to view choices
  --data-dir PATH           Existing mounted directory meeting the selected profile

Options:
  --list-profiles           Print available profiles and exit
  --runtime NAME            sglang, vllm, or llamacpp
  --model ID                Hugging Face model ID
  --model-revision REV      Required pinned revision for a custom model
  --served-model-name NAME  Model name exposed by the API
  --runtime-args-file PATH  Extra runtime arguments, one argument per line
  --trust-remote-code       Allow custom model repository code
  --gpu-count COUNT         Required GPU count (profile default when omitted)
  --gpu-name TEXT           Optional required GPU-name substring
  --min-gpu-memory-mib MIB  Minimum memory per GPU
  --min-system-memory-mib N Minimum host memory in MiB
  --min-data-gib GIB        Free space plus existing selected-model cache
  --min-docker-free-gib GIB Free space required in Docker data root (default: 80)
  --listen-address IPv4     API bind address (default: 127.0.0.1)
  --port PORT               API port (default: 8000)
  --context-length TOKENS   Model context window (profile default when omitted)
  --api-key-file PATH       Read an existing API key from a file
  --enable-mtp              Enable experimental MTP speculative decoding
  --startup-timeout SEC     Wait up to this many seconds for readiness (default: 14400)
  --check-only              Run hardware and storage checks without changing the host
  -h, --help                Show this help

The installer does not provision cloud resources, configure firewalls, format
disks, or install NVIDIA drivers.
EOF
}

for ((argument_index = 0; argument_index < ${#ORIGINAL_ARGS[@]}; argument_index++)); do
  if [[ "${ORIGINAL_ARGS[$argument_index]}" == "--list-profiles" ]]; then
    list_profiles
    exit 0
  fi
  if [[ "${ORIGINAL_ARGS[$argument_index]}" == "-h" || "${ORIGINAL_ARGS[$argument_index]}" == "--help" ]]; then
    usage
    exit 0
  fi
  if [[ "${ORIGINAL_ARGS[$argument_index]}" == "--profile" ]]; then
    ((argument_index + 1 < ${#ORIGINAL_ARGS[@]})) || die "--profile requires a value."
    PROFILE=${ORIGINAL_ARGS[$((argument_index + 1))]}
  fi
done

[[ -n "$PROFILE" ]] || die "--profile is required. Run --list-profiles to view available model profiles."
load_profile "$PROFILE"
RUNTIME=$PROFILE_DEFAULT_RUNTIME
MODEL_ID=$PROFILE_MODEL_ID
MODEL_REVISION=$PROFILE_MODEL_REVISION
SERVED_MODEL_NAME=$PROFILE_SERVED_MODEL_NAME
MODEL_FAMILY=$PROFILE_MODEL_FAMILY
ALLOWED_RUNTIMES=$PROFILE_ALLOWED_RUNTIMES
REQUIRED_GPU_COUNT=$PROFILE_GPU_COUNT
REQUIRED_GPU_NAME=$PROFILE_GPU_NAME
MIN_GPU_MEMORY_MIB=$PROFILE_MIN_GPU_MEMORY_MIB
MIN_COMPUTE_CAPABILITY=$PROFILE_MIN_COMPUTE_CAPABILITY
MIN_SYSTEM_MEMORY_MIB=$PROFILE_MIN_SYSTEM_MEMORY_MIB
MIN_DATA_GIB=$PROFILE_MIN_DATA_GIB
CONTEXT_LENGTH=$PROFILE_CONTEXT_LENGTH
TRUST_REMOTE_CODE=$PROFILE_TRUST_REMOTE_CODE
GGUF_FILES=("${PROFILE_GGUF_FILES[@]}")
GGUF_FILENAME=${GGUF_FILES[0]-}
MTP_MODE=$PROFILE_MTP_MODE

while (($#)); do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || die "--profile requires a value."
      PROFILE=$2
      shift 2
      ;;
    --list-profiles)
      shift
      ;;
    --runtime)
      [[ $# -ge 2 ]] || die "--runtime requires a value."
      RUNTIME=$2
      shift 2
      ;;
    --model)
      [[ $# -ge 2 ]] || die "--model requires a value."
      MODEL_ID=$2
      MODEL_WAS_SET=true
      shift 2
      ;;
    --model-revision)
      [[ $# -ge 2 ]] || die "--model-revision requires a value."
      MODEL_REVISION=$2
      REVISION_WAS_SET=true
      shift 2
      ;;
    --served-model-name)
      [[ $# -ge 2 ]] || die "--served-model-name requires a value."
      SERVED_MODEL_NAME=$2
      SERVED_NAME_WAS_SET=true
      shift 2
      ;;
    --runtime-args-file)
      [[ $# -ge 2 ]] || die "--runtime-args-file requires a value."
      RUNTIME_ARGS_FILE=$2
      shift 2
      ;;
    --trust-remote-code)
      TRUST_REMOTE_CODE=true
      TRUST_WAS_SET=true
      shift
      ;;
    --gpu-count)
      [[ $# -ge 2 ]] || die "--gpu-count requires a value."
      REQUIRED_GPU_COUNT=$2
      shift 2
      ;;
    --gpu-name)
      [[ $# -ge 2 ]] || die "--gpu-name requires a value."
      REQUIRED_GPU_NAME=$2
      shift 2
      ;;
    --min-gpu-memory-mib)
      [[ $# -ge 2 ]] || die "--min-gpu-memory-mib requires a value."
      MIN_GPU_MEMORY_MIB=$2
      shift 2
      ;;
    --min-system-memory-mib)
      [[ $# -ge 2 ]] || die "--min-system-memory-mib requires a value."
      MIN_SYSTEM_MEMORY_MIB=$2
      shift 2
      ;;
    --min-data-gib)
      [[ $# -ge 2 ]] || die "--min-data-gib requires a value."
      MIN_DATA_GIB=$2
      shift 2
      ;;
    --min-docker-free-gib)
      [[ $# -ge 2 ]] || die "--min-docker-free-gib requires a value."
      MIN_DOCKER_FREE_GIB=$2
      shift 2
      ;;
    --data-dir)
      [[ $# -ge 2 ]] || die "--data-dir requires a value."
      DATA_DIR=$2
      shift 2
      ;;
    --listen-address)
      [[ $# -ge 2 ]] || die "--listen-address requires a value."
      LISTEN_ADDRESS=$2
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || die "--port requires a value."
      PORT=$2
      shift 2
      ;;
    --context-length)
      [[ $# -ge 2 ]] || die "--context-length requires a value."
      CONTEXT_LENGTH=$2
      shift 2
      ;;
    --api-key-file)
      [[ $# -ge 2 ]] || die "--api-key-file requires a value."
      ACCESS_FILE=$2
      shift 2
      ;;
    --startup-timeout)
      [[ $# -ge 2 ]] || die "--startup-timeout requires a value."
      STARTUP_TIMEOUT=$2
      shift 2
      ;;
    --enable-mtp)
      MTP_ENABLED=true
      shift
      ;;
    --check-only)
      CHECK_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[[ -n "$DATA_DIR" ]] || die "--data-dir is required."
DATA_DIR=$(canonicalize_data_directory "$DATA_DIR")
[[ "$STARTUP_TIMEOUT" =~ ^[0-9]+$ ]] || die "Startup timeout must be a non-negative number."
if [[ "$PROFILE_REQUIRES_CUSTOM_MODEL" == "true" && "$MODEL_WAS_SET" != "true" ]]; then
  die "Profile ${PROFILE} requires --model and --model-revision because no community INT4 checkpoint is trusted as a built-in default yet."
fi
validate_runtime "$RUNTIME"
validate_model_value "Model" "$MODEL_ID"
validate_huggingface_model_id "$MODEL_ID"
validate_positive_integer "GPU count" "$REQUIRED_GPU_COUNT"
validate_positive_integer "Minimum GPU memory" "$MIN_GPU_MEMORY_MIB"
validate_nonnegative_integer "Minimum system memory" "$MIN_SYSTEM_MEMORY_MIB"
validate_positive_integer "Minimum data size" "$MIN_DATA_GIB"
validate_positive_integer "Minimum Docker free space" "$MIN_DOCKER_FREE_GIB"
if [[ -n "$REQUIRED_GPU_NAME" ]]; then
  validate_model_value "GPU name substring" "$REQUIRED_GPU_NAME"
fi

if [[ "$MODEL_WAS_SET" == "true" && "$MODEL_ID" != "$PROFILE_MODEL_ID" ]]; then
  [[ "$REVISION_WAS_SET" == "true" ]] ||
    die "A custom model requires --model-revision so deployments remain reproducible."
  if [[ "$PROFILE_PRESERVE_FAMILY_ON_MODEL_OVERRIDE" != "true" ]]; then
    MODEL_FAMILY="custom"
    ALLOWED_RUNTIMES="sglang vllm"
    PROFILE_SGLANG_ARGS=()
    PROFILE_SGLANG_ENV=()
    PROFILE_VLLM_ARGS=()
    PROFILE_VLLM_ENV=()
    PROFILE_LLAMACPP_ARGS=()
    PROFILE_LLAMACPP_ENV=()
  fi
  if [[ "$TRUST_WAS_SET" != "true" ]]; then
    TRUST_REMOTE_CODE=false
  fi
  if [[ "$SERVED_NAME_WAS_SET" != "true" ]]; then
    SERVED_MODEL_NAME=${MODEL_ID##*/}
  fi
fi
if ((${#GGUF_FILES[@]})) && [[ "$MODEL_ID" != "$PROFILE_MODEL_ID" ]]; then
  die "A GGUF profile cannot override its model repository. Add a new profile with the pinned GGUF filename instead."
fi
validate_model_value "Served model name" "$SERVED_MODEL_NAME"
validate_model_value "Model revision" "$MODEL_REVISION"
validate_model_revision "$MODEL_REVISION"
[[ "$SERVED_MODEL_NAME" =~ ^[A-Za-z0-9._-]+$ ]] ||
  die "Served model name may contain only letters, numbers, dot, underscore, and hyphen."

if [[ -n "$RUNTIME_ARGS_FILE" ]]; then
  validate_runtime_args_file "$RUNTIME_ARGS_FILE"
fi

runtime_is_allowed "$RUNTIME" "$ALLOWED_RUNTIMES" ||
  die "Profile ${PROFILE} supports runtime(s) ${ALLOWED_RUNTIMES}; received ${RUNTIME}."

case "$RUNTIME" in
  sglang)
    RUNTIME_IMAGE_TAG=$SGLANG_IMAGE_TAG
    MIN_DRIVER_VERSION="580.82.07"
    ;;
  vllm)
    RUNTIME_IMAGE_TAG=$VLLM_IMAGE_TAG
    MIN_DRIVER_VERSION="580.95.05"
    ;;
  llamacpp)
    RUNTIME_IMAGE_TAG=$LLAMACPP_IMAGE_TAG
    MIN_DRIVER_VERSION="570.26.00"
    ((${#GGUF_FILES[@]})) ||
      die "llamacpp requires a profile with pinned GGUF files."
    ;;
esac

if [[ "$MTP_ENABLED" == "true" && "$MTP_MODE" != "sglang-eagle" ]]; then
  die "--enable-mtp is not supported by profile ${PROFILE}."
fi

if [[ "$CHECK_ONLY" != "true" && "$EUID" -ne 0 ]]; then
  command_exists sudo || die "Run this installer as root or install sudo."
  exec sudo -- "$0" "${ORIGINAL_ARGS[@]}"
fi

runtime_args_staged=false
if [[ "$CHECK_ONLY" != "true" && -n "$RUNTIME_ARGS_FILE" ]]; then
  install -d -m 0755 /etc/opsrabbit-llm
  install -m 0600 "$RUNTIME_ARGS_FILE" /etc/opsrabbit-llm/runtime.args.pending
  validate_runtime_args_file /etc/opsrabbit-llm/runtime.args.pending
  RUNTIME_ARGS_FILE="/etc/opsrabbit-llm/runtime.args.pending"
  runtime_args_staged=true
fi

model_cache_dir="$DATA_DIR/huggingface/${MODEL_ID//\//--}/$MODEL_REVISION"

gpu_description="NVIDIA GPU"
if [[ -n "$REQUIRED_GPU_NAME" ]]; then
  gpu_description=$REQUIRED_GPU_NAME
fi
log "Selected profile ${PROFILE}: ${RUNTIME}, ${MODEL_ID}@${MODEL_REVISION}, ${REQUIRED_GPU_COUNT}x ${gpu_description}, ${CONTEXT_LENGTH}-token context."
log "Running preflight checks. No NVIDIA driver will be installed or changed."
run_preflight "$DATA_DIR" "$LISTEN_ADDRESS" "$PORT" "$CONTEXT_LENGTH" "$model_cache_dir"

if [[ "$RUNTIME" == "sglang" ]] && port_is_listening 127.0.0.1 "$INTERNAL_PORT"; then
  managed_backend=false
  if command_exists docker &&
    docker port opsrabbit-llm-server "${INTERNAL_PORT}/tcp" 2>/dev/null |
      grep -qx "127.0.0.1:${INTERNAL_PORT}"; then
    managed_backend=true
  fi
  [[ "$managed_backend" == "true" ]] ||
    die "Internal port ${INTERNAL_PORT} is already in use by another process. Stop it before installation."
fi

if [[ "$CHECK_ONLY" == "true" ]]; then
  log "Preflight passed: Ubuntu 24.04, x86_64, GPU profile, storage, and network settings are valid."
  exit 0
fi

existing_port=""
existing_listen_address=""
if [[ -r /etc/opsrabbit-llm/install.conf ]]; then
  existing_port=$(sed -n 's/^PORT=//p' /etc/opsrabbit-llm/install.conf)
  existing_listen_address=$(sed -n 's/^LISTEN_ADDRESS=//p' /etc/opsrabbit-llm/install.conf)
fi
if { [[ "$existing_port" != "$PORT" ]] || [[ "$existing_listen_address" != "$LISTEN_ADDRESS" ]]; } &&
  port_is_listening "$LISTEN_ADDRESS" "$PORT"; then
  die "Port ${PORT} is already in use. Choose another port or stop the existing service."
fi

if [[ -n "$ACCESS_FILE" ]]; then
  [[ -r "$ACCESS_FILE" ]] || die "Cannot read API key file: ${ACCESS_FILE}."
  ACCESS_VALUE=$(tr -d '\r\n' <"$ACCESS_FILE")
  validate_access_value "$ACCESS_VALUE"
elif [[ -r /etc/opsrabbit-llm/api-key ]]; then
  ACCESS_VALUE=$(< /etc/opsrabbit-llm/api-key)
  validate_access_value "$ACCESS_VALUE"
else
  command_exists openssl || {
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y openssl
  }
  ACCESS_VALUE=$(openssl rand -hex 32)
fi

log "Installing missing operating-system prerequisites."
export DEBIAN_FRONTEND=noninteractive
apt-get update
docker_preexisting=false
if command_exists docker; then
  systemctl cat docker.service >/dev/null 2>&1 ||
    die "An existing Docker installation was found without a systemd docker.service. Configure a supported Docker Engine before running this installer."
  systemctl start docker
  docker info >/dev/null || die "The existing Docker Engine is not usable. Fix it before running this installer."
  docker_preexisting=true
fi

base_packages=(ca-certificates curl gnupg2 jq openssl nginx)
if [[ "$docker_preexisting" != "true" ]]; then
  base_packages+=(docker.io)
fi
missing_packages=()
for package_name in "${base_packages[@]}"; do
  if ! dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q '^install ok installed$'; then
    missing_packages+=("$package_name")
  fi
done
if ((${#missing_packages[@]})); then
  apt-get install -y "${missing_packages[@]}"
fi
systemctl enable --now docker

if [[ -r /etc/opsrabbit-llm/admin-key ]]; then
  ADMIN_VALUE=$(< /etc/opsrabbit-llm/admin-key)
  validate_access_value "$ADMIN_VALUE"
else
  ADMIN_VALUE=$(openssl rand -hex 32)
fi

log "Ensuring NVIDIA Container Toolkit ${NVIDIA_TOOLKIT_VERSION} or newer is installed."
install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey |
  gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    >/etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update
toolkit_packages=(
  nvidia-container-toolkit
  nvidia-container-toolkit-base
  libnvidia-container-tools
  libnvidia-container1
)
toolkit_install_args=()
for package_name in "${toolkit_packages[@]}"; do
  installed_version=$(dpkg-query -W -f='${Version}' "$package_name" 2>/dev/null || true)
  if [[ -z "$installed_version" ]] || ! dpkg --compare-versions "$installed_version" ge "$NVIDIA_TOOLKIT_VERSION"; then
    toolkit_install_args+=("${package_name}=${NVIDIA_TOOLKIT_VERSION}")
  fi
done
if ((${#toolkit_install_args[@]})); then
  apt-get install -y "${toolkit_install_args[@]}"
fi

if docker info --format '{{json .Runtimes}}' | jq -e 'has("nvidia")' >/dev/null; then
  log "NVIDIA Docker runtime is already configured; leaving the Docker daemon running."
else
  unrelated_containers=$(docker ps --format '{{.Names}}' | grep -v '^opsrabbit-llm-server$' || true)
  if [[ -n "$unrelated_containers" ]]; then
    printf '%s\n' "$unrelated_containers" >&2
    die "Docker must restart to enable the NVIDIA runtime, but unrelated containers are running. Stop them during a maintenance window or configure the NVIDIA runtime yourself, then rerun the installer."
  fi
  systemctl stop opsrabbit-llm.service >/dev/null 2>&1 || true
  nvidia-ctk runtime configure --runtime=docker
  systemctl restart docker
fi

docker_root=$(docker info --format '{{.DockerRootDir}}')
validate_docker_storage "$docker_root" "$MIN_DOCKER_FREE_GIB"

log "Creating persistent model-cache directories."
install -d -m 0755 "$DATA_DIR/huggingface" "$DATA_DIR/torch" "$DATA_DIR/sglang" "$DATA_DIR/llamacpp"
install -d -m 0755 "$model_cache_dir"
install -d -m 0755 /etc/opsrabbit-llm
install -d -m 0755 /usr/local/lib/opsrabbit-llm /usr/local/sbin
install -d -o root -g www-data -m 2750 /run/opsrabbit-llm

log "Pulling the latest official ${RUNTIME} image. This image is large and may take several minutes."
docker pull "$RUNTIME_IMAGE_TAG"
RUNTIME_IMAGE=$(docker image inspect --format '{{index .RepoDigests 0}}' "$RUNTIME_IMAGE_TAG")
[[ "$RUNTIME_IMAGE" == *@sha256:* ]] || die "Could not resolve ${RUNTIME_IMAGE_TAG} to an immutable image digest."

log "Verifying that the latest runtime can access the selected GPU configuration."
if [[ "$RUNTIME" == "llamacpp" ]]; then
  docker run --rm --gpus all "$RUNTIME_IMAGE" --list-devices 2>&1 |
    grep -Fq 'CUDA' ||
    die "The latest llama.cpp runtime could not detect a CUDA device. A newer NVIDIA driver or a different runtime may be required."
else
  docker run --rm --gpus all --entrypoint python3 "$RUNTIME_IMAGE" \
    -c 'import sys, torch; expected=int(sys.argv[1]); assert torch.cuda.device_count() == expected, f"expected {expected} GPUs, found {torch.cuda.device_count()}"; [torch.ones(1, device=f"cuda:{index}").add_(1).cpu() for index in range(expected)]; [torch.cuda.synchronize(index) for index in range(expected)]' \
    "$REQUIRED_GPU_COUNT" ||
    die "The latest runtime could not execute a CUDA operation on every GPU. A newer NVIDIA driver or a different runtime may be required."
fi

log "Downloading the exact model revision into the persistent cache."
if [[ "$RUNTIME" == "llamacpp" ]]; then
  for gguf_file in "${GGUF_FILES[@]}"; do
    gguf_destination="$model_cache_dir/$gguf_file"
    gguf_partial="$gguf_destination.partial"
    gguf_url="https://huggingface.co/${MODEL_ID}/resolve/${MODEL_REVISION}/${gguf_file}?download=true"
    install -d -m 0755 "$(dirname -- "$gguf_destination")"
    if [[ ! -s "$gguf_destination" ]]; then
      curl --fail --location --retry 5 --continue-at - --output "$gguf_partial" "$gguf_url"
      mv -- "$gguf_partial" "$gguf_destination"
    fi
  done
else
  docker run --rm \
    --network bridge \
    --entrypoint python3 \
    --env HF_HUB_DISABLE_TELEMETRY=1 \
    --volume "$model_cache_dir:/root/.cache/huggingface" \
    "$RUNTIME_IMAGE" \
    -c 'import sys; from huggingface_hub import snapshot_download; snapshot_download(repo_id=sys.argv[1], revision=sys.argv[2])' \
    "$MODEL_ID" "$MODEL_REVISION"
fi

printf '%s\n' "$ACCESS_VALUE" >/etc/opsrabbit-llm/api-key
chmod 0600 /etc/opsrabbit-llm/api-key
printf '%s\n' "$ADMIN_VALUE" >/etc/opsrabbit-llm/admin-key
chmod 0600 /etc/opsrabbit-llm/admin-key
printf 'VLLM_API_KEY=%s\n' "$ACCESS_VALUE" >/etc/opsrabbit-llm/vllm.env
chmod 0600 /etc/opsrabbit-llm/vllm.env
jq -n --arg access "$ACCESS_VALUE" --arg admin "$ADMIN_VALUE" \
  '{"api-key": $access, "admin-api-key": $admin}' >/etc/opsrabbit-llm/sglang-auth.yaml
chmod 0600 /etc/opsrabbit-llm/sglang-auth.yaml
rm -f /etc/opsrabbit-llm/sglang-auth.json
printf 'header = "Authorization: Bearer %s"\n' "$ACCESS_VALUE" >/etc/opsrabbit-llm/curl.conf
chmod 0600 /etc/opsrabbit-llm/curl.conf

{
  printf 'DATA_DIR=%q\n' "$DATA_DIR"
  printf 'MODEL_CACHE_DIR=%q\n' "$model_cache_dir"
  printf 'CONTEXT_LENGTH=%q\n' "$CONTEXT_LENGTH"
  printf 'MTP_ENABLED=%q\n' "$MTP_ENABLED"
  printf 'MTP_MODE=%q\n' "$MTP_MODE"
  printf 'PROFILE=%q\n' "$PROFILE"
  printf 'RUNTIME=%q\n' "$RUNTIME"
  printf 'MODEL_FAMILY=%q\n' "$MODEL_FAMILY"
  printf 'GPU_COUNT=%q\n' "$REQUIRED_GPU_COUNT"
  printf 'TRUST_REMOTE_CODE=%q\n' "$TRUST_REMOTE_CODE"
  printf 'LISTEN_ADDRESS=%q\n' "$LISTEN_ADDRESS"
  printf 'PORT=%q\n' "$PORT"
  printf 'MODEL_ID=%q\n' "$MODEL_ID"
  printf 'MODEL_REVISION=%q\n' "$MODEL_REVISION"
  printf 'SERVED_MODEL_NAME=%q\n' "$SERVED_MODEL_NAME"
  printf 'GGUF_FILENAME=%q\n' "$GGUF_FILENAME"
  printf 'SGLANG_MEM_FRACTION=%q\n' "$PROFILE_SGLANG_MEM_FRACTION"
  printf 'GPU_MEMORY_UTILIZATION=%q\n' "$PROFILE_GPU_MEMORY_UTILIZATION"
  printf 'RUNTIME_IMAGE=%q\n' "$RUNTIME_IMAGE"
  printf 'INTERNAL_PORT=%q\n' "$INTERNAL_PORT"
  printf 'BACKEND_SOCKET=%q\n' "$BACKEND_SOCKET"
  declare -p PROFILE_SGLANG_ARGS PROFILE_SGLANG_ENV PROFILE_VLLM_ARGS PROFILE_VLLM_ENV PROFILE_LLAMACPP_ARGS PROFILE_LLAMACPP_ENV
} >/etc/opsrabbit-llm/install.conf
chmod 0600 /etc/opsrabbit-llm/install.conf

if [[ "$runtime_args_staged" == "true" ]]; then
  validate_runtime_args_file /etc/opsrabbit-llm/runtime.args.pending
  install -m 0600 /etc/opsrabbit-llm/runtime.args.pending /etc/opsrabbit-llm/runtime.args
  rm -f /etc/opsrabbit-llm/runtime.args.pending
else
  : >/etc/opsrabbit-llm/runtime.args
  chmod 0600 /etc/opsrabbit-llm/runtime.args
fi

install -m 0755 "$SCRIPT_DIR/scripts/run-model.sh" /usr/local/lib/opsrabbit-llm/run-model.sh
install -m 0755 "$SCRIPT_DIR/scripts/healthcheck.sh" /usr/local/sbin/opsrabbit-llm-healthcheck

cat >/etc/systemd/system/opsrabbit-llm.service <<'EOF'
[Unit]
Description=OpsRabbit OpenAI-compatible model server
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/local/lib/opsrabbit-llm/run-model.sh
ExecStartPre=/usr/bin/install -d -o root -g www-data -m 2750 /run/opsrabbit-llm
ExecStop=-/usr/bin/docker stop --time 120 opsrabbit-llm-server
ExecStopPost=-/usr/bin/docker rm -f opsrabbit-llm-server
Restart=on-failure
RestartSec=10
TimeoutStartSec=infinity
TimeoutStopSec=180
LimitMEMLOCK=infinity
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

additional_listen=""
if [[ "$LISTEN_ADDRESS" != "127.0.0.1" && "$LISTEN_ADDRESS" != "0.0.0.0" ]]; then
  additional_listen="    listen 127.0.0.1:${PORT};"
fi

backend_proxy="http://127.0.0.1:${INTERNAL_PORT}"
if [[ "$RUNTIME" != "sglang" ]]; then
  backend_proxy="http://unix:${BACKEND_SOCKET}:"
fi

cat >/etc/nginx/conf.d/opsrabbit-llm.conf <<EOF
# Accommodate the maximum supported 256-character bearer key.
map_hash_bucket_size 512;

map \$http_authorization \$opsrabbit_llm_authorized {
    default 0;
    "Bearer ${ACCESS_VALUE}" 1;
}

server {
    listen ${LISTEN_ADDRESS}:${PORT};
${additional_listen}
    server_name _;
    access_log off;
    client_max_body_size 16m;

    location = /health {
        if (\$opsrabbit_llm_authorized = 0) { return 401; }
        proxy_pass ${backend_proxy};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location ^~ /v1/ {
        if (\$opsrabbit_llm_authorized = 0) { return 401; }
        proxy_pass ${backend_proxy};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location / {
        return 404;
    }
}
EOF
chmod 0600 /etc/nginx/conf.d/opsrabbit-llm.conf
nginx -t
systemctl enable --now nginx
systemctl reload nginx

systemctl daemon-reload
systemctl enable opsrabbit-llm.service
systemctl restart opsrabbit-llm.service

if ((STARTUP_TIMEOUT > 0)); then
  if [[ "$MODEL_FAMILY" == "glm-5.2-w4afp8" ]]; then
    log "Waiting for model readiness. The first run downloads roughly 440 GB and can take a long time."
  else
    log "Waiting for model readiness. A first run may need to download large model files."
  fi
  deadline=$((SECONDS + STARTUP_TIMEOUT))
  while ((SECONDS < deadline)); do
    if curl --silent --fail --max-time 5 \
      --config /etc/opsrabbit-llm/curl.conf \
      "http://127.0.0.1:${PORT}/health" >/dev/null; then
      log "Model endpoint is ready."
      break
    fi
    if ! systemctl is-active --quiet opsrabbit-llm.service; then
      docker logs --tail 100 opsrabbit-llm-server >&2 || true
      journalctl -u opsrabbit-llm.service -n 80 --no-pager >&2
      die "Model service stopped before becoming ready."
    fi
    sleep 30
  done
  curl --silent --fail --max-time 5 \
    --config /etc/opsrabbit-llm/curl.conf \
    "http://127.0.0.1:${PORT}/health" >/dev/null || {
      docker logs --tail 100 opsrabbit-llm-server >&2 || true
      journalctl -u opsrabbit-llm.service -n 80 --no-pager >&2
      die "Model did not become ready within ${STARTUP_TIMEOUT} seconds. The service remains enabled; inspect it with journalctl -u opsrabbit-llm.service."
    }
fi

display_address=$LISTEN_ADDRESS
if [[ "$LISTEN_ADDRESS" == "0.0.0.0" ]]; then
  display_address="<server-private-ip>"
fi

cat <<EOF

Installation complete.

OpenAI-compatible base URL: http://${display_address}:${PORT}/v1
Model name:                  ${SERVED_MODEL_NAME}
API key (root-only):         sudo cat /etc/opsrabbit-llm/api-key
Health check:                sudo opsrabbit-llm-healthcheck
Model logs:                  sudo docker logs -f opsrabbit-llm-server
Service supervisor logs:    sudo journalctl -u opsrabbit-llm.service -f

TLS is not configured. Keep this endpoint on localhost or a trusted private
network protected by a firewall.
EOF
