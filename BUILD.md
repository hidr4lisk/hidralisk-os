# Build Pipeline de MagicLinux

## Stack de herramientas

- **mmdebstrap**: genera sistema base Debian minimizado (fase 1)
- **mkosi**: construye imágenes de sistema completas (fase 2)
- **ostree**: commit del rootfs como artefacto inmutable
- **GPG + signify**: firma criptográfica de cada capa
- **GitHub Actions / GitLab CI**: orquestación del pipeline

## Pipeline

```
┌─────────────────────────────────────────────────────┐
│  Fase 1: Base image                                 │
│  mmdebstrap --variant=custom bookworm base.tar      │
│  └── resultado: rootfs Debian mínimo firmado         │
├─────────────────────────────────────────────────────┤
│  Fase 2: Magic layer                                │
│  mkosi --distribution=debian --format=disk          │
│  └── inyecta magic-init, grimoire, magic-apt        │
├─────────────────────────────────────────────────────┤
│  Fase 3: ostree commit                              │
│  magic-build commit --layer base --sign             │
│  └── artifact: capa ostree firmada (.tar + .sig)    │
├─────────────────────────────────────────────────────┤
│  Fase 4: Hybrid ISO                                 │
│  mkosi --format=iso --hybrid                        │
│  └── artifact: MagicLinux-<version>.iso              │
├─────────────────────────────────────────────────────┤
│  Fase 5: Verification                               │
│  magic-verify --iso MagicLinux-<version>.iso        │
│  magic-verify --signature ./*.sig                   │
│  └── resultado: PASS/FAIL + hash manifest            │
└─────────────────────────────────────────────────────┘
```

## Estructura del repositorio

```
magiclinux/
├── .github/workflows/build.yml
├── mmdebstrap/
│   └── bookworm.conf        → configuración de mmdebstrap
├── mkosi/
│   ├── mkosi.conf           → configuración general
│   ├── mkosi.conf.d/
│   │   ├── 10-debian.conf
│   │   ├── 20-magic.conf
│   │   └── 30-iso.conf
│   └── extra/
│       ├── magic-init
│       ├── grimoire
│       └── magic-apt
├── keys/
│   ├── verify.pub           → clave pública de verificación (privada NUNCA en disco)
│   └── # La clave privada de firma vive en HSM externo (YubiKey, Nitrokey, o cloud HSM).
│       # El pipeline de CI nunca tiene acceso directo a la clave — usa cosign con
│       # identidad OIDC (GitHub OIDC → Sigstore) o firma delegada al HSM vía PKCS#11.
└── scripts/
    ├── stage1-base.sh
    ├── stage2-magic.sh
    ├── stage3-ostree.sh
    ├── stage4-iso.sh
    └── stage5-verify.sh
```

## CI/CD (GitHub Actions)

El pipeline se ejecuta en cada tag semver o push a `stable/`:

```yaml
name: Build MagicLinux ISO
on:
  push:
    tags: ["v*"]
    branches: [stable/*]

jobs:
  build:
    runs-on: [self-hosted, linux, x64]
    # ⚠️  Runners self-hosted requeridos para SLSA Level 3+
    # Los runners de GitHub Actions públicos son superficie de ataque.
    # El runner self-hosted debe estar:
    #   - Aislado (hardware dedicado o VM efímera)
    #   - Auditado (todas las operaciones logueadas)
    #   - Con Secure Boot + TPM + disco encriptado
    #   - Sin acceso a internet saliente excepto mirrors Debian firmados
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt install mmdebstrap mkosi ostree
      - run: ./scripts/stage1-base.sh
      - run: ./scripts/stage2-magic.sh
      - run: ./scripts/stage3-ostree.sh
      - run: ./scripts/stage4-iso.sh
      - run: ./scripts/stage5-verify.sh
      - uses: actions/upload-artifact@v4
        with:
          name: MagicLinux-${{ github.ref_name }}.iso
          path: output/*.iso
```

## Firmas y verificación

Cada stage produce un manifest firmado:

```bash
# Firmar la ISO — con HSM remoto vía Sigstore
# La clave privada nunca está en el disco del runner
cosign sign-blob \
  --key hsm://<provider>/<key-id> \
  --output-signature MagicLinux-1.0.iso.sig \
  MagicLinux-1.0.iso

# Verificar
magic-verify --iso MagicLinux-1.0.iso                \
  --signature MagicLinux-1.0.iso.sig                 \
  --public-key keys/verify.pub
```

El pipeline falla si cualquier etapa de verificación no pasa. No se publica ISO sin firma válida y test de integridad aprobado.

### Reproducible Build Attestation

Cada build produce un attestation siguiendo SLSA Level 3:

```bash
# Generar provenance (SLSA)
slsa-generator-generic \
  --artifact MagicLinux-<version>.iso \
  --output attestation.intoto.jsonl

# Firmar attestation con la misma identidad OIDC
cosign attest \
  --predicate attestation.intoto.jsonl \
  --type slsa.dev/provenance/v1 \
  MagicLinux-<version>.iso

# Publicar transparency log
cosign upload \
  --rekor-url https://rekor.sigstore.dev \
  --attestation attestation.intoto.jsonl

# Verificable por cualquiera:
# cosign verify-attestation --type slsa.dev/provenance/v1 \
#   --certificate-identity <expected-oidc> \
#   MagicLinux-<version>.iso
```

El manifest de build incluye: fuente del commit, parámetros de mmdebstrap/mkosi, hash de todos los inputs (deb packages, scripts, configs), y output hash de la ISO. Cualquier persona puede reproducir el build y comparar hashes.
