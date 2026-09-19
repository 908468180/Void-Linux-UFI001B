#!/bin/sh -e
# fetch-firmware.sh - fetch stock Qualcomm firmware (rpm/sbl1/tz) and
# generate the partition table.
# Produces (into $BUILD/files):
#   rpm.mbn, sbl1.mbn, tz.mbn  - stock, unchanged
#   gpt_both0.bin              - generated partition table

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/../config/build.conf"

mkdir -p "$BUILD/work" "$BUILD/files"

# --- stock Qualcomm firmware (rpm/sbl1/tz) ---
FNAME=$(basename "$DB410C_FW_URL")
if [ ! -f "$BUILD/work/$FNAME" ]; then
    echo "==> downloading $DB410C_FW_URL"
    wget --no-verbose -O "$BUILD/work/$FNAME" "$DB410C_FW_URL"
fi
echo "$DB410C_FW_SHA256  $BUILD/work/$FNAME" | sha256sum -c - || {
    echo "ERROR: $FNAME sha256 mismatch" >&2
    exit 1
}

if [ ! -f "$BUILD/files/rpm.mbn" ]; then
    unzip -o -j -d "$BUILD/files" "$BUILD/work/$FNAME" \
        "$DB410C_FW_ZIP/rpm.mbn" "$DB410C_FW_ZIP/sbl1.mbn" "$DB410C_FW_ZIP/tz.mbn"
fi

# --- partition table ---
python3 "$SCRIPT_DIR/../tools/make_gpt.py" \
    --total-sectors "$DISK_TOTAL_SECTORS" \
    --output "$BUILD/files/gpt_both0.bin" \
    --info

echo "==> firmware artifacts:"
ls -l "$BUILD/files/rpm.mbn" "$BUILD/files/sbl1.mbn" "$BUILD/files/tz.mbn" "$BUILD/files/gpt_both0.bin"