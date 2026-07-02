# Hardening — Hidralisk OS

La seguridad por defecto es **el diferenciador** de Hidralisk OS: la imagen viene endurecida de
fábrica, no como un checklist que el usuario aplica después. Este documento describe lo que **está
materializado hoy** en la imagen y lo que viene en fases siguientes.

> Principio rector: endurecer todo lo que se pueda **sin romper** el modelo de Vanilla OS 2
> (ABRoot + `apx`/distrobox/podman rootless). Un hardening que rompe los contenedores sin
> privilegios no sirve — el usuario lo desactivaría.

---

## 1. Kernel hardening (`sysctl`) — ✅ materializado

Fuente: [`vib/sources/hidralisk/hardening/99-hidra-hardening.conf`](vib/sources/hidralisk/hardening/99-hidra-hardening.conf)
→ se instala en `/etc/sysctl.d/99-hidra-hardening.conf` (paso del `vib/recipe.yml`).

| Área | Ajustes |
|---|---|
| **Memoria / ASLR** | `randomize_va_space=2`, `vm.mmap_min_addr=65536`, `fs.suid_dumpable=0` |
| **Info del kernel** | `kptr_restrict=2`, `dmesg_restrict=1`, `perf_event_paranoid=3`, `kexec_load_disabled=1` |
| **ptrace** | `yama.ptrace_scope=1` (restringe sin romper depuradores del usuario) |
| **Filesystem** | `protected_hardlinks`, `protected_symlinks`, `protected_fifos=2`, `protected_regular=2` |
| **Red (anti-spoof/MITM)** | `rp_filter`, `accept_redirects=0`, `send_redirects=0`, `accept_source_route=0`, `log_martians`, `icmp_echo_ignore_broadcasts`, `tcp_syncookies` |
| **BPF** | `net.core.bpf_jit_harden=2` (JIT endurecido, sin deshabilitar BPF) |

### Reconciliación con `apx` — qué se OMITE a propósito

Estas líneas, comunes en guías de hardening, romperían los contenedores rootless de `apx` y por eso
**no** se aplican (documentado en el `.conf`):

| Ajuste omitido | Por qué |
|---|---|
| `kernel.unprivileged_userns_clone=0` | `apx`/distrobox **necesitan** user namespaces sin privilegio |
| `kernel.unprivileged_bpf_disabled=1` | Puede romper red/containers rootless |
| `kernel.core_pattern=\|/bin/false` | Interfiere con `systemd-coredump` |
| `kernel.yama.ptrace_scope=2` | Rompe el attach de depuradores del usuario (se usa `=1`) |

Si en el futuro Hidralisk deja de depender de `apx`, se re-evalúan.

## 2. Firewall (`ufw`) y SSH — ✅ materializado

Aplicado en el `vib/recipe.yml`:

- `ufw default deny incoming` + `ufw default allow outgoing` — **sin puertos abiertos**.
- `ENABLED=yes` + servicio habilitado → la política se aplica en el primer arranque.
- **SSH viene APAGADO por defecto.** `openssh-server` está instalado pero el servicio no se
  habilita ni se abre el puerto: con un usuario por defecto conocido (`hidra`/`hidra`), un `sshd`
  escuchando desde el primer boot sería una puerta abierta en la LAN — exactamente lo contrario
  del pitch. Quien lo necesite lo enciende conscientemente:

  ```sh
  sudo systemctl enable --now ssh
  sudo ufw limit 22/tcp        # limit (no allow): rate-limit anti fuerza bruta
  ```

- **Drop-in de `sshd` endurecido, listo de fábrica** — cuando el usuario enciende SSH, ya arranca
  endurecido sin checklist: [`99-hidra-sshd.conf`](vib/sources/hidralisk/hardening/99-hidra-sshd.conf)
  (`PermitRootLogin no`, `MaxAuthTries 4`) instalado en `/etc/ssh/sshd_config.d/`.
- **Contraseña por defecto** — `hidra`/`hidra`; se pide cambiarla con `passwd` (README + notas de
  release). No se fuerza con `chage -d 0`: verificado en vivo que con `AutomaticLogin=hidra` una pass
  expirada rompe el autologin de GDM (`gdm-autologin:chauthtok: conversation failed` → sesión que no
  arranca). Forzar el cambio requeriría desactivar el autologin — ver roadmap.

## 3. Postura general — heredado de Vanilla OS 2

Hidralisk hereda de la base inmutable, sin trabajo extra:

- **Sistema base de solo lectura** (ABRoot) — un compromiso de runtime no persiste binarios del sistema.
- **Integridad de filesystem** vía composefs / fs-verity (verificación a nivel de bloque del root RO).
- **Updates transaccionales con rollback atómico** — un update malicioso o roto se revierte.

## 4. Decisiones e implementación — notas de transparencia

- **FsGuard desactivado (a propósito).** Vanilla trae `FsGuard`, un verificador que al boot compara un
  `filelist` de hashes contra una firma **minisign**. El problema: ese filelist está firmado con la
  **clave privada de Vanilla, cuya pública está EMBEBIDA en el binario** `/usr/sbin/FsGuard` — no es
  re-firmable para una imagen custom. Como nuestra imagen modifica archivos del filelist (branding,
  hardening, shell), FsGuard fallaba al boot ("Integrity Check Failed"). Se **quita el hook**
  (`rm /usr/share/init.d/010-fsguard.sh` en el recipe). La integridad del sistema la sigue dando
  **composefs/fs-verity** (root de solo lectura, verificado a nivel de bloque) + los `sysctl`/`ufw`.
  Reintroducir un FsGuard **con clave propia** (recompilando el binario + generando y firmando nuestro
  filelist) es un ítem de roadmap.
- **AppArmor y Yama NO están cargados** (gap conocido). El cmdline por defecto de Vanilla trae
  `lsm=integrity`, que resuelve a `lockdown,capability,ima,evm` — **sin `apparmor` ni `yama`**. Por eso
  el `kernel.yama.ptrace_scope=1` del §1 **queda seteado pero no es efectivo** (el LSM Yama no está
  activo; `hidrafetch` lo reporta como `n/d`, de ahí el `7/8` en vez de `8/8`). Cerrarlo = agregar
  `yama` (y evaluar `apparmor`) a la lista `lsm=` del cmdline del kernel — ver roadmap.

---

## Roadmap de hardening (fases siguientes)

Lo materializado hoy (sysctl + ufw) es la **primera capa**. Lo que sigue, en orden de prioridad:

1. **Cargar `yama` (y evaluar `apparmor`) en el `lsm=` del cmdline** — hoy `lsm=integrity` los deja
   afuera, así que `ptrace_scope` no es efectivo y AppArmor no confina. Es el gap que baja el score a 7/8.
2. **Blacklist de módulos del kernel** (`/etc/modprobe.d/`) — filesystems y protocolos raros
   (cramfs, hfs, dccp, sctp, firewire, etc.).
3. **`auditd`** con un ruleset base — trazabilidad de eventos de seguridad.
4. **Parámetros de kernel en GRUB** (`init_on_alloc/free`, `slab_nomerge`, `randomize_kstack_offset`,
   `lockdown=confidentiality`, `module.sig_enforce`) — evaluando impacto en boot/compatibilidad.
5. **AppArmor profiles propios** para servicios expuestos (depende del punto 1).
6. **FsGuard con clave propia** — recompilar el binario con nuestra pública minisign + generar y firmar
   nuestro `filelist` sobre la imagen final, para recuperar la verificación de integridad firmada.
7. **Minimización de servicios** — apagar lo que no se usa por defecto.
8. **Forzar el cambio de la contraseña por defecto** — hoy `AutomaticLogin=hidra` impide expirar la
   pass (rompe el autologin). Evaluar **desactivar el autologin** + `chage -d 0`: así el greeter de GDM
   (que sí soporta el diálogo de cambio) exige la contraseña nueva en el primer login.

Cada fase se materializa en `vib/recipe.yml` (o sus `sources/`) y se valida en una instalación real
antes de darse por cerrada. La regla del §0 (no romper `apx`/ABRoot) aplica a todas.
