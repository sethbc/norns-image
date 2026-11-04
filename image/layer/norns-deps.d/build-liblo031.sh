#!/bin/bash
# Build liblo 0.31 into /opt/norns/liblo031 inside the root filesystem.
# usage: build-liblo031.sh <rootfs> <tag> <commit>
#
# Private to norns: matron's event_types.h restates liblo 0.31's
# `typedef void *lo_message`, which conflicts with trixie's liblo 0.32
# (`struct lo_message_ *`). Both are liblo.so.7, so this one stays off the
# loader path (no ld.so.conf entry); libmonome and norns find it through
# its pkg-config file and an rpath.
set -euo pipefail

root=$1
tag=$2
commit=$3
url=https://github.com/radarsat1/liblo
prefix=/opt/norns/liblo031

# autogen.sh would configure with --enable-debug (-O0, -Werror); configure
# directly instead. GCC 14 builds it cleanly, -Werror and all.
# shellcheck disable=SC2016  # expanded by the shell inside the chroot
chroot "$root" /bin/bash -euo pipefail -c '
  src=$(mktemp -d /tmp/liblo031.XXXXXX)
  trap "rm -rf -- $src" EXIT
  git clone --quiet --depth 1 --branch "$1" "$2" "$src"
  [ "$(git -C "$src" rev-parse HEAD)" = "$3" ] || {
    echo "liblo $1 is at $(git -C "$src" rev-parse HEAD), expected $3" >&2
    exit 1
  }
  cd "$src"
  NOCONFIGURE=1 ./autogen.sh
  ./configure --prefix="$4" --disable-static --disable-tests \
    --disable-network-tests --disable-tools --disable-examples
  make -j"$(nproc)"
  make install
  rm -f "$4"/lib/*.la
' _ "$tag" "$url" "$commit" "$prefix"
