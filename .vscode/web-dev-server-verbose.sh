#!/bin/zsh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/platforms/web/ui"

# Mantém os bundles WASM atualizados antes de depurar.
npm run build:wasm

# O Tauri carrega http://127.0.0.1:5173 (sem query string). O
# VITE_EMMU_PSP_VERBOSE é resolvido quando o Vite transforma os módulos, não
# quando a página carrega — por isso um Vite normal já aberto na porta precisa
# ser substituído para o flag entrar no bundle servido.
PIDS="$(lsof -nP -iTCP:5173 -sTCP:LISTEN -t 2>/dev/null || true)"
if [ -n "$PIDS" ]; then
  echo "Emmu: reiniciando Vite em 5173 com logs PSP verbose"
  echo "$PIDS" | xargs kill
  sleep 1
fi

export VITE_EMMU_PSP_VERBOSE=1
exec ./node_modules/.bin/vite --host 127.0.0.1 --port 5173 --strictPort
