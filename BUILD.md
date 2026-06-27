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
│   ├── sign.key             → clave de firma (protegida)
│   └── verify.pub           → clave pública de verificación
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
    runs-on: ubuntu-24.04
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
# Firmar la ISO
signify -S -s keys/sign.key -m MagicLinux-1.0.iso  \
  -o MagicLinux-1.0.iso.sig

# Verificar
magic-verify --iso MagicLinux-1.0.iso              \
  --signature MagicLinux-1.0.iso.sig               \
  --public-key keys/verify.pub
```

El pipeline falla si cualquier etapa de verificación no pasa. No se publica ISO sin firma válida y test de integridad aprobado.
