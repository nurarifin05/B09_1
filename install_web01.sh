#!/usr/bin/env bash
# Kompatibilitas paket lama. Gunakan setup.sh sebagai installer utama.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/setup.sh" "$@"
