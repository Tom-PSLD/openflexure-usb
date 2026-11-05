# OpenFlexure USB : image « USB uniquement »

Image prête à flasher pour piloter un microscope OpenFlexure par câble USB-C, sans réseau.

## Installation

1. Téléchargez le fichier `.img.xz` et son `.sha256`.
2. Vérifiez l'empreinte : `sha256sum -c <fichier>.sha256`.
3. Dans Raspberry Pi Imager, choisissez « Utiliser une image personnalisée », puis une carte de **16 Go minimum**.
4. **Refusez la personnalisation de l'OS.**
5. Le premier démarrage est plus long. Ouvrez ensuite `http://10.55.0.1` depuis l'ordinateur relié par USB-C.

Lisez d'abord la section « Alimentation » du [README](README.md) : une mauvaise combinaison de branchements peut endommager le matériel.

## Particularités

- Le Wi-Fi est désactivé.
- Aucun compte n'a de mot de passe et `pi` est en `nologin` : pas de SSH sans réactivation depuis la carte SD (voir le README).
- L'image ne contient aucun étalonnage : faites celui de la caméra et de la platine après le premier démarrage.
- Matériel : Raspberry Pi 4 de 4 Go ou plus, Sangaboard v5.
- OpenFlexure v3 est une version bêta.

## Composants et sources

| Composant | Version | Licence | Sources |
|---|---|---|---|
| OpenFlexure Microscope Server | `3.0.0-beta1`, révision `4aa9ef70403b5e6fd9cd71712f937700947c2609` (branche `v3`) | GPL-3.0 | <https://gitlab.com/openflexure/openflexure-microscope-server> |
| Raspberry Pi OS Trixie | image de référence du 2026-04-13, pi-gen `b80caf532a22578ab8b2cfaa2d0368080b509a31` | licences par paquet, listées dans `/usr/share/doc/*/copyright` | <https://github.com/RPi-Distro/pi-gen>, <https://archive.raspberrypi.com/debian/> |
| Scripts de ce dépôt | voir le tag de cette Release | GPL-3.0-or-later | ce dépôt |

Empreinte SHA-256 : `6078abedd2dfac0e3c693bb363297d31ecdbe19350a0ce62a0eecda044651699`
