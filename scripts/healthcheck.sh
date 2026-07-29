#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="/etc/opsrabbit-llm/install.conf"
CURL_CONFIG="/etc/opsrabbit-llm/curl.conf"
NGINX_CONFIG="/etc/nginx/conf.d/opsrabbit-llm.conf"
RUN_CHAT=false

usage() {
  cat <<'EOF'
Usage: sudo opsrabbit-llm-healthcheck [--chat]

Checks the authenticated health and model-list endpoints. --chat also sends a
small chat-completion request and can consume GPU capacity.
EOF
}

while (($#)); do
  case "$1" in
    --chat) RUN_CHAT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

((EUID == 0)) || {
  printf 'Run this health check with sudo so it can read the API key.\n' >&2
  exit 1
}

[[ -r "$CONFIG_FILE" && -r "$CURL_CONFIG" && -r "$NGINX_CONFIG" ]] || {
  printf 'OpsRabbit LLM configuration is incomplete. Re-run install.sh.\n' >&2
  exit 1
}

# shellcheck source=/dev/null
source "$CONFIG_FILE"
[[ "$PORT" =~ ^[0-9]+$ ]] || {
  printf 'Could not determine the public API port.\n' >&2
  exit 1
}

BASE_URL="http://127.0.0.1:${PORT}"
curl --silent --show-error --fail --max-time 10 --config "$CURL_CONFIG" "$BASE_URL/health" >/dev/null
models=$(curl --silent --show-error --fail --max-time 30 --config "$CURL_CONFIG" "$BASE_URL/v1/models")
jq -e --arg model "$SERVED_MODEL_NAME" '.data[] | select(.id == $model)' <<<"$models" >/dev/null

printf 'Health: ready\nModel:  %s\nAPI:    %s/v1\n' "$SERVED_MODEL_NAME" "$BASE_URL"

if [[ "$RUN_CHAT" == "true" ]]; then
  response=$(jq -n --arg model "$SERVED_MODEL_NAME" '{model: $model, messages: [{role: "user", content: "Reply with: ready"}], max_tokens: 16, temperature: 0}' |
    curl --silent --show-error --fail --max-time 300 \
      --config "$CURL_CONFIG" \
      --header 'Content-Type: application/json' \
      --data-binary @- \
      "$BASE_URL/v1/chat/completions")
  jq -e '.choices[0].message.content | strings | length > 0' <<<"$response" >/dev/null
  printf 'Chat:   passed\n'
fi
