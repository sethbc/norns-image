# norns-image

Builds the norns disk image: Raspberry Pi OS (Debian trixie, arm64) for
monome norns shields on Raspberry Pi 4 and 5, using
[rpi-image-gen](https://github.com/raspberrypi/rpi-image-gen).

## Supported hardware

| Hardware | Status |
|---|---|
| Raspberry Pi 4 + stock norns shield or shieldXL (CS4270) | Supported: phase 1, this image |
| Raspberry Pi 5 + shield | Boots to a shell; shield audio and controls pending |
| shieldXL UART MIDI | Later phase |
| CS4271 shields (211028 and later) | Detected, not yet tested on hardware |
| CM3 norns, PiSugar | Later phases |

What to check after flashing an image: [docs/testing/acceptance.md](docs/testing/acceptance.md).

## Building

```
git clone --recursive https://github.com/sethbc/norns-image   # add -b <branch or tag> as needed
cd norns-image
# once: rpi-image-gen's build dependencies (installs packages, hence sudo) ...
sudo vendor/rpi-image-gen/install_deps.sh
# ... and the rest, as CI installs them (.github/workflows/build.yml)
sudo apt-get install -y bats uidmap podman device-tree-compiler
./build.sh
tests/run.sh all     # optional: the unit tests and the built image's tests
```

Use a Debian or Ubuntu host. An arm64 host builds natively; on x86 also
install `qemu-user-binfmt` so the arm64 filesystem can run. The build runs
without root, in a podman user namespace, so your user needs a subordinate
uid/gid range in `/etc/subuid` and `/etc/subgid` (most distributions add one
when the user is created; CI adds `<user>:100000:65536`).
`./build.sh --fs-only` builds just the root filesystem, which is what
`tests/run.sh image` inspects; `--clean` removes `work/` and `out/` first.

The image lands in `out/` as `norns-trixie-arm64-<version>.img.zst`, with a
`.sha256`, an SBOM and a manifest (`out/image-name` holds the
`norns-trixie-arm64-<version>` prefix). Each build removes the previous
builds' images from `out/`.

Flash it with [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
(Use custom), or from a shell:

```
zstdcat out/norns-trixie-arm64-<version>.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Check the device name first; `dd` overwrites whatever you point it at. On
first boot the root partition grows to fill the card.

## Differences from monome's images

* The base is Raspberry Pi OS trixie (the monome images are bookworm-era), with
  one image booting both Pi 4 and Pi 5.
* NetworkManager is the network stack (systemd-networkd and iwd are disabled);
  polkit uses a JavaScript rule instead of a `.pkla` file; the samba service
  is `smbd`.
* No USB auto-mount. norns v2.9.4's SYSTEM menu has no SYNC page (DEVICES,
  WIFI, MODS, SETTINGS, RESTART, UPDATE), so nothing in norns needs it.
* No rsyslog, swap file, exim, nfs-common, triggerhappy, plymouth or
  modemmanager.
* norns is the unchanged v2.9.4 source, built for arm64 without `--release`
  through a compiler wrapper that drops the 32-bit ARM float flags and
  `-Werror` its build files add, and with waf 2.0.27 (the waf in the norns
  tree needs Python < 3.11). Both live in `/usr/local/lib/norns-build`.
  matron needs liblo 0.31 (trixie has 0.32) and libgpiod 1.x (trixie has
  2.x): private copies live in `/opt/norns`, and libmonome, matron and crone
  load that liblo through an rpath. GCC 14 needs two more flags; see
  `image/layer/norns-runtime.d/build-norns.sh`. To rebuild on the device, in
  `~/norns`:

  ```
  export PATH=/usr/local/lib/norns-build:$PATH \
    PKG_CONFIG_PATH=/opt/norns/liblo031/lib/pkgconfig:/opt/norns/libgpiod1/lib/pkgconfig \
    LDFLAGS=-Wl,-rpath,/opt/norns/liblo031/lib CXXFLAGS="-include string"
  CFLAGS=$(pkg-config --cflags glib-2.0) python3 /usr/local/lib/norns-build/waf configure
  python3 /usr/local/lib/norns-build/waf
  ```
* SuperCollider (3.13) comes from Debian. Its `sclang` is a Qt build, so the
  sclang unit sets `QT_QPA_PLATFORM=offscreen`.
* SYSTEM > UPDATE can't install anything: the monome update archives are for
  their own images. `~/update` is a root-owned directory made immutable at
  boot, so a download fails ("update failed."); the next key press shuts
  down as usual. Update by flashing a newer image.

## Logging in

Log in as `we`, password `sleep`: `ssh we@norns.local` (mDNS, through avahi),
or the IP address that SYSTEM > WIFI shows.

Wi-Fi is NetworkManager, driven from the norns menu:

* SYSTEM > WIFI > ADD joins a network (pick it, enter the password); CONNECT
  rejoins a saved one. Over ssh, `nmcli device wifi connect "My Wifi SSID"
  password "wifi-password"` does the same.
* SYSTEM > WIFI > HOTSPOT starts the norns hotspot (SSID `norns`, password
  `nnnnnnnn`); it does not start by itself. Over the hotspot the norns is
  `10.42.0.1`: `ssh we@10.42.0.1`.
