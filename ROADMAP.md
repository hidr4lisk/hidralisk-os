# Roadmap — Hidralisk OS

Estado real del proyecto y lo que viene. Para el *por qué* de las decisiones de base, ver
[`docs/adr/`](docs/adr/).

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

## Próximo

- **Showcase de instalación end-to-end** desde la ISO: verificar en una instalación limpia que GRUB,
  instalador, GDM (avatar + fondo), escritorio (wallpaper), terminal (zsh + starship) y la postura de
  seguridad (`sysctl`/`ufw`) quedan todos correctos.
- **Branding del instalador (gresource)** — pendientes confirmados en vivo (2026-06-30), viven en
  `vanilla-installer.gresource` → requieren build propio del instalador:
  1. El botón final del resumen dice **"Install Vanilla"** → debe decir **"Install Hidralisk OS"**.
  2. Durante la instalación se ven las **imágenes/slideshow de Vanilla** → sacarlas y dejar por
     defecto **"show console output"** (que se vea el código directo, no las imágenes de Vanilla).
- **Test de `apx` post-instalación** — confirmar que instalar software en contenedores rootless
  funciona con el hardening aplicado (es la razón por la que se omiten ciertos `sysctl`).
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

Pendiente: re-test en vivo (que el panel renderice como se espera en una instalación limpia).

## App de estado del sistema — ✅ `hidrafetch`

La cara "consciente de sí misma" del sistema: un *neofetch con esteroides* que viene por defecto y
describe **esta** instalación (impersonal, no multi-máquina). Foco en el diferenciador: **postura de
hardening** (sysctl + ufw, con veredicto ENDURECIDO/PARCIAL) e **integridad ABRoot** (A/B + imagen),
más hardware. Dragón derivado del logo, sin dependencias externas (stdlib de python3).

`vib/sources/hidralisk/status/hidrafetch` — **wireado al recipe** (`/usr/bin/hidrafetch`). Pendiente:
decidir si saluda al abrir la terminal (ver `status/README.md`) y, más adelante, ampliarlo (servicios,
salud, red local).
