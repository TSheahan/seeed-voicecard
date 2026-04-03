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

echo "==> Installing to /lib/modules (DKMS path)..."
# DKMS modules in updates/dkms/ take precedence over kernel/ in module search
# order. Compress with xz to match the format DKMS uses.
DKMS_PATH=/lib/modules/$(uname -r)/updates/dkms
xz -kf snd-soc-ac108.ko
xz -kf snd-soc-seeed-voicecard.ko
xz -kf snd-soc-wm8960.ko
cp snd-soc-ac108.ko.xz           $DKMS_PATH/
cp snd-soc-seeed-voicecard.ko.xz $DKMS_PATH/
cp snd-soc-wm8960.ko.xz          $DKMS_PATH/
depmod -a

echo "==> Verifying installed modules match build tree..."
for mod in snd_soc_ac108 snd_soc_seeed_voicecard; do
  ko=$(echo $mod | tr '_' '-').ko
  installed=$(modinfo $mod          2>/dev/null | awk '/^srcversion/{print $2}')
  built=$(    modinfo ./$ko         2>/dev/null | awk '/^srcversion/{print $2}')
  if [[ "$installed" == "$built" ]]; then
    echo "  OK  $mod ($installed)"
  else
    echo "  MISMATCH $mod"
    echo "    installed: $installed"
    echo "    built:     $built"
  fi
done

echo ""
echo "==> Done. Reboot to load new modules: sudo reboot"
