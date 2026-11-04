# Shared bats helpers. Load from a test file with: load ../helpers

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pinned versions ($NORNS_COMMIT, $MAIDEN_TAG, ...) for every test.
set -a
# shellcheck source=../versions.env
. "$REPO_ROOT/versions.env"
set +a

# Root of the most recently built filesystem (written by build.sh).
ROOTFS="$(cat "$REPO_ROOT/out/rootfs-path" 2>/dev/null || true)"

# Fail the test unless build.sh has produced a filesystem to inspect.
require_rootfs() {
  if [ -z "$ROOTFS" ] || [ ! -d "$ROOTFS/etc" ]; then
    echo "no built rootfs (out/rootfs-path); run ./build.sh first" >&2
    return 1
  fi
}

# Skip unless the last build ran rpi-image-gen's image stage: its preimage
# hooks assemble /boot/firmware/config.txt and cmdline.txt, so a --fs-only
# build doesn't have them (CI always builds the image).
require_image_stage() {
  if [ "$(cat "$REPO_ROOT/out/build-kind" 2>/dev/null)" = fs-only ]; then
    skip "--fs-only build: config.txt and cmdline.txt are written at the image stage"
  fi
}

# Run a command inside the built arm64 filesystem (qemu-user binfmt). The
# chroot runs in rpi-image-gen's user namespace (podman unshare when not
# root): the build leaves files owned by subordinate uids, and only there do
# they map back to their in-image owners (sudo, for one, insists that
# /etc/sudoers is owned by uid 0).
in_root() {
  in_ns chroot "$ROOTFS" "$@"
}

# Run a host command in that user namespace, for tools that need what the
# built filesystem lacks (it has no /dev, so git inside it can't run).
in_ns() {
  NS_SETUP='_ns_setup() { :; }' "$REPO_ROOT/vendor/rpi-image-gen/bin/ns" "$@"
}

# Host path of a file inside the built filesystem.
rootfs_file() {
  printf '%s/%s\n' "$ROOTFS" "${1#/}"
}

# Compiled device tree overlays (tests/unit/overlays.bats compiles
# overlays/NAME-overlay.dts to $DTBO_DIR/NAME.dtbo).
dtbo_path() { printf '%s/%s.dtbo\n' "${DTBO_DIR:-$BATS_TMPDIR}" "$1"; }

# fdtdump of overlay NAME.
dtbo() { fdtdump "$(dtbo_path "$1")" 2>/dev/null; }

# Path in overlay NAME of the node labelled LABEL (from its __symbols__).
ov_path() { fdtget "$(dtbo_path "$1")" /__symbols__ "$2"; }

# Property PROP of the node labelled LABEL in overlay NAME.
ov_get() { fdtget "$(dtbo_path "$1")" "$(ov_path "$1" "$2")" "$3"; }

# target-path of the fragment that holds the node labelled LABEL in overlay
# NAME (the node it lands under in the live tree).
ov_frag_target() {
  local p
  p=$(ov_path "$1" "$2") || return
  p=${p#/}; p=/${p%%/*}
  fdtget "$(dtbo_path "$1")" "$p" target-path
}
