#!/bin/bash
# ============================================================================
# Void-Linux-UFI001B: Minimal Void Linux glibc for UFI001B (MSM8916)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$SCRIPT_DIR/build"
ROOTFS="$BUILD/rootfs"
OUT="$SCRIPT_DIR/out"

. "$SCRIPT_DIR/config/build.conf"

echo "==> Void-Linux-UFI001B (glibc/$ARCH)"

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
tar -Jxf "$TARBALL" -C "$ROOTFS" --strip-components=1

# Verify rootfs
if [ ! -d "$ROOTFS/usr" ]; then
    echo "ERROR: rootfs extraction failed" >&2
    ls -la "$ROOTFS" >&2
    exit 1
fi
echo "  rootfs OK: $(ls $ROOTFS | tr '\n' ' ')"

# --- copy qemu for cross-build ---
if [ "$(uname -m)" != "aarch64" ]; then
    if [ -f /usr/bin/qemu-aarch64-static ]; then
        cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/"
        echo "  qemu copied"
    else
        echo "  WARN: qemu-aarch64-static not found, skipping"
    fi
fi

# --- configure XBPS repos ---
mkdir -p "$ROOTFS/etc/xbps.d"
cat > "$ROOTFS/etc/xbps.d/00-repository-main.conf" << EOF
repository=$VOID_MIRROR
EOF

# --- mount virtual filesystems for chroot ---
mount --bind /dev "$ROOTFS/dev" 2>/dev/null || true
mount -t proc proc "$ROOTFS/proc" 2>/dev/null || true
mount -t sysfs sysfs "$ROOTFS/sys" 2>/dev/null || true
mount --bind /dev/pts "$ROOTFS/dev/pts" 2>/dev/null || true

cleanup() {
    umount "$ROOTFS/dev/pts" 2>/dev/null || true
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
    bash coreutils curl dnsmasq dropbear ethtool findutils grep \
    iproute2 iw kmod nano procps sed sudo tar udev usbutils \
    wget which wpa_supplicant xbps xz

# --- install Chinese fonts (optional) ---
chroot "$ROOTFS" xbps-install -y wqy-microhei 2>/dev/null || true

# --- locale ---
echo "==> configuring locale"
mkdir -p "$ROOTFS/etc/default"
echo "LANG=en_US.UTF-8" > "$ROOTFS/etc/locale.conf"

# --- root password ---
echo "root:root" | chroot "$ROOTFS" chpasswd

# --- hostname ---
echo "ufi001b" > "$ROOTFS/etc/hostname"

# --- fstab ---
cat > "$ROOTFS/etc/fstab" << 'EOF'
proc        /proc    proc    defaults   0       0
sysfs       /sys     sysfs   defaults   0       0
tmpfs       /tmp     tmpfs   defaults   0       0
EOF

# --- kernel ---
echo "==> installing kernel"
if [ ! -f "$BUILD/$KERNEL_APK" ]; then
    curl -fSL -o "$BUILD/$KERNEL_APK" \
        "$KERNEL_REPO/releases/download/v1.0/$KERNEL_APK" 2>/dev/null || true
fi
if [ -f "$BUILD/$KERNEL_APK" ]; then
    mkdir -p "$ROOTFS/boot"
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
cat > "$ROOTFS/usr/local/bin/iwlist" << 'IWEOF'
#!/bin/sh
IFACE=""
for arg in "$@"; do case "$arg" in wlan*|wl*) IFACE="$arg" ;; esac; done
[ -z "$IFACE" ] && { echo "Usage: iwlist <iface> scan"; exit 1; }
iw dev "$IFACE" scan 2>/dev/null | perl -pe 's/\\x([0-9a-fA-F]{2})/chr(hex($1))/ge' \
    | awk '/BSS /{b=substr($2,1,17);n++}/freq:/{f=$2}/signal:/{s=$2}/SSID:/{printf "Cell %d - %s  Freq:%s  Signal:%s  ESSID:\"%s\"\n",n,b,f,s,substr($0,index($0,": ")+2)}'
IWEOF
chmod 0755 "$ROOTFS/usr/local/bin/iwlist"

# --- enable runit services ---
echo "==> enabling services"
mkdir -p "$ROOTFS/var/service"
for svc in dropbear dnsmasq usb-gadget; do
    if [ -d "$ROOTFS/etc/sv/$svc" ]; then
        ln -sf "/etc/sv/$svc" "$ROOTFS/var/service/$svc"
        echo "  enabled: $svc"
    fi
done

# --- finalize ---
: > "$ROOTFS/root/.bash_history" 2>/dev/null || true
rm -rf "$ROOTFS/tmp"/*

# --- pack rootfs ---
echo "==> packing rootfs"
tar -cf "$OUT/rootfs.tar" -C "$ROOTFS" .

echo "==> build complete"
ls -lh "$OUT/"
du -sh "$ROOTFS"
