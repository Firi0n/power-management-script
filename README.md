# ⚡ Universal Linux Laptop Power Management Script

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Arch Linux](https://img.shields.io/badge/Arch_Linux-Compatible-1793D1?logo=arch-linux&logoColor=white)](https://archlinux.org/)
[![CachyOS](https://img.shields.io/badge/CachyOS-Optimized-00A88F)](https://cachyos.org/)
[![NVIDIA D3cold](https://img.shields.io/badge/NVIDIA-D3cold_0W-76B900?logo=nvidia&logoColor=white)](https://www.nvidia.com/)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)

An all-in-one, update-safe Bash script designed to optimize battery life and power management on hybrid-graphics Linux laptops (AMD/Intel + NVIDIA).

Tested and optimized for **CachyOS, Arch Linux, Fedora, Ubuntu, Debian, Manjaro, and Pop!_OS**.

---

## 🚀 Key Features

- **Automatic Pre-Execution System Snapshot:** Automatically creates a system snapshot using **Snapper** or **Timeshift** before modifying system files, guaranteeing total safety and easy rollback.
- **NVIDIA D3cold (0 Watt Idle):** Configures `NVreg_DynamicPowerManagement=0x02` in `/etc/modprobe.d/nvidia-power.conf` to power down the discrete NVIDIA GPU completely when not in use.
- **Dedicated NVIDIA PCI Udev PM Rule:** Installs `/etc/udev/rules.d/80-nvidia-pm.rules` to enforce runtime power management (`power/control="auto"`) specifically for NVIDIA PCI devices across all system events.
- **Audio Power Saving:** Enables `snd_hda_intel` power save modes (`power_save=1` and `power_save_controller=Y`) in `/etc/modprobe.d/audio-powersave.conf`.
- **Safe Operations & Automatic Backups (`write_with_backup`):** Checks existing configuration files before writing. If a file exists and differs, a timestamped backup (`.bak.YYYYMMDD-HHMMSS`) is saved automatically; identical files are skipped to avoid unnecessary disk I/O.
- **In-Place Bootloader Patching (`--update-bootloader`):** Safely appends `nvidia.NVreg_DynamicPowerManagement=0x02` and `rcutree.enable_rcu_lazy=1` in-place without clobbering machine-specific UUIDs, subvolume flags, or existing boot loader options.
- **Multi-Layer Deduplication Engine:** 
  - Prevents creating duplicate VRAM profiles in `/etc/nvidia/nvidia-application-profiles-rc.d/` if a matching profile (`GLVidHeapReuseRatio`) already exists.
  - Detects existing GPU forcing (`WLR_DRM_DEVICES`) across shell configs, `uwsm` (`~/.config/uwsm/env`), `systemctl --user`, and user systemd service units before modifying Niri's `config.kdl`.
- **NVIDIA Power & Sleep Service Management:** Safely masks `nvidia-powerd` and disables `nvidia-persistenced` to eliminate background hardware polling loops, while enabling `nvidia-suspend`, `nvidia-hibernate`, and `nvidia-resume` services for clean VRAM state preservation across system sleep/wake cycles.
- **Modular Niri Compositor Support (`--niri` / `-n`):** Dynamically detects the integrated GPU (AMD `amdgpu` or Intel `i915`/`xe`) render node and binds Niri compositor (`config.kdl`) to render exclusively on the iGPU.
- **Read-Only System Diagnostic Mode (`--status` / `-s`):** Reports GPU D3cold power state, active NVIDIA processes, systemd services, kernel parameters, and live battery power draw without making any changes.
- **Dry-Run Preview Mode (`--dry-run` / `-d`):** Previews all file modifications without modifying disk contents.
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

### 3. Execution Options

| Flag | Short | Description |
| :--- | :---: | :--- |
| `--niri` | `-n` | Configures Niri Wayland compositor iGPU rendering |
| `--update-bootloader` | `-b` | In-place patches bootloader parameters without overwriting existing configs |
| `--status` | `-s` | Displays live GPU status, systemd services & power draw (Read-only, no root required) |
| `--dry-run` | `-d` | Previews actions without writing files or changing services |
| `--no-snapshot` | | Skips pre-execution Btrfs/Snapper/Timeshift snapshot |

#### Examples:
```bash
# Check live GPU and power status (no root required)
./setup-power-management.sh --status

# Preview modifications before executing
sudo ./setup-power-management.sh --dry-run

# Run full setup for Niri with automatic in-place bootloader patching
sudo ./setup-power-management.sh --niri --update-bootloader
```

---

## 🛠️ Bootloader Auto-Patching (`--update-bootloader` / `-b`)

When executed with the `--update-bootloader` (or `-b`) flag, the script automatically patches your bootloader command line in-place with optimal power-saving parameters:

- `nvidia.NVreg_DynamicPowerManagement=0x02` — Enables fine-grained D3cold GPU power state.
- `rcutree.enable_rcu_lazy=1` — Reduces AMD Ryzen CPU micro-interrupts during idle.

The script automatically detects **Limine**, **systemd-boot**, or **GRUB**, patches the configuration in-place without overwriting machine-specific settings (UUIDs, subvolumes, existing flags), and triggers bootloader updates (`limine-mkinitcpio`, etc.) automatically.

---

## 🛡️ Update-Safe & Permanent
All configuration files created by this script are stored in `/etc/modprobe.d/` and `/etc/udev/rules.d/`. They are fully update-safe and will **never be overwritten** by distribution package updates (`pacman -Syu`, `apt upgrade`, `dnf update`).
