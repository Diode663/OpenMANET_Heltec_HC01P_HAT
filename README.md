# OpenMANET on the Heltec HT-HC01P Raspberry Pi HAT

Run [OpenMANET](https://github.com/OpenMANET) on a Raspberry Pi fitted with the
[Heltec HT-HC01P HAT](https://heltec.org/project/ht-hc01p-hat/) and an
[HC01P / HC01P V2](https://heltec.org/project/hc01p-v2/) Wi-Fi HaLow module
(Morse Micro MM6108 over SPI). The HAT is not an officially supported board.
This repo adds it to the stock image; you don't have to rebuild the firmware.

**Tested:** Raspberry Pi 4B, OpenMANET 24.10 (1.8.0) `bcm2711 mm6108-spi` image,
HC01P V2 module on the HT-HC01P HAT. The mesh interface comes up and the
driver loads Heltec's BCF. Pi 3 and Zero 2 W images use the same overlay but
are untested.

## Why the stock image doesn't work

OpenMANET's SPI image is wired for the Seeed WM1302 HAT. Heltec's HAT uses
Morse Micro's eval-kit pinout instead (from Heltec's
[reference schematic](https://resource.heltec.cn/download/HT-HC01P/Reference_design/HT-HC01P_Raspberry_Pi_reference_design.PDF)):

| Signal | Heltec HAT | OpenMANET stock (Seeed) |
|---|---|---|
| CS / SCLK / MOSI / MISO | GPIO8 / 11 / 10 / 9 | same |
| IRQ | GPIO25 (pin 22) | GPIO5 |
| RESET | GPIO5 (pin 29) | GPIO17 |
| WAKE | GPIO3 (pin 5) | GPIO23 |
| BUSY | GPIO7 (pin 26) | GPIO24 |

The stock overlay has no parameters for changing pins, so this repo supplies a
replacement. Three more things need changing:

- **I2C1 has to be off.** GPIO3 is I2C1 SCL, and OpenMANET turns I2C1 on for Pi 3/4.
- **OpenMANET's GPS script has to be disabled.** `gpsboard.init` is written for
  the Seeed HAT, and at boot it holds GPIO25 low as a GPS reset line. On this
  HAT GPIO25 is the radio's IRQ. When the driver reloads, for example to apply
  a new BCF, it fails with `morse_spi_setup_irq() failed: -16`.
- **The init script can't be used to disable it.** Its `gpioset` daemons keep the
  script's procd lock, so `/etc/init.d/gpsboard.init disable` hangs. The
  installer removes the startup link directly instead.

## Files

| File | What it is |
|---|---|
| `heltec-hc01p-spi-overlay.dts` | Device tree overlay source: OpenMANET's `mm610x-spi` overlay with the Heltec pins, plus `gpio-line-names` so `MM_RESET` lands on GPIO5 for Morse's `chipreset.sh` |
| `heltec-hc01p-spi.dtbo` | The compiled overlay |
| `install.sh` | Installs everything on a running Pi: overlay, boot config edits, GPS script disable, BCF selection |
| `bcf/v2/bcf_HC01P-V2.bin` | Heltec's BCF (board configuration file) for the HC01P V2 module (tested) |
| `bcf/v1/bcf_HC0P.bin` | Heltec's BCF for the original HC01P module (untested). The file name is Heltec's own. |

The BCFs are Heltec's files, included unmodified from their
[driver 1.15.3 downloads](https://resource.heltec.cn/download/HT-HC01P_V2/BCF/driver_1_15_3/)
([V1](https://resource.heltec.cn/download/HT-HC01P/BCF/driver_1_15_3/)). They
are not covered by this repo's licences. Get the latest versions from Heltec.

## Install

1. Flash the stock OpenMANET **mm6108-spi** image for your Pi. Keep the stock
   image: OpenMANET recognises its board name (`bcm2711,mm6108-spi`).
2. Boot with Ethernet connected; HaLow won't work yet. Set the root password in
   the web UI.
3. Copy `install.sh`, `heltec-hc01p-spi.dtbo` and **only the BCF for your module**
   to the Pi. `install.sh` uses the first `bcf_*.bin` it finds next to itself,
   so don't copy both. Keep the `-O`: OpenWrt's SSH server usually doesn't
   support the default transfer mode of newer `scp` clients.

   ```sh
   ssh root@<pi_ip> "mkdir -p /root/heltec"
   scp -O install.sh heltec-hc01p-spi.dtbo bcf/v2/bcf_HC01P-V2.bin root@<pi_ip>:/root/heltec/
   ```

   For an original HC01P module, use `bcf/v1/bcf_HC0P.bin` instead.

4. Run the installer and reboot:

   ```sh
   ssh root@<pi_ip> "sh /root/heltec/install.sh && reboot"
   ```

5. If the installer said the HaLow radio wasn't in `/etc/config/wireless` yet,
   run it again after the reboot, then reboot once more. The script is safe to
   run repeatedly.

## Check it worked

```sh
ssh root@<pi_ip> "gpioinfo | grep -E 'MM_|gps'; dmesg | grep -iE 'Loaded BCF|probe failed'; iw dev"
```

Expected:

- line 25 `MM_IRQ` shows `consumer="mm610x_spi_irq_gpio"`, and no line shows `gps-wm1302`
- `Loaded BCF from morse/bcf_HC01P-V2.bin`, and no `probe failed`
- a `mesh point` interface (e.g. `wlh0`)

`iw` reports the HaLow channel with 5 GHz channel numbers and frequencies.
That's normal for the Morse driver; the radio is on sub-GHz. Connect the
antenna before transmitting.

Then configure the mesh in the OpenMANET web UI.

## Notes

- A sysupgrade rewrites the boot partition and can restore the GPS script. Re-run
  `install.sh` after upgrading.
- `install.sh` keeps `distroconfig.txt.orig` and `config.txt.orig` on the boot
  partition. To undo, restore them, re-enable the GPS script with
  `ln -s ../init.d/gpsboard.init /etc/rc.d/S21gpsboard.init`, and reboot.
- The HAT's RGB LED (GPIO2/6/16) and button (GPIO21) aren't used.
- To rebuild the overlay yourself:
  `dtc -@ -I dts -O dtb -o heltec-hc01p-spi.dtbo heltec-hc01p-spi-overlay.dts`

## Credits

- [OpenMANET discussion #50](https://github.com/orgs/OpenMANET/discussions/50):
  the first HC01P bring-up on OpenMANET, using jumper wires.
- The overlay is derived from OpenMANET's / Morse Micro's `mm610x-spi` overlay
  (OpenMANET firmware patch `991-0003`).

## Licence

- `heltec-hc01p-spi-overlay.dts` and `heltec-hc01p-spi.dtbo`: GPL-2.0, as a
  derivative of the Linux kernel device tree overlay they are based on. See `LICENSE-GPL-2.0`.
- `bcf/`: Heltec's files, not covered by either licence.
- Everything else: MIT. See `LICENSE-MIT`.

Not affiliated with Heltec, Morse Micro or the OpenMANET project.
