#!/usr/bin/env bash
# ==============================================================================
# SCRIPT UNIVERSALE DI POWER MANAGEMENT TOTALE — LAPTOP HYBRID (AMD/INTEL + NVIDIA)
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

if [ "$EUID" -ne 0 ]; then
  echo "❌ Errore: Esegui questo script con privilegi root (sudo)!"
  echo "Uso: sudo ./setup-power-management.sh [--niri|-n]"
  exit 1
fi

echo "=== 1. Configurazione Modprobe NVIDIA (/etc/modprobe.d/nvidia-power.conf) ==="
cat << 'EOF' > /etc/modprobe.d/nvidia-power.conf
options nvidia NVreg_DynamicPowerManagement=0x02
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia-drm modeset=1 fbdev=1
EOF

echo "=== 2. Configurazione Regole Udev PCI & USB Universali ==="
cat << 'EOF' > /etc/udev/rules.d/80-nvidia-pm.rules
# Enable runtime PM for all NVIDIA PCI devices on any udev event (boot, change, unplug)
SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", TEST=="power/control", ATTR{power/control}="auto"
EOF

cat << 'EOF' > /etc/udev/rules.d/99-pci-pm.rules
# Enable Runtime Power Management for all PCI devices (NVMe, Wi-Fi, Ethernet, iGPU)
ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
EOF

cat << 'EOF' > /etc/udev/rules.d/99-usb-pm.rules
# Enable Autosuspend for USB devices
ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="auto"
EOF

echo "=== 3. Configurazione Risparmio Energetico Audio ==="
cat << 'EOF' > /etc/modprobe.d/audio-powersave.conf
options snd_hda_intel power_save=1 power_save_controller=Y
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

echo "=== 5. Disattivazione Servizi Background Polling NVIDIA ==="
systemctl stop nvidia-powerd 2>/dev/null || true
systemctl disable nvidia-powerd 2>/dev/null || true
systemctl mask nvidia-powerd 2>/dev/null || true

systemctl stop nvidia-persistenced 2>/dev/null || true
systemctl disable nvidia-persistenced 2>/dev/null || true

systemctl disable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service 2>/dev/null || true

echo "=== 6. Ricarica Regole Udev ed Applicazione a Caldo ==="
udevadm control --reload-rules
udevadm trigger

for dev in /sys/bus/pci/devices/*; do
  if [ -f "$dev/power/control" ]; then
    echo "auto" > "$dev/power/control" 2>/dev/null || true
  fi
done

for dev in /sys/bus/usb/devices/*; do
  if [ -f "$dev/power/control" ]; then
    echo "auto" > "$dev/power/control" 2>/dev/null || true
  fi
done

echo "=== 7. Impostazione Profilo Power Saver ==="
powerprofilesctl set power-saver 2>/dev/null || true

if [ "$APPLY_NIRI" = true ]; then
  echo "=== 8. Configurazione Niri Compositor (~/.config/niri/config.kdl) ==="
  USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
  NIRI_CONF="$USER_HOME/.config/niri/config.kdl"
  
  # Rilevamento dinamico dell'indirizzo PCI dell'iGPU (AMD o Intel)
  IGPU_PCI=""
  for dev in /sys/class/drm/renderD*/device; do
    drv=$(readlink -f "$dev/driver" 2>/dev/null || true)
    if echo "$drv" | grep -qE 'amdgpu|i915|xe'; then
      IGPU_PCI=$(basename "$(readlink -f "$dev")")
    fi
  done

  if [ -f "$NIRI_CONF" ] && [ -n "$IGPU_PCI" ]; then
    IGPU_RENDER_PATH="/dev/dri/by-path/pci-${IGPU_PCI}-render"
    echo "--> iGPU Rilevata dinamicamente: $IGPU_RENDER_PATH"
    if ! grep -q "render-drm-device" "$NIRI_CONF"; then
      sed -i "/debug {/a \\    render-drm-device \"$IGPU_RENDER_PATH\"" "$NIRI_CONF"
    fi
  fi
fi

echo "=============================================================================="
echo " ✅ Master Script completato con successo!"
echo "=============================================================================="

sleep 3
BAT_PATH=$(upower -e | grep BAT | head -n 1)
if [ -n "$BAT_PATH" ]; then
  echo -e "\n=== CONSUMO BATTERIA RILEVATO ==="
  upower -i "$BAT_PATH" | grep -iE 'energy-rate|percentage|state|time to empty'
fi
