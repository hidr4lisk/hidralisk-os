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
- **`bootloaders/grub-pc/grub.cfg`** *(branding, Spike-5)* — menú de boot de la ISO:
  `menuentry "Install Hidralisk OS"` (+ Safe Graphics / Nouveau).

Detalle y lecciones (core no es instalable, patrón `lpkg`, etc.) → `docs/adr/ADR-002` §6.

> **Pendiente de branding (no resuelto acá):** botón final "Install Vanilla OS" dentro del
> instalador (vive en `vanilla-installer.gresource`, requiere build propio del instalador),
> logo de GDM y splash de Plymouth (requieren el asset del logo Hidralisk).
