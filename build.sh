#!/bin/bash
set -euo pipefail
# ============================================================================
# Void-Linux-UFI001B: Minimal Void Linux glibc for UFI001B (MSM8916)
# ============================================================================
# Features:
#   - USB RNDIS/ECM with DHCP (192.168.68.1)
#   - WiFi STA/AP via WCNSS
#   - SSH (dropbear)
#   - runit init (no systemd)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$SCRIPT_DIR/build"
ROOTFS="$BUILD/rootfs"
OUT="$SCRIPT_DIR/out"
XBPS_BIN="$ROOTFS/usr/bin/xbps-install"

. "$SCRIPT_DIR/config/build.conf"

echo "==> Void-Linux-UFI001B ($GLIBC/$ARCH)"

# --- clean ---
rm -rf "$BUILD"
mkdir -p "$BUILD" "$OUT"

# --- fetch Void ROOTFS tarball ---
TARBALL="$BUILD/$ROOTFS_TARBALL"
if [ ! -f "$TARBALL" ]; then
    echo "==> downloading Void ROOTFS"
    curl -fSL -o "$TARBALL" \
        "$VOID_MIRROR/live/current/$ROOTFS_TARBALL"
fi

# --- extract rootfs ---
echo "==> extracting rootfs"
mkdir -p "$ROOTFS"
tar -Jxf "$TARBALL" -C "$ROOTFS"

# --- copy qemu for cross-build ---
if [ "$(uname -m)" != "aarch64" ]; then
    cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/" 2>/dev/null || true
fi

# --- configure XBPS repos ---
mkdir -p "$ROOTFS/etc/xbps.d"
cat > "$ROOTFS/etc/xbps.d/00-repository-main.conf" << EOF
repository=$VOID_MIRROR
EOF

cat > "$ROOTFS/etc/xbps.d/00-repository-nonfree.conf" << EOF
repository=$VOID_MIRROR/nonfree
EOF

cat > "$ROOTFS/etc/xbps.d/00-repository-multilib.conf" << EOF
repository=$VOID_MIRROR/multilib
EOF

# --- mount virtual filesystems for chroot ---
mount --bind /dev "$ROOTFS/dev" 2>/dev/null || true
mount -t proc proc "$ROOTFS/proc" 2>/dev/null || true
mount -t sysfs sysfs "$ROOTFS/sys" 2>/dev/null || true

cleanup() {
    umount "$ROOTFS/dev" 2>/dev/null || true
    umount "$ROOTFS/proc" 2>/dev/null || true
    umount "$ROOTFS/sys" 2>/dev/null || true
}
trap cleanup EXIT

# --- sync repos ---
echo "==> syncing XBPS repos"
chroot "$ROOTFS" xbps-install -S

# --- install packages ---
echo "==> installing packages"
chroot "$ROOTFS" xbps-install -y \
    bash \
    coreutils \
    curl \
    dnsmasq \
    dropbear \
    ethtool \
    findutils \
    grep \
    iproute2 \
    iw \
    kmod \
    nano \
    net-tools \
    procps \
    sed \
    sudo \
    tar \
    udev \
    usbutils \
    wget \
    which \
    wpa_supplicant \
    xbps \
    xz

# --- install Chinese fonts ---
chroot "$ROOTFS" xbps-install -y wqy-microhei 2>/dev/null || true

# --- locale ---
# Void uses a different locale setup
chroot "$ROOTFS" bash -c 'echo "LANG=en_US.UTF-8" > /etc/locale.conf'
chroot "$ROOTFS" bash -c 'echo "en_US.UTF-8 UTF-8" >> /etc/default/libc-locales'
chroot "$ROOTFS" xbps-reconfigure -f glibc-locales 2>/dev/null || true

# --- root password ---
echo "root:root" | chroot "$ROOTFS" chpasswd

# --- hostname ---
echo "ufi001b" > "$ROOTFS/etc/hostname"

# --- fstab (noautomount, rely on kernel) ---
cat > "$ROOTFS/etc/fstab" << 'EOF'
# <device>  <mount>  <type>  <options>  <dump>  <pass>
proc        /proc    proc    defaults   0       0
sysfs       /sys     sysfs   defaults   0       0
tmpfs       /tmp     tmpfs   defaults   0       0
EOF

# --- kernel (extract APK) ---
echo "==> installing kernel"
if [ ! -f "$BUILD/$KERNEL_APK" ]; then
    curl -fSL -o "$BUILD/$KERNEL_APK" \
        "$KERNEL_REPO/releases/download/v1.0/$KERNEL_APK" 2>/dev/null || true
fi
if [ -f "$BUILD/$KERNEL_APK" ]; then
    mkdir -p "$ROOTFS/boot"
    # APK is just a tar.gz, extract kernel and DTB
    tar -zxf "$BUILD/$KERNEL_APK" -C "$ROOTFS/boot" 2>/dev/null || \
        cp "$BUILD/$KERNEL_APK" "$ROOTFS/boot/" 2>/dev/null || true
fi

# --- overlay ---
echo "==> overlay"
cp -a "$SCRIPT_DIR/overlay/." "$ROOTFS/"

# --- firmware ---
echo "==> firmware"
mkdir -p "$ROOTFS/lib/firmware/wlan/prima"
cp "$SCRIPT_DIR/vendor/lib/firmware/wcnss"*.mdt "$ROOTFS/lib/firmware/" 2>/dev/null || true
cp "$SCRIPT_DIR/vendor/lib/firmware/wcnss"*.b* "$ROOTFS/lib/firmware/" 2>/dev/null || true
cp "$SCRIPT_DIR/vendor/lib/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin" \
    "$ROOTFS/lib/firmware/wlan/prima/" 2>/dev/null || true

# --- iwlist wrapper ---
install -m 0755 /dev/stdin "$ROOTFS/usr/local/bin/iwlist" << 'EOF'
#!/bin/sh
IFACE=""
for arg in "$@"; do case "$arg" in wlan*|wl*) IFACE="$arg" ;; esac; done
[ -z "$IFACE" ] && { echo "Usage: iwlist <iface> scan"; exit 1; }
iw dev "$IFACE" scan 2>/dev/null | perl -pe 's/\\x([0-9a-fA-F]{2})/chr(hex($1))/ge' \
    | awk '/BSS /{b=substr($2,1,17);n++}/freq:/{f=$2}/signal:/{s=$2}/SSID:/{printf "Cell %d - %s  Freq:%s  Signal:%s  ESSID:\"%s\"\n",n,b,f,s,substr($0,index($0,": ")+2)}'
EOF

# --- enable runit services ---
echo "==> enabling services"
for svc in dropbear dnsmasq usb-gadget; do
    if [ -d "$ROOTFS/etc/sv/$svc" ]; then
        ln -sf "/etc/sv/$svc" "$ROOTFS/var/service/$svc"
    fi
done

# --- finalize ---
: > "$ROOTFS/root/.bash_history"
rm -rf "$ROOTFS/tmp"/*

echo "==> done"
du -sh "$ROOTFS"
