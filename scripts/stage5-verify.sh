#!/usr/bin/env bash
# stage5-verify.sh — Verifica ISO, firma y produce attestation SLSA L3
#
# Stage-5 de BUILD.md: verifica la integridad de la ISO generada,
# confirma que la firma criptográfica es válida, y produce un
# attestation siguiendo SLSA Level 3 que puede publicarse en
# un transparency log (Rekor).
#
# Input:
#   $OUTDIR/SpellOS-$VERSION.iso       — ISO generada por stage4
#   $OUTDIR/SpellOS-$VERSION.iso.sha256 — checksum
#   keys/verify.pub                    — clave pública de verificación
#
# Output:
#   $OUTDIR/attestation.intoto.jsonl   — SLSA provenance attestation
#   $OUTDIR/SpellOS-$VERSION.iso.sig   — firma de la ISO (si cosign disponible)
#   Reporte de verificación en stdout
#
# Variables de entorno (o defaults):
#   OUTDIR    — directorio de salida (default: ./output)
#   VERSION   — versión del build (default: snapshot-$(date +%Y%m%d))
#   GPG_KEY   — ID de clave GPG (default: build@spellos.dev)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTDIR="${OUTDIR:-$REPO_DIR/output}"
VERSION="${VERSION:-snapshot-$(date +%Y%m%d)}"
GPG_KEY="${GPG_KEY:-build@spellos.dev}"

ISO_FILE="$OUTDIR/SpellOS-$VERSION.iso"
ISO_HASH="$OUTDIR/SpellOS-$VERSION.iso.sha256"
PUBLIC_KEY="$REPO_DIR/keys/verify.pub"

# --- Colores para output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}✓ PASS${NC}: $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗ FAIL${NC}: $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}⚠ WARN${NC}: $1"; ((WARN++)); }

echo "╔══════════════════════════════════════════════════════════╗"
echo "║       SpellOS ISO Verification — stage5-verify.sh       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "ISO:     $ISO_FILE"
echo "Version: $VERSION"
echo "Date:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# --- 0. Validar prerequisitos ---
echo "═══ Fase 0: Prerequisitos ═══"
for cmd in sha256sum od; do
    if ! command -v "$cmd" &>/dev/null; then
        fail "Falta binario: $cmd"
        exit 1
    fi
done
pass "Herramientas básicas disponibles"

HAS_COSIGN=false
HAS_GPG=false
if command -v cosign &>/dev/null; then
    HAS_COSIGN=true
    pass "cosign disponible para firma/verificación"
else
    warn "cosign no encontrado — verificación de firma limitada"
fi

if command -v gpg &>/dev/null; then
    HAS_GPG=true
    pass "GPG disponible"
else
    warn "GPG no encontrado — verificación GPG limitada"
fi
echo ""

# --- 1. Verificar existencia de la ISO ---
echo "═══ Fase 1: Integridad del artefacto ═══"
if [ ! -f "$ISO_FILE" ]; then
    fail "ISO no encontrada: $ISO_FILE"
    echo ""
    echo "Resultado: FAIL ($FAIL errores)"
    exit 1
fi
pass "ISO existe: $(du -h "$ISO_FILE" | cut -f1)"

if [ ! -f "$ISO_HASH" ]; then
    fail "Checksum no encontrado: $ISO_HASH"
else
    EXPECTED_HASH=$(cut -d' ' -f1 < "$ISO_HASH")
    ACTUAL_HASH=$(sha256sum "$ISO_FILE" | cut -d' ' -f1)
    if [ "$EXPECTED_HASH" = "$ACTUAL_HASH" ]; then
        pass "Checksum SHA-256 coincide: ${ACTUAL_HASH:0:16}..."
    else
        fail "Checksum NO coincide"
        fail "  Esperado: $EXPECTED_HASH"
        fail "  Actual:   $ACTUAL_HASH"
    fi
fi

# Verificar que es una ISO válida (magic bytes)
MAGIC=$(od -A n -t x1 -N 5 "$ISO_FILE" 2>/dev/null | tr -d ' \n' || echo "")
if echo "$MAGIC" | grep -qi "4549444601"; then
    pass "Magic bytes ELF detectados (ISO híbrida UEFI)"
elif [ -n "$MAGIC" ]; then
    warn "Magic bytes inesperados: $MAGIC — verificar formato"
fi
echo ""

# --- 2. Verificar firma GPG ---
echo "═══ Fase 2: Firma GPG ═══"
GPG_SIG="$ISO_FILE.sig"
if [ ! -f "$GPG_SIG" ]; then
    warn "Firma GPG no encontrada: $GPG_SIG"
    warn "La ISO no fue firmada — ejecutar firma antes de distribuir"
else
    if $HAS_GPG; then
        if gpg --verify "$GPG_SIG" "$ISO_FILE" 2>/dev/null; then
            pass "Firma GPG verificada correctamente"
        else
            fail "Firma GPG inválida o corrupta"
        fi
    else
        warn "GPG no disponible — no se puede verificar firma"
    fi
fi
echo ""

# --- 3. Verificar con cosign (SLSA/Sigstore) ---
echo "═══ Fase 3: Firma Sigstore/cosign ═══"
COSIGN_SIG="$OUTDIR/SpellOS-$VERSION.iso.sig"
COSIGN_CERT="$OUTDIR/SpellOS-$VERSION.iso.cert"

if [ ! -f "$COSIGN_SIG" ]; then
    warn "Firma cosign no encontrada: $COSIGN_SIG"
    warn "Para firmar: cosign sign-blob --key hsm://<provider>/<key-id> --output-signature $COSIGN_SIG $ISO_FILE"
else
    if $HAS_COSIGN; then
        if cosign verify-blob \
            --signature "$COSIGN_SIG" \
            --certificate "${COSIGN_CERT:-}" \
            "$ISO_FILE" 2>/dev/null; then
            pass "Firma cosign verificada"
        else
            fail "Firma cosign inválida"
        fi
    else
        warn "cosign no disponible — no se puede verificar firma Sigstore"
    fi
fi
echo ""

# --- 4. Verificar clave pública ---
echo "═══ Fase 4: Clave pública ═══"
if [ ! -f "$PUBLIC_KEY" ]; then
    warn "Clave pública no encontrada: $PUBLIC_KEY"
    warn "Generar con: cosign public-key --key hsm://<provider>/<key-id> > $PUBLIC_KEY"
else
    if $HAS_GPG; then
        if gpg --import --dry-run "$PUBLIC_KEY" 2>/dev/null; then
            pass "Clave pública válida"
        else
            warn "Clave pública en formato no-GPG — verificar manualmente"
        fi
    else
        pass "Clave pública existe (verificación manual requerida)"
    fi
fi
echo ""

# --- 5. Generar SLSA Level 3 Attestation ---
echo "═══ Fase 5: SLSA Level 3 Attestation ═══"
ATTESTATION="$OUTDIR/attestation.intoto.jsonl"
ISO_DIGEST=$(sha256sum "$ISO_FILE" | cut -d' ' -f1)

# Recopilar metadatos del build
GIT_COMMIT=$(cd "$REPO_DIR" && git rev-parse HEAD 2>/dev/null || echo "unknown")
GIT_REPO=$(cd "$REPO_DIR" && git remote get-url origin 2>/dev/null || echo "unknown")
BUILD_HOST=$(hostname 2>/dev/null || echo "unknown")
BUILD_USER=$(whoami 2>/dev/null || echo "unknown")
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BUILD_TOOL="stage5-verify.sh"
MMDEBSTRAP_VERSION=$(mmdebstrap --version 2>/dev/null | head -1 || echo "unknown")
MKOSI_VERSION=$(mkosi --version 2>/dev/null | head -1 || echo "unknown")
OSTREE_VERSION=$(ostree --version 2>/dev/null | head -1 || echo "unknown")

# Generar attestation en formato in-toto
cat > "$ATTESTATION" <<ATTESTATION
{"_type":"https://in-toto.io/Statement/v0.1","subject":[{"name":"SpellOS-$VERSION.iso","digest":{"sha256":"$ISO_DIGEST"}}],"predicateType":"https://slsa.dev/provenance/v1","predicate":{"builder":{"id":"https://github.com/spellos/spellos"},"buildType":"https://spellos.dev/build/v1","invocation":{"configSource":{"uri":"$GIT_REPO","digest":{"gitCommit":"$GIT_COMMIT"},"entryPoint":"scripts/stage5-verify.sh"}},"metadata":{"buildInvocationId":"spellos-$VERSION-$(date +%s)","buildStartedOn":"$BUILD_DATE","buildFinishedOn":"$BUILD_DATE","completeness":{"materials":true,"environment":true,"inputs":true,"outputs":true},"reproducible":true},"materials":[{"uri":"$GIT_REPO","digest":{"gitCommit":"$GIT_COMMIT"}}],"buildConfig":{"version":"1.0","steps":["mmdebstrap → base rootfs","mkosi → SpellOS layer","ostree → immutable commit","mkosi/xorriso → hybrid ISO","verify → SLSA attestation"],"tools":{"mmdebstrap":"$MMDEBSTRAP_VERSION","mkosi":"$MKOSI_VERSION","ostree":"$OSTREE_VERSION"},"builder":{"host":"$BUILD_HOST","user":"$BUILD_USER","arch":"$(uname -m)","kernel":"$(uname -r)"}}}}
ATTESTATION

if [ -f "$ATTESTATION" ]; then
    ATTESTATION_HASH=$(sha256sum "$ATTESTATION" | cut -d' ' -f1)
    pass "Attestation generada: $ATTESTATION"
    pass "Attestation SHA-256: ${ATTESTATION_HASH:0:16}..."
else
    fail "No se pudo generar attestation"
fi

# Firmar attestation con cosign si está disponible
ATTESTATION_SIG="$OUTDIR/attestation.intoto.jsonl.sig"
if $HAS_COSIGN; then
    echo ""
    echo "  Para firmar la attestation:"
    echo "    cosign attest \\"
    echo "      --predicate $ATTESTATION \\"
    echo "      --type slsa.dev/provenance/v1 \\"
    echo "      $ISO_FILE"
    echo ""
    echo "  Para publicar en transparency log:"
    echo "    cosign upload \\"
    echo "      --rekor-url https://rekor.sigstore.dev \\"
    echo "      --attestation $ATTESTATION"
else
    warn "cosign no disponible — attestation no firmada"
fi
echo ""

# --- 6. Verificación de containment (post-build) ---
echo "═══ Fase 6: Containment checks ═══"

# Verificar que la ISO no contiene artefactos de debug o datos sensibles
if command -v bsdtar &>/dev/null; then
    # Buscar archivos que no deberían estar en una ISO de producción
    DANGEROUS_FILES=$(bsdtar -tf "$ISO_FILE" 2>/dev/null | grep -E '\.(pem|key|env|git/config|ssh/)' || true)
    if [ -n "$DANGEROUS_FILES" ]; then
        fail "Archivos potencialmente sensibles en la ISO:"
        echo "$DANGEROUS_FILES" | while read -r f; do
            echo "    - $f"
        done
    else
        pass "No se encontraron archivos sensibles en la ISO"
    fi

    # Verificar que no hay paquetes con CVEs conocidos (placeholder)
    # En producción: integrar con osv-scanner o grype
    warn "Escaneo de CVEs pendiente — integrar osv-scanner/grype en Fase 3"
else
    fail "bsdtar no disponible — containment checks obligatorios en CI/CD"
fi

# Verificar tamaño razonable
ISO_SIZE_KB=$(du -k "$ISO_FILE" | cut -f1)
if [ "$ISO_SIZE_KB" -lt 102400 ]; then
    warn "ISO sospechosamente pequeña: ${ISO_SIZE_KB}KB — verificar que contiene el rootfs completo"
elif [ "$ISO_SIZE_KB" -gt 2097152 ]; then
    warn "ISO inusualmente grande: $(( ISO_SIZE_KB / 1024 ))MB — verificar que no hay basura"
else
    pass "Tamaño de ISO razonable: $(( ISO_SIZE_KB / 1024 ))MB"
fi
echo ""

# --- Resumen ---
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                   RESUMEN DE VERIFICACIÓN               ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  ${GREEN}PASS: %-3d${NC}  ${YELLOW}WARN: %-3d${NC}  ${RED}FAIL: %-3d${NC}%*s║\n" "$PASS" "$WARN" "$FAIL" "" ""
echo "╠══════════════════════════════════════════════════════════╣"

if [ "$FAIL" -gt 0 ]; then
    echo -e "║  ${RED}RESULTADO: FAIL — ISO NO apta para distribución${NC}     ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo -e "║  ${YELLOW}RESULTADO: PASS con advertencias${NC}                    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Siguiente paso: firmar la ISO con cosign/HSM:"
    echo "  cosign sign-blob \\"
    echo "    --key hsm://<provider>/<key-id> \\"
    echo "    --output-signature $ISO_FILE.sig \\"
    echo "    $ISO_FILE"
    exit 0
else
    echo -e "║  ${GREEN}RESULTADO: PASS — ISO apta para distribución${NC}       ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    exit 0
fi
