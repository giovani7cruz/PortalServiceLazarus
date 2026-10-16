# AguiaPortalService (Lazarus / FPC, Linux)

Sincroniza clientes, titulos e boletos (PDF no S3) do Aguia com o Portal do
Cliente. Versao **so Linux**, Lazarus/FPC com SQLdb, irma do projeto Delphi
`Aguia\PortalService` (mesmos comandos, mesmas tabelas `PORTAL_*`, mesmo
formato de payload e do token `L1:`). Os dois sao mantidos.

## Compilar (WSL/Linux, FPC 3.2.2 + Lazarus)

    ./build-linux.sh [pasta do ACBr]      # bin/AguiaPortalService
    tests/run-tests.sh                    # SHA/HMAC, token, JSON, 1252

O ACBr vem de `../../Delphi/Componentes/ACBr` (pacote `ACBr_BoletoFC_FPDF`).

## Comandos

Sem parametro = daemon (systemd). `/configurar`, `/testar-conexao`,
`/executar-ciclo`, `/carregar-fila-clientes`, `/enviar-clientes`,
`/carregar-fila-titulos`, `/enviar-titulos`, `/testar-clientes`,
`/testar-titulos`, `/diagnosticar-fila-titulos`, `/sincronizar-boletos AAAA-MM`,
`/testar-geracao-boleto-fpdf <id>`, `/testar-upload-boleto <id>`.

## Instalar

`deploy/linux` (unit do systemd, `AguiaPortalService.ini.linux`, `instalar.sh`,
74 logos em PNG). Detalhes no `LEIA-ME.md` de la.

## Diferencas em relacao ao projeto Delphi

- Acesso a dados: SQLdb (`PortalCliente.Db`) no lugar do FireDAC;
  `Percorrer` com callback virou `Listar` (array).
- HTTP: fphttpclient + OpenSSL (`PortalCliente.Http`); JSON: fpjson com um
  helper no estilo System.JSON (`PortalCliente.Json`; numero monetario com
  2 casas exatas, o fpjson escreveria notacao cientifica).
- SHA-256/HMAC proprios (`PortalCliente.Sha256`, vetores NIST/RFC nos testes).
- `configFirebird.ini` lido em 1252, senha desembaralhada por byte (+118).
