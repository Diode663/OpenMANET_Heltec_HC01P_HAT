#!/bin/sh
# SPDX-License-Identifier: MIT
# Install the Heltec HT-HC01P HAT overlay and BCF on a running OpenMANET Pi.
# Run from the folder holding heltec-hc01p-spi.dtbo and the bcf_*.bin, then reboot.
# Safe to run again; after the first reboot run it once more if it says the
# HaLow radio was not found yet.
set -e
cd "$(dirname "$0")"

# Boot (FAT) partition: use it where it is mounted, else mount partition 1
BOOT=$(awk '$3 == "vfat" { print $2; exit }' /proc/mounts)
if [ -z "$BOOT" ]; then
	BOOT=/boot
	mkdir -p "$BOOT"
	for dev in /dev/mmcblk0p1 /dev/sda1; do
		[ -b "$dev" ] && mount -t vfat "$dev" "$BOOT" && break
	done
fi
[ -f "$BOOT/distroconfig.txt" ] || { echo "No distroconfig.txt in $BOOT - boot partition not found"; exit 1; }
echo "Boot partition: $BOOT"

cp heltec-hc01p-spi.dtbo "$BOOT/overlays/"

[ -f "$BOOT/distroconfig.txt.orig" ] || cp "$BOOT/distroconfig.txt" "$BOOT/distroconfig.txt.orig"
[ -f "$BOOT/config.txt.orig" ] || cp "$BOOT/config.txt" "$BOOT/config.txt.orig"

sed -i 's/^dtoverlay=mm610x-spi[[:space:]]*$/dtoverlay=heltec-hc01p-spi/' "$BOOT/distroconfig.txt"
grep -q '^dtoverlay=heltec-hc01p-spi' "$BOOT/distroconfig.txt" || {
	echo "distroconfig.txt has no dtoverlay=mm610x-spi line - is this the mm6108-spi image?"
	exit 1
}
grep -q '^dtparam=i2c1=off' "$BOOT/config.txt" || printf '\n[all]\ndtparam=i2c1=off\n' >> "$BOOT/config.txt"
sync
echo "Overlay installed, I2C1 disabled"

# The Seeed-HAT GPS init holds GPIO25 as GPS reset; on this HAT GPIO25 is the
# MM6108 IRQ, so the driver cannot re-probe (morse_spi_setup_irq -16)
# Its gpioset daemons inherit the init script's procd lock, so calling
# "/etc/init.d/gpsboard.init disable" blocks forever; remove the link directly
if [ -e /etc/init.d/gpsboard.init ]; then
	rm -f /etc/rc.d/S??gpsboard.init /etc/rc.d/K??gpsboard.init
	killall gpioset 2>/dev/null || true
	echo "Disabled gpsboard.init (it claims GPIO25)"
fi

# BCF
BCF=$(ls bcf_*.bin 2>/dev/null | head -n 1)
if [ -n "$BCF" ]; then
	mkdir -p /lib/firmware/morse
	cp "$BCF" /lib/firmware/morse/
	RADIOS=$(uci show wireless | sed -n "s/^wireless\.\([^.]*\)\.type='morse'$/\1/p")
	if [ -n "$RADIOS" ]; then
		for r in $RADIOS; do
			uci set "wireless.$r.bcf=$BCF"
			echo "wireless.$r.bcf = $BCF"
		done
		uci commit wireless
	else
		echo "HaLow radio not in /etc/config/wireless yet - reboot, then run this script again to set the BCF"
	fi
else
	echo "No bcf_*.bin next to this script - BCF not changed"
fi

echo "Done. Reboot to apply: reboot"
