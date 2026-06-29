# iso/ — ISO instalable de Hidralisk OS (Spike-4b)

> Registro mínimo. La doc completa se arma cuando el proyecto esté terminado.

La ISO instalable se construye con el **`live-iso` de Vanilla** + nuestro hook, que
reemplaza el `recipe.json` del instalador para que despliegue **nuestra imagen OCI**
(`ghcr.io/hidr4lisk/hidralisk-os`) en vez de `vanilla-os/desktop`.

## Cómo se buildeó (en el Laboratorio, 2026-06-29)

```sh
git clone https://github.com/Vanilla-OS/live-iso && cd live-iso
cp <este-repo>/iso/hooks/078-hidralisk-recipe.chroot etc/config/hooks/live/
chmod +x etc/config/hooks/live/078-hidralisk-recipe.chroot
docker run --privileged -i -v /proc:/proc -v ${PWD}:/working_dir -w /working_dir \
  ghcr.io/vanilla-os/pico:main /bin/bash -s etc/terraform.conf < build.sh
# → builds/amd64/VanillaOS-2-stable.YYYYMMDD.iso  (instala Hidralisk OS directo)
```

## hooks/078-hidralisk-recipe.chroot

Escribe `/etc/vanilla-installer/recipe.json` en el chroot de la ISO. Apunta las **3**
imágenes (`default`/`nvidia`/`vm` — en KVM el instalador dispara `vm`) a
`ghcr.io/hidr4lisk/hidralisk-os:latest` y pone `distro_name: "Hidralisk OS"`.

Detalle y lecciones (core no es instalable, patrón `lpkg`, etc.) → `docs/adr/ADR-002` §6.
