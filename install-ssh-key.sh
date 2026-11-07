#!/bin/sh
# SSH Key Installer
#
# Installs this machine's SSH public key on a Linux, OpenWrt, or Windows
# OpenSSH server. Intended for Termux, macOS, and Linux clients, where
# ssh-copy-id cannot handle Windows targets.
#
#   curl -fsSL https://guajun.github.io/ssh-key-installer/install.sh | sh
#
# The private key never leaves this machine: only the public key is sent to
# the target, and passwords are read by ssh itself.
set -eu

PROGRAM='SSH Key Installer'
DESTINATION=''
TARGET_OS=''
PORT=''
PROXY_JUMP=''
IDENTITY=''

if [ -t 2 ]; then
    COLOR_STEP=$(printf '\033[36m')
    COLOR_WARN=$(printf '\033[33m')
    COLOR_OK=$(printf '\033[32m')
    COLOR_OFF=$(printf '\033[0m')
else
    COLOR_STEP=''
    COLOR_WARN=''
    COLOR_OK=''
    COLOR_OFF=''
fi

usage() {
    cat <<'EOF'
Install this machine's SSH public key on a Linux, OpenWrt, or Windows server.

Usage: install-ssh-key.sh [options]

  -d DESTINATION   SSH destination, for example root@192.168.1.1 or a Host alias
  -o OS            target OS: linux, windows, or auto (default: ask)
  -p PORT          SSH port (default: SSH config, otherwise 22)
  -J JUMP          ProxyJump destination
  -i IDENTITY      private key to use (default: discover from the SSH config)
  -h               show this help

The script prompts for anything it still needs. See also install-ssh-key.ps1 for
Windows clients.
EOF
}

step() { printf '\n%s==> %s%s\n' "$COLOR_STEP" "$1" "$COLOR_OFF" >&2; }
warn() { printf '%s%s%s\n' "$COLOR_WARN" "$1" "$COLOR_OFF" >&2; }
say() { printf '%s\n' "$1" >&2; }
die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# Reads one line from the terminal even when the script itself arrived on stdin.
ask() {
    printf '%s' "$1" >&2
    if ( : < /dev/tty ) 2>/dev/null; then
        IFS= read -r _answer < /dev/tty || _answer=''
    else
        IFS= read -r _answer || _answer=''
    fi
    printf '%s' "$_answer"
}

while getopts ':d:o:p:J:i:h' option; do
    case $option in
        d) DESTINATION=$OPTARG ;;
        o) TARGET_OS=$OPTARG ;;
        p) PORT=$OPTARG ;;
        J) PROXY_JUMP=$OPTARG ;;
        i) IDENTITY=$OPTARG ;;
        h) usage; exit 0 ;;
        :) die "option -$OPTARG requires a value" ;;
        *) usage >&2; exit 2 ;;
    esac
done

case $TARGET_OS in
    '') TARGET_OS='' ;;
    auto|Auto|AUTO) TARGET_OS='Auto' ;;
    linux|Linux|LINUX) TARGET_OS='Linux' ;;
    windows|Windows|WINDOWS) TARGET_OS='Windows' ;;
    *) die "unsupported target OS: $TARGET_OS (use linux, windows, or auto)" ;;
esac

if [ -n "$PORT" ]; then
    case $PORT in
        *[!0-9]*) die "invalid port: $PORT" ;;
    esac
    if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        die "invalid port: $PORT"
    fi
fi

for tool in ssh ssh-keygen base64; do
    command -v "$tool" >/dev/null 2>&1 || die "'$tool' was not found. Install the OpenSSH client first."
done

if [ -z "$DESTINATION" ]; then
    DESTINATION=$(ask 'SSH destination (for example root@192.168.1.1 or a Host alias): ')
fi
case $DESTINATION in
    '') die 'a destination is required' ;;
    *[[:space:]]*) die 'destination must not contain spaces' ;;
esac

if [ -z "$TARGET_OS" ]; then
    answer=$(ask 'Remote OS: [L]inux, [W]indows, or [A]uto-detect? [A] ')
    case $answer in
        w|W|windows|Windows) TARGET_OS='Windows' ;;
        l|L|linux|Linux) TARGET_OS='Linux' ;;
        *) TARGET_OS='Auto' ;;
    esac
fi

resolve_identity_path() {
    _path=$1
    case $_path in
        \"*\") _path=${_path#\"}; _path=${_path%\"} ;;
    esac
    case $_path in
        '~') _path=$HOME ;;
        '~/'*) _path="$HOME/${_path#\~/}" ;;
    esac
    printf '%s' "$_path"
}

ssh_with_options() {
    if [ -n "$PORT" ]; then
        set -- -p "$PORT" "$@"
    fi
    if [ -n "$PROXY_JUMP" ]; then
        set -- -J "$PROXY_JUMP" "$@"
    fi
    ssh "$@"
}

effective_ssh_config() {
    ssh_with_options -G "$DESTINATION" </dev/null 2>/dev/null || true
}

find_identity() {
    _candidates=$(effective_ssh_config | awk 'tolower($1) == "identityfile" { sub(/^[^ \t]+[ \t]+/, ""); print }')
    _candidates="$_candidates
$HOME/.ssh/id_ed25519
$HOME/.ssh/id_ecdsa
$HOME/.ssh/id_rsa"

    _previous_ifs=$IFS
    IFS='
'
    set -f
    for _candidate in $_candidates; do
        case $_candidate in
            ''|none|*.pub) continue ;;
        esac
        _resolved=$(resolve_identity_path "$_candidate")
        if [ -f "$_resolved" ]; then
            IFS=$_previous_ifs
            set +f
            printf '%s' "$_resolved"
            return 0
        fi
    done
    IFS=$_previous_ifs
    set +f

    _default="$HOME/.ssh/id_ed25519"
    warn "No usable SSH private key was found in the effective SSH config or '$HOME/.ssh'."
    while :; do
        _answer=$(ask "Existing private key path (press Enter to create '$_default'): ")
        if [ -z "$_answer" ]; then
            printf '%s' "$_default"
            return 0
        fi
        _resolved=$(resolve_identity_path "$_answer")
        case $_resolved in
            *.pub) _resolved=${_resolved%.pub} ;;
        esac
        if [ -f "$_resolved" ]; then
            printf '%s' "$_resolved"
            return 0
        fi
        warn "Private key not found: $_resolved"
    done
}

if [ -n "$IDENTITY" ]; then
    IDENTITY=$(resolve_identity_path "$IDENTITY")
else
    IDENTITY=$(find_identity)
fi

case $IDENTITY in
    *.pub)
        _private=${IDENTITY%.pub}
        if [ -f "$_private" ]; then
            say "Using the private key that matches '$IDENTITY'."
        fi
        IDENTITY=$_private
        ;;
esac

PUBLIC_KEY_PATH="$IDENTITY.pub"
KEY_DIRECTORY=$(dirname "$IDENTITY")

[ -d "$KEY_DIRECTORY" ] || mkdir -p "$KEY_DIRECTORY"

if [ ! -f "$IDENTITY" ]; then
    _answer=$(ask "No SSH key exists at '$IDENTITY'. Create an Ed25519 key now? [Y/n] ")
    case $_answer in
        ''|y|Y|yes|YES|Yes) ;;
        *) die 'a local SSH identity is required' ;;
    esac

    step 'Creating a local Ed25519 identity'
    say 'ssh-keygen will now ask for an optional passphrase. Press Enter twice for no passphrase.'
    ssh-keygen -t ed25519 -f "$IDENTITY" || die "ssh-keygen failed with exit code $?"
fi

if [ ! -f "$PUBLIC_KEY_PATH" ]; then
    step 'Rebuilding the missing public key'
    ssh-keygen -y -f "$IDENTITY" > "$PUBLIC_KEY_PATH" || die "could not read the private key at '$IDENTITY'"
fi

PUBLIC_KEY=$(tr -d '\r' < "$PUBLIC_KEY_PATH" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
case $PUBLIC_KEY in
    ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *|ssh-dss\ *) ;;
    *) die "'$PUBLIC_KEY_PATH' does not contain a supported OpenSSH public key" ;;
esac

run_ssh() {
    ssh_with_options -i "$IDENTITY" -o IdentitiesOnly=yes "$DESTINATION" "$1"
}

verify_ssh() {
    ssh_with_options -i "$IDENTITY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 "$DESTINATION" 'echo SSH_KEY_LOGIN_OK' </dev/null
}

detect_target_os() {
    step 'Detecting the remote operating system (this may ask for the password once)'
    # cmd expands %OS%; PowerShell expands $env:OS; only one of them is meaningful.
    # ssh must not consume the remaining installer when invoked as curl | sh.
    _probe=$(run_ssh 'echo __SSH_KEY_INSTALLER_OS__%OS%__$env:OS' </dev/null 2>&1) || {
        say "$_probe"
        die 'could not detect the remote operating system'
    }
    case $_probe in
        *Windows_NT*) printf '%s' 'Windows' ;;
        *) printf '%s' 'Linux' ;;
    esac
}

install_linux_key() {
    # The remote script is base64 encoded so no Windows or POSIX quoting can
    # mangle it; base64 is available on standard Linux and OpenWrt.
    _key_b64=$(printf '%s' "$PUBLIC_KEY" | base64 | tr -d '\n')
    _script=$(cat <<EOF
set -eu
umask 077
key=\$(printf '%s' '$_key_b64' | base64 -d)
if [ "\$(id -u)" = '0' ] && { [ -d /etc/dropbear ] || command -v dropbear >/dev/null 2>&1; }; then
    key_dir=/etc/dropbear
    key_file=/etc/dropbear/authorized_keys
else
    key_dir="\$HOME/.ssh"
    key_file="\$HOME/.ssh/authorized_keys"
fi
mkdir -p "\$key_dir"
touch "\$key_file"
chmod 700 "\$key_dir"
chmod 600 "\$key_file"
if ! grep -qxF "\$key" "\$key_file"; then
    if [ -s "\$key_file" ] && [ -n "\$(tail -c 1 "\$key_file")" ]; then
        printf '\n' >> "\$key_file"
    fi
    printf '%s\n' "\$key" >> "\$key_file"
fi
printf '%s\n' 'SSH_KEY_INSTALLER_OK=Linux'
printf 'SSH_KEY_INSTALLER_PATH=%s\n' "\$key_file"
EOF
)
    _script_b64=$(printf '%s\n' "$_script" | base64 | tr -d '\n')
    run_ssh "echo $_script_b64|base64 -d|sh" </dev/null || die "SSH failed with exit code $?"
}

build_windows_script() {
    _key_b64=$(printf '%s' "$PUBLIC_KEY" | base64 | tr -d '\n')
    cat <<'PSEOF'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$key = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('@@KEY_BASE64@@'))

function Add-SshKey([string]$Path) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $text = if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { '' }
    if ($text.Contains($key)) {
        Write-Output "SSH_KEY_INSTALLER_EXISTING=$Path"
        return
    }
    # OpenSSH ignores a trailing newline-free line, so never join two keys together.
    if ($text -and -not $text.EndsWith("`n")) { $text += "`n" }
    [IO.File]::WriteAllText($Path, $text + $key + "`n")
    Write-Output "SSH_KEY_INSTALLER_ADDED=$Path"
}

$userAuth = Join-Path $env:USERPROFILE '.ssh\authorized_keys'
Add-SshKey $userAuth
& icacls.exe (Split-Path -Parent $userAuth) /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
& icacls.exe $userAuth /inheritance:r /grant:r "${env:USERNAME}:F" '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null

$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $adminAuth = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
    Add-SshKey $adminAuth
    & icacls.exe $adminAuth /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
}

Write-Output 'SSH_KEY_INSTALLER_OK=Windows'
PSEOF
}

install_windows_key() {
    # Windows PowerShell 5.1 is always present on OpenSSH for Windows targets.
    # The script is streamed on stdin instead of the command line: the target's
    # default shell (cmd, PowerShell 5.1, or PowerShell 7) would otherwise strip
    # quotes from a -Command argument, and PowerShell 7 rewrites native arguments
    # anyway. "-Command -" has no quoting to get wrong.
    _script=$(build_windows_script | sed "s|@@KEY_BASE64@@|$(printf '%s' "$PUBLIC_KEY" | base64 | tr -d '\n')|")
    printf '%s\n' "$_script" | run_ssh 'powershell.exe -NoLogo -NonInteractive -NoProfile -Command -' \
        || die "SSH failed with exit code $?"
}

if [ "$TARGET_OS" = 'Auto' ] || [ -z "$TARGET_OS" ]; then
    TARGET_OS=$(detect_target_os)
    say "Detected remote OS: $TARGET_OS"
fi

say ''
say "Local key: $PUBLIC_KEY_PATH"
say "Fingerprint: $(ssh-keygen -lf "$PUBLIC_KEY_PATH")"
say "Target: $DESTINATION ($TARGET_OS)"

step "Installing the public key on $TARGET_OS"
if [ "$TARGET_OS" = 'Windows' ]; then
    install_windows_key
else
    install_linux_key
fi

step 'Verifying key-only login'
verify_ssh >/dev/null 2>&1 || die 'key-only login verification failed'

printf '\n%sDone. Key login is working:%s\n' "$COLOR_OK" "$COLOR_OFF" >&2
printf 'ssh %s\n' "$DESTINATION" >&2
