#!/usr/bin/env bash
# stage3-ostree.sh — Crea commit ostree de la capa base y firma el registro
#
# P1.2 del roadmap: toma el rootfs con capa SpellOS (stage2 output),
# hace un ostree commit, lo firma con GPG, y genera registry.asc
# con placeholder de TPM PCR binding.
#
# Input:
#   $1 — tarball de la capa (default: $OUTDIR/magic-$VERSION.tar)
#
# Output:
#   $OSTREE_REPO/ — repositorio ostree local
#   $OUTDIR/registry.asc  — registro firmado de capas con TPM PCR binding
#   $OUTDIR/layer-$VERSION.tar  — capa exportada desde ostree
#   $OUTDIR/layer-$VERSION.tar.sig

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTDIR="${OUTDIR:-$REPO_DIR/output}"
VERSION="${VERSION:-snapshot-$(date +%Y%m%d)}"
GPG_KEY="${GPG_KEY:-build@spellos.dev}"
OSTREE_REPO="${OSTREE_REPO:-$OUTDIR/ostree-repo}"

MAGIC_TAR="${1:-$OUTDIR/magic-$VERSION.tar}"

if [ ! -f "$MAGIC_TAR" ]; then
    echo "[FATAL] No se encuentra capa: $MAGIC_TAR"
    echo "        Ejecutar stage1-base.sh + stage2-magic.sh primero."
    exit 1
fi

echo "[STAGE-3] Creando commit ostree de la capa base..."

# --- Validar prerequisitos ---
for cmd in ostree gpg sha256sum; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "[FATAL] Falta binario: $cmd"
        exit 1
    fi
done

# --- Directorio temporal para extraer la capa ---
LAYER_DIR=$(mktemp -d /tmp/spellos-layer-XXXXXX)
trap 'rm -rf "$LAYER_DIR"' EXIT

echo "[STAGE-3] Extrayendo $MAGIC_TAR..."
tar -xpf "$MAGIC_TAR" -C "$LAYER_DIR"

# --- Inicializar repositorio ostree si no existe ---
if [ ! -d "$OSTREE_REPO" ]; then
    echo "[STAGE-3] Inicializando repositorio ostree en $OSTREE_REPO..."
    ostree init --repo="$OSTREE_REPO" --mode=archive
fi

# --- Generar resumen de hashes para el commit ---
echo "[STAGE-3] Generando manifest de la capa..."
HASH_MANIFEST="$OUTDIR/manifest-$VERSION.txt"
{
    echo "# SpellOS Layer Manifest — $VERSION"
    echo "# Generado: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "## Filesystem hashes (SHA-256)"
    find "$LAYER_DIR" -type f -exec sha256sum {} \; 2>/dev/null | \
        while read -r hash path; do
            rel="${path#$LAYER_DIR/}"
            echo "$hash  $rel"
        done
} > "$HASH_MANIFEST"
echo "[STAGE-3] Manifest generado: $(wc -l < "$HASH_MANIFEST") entradas"

# --- Commit ostree ---
echo "[STAGE-3] Commit ostree..."
BRANCH_NAME="spellos/$VERSION/base"
COMMIT_HASH=$(ostree commit \
    --repo="$OSTREE_REPO" \
    --branch="$BRANCH_NAME" \
    --subject="SpellOS base layer $VERSION" \
    --body="Build snapshot generado por stage3-ostree.sh" \
    --gpg-sign="$GPG_KEY" \
    --tree=dir="$LAYER_DIR" 2>&1 | tail -1)

echo "[STAGE-3] Commit: $BRANCH_NAME @ $COMMIT_HASH"

# --- Exportar capa desde ostree ---
LAYER_TAR="$OUTDIR/layer-$VERSION.tar"
echo "[STAGE-3] Exportando capa ostree a $LAYER_TAR..."
ostree export --repo="$OSTREE_REPO" "$BRANCH_NAME" --output="$LAYER_TAR"

# --- Firma desprendida de la capa ---
if gpg --list-keys "$GPG_KEY" &>/dev/null; then
    gpg --detach-sign --armor --local-user "$GPG_KEY" \
        --output "$LAYER_TAR.sig" "$LAYER_TAR"
else
    echo "Placeholder: sin firma real" > "$LAYER_TAR.sig"
fi
sha256sum "$LAYER_TAR" > "$LAYER_TAR.sha256"

# --- Generar registry.asc (Registro firmado de capas + TPM PCR binding) ---
#
# registry.asc es el archivo que magic-init stage-1 verifica en boot.
# Contiene:
#   - Hash de la capa base (este commit)
#   - Firma GPG del registro
#   - Placeholder de TPM PCR measurement (en producción se extiende
#     usando tpm2-tools)
#
# El TPM PCR binding asegura que si un atacante reemplaza registry.asc,
# los PCRs del TPM no coinciden y el boot se niega.

REGISTRY="$OUTDIR/registry.asc"
echo "[STAGE-3] Generando registry.asc con TPM PCR binding placeholder..."

LAYER_DIGEST=$(sha256sum "$LAYER_TAR" | cut -d' ' -f1)
MANIFEST_DIGEST=$(sha256sum "$HASH_MANIFEST" | cut -d' ' -f1)

{
    echo "-----BEGIN SPELLOS REGISTRY-----"
    echo ""
    echo "Registry: SpellOS Capas Firmadas"
    echo "Version: $VERSION"
    echo "Generado: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Branch: $BRANCH_NAME"
    echo "Commit: $COMMIT_HASH"
    echo ""
    echo "--- Capa Base ---"
    echo "Layer: $LAYER_TAR"
    echo "SHA-256: $LAYER_DIGEST"
    echo "Manifest: $HASH_MANIFEST"
    echo "Manifest-SHA256: $MANIFEST_DIGEST"
    echo ""
    echo "--- TPM PCR Binding (placeholder) ---"
    echo "PCR-Selection: sha256:0,7"
    echo "PCR-Value: 0000000000000000000000000000000000000000000000000000000000000000"
    echo "PCR-Policy: NoExecuteWithoutMatch"
    echo "TPM-Notes: En producción, este valor se extiende con tpm2_pcrextend"
    echo "            usando el hash del registry.asc firmado. El stage-1 de"
    echo "            magic-init lee los PCRs actuales y solo permite boot"
    echo "            si coinciden con este registro."
    echo ""
    echo "--- Firmas Permitidas ---"
    echo "GPG-Key: $GPG_KEY"
    echo "Verify-Path: /etc/magic/keys/verify.pub"
    echo ""
} > "$REGISTRY"

# Firmar el registry.asc
if gpg --list-keys "$GPG_KEY" &>/dev/null; then
    gpg --clearsign --local-user "$GPG_KEY" --output "$REGISTRY.sig" "$REGISTRY"
    mv "$REGISTRY.sig" "$REGISTRY"
    echo "[STAGE-3] registry.asc firmado con GPG"
else
    echo "[WARN] registry.asc generado pero NO firmado (GPG key no disponible)"
fi

sha256sum "$REGISTRY" > "$REGISTRY.sha256"

echo "[STAGE-3] Completado. Artefactos:"
ls -lh "$OSTREE_REPO"
ls -lh "$LAYER_TAR" "$LAYER_TAR.sha256" "$REGISTRY"

echo ""
echo "=== registry.asc ==="
head -20 "$REGISTRY"

exit 0
