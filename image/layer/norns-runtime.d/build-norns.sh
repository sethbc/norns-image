#!/bin/bash
# Build monome's norns from its release tag, unchanged, into /home/we/norns,
# and install what runs it: SC classes, systemd units, groups, update guard.
# usage: build-norns.sh <rootfs> <repo-dir> <tag> <commit> <version-txt> \
#                       <waf-url> <waf-sha256>
#
# The sources stay byte-identical to the tag. Their wscripts target 32-bit
# ARM (-mfpu=..., -mfloat-abi=...) and build with -Werror, so the build runs
# with scripts/norns-cc-wrapper first on PATH (and as CC/CXX), which drops
# those flags. No --release: that only adds Cortex-A53/32-bit tuning. The
# waf 2.0.14 in the norns tree can't run on trixie's Python 3.13 (it imports
# imp and opens files with mode 'rU'), so the unchanged wscripts are run by
# a pinned, checksum-verified waf 2.0.x installed next to the wrapper.
#
# Build environment for trixie (GCC 14, liblo 0.31 from norns-deps); every
# flag added here fixes a build error of the unchanged source:
#   PKG_CONFIG_PATH  /opt/norns/liblo031 and /opt/norns/libgpiod1 first:
#                    matron's `typedef void *lo_message` (event_types.h:7)
#                    conflicts with liblo 0.32's struct-pointer typedef
#                    ("conflicting types for 'lo_message'", plus GCC 14's
#                    default-error -Wincompatible-pointer-types for every
#                    lo_server_thread_add_method handler); matron needs the
#                    libgpiod v1 API.
#   LDFLAGS          -Wl,-rpath,/opt/norns/liblo031/lib: that liblo is off
#                    the loader path (same soname as trixie's), so matron and
#                    crone load it, as libmonome does, through an rpath.
#   CFLAGS           $(pkg-config --cflags glib-2.0): matron's device_hid.c
#                    includes <glib.h> ("fatal error: glib.h: No such file
#                    or directory"); on bullseye a checked package's cflags
#                    happened to bring glib's include path, on trixie none do.
#   CXXFLAGS         -include string: crone's BufDiskWorker.h uses
#                    std::string without <string> ("field 'path' has
#                    incomplete type 'std::string'"), which GCC 14's
#                    libstdc++ no longer pulls in through other headers.
#
# Update guard (SYSTEM > UPDATE must not touch ~/norns or ~/maiden).
# lua/core/menu/update.lua at the tag:
#   - plain UPDATE compares ~/version.txt with releases.stable.version from
#     monome's releases.txt (curl); we write NORNS_VERSION_TXT there, so for
#     the stable release it says "up to date." and stops.
#   - K1-alt (stable or beta), or once monome publishes a newer stable: it
#     stops norns-crone and norns-sclang, runs `sudo rm -rf /home/we/update/*`,
#     then, as we, `wget -P /home/we/update/ <tgz> <sha256>`. ~/update is a
#     root-owned 0755 directory that norns-update-guard.service makes
#     immutable at boot, so the rm removes nothing and wget cannot write
#     ("Permission denied"). The download callback then runs
#     `sha256sum -c /home/we/update/*.sha256 | grep OK`, which finds no file
#     and prints no OK, so the menu shows "update failed." and never unpacks
#     or runs update.sh. It does not return to the menu: the next key press
#     runs `sudo shutdown now` (stage "done"), and audio (crone, sclang) stays
#     stopped until then. After the reboot everything is as before.
#   The immutable flag is set on the device, not here: inode flags don't
#   survive the image build, and an immutable dir would block cleaning the
#   work tree. systemd-tmpfiles can't do it either: it refuses the root-owned
#   ~/update under the we-owned ~ ("unsafe path transition").
set -euo pipefail

root=$1
repo=$2
tag=$3
commit=$4
version_txt=$5
waf_url=$6
waf_sha256=$7
url=https://github.com/monome/norns
wrapdir=/usr/local/lib/norns-build

# Compiler wrapper: cc/gcc/c++/g++ symlinks run /usr/bin/<name> through it.
install -D -m 0755 "$repo/scripts/norns-cc-wrapper" "$root$wrapdir/norns-cc-wrapper"
for cc in cc gcc c++ g++; do
  ln -sfn norns-cc-wrapper "$root$wrapdir/$cc"
done

# waf, unpacked now (as root) so we can run it from the root-owned dir.
# shellcheck disable=SC2016  # expanded by the shell inside the chroot
chroot "$root" /bin/bash -euo pipefail -c '
  curl -fsSL --retry 3 -o "$1/waf" "$2"
  echo "$3  $1/waf" | sha256sum -c --quiet
  chmod 0755 "$1/waf"
  cd / && python3 "$1/waf" --version
' _ "$wrapdir" "$waf_url" "$waf_sha256"

# Groups: realtime (limits.d/99-realtime.conf), audio for JACK, and the
# device nodes matron opens (gpiochip0, spidev0.0, i2c-1, /dev/input/*).
# gpio and spi own gpiochip* and spidev* through 99-norns-gpio-spi.rules, so
# they must exist whatever the base layers create.
for g in realtime gpio spi; do
  chroot "$root" groupadd --system --force "$g"
done
install -D -m 0644 "$repo/config/99-norns-gpio-spi.rules" "$root/etc/udev/rules.d/99-norns-gpio-spi.rules"
groups=audio,realtime
for g in gpio i2c spi input; do
  if chroot "$root" getent group "$g" >/dev/null; then groups+=,$g; fi
done
chroot "$root" usermod -a -G "$groups" we

# norns, built as we so everything under ~/norns is we's.
# shellcheck disable=SC2016  # expanded by the shell inside the chroot
chroot "$root" setpriv --reuid=we --regid=we --init-groups \
  env -i HOME=/home/we USER=we LOGNAME=we LANG=C.UTF-8 \
    PATH="$wrapdir:/usr/local/bin:/usr/bin:/bin" \
    CC="$wrapdir/gcc" CXX="$wrapdir/g++" \
    PKG_CONFIG_PATH=/opt/norns/liblo031/lib/pkgconfig:/opt/norns/libgpiod1/lib/pkgconfig \
    LDFLAGS=-Wl,-rpath,/opt/norns/liblo031/lib \
    CXXFLAGS="-include string" \
  /bin/bash -euo pipefail -c '
  cd /home/we
  git clone --quiet --depth 1 --branch "$1" "$2" norns
  [ "$(git -C norns rev-parse HEAD)" = "$3" ] || {
    echo "norns $1 is at $(git -C norns rev-parse HEAD), expected $3" >&2
    exit 1
  }
  cd norns
  git submodule --quiet update --init --recursive --depth 1
  CFLAGS=$(pkg-config --cflags glib-2.0) python3 "$4/waf" configure
  python3 "$4/waf" build
  mkdir -p /home/we/.local/share/SuperCollider/Extensions
  cd sc && ./install.sh
' _ "$tag" "$url" "$commit" "$wrapdir"

# shellcheck disable=SC2016  # expanded by the shell inside the chroot
chroot "$root" setpriv --reuid=we --regid=we --init-groups \
  sh -c 'printf "%s\n" "$1" > /home/we/version.txt' _ "$version_txt"

# Update guard (see above): an empty root-owned ~/update, made immutable on
# every boot by norns-update-guard.service.
chroot "$root" install -d -m 0755 -o root -g root /home/we/update

# systemd units (maiden's binary comes from a later layer)
for f in "$repo"/config/norns-*.service "$repo"/config/norns-*.socket "$repo"/config/norns.target; do
  install -m 0644 "$f" "$root/etc/systemd/system/${f##*/}"
done
chroot "$root" systemctl enable norns.target norns-update-guard.service
