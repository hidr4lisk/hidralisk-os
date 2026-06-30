# hidrafetch — la app de estado de Hidralisk OS

Un "super neofetch" propio que **viene con el sistema**. A diferencia de un neofetch común
(que solo muestra hardware), `hidrafetch` pone el foco en lo que hace **único a Hidralisk OS**:
la **postura de seguridad por defecto** y la **integridad atómica (ABRoot)**.

Describe **esta** instalación, hablando de sí misma — no es un inventario de varias máquinas.
Impersonal: nada atado a una red, usuario o servidor concreto.

## Qué muestra
- **Cabecera neofetch** (dragón Hidralisk + datos): OS, base, kernel, uptime, paquetes, shell,
  escritorio, terminal, CPU, RAM, disco.
- **🛡️ Seguridad por defecto**: estado del firewall (ufw) + verificación de los `sysctl` de
  hardening (ASLR, kptr_restrict, dmesg_restrict, kexec, ptrace_scope, etc.) con un veredicto
  de postura (ENDURECIDO / PARCIAL / SIN APLICAR).
- **🔒 Integridad atómica (ABRoot)**: raíz activa/próxima (A/B), imagen OCI desplegada y su digest.

## Uso
```bash
hidrafetch            # vista completa
hidrafetch --plain    # sin color (para pipes/logs)
hidrafetch --no-art   # sin el dragón
hidrafetch --color    # forzar color aunque la salida no sea una terminal
```

## Diseño
- **Sin dependencias externas** — solo la stdlib de Python 3 (clave en una base inmutable donde
  no se hace `pip install`). El dragón está derivado del logo (medios-bloques Unicode), embebido.
- **Defensivo**: cada lectura degrada con elegancia (`n/d`) si algo no está; corre incluso fuera de
  Hidralisk (avisa que ABRoot/hardening no están).
- Los `sysctl` verificados son los de `vib/sources/hidralisk/hardening/99-hidra-hardening.conf`.

## Instalación (ya wireada en el recipe)
`vib/recipe.yml` lo instala como comando del sistema:
```yaml
- install -Dm755 /sources/hidralisk/status/hidrafetch /usr/bin/hidrafetch
```

## Opcional: saludo al abrir la terminal
Para que salude como neofetch al abrir una terminal (no en subshells), agregar a
`/etc/zsh/zshrc` (`zshrc-system`):
```zsh
if [[ -o interactive && $SHLVL -eq 1 ]] && command -v hidrafetch >/dev/null; then
  hidrafetch
fi
```
No está activado por defecto — queda a decisión (algunos lo quieren en cada terminal, otros no).
