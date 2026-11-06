# SSH Key Installer

Install your SSH public key on a Linux, OpenWrt, or Windows OpenSSH server with one command.

Windows clients (PowerShell 5.1+):

```powershell
irm https://guajun.github.io/ssh-key-installer/install.ps1 | iex
```

Termux, macOS, and Linux clients (POSIX sh):

```sh
curl -fsSL https://guajun.github.io/ssh-key-installer/install.sh | sh
```

Both scripts prompt for the SSH destination and remote operating system, defaulting to automatic OS detection. Password input is handled directly by `ssh`; the scripts never read or store it.

## Features

- Linux targets: safely updates `~/.ssh/authorized_keys` and permissions.
- OpenWrt/Dropbear targets: automatically uses `/etc/dropbear/authorized_keys` for root.
- Windows targets: updates the user key file and, for administrators, `administrators_authorized_keys` with the ACLs required by Windows OpenSSH.
- Windows targets work from any client: the remote side always runs Windows PowerShell with a base64-encoded payload, so the target's default shell (`cmd`, PowerShell 5.1, or PowerShell 7) does not matter.
- Works with SSH config aliases, custom ports, and `ProxyJump`.
- Reuses identities from the effective SSH config, including existing Ed25519, ECDSA, RSA, and custom key files.
- When discovery finds no usable identity, interactively accepts an existing private key path or creates a new Ed25519 key after confirmation.
- Keeps `-IdentityFile` available for non-interactive and scripted use.
- Idempotent: an existing key is not duplicated, and a key file without a trailing newline is repaired instead of being glued to the new key.
- Verifies key-only login after installation.

## Usage

Interactive, Windows client:

```powershell
irm https://guajun.github.io/ssh-key-installer/install.ps1 | iex
```

Interactive, Termux / macOS / Linux client:

```sh
curl -fsSL https://guajun.github.io/ssh-key-installer/install.sh | sh
```

Download, inspect, and run with options:

```powershell
irm https://guajun.github.io/ssh-key-installer/install.ps1 -OutFile install-ssh-key.ps1
Get-Content .\install-ssh-key.ps1
.\install-ssh-key.ps1 -Destination root@192.168.1.1 -TargetOS Linux
```

```sh
curl -fsSL https://guajun.github.io/ssh-key-installer/install.sh -o install-ssh-key.sh
less install-ssh-key.sh
sh ./install-ssh-key.sh -d root@192.168.1.1 -o linux
```

Windows target through an SSH config jump host:

```powershell
.\install-ssh-key.ps1 -Destination winbox -TargetOS Windows
```

```sh
sh ./install-ssh-key.sh -d winbox -o windows
```

Explicit jump host and port:

```powershell
.\install-ssh-key.ps1 -Destination user@server -TargetOS Linux -Port 2222 -ProxyJump root@jump.example.com
```

```sh
sh ./install-ssh-key.sh -d user@server -o linux -p 2222 -J root@jump.example.com
```

Automatic OS detection makes an additional SSH connection and can therefore ask for the password twice. Pass `-TargetOS Linux`/`-TargetOS Windows` (PowerShell) or `-o linux`/`-o windows` (sh) to skip detection when the target OS is known.

## Why not ssh-copy-id?

`ssh-copy-id` sends a POSIX shell script to the remote host, including a repair step that appends a missing newline:

```sh
{ [ -z "`tail -1c "${AUTH_KEY_FILE}" 2>/dev/null`" ] || echo >> "${AUTH_KEY_FILE}" || exit 1; }
```

On a Windows target whose `sshd` default shell is `cmd`, `test` is unknown, so the `||` branch runs: `echo` without arguments writes `ECHO is on.` (localized, for example `ECHO 处于打开状态。`) straight into `authorized_keys`, and the key itself is never installed. `install-ssh-key.sh` avoids the whole class of problems by sending base64-encoded payloads — a Linux payload decoded by `sh`, and a Windows payload decoded by Windows PowerShell — so no shell ever re-parses quoting.

## Requirements

- Windows client: Windows PowerShell 5.1 or PowerShell 7+, and the Windows OpenSSH Client (`ssh`, `ssh-keygen`)
- POSIX client: a POSIX `sh`, `ssh`, `ssh-keygen`, and `base64`. In Termux: `pkg install openssh coreutils`
- Password or another working authentication method for the remote account
- Linux targets need `base64`, available on standard Linux and OpenWrt systems
- Windows targets need Windows PowerShell and OpenSSH Server

## Security

The one-line commands execute a script downloaded from GitHub Pages. For sensitive environments, use the download-and-inspect workflow above and compare its SHA-256 hash with the release checksum.

The private key never leaves the local computer. Only the public key is sent to the target. Host-key checking remains enabled.

## Releases

Tagged releases attach `install-ssh-key.ps1`, `install-ssh-key.sh`, and `SHA256SUMS.txt`. GitHub Pages always serves the scripts from the default branch as `install.ps1` and `install.sh`.

## License

MIT
