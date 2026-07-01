# Roadmap — Hidralisk OS

Estado real del proyecto y lo que viene. Para el *por qué* de las decisiones de base, ver
[`docs/adr/`](docs/adr/).

## 🐉 Release actual: v0.1.0 (2026-07-01)

**Primera ISO instalable pública** → [Releases](https://github.com/hidr4lisk/hidralisk-os/releases/tag/v0.1.0).
La ISO (~2.14 GiB) va **partida en 2** por el límite de 2 GiB de GitHub (se rearma con `cat`). Instala la
imagen `ghcr.io/hidr4lisk/hidralisk-os:latest`. Incluye, además de lo de abajo: **Flathub** preconfigurado
(vía firstboot), **Desktop Icons NG** (íconos + selección en el escritorio), **logo propio en Ajustes>Acerca de**,
**tema oscuro por defecto** y un **shim de `apt`** que guía a `apx`/`flatpak`/`abroot`.

## Dónde está hoy

Hidralisk OS **instala y bootea** desde nuestra imagen OCI (`ghcr.io/hidr4lisk/hidralisk-os`)
mediante una ISO custom. Lo que ya funciona:

| Área | Estado |
|---|---|
| Instala + bootea desde la imagen OCI propia | ✅ |
| Branding completo (os-release, GRUB, instalador, GDM, Plymouth, wallpaper, avatar) | ✅ |
| Shell por defecto (zsh + starship + Ptyxis + Hack Nerd Font, system-wide) | ✅ |
| Hardening por defecto (sysctl + ufw) — ver [`HARDENING.md`](HARDENING.md) | ✅ en imagen |
| Escritorio "tipo Mint" (Dash to Panel + Arc Menu, menú = dragón) | ✅ en imagen (Spike-8) |
| Boot limpio: FsGuard desactivado (su filelist firmado por Vanilla no es re-firmable) | ✅ en imagen (Spike-8) |
| `abroot upgrade` apunta a nuestra imagen (`ghcr.io/hidr4lisk/hidralisk-os`) | ✅ en imagen (Spike-8) |
| Usuario por defecto **hidra/hidra** + hostname **hidralisk** (no vanilla/vanilla) | ✅ en ISO (hook 084) |
| Color de acento por defecto **Slate** (gris, no el amarillo de Vanilla) | ✅ en imagen |
| `sudo` funcional (la base no traía el binario) — hidra `(ALL:ALL) ALL` con password | ✅ en imagen |
| Un solo terminal: **Ptyxis** (se purgan Black Box + Alacritty de la base) | ✅ en imagen |
| `/etc/skel/.zshrc` — sin asistente `zsh-newuser-install` en el primer login | ✅ en imagen |

## Próximo

- ~~**Showcase de instalación end-to-end** desde la ISO~~ ✅ **verificado en vivo (2026-06-30, KVM)**: instala,
  **bootea limpio** (sin la pantalla roja de FsGuard), barra Mint + dragón, avatar + `Session=gnome` (sin la
  flor), usuario en zsh, **hidrafetch ENDURECIDO 7/8** + ufw, ABRoot A/B. (Gotcha resuelto: no borrar
  `org.vanillaos.FirstSetup.desktop` del image — el postInstall del instalador lo copia y su ausencia abortaba
  la instalación antes del `chown` del home; y el instalador crea el user en UID 1200 → `hidralisk-firstboot`
  detecta por UID≥1000.)
- ~~**Test de `apx` post-instalación**~~ ✅ **verificado**: creó un subsistema alpine rootless con el hardening
  puesto e instaló+corrió software (`podman rootless=true`). El "apt alternativo" funciona.
- ~~**Branding del instalador (gresource)**~~ ✅ **hecho y verificado en vivo (2026-07-01)**:
  1. Botón de confirmación **"Install Vanilla OS"** → **"Install Hidralisk OS"** — hook `082`
     (`iso/hooks/082-hidralisk-installer-confirm.chroot`: extrae → `sed` → recompila el gresource).
     ✅ confirmado en la instalación.
  2. Slideshow de Vanilla → **consola por defecto** — hook `083` (parchea `progress.py`, plano, para
     disparar `__on_console_button` al construir la vista). ✅ confirmado en la instalación.
- ~~**Pulido de `hidrafetch`**~~ ✅ **arreglado y verificado en vivo** (`Shell` del passwd, imagen desde
  `abroot.json` — se ve en el instalado, strip de ANSI de `abroot`). Nota `--no-cache`: cambiar solo un archivo bajo `vib/sources/` NO
  produce imagen nueva (podman cachea la capa `RUN`; el `--mount` no invalida el cache) → el próximo build
  de imagen debe ser `podman build --no-cache`.
- **Botón "Show slideshow" en la pantalla de progreso** — con `083` arrancamos en consola, pero queda
  visible el botón que vuelve al slideshow de Vanilla (el `tour_button` de `progress.py`). Sacarlo (que
  no se muestre) para que la instalación sea solo-consola. Ampliar el hook `083` (mismo `progress.py`):
  ocultar `self.tour_button` además de disparar `__on_console_button`. Requiere rebuild de ISO.
- ~~**Usuario por defecto hidra/hidra**~~ ✅ **hecho y verificado en vivo (2026-07-01)**: esta versión del
  vanilla-installer no tiene paso "users" (el user/pass/hostname salen fijos del postInstall de `processor.py`).
  Hook `084` (`iso/hooks/084-hidralisk-default-user.chroot`) lo renombra vanilla/vanilla → **hidra/hidra** +
  hostname **hidralisk**. Verificado en el SO instalado: `hidra` UID 1200 (zsh, sudo+lpadmin), home `hidra:hidra`.
  (En hardware real conviene cambiar la pass con `passwd` — el autologin queda en `hidra`.)
- ~~**Accent color Slate por defecto**~~ ✅ **hecho y verificado en vivo (2026-07-01)**: el amarillo lo trae la
  base `vanilla-os/desktop`; el override `95_hidralisk-desktop.gschema.override` setea
  `accent-color='slate'` (gana sobre `90-vanilla-settings`). Verificado en el session vivo de GNOME.
- **Plymouth de reboot de la sesión live** — al reiniciar tras instalar, el splash "Restarting" de la
  **sesión live (ISO)** todavía muestra la flor de Vanilla. El Plymouth del sistema **instalado** ya está
  brandeado (throbber→dragón en `vib/`), pero el de la ISO no → falta un hook que reemplace watermark +
  throbber del `vanilla-bgrt` en el chroot del live. Cosmético (se ve una vez durante la instalación).
- ~~**CI** — workflow que valide la receta en cada push~~ ✅ hecho (`.github/workflows/ci.yml`:
  yamllint + validación de estructura del recipe (PyYAML) + `bash -n` de los hooks + compile de
  hidrafetch). Offline/determinístico; el `vib build` real se corre en el Laboratorio.

## Hardening — fases siguientes

El hardening es iterativo. Las próximas capas (blacklist de módulos, `auditd`, parámetros de kernel en
GRUB, AppArmor profiles, minimización de servicios) están detalladas en
[`HARDENING.md`](HARDENING.md#roadmap-de-hardening-fases-siguientes).

## Experiencia de escritorio "tipo Linux Mint" — ✅ wireado + buildeado (Spike-8)

GNOME pelado (lo que trae Vanilla) es minimalista. Ofrecemos una experiencia **más tradicional,
tipo Linux Mint**: **panel arriba** con menú de apps + taskbar + bandeja, y el **botón de menú = el
dragón Hidralisk**. Vía **Dash to Panel** + **Arc Menu** + override dconf system-wide.

Verificado contra **GNOME Shell 49** (paquetes Debian `gnome-shell-extension-dash-to-panel` +
`gnome-shell-extension-arc-menu`; UUIDs `dash-to-panel@jderose9.github.com` + `arcmenu@arcmenu.com`)
y wireado al `recipe.yml`:
- ✅ **Ícono de menú** (dragón blanco) — `menu-icon-white-256.png` → `/usr/share/hidralisk/menu-icon.png`.
- ✅ **Override** `95_hidralisk-desktop.gschema.override` — habilita las extensiones (conserva `vso@`),
  panel arriba (`panel-positions`), ArcMenu layout `Mint` con el dragón como botón. Compila sin error.

✅ **Verificado en vivo (2026-06-30)**: en la instalación limpia el panel arriba renderiza, ambas extensiones
(`dash-to-panel` + `arcmenu`) quedan activas y el botón de menú muestra el dragón.

## App de estado del sistema — ✅ `hidrafetch`

La cara "consciente de sí misma" del sistema: un *neofetch con esteroides* que viene por defecto y
describe **esta** instalación (impersonal, no multi-máquina). Foco en el diferenciador: **postura de
hardening** (sysctl + ufw, con veredicto ENDURECIDO/PARCIAL) e **integridad ABRoot** (A/B + imagen),
más hardware. Dragón derivado del logo, sin dependencias externas (stdlib de python3).

`vib/sources/hidralisk/status/hidrafetch` — **wireado al recipe** (`/usr/bin/hidrafetch`). Pendiente:
decidir si saluda al abrir la terminal (ver `status/README.md`) y, más adelante, ampliarlo (servicios,
salud, red local).
