#!/bin/zsh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/platforms/web/ui"

# Mantém os bundles WASM atualizados antes de depurar.
npm run build:wasm

# Reaproveita um Vite já aberto na porta 5173, mantendo a tarefa viva.
if lsof -nP -iTCP:5173 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Emmu: servidor web já ativo em 127.0.0.1:5173"
  exec tail -f /dev/null
fi

# Mantém o Vite em primeiro plano: a tarefa background do VS Code precisa
# continuar ativa para que o preLaunchTask do F5 funcione corretamente.
exec ./node_modules/.bin/vite --host 127.0.0.1 --port 5173 --strictPort
