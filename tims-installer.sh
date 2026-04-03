#!/bin/bash
# Rebuild and install loop for ac108-shutdown-fix development.
# Syncs from tsheahan, builds, installs to /lib/modules, then reboots.
# Run from the repo root on the Pi: sudo ./tims-installer.sh
#
# CONFIG_MODULE_FORCE_UNLOAD is not set on the Pi stock kernel, so hot-swap
# is not possible. Install + reboot is the only reliable reload path.
#
# For initial setup (DKMS, dtoverlays, ALSA config), use install.sh instead.

set -e

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo ./tims-installer.sh" >&2
  exit 1
fi

echo "==> Syncing from tsheahan/ac108-shutdown-fix..."
# Run as the repo owner, not root, so git credentials and config are correct.
sudo -u "$(stat -c '%U' "$(pwd)")" git pull tsheahan ac108-shutdown-fix

echo "==> Building..."
make -C /lib/modules/$(uname -r)/build M=$(pwd) modules

echo "==> Installing to /lib/modules..."
cp snd-soc-ac108.ko          /lib/modules/$(uname -r)/kernel/sound/soc/codecs/
cp snd-soc-wm8960.ko         /lib/modules/$(uname -r)/kernel/sound/soc/codecs/
cp snd-soc-seeed-voicecard.ko /lib/modules/$(uname -r)/kernel/sound/soc/bcm/
depmod -a

echo "==> Done. Reboot to load new modules."
echo "    Run: sudo reboot"
