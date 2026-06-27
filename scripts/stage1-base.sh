#!/usr/bin/env bash
# stage1-base.sh — Genera rootfs Debian minimizado vía mmdebstrap
#
# P1.1 del roadmap: produce el sistema base firmado que alimenta
# las etapas posteriores del build pipeline.
#
# Output:
#   $OUTDIR/base-$VERSION.tar      — rootfs tarball
#   $OUTDIR/base-$VERSION.tar.sig  — firma GPG desprendida
#   $OUTDIR/base-$VERSION.sha256   — checksum
#
# Variables de entorno (o defaults):
#   OUTDIR    — directorio de salida (default: ./output)
#   VERSION   — versión del build (default: snapshot-$(date +%Y%m%d))
#   GPG_KEY   — ID de clave GPG para firmar (default: build@spellos.dev)
#   MIRROR    — mirror Debian (default: http://deb.debian.org/debian)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTDIR="${OUTDIR:-$REPO_DIR/output}"
VERSION="${VERSION:-snapshot-$(date +%Y%m%d)}"
GPG_KEY="${GPG_KEY:-build@spellos.dev}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"

mkdir -p "$OUTDIR"

# --- Validación de prerequisitos ---
for cmd in mmdebstrap gpg sha256sum; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "[FATAL] Falta binario: $cmd"
        exit 1
    fi
done

# --- Verificar mmdebstrap config ---
CONFIG_FILE="$REPO_DIR/mmdebstrap/bookworm.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[FATAL] Config de mmdebstrap no encontrada: $CONFIG_FILE"
    exit 1
fi

ROOTFS_TAR="$OUTDIR/base-$VERSION.tar"
ROOTFS_SIG="$OUTDIR/base-$VERSION.tar.sig"
ROOTFS_HASH="$OUTDIR/base-$VERSION.sha256"

echo "[STAGE-1] Generando rootfs Debian Bookworm minimizado..."
echo "  Mirror:  $MIRROR"
echo "  Output:  $ROOTFS_TAR"
echo "  Version: $VERSION"

# --- Limpiar builds previos ---
rm -f "$ROOTFS_TAR" "$ROOTFS_SIG" "$ROOTFS_HASH"

# --- Ejecutar mmdebstrap ---
# --customize-hook: hooks inline del config no siempre funcionan en
#   todas las versiones; los ejecutamos como script post-chroot
mmdebstrap \
    --variant=custom \
    --components="main,contrib,non-free-firmware" \
    --include="$(grep -v '^#' "$CONFIG_FILE" | grep -E '^[a-z]' | tr '\n' ',' | sed 's/,$//')" \
    --customize-hook='apt-get purge -y --auto-remove apt-listchanges tasksel dictionaries-common iamerican ispell 2>/dev/null; apt-get clean; rm -rf /var/lib/apt/lists/* /var/cache/apt/*; passwd -l root; echo "en_US.UTF-8 UTF-8" > /etc/locale.gen; locale-gen en_US.UTF-8; echo "LANG=en_US.UTF-8" > /etc/default/locale' \
    --skip=check/empty \
    bookworm \
    "$ROOTFS_TAR" \
    --mirror="$MIRROR"

echo "[STAGE-1] rootfs generado: $(du -h "$ROOTFS_TAR" | cut -f1)"

# --- Checksum ---
sha256sum "$ROOTFS_TAR" > "$ROOTFS_HASH"
echo "[STAGE-1] Checksum: $(cut -d' ' -f1 < "$ROOTFS_HASH")"

# --- Firma GPG desprendida ---
echo "[STAGE-1] Firmando con GPG key: $GPG_KEY"
if gpg --list-keys "$GPG_KEY" &>/dev/null; then
    gpg --detach-sign \
        --armor \
        --local-user "$GPG_KEY" \
        --output "$ROOTFS_SIG" \
        "$ROOTFS_TAR"
    echo "[STAGE-1] Firma: $ROOTFS_SIG"
else
    echo "[WARN] Clave GPG '$GPG_KEY' no encontrada. Generando placeholder."
    echo "Placeholder: sin firma real — configurar GPG key en build real" > "$ROOTFS_SIG"
fi

echo "[STAGE-1] Completado. Artefactos en $OUTDIR:"
ls -lh "$OUTDIR/base-$VERSION"*

exit 0
