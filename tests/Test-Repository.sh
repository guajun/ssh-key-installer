#!/bin/sh
# POSIX repository checks. Mirrors tests/Test-Repository.ps1 and additionally
# exercises install-ssh-key.sh end to end with a stub ssh client.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
sh_script="$root/install-ssh-key.sh"
ps1_script="$root/install-ssh-key.ps1"
readme="$root/README.md"
page="$root/docs/index.html"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[ -f "$sh_script" ] || fail 'install-ssh-key.sh is missing'
[ -f "$ps1_script" ] || fail 'install-ssh-key.ps1 is missing'

sh -n "$sh_script" || fail 'install-ssh-key.sh has shell syntax errors'
if command -v dash >/dev/null 2>&1; then
    dash -n "$sh_script" || fail 'install-ssh-key.sh is not POSIX sh'
fi
if grep -q "$(printf '\r')" "$sh_script"; then
    fail 'install-ssh-key.sh must use LF line endings so curl | sh works'
fi

canonical_powershell='irm https://guajun.github.io/ssh-key-installer/install.ps1 | iex'
canonical_posix='curl -fsSL https://guajun.github.io/ssh-key-installer/install.sh | sh'

grep -qF "$canonical_powershell" "$readme" || fail 'README is missing the PowerShell install command'
grep -qF "$canonical_posix" "$readme" || fail 'README is missing the POSIX install command'
grep -qF "$canonical_powershell" "$page" || fail 'GitHub Pages is missing the PowerShell install command'
grep -qF "$canonical_posix" "$page" || fail 'GitHub Pages is missing the POSIX install command'

for marker in \
    'SSH_KEY_INSTALLER_OK=Linux' \
    'SSH_KEY_INSTALLER_OK=Windows' \
    '/etc/dropbear/authorized_keys' \
    'IdentitiesOnly=yes' \
    'BatchMode=yes' \
    'FromBase64String' \
    'administrators_authorized_keys' \
    'neither cmd nor PowerShell'
do
    grep -qF "$marker" "$sh_script" || fail "install-ssh-key.sh is missing marker: $marker"
done

if grep -q -E 'IdentityFile[[:space:]]+[^[:space:]]+\.pub' "$sh_script"; then
    fail 'install-ssh-key.sh must never pass a public key path as IdentityFile'
fi

printf 'Repository checks passed\n'

# --- behaviour check with a stub ssh client -------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/bin" "$tmp/home/.ssh"
ssh-keygen -q -t ed25519 -N '' -C 'test@installer' -f "$tmp/home/.ssh/id_ed25519" \
    || fail 'could not create a throwaway key for the behaviour check'

cat > "$tmp/bin/ssh" <<'STUB'
#!/bin/sh
if [ "$1" = "-G" ]; then
    printf 'hostname stub.invalid\n'
    printf 'identityfile %s\n' "$STUB_IDENTITY"
    exit 0
fi
last=''
for argument in "$@"; do
    last=$argument
done
printf '%s\n' "$last" >> "$STUB_LOG"
printf 'SSH_KEY_LOGIN_OK\n'
exit 0
STUB
chmod +x "$tmp/bin/ssh"

export STUB_IDENTITY="$tmp/home/.ssh/id_ed25519"
export STUB_LOG="$tmp/calls.log"
export HOME="$tmp/home"
export PATH="$tmp/bin:$PATH"

sh "$sh_script" -d test@stub -o windows >/dev/null 2>&1 || fail 'install-ssh-key.sh failed for a Windows target'
sh "$sh_script" -d test@stub -o linux >/dev/null 2>&1 || fail 'install-ssh-key.sh failed for a Linux target'

expected_key=$(tr -d '\r' < "$tmp/home/.ssh/id_ed25519.pub")

windows_command=$(grep -F 'FromBase64String' "$STUB_LOG" | head -1)
windows_payload=$(printf '%s' "$windows_command" | sed -nE "s/.*FromBase64String\('([^']+)'\).*/\1/p")
[ -n "$windows_payload" ] || fail 'the Windows payload is not a base64 argument'

printf '%s' "$windows_payload" | base64 -d > "$tmp/windows.ps1" 2>/dev/null \
    || fail 'the Windows payload is not valid base64'
grep -qF 'SSH_KEY_INSTALLER_OK=Windows' "$tmp/windows.ps1" || fail 'the Windows payload lost its completion marker'
if printf '%s' "$windows_command" | grep -q '\$'; then
    fail 'the Windows remote command must not contain $, which shells would expand'
fi

path_argument=$(grep -F 'authorized_keys' "$tmp/windows.ps1" | head -1)
[ -n "$path_argument" ] || fail 'the Windows payload does not touch authorized_keys'

linux_command=$(grep -F 'base64 -d|sh' "$STUB_LOG" | head -1)
linux_payload=$(printf '%s' "$linux_command" | sed -nE 's/^echo ([A-Za-z0-9+/=]+)\|base64 -d\|sh$/\1/p')
[ -n "$linux_payload" ] || fail 'the Linux payload is not a base64 sh command'

printf '%s' "$linux_payload" | base64 -d > "$tmp/linux.sh" 2>/dev/null \
    || fail 'the Linux payload is not valid base64'
sh -n "$tmp/linux.sh" || fail 'the Linux payload is not valid shell'
grep -qF 'SSH_KEY_INSTALLER_OK=Linux' "$tmp/linux.sh" || fail 'the Linux payload lost its completion marker'

embedded_key=$(printf '%s' "$linux_payload" | base64 -d | sed -nE "s/.*printf '%s' '([A-Za-z0-9+/=]+)' \| base64 -d.*/\1/p")
[ -n "$embedded_key" ] || fail 'the Linux payload does not embed a base64 key'
if [ "$(printf '%s' "$embedded_key" | base64 -d)" != "$expected_key" ]; then
    fail 'the Linux payload does not carry the public key of the local identity'
fi

printf 'Behaviour checks passed\n'
printf 'POSIX_TESTS_OK\n'
