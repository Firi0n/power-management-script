# ⚡ Universal Linux Laptop Power Management Script

An all-in-one, update-safe Bash script designed to optimize battery life and power management on hybrid-graphics Linux laptops (AMD/Intel + NVIDIA).

Tested and optimized for **CachyOS, Arch Linux, Fedora, Ubuntu, Debian, Manjaro, and Pop!_OS**.

---

## 🚀 Key Features

- **NVIDIA D3cold (0 Watt Idle):** Configures `NVreg_DynamicPowerManagement=0x02` in `/etc/modprobe.d/nvidia-power.conf` to power down the discrete NVIDIA GPU completely when not in use.
- **Dedicated NVIDIA PCI Udev PM Rule:** Installs `/etc/udev/rules.d/80-nvidia-pm.rules` to enforce runtime power management (`power/control="auto"`) specifically for NVIDIA PCI devices across all system events.
- **Audio Power Saving:** Enables `snd_hda_intel` power save modes (`power_save=1` and `power_save_controller=Y`) in `/etc/modprobe.d/audio-powersave.conf`.
- **Safe Operations & Automatic Backups (`write_with_backup`):** Checks existing configuration files before writing. If a file exists and differs, a timestamped backup (`.bak.YYYYMMDD-HHMMSS`) is saved automatically; identical files are skipped to avoid unnecessary disk I/O.
- **Deduplication Engine:** 
  - Prevents creating duplicate VRAM profiles in `/etc/nvidia/nvidia-application-profiles-rc.d/` if a matching profile (`GLVidHeapReuseRatio`) already exists.
  - Detects existing environment-based GPU forcing (`WLR_DRM_DEVICES`) before modifying Niri's `config.kdl`.
- **NVIDIA Background Cleanup:** Safely masks `nvidia-powerd` and disables `nvidia-persistenced` to eliminate background hardware polling loops.
- **Modular Niri Compositor Support (`--niri` / `-n`):** Dynamically detects the integrated GPU (AMD `amdgpu` or Intel `i915`/`xe`) render node and binds Niri compositor (`config.kdl`) to render exclusively on the iGPU.
- **Real-Time Battery Metering:** Measures current power draw (`energy-rate` in Watts) using `upower`.

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

## 📌 Recommended Bootloader & Kernel Parameters

For optimal battery savings on AMD Ryzen + NVIDIA laptops, verify or add the following parameters to your bootloader command line:

- `nvidia.NVreg_DynamicPowerManagement=0x02` — Enables fine-grained D3cold GPU power state.
- `rcutree.enable_rcu_lazy=1` — Reduces CPU micro-interrupts during idle.

> [!WARNING]
> **DO NOT add `amdgpu.backlight=0`** to your bootloader parameters. Disabling AMD backlight forces display brightness control onto the NVIDIA WMI driver (`nvidia_wmi_ec_backlight`), causing the discrete GPU to wake up every time display brightness changes on battery power.

### Bootloader File Locations:
- **Limine:** Edit `/etc/default/limine`, then run `sudo limine-mkinitcpio`.
- **systemd-boot:** Edit `/etc/cmdline.d/power.conf`.
- **GRUB:** Edit `/etc/default/grub`, then run `sudo grub-mkconfig -o /boot/grub/grub.cfg`.

---

## 🛡️ Update-Safe & Permanent
All configuration files created by this script are stored in `/etc/modprobe.d/` and `/etc/udev/rules.d/`. They are fully update-safe and will **never be overwritten** by distribution package updates (`pacman -Syu`, `apt upgrade`, `dnf update`).
