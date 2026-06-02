# Adding battery indicator to arch os for hackberry Pi CM5

This shell script is designed to manage the hackberrypiq20 hardware driver module.

## Functional Explanation

The script automates the compilation, configuration, and deployment of a device driver and device tree overlay for a hardware module on an Arch Linux distribution running on Raspberry Pi architecture.

---

## Usage Guide

### Prerequisites

The target system must run an Arch Linux operating system variant with root access enabled and network connectivity active.

### Installation

Run the script as root to perform full dependency installation, driver compilation, and boot registration:

```bash
git clone https://github.com/ppapak/HackberryPiCM5-arch-battery
cd HackberryPiCM5-arch-battery
chmod +x battery.sh
sudo ./battery.sh
```

### Uninstallation

Execute the script with the uninstallation flag to purge the kernel module, remove configuration changes, and roll back system modifications:

```bash
sudo ./installer.sh -u
```