#!/bin/bash
# Install the norns OS configuration into the root filesystem.
# usage: configure-os.sh <rootfs> <config-dir>
set -euo pipefail

root=$1
cfg=$2

put() { install -D -m 0644 -- "$cfg/$1" "$root/$2"; }

# systemd and login-shell defaults for JACK
put 10-default-env-vars.conf etc/systemd/system.conf.d/10-default-env-vars.conf
put 10-default-env-vars.sh   etc/profile.d/10-default-env-vars.sh
put 99-realtime.conf         etc/security/limits.d/99-realtime.conf

# maiden (as we) manages units through systemctl. polkit 121+ reads
# JavaScript rules; the old .pkla files are gone.
put polkit/55-maiden-systemctl.rules etc/polkit-1/rules.d/55-maiden-systemctl.rules

put motd etc/motd

# we's shell setup
put bashrc home/we/.bashrc
chroot "$root" chown we:we /home/we/.bashrc

# samba: the dust share, with we/sleep as its user
put smb.conf etc/samba/smb.conf
printf 'sleep\nsleep\n' | chroot "$root" smbpasswd -s -a we

# network: NetworkManager owns everything; ifupdown config is loopback only
# (trixie-minbase enables systemd-networkd and iwd; NetworkManager with
# wpa_supplicant replaces them, as on monome's images)
chroot "$root" systemctl disable systemd-networkd.service systemd-networkd.socket \
  systemd-networkd-wait-online.service iwd.service 2>/dev/null

put blacklist-8192cu.conf etc/modprobe.d/blacklist-8192cu.conf
put interfaces            etc/network/interfaces
for f in 100-disable-wifi-mac-randomization 101-logging 200-disable-nmcli-auth; do
  put "network-manager/$f.conf" "etc/NetworkManager/conf.d/$f.conf"
done

# limit log sizes
put journald.conf etc/systemd/journald.conf
put logrotate.conf etc/logrotate.conf

# Masked units: apt must not run behind the user's back, and the ALSA mixer
# state is handled by norns itself.
for unit in apt-daily.timer apt-daily-upgrade.timer alsa-restore.service alsa-state.service; do
  ln -sf /dev/null "$root/etc/systemd/system/$unit"
done

# Packages the minimal base may or may not pull in (NetworkManager recommends
# modemmanager, for one). Purge whatever is installed.
installed=$(chroot "$root" dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' \
  'rsyslog' 'dphys-swapfile' 'exim4*' 'nfs-common' 'triggerhappy' 'plymouth*' \
  'modemmanager' 'libraspberrypi-doc' 2>/dev/null | awk '$1 ~ /^i/ {print $2}' || true)
if [ -n "$installed" ]; then
  # shellcheck disable=SC2086  # one word per package
  chroot "$root" apt-get -y purge --autoremove $installed
fi
