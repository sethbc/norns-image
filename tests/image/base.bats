#!/usr/bin/env bats
# Base system: user, sudo, hostname, ssh, kernels, first-boot root growth.

setup() {
  load ../helpers
  require_rootfs
}

@test "user we exists with uid 1000 and the sleep password" {
  run in_root getent passwd we;  [[ "$output" == we:x:1000:1000:* ]]
  hash=$(in_root getent shadow we | cut -d: -f2)
  [ "$(openssl passwd -6 -salt "$(cut -d'$' -f3 <<<"$hash")" sleep)" = "$hash" ]
}
@test "we has passwordless sudo"        { run in_root sudo -l -U we; [[ "$output" == *"NOPASSWD: ALL"* ]]; }
@test "hostname is norns"               { [ "$(cat "$ROOTFS/etc/hostname")" = norns ]; }
# systemctl warns on stderr that /proc is not mounted; compare stdout only.
@test "ssh is enabled"                  { [ "$(in_root systemctl is-enabled ssh)" = enabled ]; }
@test "Pi 4 and Pi 5 kernels installed" { [ -f "$ROOTFS/boot/firmware/kernel8.img" ] && [ -f "$ROOTFS/boot/firmware/kernel_2712.img" ]; }
@test "headers for both kernel flavours" { run in_root dpkg -s linux-headers-rpi-v8 linux-headers-rpi-2712; [ "$status" -eq 0 ]; }
@test "root grows on first boot" {
  # rpi-image-gen has no grow mechanism for dd-flashed images, so norns-base
  # ships one: a run-once unit that grows partition 2 and its filesystem.
  [ "$(in_root systemctl is-enabled norns-grow-root.service)" = enabled ]
  in_root sh -c 'command -v growpart && command -v resize2fs && command -v lsblk && command -v findmnt'
  [ -x "$(rootfs_file /usr/local/sbin/norns-grow-root)" ]
}
@test "trixie arm64"                    { grep -q 'VERSION_CODENAME=trixie' "$ROOTFS/etc/os-release"; [ "$(in_root dpkg --print-architecture)" = arm64 ]; }
