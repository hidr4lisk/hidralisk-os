# Hidralisk OS

[![CI](https://github.com/hidr4lisk/hidralisk-os/actions/workflows/ci.yml/badge.svg)](https://github.com/hidr4lisk/hidralisk-os/actions/workflows/ci.yml)

**Distribución Linux inmutable, atómica y endurecida por defecto** — construida sobre
[Vanilla OS 2](https://vanillaos.org), con identidad, shell y postura de seguridad propias.

Hidralisk OS no reinventa el sistema operativo: parte de una base inmutable madura
(ABRoot A/B, OCI, composefs/fs-verity) y construye **encima** lo que la diferencia —
**seguridad por defecto**, una **experiencia de terminal lista para usar**, y branding propio
de punta a punta. El sistema base es de solo lectura y se actualiza de forma transaccional;
si algo sale mal, el rollback es atómico.

> Estado: **funcional**. Instala y bootea desde nuestra imagen OCI con una ISO custom.
> En desarrollo activo — ver [`ROADMAP.md`](ROADMAP.md).

---

## Qué la diferencia

### 🛡️ Seguridad por defecto, no opcional
El diferenciador central. La imagen viene endurecida de fábrica, no como un checklist que el
usuario tiene que aplicar después:

- **Kernel hardening** vía `sysctl` (ASLR completo, `kptr_restrict`, `dmesg_restrict`,
  `kexec_load_disabled`, protección de symlinks/hardlinks, anti-spoofing de red, SYN cookies,
  BPF JIT hardening). Ver [`HARDENING.md`](HARDENING.md).
- **Firewall `ufw` con política `deny incoming`** activa desde el primer arranque (SSH permitido).
- **Reconciliado con el modelo de contenedores de Vanilla** (`apx` / distrobox / podman rootless):
  se omiten a propósito los ajustes que romperían los contenedores sin privilegios. Seguridad
  real, sin sacrificar usabilidad.

### 🐚 Experiencia de terminal lista para usar
Vanilla viene con GNOME pelado y sin terminal. Hidralisk OS trae, configurado a nivel sistema:

- **zsh** como shell por defecto, con `zsh-autosuggestions` + `zsh-syntax-highlighting`.
- **Starship** con un prompt temático propio.
- **Ptyxis** como terminal + **Hack Nerd Font**.
- Configuración **impersonal y system-wide** (`/etc/zsh/zshrc`, `/etc/starship.toml`) — funciona
  para cualquier usuario apenas instala, sin dotfiles que copiar.

### 🐉 Identidad propia de punta a punta
GRUB, instalador, GDM, Plymouth, wallpaper de escritorio/login/sesión live y avatar de usuario
por defecto: todo con la marca Hidralisk (el dragón). Nada de "Vanilla OS" residual a la vista.

---

## Arquitectura en una imagen

```
┌─────────────────────────────────────────────────────────┐
│  Capa Hidralisk  (lo que construimos nosotros)           │
│  · hardening (sysctl + ufw)   · shell (zsh+starship)     │
│  · branding (GRUB/GDM/Plymouth/wallpaper/avatar)         │
├─────────────────────────────────────────────────────────┤
│  Base Vanilla OS 2  (heredado, maduro)                   │
│  · ABRoot (A/B atómico, rollback)   · GNOME              │
│  · lpkg (capa de paquetes)   · apx (contenedores)        │
│  · composefs / fs-verity (integridad)                    │
└─────────────────────────────────────────────────────────┘
```

- **ABRoot** — dos roots (A/B); cada update es transaccional y reversible.
- **lpkg** — bloquea/desbloquea la capa de paquetes del sistema base (así inyectamos nuestro stack).
- **apx** — instalar software *encima* en contenedores rootless, sin tocar el sistema base.
- **composefs + fs-verity** — integridad del sistema de archivos heredada de Vanilla.

Detalle del stack y decisiones de diseño: [`docs/adr/`](docs/adr/).

## Cómo se construye

Hidralisk OS se arma con dos artefactos, ambos buildeados en infraestructura propia:

| Artefacto | Qué es | Dónde |
|---|---|---|
| **Imagen OCI** | El sistema en sí, derivado de Vanilla vía [Vib](https://github.com/Vanilla-OS/Vib) | [`vib/`](vib/) → `ghcr.io/hidr4lisk/hidralisk-os` |
| **ISO instalable** | Medio de instalación que despliega la imagen OCI | [`iso/`](iso/) |

```bash
# Imagen (resumen — ver vib/README.md)
./vib-amd64 build vib/recipe.yml          # receta → Containerfile
podman build -t hidralisk-os -f vib/Containerfile vib/
# La ISO usa el toolchain live de Vanilla con nuestros hooks (ver iso/README.md)
```

El instalador baja la imagen OCI publicada en GHCR (que **debe permanecer pública**) y la despliega
en disco con ABRoot.

## Roadmap

Lo que viene (escritorio tipo tradicional, app de estado del sistema, más fases de hardening) está
en [`ROADMAP.md`](ROADMAP.md).

## Licencia

[MIT](LICENSE).
