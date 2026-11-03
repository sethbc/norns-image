#!/bin/bash
# Build libgpiod v1 into /opt/norns/libgpiod1 inside the root filesystem.
# usage: build-libgpiod1.sh <rootfs> <tag> <commit>
set -euo pipefail

root=$1
tag=$2
commit=$3
url=https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git
prefix=/opt/norns/libgpiod1

# shellcheck disable=SC2016  # expanded by the shell inside the chroot
chroot "$root" /bin/bash -euo pipefail -c '
  src=$(mktemp -d /tmp/libgpiod1.XXXXXX)
  trap "rm -rf -- $src" EXIT
  git clone --quiet --depth 1 --branch "$1" "$2" "$src"
  [ "$(git -C "$src" rev-parse HEAD)" = "$3" ] || {
    echo "libgpiod $1 is at $(git -C "$src" rev-parse HEAD), expected $3" >&2
    exit 1
  }
  cd "$src"
  ./autogen.sh --prefix="$4" --enable-tools=no
  make -j"$(nproc)"
  make install
' _ "$tag" "$url" "$commit" "$prefix"

# libgpiod.so.2 comes from here, next to trixie's libgpiod.so.3.
echo "$prefix/lib" > "$root/etc/ld.so.conf.d/norns-libgpiod1.conf"
chroot "$root" ldconfig
