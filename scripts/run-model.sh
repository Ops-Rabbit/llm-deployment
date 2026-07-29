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
      --mem-fraction-static 0.85
      --sampling-defaults model
      --log-level warning
      --config /run/secrets/sglang-auth.json
    )
    if [[ "$MODEL_PROFILE" == "glm-5.2-w4afp8" ]]; then
      server_args+=(
        --quantization w4afp8
        --reasoning-parser glm45
        --tool-call-parser glm47
        --disable-shared-experts-fusion
      )
    fi
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
      --gpu-memory-utilization 0.85
    )
    ;;
  *)
    printf 'Unsupported runtime in %s: %s\n' "$CONFIG_FILE" "$RUNTIME" >&2
    exit 1
    ;;
esac

if [[ "$TRUST_REMOTE_CODE" == "true" ]]; then
  server_args+=(--trust-remote-code)
fi

if [[ "$MTP_ENABLED" == "true" ]]; then
  server_args+=(
    --speculative-algorithm EAGLE
    --speculative-num-steps 1
    --speculative-eagle-topk 1
    --speculative-num-draft-tokens 2
  )
fi

server_args+=("${runtime_args[@]}")

runtime_secret_args=()
if [[ "$RUNTIME" == "sglang" ]]; then
  runtime_secret_args+=(--volume /etc/opsrabbit-llm/sglang-auth.json:/run/secrets/sglang-auth.json:ro)
else
  runtime_secret_args+=(
    --env-file /etc/opsrabbit-llm/vllm.env
    --volume /run/opsrabbit-llm:/run/opsrabbit-llm
  )
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
  --volume "$MODEL_CACHE_DIR:/root/.cache/huggingface" \
  --volume "$DATA_DIR/torch:/root/.cache/torch" \
  --volume "$DATA_DIR/sglang:/root/.cache/sglang" \
  "${runtime_secret_args[@]}" \
  "$RUNTIME_IMAGE" \
  "${server_args[@]}"
