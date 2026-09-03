#!/usr/bin/env bash
# Warkop Remote Multi-Server v3.5 Modular
# Main entrypoint. Features are split into modules for easier maintenance.
set -o pipefail
shopt -s extglob

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$BASE_DIR/modules"

# Load modules in dependency order.
for module in \
  00-core.sh \
  05-os.sh \
  10-ssh.sh \
  20-maintainer.sh \
  30-information.sh \
  40-users.sh \
  50-security.sh \
  60-services.sh \
  70-mail.sh \
  80-network.sh \
  90-menus.sh \
  100-installation.sh \
  99-main.sh
 do
  module_path="$MODULE_DIR/$module"
  if [[ ! -r "$module_path" ]]; then
    printf '[ERROR] Missing module: %s\n' "$module_path" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$module_path"
done

if [[ "${WARKOP_NO_RUN:-0}" != "1" ]]; then
  main "$@"
fi
