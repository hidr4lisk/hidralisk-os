#!/usr/bin/env bash
# build.sh — Orquestador del pipeline SpellOS
#
# Ejecuta stage1→stage5 secuencialmente con:
#   (a) validación de prerequisitos
#   (b) gate de schema validation post-stage2
#   (c) verificación de que cada stage produjo sus artefactos
#   (d) resumen final de PASS/FAIL
#
# Uso: ./scripts/build.sh
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

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0
STAGE_RESULTS=()

pass() { echo -e "  ${GREEN}✓ PASS${NC}: $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗ FAIL${NC}: $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}⚠ WARN${NC}: $1"; ((WARN++)); }

stage_pass() { STAGE_RESULTS+=("${GREEN}✓ $1${NC}"); }
stage_fail() { STAGE_RESULTS+=("${RED}✗ $1${NC}"); }

# --- Cleanup en interrupción ---
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo -e "${RED}[BUILD] Pipeline interrumpido (exit code: $exit_code)${NC}"
        echo -e "${RED}[BUILD] Artefactos parciales en: $OUTDIR${NC}"
    fi
}
trap cleanup EXIT

# --- Banner ---
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          SpellOS Build Pipeline — build.sh              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Directorio de trabajo: $REPO_DIR"
echo "Directorio de salida:  $OUTDIR"
echo "Versión:               $VERSION"
echo "Clave GPG:             $GPG_KEY"
echo "Fecha:                 $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ═══════════════════════════════════════════════════════════
# FASE 0: Validación de prerequisitos del host
# ═══════════════════════════════════════════════════════════
echo "═══ Fase 0: Prerequisitos del host ═══"

REQUIRED_CMDS=(mmdebstrap gpg sha256sum ostree bsdtar python3 mkosi xorriso)
OPTIONAL_CMDS=(cosign)

MISSING_REQUIRED=()
MISSING_OPTIONAL=()

for cmd in "${REQUIRED_CMDS[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        pass "$cmd disponible"
    else
        fail "$cmd NO encontrado (requerido)"
        MISSING_REQUIRED+=("$cmd")
    fi
done

for cmd in "${OPTIONAL_CMDS[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        pass "$cmd disponible"
    else
        warn "$cmd no encontrado (opcional, algunos stages pueden fallar)"
        MISSING_OPTIONAL+=("$cmd")
    fi
done

if [ ${#MISSING_REQUIRED[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}[BUILD] FATAL: Faltan binarios requeridos: ${MISSING_REQUIRED[*]}${NC}"
    echo "[BUILD] Instalar dependencias y reintentar."
    exit 1
fi

# Verificar python3 con módulos necesarios
if command -v python3 &>/dev/null; then
    PY_OK=0
    python3 -c "import yaml, jsonschema" 2>/dev/null && PY_OK=1 || true
    if [ "$PY_OK" = "1" ]; then
        pass "python3 con yaml+jsonschema"
    else
        warn "python3 sin yaml/jsonschema — schema validation deshabilitada"
    fi
fi

# Verificar que el mmdebstrap config existe
if [ ! -f "$REPO_DIR/mmdebstrap/bookworm.conf" ]; then
    fail "Config de mmdebstrap no encontrada: mmdebstrap/bookworm.conf"
    exit 1
fi
pass "mmdebstrap/bookworm.conf existe"

echo ""

# ═══════════════════════════════════════════════════════════
# STAGE 1: Rootfs Debian minimizado
# ═══════════════════════════════════════════════════════════
echo "═══ Stage 1: Generando rootfs Debian minimizado ═══"

mkdir -p "$OUTDIR"

# Limpiar artefactos previos de este stage
rm -f "$OUTDIR/base-$VERSION"* 2>/dev/null || true

if bash "$SCRIPT_DIR/stage1-base.sh"; then
    # Verificar artefactos
    BASE_TAR="$OUTDIR/base-$VERSION.tar"
    BASE_SIG="$OUTDIR/base-$VERSION.tar.sig"
    BASE_HASH="$OUTDIR/base-$VERSION.sha256"

    ARTIFACTS_OK=true
    for f in "$BASE_TAR" "$BASE_HASH"; do
        if [ ! -f "$f" ]; then
            fail "Stage 1 no produjo: $f"
            ARTIFACTS_OK=false
        fi
    done

    if $ARTIFACTS_OK; then
        # Verificar checksum
        EXPECTED=$(cut -d' ' -f1 < "$BASE_HASH")
        ACTUAL=$(sha256sum "$BASE_TAR" | cut -d' ' -f1)
        if [ "$EXPECTED" = "$ACTUAL" ]; then
            pass "Stage 1 completado — checksum OK"
            stage_pass "Stage 1: rootfs"
        else
            fail "Stage 1: checksum mismatch"
            stage_fail "Stage 1: rootfs"
            exit 1
        fi
    else
        stage_fail "Stage 1: rootfs"
        exit 1
    fi
else
    fail "Stage 1 falló"
    stage_fail "Stage 1: rootfs"
    exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════
# STAGE 2: Capa SpellOS
# ═══════════════════════════════════════════════════════════
echo "═══ Stage 2: Inyectando capa SpellOS ═══"

rm -f "$OUTDIR/magic-$VERSION"* 2>/dev/null || true

if bash "$SCRIPT_DIR/stage2-magic.sh"; then
    MAGIC_TAR="$OUTDIR/magic-$VERSION.tar"
    MAGIC_SIG="$OUTDIR/magic-$VERSION.tar.sig"
    MAGIC_HASH="$OUTDIR/magic-$VERSION.sha256"

    ARTIFACTS_OK=true
    for f in "$MAGIC_TAR" "$MAGIC_HASH"; do
        if [ ! -f "$f" ]; then
            fail "Stage 2 no produjo: $f"
            ARTIFACTS_OK=false
        fi
    done

    if $ARTIFACTS_OK; then
        EXPECTED=$(cut -d' ' -f1 < "$MAGIC_HASH")
        ACTUAL=$(sha256sum "$MAGIC_TAR" | cut -d' ' -f1)
        if [ "$EXPECTED" = "$ACTUAL" ]; then
            pass "Stage 2 completado — checksum OK"
            stage_pass "Stage 2: SpellOS layer"
        else
            fail "Stage 2: checksum mismatch"
            stage_fail "Stage 2: SpellOS layer"
            exit 1
        fi
    else
        stage_fail "Stage 2: SpellOS layer"
        exit 1
    fi
else
    fail "Stage 2 falló"
    stage_fail "Stage 2: SpellOS layer"
    exit 1
fi

# --- GATE: Schema validation post-stage2 ---
echo ""
echo "═══ Gate: Schema validation ═══"

MAGIC_YAML="$OUTDIR/magic-yaml-check"
SCHEMA_FILE="$REPO_DIR/magic-schema.json"

# Extraer magic.yaml del tarball para validarlo
if [ -f "$MAGIC_TAR" ]; then
    TMP_YAML=$(mktemp /tmp/spellos-schema-XXXXXX.yaml)
    tar -xOf "$MAGIC_TAR" etc/magic/magic.yaml > "$TMP_YAML" 2>/dev/null || true

    if [ -s "$TMP_YAML" ]; then
        if [ -f "$SCHEMA_FILE" ] && command -v python3 &>/dev/null; then
            SCHEMA_OK=0
            python3 -c "
import sys, json, yaml, jsonschema
try:
    with open('$TMP_YAML') as f:
        data = yaml.safe_load(f)
    with open('$SCHEMA_FILE') as f:
        schema = json.load(f)
    jsonschema.validate(data, schema)
    print('OK')
except Exception as e:
    print('FAIL: ' + str(e))
    sys.exit(1)
" 2>/dev/null && SCHEMA_OK=1 || true

            rm -f "$TMP_YAML"

            if [ "$SCHEMA_OK" = "1" ]; then
                pass "magic.yaml cumple magic-schema.json"
            else
                fail "magic.yaml NO cumple magic-schema.json — pipeline bloqueado"
                stage_fail "Gate: schema validation"
                exit 1
            fi
        else
            rm -f "$TMP_YAML"
            warn "Schema validation saltada (python3 o schema no disponible)"
        fi
    else
        rm -f "$TMP_YAML"
        warn "No se pudo extraer magic.yaml del tarball"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════
# STAGE 3: ostree commit
# ═══════════════════════════════════════════════════════════
echo "═══ Stage 3: Creando commit ostree ═══"

rm -f "$OUTDIR/layer-$VERSION"* "$OUTDIR/registry.asc"* 2>/dev/null || true

if bash "$SCRIPT_DIR/stage3-ostree.sh"; then
    LAYER_TAR="$OUTDIR/layer-$VERSION.tar"
    REGISTRY="$OUTDIR/registry.asc"

    ARTIFACTS_OK=true
    for f in "$LAYER_TAR" "$REGISTRY"; do
        if [ ! -f "$f" ]; then
            fail "Stage 3 no produjo: $f"
            ARTIFACTS_OK=false
        fi
    done

    if $ARTIFACTS_OK; then
        pass "Stage 3 completado — ostree commit + registry.asc"
        stage_pass "Stage 3: ostree"
    else
        stage_fail "Stage 3: ostree"
        exit 1
    fi
else
    fail "Stage 3 falló"
    stage_fail "Stage 3: ostree"
    exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════
# STAGE 4: ISO híbrida
# ═══════════════════════════════════════════════════════════
echo "═══ Stage 4: Generando ISO híbrida ═══"

rm -f "$OUTDIR/SpellOS-$VERSION.iso"* 2>/dev/null || true

if bash "$SCRIPT_DIR/stage4-iso.sh"; then
    ISO_FILE="$OUTDIR/SpellOS-$VERSION.iso"
    ISO_HASH="$OUTDIR/SpellOS-$VERSION.iso.sha256"

    ARTIFACTS_OK=true
    for f in "$ISO_FILE" "$ISO_HASH"; do
        if [ ! -f "$f" ]; then
            fail "Stage 4 no produjo: $f"
            ARTIFACTS_OK=false
        fi
    done

    if $ARTIFACTS_OK; then
        EXPECTED=$(cut -d' ' -f1 < "$ISO_HASH")
        ACTUAL=$(sha256sum "$ISO_FILE" | cut -d' ' -f1)
        if [ "$EXPECTED" = "$ACTUAL" ]; then
            ISO_SIZE=$(du -h "$ISO_FILE" | cut -f1)
            pass "Stage 4 completado — ISO $ISO_SIZE"
            stage_pass "Stage 4: ISO"
        else
            fail "Stage 4: ISO checksum mismatch"
            stage_fail "Stage 4: ISO"
            exit 1
        fi
    else
        stage_fail "Stage 4: ISO"
        exit 1
    fi
else
    fail "Stage 4 falló"
    stage_fail "Stage 4: ISO"
    exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════
# STAGE 5: Verificación + Attestation
# ═══════════════════════════════════════════════════════════
echo "═══ Stage 5: Verificación final ═══"

if bash "$SCRIPT_DIR/stage5-verify.sh"; then
    ATTESTATION="$OUTDIR/attestation.intoto.jsonl"
    if [ -f "$ATTESTATION" ]; then
        pass "Stage 5 completado — attestation generada"
        stage_pass "Stage 5: verify"
    else
        warn "Stage 5 completado pero sin attestation"
        stage_pass "Stage 5: verify (warn)"
    fi
else
    fail "Stage 5 falló — verificación de ISO incorrecta"
    stage_fail "Stage 5: verify"
    exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════
# RESUMEN FINAL
# ═══════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              RESUMEN DEL BUILD PIPELINE                 ║"
echo "╠══════════════════════════════════════════════════════════╣"

for result in "${STAGE_RESULTS[@]}"; do
    echo -e "║  $result"
done

echo "╠══════════════════════════════════════════════════════════╣"
printf "║  ${GREEN}PASS: %-3d${NC}  ${YELLOW}WARN: %-3d${NC}  ${RED}FAIL: %-3d${NC}%*s║\n" "$PASS" "$WARN" "$FAIL" "" ""
echo "╠══════════════════════════════════════════════════════════╣"

if [ "$FAIL" -gt 0 ]; then
    echo -e "║  ${RED}RESULTADO: FAIL — Build falló${NC}                       ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    exit 1
else
    echo -e "║  ${GREEN}RESULTADO: PASS — Build exitoso${NC}                     ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Artefactos en $OUTDIR:"
    ls -lh "$OUTDIR/base-$VERSION"* "$OUTDIR/magic-$VERSION"* "$OUTDIR/layer-$VERSION"* "$OUTDIR/SpellOS-$VERSION.iso" "$OUTDIR/registry.asc" "$OUTDIR/attestation.intoto.jsonl" 2>/dev/null || true
    echo ""
    echo "Siguiente paso: firmar la ISO con cosign/HSM"
    exit 0
fi
