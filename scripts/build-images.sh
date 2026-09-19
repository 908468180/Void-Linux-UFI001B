#!/bin/sh -e
# build-images.sh - patch DTB, assemble boot/rootfs raw images and sparse them.
# Expects: $ROOTFS (extracted rootfs tree), $BUILD/files with aboot/hyp/rpm/sbl1/tz.
# Produces (into $BUILD/files):
#   boot.bin, rootfs.bin  - sparse Android images for fastboot

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/../config/build.conf"

WORK="$BUILD/work"

if [ -z "$ROOTFS" ]; then
    echo "ERROR: ROOTFS not set (extract rootfs tarball first)" >&2
    exit 1
fi

# --- patch device tree (overclock / memory release) ---
DTB="$ROOTFS/boot/dtbs/qcom/$KERNEL_DTB"
if [ ! -f "$DTB" ]; then
    echo "ERROR: $DTB not found" >&2
    exit 1
fi
python3 "$SCRIPT_DIR/../tools/patch_dtb.py" \
    --input "$DTB" \
    --output "$DTB" \
    --opp-mhz "$CPU_OPP_MHZ" \
    $([ "$RELEASE_MEMORY" = "1" ] && echo --release-memory || true)

# --- move /boot out of rootfs while assembling ---
mv "$ROOTFS/boot" "$WORK/boot-part"

echo "==> assembling /boot (64 MiB ext2)"
rm -f "$WORK/boot.raw"
truncate -s 67108864 "$WORK/boot.raw"
mkfs.ext2 -q -q -L boot -d "$WORK/boot-part" "$WORK/boot.raw"

echo "==> assembling rootfs (1.5 GiB ext4)"
rm -f "$WORK/rootfs.raw"
truncate -s 1610612736 "$WORK/rootfs.raw"
mkfs.ext4 -q -q -d "$ROOTFS" -E discard=on "$WORK/rootfs.raw"

mv "$WORK/boot-part" "$ROOTFS/boot"

echo "==> sparse images"
img2simg "$WORK/boot.raw" "$BUILD/files/boot.bin"
img2simg "$WORK/rootfs.raw" "$BUILD/files/rootfs.bin"

echo "==> checksums"
( cd "$BUILD/files" && sha256sum aboot.mbn hyp.mbn rpm.mbn sbl1.mbn tz.mbn \
    gpt_both0.bin boot.bin rootfs.bin > SHA256SUMS )

echo "==> flash package:"
ls -l "$BUILD/files"