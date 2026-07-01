# iso/ — ISO instalable de Hidralisk OS (Spike-4b)

> Registro mínimo. La doc completa se arma cuando el proyecto esté terminado.

La ISO instalable se construye con el **`live-iso` de Vanilla** + nuestro hook, que
reemplaza el `recipe.json` del instalador para que despliegue **nuestra imagen OCI**
(`ghcr.io/hidr4lisk/hidralisk-os`) en vez de `vanilla-os/desktop`.

## Cómo se buildeó (en el Laboratorio, 2026-06-29)

```sh
git clone https://github.com/Vanilla-OS/live-iso && cd live-iso
# hooks del chroot
cp <este-repo>/iso/hooks/*.chroot etc/config/hooks/live/
chmod +x etc/config/hooks/live/*.chroot
# menú GRUB de la ISO (rebrand)
cp <este-repo>/iso/bootloaders/grub-pc/grub.cfg etc/config/bootloaders/grub-pc/grub.cfg
# overlay de la sesión live (wallpaper del instalador)
cp -r <este-repo>/iso/includes.chroot/. etc/config/includes.chroot/
docker run --privileged -i -v /proc:/proc -v ${PWD}:/working_dir -w /working_dir \
  ghcr.io/vanilla-os/pico:main /bin/bash -s etc/terraform.conf < build.sh
# → builds/amd64/VanillaOS-2-stable.YYYYMMDD.iso  (instala Hidralisk OS directo)
```

## Qué hace cada artefacto

- **`hooks/078-hidralisk-recipe.chroot`** — escribe `/etc/vanilla-installer/recipe.json`
  apuntando las **3** imágenes (`default`/`nvidia`/`vm` — en KVM el instalador dispara `vm`)
  a `ghcr.io/hidr4lisk/hidralisk-os:latest` + `distro_name: "Hidralisk OS"`. **Esto define
  qué se instala.**
- **`hooks/079-hidralisk-installer-name.chroot`** *(branding, Spike-5)* — rebrand del
  `Name` del `.desktop` del instalador → "Hidralisk OS" (el ícono/lanzador).
- **`hooks/080-hidralisk-installer-flower.chroot`** *(branding, Spike-5)* — reemplaza el
  ícono `flower` del instalador (`distro_logo`) por el dragón (SVG negro embebido).
  **Es un hook (no `includes.chroot`)** porque el `.deb` del instalador se instala en el
  hook 001, *después* de los includes — así que el overlay se pisaba; el hook corre al final.
- **`hooks/081-hidralisk-live-wallpaper.chroot`** *(branding, Spike-6)* — recompila los schemas
  para que el wallpaper de la **sesión live del instalador** sea el de Hidralisk. El PNG y el
  override van por `includes.chroot` (acá sí sirve: ningún paquete los pisa).
- **`hooks/082-hidralisk-installer-confirm.chroot`** *(branding, Spike-8)* — parchea el string
  "Install Vanilla OS" (botón de la pantalla de confirmación) → "Install Hidralisk OS". Vive
  **compilado dentro de** `vanilla-installer.gresource`, así que el hook lo extrae → `sed` en los
  `.ui` → recompila con `glib-compile-resources`. No-fatal. ✅ **Verificado en vivo (2026-07-01).**
- **`hooks/083-hidralisk-installer-console.chroot`** *(branding, Spike-8)* — durante la instalación,
  arranca mostrando **la consola** en vez del slideshow de Vanilla. Parchea `progress.py` (plano, no
  gresource) para disparar `__on_console_button()` al construir la vista. ✅ **Verificado en vivo.**
- **`hooks/084-hidralisk-default-user.chroot`** *(usuario)* — esta versión del vanilla-installer **no tiene
  paso "users"** (no hay `defaults/users.py`), así que el usuario/pass/hostname salen **fijos** del postInstall
  de albius en `utils/processor.py` (originalmente `vanilla`/`vanilla` UID 1200, hostname `vanilla`). El hook
  parchea `processor.py` a **hidra/hidra** + hostname **hidralisk** (conserva el grupo interno
  `vanilla-first-setup` y el id `efi "vanilla"` de grub-install, que **no** es el usuario). Idempotente,
  no-fatal. ✅ **Verificado en vivo (2026-07-01):** el SO instalado crea `hidra` (UID 1200, zsh, sudo+lpadmin),
  hostname `hidralisk`, home `hidra:hidra`. El `hidralisk-firstboot` de la imagen lo detecta por UID≥1000.
- **`bootloaders/grub-pc/grub.cfg`** *(branding, Spike-5)* — menú de boot de la ISO:
  `menuentry "Install Hidralisk OS"` (+ Safe Graphics / Nouveau).

Detalle y lecciones (core no es instalable, patrón `lpkg`, etc.) → `docs/adr/ADR-002` §6.

> **Pendiente de branding:** el **Plymouth de reboot de la sesión live** (splash "Restarting" de la ISO)
> todavía muestra la flor de Vanilla → falta un hook que brandee el `vanilla-bgrt` del chroot del live
> (watermark + throbber, como en el `vib/` del instalado). Cosmético, se ve una vez. El botón de
> confirmación (`082`) y la consola-por-defecto (`083`) ya están resueltos y verificados. El logo de GDM,
> el splash de Plymouth del instalado, el wallpaper y el avatar ya están (imagen vía `vib/`, salvo el
> wallpaper live que es de la ISO).
