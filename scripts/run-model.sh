#!/usr/bin/env bash
set -Eeuo pipefail

readonly CONFIG_FILE="/etc/opsrabbit-llm/install.conf"
readonly CONTAINER_NAME="opsrabbit-llm-server"
readonly RUNTIME_ARGS_FILE="/etc/opsrabbit-llm/runtime.args"

if [[ ! -r "$CONFIG_FILE" ]]; then
  printf 'Missing configuration: %s\n' "$CONFIG_FILE" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

runtime_args=()
runtime_environment_args=()
profile_runtime_args=()
profile_runtime_environment=()
if [[ -r "$RUNTIME_ARGS_FILE" ]]; then
  while IFS= read -r runtime_arg || [[ -n "$runtime_arg" ]]; do
    [[ -z "$runtime_arg" || "$runtime_arg" == \#* ]] && continue
    runtime_args+=("$runtime_arg")
  done <"$RUNTIME_ARGS_FILE"
fi

case "$RUNTIME" in
  sglang)
    docker_entrypoint_args=(--entrypoint python3)
    network_args=(--network bridge --publish "127.0.0.1:${INTERNAL_PORT}:${INTERNAL_PORT}")
    server_args=(
      -m sglang.launch_server
      --model-path "$MODEL_ID"
      --revision "$MODEL_REVISION"
      --served-model-name "$SERVED_MODEL_NAME"
      --host 0.0.0.0
      --port "$INTERNAL_PORT"
      --tp-size "$GPU_COUNT"
      --context-length "$CONTEXT_LENGTH"
      --mem-fraction-static "$SGLANG_MEM_FRACTION"
      --sampling-defaults model
      --log-level warning
      --config /run/secrets/sglang-auth.json
    )
    profile_runtime_args=("${PROFILE_SGLANG_ARGS[@]}")
    profile_runtime_environment=("${PROFILE_SGLANG_ENV[@]}")
    ;;
  vllm)
    rm -f "$BACKEND_SOCKET"
    docker_entrypoint_args=(--entrypoint bash)
    network_args=(--network none)
    server_args=(
      -c 'umask 007; exec python3 "$@"' opsrabbit-vllm
      -m vllm.entrypoints.openai.api_server
      --model "$MODEL_ID"
      --revision "$MODEL_REVISION"
      --served-model-name "$SERVED_MODEL_NAME"
      --uds "$BACKEND_SOCKET"
      --tensor-parallel-size "$GPU_COUNT"
      --max-model-len "$CONTEXT_LENGTH"
      --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION"
    )
    profile_runtime_args=("${PROFILE_VLLM_ARGS[@]}")
    profile_runtime_environment=("${PROFILE_VLLM_ENV[@]}")
    ;;
  llamacpp)
    rm -f "$BACKEND_SOCKET"
    docker_entrypoint_args=(--entrypoint sh)
    network_args=(--network none)
    server_args=(
      -c 'umask 007; exec /app/llama-server "$@"' opsrabbit-llamacpp
      --model "/models/$GGUF_FILENAME"
      --alias "$SERVED_MODEL_NAME"
      --host "$BACKEND_SOCKET"
      --ctx-size "$CONTEXT_LENGTH"
      --n-gpu-layers auto
      --api-key-file /run/secrets/api-key
    )
    profile_runtime_args=("${PROFILE_LLAMACPP_ARGS[@]}")
    profile_runtime_environment=("${PROFILE_LLAMACPP_ENV[@]}")
    ;;
  *)
    printf 'Unsupported runtime in %s: %s\n' "$CONFIG_FILE" "$RUNTIME" >&2
    exit 1
    ;;
esac

if [[ "$TRUST_REMOTE_CODE" == "true" && "$RUNTIME" != "llamacpp" ]]; then
  server_args+=(--trust-remote-code)
fi

if [[ "$MTP_ENABLED" == "true" && "$MTP_MODE" == "sglang-eagle" ]]; then
  server_args+=(
    --speculative-algorithm EAGLE
    --speculative-num-steps 1
    --speculative-eagle-topk 1
    --speculative-num-draft-tokens 2
  )
fi

server_args+=("${profile_runtime_args[@]}" "${runtime_args[@]}")

for runtime_environment in "${profile_runtime_environment[@]}"; do
  runtime_environment_args+=(--env "$runtime_environment")
done

runtime_secret_args=()
if [[ "$RUNTIME" == "sglang" ]]; then
  runtime_secret_args+=(--volume /etc/opsrabbit-llm/sglang-auth.json:/run/secrets/sglang-auth.json:ro)
elif [[ "$RUNTIME" == "vllm" ]]; then
  runtime_secret_args+=(
    --env-file /etc/opsrabbit-llm/vllm.env
    --volume /run/opsrabbit-llm:/run/opsrabbit-llm
  )
else
  runtime_secret_args+=(
    --volume /etc/opsrabbit-llm/api-key:/run/secrets/api-key:ro
    --volume /run/opsrabbit-llm:/run/opsrabbit-llm
  )
fi

model_volume_args=(--volume "$MODEL_CACHE_DIR:/root/.cache/huggingface")
if [[ "$RUNTIME" == "llamacpp" ]]; then
  model_volume_args=(--volume "$MODEL_CACHE_DIR:/models:ro")
fi

exec docker run --rm \
  --name "$CONTAINER_NAME" \
  "${docker_entrypoint_args[@]}" \
  --gpus all \
  --ipc=host \
  "${network_args[@]}" \
  --stop-timeout 120 \
  --ulimit memlock=-1:-1 \
  --ulimit stack=67108864:67108864 \
  --env DO_NOT_TRACK=1 \
  --env HF_HUB_DISABLE_TELEMETRY=1 \
  --env HF_HUB_OFFLINE=1 \
  --env TRANSFORMERS_OFFLINE=1 \
  "${runtime_environment_args[@]}" \
  "${model_volume_args[@]}" \
  --volume "$DATA_DIR/torch:/root/.cache/torch" \
  --volume "$DATA_DIR/sglang:/root/.cache/sglang" \
  "${runtime_secret_args[@]}" \
  "$RUNTIME_IMAGE" \
  "${server_args[@]}"
