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

Release download (after a release is published):

```text
https://github.com/ivyiz/ivy-rejoin-tool/releases/latest/download/ivy-tun.zip
```

## Quick install

```bash
pkg update -y
pkg install -y bash coreutils curl sqlite ncurses-utils unzip
termux-setup-storage

curl -L -o /sdcard/Download/ivy-tun.sh "https://raw.githubusercontent.com/ivyiz/ivy-rejoin-tool/main/ivy-tun.sh"
bash /sdcard/Download/ivy-tun.sh
```

Grant root access to Termux when Magisk/KernelSU asks.

## Usage

- `2` or `4`: select apps and assign Place ID/server link
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