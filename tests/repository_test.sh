#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_DIR
cd "$REPO_DIR"

assert_contains() {
  local pattern=$1
  local file=$2
  grep -Fq -- "$pattern" "$file" || {
    printf 'FAIL: %s does not contain required text: %s\n' "$file" "$pattern" >&2
    exit 1
  }
}

assert_not_contains() {
  local pattern=$1
  local file=$2
  if grep -Fq -- "$pattern" "$file"; then
    printf 'FAIL: %s contains forbidden text: %s\n' "$file" "$pattern" >&2
    exit 1
  fi
}

assert_contains 'vllm.entrypoints.openai.api_server' scripts/run-model.sh
assert_contains 'sglang.launch_server' scripts/run-model.sh
assert_contains 'qwen3_coder' profiles/qwen38-fp8.conf
assert_contains 'ghcr.io/ggml-org/llama.cpp:server-cuda' lib/common.sh
assert_contains '--n-gpu-layers auto' scripts/run-model.sh
assert_contains '--api-key-file /run/secrets/api-key' scripts/run-model.sh
assert_contains 'umask 007; exec /app/llama-server' scripts/run-model.sh
assert_contains '/run/secrets/sglang-auth.json' scripts/run-model.sh
assert_contains '--log-level warning' scripts/run-model.sh
assert_contains '--env-file /etc/opsrabbit-llm/vllm.env' scripts/run-model.sh
assert_contains 'docker_entrypoint_args=(--entrypoint python3)' scripts/run-model.sh
assert_contains '--network bridge' scripts/run-model.sh
assert_not_contains '--network host' scripts/run-model.sh
assert_contains "--publish \"127.0.0.1:\${INTERNAL_PORT}:\${INTERNAL_PORT}\"" scripts/run-model.sh
assert_contains 'network_args=(--network none)' scripts/run-model.sh
assert_contains "--uds \"\$BACKEND_SOCKET\"" scripts/run-model.sh
assert_contains "--host \"\$BACKEND_SOCKET\"" scripts/run-model.sh
assert_contains 'glm-5.2-w4a16-a100' profiles/a100.conf
assert_contains 'VLLM_USE_FLASHINFER_SAMPLER=0' profiles/a100.conf
assert_contains 'VLLM_USE_DEEP_GEMM=0' profiles/a100.conf
assert_contains '--dtype bfloat16' profiles/a100.conf
assert_contains '--reasoning-parser glm45' profiles/a100.conf
assert_contains '--tool-call-parser glm47' profiles/a100.conf
assert_contains '--enable-auto-tool-choice' profiles/a100.conf
assert_contains 'HF_HUB_OFFLINE=1' scripts/run-model.sh
assert_not_contains '--kv-cache-dtype' scripts/run-model.sh
assert_not_contains 'proxy_set_header Authorization ""' install.sh
assert_contains 'location = /health' install.sh
assert_contains 'location ^~ /v1/' install.sh
assert_contains 'location / {' install.sh
assert_contains 'return 404;' install.sh
assert_contains 'systemctl restart opsrabbit-llm.service' install.sh
assert_contains 'leaving the Docker daemon running' install.sh
assert_contains 'docker_preexisting=true' install.sh
assert_contains 'validate_docker_storage' install.sh
assert_contains 'additional_listen="    listen 127.0.0.1:' install.sh
assert_contains 'snapshot_download' install.sh
assert_contains 'torch.cuda.device_count()' install.sh
assert_contains "model_cache_dir=\"\$DATA_DIR/huggingface/\${MODEL_ID//\\//--}/\$MODEL_REVISION\"" install.sh
assert_contains "backend_proxy=\"http://unix:\${BACKEND_SOCKET}:\"" install.sh
assert_contains 'runtime.args.pending' install.sh
assert_contains 'ExecStartPre=/usr/bin/install -d -o root -g www-data -m 2750 /run/opsrabbit-llm' install.sh
assert_contains 'VLLM_IMAGE_TAG="vllm/vllm-openai:latest"' lib/common.sh
assert_contains 'SGLANG_IMAGE_TAG="lmsysorg/sglang:latest"' lib/common.sh
assert_contains 'LLAMACPP_IMAGE_TAG="ghcr.io/ggml-org/llama.cpp:server-cuda"' lib/common.sh
assert_contains 'PROFILE_MODEL_ID="lowbitcoffee/GLM-5.2-W4A16"' profiles/a100.conf
assert_contains 'PROFILE_MODEL_REVISION="55c92ae85b7ec564c94634964b6f5efe5c09a844"' profiles/a100.conf
assert_contains 'PROFILE_CONTEXT_LENGTH=32768' profiles/a100.conf
assert_contains "RUNTIME_IMAGE=\$(docker image inspect" install.sh
assert_contains "source \"\$SCRIPT_DIR/lib/profiles.sh\"" install.sh
assert_contains 'declare -p PROFILE_SGLANG_ARGS' install.sh
assert_contains 'Qwen3.8-27B-UD-Q4_K_XL.gguf' profiles/qwen38-unsloth-gguf-q4.conf

printf 'PASS: repository integration assertions\n'
