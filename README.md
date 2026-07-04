# Hidralisk OS

[![CI](https://github.com/hidr4lisk/hidralisk-os/actions/workflows/ci.yml/badge.svg)](https://github.com/hidr4lisk/hidralisk-os/actions/workflows/ci.yml)

**A custom Linux distribution, immutable and hardened by default**, built end to end
on top of [Vanilla OS 2](https://vanillaos.org).

🌐 **[Website](https://hidr4lisk.github.io/hidralisk-os/)** · 🇦🇷 **[Leer en español](./README.es.md)**

### In one sentence

A Linux that **ships secure out of the box** and **doesn't break**: the base system is read-only,
and every update is atomic and reversible — if something goes wrong, it **rolls back to the previous
state on its own**. On top of that base we add what makes it ours: security enabled by default, a
traditional (Mint-style) desktop, and a terminal that's ready to work the moment you install.

### Why it exists

Hidralisk OS is, above all, a **learning and showcase project**: the goal is to build an immutable
distribution **from zero to installable** and, along the way, make it genuinely usable. It **doesn't
try to compete** with Ubuntu, Fedora or Vanilla OS itself — its value is in *showing how an atomic,
secure distro is put together* on top of a mature base: a custom OCI image, an installable ISO,
hardening, branding and integration, all reproducible and documented. If you're interested in the
**behind the scenes** of an immutable distro — how it's built, signed, installed and maintained —
this repo is exactly that.

> **Status:** functional, **verified end-to-end** — it installs from a custom ISO, **boots clean** and
> runs with everything in place (hardening, custom desktop, working `apx`, default user with `sudo`).
> Under active development — see [`ROADMAP.md`](ROADMAP.md).

## ⬇️ Download

**Latest installable ISO:** [Releases](https://github.com/hidr4lisk/hidralisk-os/releases/latest) ·
step-by-step instructions on the [website](https://hidr4lisk.github.io/hidralisk-os/#descargar).
The ISO ships **split in two parts** (GitHub's 2 GiB limit); rebuild it with `cat` (instructions in
the release) and flash it with Etcher/Ventoy/`dd`.

> 🔑 **Default credentials: user `hidra` / password `hidra`.**
> Change it as soon as you log in with `passwd` (and rename the user if you like).
> SSH ships **off** by default, so these credentials give no remote access.
> Autologin applies to the initial install only: after the first system update
> (`abroot upgrade`) you'll see the GDM login screen — log in as `hidra` with your password.

---

## What sets it apart

### 🛡️ Security by default, not optional
The core differentiator. The image ships hardened from the factory, not as a checklist the user
has to apply afterwards:

- **Kernel hardening** via `sysctl` (full ASLR, `kptr_restrict`, `dmesg_restrict`,
  `kexec_load_disabled`, symlink/hardlink protection, network anti-spoofing, SYN cookies,
  BPF JIT hardening). See [`HARDENING.md`](HARDENING.md).
- **`ufw` firewall with a `deny incoming` policy** active from the very first boot, **with no open
  ports**. **SSH ships off** (with a well-known default user, a listening `sshd` would be an open
  door); it can be enabled with two commands and starts already hardened
  (`PermitRootLogin no`) — see [`HARDENING.md`](HARDENING.md).
- **Reconciled with Vanilla's container model** (`apx` / distrobox / rootless podman):
  the knobs that would break unprivileged containers are deliberately left out. Real security,
  without sacrificing usability.

### 🐚 A terminal experience that's ready to use
Vanilla ships with bare GNOME and no terminal. Hidralisk OS brings, configured system-wide:

- **zsh** as the default shell, with `zsh-autosuggestions` + `zsh-syntax-highlighting`.
- **Starship** with a custom themed prompt.
- **Ptyxis** as the **only** terminal (no duplicates) + **Hack Nerd Font**.
- **`sudo` ready** — the default user has admin privileges from the start.
- **Impersonal, system-wide** configuration (`/etc/zsh/zshrc`, `/etc/starship.toml`) — it works
  for any user right after install, **no dotfiles to copy and no wizards** on first login.

### 🖥️ A traditional, Mint-style desktop
Vanilla's bare GNOME becomes a familiar experience, with nothing to configure:

- **Top panel** with an app menu + taskbar + tray (Dash to Panel).
- **Mint-style application menu** whose button is the Hidralisk dragon (Arc Menu).
- **Slate accent color** (a sober gray) instead of Vanilla's yellow.
- All by default via system-wide `dconf`; the user can change any of it at any time.

### 📟 It knows itself — `hidrafetch`
A *neofetch on steroids* that ships with the system and describes **this** installation: hardware,
**hardening posture** (with a `HARDENED`/`PARTIAL` verdict) and **ABRoot integrity** (A/B + image).
Python stdlib only, no external dependencies.

### 🐉 Its own identity, end to end
GRUB, installer, GDM, Plymouth, desktop/login/live-session wallpaper and default user avatar:
everything carries the Hidralisk brand (the dragon). No residual "Vanilla OS" in sight.

---

## Architecture in one picture

```
┌─────────────────────────────────────────────────────────┐
│  Hidralisk layer  (what we build)                        │
│  · hardening (sysctl + ufw)   · shell (zsh+starship)     │
│  · branding (GRUB/GDM/Plymouth/wallpaper/avatar)         │
├─────────────────────────────────────────────────────────┤
│  Vanilla OS 2 base  (inherited, mature)                  │
│  · ABRoot (atomic A/B, rollback)   · GNOME               │
│  · lpkg (package layer)   · apx (containers)             │
│  · composefs / fs-verity (integrity)                     │
└─────────────────────────────────────────────────────────┘
```

- **ABRoot** — two roots (A/B); every update is transactional and reversible.
- **lpkg** — locks/unlocks the base system's package layer (that's how we inject our stack).
- **apx** — install software *on top* in rootless containers, without touching the base system.
- **composefs + fs-verity** — filesystem integrity inherited from Vanilla.

Stack details and design decisions: [`docs/adr/`](docs/adr/).

## How it's built

Hidralisk OS is made of two artifacts, both built on our own infrastructure:

| Artifact | What it is | Where |
|---|---|---|
| **OCI image** | The system itself, derived from Vanilla via [Vib](https://github.com/Vanilla-OS/Vib) | [`vib/`](vib/) → `ghcr.io/hidr4lisk/hidralisk-os` |
| **Installable ISO** | Installation medium that deploys the OCI image | [`iso/`](iso/) |

```bash
# Image (summary — see vib/README.md)
./vib-amd64 build vib/recipe.yml          # recipe → Containerfile
podman build -t hidralisk-os -f vib/Containerfile vib/
# The ISO uses Vanilla's live toolchain with our hooks (see iso/README.md)
```

The installer downloads the OCI image published on GHCR (which **must remain public**) and deploys
it to disk with ABRoot.

## Roadmap

What's next (more hardening phases, installer branding polish, `hidrafetch` improvements)
lives in [`ROADMAP.md`](ROADMAP.md).

## License

[MIT](LICENSE).
