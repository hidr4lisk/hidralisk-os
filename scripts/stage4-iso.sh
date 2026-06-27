#!/usr/bin/env bash
# stage4-iso.sh — Genera ISO híbrida booteable via mkosi
#
# P1.6 del roadmap: toma el rootfs construido por las etapas 1-3
# y produce una ISO híbrida UEFI+Legacy que puede bootear en
# hardware real o VM.
#
# Input:
#   $OUTDIR/magic-$VERSION.tar  — rootfs con capa SpellOS (stage2 output)
#   $OSTREE_REPO/               — repositorio ostree (stage3 output)
#
# Output:
#   $OUTDIR/SpellOS-$VERSION.iso  — ISO híbrida booteable
#   $OUTDIR/SpellOS-$VERSION.iso.sha256
#
# Variables de entorno (o defaults):
#   OUTDIR    — directorio de salida (default: ./output)
#   VERSION   — versión del build (default: snapshot-$(date +%Y%m%d))
#   GPG_KEY   — ID de clave GPG para firmar (default: build@spellos.dev)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTDIR="${OUTDIR:-$REPO_DIR/output}"
VERSION="${VERSION:-snapshot-$(date +%Y%m%d)}"
GPG_KEY="${GPG_KEY:-build@spellos.dev}"

ROOTFS_TAR="$OUTDIR/magic-$VERSION.tar"

if [ ! -f "$ROOTFS_TAR" ]; then
    echo "[FATAL] No se encuentra rootfs: $ROOTFS_TAR"
    echo "        Ejecutar stage1-base.sh + stage2-magic.sh + stage3-ostree.sh primero."
    exit 1
fi

# --- Validar prerequisitos ---
HAS_MKOSI=false
HAS_XORRISO=false
HAS_SHA256SUM=false

for cmd in sha256sum; do
    if command -v "$cmd" &>/dev/null; then
        HAS_SHA256SUM=true
    else
        echo "[FATAL] Falta binario requerido: $cmd"
        exit 1
    fi
done

if command -v mkosi &>/dev/null; then
    HAS_MKOSI=true
    echo "[STAGE-4] mkosi detectado — usando mkosi para ISO"
elif command -v xorriso &>/dev/null; then
    HAS_XORRISO=true
    echo "[STAGE-4] mkosi no disponible — usando xorriso como fallback"
else
    echo "[FATAL] Ni mkosi ni xorriso están disponibles."
    echo "        Instalar al menos uno: apt install mkosi  o  apt install xorriso"
    exit 1
fi

echo "[STAGE-4] Generando ISO híbrida SpellOS $VERSION..."

# --- Preparar configuración mkosi ---
MKOSI_DIR="$REPO_DIR/mkosi"
MKOSI_CONF="$MKOSI_DIR/mkosi.conf"
MKOSI_EXTRA="$MKOSI_DIR/extra"

if [ ! -d "$MKOSI_DIR" ]; then
    echo "[WARN] Directorio mkosi/ no existe. Creando configuración por defecto..."
    mkdir -p "$MKOSI_DIR/mkosi.conf.d"
    mkdir -p "$MKOSI_EXTRA"
fi

# Generar mkosi.conf si no existe
if [ ! -f "$MKOSI_CONF" ]; then
    echo "[STAGE-4] Generando mkosi.conf..."
    cat > "$MKOSI_CONF" <<'MKOSI_CONF'
[Distribution]
Distribution=debian
Release=bookworm
Mirror=http://deb.debian.org/debian
Repositories=main contrib non-free-firmware

[Output]
OutputDirectory=../output
ImageId=SpellOS
ImageVersion=1.0
Format=iso
Bootable=yes
HybridMBR=yes
QemuHeadless=yes

[Partition]
PartitionSize=4G
Bootable=yes
BootLoader=grub

[Content]
RootDirectory=../output/magic-rootfs
Bootable=yes
Stamp=touched
# Package directories are overlaid onto the root filesystem
Packages=
    systemd
    linux-image-amd64
    systemd-sysv
    console-setup
    keyboard-setup
    locales
    initramfs-tools
    btrfs-progs
    grub-efi-amd64
    shim-signed
    dmsetup
    apparmor
    ostree
    gpg
    curl
    jq

SkeletonTrees=
    ../output/magic-rootfs

# Clean up after build
RemovePackages=
    tasksel
    dictionaries-common
    iamerican
    ispell
MKOSI_CONF
fi

# Generar configs de override si no existen
CONF_D="$MKOSI_DIR/mkosi.conf.d"
if [ ! -f "$CONF_D/10-debian.conf" ]; then
    cat > "$CONF_D/10-debian.conf" <<'DEBCONF'
[Distribution]
Mirror=http://deb.debian.org/debian
Repositories=main contrib non-free-firmware
DEBCONF
fi

if [ ! -f "$CONF_D/20-magic.conf" ]; then
    cat > "$CONF_D/20-magic.conf" <<'MAGICCONF'
[Content]
# SpellOS-specific packages
Packages=
    btrfs-progs
    ostree
    dmsetup
    apparmor
    gpg
    jq
    curl
MAGICCONF
fi

if [ ! -f "$CONF_D/30-iso.conf" ]; then
    cat > "$CONF_D/30-iso.conf" <<'ISOCONF'
[Output]
Format=iso
Bootable=yes
HybridMBR=yes

[Partition]
PartitionSize=4G
Bootable=yes
BootLoader=grub
ISOCONF
fi

# --- Extraer rootfs temporal para mkosi ---
EXTRACT_DIR=$(mktemp -d /tmp/spellos-mkosi-XXXXXX)
trap 'rm -rf "$EXTRACT_DIR"' EXIT

echo "[STAGE-4] Extrayendo rootfs para mkosi..."
tar -xpf "$ROOTFS_TAR" -C "$EXTRACT_DIR"

# mkosi espera RootDirectory como directorio, no tarball
# Apuntamos la config al directorio extraído
MAGIC_ROOTFS="$OUTDIR/magic-rootfs"
rm -rf "$MAGIC_ROOTFS"
mv "$EXTRACT_DIR" "$MAGIC_ROOTFS"

# --- Generar GRUB config para ISO ---
echo "[STAGE-4] Configurando GRUB para ISO híbrida..."
GRUB_DIR="$MAGIC_ROOTFS/boot/grub"
mkdir -p "$GRUB_DIR"

cat > "$GRUB_DIR/grub.cfg" <<'GRUB'
# SpellOS GRUB Configuration
set default=0
set timeout=5
set gfxmode=auto

menuentry "SpellOS" {
    linux /boot/vmlinuz root=LABEL=SPELLOS ro quiet splash
    initrd /boot/initrd.img
}

menuentry "SpellOS (recovery)" {
    linux /boot/vmlinuz root=LABEL=SPELLOS ro single
    initrd /boot/initrd.img
}

menuentry "SpellOS (verbose)" {
    linux /boot/vmlinuz root=LABEL=SPELLOS ro verbose debug
    initrd /boot/initrd.img
}
GRUB

# --- Generar systemd-boot config (UEFI) ---
BOOT_DIR="$MAGIC_ROOTFS/boot/efi/loader/entries"
mkdir -p "$BOOT_DIR"

cat > "$BOOT_DIR/spellos.conf" <<'BOOTCONF'
title   SpellOS
linux   /vmlinuz
options root=LABEL=SPELLOS ro quiet splash
initrd  /initrd.img
BOOTCONF

cat > "$BOOT_DIR/spellos-recovery.conf" <<'BOOTRECOV'
title   SpellOS (recovery)
linux   /vmlinuz
options root=LABEL=SPELLOS ro single
initrd  /initrd.img
BOOTRECOV

# --- Ejecutar generación de ISO ---
ISO_OUTPUT="$OUTDIR/SpellOS-$VERSION.iso"

if $HAS_MKOSI; then
    echo "[STAGE-4] Generando ISO con mkosi..."
    mkosi \
        --directory="$MAGIC_ROOTFS" \
        --output="$ISO_OUTPUT" \
        --format=iso \
        --bootable=yes \
        --force \
        2>&1 || {
            if $HAS_XORRISO; then
                echo "[WARN] mkosi falló. Usando xorriso como fallback..."
                HAS_MKOSI=false
            else
                echo "[FATAL] mkosi falló y xorriso no está disponible."
                rm -rf "$MAGIC_ROOTFS"
                exit 1
            fi
        }
fi

if ! $HAS_MKOSI && $HAS_XORRISO; then
    echo "[STAGE-4] Generando ISO con xorriso..."
    ISO_LABEL="SPELLOS_$(echo "$VERSION" | tr '-' '_')"
    xorriso -as mkisofs \
        -r -J \
        -joliet-long \
        -V "$ISO_LABEL" \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -c boot.cat \
        -b boot/grub/eltorito.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --grub2-boot-info \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -o "$ISO_OUTPUT" \
        "$MAGIC_ROOTFS" 2>&1 || {
            echo "[FATAL] xorriso falló al generar la ISO."
            rm -rf "$MAGIC_ROOTFS"
            exit 1
        }
fi

# --- Limpiar rootfs temporal ---
rm -rf "$MAGIC_ROOTFS"

# --- Checksum ---
sha256sum "$ISO_OUTPUT" > "$ISO_OUTPUT.sha256"
ISO_SIZE=$(du -h "$ISO_OUTPUT" | cut -f1)

echo ""
echo "[STAGE-4] ============================================="
echo "[STAGE-4] ISO generada exitosamente"
echo "[STAGE-4] Archivo: $ISO_OUTPUT"
echo "[STAGE-4] Tamaño:  $ISO_SIZE"
echo "[STAGE-4] SHA-256: $(cut -d' ' -f1 < "$ISO_OUTPUT.sha256")"
echo "[STAGE-4] ============================================="
echo ""
echo "[STAGE-4] Para verificar: ./scripts/stage5-verify.sh"
echo "[STAGE-4] Para probar:   qemu-system-x86_64 -cdrom $ISO_OUTPUT -m 4G -enable-kvm"

exit 0
