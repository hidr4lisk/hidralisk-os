SHELL := /bin/bash
.ONESHELL:

VERSION ?= snapshot-$(shell date +%Y%m%d)
OUTDIR ?= $(CURDIR)/output
ISO ?= $(shell ls -t $(OUTDIR)/SpellOS-*.iso 2>/dev/null | head -1)

.PHONY: build deps lint quick-test smoke-test qa test-vm clean

build:
	@echo "=== SpellOS Build Pipeline ==="
	@mkdir -p "$(OUTDIR)"
	VERSION="$(VERSION)" OUTDIR="$(OUTDIR)" bash scripts/build.sh

deps:
	@echo "=== Instalando dependencias del host ==="
	@if [ "$$(id -u)" -ne 0 ]; then
		echo "make deps requiere sudo. Reintentar: sudo make deps" >&2
		exit 1
	fi
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
	@echo "=== Setup clave de desarrollo ==="
	@if command -v gpg &>/dev/null; then
		gpg --batch --quick-gen-key build@spellos.dev default default never 2>/dev/null || true
		gpg --export --armor build@spellos.dev > keys/verify.pub 2>/dev/null || true
		echo "Clave GPG build@spellos.dev generada"
	fi
	@echo "=== Dependencias listas ==="

quick-test:
	@echo "=== SpellOS Quick Test ==="
	@errors=0
	@echo "--- 1. Estructura de directorios ---"
	@for d in mmdebstrap scripts keys mkosi/extra; do
		if [ -d "$$d" ]; then
			echo "  OK: $$d/"
		else
			echo "  FAIL: $$d/ no existe" >&2
			((errors++))
		fi
	done
	@echo ""
	@echo "--- 2. Scripts existentes y ejecutables ---"
	@for s in scripts/stage1-base.sh scripts/stage2-magic.sh scripts/stage3-ostree.sh scripts/stage4-iso.sh scripts/stage5-verify.sh scripts/build.sh; do
		if [ -x "$$s" ]; then
			echo "  OK: $$s"
		elif [ -f "$$s" ]; then
			echo "  WARN: $$s no ejecutable — arreglando"
			chmod +x "$$s"
		else
			echo "  FAIL: $$s no encontrado" >&2
			((errors++))
		fi
	done
	@echo ""
	@echo "--- 3. Syntax check (bash -n) ---"
	@for s in scripts/*.sh; do
		if bash -n "$$s" 2>/dev/null; then
			echo "  OK: $$s (syntax OK)"
		else
			echo "  FAIL: $$s (error de sintaxis)" >&2
			((errors++))
		fi
	done
	@echo ""
	@echo "--- 4. JSON Schema válido ---"
	@if command -v python3 &>/dev/null; then
		if python3 -c "import json; json.load(open('magic-schema.json'))" 2>/dev/null; then
			echo "  OK: magic-schema.json (JSON válido)"
		else
			echo "  FAIL: magic-schema.json (JSON inválido)" >&2
			((errors++))
		fi
	else
		echo "  WARN: python3 no disponible — saltando validación JSON"
	fi
	@echo ""
	@echo "--- 5. Dependencias del host ---"
	@for cmd in mmdebstrap gpg sha256sum python3; do
		if command -v "$$cmd" &>/dev/null; then
			echo "  OK: $$cmd disponible"
		else
			echo "  FAIL: $$cmd no encontrado (requerido para build completo)" >&2
			((errors++))
		fi
	done
	@for cmd in mkosi xorriso bsdtar qemu-system-x86_64; do
		if command -v "$$cmd" &>/dev/null; then
			echo "  OK: $$cmd disponible"
		else
			echo "  WARN: $$cmd no encontrado"
		fi
	done
	@echo ""
	@echo "--- 6. keys/verify.pub ---"
	@if [ -f keys/verify.pub ]; then
		echo "  OK: keys/verify.pub existe"
	else
		echo "  WARN: keys/verify.pub ausente — make deps para generarlo"
	fi
	@echo ""
	@echo "--- 7. mmdebstrap config ---"
	@if [ -f mmdebstrap/bookworm.conf ]; then
		echo "  OK: mmdebstrap/bookworm.conf existe"
	else
		echo "  FAIL: mmdebstrap/bookworm.conf no encontrado" >&2
		((errors++))
	fi
	@echo ""
	@if [ "$$errors" -gt 0 ]; then
		echo "=== RESULTADO: FAIL — $$errors errores detectados ===" >&2
		exit 1
	else
		echo "=== RESULTADO: PASS — pipeline listo para build ==="
	fi

lint:
	@echo "=== SpellOS Lint ==="
	@errors=0
	@echo "--- shellcheck ---"
	@if command -v shellcheck &>/dev/null; then
		if shellcheck scripts/*.sh; then
			echo "  OK: shellcheck passed"
		else
			echo "  FAIL: shellcheck encontró errores" >&2
			((errors++))
		fi
	else
		echo "  WARN: shellcheck no instalado — saltando" >&2
	fi
	@echo ""
	@echo "--- yamllint ---"
	@if command -v yamllint &>/dev/null; then
		if yamllint mmdebstrap/bookworm.conf .github/workflows/*.yml; then
			echo "  OK: yamllint passed"
		else
			echo "  FAIL: yamllint encontró errores" >&2
			((errors++))
		fi
	else
		echo "  WARN: yamllint no instalado — saltando" >&2
	fi
	@echo ""
	@echo "--- JSON syntax check ---"
	@if command -v python3 &>/dev/null; then
		if python3 -c "import json; json.load(open('magic-schema.json'))" 2>/dev/null; then
			echo "  OK: magic-schema.json (syntax OK)"
		else
			echo "  FAIL: magic-schema.json (JSON inválido)" >&2
			((errors++))
		fi
	else
		echo "  WARN: python3 no disponible — saltando validación JSON" >&2
	fi
	@echo ""
	@if [ "$$errors" -gt 0 ]; then
		echo "=== LINT RESULT: FAIL — $$errors errores ===" >&2
		exit 1
	else
		echo "=== LINT RESULT: PASS ==="
	fi

smoke-test:
	@echo "=== SpellOS Smoke Test ==="
	VERSION="$(VERSION)" OUTDIR="$(OUTDIR)" bash scripts/smoke-test.sh

qa: lint quick-test smoke-test
	@echo "=== QA completo ==="

test-vm: $(ISO)
	@if [ -z "$(ISO)" ]; then
		echo "No se encontró ISO en $(OUTDIR). Ejecutar: make build" >&2
		exit 1
	fi
	bash scripts/test-vm.sh "$(ISO)"

clean:
	@echo "=== Limpiando artefactos ==="
	rm -rf "$(OUTDIR)"
	@echo "OK: $(OUTDIR)/ eliminado"
	@echo "Para limpieza completa: git clean -fdX"

$(ISO):
	@echo "ISO no encontrada. Ejecuta 'make build' primero." >&2
	@exit 1
