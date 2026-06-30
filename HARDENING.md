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

## 2. Firewall (`ufw`) — ✅ materializado

Aplicado en el `vib/recipe.yml`:

- `ufw default deny incoming` + `ufw default allow outgoing`
- `ufw allow 22/tcp` (la imagen trae `openssh-server`)
- `ENABLED=yes` + servicio habilitado → la política se aplica en el primer arranque.

## 3. Postura general — heredado de Vanilla OS 2

Hidralisk hereda de la base inmutable, sin trabajo extra:

- **Sistema base de solo lectura** (ABRoot) — un compromiso de runtime no persiste binarios del sistema.
- **Integridad de filesystem** vía composefs / fs-verity.
- **Updates transaccionales con rollback atómico** — un update malicioso o roto se revierte.
- **AppArmor** presente en la base Debian/Vanilla.

---

## Roadmap de hardening (fases siguientes)

Lo materializado hoy (sysctl + ufw) es la **primera capa**. Lo que sigue, en orden de prioridad:

1. **Blacklist de módulos del kernel** (`/etc/modprobe.d/`) — filesystems y protocolos raros
   (cramfs, hfs, dccp, sctp, firewire, etc.).
2. **`auditd`** con un ruleset base — trazabilidad de eventos de seguridad.
3. **Parámetros de kernel en GRUB** (`init_on_alloc/free`, `slab_nomerge`, `randomize_kstack_offset`,
   `lockdown=confidentiality`, `module.sig_enforce`) — evaluando impacto en boot/compatibilidad.
4. **AppArmor profiles propios** para servicios expuestos.
5. **Minimización de servicios** — apagar lo que no se usa por defecto.

Cada fase se materializa en `vib/recipe.yml` (o sus `sources/`) y se valida en una instalación real
antes de darse por cerrada. La regla del §0 (no romper `apx`/ABRoot) aplica a todas.
