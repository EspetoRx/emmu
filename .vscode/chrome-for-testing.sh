#!/bin/zsh
set -e

CACHE="$HOME/Library/Caches/ms-playwright"
CHROMIUM="$(find "$CACHE" -maxdepth 1 -type d -name 'chromium-*' ! -name '*headless*' | sort -V | tail -1)"
if [[ -z "$CHROMIUM" ]]; then
  echo "Chromium do Playwright não encontrado. Rode: npx playwright install chromium" >&2
  exit 1
fi

EXE="$(find "$CHROMIUM" -type f -path '*/Contents/MacOS/Google Chrome for Testing' | head -1)"
if [[ -z "$EXE" ]]; then
  EXE="$(find "$CHROMIUM" -type f -name 'chrome' | head -1)"
fi
exec "$EXE" "$@"
