# Void Linux for UFI001B

Minimal Void Linux (glibc) for UFI001B 4G USB dongle (MSM8916).

## Features

- USB RNDIS/ECM with DHCP (192.168.68.1)
- WiFi STA/AP via WCNSS
- SSH (dropbear) - root/root
- runit init (no systemd)
- Chinese font support

## Build

```bash
# Requires: curl, xz, qemu-user-static (for cross-build)
bash build.sh
```

## Flash

```bash
# Requires: edl, fastboot
cd flash
bash flash-all.sh --backup  # first time: backup partitions
bash flash-all.sh           # flash
```

## SSH Access

```bash
# After boot, connect via USB RNDIS
ssh root@192.168.68.1
# Password: root
```

## WiFi

```bash
# Scan
iwlist wlan0 scan

# Connect
wpa_passphrase "SSID" "password" > /etc/wpa_supplicant.conf
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
udhcpc -i wlan0
```

## Package Management

```bash
xbps-install -S               # sync repos
xbps-install <package>        # install
xbps-remove <package>         # remove
xbps-query -Rs <keyword>      # search
```

## Services

runit services are in `/etc/sv/`. Enable by symlinking:

```bash
ln -s /etc/sv/dropbear /var/service/
ln -s /etc/sv/dnsmasq /var/service/
ln -s /etc/sv/usb-gadget /var/service/
```

## Credits

- [Void Linux](https://voidlinux.org/)
- [OpenStick-Builder](https://github.com/kinsamanka/OpenStick-Builder)
- [postmarketOS](https://postmarketos.org/)
