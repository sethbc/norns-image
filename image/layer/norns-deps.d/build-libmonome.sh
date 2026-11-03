#!/bin/bash
# Build libmonome into /usr/local inside the root filesystem.
# usage: build-libmonome.sh <rootfs> <tag> <commit>
#
# Linked against norns' private liblo 0.31 (build-liblo031.sh), with an
# rpath, so it and matron load the same liblo. libmonome's waf finds liblo
# with a plain compile check, so the flags come in through CFLAGS/LDFLAGS.
set -euo pipefail

root=$1
tag=$2
commit=$3
url=https://github.com/monome/libmonome

# shellcheck disable=SC2016  # expanded by the shell inside the chroot
chroot "$root" /bin/bash -euo pipefail -c '
  src=$(mktemp -d /tmp/libmonome.XXXXXX)
  trap "rm -rf -- $src" EXIT
  git clone --quiet --depth 1 --branch "$1" "$2" "$src"
  [ "$(git -C "$src" rev-parse HEAD)" = "$3" ] || {
    echo "libmonome $1 is at $(git -C "$src" rev-parse HEAD), expected $3" >&2
    exit 1
  }
  cd "$src"
  lo=/opt/norns/liblo031
  export CFLAGS="-I$lo/include" LDFLAGS="-L$lo/lib -Wl,-rpath,$lo/lib"
  python3 ./waf configure --prefix=/usr/local
  python3 ./waf
  python3 ./waf install
' _ "$tag" "$url" "$commit"

chroot "$root" ldconfig
