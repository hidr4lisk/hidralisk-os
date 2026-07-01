# Hidralisk OS

[![CI](https://github.com/hidr4lisk/hidralisk-os/actions/workflows/ci.yml/badge.svg)](https://github.com/hidr4lisk/hidralisk-os/actions/workflows/ci.yml)

**Una distribución Linux propia, inmutable y endurecida por defecto**, construida de punta a
punta sobre [Vanilla OS 2](https://vanillaos.org).

### En una frase

Un Linux que **viene seguro de fábrica** y que **no se rompe**: el sistema base es de solo lectura,
y cada actualización es atómica y reversible — si algo sale mal, **vuelve solo al estado anterior**.
Sobre esa base le sumamos lo que lo hace nuestro: seguridad activada por defecto, un escritorio
tradicional (tipo Mint) y una terminal lista para trabajar apenas instalás.

### Por qué existe

Hidralisk OS es, ante todo, un **proyecto de aprendizaje y showcase**: el objetivo es construir una
distribución inmutable **de cero a instalable** y, en el camino, dejarla realmente usable. **No busca
competir** con Ubuntu, Fedora ni con la propia Vanilla OS — su valor está en *mostrar cómo se arma*
una distro atómica y segura sobre una base madura: imagen OCI propia, ISO instalable, hardening,
branding e integración, todo reproducible y documentado. Si te interesa el **detrás de escena** de
una distro inmutable —cómo se construye, se firma, se instala y se mantiene— este repo es eso.

> **Estado:** funcional, **verificado end-to-end** — instala desde una ISO custom, **bootea limpio** y
> corre con todo puesto (hardening, escritorio propio, `apx` operativo, usuario listo con `sudo`).
> En desarrollo activo — ver [`ROADMAP.md`](ROADMAP.md).

## ⬇️ Descargar

**Primera ISO instalable:** [Releases → v0.1.0](https://github.com/hidr4lisk/hidralisk-os/releases/tag/v0.1.0).
La ISO va **partida en dos** (límite de 2 GiB de GitHub); se rearma con `cat` (instrucciones en la release) y
se flashea con Etcher/Ventoy/`dd`. Usuario por defecto **hidra/hidra** (cambialo con `passwd` tras instalar).

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
- **Ptyxis** como **único** terminal (sin duplicados) + **Hack Nerd Font**.
- **`sudo` listo** — el usuario por defecto tiene privilegios de administrador desde el arranque.
- Configuración **impersonal y system-wide** (`/etc/zsh/zshrc`, `/etc/starship.toml`) — funciona
  para cualquier usuario apenas instala, **sin dotfiles que copiar ni asistentes** en el primer login.

### 🖥️ Escritorio tradicional, tipo Mint
El GNOME pelado de Vanilla se convierte en una experiencia familiar, sin configurar nada:

- **Panel arriba** con menú de apps + taskbar + bandeja (Dash to Panel).
- **Menú de aplicaciones estilo Mint** cuyo botón es el dragón Hidralisk (Arc Menu).
- **Color de acento Slate** (gris sobrio) en vez del amarillo de Vanilla.
- Todo por defecto vía `dconf` system-wide; el usuario lo puede cambiar cuando quiera.

### 📟 Se conoce a sí misma — `hidrafetch`
Un *neofetch con esteroides* que viene con el sistema y describe **esta** instalación: hardware,
**postura de hardening** (con veredicto `ENDURECIDO`/`PARCIAL`) e **integridad ABRoot** (A/B + imagen).
Solo stdlib de Python, sin dependencias externas.

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

Lo que viene (más fases de hardening, pulido del branding del instalador, mejoras de `hidrafetch`)
está en [`ROADMAP.md`](ROADMAP.md).

## Licencia

[MIT](LICENSE).
