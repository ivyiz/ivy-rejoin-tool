# Ivy TUN

Rooted Android + Termux helper for managing multiple Roblox sessions on **your own accounts**.

## Download

- Script: `ivy-tun.sh`
- Guide: `IVY_TUN_INSTALL.md`
- Package: `ivy-tun.zip`

Permanent raw download:

```text
https://raw.githubusercontent.com/ivyiz/ivy-rejoin-tool/main/ivy-tun.sh
```

Release download:

```text
https://github.com/ivyiz/ivy-rejoin-tool/releases/latest/download/ivy-tun.zip
```

## Quick install

One line (script downloads to Termux home as `i`):

```bash
pkg install -y curl sqlite ncurses-utils && curl -L -o i https://github.com/ivyiz/ivy-rejoin-tool/raw/main/ivy-tun.sh && bash i
```

Grant root access to Termux when Magisk/KernelSU asks.

## Usage

- `2`: select one or more installed apps, press `0` to confirm, then assign a shared or per-app Place ID/server link
- `11`: list all installed packages (Roblox-like packages first)
- `4`: auto-assign one link to all detected Roblox-like packages
- `6`: login with `.ROBLOSECURITY` cookie
- `7`: manage profiles
- `10`: configure Discord webhook/uptime
- `1`: start auto-rejoin
- `Ctrl+C`: stop auto-rejoin

## Security

- Use only with your own Roblox accounts.
- Never commit or share `cookie.txt`, `profiles.conf`, `packages.conf`, `discord.conf`, logs, or exported cookies.
- Some WebViews store cookies in `encrypted_value`; this tool cannot decrypt them.
- Running rooted tools and automating account login may violate Roblox Terms of Service and can risk account restrictions.

## Disclaimer

This project is not affiliated with Roblox Corporation or Termux. Use at your own risk.