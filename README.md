# SSH Key Installer

Install your Windows SSH public key on a Linux or Windows OpenSSH server with one command.

```powershell
irm https://guajun.github.io/ssh-key-installer/install.ps1 | iex
```

The script prompts for the SSH destination and remote operating system. Password input is handled directly by `ssh`; the script never reads or stores it.

## Features

- Linux targets: safely updates `~/.ssh/authorized_keys` and permissions.
- OpenWrt/Dropbear targets: automatically uses `/etc/dropbear/authorized_keys` for root.
- Windows targets: updates the user key file and, for administrators, `administrators_authorized_keys` with the ACLs required by Windows OpenSSH.
- Works with SSH config aliases, custom ports, and `ProxyJump`.
- Reuses identities from the effective SSH config, including existing Ed25519, ECDSA, RSA, and custom key files.
- Creates a new Ed25519 identity after confirmation only when no usable private key exists.
- Idempotent: an existing key is not duplicated.
- Verifies key-only login after installation.

## Usage

Interactive:

```powershell
irm https://guajun.github.io/ssh-key-installer/install.ps1 | iex
```

Download, inspect, and run with options:

```powershell
irm https://guajun.github.io/ssh-key-installer/install.ps1 -OutFile install-ssh-key.ps1
Get-Content .\install-ssh-key.ps1
.\install-ssh-key.ps1 -Destination root@192.168.1.1 -TargetOS Linux
```

Windows target through an SSH config jump host:

```powershell
.\install-ssh-key.ps1 -Destination winbox -TargetOS Windows
```

Explicit jump host and port:

```powershell
.\install-ssh-key.ps1 -Destination user@server -TargetOS Linux -Port 2222 -ProxyJump root@jump.example.com
```

Use `-TargetOS Auto` only when needed. Detection makes an additional SSH connection and can therefore ask for the password twice.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Windows OpenSSH Client (`ssh` and `ssh-keygen`)
- Password or another working authentication method for the remote account
- Linux targets need `base64`, available on standard Linux and OpenWrt systems
- Windows targets need Windows PowerShell and OpenSSH Server

## Security

The one-line command executes a script downloaded from GitHub Pages. For sensitive environments, use the download-and-inspect workflow above and compare its SHA-256 hash with the release checksum.

The private key never leaves the local computer. Only the public key is sent to the target. Host-key checking remains enabled.

## Releases

Tagged releases attach `install-ssh-key.ps1` and `SHA256SUMS.txt`. GitHub Pages always serves the script from the default branch.

## License

MIT
