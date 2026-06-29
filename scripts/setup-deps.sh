#!/usr/bin/env bash
# setup-deps.sh — Instalación autónoma de dependencias para SpellOS
#
# Si make está disponible, delega en `make deps`.
# Si no, ejecuta los comandos directamente.
#
# Uso: sudo bash scripts/setup-deps.sh
#
# Variables de entorno:
#   GPG_KEY    — ID de clave GPG (default: build@spellos.dev)
#   SKIP_GPG   — si=1, salta generación de clave GPG

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GPG_KEY="${GPG_KEY:-build@spellos.dev}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓ PASS${NC}: $1"; }
fail() { echo -e "  ${RED}✗ FAIL${NC}: $1" >&2; }
warn() { echo -e "  ${YELLOW}⚠ WARN${NC}: $1"; }

echo "╔══════════════════════════════════════════════════════════╗"
echo "║       SpellOS Dependency Setup — setup-deps.sh          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# --- Verificar root ---
if [ "$(id -u)" -ne 0 ]; then
    fail "Este script requiere sudo. Reintentar: sudo bash $0"
    exit 1
fi

# --- Delegar a make si está disponible ---
if command -v make &>/dev/null && [ -f "$REPO_DIR/Makefile" ]; then
    echo "═══ make detectado — delegando a make deps ═══"
    exec make -C "$REPO_DIR" deps
fi

echo "═══ make no disponible — instalación directa ═══"

# --- Instalar paquetes del sistema ---
echo "--- Instalando paquetes del sistema ---"
apt-get update -qq
apt-get install -y -qq \
    mmdebstrap \
    ostree \
    xorriso \
    gnupg \
    python3-yaml \
    python3-jsonschema \
    qemu-system-x86 \
    libarchive-tools \
    shellcheck \
    yamllint
pass "Paquetes del sistema instalados"

# --- Generar clave GPG de desarrollo ---
if [ "${SKIP_GPG:-0}" != "1" ]; then
    echo "--- Setup clave de desarrollo ---"
    if command -v gpg &>/dev/null; then
        gpg --batch --quick-gen-key "$GPG_KEY" default default never 2>/dev/null || true
        gpg --export --armor "$GPG_KEY" > "$REPO_DIR/keys/verify.pub" 2>/dev/null || true
        if [ -f "$REPO_DIR/keys/verify.pub" ]; then
            pass "Clave GPG $GPG_KEY generada"
        else
            warn "No se pudo exportar clave GPG — verificar gpg"
        fi
    else
        warn "gpg no disponible — no se puede generar clave"
    fi
fi

# --- Verificar que keys/verify.pub es una clave GPG válida ---
echo "--- Verificando keys/verify.pub ---"
if [ -f "$REPO_DIR/keys/verify.pub" ]; then
    if command -v gpg &>/dev/null; then
        if gpg --import --dry-run "$REPO_DIR/keys/verify.pub" 2>/dev/null; then
            pass "keys/verify.pub es una clave GPG válida"
        else
            fail "keys/verify.pub NO es una clave GPG válida"
            fail "Ejecutar: gpg --batch --quick-gen-key $GPG_KEY default default never"
            exit 1
        fi
    else
        warn "gpg no disponible — no se puede verificar keys/verify.pub"
    fi
else
    fail "keys/verify.pub no encontrado"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Dependencias listas ===${NC}"
echo "Siguiente paso: bash scripts/build.sh"
