# OpenFlexure USB : un microscope utilisable sans aucun réseau

Ce projet permet de piloter un [microscope OpenFlexure](https://openflexure.org) avec **un simple câble USB-C** relié à un ordinateur. Pas besoin de Wi-Fi, d'Internet ni de logiciel à installer : tout se passe dans le navigateur.

**À qui ça sert ?**

- aux **chercheurs sur le terrain**, sans connexion ni box Wi-Fi ;
- aux **laboratoires, écoles et ateliers** sans infrastructure réseau disponible ;
- aux **établissements** dont le réseau n'accepte pas d'appareils extérieurs.

**[Télécharger l'image prête à flasher](https://github.com/Tom-PSLD/openflexure-usb/releases)** : rien à installer, il suffit de la copier sur une carte SD.

📄 **[Guide illustré, accessible sans connaissances techniques](docs/guide-openflexure-usb.pdf)**

## Comment ça marche

Pour l'ordinateur, le microscope devient une petite carte réseau USB, reliée à rien d'autre qu'au microscope.

```text
┌──────────────┐    câble USB-C     ┌─────────────────────┐
│ Ordinateur   │◄──────────────────►│ Microscope          │
│ + navigateur │  réseau privé      │ Raspberry Pi 4      │
│              │  10.55.0.0/24      │ + Sangaboard v5     │
└──────────────┘                    └─────────────────────┘
```

1. L'ordinateur reçoit automatiquement une adresse, sans pilote à installer.
2. Vous ouvrez **http://10.55.0.1**.
3. La page transmet l'heure de l'ordinateur au microscope, qui n'a pas d'horloge à pile. Vos images restent correctement datées, même hors ligne.
4. L'interface OpenFlexure s'affiche.

Le câble ne donne accès qu'au microscope : aucune passerelle ni DNS n'est transmis à l'ordinateur, qui garde sa propre connexion s'il en a une.

## État du projet

| Élément | État |
|---|---|
| Liaison USB automatique et redémarrage |  validés |
| Mise à l'heure sans Internet |  validée |
| Linux (Debian 12) |  testé |
| Windows |  testé |
| macOS |  testé |
| Alimentation et moteurs par un seul câble |  testés sur un seul ordinateur |
| Autres ordinateurs portables, autonomie |  non mesurés |
| Utilisation en conditions réelles de terrain |  pas encore réalisée |
| Batterie intégrée |  en développement, non publiée |

Configuration testée : OpenFlexure v3.0.0-beta1, Raspberry Pi OS Trixie, Raspberry Pi 4, Sangaboard v5. OpenFlexure v3 demande un Pi 4 de 4 Go ou plus. La v3 d'OpenFlexure est encore une bêta et une mise à jour peut demander de relancer le script.

## Installation

Deux possibilités : flasher l'image toute prête (le plus simple), ou ajouter le mode USB à une carte OpenFlexure existante.

### Option 1 : l'image prête à flasher (conseillé)

1. Téléchargez le fichier `.img.xz` et son `.sha256` depuis la page [Releases](https://github.com/Tom-PSLD/openflexure-usb/releases).
2. Vérifiez le fichier (facultatif) : `sha256sum -c openflexure-usb-peripherique-*.img.xz.sha256`.
3. Ouvrez [Raspberry Pi Imager](https://www.raspberrypi.com/software/), choisissez « Utiliser une image personnalisée », puis une carte SD de **16 Go minimum**.
4. **Refusez la personnalisation de l'OS** proposée par Imager.
5. Mettez la carte dans le Pi, lisez la section « Alimentation » plus bas, branchez le câble USB-C, puis ouvrez **http://10.55.0.1**. Le premier démarrage est un peu plus long.

L'image a le Wi-Fi coupé et ne contient aucun mot de passe ni étalonnage : refaites l'étalonnage de la caméra et de la platine au premier lancement.

### Option 2 : ajouter le mode USB à une carte existante

Il faut un microscope qui fonctionne déjà avec l'image **OpenFlexure v3 bêta** officielle ([instructions d'installation](https://openflexure.org/projects/microscope/install)). Le Wi-Fi reste alors actif en plus de l'USB.

**Depuis le Raspberry Pi :**

```bash
sudo ./scripts/ofm-usb-install.sh / /boot/firmware
sudo reboot
```

**Depuis un PC Linux, carte SD montée :**

```bash
sudo ./scripts/ofm-usb-install.sh /media/$USER/rootfs /media/$USER/bootfs
```

**Pour désinstaller :**

```bash
sudo ./scripts/ofm-usb-install.sh --uninstall / /boot/firmware
```

## ⚠️ Alimentation : à lire avant de brancher

Sur le Pi 4, le 5 V du port USB-C et celui du connecteur GPIO sont reliés. **Ne branchez jamais l'ordinateur sur le Pi pendant que la Sangaboard est alimentée par son propre USB-C** sans bloqueur de 5 V : deux sources seraient reliées directement, avec un risque pour le matériel.

Deux montages sont possibles :

| Montage | Branchement | Remarque |
|---|---|---|
| **Un seul câble** | Ordinateur → USB-C du Pi ; rien sur l'USB-C de la Sangaboard | Testé sur un seul ordinateur. Préférez un port USB-C ; un port trop faible peut provoquer des coupures, et la batterie du portable se vide plus vite |
| **Alimentation séparée** | Alimentation → USB-C de la Sangaboard ; ordinateur → USB-C du Pi via un **bloqueur de 5 V** (*USB power blocker*, pas un *data blocker*) | Non testé à ce jour |

## Dépannage

| Problème | À essayer |
|---|---|
| La page ne s'ouvre pas | Attendre une minute après la mise sous tension, puis essayer un autre câble : certains ne transportent que le courant |
| Le microscope redémarre ou se coupe | Port USB trop faible : utiliser un autre port USB-C ou une alimentation séparée |
| Ordinateur d'entreprise ou d'établissement | Ajouter `10.55.0.1` aux exceptions du proxy du navigateur ; un pare-feu ou une politique USB peut bloquer la liaison |
| Linux : pas d'adresse | Un profil réseau « partagé » existant peut prendre la carte USB ; créer un profil client DHCP dédié |
| L'heure n'est pas corrigée | Ouvrir `http://10.55.0.1` et non directement le port 5000 |

Pour la maintenance : `ssh pi@10.55.0.1`, si le compte `pi` dispose d'un shell. Il est en `nologin` sur l'image officielle comme sur les images créées par `ofm-image.sh`.

## Ce que fait le script

| Élément | Rôle |
|---|---|
| `config.txt` (copie gardée dans `config.txt.orig`) | Passe le contrôleur USB-C en mode périphérique (`dwc2`) |
| `ofm-usb-gadget` et son service | Crée la carte réseau USB : RNDIS pour Windows, NCM pour Linux et macOS |
| Règle udev `86-ofm-usb-managed` | Autorise NetworkManager à gérer l'interface USB |
| Profil `ofm-usb` | Adresse `10.55.0.1/24` et DHCP sans passerelle ni DNS |
| `ofm-heure` et son service | Page de mise à l'heure sur le port 80, acceptée uniquement par le câble USB |

## Créer sa propre image

`scripts/ofm-image.sh` crée une image « USB uniquement », sans Wi-Fi, à partir d'une carte SD préparée. La carte d'origine est seulement lue ; ces changements ne portent que sur la copie :

- tous les mots de passe sont retirés et le compte `pi` repasse en `nologin` ; pour la maintenance, réactivez-le depuis la carte SD montée sur un PC Linux avec `sudo usermod -R /media/$USER/rootfs -s /bin/bash pi`, puis définissez un mot de passe ;
- les images, les scans, les journaux et l'étalonnage d'OpenFlexure sont effacés : chaque microscope doit refaire le sien ;
- la création s'arrête si un média reste dans les dossiers personnels ou si un ancien mot de passe chiffré subsiste dans l'image ;
- un inventaire `.contenu.txt` liste les fichiers restants, à relire avant de partager.

```bash
sudo ./scripts/ofm-image.sh /dev/sdX ./image 'ssid=MonWifi'
```

Chaque motif donné après le dossier de sortie est recherché dans l'image, et sa présence arrête la création.

C'est ce script qui a servi à créer l'image proposée dans les [Releases](https://github.com/Tom-PSLD/openflexure-usb/releases).

## Usage en établissement

Ce projet ne contourne aucune protection réseau : le microscope n'est jamais raccordé au réseau de l'établissement. Si vous l'utilisez dans une structure dont les règles encadrent les périphériques USB, prévenez le service informatique avant de l'installer. Ce montage n'est pas un dispositif médical.

## Licence

Scripts sous licence [GPL-3.0-or-later](LICENSE). OpenFlexure est un projet indépendant : son serveur est sous GPL-3.0 et son matériel sous CERN-OHL-S-2.0.

Auteur : Tom Penfornis.
