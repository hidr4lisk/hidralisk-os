#!/usr/bin/env bash
# test-vm.sh — Lanza Hidralisk ISO en QEMU
#
# Uso: ./scripts/test-vm.sh [ruta-iso]
#   Si no se especifica ruta, busca output/Hidralisk-*.iso
#
# Variables de entorno:
#   QEMU_MEM   — RAM en MB (default: 4096)
#   QEMU_SMP   — CPUs (default: 4)
#   QEMU_VNC   — Display VNC (default: :5900)
#   QEMU_KVM   — forzar/evitar KVM (auto por defecto)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

QEMU_MEM="${QEMU_MEM:-4096}"
QEMU_SMP="${QEMU_SMP:-4}"
QEMU_VNC="${QEMU_VNC:-:5900}"
QEMU_KVM="${QEMU_KVM:-auto}"

# --- Buscar ISO ---
if [ $# -ge 1 ] && [ -n "$1" ]; then
    ISO="$1"
else
    ISO=$(ls -t "$REPO_DIR/output/Hidralisk-"*.iso 2>/dev/null | head -1)
fi

if [ -z "$ISO" ]; then
    echo "[FATAL] No se encontró ISO de Hidralisk." >&2
    echo "        Especificar ruta: $0 /ruta/a/Hidralisk.iso" >&2
    echo "        O generar con:    make build" >&2
    exit 1
fi

if [ ! -f "$ISO" ]; then
    echo "[FATAL] ISO no encontrada: $ISO" >&2
    exit 1
fi

# --- Validar qemu disponible ---
if ! command -v qemu-system-x86_64 &>/dev/null; then
    echo "[FATAL] qemu-system-x86_64 no encontrado." >&2
    echo "        Instalar: sudo apt install qemu-system-x86" >&2
    echo "        O:        sudo make deps" >&2
    exit 1
fi

ISO_SIZE=$(du -h "$ISO" | cut -f1)
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              Hidralisk — QEMU Test VM                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "ISO:      $ISO"
echo "Tamaño:   $ISO_SIZE"
echo "Memoria:  ${QEMU_MEM}MB"
echo "CPUs:     $QEMU_SMP"
echo "VNC:      $QEMU_VNC"
echo ""

# --- Detectar KVM ---
KVM_FLAG=""
case "$QEMU_KVM" in
    force)
        KVM_FLAG="-enable-kvm"
        ;;
    no|never|off)
        KVM_FLAG=""
        echo "[WARN] KVM deshabilitado por QEMU_KVM=$QEMU_KVM"
        echo "[WARN] Rendimiento significativamente menor"
        ;;
    *)
        if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            KVM_FLAG="-enable-kvm"
            echo "[INFO] KVM disponible — aceleración por hardware activada"
        else
            echo "[WARN] KVM no disponible (/dev/kvm no accesible)"
            echo "[WARN] Ejecutar sin KVM (rendimiento menor)"
            echo "[WARN] Para habilitar: sudo usermod -aG kvm \$USER && sudo chmod 666 /dev/kvm"
        fi
        ;;
esac

# --- Armar comando QEMU ---
QEMU_CMD=(
    qemu-system-x86_64
    -cdrom "$ISO"
    -m "$QEMU_MEM"
    -smp "$QEMU_SMP"
    -cpu host
    -vga virtio
    -display vnc="$QEMU_VNC"
    -usb
    -device usb-tablet
    -netdev user,id=net0
    -device virtio-net,netdev=net0
    -audiodev none,id=noaudio
    -serial mon:stdio
    -boot menu=on
)

if [ -n "$KVM_FLAG" ]; then
    QEMU_CMD+=("$KVM_FLAG")
fi

echo "Comando: ${QEMU_CMD[*]}"
echo ""
echo "Hidralisk corriendo en QEMU en $QEMU_VNC VNC"
echo ""
echo "Conectar: vncviewer localhost${QEMU_VNC#:}"
echo "O:        gvncviewer localhost:${QEMU_VNC#:}"
echo "O:        vinagre localhost:${QEMU_VNC#:}"
echo ""
echo "Salida serial disponible en esta terminal."
echo "Para salir: Ctrl+A, X  (desde la consola serial)"
echo ""

exec "${QEMU_CMD[@]}"
