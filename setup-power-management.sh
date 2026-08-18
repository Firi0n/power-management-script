#!/usr/bin/env bash
# ==============================================================================
# UNIVERSAL LAPTOP POWER MANAGEMENT SCRIPT — HYBRID GRAPHICS (AMD/INTEL + NVIDIA)
# Compatible with CachyOS / Arch Linux / Fedora / Ubuntu / Debian / Manjaro / Pop!_OS
#
# Safe Version: Creates timestamped backups before modifying existing files.
# For Niri, checks existing configs (VRAM profiles, GPU forcing) before applying.
#
# Usage: sudo ./setup-power-management.sh [--niri|-n]
# ==============================================================================
set -e

APPLY_NIRI=false
for arg in "$@"; do
  case $arg in
    -n|--niri)
      APPLY_NIRI=true
      shift
      ;;
  esac
done

if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Please run this script with root privileges (sudo)!"
  echo "Usage: sudo ./setup-power-management.sh [--niri|-n]"
  exit 1
fi

# ------------------------------------------------------------------------------
# Helper: Write file only after creating a timestamped backup if it already exists
# Usage: write_with_backup <path> <<< "$content"
# ------------------------------------------------------------------------------
write_with_backup() {
  local target="$1"
  local tmpfile
  tmpfile=$(mktemp)
  cat > "$tmpfile"

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
systemctl stop nvidia-powerd 2>/dev/null || true
systemctl disable nvidia-powerd 2>/dev/null || true
systemctl mask nvidia-powerd 2>/dev/null || true

systemctl stop nvidia-persistenced 2>/dev/null || true
systemctl disable nvidia-persistenced 2>/dev/null || true

systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service 2>/dev/null || true

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
          cp -a "$NIRI_CONF" "${NIRI_CONF}.bak.$(date +%Y%m%d-%H%M%S)"
          sed -i "/debug {/a \\    render-drm-device \"$IGPU_RENDER_PATH\"" "$NIRI_CONF"
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

sleep 3
BAT_PATH=$(upower -e | grep BAT | head -n 1)
if [ -n "$BAT_PATH" ]; then
  echo -e "\n=== MEASURED BATTERY POWER DRAW ==="
  upower -i "$BAT_PATH" | grep -iE 'energy-rate|percentage|state|time to empty'
fi