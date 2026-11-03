# norns-image

Builds the norns disk image: Raspberry Pi OS (Debian trixie, arm64) for
monome norns shields on Raspberry Pi 4 and 5, using
[rpi-image-gen](https://github.com/raspberrypi/rpi-image-gen).

## Building

```
git clone --recursive https://github.com/sethbc/norns-image   # add -b <branch or tag> as needed
cd norns-image
vendor/rpi-image-gen/install_deps.sh     # once; installs rpi-image-gen's build dependencies
./build.sh
```

Use a Debian or Ubuntu host with `qemu-user-binfmt` installed (or a native
arm64 host). `./build.sh --fs-only` builds just the root filesystem, which is
what `tests/run.sh image` inspects; `--clean` removes `work/` and `out/` first.

The image lands in `out/` as `norns-trixie-arm64-<version>.img.zst`, with a
`.sha256`, an SBOM and a manifest.

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

## start

* attach mini-usb to computer usb
* insert wifi adapter
* hold key 1 for 3 seconds
* rear LED shows orange for power, white for disk activity

## serial connection

* linux: `screen /dev/ttyACM0 115200`
* mac: `screen /dev/tty.ubserial(...) 115200` (fill in the serial number)
* windows: install [Putty](https://www.chiark.greenend.org.uk/~sgtatham/putty/) and connect with connection type "Serial" to serial line COM(...) and speed: 115200 (fill in comport number)

login is `we` and password is `sleep`

disconnect from `screen` (crtl-a-z)

## hotspot connect

connect to norns' wifi hotspot: SSID=norns PSK=nnnnnnnn

`ssh we@norns.local` (provided avahi is working) `ssh we@172.24.1.1` (if avahi is not working)

## switch norns wifi connection to external wifi network
* (`wifi.sh` is in the norns repo)
* `wifi.sh scan`
* `wifi.sh select "My Wifi SSID" "wifi-password"`
* `wifi-router.sh` (helper script to reconfigure network whilst ssh-ed in)
* `wifi-hotspot.sh` (switches back to hotspot mode whilst ssh-ed in)
