#!/bin/bash
# Instala o AguiaPortalService no Linux (systemd) ao lado do AguiaServer.
#   sudo ./instalar.sh        (de dentro da pasta com o binario AguiaPortalService_linux)
set -euo pipefail
DESTINO=/opt/aguia/portalservice
USUARIO=aguia
ORIGEM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo 'rode como root' >&2; exit 1; }
id "$USUARIO" >/dev/null 2>&1 || { echo "usuario $USUARIO nao existe: instale antes o AguiaServer (instalar.sh do pacote Linux)" >&2; exit 1; }
BIN="$ORIGEM/AguiaPortalService"
[ -f "$BIN" ] || BIN="$ORIGEM/AguiaPortalService_linux"
[ -f "$BIN" ] || { echo 'binario AguiaPortalService nao encontrado ao lado do instalar.sh' >&2; exit 1; }

install -d -o "$USUARIO" -g "$USUARIO" "$DESTINO" "$DESTINO/logos"
install -o "$USUARIO" -g "$USUARIO" -m 755 "$BIN" "$DESTINO/AguiaPortalService"
# Configuracao so na primeira vez.
if [ ! -f "$DESTINO/AguiaPortalService.ini" ]; then
  install -o "$USUARIO" -g "$USUARIO" -m 640 "$ORIGEM/AguiaPortalService.ini.linux" "$DESTINO/AguiaPortalService.ini"
fi
install -d -m 750 -o root -g "$USUARIO" /etc/aguia
if [ ! -f /etc/aguia/portalservice.env ]; then
  printf 'AWS_ACCESS_KEY_ID=\nAWS_SECRET_ACCESS_KEY=\n' > /etc/aguia/portalservice.env
  chown root:"$USUARIO" /etc/aguia/portalservice.env
  chmod 640 /etc/aguia/portalservice.env
  echo 'Preencha /etc/aguia/portalservice.env com a credencial S3.'
fi
if ls "$ORIGEM"/logos/*.png >/dev/null 2>&1; then
  install -o "$USUARIO" -g "$USUARIO" -m 644 "$ORIGEM"/logos/*.png "$DESTINO/logos/"
fi
install -m 644 "$ORIGEM/aguia-portalservice.service" /etc/systemd/system/aguia-portalservice.service
systemctl daemon-reload
echo
echo 'Instalado. Proximos passos:'
echo "  1) sudo -u $USUARIO $DESTINO/AguiaPortalService /configurar     (token do portal; recria a chave local)"
echo "  2) sudo -u $USUARIO $DESTINO/AguiaPortalService /testar-conexao"
echo '  3) sudo systemctl enable --now aguia-portalservice'
echo '  4) journalctl -u aguia-portalservice -f'
