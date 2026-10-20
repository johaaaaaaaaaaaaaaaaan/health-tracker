#!/usr/bin/env bash
# Fails if any Swift source uses networking APIs. The app must never send data off the phone.
set -euo pipefail
dirs=("$@")
[ ${#dirs[@]} -eq 0 ] && dirs=(App Packages)
pattern='URLSession|import Network|NWConnection|WKWebView|URLRequest'
if grep -REn --include='*.swift' "$pattern" "${dirs[@]}"; then
  echo "Networking code is forbidden (see SPEC.md §11)." >&2
  exit 1
fi
echo "OK: no networking code"
