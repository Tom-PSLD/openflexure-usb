#!/bin/bash
# Crée une image de déploiement « microscope périphérique USB uniquement » à partir de la carte SD.
# La carte n'est que lue : toutes les modifications portent sur la copie.
# Dans la copie : comptes sans mot de passe, pi en nologin, scans, étalonnage et journaux effacés.
# Usage : sudo ./ofm-image.sh /dev/sdX [dossier_de_sortie] [motif_wifi...]
# Chaque motif (ex. ssid=MonWifi) est recherché dans l'image : sa présence arrête la création.
set -euo pipefail

SD="${1:-}"
OUT="${2:-$(dirname "$(readlink -f "$0")")/image}"
NOM="openflexure-usb-peripherique-$(date +%F)"
IMG="$OUT/$NOM.img"
MNT=""
LOOP=""
MOTIFS=("${@:3}")
HASHS=""

die() { echo "Erreur : $*" >&2; exit 1; }

nettoyer() {
  [ -n "$MNT" ] && { umount "$MNT/boot" 2>/dev/null || true; umount "$MNT/root" 2>/dev/null || true; rm -rf "$MNT"; }
  [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null || true
}
trap nettoyer EXIT

[ "$(id -u)" -eq 0 ] || die "à lancer avec sudo"
[ -b "$SD" ] || die "indiquer le périphérique de la carte, par exemple /dev/sdb"
[ "$(lsblk -dno RM "$SD" | tr -d " ")" = "1" ] || die "$SD n'est pas un support amovible"
[ "$(lsblk -no LABEL "${SD}1" | tr -d " ")" = "bootfs" ] || die "${SD}1 n'est pas la partition bootfs"
[ "$(lsblk -no LABEL "${SD}2" | tr -d " ")" = "rootfs" ] || die "${SD}2 n'est pas la partition rootfs"
for c in e2image e2fsck resize2fs sfdisk tune2fs fstrim xz; do command -v "$c" >/dev/null || die "$c introuvable"; done

TAILLE=$(blockdev --getsize64 "$SD")
DEBUT1=$(cat "/sys/class/block/$(basename "$SD")1/start")
DEBUT2=$(cat "/sys/class/block/$(basename "$SD")2/start")
mkdir -p "$OUT"
[ "$(df --output=avail -B1 "$OUT" | tail -1)" -gt $((12 * 1024 ** 3)) ] || die "moins de 12 Go libres dans $OUT"

echo "== 1/6 Démontage de la carte (lecture seule ensuite)"
umount "${SD}1" "${SD}2" 2>/dev/null || true

echo "== 2/6 Copie de la table de partitions, de bootfs et des blocs utilisés de rootfs"
rm -f "$IMG" "$IMG.xz"
truncate -s "$TAILLE" "$IMG"
dd if="$SD" of="$IMG" bs=4M count=$((DEBUT2 * 512)) iflag=count_bytes conv=notrunc,sparse status=none
LOOP=$(losetup -P --show -f "$IMG")
e2image -ra -p "${SD}2" "${LOOP}p2"
e2fsck -fy "${LOOP}p2" >/dev/null || [ $? -le 1 ]

echo "== 3/6 Nettoyage de la copie"
MNT=$(mktemp -d)
mkdir "$MNT/root" "$MNT/boot"
mount "${LOOP}p2" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"
R="$MNT/root"
B="$MNT/boot"

for f in "$R"/etc/NetworkManager/system-connections/*.nmconnection; do
  if grep -q '^type=wifi' "$f"; then
    echo "   profil Wi-Fi supprimé : $(basename "$f")"
    rm -f "$f"
  fi
done
rm -f "$R"/var/lib/NetworkManager/*.lease "$R"/var/lib/NetworkManager/*.leases "$R"/var/lib/NetworkManager/timestamps \
      "$R"/var/lib/NetworkManager/seen-bssids "$R"/var/lib/NetworkManager/secret_key

if ! grep -q '^# ofm-peripherique' "$B/config.txt"; then
  printf '\n# ofm-peripherique\n[all]\ndtoverlay=disable-wifi\n' >> "$B/config.txt"
fi

echo uninitialized > "$R/etc/machine-id"
rm -f "$R/var/lib/dbus/machine-id"
ln -sf /usr/lib/systemd/system/rpi-resize.service "$R/etc/systemd/system/sysinit.target.wants/rpi-resize.service"
ln -sf /usr/lib/systemd/system/regenerate_ssh_host_keys.service "$R/etc/systemd/system/sysinit.target.wants/regenerate_ssh_host_keys.service"
grep -q ' resize' "$B/cmdline.txt" || sed -i '1 s/$/ resize/' "$B/cmdline.txt"

rm -f "$R"/home/*/.bash_history "$R/root/.bash_history" "$R"/home/*/ofm-usb-install.sh "$R"/home/*/.sudo_as_admin_successful
rm -rf "$R"/var/log/journal/*
find "$R/var/log" -type f \( -name '*.log' -o -name '*.gz' -o -name '*.[0-9]' \) -delete
: > "$R/var/log/wtmp"
: > "$R/var/log/btmp" 2>/dev/null || true
find "$R/var/openflexure/data" -mindepth 2 -delete
find "$R/var/openflexure/logs" -mindepth 1 -delete
find "$R/var/openflexure/settings" -mindepth 2 -type f -delete
rm -rf "$R/var/openflexure/.cache" "$R/var/openflexure/.config" "$R"/home/*/.config/pulse "$R"/home/*/.local/state

for s in "$R/etc/shadow" "$R/etc/shadow-"; do
  [ -f "$s" ] || continue
  HASHS+=$(awk -F: '$2 ~ /\$/ {sub(/^!+/, "", $2); print $2}' "$s")$'\n'
  sed -i -E 's/^([^:]+):!*\$[^:]*:/\1:!*:/' "$s"
done
rm -f "$R"/var/backups/shadow.* "$R"/var/backups/gshadow.*
for p in "$R/etc/passwd" "$R/etc/passwd-"; do
  [ -f "$p" ] && sed -i -E 's#^(pi:.*:)/bin/(ba)?sh$#\1/usr/sbin/nologin#' "$p"
done
if grep -qE '^[^:]+:!*\$' "$R/etc/shadow"; then die "un mot de passe reste dans /etc/shadow"; fi
grep -q '^pi:.*:/usr/sbin/nologin$' "$R/etc/passwd" || die "le compte pi garde un shell"
echo "   comptes sans mot de passe, pi en nologin"

MEDIAS=$(find "$R/home" "$R/root" "$R/var/openflexure/settings" -type f \( -iname '*.jp*g' -o -iname '*.png' -o -iname '*.tif*' -o -iname '*.h264' -o -iname '*.mp4' -o -iname '*.zip' \))
[ -z "$MEDIAS" ] || die "fichiers à retirer de la carte : $MEDIAS"
find "$R/home" "$R/root" "$R/var/openflexure/settings" -type f -printf '%s %P\n' > "$OUT/$NOM.contenu.txt"
echo "   inventaire : $OUT/$NOM.contenu.txt"

if [ "${#MOTIFS[@]}" -gt 0 ]; then
  RESTE=$(grep -rlsIF --exclude-dir=proc --exclude-dir=sys "${MOTIFS[@]/#/-e}" "$R/etc" "$R/var/lib" "$R/home" "$R/root" "$B" || true)
  [ -z "$RESTE" ] || { echo "   Traces Wi-Fi restantes :"; echo "$RESTE" | sed 's/^/     /'; }
fi

echo "   effacement de l'espace libre"
sync
fstrim "$R"
umount "$B" "$R"
e2fsck -fy "${LOOP}p2" >/dev/null || [ $? -le 1 ]
tune2fs -O ^has_journal "${LOOP}p2" >/dev/null
mount "${LOOP}p2" "$R"
fstrim "$R"
umount "$R"
tune2fs -j "${LOOP}p2" >/dev/null

echo "== 4/6 Réduction du système de fichiers"
e2fsck -fy "${LOOP}p2" >/dev/null || [ $? -le 1 ]
resize2fs -M "${LOOP}p2" >/dev/null
BLOCS=$(dumpe2fs -h "${LOOP}p2" 2>/dev/null | awk -F: '/^Block count/ {gsub(/ /,"",$2); print $2}')
TBLOC=$(dumpe2fs -h "${LOOP}p2" 2>/dev/null | awk -F: '/^Block size/ {gsub(/ /,"",$2); print $2}')
SECTEURS=$(( (BLOCS * TBLOC + 511) / 512 + 2048 ))
losetup -d "$LOOP"
LOOP=""
python3 - "$IMG" "$DEBUT1" <<'EOF'
import struct
import sys

image, debut = sys.argv[1], int(sys.argv[2]) * 512

with open(image, "r+b") as f:
    f.seek(debut)
    bs = f.read(512)
    octets_secteur, secteurs_cluster, reserves, nb_fat = struct.unpack_from("<HBHB", bs, 11)
    total = struct.unpack_from("<H", bs, 19)[0] or struct.unpack_from("<I", bs, 32)[0]
    taille_fat = struct.unpack_from("<H", bs, 22)[0] or struct.unpack_from("<I", bs, 36)[0]
    if bs[82:87] != b"FAT32":
        sys.exit("bootfs n'est pas en FAT32")
    donnees = reserves + nb_fat * taille_fat
    taille_cluster = octets_secteur * secteurs_cluster
    nb_clusters = (total - donnees) // secteurs_cluster
    f.seek(debut + reserves * octets_secteur)
    fat = f.read(taille_fat * octets_secteur)
    zero = bytes(taille_cluster)
    effaces = 0
    for c in range(2, nb_clusters + 2):
        if struct.unpack_from("<I", fat, c * 4)[0] & 0x0FFFFFFF == 0:
            pos = debut + (donnees * octets_secteur) + (c - 2) * taille_cluster
            f.seek(pos)
            if f.read(taille_cluster) != zero:
                f.seek(pos)
                f.write(zero)
                effaces += 1
    print(f"   bootfs : {effaces} clusters libres effacés")
EOF
echo "${DEBUT2},${SECTEURS}" | sfdisk -q --no-reread -N 2 "$IMG"
truncate -s $(( (DEBUT2 + SECTEURS) * 512 )) "$IMG"

for motif in "${MOTIFS[@]}"; do
  if grep -aqF "$motif" "$IMG"; then
    die "« $motif » est encore présent dans l'image ($IMG non compressée, à supprimer)"
  fi
done
echo "   motifs contrôlés dans l'image : ${#MOTIFS[@]}"
while read -r h; do
  [ -z "$h" ] && continue
  if grep -aqF "$h" "$IMG"; then
    die "un ancien mot de passe chiffré reste dans l'image ($IMG non compressée, à supprimer)"
  fi
done <<< "$HASHS"
echo "   aucun ancien mot de passe dans l'image"

echo "== 5/6 Compression (plusieurs minutes)"
xz -T0 -6 -f "$IMG"
sha256sum "$IMG.xz" | sed "s|$OUT/||" > "$IMG.xz.sha256"
chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUT"

echo "== 6/6 Terminé"
ls -lh "$IMG.xz"
echo "À flasher avec Raspberry Pi Imager : « Choisir l'OS » → « Utiliser une image personnalisée », sans personnalisation de l'OS."
