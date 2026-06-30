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
- **Test de `apx` post-instalación** — confirmar que instalar software en contenedores rootless
  funciona con el hardening aplicado (es la razón por la que se omiten ciertos `sysctl`).
- **CI** — workflow que valide la receta Vib en cada push (reemplaza al pipeline anterior, ya retirado).

## Hardening — fases siguientes

El hardening es iterativo. Las próximas capas (blacklist de módulos, `auditd`, parámetros de kernel en
GRUB, AppArmor profiles, minimización de servicios) están detalladas en
[`HARDENING.md`](HARDENING.md#roadmap-de-hardening-fases-siguientes).

## Experiencia de escritorio (backlog)

GNOME pelado (lo que trae Vanilla) es minimalista. La idea es ofrecer una experiencia **más
tradicional, tipo Linux Mint**:

- **Panel arriba** con menú de apps + taskbar + bandeja de sistema.
- **Botón de menú = el dragón Hidralisk.**

Implementación probable, vía extensiones GNOME + dconf preconfigurado a nivel sistema (como el
wallpaper): **Dash to Panel** (panel + taskbar) + **Arc Menu** (menú estilo Mint, con ícono custom).
Paso previo: verificar disponibilidad de los paquetes en el repo Debian.

## App de estado del sistema (backlog)

Una app/CLI que venga **por defecto** para ver el estado de cualquier instalación de Hidralisk OS
(hardware, red, firewall, servicios, salud, integridad de ABRoot): un *neofetch con esteroides*,
branded (dragón, colores) e **impersonal**. La cara "consciente de sí misma" del sistema.
