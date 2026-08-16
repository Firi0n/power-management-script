# ⚡ Universal Linux Laptop Power Management Script

An all-in-one, update-safe Bash script designed to optimize battery life and power management on hybrid-graphics Linux laptops (AMD/Intel + NVIDIA).

Tested and optimized for **CachyOS, Arch Linux, Fedora, Ubuntu, Debian, Manjaro, and Pop!_OS**.

---

## 🚀 Key Features

- **NVIDIA D3cold (0 Watt Idle):** Configures `NVreg_DynamicPowerManagement=0x02` to power down the discrete NVIDIA GPU completely when not in use.
- **Universal PCI & USB Runtime Power Management:** Installs `/etc/udev/rules.d/99-pci-pm.rules` and `99-usb-pm.rules` to enable runtime power management (`power/control="auto"`) across all PCI devices (NVMe SSDs, Wi-Fi, Ethernet, iGPU) and USB peripherals.
- **Audio Power Savings:** Enables `snd_hda_intel` power save modes (`power_save=1` and `power_save_controller=Y`) in `/etc/modprobe.d/audio-powersave.conf`.
- **Safe Operations & Automatic Backups (`write_with_backup`):** Checks existing configuration files before writing. If a file exists and differs, a timestamped backup (`.bak.YYYYMMDD-HHMMSS`) is saved automatically; identical files are skipped to avoid unnecessary disk I/O.
- **Deduplication Engine:** 
  - Prevents creating duplicate VRAM profiles in `/etc/nvidia/nvidia-application-profiles-rc.d/` if a matching profile (`GLVidHeapReuseRatio`) already exists.
  - Detects existing environment-based GPU forcing (`WLR_DRM_DEVICES`) before touching Niri's `config.kdl`.
- **NVIDIA Background Cleanup:** Safely masks `nvidia-powerd` and disables `nvidia-persistenced` to prevent background hardware polling loops.
- **Modular Niri Compositor Support (`--niri` / `-n`):** Dynamically detects the integrated GPU (AMD `amdgpu` or Intel `i915`/`xe`) render node and binds Niri compositor (`config.kdl`) to render exclusively on the iGPU.
- **Real-Time Battery Metering:** Displays current power draw (`energy-rate` in Watts) using `upower`.

---

## 📦 Usage & Options

### 1. Make the script executable
```bash
chmod +x setup-power-management.sh
```

### 2. Standard Execution (Any DE / WM)
```bash
sudo ./setup-power-management.sh
```

### 3. Usage with Niri Wayland Compositor
```bash
sudo ./setup-power-management.sh --niri
```
*(or `sudo ./setup-power-management.sh -n`)*

---

## 🛡️ Update-Safe & Permanent
All configuration files created by this script are located in `/etc/modprobe.d/` and `/etc/udev/rules.d/`. They are fully update-safe and will **never be overwritten** by distribution package updates (`pacman -Syu`).
