#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
unset SIGNING_IDENTITY NOTARY_API_KEY_PATH NOTARY_KEY_ID NOTARY_ISSUER_ID
exec "${SCRIPT_DIR}/package-macos.sh" "$@"
