#!/usr/bin/env bash
# smoke-test.sh — Verificación post-build del pipeline Hidralisk
#
# Verifica que los artefactos del build son consistentes y válidos.
# Ejecutar después de build.sh o stage5-verify.sh.
#
# Checks:
#   (a) ISO hidra bytes + tamaño ≥ 500MB
#   (b) attestation.intoto.jsonl → JSON válido + SHA-256 matchea ISO
#   (c) registry.asc → firma clearsign GPG válida
#   (d) Cadena checksums: base → hidra → layer → iso consistente
#
# Exit: 0 si todo pasa, 1 si algo falla.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTDIR="${OUTDIR:-$REPO_DIR/output}"
VERSION="${VERSION:-snapshot-$(date +%Y%m%d)}"
GPG_KEY="${GPG_KEY:-build@hidralisk.dev}"

ISO_FILE="$OUTDIR/Hidralisk-$VERSION.iso"
ATTESTATION="$OUTDIR/attestation.intoto.jsonl"
REGISTRY="$OUTDIR/registry.asc"
BASE_TAR="$OUTDIR/base-$VERSION.tar"
HIDRA_TAR="$OUTDIR/hidra-$VERSION.tar"
LAYER_TAR="$OUTDIR/layer-$VERSION.tar"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { echo -e "  ${GREEN}PASS${NC}: $1"; ((PASS++)); }
fail() { echo -e "  ${RED}FAIL${NC}: $1" >&2; ((FAIL++)); }

echo "╔══════════════════════════════════════════════════════════╗"
echo "║           Hidralisk Smoke Test — smoke-test.sh            ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# --- Prerequisitos ---
for cmd in sha256sum od python3; do
    if ! command -v "$cmd" &>/dev/null; then
        fail "Falta binario requerido: $cmd"
        echo ""
        echo "RESULTADO: FAIL"
        exit 1
    fi
done

HAS_GPG=false
if command -v gpg &>/dev/null; then
    HAS_GPG=true
fi

# --- (a) ISO hidra bytes + tamaño ≥ 500MB ---
echo "═══ Check (a): Integridad de la ISO ═══"
if [ ! -f "$ISO_FILE" ]; then
    fail "ISO no encontrada: $ISO_FILE"
else
    # Hidra bytes: ISO 9660 o ELF hybrid (UEFI)
    HIDRA=$(od -A n -t x1 -N 5 "$ISO_FILE" 2>/dev/null | tr -d ' \n' || echo "")
    if echo "$HIDRA" | grep -qi "4549444601"; then
        pass "ISO hidra bytes: ELF hybrid (UEFI)"
    elif echo "$HIDRA" | grep -qi "4344303031"; then
        pass "ISO hidra bytes: ISO 9660"
    elif [ -n "$HIDRA" ]; then
        fail "ISO hidra bytes inesperados: $HIDRA"
    else
        fail "No se pudieron leer hidra bytes de la ISO"
    fi

    # Tamaño ≥ 500MB
    ISO_SIZE_KB=$(du -k "$ISO_FILE" | cut -f1)
    ISO_SIZE_MB=$(( ISO_SIZE_KB / 1024 ))
    if [ "$ISO_SIZE_KB" -ge 512000 ]; then
        pass "ISO tamaño: ${ISO_SIZE_MB}MB (≥ 500MB)"
    else
        fail "ISO demasiado pequeña: ${ISO_SIZE_MB}MB (requerido ≥ 500MB)"
    fi

    # Checksum ISO
    ISO_HASH_FILE="$ISO_FILE.sha256"
    if [ ! -f "$ISO_HASH_FILE" ]; then
        fail "Checksum ISO no encontrado: $ISO_HASH_FILE"
    else
        EXPECTED=$(cut -d' ' -f1 < "$ISO_HASH_FILE")
        ACTUAL=$(sha256sum "$ISO_FILE" | cut -d' ' -f1)
        if [ "$EXPECTED" = "$ACTUAL" ]; then
            pass "ISO checksum SHA-256 coincide"
        else
            fail "ISO checksum NO coincide (esperado: ${EXPECTED:0:16}...)"
        fi
    fi
fi
echo ""

# --- (b) Attestation: JSON válido + SHA-256 matchea ISO ---
echo "═══ Check (b): Attestation SLSA ═══"
if [ ! -f "$ATTESTATION" ]; then
    fail "Attestation no encontrada: $ATTESTATION"
else
    # Validar JSON
    ATTESTATION_JSON=$(cat "$ATTESTATION")
    if echo "$ATTESTATION_JSON" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "Attestation es JSON válido"
    else
        fail "Attestation NO es JSON válido"
    fi

    # Extraer SHA-256 del subject y comparar con ISO
    if [ -f "$ISO_FILE" ]; then
        ISO_DIGEST=$(sha256sum "$ISO_FILE" | cut -d' ' -f1)
        ATTESTATION_DIGEST=$(echo "$ATTESTATION_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['subject'][0]['digest']['sha256'])
except Exception:
    print('')
" 2>/dev/null || echo "")

        if [ -z "$ATTESTATION_DIGEST" ]; then
            fail "No se pudo extraer digest de la attestation"
        elif [ "$ISO_DIGEST" = "$ATTESTATION_DIGEST" ]; then
            pass "Attestation SHA-256 coincide con ISO"
        else
            fail "Attestation SHA-256 NO coincide con ISO"
            fail "  Attestation: ${ATTESTATION_DIGEST:0:16}..."
            fail "  ISO:         ${ISO_DIGEST:0:16}..."
        fi
    fi

    # Verificar firma GPG de la attestation
    ATTESTATION_SIG="$ATTESTATION.sig"
    if [ -f "$ATTESTATION_SIG" ]; then
        if $HAS_GPG; then
            if gpg --verify "$ATTESTATION_SIG" "$ATTESTATION" 2>/dev/null; then
                pass "Attestation firma GPG válida"
            else
                fail "Attestation firma GPG inválida — provenance comprometida"
            fi
        else
            # Verificar que al menos tiene estructura binaria GPG
            if file "$ATTESTATION_SIG" 2>/dev/null | grep -qi "PGP"; then
                pass "Attestation firma presente (GPG no disponible para verificar)"
            else
                fail "Attestation firma no es GPG válido"
            fi
        fi
    else
        warn "Attestation no firmada (*.sig ausente) — builds sin HSM aceptable, pero sin trust anchor"
    fi
fi
echo ""

# --- (c) registry.asc: firma clearsign GPG válida ---
echo "═══ Check (c): Registry.asc firma GPG ═══"
if [ ! -f "$REGISTRY" ]; then
    fail "registry.asc no encontrado: $REGISTRY"
else
    if $HAS_GPG; then
        if gpg --verify "$REGISTRY" 2>/dev/null; then
            pass "registry.asc firma GPG válida"
        else
            fail "registry.asc firma GPG inválida o ausente"
        fi
    else
        # Verificar que al menos tiene la estructura clearsign
        if grep -q "BEGIN PGP SIGNED MESSAGE" "$REGISTRY" 2>/dev/null; then
            pass "registry.asc tiene estructura clearsign (GPG no disponible para verificar)"
        else
            fail "registry.asc NO tiene estructura clearsign"
        fi
    fi

    # Verificar checksum del registry
    REGISTRY_HASH_FILE="$REGISTRY.sha256"
    if [ ! -f "$REGISTRY_HASH_FILE" ]; then
        fail "Checksum registry no encontrado: $REGISTRY_HASH_FILE"
    else
        EXPECTED=$(cut -d' ' -f1 < "$REGISTRY_HASH_FILE")
        ACTUAL=$(sha256sum "$REGISTRY" | cut -d' ' -f1)
        if [ "$EXPECTED" = "$ACTUAL" ]; then
            pass "registry.asc checksum SHA-256 coincide"
        else
            fail "registry.asc checksum NO coincide"
        fi
    fi
fi
echo ""

# --- (d) Cadena de checksums consistente ---
echo "═══ Check (d): Cadena de checksums ═══"
CHECKSUM_OK=true

check_chain() {
    local label="$1"
    local tarball="$2"
    local hash_file="$3"

    if [ ! -f "$tarball" ]; then
        fail "Cadena: $label — tarball no encontrado ($tarball)"
        CHECKSUM_OK=false
        return
    fi

    if [ ! -f "$hash_file" ]; then
        fail "Cadena: $label — checksum no encontrado ($hash_file)"
        CHECKSUM_OK=false
        return
    fi

    EXPECTED=$(cut -d' ' -f1 < "$hash_file")
    ACTUAL=$(sha256sum "$tarball" | cut -d' ' -f1)
    if [ "$EXPECTED" = "$ACTUAL" ]; then
        pass "Cadena: $label — SHA-256 coincide"
    else
        fail "Cadena: $label — SHA-256 NO coincide"
        CHECKSUM_OK=false
    fi
}

check_chain "base" "$BASE_TAR" "$BASE_TAR.sha256"
check_chain "hidra" "$HIDRA_TAR" "$HIDRA_TAR.sha256"
check_chain "layer" "$LAYER_TAR" "$LAYER_TAR.sha256"
check_chain "iso" "$ISO_FILE" "$ISO_FILE.sha256"

# Verificar que los checksums de cada etapa apuntan al artefacto correcto
# (que no haya mezcla de artefactos entre etapas)
if [ -f "$BASE_TAR.sha256" ] && [ -f "$HIDRA_TAR.sha256" ]; then
    BASE_HASH=$(cut -d' ' -f1 < "$BASE_TAR.sha256")
    HIDRA_HASH=$(cut -d' ' -f1 < "$HIDRA_TAR.sha256")
    if [ "$BASE_HASH" != "$HIDRA_HASH" ]; then
        pass "Cadena: base ≠ hidra (etapas producen artefactos distintos — correcto)"
    else
        fail "Cadena: base = hidra (¿etapas idénticas? verificar pipeline)"
    fi
fi
echo ""

# --- Resumen ---
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                 RESUMEN SMOKE TEST                      ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  ${GREEN}PASS: %-3d${NC}  ${RED}FAIL: %-3d${NC}%*s║\n" "$PASS" "$FAIL" "" ""
echo "╚══════════════════════════════════════════════════════════╝"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo -e "${RED}RESULTADO: FAIL — $FAIL checks fallaron${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}RESULTADO: PASS — artefactos consistentes${NC}"
    exit 0
fi
