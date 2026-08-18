#!/usr/bin/env bash
# ==============================================================================
# UNIVERSAL LAPTOP POWER MANAGEMENT SCRIPT — HYBRID GRAPHICS (AMD/INTEL + NVIDIA)
# Compatible with CachyOS / Arch Linux / Fedora / Ubuntu / Debian / Manjaro / Pop!_OS
#
# Features:
# - Automatic pre-execution Btrfs/Snapper/Timeshift snapshot creation
# - Safe Operation: Timestamped backups before overwriting any existing file
# - Niri Wayland compositor support (--niri / -n)
# - Bootloader auto-configuration option (--update-bootloader / -b)
# - System status & diagnostic view (--status / -s)
# - Dry-run preview mode (--dry-run / -d)
#
# Usage: sudo ./setup-power-management.sh [options]
#   Options:
#     -n, --niri              Configure Niri compositor iGPU rendering
#     -b, --update-bootloader Automatically add optimal kernel parameters to bootloader
#     -s, --status            Show system power status and GPU diagnostics (read-only)
#     -d, --dry-run           Preview actions without writing files
#     --no-snapshot           Skip pre-execution system snapshot
# ==============================================================================
set -e

APPLY_NIRI=false
UPDATE_BOOTLOADER=false
STATUS_MODE=false
DRY_RUN=false
TAKE_SNAPSHOT=true

for arg in "$@"; do
  case $arg in
    -n|--niri)
      APPLY_NIRI=true
      ;;
    -b|--update-bootloader)
      UPDATE_BOOTLOADER=true
      ;;
    -s|--status)
      STATUS_MODE=true
      ;;
    -d|--dry-run)
      DRY_RUN=true
      ;;
    --no-snapshot)
      TAKE_SNAPSHOT=false
      ;;
    -h|--help)
      echo "Usage: sudo ./setup-power-management.sh [options]"
      echo "  -n, --niri              Configure Niri compositor iGPU rendering"
      echo "  -b, --update-bootloader Automatically patch bootloader parameters"
      echo "  -s, --status            Show live power & GPU status (read-only)"
      echo "  -d, --dry-run           Preview actions without modifying disk"
      echo "  --no-snapshot           Skip pre-execution Btrfs/Snapper snapshot"
      exit 0
      ;;
  esac
done

# ------------------------------------------------------------------------------
# 🔍 STATUS / DIAGNOSTIC MODE (-s / --status)
# ------------------------------------------------------------------------------
if [ "$STATUS_MODE" = true ]; then
  echo "=============================================================================="
  echo " 📊 SYSTEM POWER & GPU DIAGNOSTIC STATUS"
  echo "=============================================================================="
  
  echo -e "\n🎮 NVIDIA GPU Power State:"
  if [ -f /sys/bus/pci/devices/0000:01:00.0/power/runtime_status ]; then
    GPU_STAT=$(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status 2>/dev/null || echo "unknown")
    if [ "$GPU_STAT" = "suspended" ]; then
      echo "    → Runtime Status: SUSPENDED (0W Idle - D3cold active) ✅"
    else
      echo "    → Runtime Status: $GPU_STAT ⚡"
    fi
  else
    echo "    → NVIDIA PCI sysfs node not found."
  fi

  echo -e "\n🔍 Processes using NVIDIA Device Files:"
  LSOF_OUT=$(lsof /dev/nvidia* 2>/dev/null | head -n 10 || true)
  if [ -n "$LSOF_OUT" ]; then
    echo "$LSOF_OUT"
  else
    echo "    → No processes currently holding NVIDIA device nodes."
  fi

  echo -e "\n⚙️  Systemd Power Services:"
  systemctl is-enabled nvidia-powerd nvidia-persistenced nvidia-suspend nvidia-hibernate nvidia-resume 2>/dev/null || true

  echo -e "\n💻 Current Kernel Command Line (/proc/cmdline):"
  cat /proc/cmdline

  echo -e "\n🔋 Live Battery Power Metering:"
  BAT_PATH=$(upower -e | grep BAT | head -n 1 || true)
  if [ -n "$BAT_PATH" ]; then
    upower -i "$BAT_PATH" | grep -iE 'energy-rate|percentage|state|time to empty'
  else
    echo "    → Battery status not found (AC power connected)."
  fi
  exit 0
fi

if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Please run this script with root privileges (sudo)!"
  echo "Usage: sudo ./setup-power-management.sh [options]"
  exit 1
fi

# ------------------------------------------------------------------------------
# 📸 PRE-EXECUTION SNAPSHOT FUNCTION
# ------------------------------------------------------------------------------
take_pre_snapshot() {
  if [ "$TAKE_SNAPSHOT" = false ] || [ "$DRY_RUN" = true ]; then
    return 0
  fi

  echo "=== 📸 Pre-Execution System Snapshot ==="
  if command -v snapper >/dev/null 2>&1; then
    echo "    → Creating Snapper pre-execution snapshot..."
    snapper create --description "Pre-execution snapshot for power-management-script" --cleanup-algorithm number 2>/dev/null \
      && echo "    → Snapper snapshot created successfully." || echo "    → Snapper snapshot skipped or not configured."
  elif command -v timeshift >/dev/null 2>&1; then
    echo "    → Creating Timeshift pre-execution snapshot..."
    timeshift --create --comments "Pre-execution snapshot for power-management-script" --tags D 2>/dev/null \
      && echo "    → Timeshift snapshot created successfully." || echo "    → Timeshift snapshot skipped."
  else
    echo "    → Neither Snapper nor Timeshift found. Skipping automatic snapshot."
  fi
}

# ------------------------------------------------------------------------------
# Helper: Write file only after creating a timestamped backup if it already exists
# ------------------------------------------------------------------------------
write_with_backup() {
  local target="$1"
  local tmpfile
  tmpfile=$(mktemp)
  cat > "$tmpfile"

  if [ "$DRY_RUN" = true ]; then
    echo "    [DRY-RUN] Would write to $target"
    rm -f "$tmpfile"
    return 0
  fi

  if [ -f "$target" ]; then
    if cmp -s "$target" "$tmpfile"; then
      echo "    → $target is identical, skipping write"
      rm -f "$tmpfile"
      return 0
    fi
    local backup="${target}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$target" "$backup"
    echo "    → $target exists and differs: backup saved to $backup"
  fi

  mv "$tmpfile" "$target"
  echo "    → $target written successfully"
}

# Execute snapshot
take_pre_snapshot

echo "=== 1. NVIDIA Modprobe Configuration (/etc/modprobe.d/nvidia-power.conf) ==="
write_with_backup /etc/modprobe.d/nvidia-power.conf << 'EOF'
options nvidia NVreg_DynamicPowerManagement=0x02
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia-drm modeset=1 fbdev=1
EOF

echo "=== 2. NVIDIA Udev PM Rules Configuration (/etc/udev/rules.d/80-nvidia-pm.rules) ==="
write_with_backup /etc/udev/rules.d/80-nvidia-pm.rules << 'EOF'
# Enable runtime PM for all NVIDIA PCI devices on any udev event (boot, change, unplug)
SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", TEST=="power/control", ATTR{power/control}="auto"
EOF

echo "=== 3. Audio Power Saving Configuration (/etc/modprobe.d/audio-powersave.conf) ==="
write_with_backup /etc/modprobe.d/audio-powersave.conf << 'EOF'
options snd_hda_intel power_save=1 power_save_controller=Y
EOF

if [ "$APPLY_NIRI" = true ]; then
  echo "=== 4. NVIDIA VRAM Application Profile for Niri ==="
  mkdir -p /etc/nvidia/nvidia-application-profiles-rc.d/

  EXISTING_VRAM_PROFILE=$(grep -rl "GLVidHeapReuseRatio" /etc/nvidia/nvidia-application-profiles-rc.d/ 2>/dev/null || true)
  if [ -n "$EXISTING_VRAM_PROFILE" ]; then
    echo "    → Existing VRAM profile found: $EXISTING_VRAM_PROFILE"
    echo "    → Skipping 50-niri.json creation to prevent conflicting duplicate rules."
  else
    write_with_backup /etc/nvidia/nvidia-application-profiles-rc.d/50-niri.json << 'EOF'
{
  "rules": [
    {
      "pattern": { "feature": "procname", "matches": "niri" },
      "profile": "Limit Free Buffer Pool On Wayland Compositors"
    }
  ],
  "profiles": [
    {
      "name": "Limit Free Buffer Pool On Wayland Compositors",
      "settings": [
        { "key": "GLVidHeapReuseRatio", "value": 0 }
      ]
    }
  ]
}
EOF
  fi
fi

echo "=== 5. Disabling NVIDIA Background Polling Services ==="
if [ "$DRY_RUN" = true ]; then
  echo "    [DRY-RUN] Would configure systemd services (mask nvidia-powerd, disable persistenced, enable suspend/resume)"
else
  systemctl stop nvidia-powerd 2>/dev/null || true
  systemctl disable nvidia-powerd 2>/dev/null || true
  systemctl mask nvidia-powerd 2>/dev/null || true

  systemctl stop nvidia-persistenced 2>/dev/null || true
  systemctl disable nvidia-persistenced 2>/dev/null || true

  systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service 2>/dev/null || true
fi

if [ "$UPDATE_BOOTLOADER" = true ]; then
  echo "=== 🛠️ Bootloader Auto-Configuration (--update-bootloader) ==="
  CMDLINE_ADD="nvidia.NVreg_DynamicPowerManagement=0x02 rcutree.enable_rcu_lazy=1"

  if [ -f /etc/default/limine ] || command -v limine-update >/dev/null 2>&1 || command -v limine-mkinitcpio >/dev/null 2>&1; then
    echo "    → Detected Bootloader: Limine"
    if [ -f /etc/default/limine ]; then
      if ! grep -q "nvidia.NVreg_DynamicPowerManagement=0x02" /etc/default/limine; then
        write_with_backup /etc/default/limine << EOF
ESP_PATH="/boot"
KERNEL_CMDLINE[default]+="quiet nowatchdog splash rw rootflags=subvol=/@ root=UUID=6f476914-4bcd-42ff-9e28-c9881573507f nvidia.NVreg_DynamicPowerManagement=0x02 rcutree.enable_rcu_lazy=1"
BOOT_ORDER="*, *lts, *fallback, Snapshots"
EOF
      fi
    fi
    if [ "$DRY_RUN" = false ]; then
      if command -v limine-mkinitcpio >/dev/null 2>&1; then
        limine-mkinitcpio
      elif command -v limine-update >/dev/null 2>&1; then
        limine-update
      fi
    fi
  elif [ -d /etc/cmdline.d ]; then
    echo "    → Detected Bootloader: systemd-boot / cmdline.d"
    mkdir -p /etc/cmdline.d
    write_with_backup /etc/cmdline.d/power.conf <<< "$CMDLINE_ADD"
  elif [ -f /etc/default/grub ]; then
    echo "    → Detected Bootloader: GRUB"
    if ! grep -q "nvidia.NVreg_DynamicPowerManagement=0x02" /etc/default/grub; then
      echo "    → Please add '$CMDLINE_ADD' to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub."
    fi
  fi
fi

if [ "$APPLY_NIRI" = true ]; then
  echo "=== 6. Niri Compositor Configuration (~/.config/niri/config.kdl) ==="
  USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
  NIRI_CONF="$USER_HOME/.config/niri/config.kdl"

  ENV_FORCING_FOUND=""
  for envfile in "$USER_HOME/.zshrc" "$USER_HOME/.zshenv" "$USER_HOME/.config/environment.d/"*.conf /etc/environment; do
    if [ -f "$envfile" ] && grep -q "WLR_DRM_DEVICES" "$envfile" 2>/dev/null; then
      ENV_FORCING_FOUND="$envfile"
      break
    fi
  done

  if [ -n "$ENV_FORCING_FOUND" ]; then
    echo "    → WLR_DRM_DEVICES already configured in $ENV_FORCING_FOUND"
    echo "    → Skipping render-drm-device injection in config.kdl to prevent duplicate GPU forcing mechanisms."
  elif [ -f "$NIRI_CONF" ]; then
    if ! grep -q "debug {" "$NIRI_CONF"; then
      echo "    → No 'debug {' block found in $NIRI_CONF: skipping automatic injection."
      echo "    → Manually add a 'debug { render-drm-device \"...\"; }' block if desired."
    else
      IGPU_PCI=""
      for dev in /sys/class/drm/renderD*/device; do
        drv=$(readlink -f "$dev/driver" 2>/dev/null || true)
        if echo "$drv" | grep -qE 'amdgpu|i915|xe'; then
          IGPU_PCI=$(basename "$(readlink -f "$dev")")
        fi
      done
      if [ -n "$IGPU_PCI" ]; then
        IGPU_RENDER_PATH="/dev/dri/by-path/pci-${IGPU_PCI}-render"
        if ! grep -q "render-drm-device" "$NIRI_CONF"; then
          if [ "$DRY_RUN" = false ]; then
            cp -a "$NIRI_CONF" "${NIRI_CONF}.bak.$(date +%Y%m%d-%H%M%S)"
            sed -i "/debug {/a \\    render-drm-device \"$IGPU_RENDER_PATH\"" "$NIRI_CONF"
          fi
          echo "    → Added render-drm-device \"$IGPU_RENDER_PATH\" (backup saved)"
        else
          echo "    → render-drm-device is already present in $NIRI_CONF, no changes made"
        fi
      fi
    fi
  fi
fi

echo "=============================================================================="
echo " ✅ Script executed successfully."
echo "=============================================================================="

echo -e "\n📌 RECOMMENDED MANUAL CONFIGURATIONS REMINDER:"
echo "1. Kernel Parameters in Bootloader:"
echo "   Verify/add the following kernel command-line parameters to your bootloader:"
echo "   - 'nvidia.NVreg_DynamicPowerManagement=0x02' (Enables D3cold 0W idle)"
echo "   - 'rcutree.enable_rcu_lazy=1' (Reduces AMD Ryzen CPU micro-interrupts during idle)"
echo "   - [WARNING]: DO NOT add 'amdgpu.backlight=0' to avoid backlight/NVIDIA wake conflicts!"
echo "   Files to edit based on your bootloader:"
echo "     - Limine: /etc/default/limine (then run: sudo limine-mkinitcpio)"
echo "     - systemd-boot: /etc/cmdline.d/power.conf"
echo "     - GRUB: /etc/default/grub (then run: sudo grub-mkconfig -o /boot/grub/grub.cfg)"

echo -e "\n2. Nouveau Open-Source Driver Blacklist:"
echo "   Ensure Nouveau is disabled in /etc/modprobe.d/supergfxd.conf or nouveau-pm.conf:"
echo "     blacklist nouveau"
echo "     alias nouveau off"

sleep 2
BAT_PATH=$(upower -e | grep BAT | head -n 1 || true)
if [ -n "$BAT_PATH" ]; then
  echo -e "\n=== MEASURED BATTERY POWER DRAW ==="
  upower -i "$BAT_PATH" | grep -iE 'energy-rate|percentage|state|time to empty'
fi