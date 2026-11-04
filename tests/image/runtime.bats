#!/usr/bin/env bats
# norns runtime: monome/norns built unchanged from the release tag, JACK,
# SuperCollider with the norns classes, the norns units and the update guard.

setup() {
  load ../helpers
  require_rootfs
}

N=/home/we/norns
BINARIES="matron/matron crone/crone ws-wrapper/ws-wrapper watcher/watcher maiden-repl/maiden-repl"

as_we() { in_root runuser -u we -- "$@"; }
# The host's git on the checkout: git in the image needs /dev/null, which the
# built filesystem lacks. The tree is we's, hence safe.directory; no optional
# locks, so status never rewrites the index.
norns_git() {
  in_ns git -c safe.directory='*' --no-optional-locks -C "$ROOTFS$N" "$@"
}

@test "norns source is the untouched release" {
  [ "$(norns_git rev-parse HEAD)" = "$NORNS_COMMIT" ]
  [ -z "$(norns_git status --porcelain --untracked-files=no)" ]
}
@test "norns submodules are initialised at their pinned commits" {
  run norns_git submodule status --recursive
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  # '-' is uninitialised, '+' a different commit, 'U' a conflict
  ! grep -q '^[-+U]' <<<"$output"
  grep -q ' third-party/link ' <<<"$output"
}
@test "norns binaries are aarch64" {
  for b in $BINARIES; do
    in_root file "$N/build/$b" | grep -q 'ARM aarch64' || { echo "$b"; return 1; }
  done
}
@test "matron links libgpiod v1" {
  in_root ldd $N/build/matron/matron | grep -q '/opt/norns/libgpiod1/lib/libgpiod.so.2'
}
@test "matron and crone load the private liblo 0.31" {
  for b in matron/matron crone/crone; do
    in_root ldd "$N/build/$b" | grep -q 'liblo.so.7 => /opt/norns/liblo031/lib/liblo.so.7' \
      || { echo "$b"; return 1; }
  done
}
@test "norns binaries find all their libraries" {
  for b in $BINARIES; do
    libs=$(in_root ldd "$N/build/$b") || { echo "$b"; return 1; }
    ! grep 'not found' <<<"$libs" || { echo "$b"; return 1; }
  done
}
@test "norns configured through the compiler wrapper, without --release" {
  cache=$(in_root cat $N/build/c4che/_cache.py)
  grep -q "^CC = \['/usr/local/lib/norns-build/gcc'\]" <<<"$cache"
  grep -q "^CXX = \['/usr/local/lib/norns-build/g++'\]" <<<"$cache"
  grep -q "^NORNS_RELEASE = False" <<<"$cache"
}
@test "compiler wrapper and waf installed, but not on the default PATH" {
  d=/usr/local/lib/norns-build
  in_root test -x $d/norns-cc-wrapper
  in_root python3 $d/waf --version | grep -q "^waf ${NORNS_WAF_URL##*waf-} "
  for cc in cc gcc c++ g++; do
    [ "$(in_root readlink $d/$cc)" = norns-cc-wrapper ]
  done
  [ "$(as_we bash -lc 'command -v gcc')" = /usr/bin/gcc ]
}
@test "norns SC classes installed for we" {
  f=/home/we/.local/share/SuperCollider/Extensions/norns-config.sc
  in_root cmp $N/sc/norns-config.sc $f
  [ "$(in_root stat -c %U $f)" = we ]
}
@test "SuperCollider and JACK installed" {
  in_root dpkg -s supercollider-language supercollider-server sc3-plugins jackd2 jack-example-tools >/dev/null
  for p in /usr/bin/sclang /usr/bin/scsynth /usr/bin/jackd /usr/bin/jack_wait \
           /usr/bin/jack_connect /usr/bin/jack_disconnect; do
    in_root test -x $p || { echo "$p"; return 1; }
  done
}
# Debian's sclang is a Qt build; with no display it needs the offscreen platform.
@test "sclang unit runs Qt offscreen" {
  grep -qx 'Environment="QT_QPA_PLATFORM=offscreen"' "$ROOTFS/etc/systemd/system/norns-sclang.service"
  in_root sh -c 'ls /usr/lib/aarch64-linux-gnu/qt5/plugins/platforms/libqoffscreen.so'
}
@test "commands norns runs are installed" {
  for c in curl iw nmcli wget sha256sum amixer; do
    in_root sh -c "command -v $c" >/dev/null || { echo "$c"; return 1; }
  done
}
@test "norns units installed from config/" {
  for f in "$REPO_ROOT"/config/norns-*.service "$REPO_ROOT"/config/norns-*.socket "$REPO_ROOT"/config/norns.target; do
    cmp "$f" "$ROOTFS/etc/systemd/system/${f##*/}" || return 1
  done
}
# Every absolute path a unit executes must exist.
@test "unit executables exist" {
  for f in "$REPO_ROOT"/config/norns-*.service; do
    u=$ROOTFS/etc/systemd/system/${f##*/}
    [ -f "$u" ] || { echo "${f##*/} not installed"; return 1; }
    for p in $(sed -n 's/^Exec[A-Za-z]*=[-@+!:]*//p' "$u" | tr ' ' '\n' | grep '^/'); do
      in_root test -e "$p" || { echo "${f##*/}: $p"; return 1; }
    done
  done
}
# systemctl warns on stderr that /proc is not mounted; compare stdout only.
@test "norns.target enabled" {
  [ "$(in_root systemctl is-enabled norns.target)" = enabled ]
}
@test "realtime group exists and we is in the audio and device groups" {
  in_root getent group realtime >/dev/null
  groups=" $(in_root id -nG we) "
  for g in audio realtime gpio i2c spi input; do
    [[ "$groups" == *" $g "* ]] || { echo "we not in $g"; return 1; }
  done
}
# matron (as we) opens /dev/spidev0.0 (OLED data) and /dev/gpiochip0 (OLED
# D/C and reset). raspberrypi-sys-mods, whose 99-com.rules gives them to the
# spi and gpio groups, is not in the image, so without this rule both nodes
# are root:root 0600 and the screen stays blank.
@test "gpiochip and spidev nodes belong to the gpio and spi groups" {
  r=/etc/udev/rules.d/99-norns-gpio-spi.rules
  cmp "$REPO_ROOT/config/99-norns-gpio-spi.rules" "$ROOTFS$r"
  grep -qxF 'SUBSYSTEM=="gpio", KERNEL=="gpiochip*", GROUP="gpio", MODE="0660"' "$ROOTFS$r"
  grep -qxF 'SUBSYSTEM=="spidev", KERNEL=="spidev*", GROUP="spi", MODE="0660"' "$ROOTFS$r"
  for g in gpio spi; do
    gid=$(in_root getent group "$g" | cut -d: -f3)
    [ -n "$gid" ] && [ "$gid" -lt 1000 ] || { echo "$g: gid '$gid' is not a system group"; return 1; }
  done
  # syntax, and the group names resolve in the image
  in_root udevadm verify "$r"
}
# SYSTEM > UPDATE: ~/version.txt makes stable report "up to date"; for a
# beta (K1-alt) install the download into ~/update fails, as that is a
# root-owned directory made immutable at boot.
@test "update menu is inert" {
  [ "$(in_root cat /home/we/version.txt)" = "$NORNS_VERSION_TXT" ]
  [ "$(in_root stat -c '%U:%G %a %F' /home/we/update)" = "root:root 755 directory" ]
  [ -z "$(in_root find /home/we/update -mindepth 1)" ]
  u=/etc/systemd/system/norns-update-guard.service
  grep -qx 'ExecStart=/usr/bin/chattr +i /home/we/update' "$ROOTFS$u"
  grep -qx 'Before=norns.target' "$ROOTFS$u"
  in_root test -x /usr/bin/chattr
  [ "$(in_root systemctl is-enabled norns-update-guard.service)" = enabled ]
}
@test "home owned by we" {
  [ "$(in_root stat -c %U $N)" = we ]
  [ -z "$(in_root find $N /home/we/.local /home/we/version.txt ! -user we)" ]
}
