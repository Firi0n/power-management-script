#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DI POWER MANAGEMENT — LAPTOP HYBRID (AMD/INTEL + NVIDIA)
# Su CachyOS / Arch Linux / Fedora / Ubuntu / Debian / Manjaro / Pop!_OS
#
# Versione "safe": prima di sovrascrivere un file esistente ne fa un backup
# con timestamp, e per la parte niri controlla se esistono già config che
# si sovrappongono (profilo VRAM, forcing GPU) invece di duplicarle.
#
# Uso: sudo ./setup-power-management-safe.sh [--niri|-n]
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
  echo "Uso: sudo ./setup-power-management-safe.sh [--niri|-n]"
  exit 1
fi

# ------------------------------------------------------------------------------
# Helper: scrive un file solo dopo averne fatto il backup se esiste già
# Uso: write_with_backup <path> <<< "$contenuto"
# ------------------------------------------------------------------------------
write_with_backup() {
  local target="$1"
  local tmpfile
  tmpfile=$(mktemp)
  cat > "$tmpfile"

  if [ -f "$target" ]; then
    if cmp -s "$target" "$tmpfile"; then
      echo "    → $target identico, nessuna modifica necessaria"
      rm -f "$tmpfile"
      return 0
    fi
    local backup="${target}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$target" "$backup"
    echo "    → $target esisteva già ed è diverso: backup salvato in $backup"
  fi

  mv "$tmpfile" "$target"
  echo "    → $target scritto"
}

echo "=== 1. Configurazione Modprobe NVIDIA (/etc/modprobe.d/nvidia-power.conf) ==="
write_with_backup /etc/modprobe.d/nvidia-power.conf << 'EOF'
options nvidia NVreg_DynamicPowerManagement=0x02
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia-drm modeset=1 fbdev=1
EOF

echo "=== 2. Configurazione Regole Udev PCI & USB Universali ==="
write_with_backup /etc/udev/rules.d/80-nvidia-pm.rules << 'EOF'
# Enable runtime PM for all NVIDIA PCI devices on any udev event (boot, change, unplug)
SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", TEST=="power/control", ATTR{power/control}="auto"
EOF

write_with_backup /etc/udev/rules.d/99-pci-pm.rules << 'EOF'
# Enable Runtime Power Management for all PCI devices (NVMe, Wi-Fi, Ethernet, iGPU)
ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
EOF

write_with_backup /etc/udev/rules.d/99-usb-pm.rules << 'EOF'
# Enable Autosuspend for USB devices
ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="auto"
EOF

echo "=== 3. Configurazione Risparmio Energetico Audio ==="
write_with_backup /etc/modprobe.d/audio-powersave.conf << 'EOF'
options snd_hda_intel power_save=1 power_save_controller=Y
EOF

if [ "$APPLY_NIRI" = true ]; then
  echo "=== 4. Profilo Applicativo NVIDIA VRAM per Niri ==="
  mkdir -p /etc/nvidia/nvidia-application-profiles-rc.d/

  EXISTING_VRAM_PROFILE=$(grep -rl "GLVidHeapReuseRatio" /etc/nvidia/nvidia-application-profiles-rc.d/ 2>/dev/null || true)
  if [ -n "$EXISTING_VRAM_PROFILE" ]; then
    echo "    → Trovato profilo VRAM già esistente: $EXISTING_VRAM_PROFILE"
    echo "    → Salto la creazione di 50-niri.json per evitare regole duplicate/in conflitto."
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

echo "=== 5. Disattivazione Servizi Background Polling NVIDIA ==="
systemctl stop nvidia-powerd 2>/dev/null || true
systemctl disable nvidia-powerd 2>/dev/null || true
systemctl mask nvidia-powerd 2>/dev/null || true

systemctl stop nvidia-persistenced 2>/dev/null || true
systemctl disable nvidia-persistenced 2>/dev/null || true

systemctl disable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service 2>/dev/null || true

echo "=== 6. Ricarica Regole Udev ed Applicazione a Caldo ==="
udevadm control --reload-rules

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

  # Se esiste già un forcing GPU via variabile d'ambiente (es. WLR_DRM_DEVICES
  # in un file di sessione/profile), avvisa invece di aggiungere un secondo
  # meccanismo che punta allo stesso risultato per vie diverse.
  ENV_FORCING_FOUND=""
  for envfile in "$USER_HOME/.zshrc" "$USER_HOME/.zshenv" "$USER_HOME/.config/environment.d/"*.conf /etc/environment; do
    if [ -f "$envfile" ] && grep -q "WLR_DRM_DEVICES" "$envfile" 2>/dev/null; then
      ENV_FORCING_FOUND="$envfile"
      break
    fi
  done

  if [ -n "$ENV_FORCING_FOUND" ]; then
    echo "    → Trovato WLR_DRM_DEVICES già impostato in $ENV_FORCING_FOUND"
    echo "    → Salto l'inserimento di render-drm-device in config.kdl per evitare due meccanismi di forcing GPU in parallelo."
  elif [ -f "$NIRI_CONF" ]; then
    if ! grep -q "debug {" "$NIRI_CONF"; then
      echo "    → Nessun blocco 'debug {' trovato in $NIRI_CONF: non inserisco nulla automaticamente."
      echo "    → Aggiungi manualmente un blocco 'debug { render-drm-device \"...\"; }' se vuoi usare questo metodo."
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
          echo "    → Aggiunto render-drm-device \"$IGPU_RENDER_PATH\" (backup del config salvato)"
        else
          echo "    → render-drm-device già presente in $NIRI_CONF, nessuna modifica"
        fi
      fi
    fi
  fi
fi

echo "=============================================================================="
echo " ✅ Script completato."
echo "=============================================================================="

sleep 3
BAT_PATH=$(upower -e | grep BAT | head -n 1)
if [ -n "$BAT_PATH" ]; then
  echo -e "\n=== CONSUMO BATTERIA RILEVATO ==="
  upower -i "$BAT_PATH" | grep -iE 'energy-rate|percentage|state|time to empty'
fi