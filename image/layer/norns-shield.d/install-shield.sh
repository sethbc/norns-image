#!/bin/bash
# Install the norns shield's hardware support.
# usage: install-shield.sh <rootfs> <repo>
#
#  - overlays/NAME-overlay.dts -> /boot/firmware/overlays/NAME.dtbo, compiled
#    with the build host's dtc (device-tree-compiler).
#  - packages/monome-codecs-dkms -> /usr/src/monome-codecs-1.0, registered
#    with DKMS and built and installed for every kernel in /lib/modules. The
#    chroot runs on the build host's kernel, so each build names its kernel.
# config.txt and cmdline.txt are not written here: rpi-image-gen assembles
# them at the image stage from drop-ins, ours in norns-shield.d/for/.
set -euo pipefail

root=$1
repo=$2
pkg=monome-codecs
version=1.0

command -v dtc >/dev/null || { echo "dtc not found: install device-tree-compiler" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# overlays
mkdir -p "$root/boot/firmware/overlays"
for src in "$repo"/overlays/*-overlay.dts; do
  name=$(basename "$src" -overlay.dts)
  dtc -@ -I dts -O dtb -o "$work/$name.dtbo" "$src"
  install -m 644 "$work/$name.dtbo" "$root/boot/firmware/overlays/$name.dtbo"
done

# codec modules
src=/usr/src/$pkg-$version
rm -rf -- "${root:?}$src"
install -d -m 755 "$root$src"
install -m 644 "$repo"/packages/monome-codecs-dkms/* "$root$src/"
chroot "$root" dkms add "$pkg/$version"
kernels=0
for dir in "$root"/lib/modules/*/; do
  kver=$(basename "$dir")
  [ -e "$dir/build" ] || { echo "no headers for kernel $kver" >&2; exit 1; }
  chroot "$root" dkms build -k "$kver" "$pkg/$version"
  chroot "$root" dkms install -k "$kver" "$pkg/$version"
  chroot "$root" depmod -a "$kver"
  kernels=$((kernels + 1))
done
[ "$kernels" -gt 0 ] || { echo "no kernels in $root/lib/modules" >&2; exit 1; }

# codec detector: picks the overlays for the shield's codec on each boot
install -D -m 755 "$repo/scripts/norns-codec-detect" "$root/usr/local/sbin/norns-codec-detect"
install -D -m 644 "$repo/config/norns-codec-detect.service" "$root/etc/systemd/system/norns-codec-detect.service"
chroot "$root" systemctl enable norns-codec-detect.service
