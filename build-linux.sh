#!/usr/bin/env bash
# Compila o AguiaPortalService no Linux (FPC 3.2.2 + Lazarus, lazbuild).
# Uso: ./build-linux.sh [pasta do ACBr]   (padrao: ../../Delphi/Componentes/ACBr)
# Usa uma configuracao do Lazarus so deste projeto (.lazcfg-linux), sem tocar
# na do usuario. Binario em bin/AguiaPortalService.
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")" && pwd)"
ACBR="${1:-$RAIZ/../../Delphi/Componentes/ACBr}"
LAZDIR="${LAZARUS_DIR:-/usr/lib/lazarus/default}"
PCP="$RAIZ/.lazcfg-linux"
mkdir -p "$PCP" "$RAIZ/bin" "$RAIZ/lib/x86_64-linux"

if [ ! -f "$PCP/packagefiles.xml" ]; then
  find "$ACBR/Pacotes/Lazarus" -name '*.lpk' |
    grep -Ev 'Report|DANFE|Danfe|Fortes|ECF|TEF|SAT|Serial|DAMDFE|DACTE|DABPE|Extrato|NFSe' |
    while read -r p; do
      lazbuild --pcp="$PCP" --lazarusdir="$LAZDIR" --add-package-link "$p" >/dev/null
    done
fi

lazbuild --pcp="$PCP" --lazarusdir="$LAZDIR" --ws=nogui "$RAIZ/source/AguiaPortalService.lpi" \
  > "$RAIZ/lib/build-linux.log" 2>&1 || {
  grep -E 'Error|Fatal' "$RAIZ/lib/build-linux.log" | tail -30
  echo "Falha na compilacao (log: $RAIZ/lib/build-linux.log)"; exit 1; }
ls -l "$RAIZ/bin/AguiaPortalService"
