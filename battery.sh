#!/bin/bash
set -e

# Logic verification: confirm root execution
(( EUID != 0 )) && echo Error:\ Root\ privileges\ required && exit 1

# Metric definitions
MODULE_NAME=hackberrypiq20
MODULE_VERSION=1.0
SRC_DIR=/usr/src/$MODULE_NAME-$MODULE_VERSION
DRIVER_SRC=hackberrypi-max17048.c
DTS_SRC=hackberrypicm5.dts
OVERLAY_PATH=/boot/overlays
REPO_URL=https://github.com/CNflysky/hackberrypiq20
REPO_DIR=hackberrypiq20

# Uninstall function
# Logic: Reverse all persistent system modifications and restore conflicting configurations
perform_uninstall() {
    echo Deleting\ DKMS\ module...
    dkms remove -m $MODULE_NAME -v $MODULE_VERSION --all 2>/dev/null || true
    echo Removing\ source\ files...
    rm -rf $SRC_DIR
    echo Removing\ device\ tree\ overlay...
    rm -f $OVERLAY_PATH/hackberrypiq20.dtbo
    echo Cleaning\ boot\ configuration...
    sed -i /dtoverlay=hackberrypiq20/d /boot/config.txt
    grep -q dtoverlay=vc4-kms-dpi-hyperpixel4sq /boot/config.txt || echo dtoverlay=vc4-kms-dpi-hyperpixel4sq >> /boot/config.txt
    echo Uninstall\ completed
    exit 0
}

# Flag parsing
# Executed before dependencies to prevent redundant package manager invocation
while getopts u opt; do
    case $opt in
        u) perform_uninstall ;;
        *) echo Usage:\ $0\ [-u]; exit 1 ;;
    esac
done

# System dependency installation
# Requirement: Ensure tools for building and compilation are present
pacman -S dkms git

# Repository acquisition logic
# Logic: If driver source is missing, clone or enter repository
if [ ! -f $DRIVER_SRC ]; then
    if [ ! -d $REPO_DIR ]; then
        git clone $REPO_URL
    fi
    cd $REPO_DIR
fi

# Baseline reset logic
# Logic: Revert local edits to ensure sed operations start from clean source
git checkout $DRIVER_SRC
git checkout $DTS_SRC

# Modify existing DTS file for peripheral controller compatibility
sed -i s/interrupt-parent\ =\ \<\&gpio\>\;/interrupt-parent\ =\ \<\\\&rp1_gpio\>\;/ $DTS_SRC

# Cleanup existing module state
dkms remove -m $MODULE_NAME -v $MODULE_VERSION --all 2>/dev/null || true
rm -rf $SRC_DIR

# Local source modification
# Requirement: Modern kernel property handling compatibility
sed -i 1i\#include\ \<linux/property.h\> $DRIVER_SRC
sed -i s/psycfg.of_node\ =\ dev-\>of_node\;/psycfg.fwnode\ =\ dev_fwnode\(dev\)\;/ $DRIVER_SRC

# DKMS file migration
mkdir -p $SRC_DIR
cp $DRIVER_SRC $SRC_DIR/
cp dkms.conf $SRC_DIR/
cp Makefile $SRC_DIR/

# DKMS installation lifecycle
dkms add -m $MODULE_NAME -v $MODULE_VERSION
dkms build -m $MODULE_NAME -v $MODULE_VERSION
dkms install -m $MODULE_NAME -v $MODULE_VERSION

# Device Tree Overlay compilation
dtc -@ -I dts -O dtb -o $OVERLAY_PATH/hackberrypiq20.dtbo $DTS_SRC

# Persistence logic for boot configuration
# Purges redundant overlay configuration and appends new target hardware overlay
sed -i /dtoverlay=vc4-kms-dpi-hyperpixel4sq/d /boot/config.txt
grep -q dtoverlay=hackberrypiq20 /boot/config.txt || echo dtoverlay=hackberrypiq20 >> /boot/config.txt

# Execution summary
dkms status