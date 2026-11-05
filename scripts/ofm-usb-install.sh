#!/bin/bash
# Installe la liaison USB (gadget RNDIS + NCM) du microscope OpenFlexure et la mise à l'heure par le navigateur.
# Carte SD montée sur un PC : sudo ./ofm-usb-install.sh /media/$USER/rootfs /media/$USER/bootfs
# Directement sur le Pi     : sudo ./ofm-usb-install.sh / /boot/firmware
# Désinstallation           : ajouter --uninstall en premier argument
set -euo pipefail

UNINSTALL=0
if [ "${1:-}" = "--uninstall" ]; then
  UNINSTALL=1
  shift
fi

ROOT="${1:-/}"
BOOT="${2:-/boot/firmware}"
ADDR="10.55.0.1/24"
MARK="# ofm-usb-gadget"

GADGET="$ROOT/usr/local/sbin/ofm-usb-gadget"
UNIT="$ROOT/etc/systemd/system/ofm-usb-gadget.service"
NMCONN="$ROOT/etc/NetworkManager/system-connections/ofm-usb.nmconnection"
DNSMASQ="$ROOT/etc/NetworkManager/dnsmasq-shared.d/ofm-usb.conf"
UDEV="$ROOT/etc/udev/rules.d/86-ofm-usb-managed.rules"
HEURE="$ROOT/usr/local/sbin/ofm-heure"
HEURE_UNIT="$ROOT/etc/systemd/system/ofm-heure.service"
CFG="$BOOT/config.txt"

die() { echo "Erreur : $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "à lancer avec sudo"
grep -qs trixie "$ROOT/etc/os-release" || die "$ROOT ne ressemble pas au rootfs OpenFlexure (Trixie)"
[ -d "$ROOT/var/openflexure" ] || die "$ROOT/var/openflexure introuvable"
[ -f "$CFG" ] || die "$CFG introuvable"
[ -x "$ROOT/usr/bin/python3" ] || die "python3 introuvable dans $ROOT"

if [ "$UNINSTALL" -eq 1 ]; then
  systemctl --root="$ROOT" disable ofm-usb-gadget.service ofm-heure.service 2>/dev/null || true
  rm -f "$GADGET" "$UNIT" "$NMCONN" "$DNSMASQ" "$UDEV" "$HEURE" "$HEURE_UNIT"
  if [ -f "$CFG.orig" ]; then
    cp "$CFG.orig" "$CFG"
    rm -f "$CFG.orig"
  fi
  echo "Liaison USB désinstallée."
  exit 0
fi

if ! grep -qF "$MARK" "$CFG"; then
  [ -f "$CFG.orig" ] || cp "$CFG" "$CFG.orig"
  printf '\n%s\n[pi4]\ndtoverlay=dwc2,dr_mode=peripheral\n[pi5]\ndtoverlay=dwc2,dr_mode=peripheral\n[all]\n' "$MARK" >> "$CFG"
fi

install -d -m 755 "$(dirname "$GADGET")"
cat > "$GADGET" <<'EOF'
#!/bin/bash
set -euo pipefail

G=/sys/kernel/config/usb_gadget/ofm
SERIAL=$(tr -d '\0' < /sys/firmware/devicetree/base/serial-number 2>/dev/null || echo 0000000000000000)

mac() {
  echo "$1:$(echo "$SERIAL$2" | md5sum | sed -E 's/^(..)(..)(..)(..)(..).*/\1:\2:\3:\4:\5/')"
}

stop() {
  [ -d "$G" ] || return 0
  echo "" > "$G/UDC" 2>/dev/null || true
  rm -f "$G/os_desc/c.1"
  for c in "$G"/configs/*/; do
    find "$c" -maxdepth 1 -type l -delete
    rmdir "${c}strings/0x409" 2>/dev/null || true
  done
  rmdir "$G"/configs/* 2>/dev/null || true
  rmdir "$G"/functions/* 2>/dev/null || true
  rmdir "$G/strings/0x409" 2>/dev/null || true
  rmdir "$G"
}

start() {
  modprobe libcomposite
  mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config

  UDC=""
  for _ in $(seq 20); do
    UDC=$(ls /sys/class/udc 2>/dev/null | head -n1)
    [ -n "$UDC" ] && break
    sleep 0.5
  done
  [ -n "$UDC" ] || { echo "Aucun contrôleur USB device (dwc2) : vérifier config.txt" >&2; exit 1; }

  stop
  mkdir -p "$G"
  cd "$G"

  echo 0x1d6b > idVendor
  echo 0x0104 > idProduct
  echo 0x0100 > bcdDevice
  echo 0x0200 > bcdUSB
  echo 0xEF > bDeviceClass
  echo 0x02 > bDeviceSubClass
  echo 0x01 > bDeviceProtocol

  mkdir -p strings/0x409
  echo "$SERIAL" > strings/0x409/serialnumber
  echo "OpenFlexure" > strings/0x409/manufacturer
  echo "OpenFlexure Microscope USB" > strings/0x409/product

  echo 1 > os_desc/use
  echo 0xcd > os_desc/b_vendor_code
  echo MSFT100 > os_desc/qw_sign

  mkdir -p functions/rndis.usb0
  mac 02 rndis-dev > functions/rndis.usb0/dev_addr
  mac 06 rndis-host > functions/rndis.usb0/host_addr
  echo RNDIS > functions/rndis.usb0/os_desc/interface.rndis/compatible_id
  echo 5162001 > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id

  mkdir -p functions/ncm.usb1
  mac 02 ncm-dev > functions/ncm.usb1/dev_addr
  mac 06 ncm-host > functions/ncm.usb1/host_addr

  for c in 1 2; do
    mkdir -p configs/c.$c/strings/0x409
    echo 0xC0 > configs/c.$c/bmAttributes
    echo 100 > configs/c.$c/MaxPower
  done
  echo "RNDIS (Windows)" > configs/c.1/strings/0x409/configuration
  echo "NCM (Linux, macOS)" > configs/c.2/strings/0x409/configuration

  ln -s functions/rndis.usb0 configs/c.1/
  ln -s functions/ncm.usb1 configs/c.2/
  ln -s configs/c.1 os_desc/

  echo "$UDC" > UDC
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  *) echo "Usage : $0 start|stop" >&2; exit 1 ;;
esac
EOF
chmod 755 "$GADGET"

cat > "$UNIT" <<'EOF'
[Unit]
Description=OpenFlexure USB gadget (RNDIS + NCM)
After=sys-kernel-config.mount systemd-modules-load.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/ofm-usb-gadget start
ExecStop=/usr/local/sbin/ofm-usb-gadget stop

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$UNIT"

UUID=$(grep -s '^uuid=' "$NMCONN" | cut -d= -f2 || true)
[ -n "$UUID" ] || UUID=$(cat /proc/sys/kernel/random/uuid)
cat > "$NMCONN" <<EOF
[connection]
id=ofm-usb
uuid=$UUID
type=ethernet
autoconnect=true
autoconnect-priority=100

[match]
interface-name=usb0;usb1;

[ethernet]

[ipv4]
method=shared
address1=$ADDR
never-default=true

[ipv6]
method=disabled
EOF
chmod 600 "$NMCONN"

install -d -m 755 "$(dirname "$DNSMASQ")"
cat > "$DNSMASQ" <<'EOF'
dhcp-option=tag:usb0,option:router
dhcp-option=tag:usb1,option:router
dhcp-option=tag:usb0,option:dns-server
dhcp-option=tag:usb1,option:dns-server
EOF
chmod 644 "$DNSMASQ"

install -d -m 755 "$(dirname "$UDEV")"
echo 'SUBSYSTEM=="net", ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="0"' > "$UDEV"
chmod 644 "$UDEV"

cat > "$HEURE" <<'EOF'
#!/usr/bin/python3
import ipaddress
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

USB = ipaddress.ip_network("10.55.0.0/24")
PLANCHER = 1735689600

PAGE = b"""<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OpenFlexure</title>
<style>body{font-family:sans-serif;text-align:center;margin-top:20vh;color:#333}</style>
</head>
<body>
<p id="m">Mise &agrave; l'heure du microscope&hellip;</p>
<script>
const m = document.getElementById("m");
const suite = location.protocol + "//" + location.hostname + ":5000/";
fetch("/heure", {method: "POST", body: String(Date.now())})
  .then(r => r.text())
  .then(t => { m.textContent = t; })
  .catch(() => { m.textContent = "Heure non transmise."; })
  .finally(() => setTimeout(() => location.replace(suite), 800));
</script>
<noscript><a href="/">JavaScript requis</a></noscript>
</body>
</html>
"""


class Heure(BaseHTTPRequestHandler):
    def repondre(self, code, corps, type_="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", type_)
        self.send_header("Content-Length", str(len(corps)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self):
        self.repondre(200, PAGE, "text/html; charset=utf-8")

    def do_POST(self):
        if self.path != "/heure":
            return self.repondre(404, "Introuvable".encode())
        if ipaddress.ip_address(self.client_address[0]) not in USB:
            return self.repondre(403, "Heure acceptée uniquement par le câble USB.".encode())
        try:
            longueur = min(int(self.headers.get("Content-Length", 0)), 32)
            t = float(self.rfile.read(longueur)) / 1000
        except ValueError:
            return self.repondre(400, "Heure illisible.".encode())
        if t < PLANCHER:
            return self.repondre(400, "Heure du PC incohérente.".encode())
        ecart = t - time.time()
        if abs(ecart) > 2:
            try:
                time.clock_settime(time.CLOCK_REALTIME, t)
            except OSError as e:
                return self.repondre(500, ("Impossible de régler l'horloge : %s" % e).encode())
            self.log_message("horloge corrigée de %+.0f s", ecart)
        self.repondre(200, ("Microscope à l'heure : " + time.strftime("%d/%m/%Y %H:%M")).encode())


ThreadingHTTPServer(("0.0.0.0", 80), Heure).serve_forever()
EOF
chmod 755 "$HEURE"

cat > "$HEURE_UNIT" <<'EOF'
[Unit]
Description=OpenFlexure mise à l'heure par le navigateur (port 80)
After=network.target

[Service]
ExecStart=/usr/local/sbin/ofm-heure
Restart=on-failure
CapabilityBoundingSet=CAP_SYS_TIME CAP_NET_BIND_SERVICE
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$HEURE_UNIT"

systemctl --root="$ROOT" enable ofm-usb-gadget.service ofm-heure.service

if [ "$ROOT" = "/" ]; then
  systemctl daemon-reload
  udevadm control --reload
  udevadm trigger --subsystem-match=net --action=change
  systemctl restart ofm-usb-gadget.service ofm-heure.service
  nmcli connection reload
fi

echo "Liaison USB installée : ouvrir http://${ADDR%/*} via le câble USB-C (mise à l'heure puis microscope sur le port 5000)."
