#!/bin/bash
# Tight rebuild loop for ac108-shutdown-fix development.
# Bypasses DKMS and apt — use this for instrumentation/fix iteration.
# Run from the repo root on the Pi: sudo ./tims-installer.sh
#
# For initial setup or persistence across reboots, use install.sh instead.

set -e

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo ./tims-installer.sh" >&2
  exit 1
fi

echo "==> Stopping service and unloading modules..."
systemctl stop seeed-voicecard 2>/dev/null || true
modprobe -r snd_soc_seeed_voicecard 2>/dev/null || true
modprobe -r snd_soc_ac108           2>/dev/null || true
modprobe -r snd_soc_wm8960          2>/dev/null || true

echo "==> Building..."
make -C /lib/modules/$(uname -r)/build M=$(pwd) modules

echo "==> Loading..."
insmod ./snd-soc-ac108.ko
insmod ./snd-soc-seeed-voicecard.ko

echo "==> Done. Modules loaded:"
lsmod | grep snd_soc_
