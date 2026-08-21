#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  cat <<'EOF'
Usage: sudo ./uninstall.sh

Removes the model service and API proxy. Model files and cache data are preserved.
The script does not remove Docker, NVIDIA drivers, or NVIDIA Container Toolkit.
EOF
  exit 0
fi

if (($#)); then
  printf 'Unknown option: %s\n' "$1" >&2
  exit 1
fi

if ((EUID != 0)); then
  command -v sudo >/dev/null 2>&1 || {
    printf 'Run this uninstaller as root or install sudo.\n' >&2
    exit 1
  }
  exec sudo -- "$0"
fi

data_dir="unknown"
if [[ -r /etc/opsrabbit-llm/install.conf ]]; then
  # shellcheck disable=SC1091
  source /etc/opsrabbit-llm/install.conf
  data_dir=${DATA_DIR:-unknown}
fi

systemctl disable --now opsrabbit-llm.service >/dev/null 2>&1 || true
docker rm -f opsrabbit-llm-server >/dev/null 2>&1 || true

rm -f \
  /etc/systemd/system/opsrabbit-llm.service \
  /etc/nginx/conf.d/opsrabbit-llm.conf \
  /usr/local/lib/opsrabbit-llm/run-model.sh \
  /usr/local/sbin/opsrabbit-llm-healthcheck
rm -f /etc/opsrabbit-llm/install.conf /etc/opsrabbit-llm/runtime.args /etc/opsrabbit-llm/runtime.args.pending /etc/opsrabbit-llm/api-key /etc/opsrabbit-llm/admin-key /etc/opsrabbit-llm/curl.conf
rm -f /etc/opsrabbit-llm/sglang-auth.json /etc/opsrabbit-llm/vllm.env /run/opsrabbit-llm/vllm.sock /run/opsrabbit-llm/backend.sock
rmdir /etc/opsrabbit-llm /usr/local/lib/opsrabbit-llm /run/opsrabbit-llm 2>/dev/null || true

systemctl daemon-reload
if command -v nginx >/dev/null 2>&1 && nginx -t >/dev/null 2>&1; then
  systemctl reload nginx >/dev/null 2>&1 || true
fi

printf 'Model service removed. Model data was preserved at: %s\n' "$data_dir"
