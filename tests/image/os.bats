#!/usr/bin/env bats
# OS configuration: what setup.sh used to do on a hand-built system.

setup() {
  load ../helpers
  require_rootfs
}

# Host-side reads of root-owned directories can be denied by the uid mapping;
# read from inside the image instead.
@test "polkit lets we manage units" {
  rules=/etc/polkit-1/rules.d/55-maiden-systemctl.rules
  in_root grep -q 'org.freedesktop.systemd1.manage-units' $rules
  in_root grep -q '"we"' $rules
}
@test "no legacy pkla" {
  [ ! -e "$ROOTFS/etc/polkit-1/localauthority/50-local.d/55-maiden-systemctl.pkla" ]
}
# systemctl warns on stderr that /proc is not mounted; compare stdout only.
@test "apt timers masked" {
  [ "$(in_root systemctl is-enabled apt-daily.timer)" = masked ]
  [ "$(in_root systemctl is-enabled apt-daily-upgrade.timer)" = masked ]
}
@test "alsa state units masked" {
  [ "$(in_root systemctl is-enabled alsa-restore.service)" = masked ]
  [ "$(in_root systemctl is-enabled alsa-state.service)" = masked ]
}
@test "NetworkManager is the enabled network stack" {
  [ "$(in_root systemctl is-enabled NetworkManager)" = enabled ]
  [ "$(in_root systemctl is-enabled systemd-networkd)" = disabled ]
  [ "$(in_root systemctl is-enabled iwd)" = disabled ]
}
@test "samba and avahi are enabled" {
  [ "$(in_root systemctl is-enabled smbd)" = enabled ]
  [ "$(in_root systemctl is-enabled avahi-daemon)" = enabled ]
}
@test "wanted packages installed" {
  in_root dpkg -s network-manager dnsmasq-base samba avahi-daemon midisport-firmware >/dev/null
}
@test "unwanted packages absent" {
  for p in rsyslog dphys-swapfile exim4-base exim4-daemon-light nfs-common \
           triggerhappy plymouth modemmanager libraspberrypi-doc; do
    run in_root dpkg -s "$p"
    [ "$status" -ne 0 ] || { echo "$p is installed"; return 1; }
  done
}
@test "samba user we exists" {
  in_root pdbedit -L | grep -q '^we:'
}
@test "samba config shares dust" {
  grep -q '^\[dust\]' "$ROOTFS/etc/samba/smb.conf"
  grep -q 'Path = /home/we/dust' "$ROOTFS/etc/samba/smb.conf"
}
@test "samba config parses" {
  run in_root testparm -s /etc/samba/smb.conf
  [ "$status" -eq 0 ]
  [[ "$output" != *"Unknown parameter"* ]]
}
@test "JACK env defaults (systemd and login shells)" {
  grep -q 'JACK_NO_START_SERVER=1' "$ROOTFS/etc/systemd/system.conf.d/10-default-env-vars.conf"
  grep -q 'JACK_NO_START_SERVER=1' "$ROOTFS/etc/profile.d/10-default-env-vars.sh"
  grep -q 'JACK_NO_AUDIO_RESERVATION=1' "$ROOTFS/etc/profile.d/10-default-env-vars.sh"
}
@test "we has the norns bashrc, owned by we" {
  in_root grep -q 'force_color_prompt=yes' /home/we/.bashrc
  [ "$(in_root stat -c %U:%G /home/we/.bashrc)" = we:we ]
}
@test "motd" {
  grep -q 'monome.org/norns' "$ROOTFS/etc/motd"
}
@test "8192cu blacklisted" {
  grep -qx 'blacklist 8192cu' "$ROOTFS/etc/modprobe.d/blacklist-8192cu.conf"
}
@test "/etc/network/interfaces is loopback only" {
  grep -q 'iface lo inet loopback' "$ROOTFS/etc/network/interfaces"
  ! grep -q 'iface eth0\|iface wlan0' "$ROOTFS/etc/network/interfaces"
}
@test "NetworkManager conf.d files" {
  d="$ROOTFS/etc/NetworkManager/conf.d"
  grep -q 'wifi.scan-rand-mac-address=no' "$d/100-disable-wifi-mac-randomization.conf"
  grep -q 'audit=false' "$d/101-logging.conf"
  grep -q 'auth-polkit=false' "$d/200-disable-nmcli-auth.conf"
}
# Bounded, but big enough that the previous boots' logs (journalctl -b -1,
# which the acceptance checklist reads) are still there.
@test "journald is size limited, keeping several boots" {
  j=$ROOTFS/etc/systemd/journald.conf
  cmp "$REPO_ROOT/config/journald.conf" "$j"
  grep -qx '\[Journal\]' "$j"
  grep -qx 'Storage=persistent' "$j"
  # on disk within 15 s, so a crash or hang loses little of -b -1
  grep -qx 'SyncIntervalSec=15s' "$j"
  grep -qx 'SystemMaxUse=50M' "$j"
  # a single file would keep only the current one: no SystemMaxFiles=1
  ! grep -q '^SystemMaxFiles=' "$j" || false
}
@test "logrotate config" {
  grep -q '^rotate 1' "$ROOTFS/etc/logrotate.conf"
  grep -q '^size 1M' "$ROOTFS/etc/logrotate.conf"
}
@test "realtime limits" {
  grep -q '@realtime - rtprio 99' "$ROOTFS/etc/security/limits.d/99-realtime.conf"
  grep -q '@realtime - memlock unlimited' "$ROOTFS/etc/security/limits.d/99-realtime.conf"
}
