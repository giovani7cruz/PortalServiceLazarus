# AguiaPortalService no Linux

Projeto: `source/AguiaPortalService.linux.dproj` (Delphi 12, plataforma Linux64, PAServer).
O mesmo `.dpr` serve Windows e Linux; sem parametro no Linux sobe como daemon.

## Compilar
1. Abra `AguiaPortalService.linux.dproj`, perfil PAServer (`Infus-Linux-WSL`), Release, Build.
2. O binario cai em `scratch-dir/<perfil>/AguiaPortalService.linux/AguiaPortalService_linux`.

## Instalar (no servidor, ao lado do AguiaServer)
Copie para uma pasta: o binario, `instalar.sh`, `aguia-portalservice.service`,
`AguiaPortalService.ini.linux` e `logos/`; depois `sudo ./instalar.sh`.

## Diferencas do Windows
- Boleto: so o motor **FPDF**. Logos em PNG (`logos/NNN.png`, ja convertidos aqui).
- Token do portal: no Windows e DPAPI (preso a maquina). No Linux fica cifrado com
  `portalservice.key` (0600) ao lado do binario. **O token gravado no Windows nao
  abre aqui**: rode `AguiaPortalService /configurar` como usuario `aguia`
  (`sudo -u aguia ...`) e informe o token de novo.
- S3: credenciais so por `/etc/aguia/portalservice.env` (sem Registro).
- Precisa de `libcurl` (THTTPClient) e `libfbclient.so` no servidor.
- Logs: journal (`journalctl -u aguia-portalservice`) e `Logs/` na pasta.
