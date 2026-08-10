#!/usr/bin/env bash
set -euo pipefail

# Logic verification: confirm root execution
if (( EUID != 0 )); then
    echo "Error: Root privileges required" >&2
    exit 1
fi

# Metric definitions
MODULE_NAME=hackberrypiq20
MODULE_VERSION=1.0
SRC_DIR=/usr/src/$MODULE_NAME-$MODULE_VERSION
DRIVER_SRC=hackberrypi-max17048.c
DTS_SRC=hackberrypicm5.dts
OVERLAY_PATH=/boot/overlays
OVERLAY_NAME=hackberrypiq20
BOOT_CONFIG=/boot/config.txt
REPO_URL=https://github.com/CNflysky/hackberrypiq20
REPO_DIR=hackberrypiq20
HYPERPIXEL_OVERLAY=dtoverlay=vc4-kms-dpi-hyperpixel4sq

# Shared DKMS teardown
# Logic: Used by both the uninstall path and the pre-install cleanup
remove_dkms_module() {
    dkms remove -m "$MODULE_NAME" -v "$MODULE_VERSION" --all 2>/dev/null || true
}

# Uninstall function
# Logic: Reverse all persistent system modifications and restore conflicting configurations
perform_uninstall() {
    echo "Deleting DKMS module..."
    remove_dkms_module
    echo "Removing source files..."
    rm -rf "$SRC_DIR"
    echo "Removing device tree overlay..."
    rm -f "$OVERLAY_PATH/$OVERLAY_NAME.dtbo"
    echo "Cleaning boot configuration..."
    sed -i "/dtoverlay=$OVERLAY_NAME/d" "$BOOT_CONFIG"
    grep -q "$HYPERPIXEL_OVERLAY" "$BOOT_CONFIG" || echo "$HYPERPIXEL_OVERLAY" >> "$BOOT_CONFIG"
    echo "Uninstall completed"
    exit 0
}

# Flag parsing
# Executed before dependencies to prevent redundant package manager invocation
while getopts u opt; do
    case $opt in
        u) perform_uninstall ;;
        *) echo "Usage: $0 [-u]" >&2; exit 1 ;;
    esac
done

# System dependency installation
# Requirement: Ensure tools for building and compilation are present
pacman -S --needed --noconfirm dkms git

# Repository acquisition logic
# Logic: If driver source is missing, clone or enter repository
if [ ! -f "$DRIVER_SRC" ]; then
    if [ ! -d "$REPO_DIR" ]; then
        git clone --depth 1 "$REPO_URL"
    fi
    cd "$REPO_DIR"
fi

# Baseline reset logic
# Logic: Best-effort revert to clean source. Not load-bearing: the patches below
# are individually guarded, so they stay correct when this is not a git checkout.
git checkout -- "$DRIVER_SRC" "$DTS_SRC" 2>/dev/null || true

# Modify existing DTS file for peripheral controller compatibility
grep -q 'interrupt-parent = <&rp1_gpio>;' "$DTS_SRC" || \
    sed -i 's/interrupt-parent = <&gpio>;/interrupt-parent = <\&rp1_gpio>;/' "$DTS_SRC"

# Cleanup existing module state
remove_dkms_module
rm -rf "$SRC_DIR"

# Local source modification
# Requirement: Modern kernel property handling compatibility
# Each patch is a no-op when already applied, so re-runs cannot stack edits
grep -q 'linux/property\.h' "$DRIVER_SRC" || \
    sed -i '1i #include <linux/property.h>' "$DRIVER_SRC"
grep -q 'psycfg\.fwnode' "$DRIVER_SRC" || \
    sed -i 's/psycfg\.of_node = dev->of_node;/psycfg.fwnode = dev_fwnode(dev);/' "$DRIVER_SRC"

# DKMS file migration
mkdir -p "$SRC_DIR"
cp "$DRIVER_SRC" dkms.conf Makefile "$SRC_DIR/"

# DKMS installation lifecycle
# Logic: install implies build implies add, per dkms(8)
dkms install -m "$MODULE_NAME" -v "$MODULE_VERSION"

# Device Tree Overlay compilation
# Logic: Compile to a temporary file alongside the target so a failed or
# interrupted dtc run cannot leave a truncated .dtbo in the boot partition.
# mktemp creates the file 0600, so the mode is set explicitly before the rename.
TMP_DTBO=$(mktemp "$OVERLAY_PATH/.$OVERLAY_NAME.XXXXXX")
trap 'rm -f "$TMP_DTBO"' EXIT
dtc -@ -I dts -O dtb -o "$TMP_DTBO" "$DTS_SRC"
chmod 0644 "$TMP_DTBO"
mv "$TMP_DTBO" "$OVERLAY_PATH/$OVERLAY_NAME.dtbo"

# Persistence logic for boot configuration
# Purges redundant overlay configuration and appends new target hardware overlay
sed -i "/$HYPERPIXEL_OVERLAY/d" "$BOOT_CONFIG"
grep -q "dtoverlay=$OVERLAY_NAME" "$BOOT_CONFIG" || echo "dtoverlay=$OVERLAY_NAME" >> "$BOOT_CONFIG"

# Execution summary
dkms status -m "$MODULE_NAME"
