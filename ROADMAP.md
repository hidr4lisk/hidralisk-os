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

## Experiencia de escritorio "tipo Linux Mint" — 🟡 preparado, pendiente Lab

GNOME pelado (lo que trae Vanilla) es minimalista. La idea es ofrecer una experiencia **más
tradicional, tipo Linux Mint**: **panel arriba** con menú de apps + taskbar + bandeja, y el
**botón de menú = el dragón Hidralisk**. Vía **Dash to Panel** + **Arc Menu** + dconf system-wide.

Ya hecho (en `vib/sources/hidralisk/branding/desktop/`):
- ✅ **Ícono de menú** (dragón blanco, lee bien hasta ~44px) — `menu-icon-white-{256,512}.png`.
- ✅ **Override dconf** borrador (`95_hidralisk-desktop.gschema.override`) — habilita las extensiones,
  panel arriba, ArcMenu con el dragón.
- ✅ **Plan de integración + checklist** de verificación → `desktop/README.md`.

Falta (necesita Lab): verificar nombres de paquete + UUIDs + claves exactas (cambian por versión),
ajustar el override, wirearlo al `recipe.yml` y buildear. No está en el recipe activo todavía para no
arriesgar el build de Spike-7.

## App de estado del sistema — ✅ `hidrafetch`

La cara "consciente de sí misma" del sistema: un *neofetch con esteroides* que viene por defecto y
describe **esta** instalación (impersonal, no multi-máquina). Foco en el diferenciador: **postura de
hardening** (sysctl + ufw, con veredicto ENDURECIDO/PARCIAL) e **integridad ABRoot** (A/B + imagen),
más hardware. Dragón derivado del logo, sin dependencias externas (stdlib de python3).

`vib/sources/hidralisk/status/hidrafetch` — **wireado al recipe** (`/usr/bin/hidrafetch`). Pendiente:
decidir si saluda al abrir la terminal (ver `status/README.md`) y, más adelante, ampliarlo (servicios,
salud, red local).
