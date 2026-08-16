#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 100% UNIVERSIALE DI POWER MANAGEMENT TOTALE — LAPTOP HYBRID (AMD/INTEL + NVIDIA)
# Su CachyOS / Arch Linux / Fedora / Ubuntu / Debian / Manjaro / Pop!_OS
# Uso: sudo ./setup-power-management.sh [--niri|-n]
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

echo "=== 1. Configurazione Modprobe NVIDIA (/etc/modprobe.d/nvidia-power.conf) ==="
cat << 'EOF' > /etc/modprobe.d/nvidia-power.conf
options nvidia NVreg_DynamicPowerManagement=0x02
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia-drm modeset=1 fbdev=1
EOF

echo "=== 2. Configurazione Modules-Load NVIDIA (/etc/modules-load.d/nvidia.conf) ==="
mkdir -p /etc/modules-load.d/
cat << 'EOF' > /etc/modules-load.d/nvidia.conf
nvidia
nvidia_modeset
nvidia_uvm
nvidia_drm
EOF

echo "=== 3. Configurazione Regole Udev PCI NVIDIA (/etc/udev/rules.d/80-nvidia-pm.rules) ==="
cat << 'EOF' > /etc/udev/rules.d/80-nvidia-pm.rules
# Enable runtime PM for all NVIDIA PCI devices on any udev event (boot, change, unplug)
SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", TEST=="power/control", ATTR{power/control}="auto"
EOF

if [ "$APPLY_NIRI" = true ]; then
  echo "=== 4. Profilo Applicativo NVIDIA VRAM per Niri (/etc/nvidia/nvidia-application-profiles-rc.d/50-niri.json) ==="
  mkdir -p /etc/nvidia/nvidia-application-profiles-rc.d/
  cat << 'EOF' > /etc/nvidia/nvidia-application-profiles-rc.d/50-niri.json
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

echo "=== 5. Rilevamento ed Aggiornamento Automatico del Bootloader ==="
CMDLINE_PARAMS="amdgpu.backlight=0 rcutree.enable_rcu_lazy=1"

if [ -f /etc/default/limine ] || command -v limine-update >/dev/null 2>&1; then
  echo "--> Rilevato Bootloader: Limine"
  if [ -f /etc/default/limine ]; then
    if ! grep -q "amdgpu.backlight=0" /etc/default/limine; then
      sed -i 's/KERNEL_CMDLINE\[default\]+="/KERNEL_CMDLINE[default]+="amdgpu.backlight=0 rcutree.enable_rcu_lazy=1 /g' /etc/default/limine
    fi
  fi
  if command -v limine-update >/dev/null 2>&1; then
    limine-update
  fi
elif [ -f /etc/default/grub ] || command -v grub-mkconfig >/dev/null 2>&1; then
  echo "--> Rilevato Bootloader: GRUB"
  if ! grep -q "amdgpu.backlight=0" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="amdgpu.backlight=0 rcutree.enable_rcu_lazy=1 /g' /etc/default/grub
  fi
  if command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg
  elif command -v update-grub >/dev/null 2>&1; then
    update-grub
  fi
elif [ -d /etc/cmdline.d ] || command -v bootctl >/dev/null 2>&1; then
  echo "--> Rilevato Bootloader: systemd-boot / cmdline.d"
  mkdir -p /etc/cmdline.d
  echo "$CMDLINE_PARAMS" > /etc/cmdline.d/power.conf
fi

echo "=== 6. Disattivazione Servizi nvidia-powerd ed nvidia-persistenced ==="
systemctl stop nvidia-powerd 2>/dev/null || true
systemctl disable nvidia-powerd 2>/dev/null || true
systemctl mask nvidia-powerd 2>/dev/null || true

systemctl stop nvidia-persistenced 2>/dev/null || true
systemctl disable nvidia-persistenced 2>/dev/null || true

systemctl disable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service 2>/dev/null || true

echo "=== 7. Coesistenza Nativa con i Profili Hardware Lenovo (platform_profile / FN+Q) ==="
echo "--> Ricarica Regole Udev PCI..."
udevadm control --reload-rules
udevadm trigger

echo "=== 8. Impostazione Profilo Power Saver Compatibile Lenovo ==="
powerprofilesctl set power-saver 2>/dev/null || true

if [ "$APPLY_NIRI" = true ]; then
  echo "=== 9. Configurazione Niri Compositor (~/.config/niri/config.kdl) ==="
  USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
  NIRI_CONF="$USER_HOME/.config/niri/config.kdl"
  
  # Rilevamento dinamico dell'indirizzo PCI dell'iGPU (AMD o Intel) e dGPU (NVIDIA)
  IGPU_PCI=""
  DGPU_PCI=""
  for dev in /sys/class/drm/renderD*/device; do
    drv=$(readlink -f "$dev/driver" 2>/dev/null || true)
    if echo "$drv" | grep -qE 'amdgpu|i915|xe'; then
      IGPU_PCI=$(basename "$(readlink -f "$dev")")
    elif echo "$drv" | grep -qE 'nvidia'; then
      DGPU_PCI=$(basename "$(readlink -f "$dev")")
    fi
  done

  if [ -f "$NIRI_CONF" ]; then
    if [ -n "$IGPU_PCI" ]; then
      IGPU_RENDER_PATH="/dev/dri/by-path/pci-${IGPU_PCI}-render"
      echo "--> iGPU Rilevata dinamicamente: $IGPU_RENDER_PATH"
      if ! grep -q "render-drm-device" "$NIRI_CONF"; then
        sed -i "/debug {/a \\    render-drm-device \"$IGPU_RENDER_PATH\"" "$NIRI_CONF"
      fi
    fi

    if [ -n "$DGPU_PCI" ]; then
      DGPU_CARD_PATH="/dev/dri/by-path/pci-${DGPU_PCI}-card"
      echo "--> dGPU Output Card Rilevata dinamicamente per ignore-drm-device: $DGPU_CARD_PATH"
      if ! grep -q "ignore-drm-device" "$NIRI_CONF"; then
        sed -i "/debug {/a \\    ignore-drm-device \"$DGPU_CARD_PATH\"" "$NIRI_CONF"
      fi
    fi
  fi
fi

echo "=============================================================================="
echo " OK! Master Script 100% Universale eseguito con successo!"
echo "=============================================================================="
