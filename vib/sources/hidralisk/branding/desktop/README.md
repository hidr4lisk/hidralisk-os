# Escritorio "tipo Linux Mint" — staged (pendiente Lab)

Objetivo: que Hidralisk OS no muestre el GNOME pelado de Vanilla (top bar minimalista +
Activities), sino una experiencia **tradicional tipo Linux Mint**: panel arriba con menú de
apps + lista de ventanas (taskbar) + bandeja de sistema, y el **botón de menú = el dragón**.

Implementación vía dos extensiones GNOME + dconf preconfigurado (system-wide, mismo patrón que
el wallpaper):

| Pieza | Extensión | Paquete Debian (a verificar) |
|---|---|---|
| Panel arriba + taskbar | **Dash to Panel** | `gnome-shell-extension-dashtopanel` |
| Menú estilo Mint + ícono dragón | **Arc Menu** | `gnome-shell-extension-arcmenu` |

## Assets ya generados ✅
- `menu-icon-white-256.png` / `menu-icon-white-512.png` — el dragón blanco en trazo, sobre
  transparente, trimmeado y centrado. Lee bien hasta a ~44px (tamaño real del botón). Derivado de
  `~/Compartida/logo.png` (preserva el ojo). Va a `/usr/share/hidralisk/menu-icon.png`.
- `95_hidralisk-desktop.gschema.override` — habilita ambas extensiones + panel arriba + ArcMenu
  con el ícono. **Borrador** (los valores marcados ⚠️ dependen de la versión del paquete).

## Verificación en el Lab (ANTES de wirear en el recipe)
Igual que se hizo con ptyxis/starship:

1. **¿Existen los paquetes?** En una sesión con la base `desktop`:
   ```bash
   apt-cache policy gnome-shell-extension-dashtopanel gnome-shell-extension-arcmenu
   ```
   Si alguno no está empaquetado para la versión de GNOME de Vanilla, se baja como asset desde
   extensions.gnome.org (con la UUID correcta para esa versión de Shell) — como se hizo con la
   Hack Nerd Font.
2. **UUIDs reales:** instalar el paquete y `gnome-extensions list` → confirmar las UUIDs del
   `enabled-extensions` del override.
3. **Claves reales:** `gsettings list-recursively org.gnome.shell.extensions.dash-to-panel` y
   `… arcmenu` → confirmar `panel-positions` vs `panel-position`, el valor de `menu-layout`
   (Mint/Brisk/Eleven), y los nombres de las claves del ícono.
4. Ajustar el override con los valores confirmados.

## Wireado en el recipe (cuando 1-4 estén OK)
Agregar al `vib/recipe.yml` (en el módulo `hidralisk`, antes de `lpkg --lock`):

```yaml
# Escritorio tipo Mint: panel arriba (Dash to Panel) + menú con dragón (Arc Menu)
- apt-get install -y --no-install-recommends gnome-shell-extension-dashtopanel gnome-shell-extension-arcmenu
- cp /sources/hidralisk/branding/desktop/menu-icon-white-256.png /usr/share/hidralisk/menu-icon.png
- cp /sources/hidralisk/branding/desktop/95_hidralisk-desktop.gschema.override /usr/share/glib-2.0/schemas/
- glib-compile-schemas /usr/share/glib-2.0/schemas/
```

(El `apt-get install` va dentro del bloque `lpkg --unlock … lpkg --lock` que ya existe.)

## Validar post-build
Instalar la imagen y confirmar: panel arriba, taskbar con ventanas, bandeja, y el botón de menú
con el dragón abriendo un menú estilo Mint. Que el usuario igual pueda desactivar las extensiones
(no las bloqueamos).
