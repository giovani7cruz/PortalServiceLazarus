#!/usr/bin/env bash
# Compila e roda os testes sem banco/rede (FPC 3.2.2). Saida em /tmp para nao pesar o 9p.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
O=/tmp/pso-testes; mkdir -p $O
fpc -Mdelphi -Sh -vewn -FU$O -FE$O $(for d in "$R"/source/*/; do echo -Fu$d; done) "$R/tests/TestesBase.lpr" | grep -E "Error|Fatal|Warning: .*TestesBase" || true
$O/TestesBase
