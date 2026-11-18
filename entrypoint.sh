#!/bin/sh
set -eu

if [ -z "${FIRECRAWL_LOCAL_TOKEN:-}" ]; then
  echo 'ERRO: defina FIRECRAWL_LOCAL_TOKEN no Coolify.' >&2
  exit 1
fi

# O hostname precisa ser explicitamente aceito pelo Firecrawl Local.
# O Coolify pode preencher SERVICE_FQDN_FIRECRAWL_3002 automaticamente.
public_host="${FIRECRAWL_ALLOWED_HOST:-${SERVICE_FQDN_FIRECRAWL_3002:-}}"

set -- serve --host 0.0.0.0 --port 3002 --allowed-host firecrawl
if [ -n "$public_host" ]; then
  # Deve ser somente o hostname: sem https://, caminho nem porta.
  case "$public_host" in
    *://*|*/*|*:*) echo 'ERRO: FIRECRAWL_ALLOWED_HOST deve ser apenas o hostname.' >&2; exit 1 ;;
  esac
  set -- "$@" --allowed-host "$public_host"
fi

exec /usr/local/bin/firecrawl-local "$@"
