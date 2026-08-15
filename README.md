# ⚡ Universal Linux Laptop Power Management Script

An all-in-one, highly portable Bash script designed to optimize battery life and power management on hybrid-graphics Linux laptops (AMD/Intel + NVIDIA).

Tested and optimized for **CachyOS, Arch Linux, Fedora, Ubuntu, Debian, Manjaro, and Pop!_OS**.

---

## 🚀 Key Features

- **NVIDIA D3cold (0 Watt Idle):** Configures `NVreg_DynamicPowerManagement=0x02` to power down the discrete NVIDIA GPU completely when not in use.
- **Universal Udev PM Rule:** Applies PCIe runtime power management (`power/control="auto"`) across all system events (**Boot, Power Profile Switches, and AC Charger Unplugging**).
- **Auto Bootloader Detection:** Dynamically detects and updates **Limine**, **GRUB**, or **systemd-boot** with optimal kernel parameters (`amdgpu.backlight=0`, `rcutree.enable_rcu_lazy=1`).
- **NVIDIA Dynamic Boost & Persistence Cleanup:** Safely masks `nvidia-powerd` and disables `nvidia-persistenced` to prevent background hardware polling loops.
- **CPU Frequency & EPP Tuning:** Configures `energy_performance_preference=power` and `scaling_governor=powersave` across all CPU cores.
- **Modular Niri Compositor Support (`--niri` / `-n`):** Dynamically detects the integrated GPU (AMD `amdgpu` or Intel `i915`/`xe`) render node and configures Niri compositor and NVIDIA VRAM profiles (`50-niri.json`).

---

## 📦 Quick Start & Usage

### 1. Make the script executable
```bash
chmod +x setup-power-management.sh
```

### 2. Standard Usage (Any Desktop Environment or Window Manager)
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
All configuration files created by this script are located in `/etc/modprobe.d/`, `/etc/udev/rules.d/`, `/etc/nvidia/`, and `/etc/default/`. They will **never be overwritten** by distribution package updates (`pacman -Syu`, `apt upgrade`, `dnf update`).
