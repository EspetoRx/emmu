#!/bin/zsh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/platforms/web/ui"

# Mantém os bundles WASM atualizados antes de depurar.
npm run build:wasm

# Reaproveita um Vite já aberto na porta 5173.
if lsof -nP -iTCP:5173 -sTCP:LISTEN >/dev/null 2>&1; then
  exit 0
fi

# Sobe o Vite em segundo plano e só termina a tarefa quando ele estiver pronto.
# Assim o preLaunchTask do F5 não fica como background task e não gera
# diagnósticos espúrios no painel Problems.
LOG="${TMPDIR:-/tmp}/emmu-web-vite.log"
nohup ./node_modules/.bin/vite --host 127.0.0.1 --port 5173 >"$LOG" 2>&1 &

for _ in {1..60}; do
  if curl -fsS http://127.0.0.1:5173 >/dev/null 2>&1; then
    exit 0
  fi
  sleep 0.5
done

echo "Emmu: falha ao iniciar o Vite em 127.0.0.1:5173" >&2
exit 1
