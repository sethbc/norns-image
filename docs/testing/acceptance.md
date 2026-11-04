# Acceptance checklist

Run by hand after flashing a release (or a CI-built image). Tick each box, and
record the outcome in the results table at the end.

Conventions: log in with `ssh we@norns.local` (user `we`, password `sleep`;
if mDNS is not working, use the IP that SYSTEM > WIFI shows, or `10.42.0.1`
over the norns hotspot, see A5). "Boot" means the first boot of a freshly
flashed card unless a step says otherwise. Commands run on the norns.

Flash the `.img.zst` with Raspberry Pi Imager (Use custom) or `zstdcat ... | sudo dd`
(see the README), using a card larger than the image so the grow step has work
to do.

## If something doesn't work

Every boot writes a diagnostics dump to the boot partition, so it can be read
without a screen or network: power off, put the SD card in your computer,
open the boot volume (`bootfs`) and read `norns-boot.log` (the previous
boot's is `norns-boot.prev.log`). It is written once the boot is done and
again 90 s after boot, and holds failed units, the norns, ssh and first-boot
units' status, this boot's warnings, the network addresses and listening
ports, the device nodes, the sound cards and the codec block of
`config.txt`. Attach it to any failure report.

## A. Pi 4 + shieldXL (the target)

### A1. First boot

- [ ] The norns screen lights and shows the norns UI within about two minutes. The
  device reboots once on the way, a few seconds into the first boot (see A2);
  that is expected. The checks below therefore run on the second boot and read
  the first boot's log with `-b -1`.
- [ ] Root filesystem grew to fill the card: `df -h /` shows a size close to the
  card's capacity, not the ~2 GB image size.
- [ ] The grow ran on the first boot and finished before the reboot:
  `journalctl -u norns-grow-root -b -1` shows growpart's
  `CHANGED: partition=2 ...`, resize2fs's `... is now ... blocks long` and the
  unit finishing without a failure. `systemctl is-enabled norns-grow-root`
  prints `disabled`: it runs once.

### A2. Codec detection and the single reboot

- [ ] The first boot rewrote `config.txt` and rebooted exactly once, and the next
  boot found it already correct:
  `journalctl -u norns-codec-detect -b -1` shows
  `norns-codec-detect: cs4270 found; /boot/firmware/config.txt updated, reboot needed`
  (exit status 10);
  `journalctl -u norns-codec-detect -b 0` shows no rewrite message and the unit
  finished with status 0 (`systemctl status norns-codec-detect`). If you power
  off during the first boot, check `-b 0` the same way after the second.
  Rebooting again does not reboot a third time.
- [ ] The managed block in `/boot/firmware/config.txt` holds the CS4270 overlay:
  `sed -n '/BEGIN norns-codec/,/END norns-codec/p' /boot/firmware/config.txt`
  prints `[pi4]` / `dtoverlay=norns-snd-cs4270`, `[pi5]` /
  `dtoverlay=norns-snd-cs4270-pi5`, `[all]`.
- [ ] The sound card is present: `aplay -l` lists card `sndrpimonome`
  (`snd-rpi-monome`). `arecord -l` lists it too.
- [ ] I2C bus node exists: `ls /dev/i2c-1`.
- [ ] Modules loaded: `lsmod | grep -E 'i2c_dev|snd_soc_cs4270'` prints both.
- [ ] DKMS built the codec for the running kernel:
  `dkms status` lists `monome-codecs/1.0` as `installed` for `$(uname -r)`.

### A3. Screen, keys, encoders

- [ ] The OLED shows the norns UI (home screen, not blank or garbled).
- [ ] matron (user `we`) can open the OLED's device nodes:
  `ls -l /dev/spidev0.0 /dev/gpiochip0` shows `crw-rw----` with group `spi`
  for `spidev0.0` and group `gpio` for `gpiochip0`.
- [ ] Input devices exist:
  `ls /dev/input/by-path/ | grep -E 'platform-keys-event|platform-soc:knob[123]-event'`
  prints four entries (`platform-keys-event`, `platform-soc:knob1-event`,
  `knob2`, `knob3`).
- [ ] K1, K2, K3 each respond in the UI (e.g. in the SYSTEM menu; K1 held opens
  the system menu). Keys rely on the shield's own pull-ups; a dead key is a
  hardware or overlay problem, not a software one.
- [ ] E1, E2, E3 each turn both ways and register in the UI.

### A4. Services and audio

- [ ] All norns units are active:
  `systemctl is-active norns-jack norns-crone norns-sclang norns-matron norns-maiden`
  prints `active` five times.
- [ ] JACK runs at 48 kHz, 128 frames:
  `ps -o args= -C jackd` shows `-r 48000 ... -p 128` and `hw:sndrpimonome`.
  `journalctl -u norns-jack` has no `xrun` lines. Check again after several
  minutes of playback: `journalctl -u norns-jack | grep -ci xrun` prints `0`.
- [ ] Audio in to out passes: feed a source into the shield's inputs, hear it at
  the outputs (norns passes input to output by default).
- [ ] Recording works: in the TAPE menu (K1 opens the menu, E1 moves to TAPE)
  record a few seconds of the input on the REC side, then play it back on the
  PLAY side (files land in `~/dust/audio/tape/`). `arecord`/`aplay` cannot
  open the card while JACK holds it; to use them instead, stop norns first
  with `~/norns/stop.sh`, run `arecord -D plughw:sndrpimonome -f dat -d 5
  test.wav` and `aplay -D plughw:sndrpimonome test.wav`, then start norns
  again with `~/norns/start.sh`.
- [ ] An engine plays. `~/dust/code` is empty on a fresh image, so first get a
  script: in maiden's project manager, on the `available` tab, refresh the
  catalogs and install `awake` (community catalog; needs internet), then on
  the norns choose HOME > SELECT > awake and hear notes. Without internet,
  load PolyPerc from maiden's REPL (matron):
  `engine.load("PolyPerc", function() engine.hz(440) end)` plays a note once
  the engine is up; `engine.hz(330)` plays another.
- [ ] sclang started headless:
  `journalctl -u norns-sclang -b | head -30` shows SuperCollider's startup with
  no Qt "could not connect to display" error, and
  `systemctl show norns-sclang -p Environment` includes
  `QT_QPA_PLATFORM=offscreen`.
- [ ] Memory with everything running (sclang is a Qt build; this records its
  cost): `free -m` after boot and after loading a script. Write both lines in
  the notes.

### A5. Network and sharing

- [ ] maiden loads at <http://norns.local> from another machine, and a script can
  be selected and run from it (the REPL accepts a command, e.g. `print("hi")`).
- [ ] SMB share reachable: `\\norns.local\dust` (Windows) or
  `smb://norns.local/dust` (macOS) mounts as user `we`, password `sleep`, and
  you can create and delete a file in it.
- [ ] Wi-Fi, joining a network: SYSTEM > WIFI > ADD lists the networks in
  range; pick yours and enter its password. The WIFI page then shows STATUS,
  NETWORK and IP, and `ssh we@norns.local` works over it. (Over ssh or a
  keyboard, `nmcli device wifi connect "My Wifi SSID" password "wifi-password"`
  does the same.) SYSTEM > WIFI > CONNECT rejoins a saved network.
- [ ] Wi-Fi, hotspot: it is not automatic (with no known network the norns just
  stays offline). SYSTEM > WIFI > HOTSPOT starts it: SSID `norns`, password
  `nnnnnnnn`. Join it from a computer; `ssh we@10.42.0.1` (NetworkManager's
  shared-mode address) works over it.
- [ ] A USB grid or other monome/MIDI device is detected: plug it in, then in the
  norns SYSTEM > DEVICES menu it appears (`lsusb` shows it too).

### A6. SYSTEM > UPDATE leaves the install alone

- [ ] `~/update` is immutable and empty: `lsattr -d ~/update` shows an `i` in the
  flags, and `ls -A ~/update` prints nothing. (`norns-update-guard` sets the
  flag every boot: `systemctl status norns-update-guard`.)
- [ ] SYSTEM > UPDATE, plain: reports "up to date." (`~/version.txt` is
  `260102`, the pinned norns release) and changes nothing.
- [ ] SYSTEM > UPDATE with K1-alt (stable or beta): shows "update failed."
  (the download cannot be written into the immutable directory). Crone and
  sclang stop; the next key press shuts the norns down as usual. Power it back
  on and confirm audio works again.
- [ ] Nothing changed: `git -C ~/norns status --short` and
  `git -C ~/maiden status --short` print nothing, and `cat ~/version.txt`
  still reads `260102`.

### A7. Kernel upgrade (DKMS)

- [ ] `sudo apt update && sudo apt full-upgrade`, then `sudo reboot`. This pulls a
  new kernel if one is available; if none is, note "no new kernel" and
  skip the next two lines.
- [ ] After the upgrade, `uname -r` shows the new kernel and
  `dkms status` shows `monome-codecs/1.0` installed for it (and for the other
  kernel flavour if both were upgraded).
- [ ] After the reboot: `lsmod | grep snd_soc_cs4270`, `aplay -l` shows
  `sndrpimonome`, the five units from A4 are active, and audio still
  plays.
- [ ] No extra reboot was triggered by norns-codec-detect
  (`journalctl -u norns-codec-detect -b 0` shows no "reboot needed").

### A8. Shutdown

- [ ] SLEEP on the norns HOME menu (HOME > SLEEP, then K3 at "sleep?") shuts the
  system down cleanly: the screen blanks, the Pi's activity LED stops, and on
  the next boot `journalctl -b -1 | tail` shows an orderly shutdown (no fsck
  repairs, no emergency mode).

## B. Pi 5 + shieldXL (smoke test only)

The shield's audio and controls are expected NOT to work on the Pi 5 yet
(phase 2). The point is that the same image boots and does not brick.

- [ ] The image boots on the Pi 5 and you can log in: `ssh we@norns.local`.
- [ ] `uname -r` ends in `-rpi-2712`.
- [ ] `df -h /` shows the root grew to fill the card.
- [ ] Note what happens with the shield attached (no audio card, dead keys) so
  phase 2 starts from facts: `aplay -l`, `ls /dev/input/by-path/`,
  `journalctl -u norns-codec-detect -b`.

## Known limits

* The CS4271 path (shields from 211028 on) is untested on real hardware; this
  checklist only exercises CS4270.
* Pi 5 shield support is a later phase.
* shieldXL UART MIDI is a later phase; it is not exercised here.
* PiSugar and CM3 norns are later phases.

## Results

One block per run. Copy the table, fill it in, commit.

| Field | Value |
|---|---|
| Date | |
| Hardware | |
| Image name | |
| Tester | |

| Section | Pass / fail | Notes |
|---|---|---|
| A1 First boot | | |
| A2 Codec detection | | |
| A3 Screen, keys, encoders | | |
| A4 Services and audio (`free -m`: ) | | |
| A5 Network and sharing | | |
| A6 SYSTEM > UPDATE | | |
| A7 Kernel upgrade | | |
| A8 Shutdown | | |
| B Pi 5 smoke | | |
