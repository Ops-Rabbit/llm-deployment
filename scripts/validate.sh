#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_DIR
cd "$REPO_DIR"

command -v shellcheck >/dev/null 2>&1 || {
  printf 'shellcheck is required.\n' >&2
  exit 1
}

shell_files=(./install.sh ./uninstall.sh)
while IFS= read -r shell_file; do
  shell_files+=("$shell_file")
done < <(find ./scripts ./tests -type f -name '*.sh' | sort)
shellcheck -x "${shell_files[@]}"

for shell_file in "${shell_files[@]}"; do
  bash -n "$shell_file"
done
bash -n ./lib/common.sh
for profile_file in ./profiles/*.conf; do
  bash -n "$profile_file"
done

./tests/common_test.sh
./tests/catalog_test.sh
./tests/profile_test.sh
./tests/repository_test.sh
./install.sh --help >/dev/null
./scripts/healthcheck.sh --help >/dev/null
./uninstall.sh --help >/dev/null

printf 'All repository validation passed.\n'
