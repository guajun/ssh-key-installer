#requires -Version 5.1
<#
.SYNOPSIS
Installs this computer's SSH public key on a Linux or Windows SSH server.

.EXAMPLE
.\install-ssh-key.ps1 -Destination root@192.168.1.1 -TargetOS Linux

.EXAMPLE
.\install-ssh-key.ps1 -Destination winbox -TargetOS Windows -ProxyJump jumpbox
#>
[CmdletBinding()]
param(
    [string]$Destination,

    [ValidateSet('', 'Auto', 'Linux', 'Windows')]
    [string]$TargetOS = '',

    [ValidateRange(1, 65535)]
    [int]$Port = 22,

    [string]$ProxyJump,

    [string]$IdentityFile = (Join-Path $HOME '.ssh\id_ed25519')
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Resolve-IdentityPath([string]$Path) {
    if ($Path.StartsWith('~')) {
        return Join-Path $HOME $Path.Substring(1).TrimStart('\', '/')
    }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Ensure-LocalIdentity([string]$PrivateKeyPath) {
    $publicKeyPath = "$PrivateKeyPath.pub"
    $keyDirectory = Split-Path -Parent $PrivateKeyPath

    if (-not (Test-Path -LiteralPath $keyDirectory)) {
        New-Item -ItemType Directory -Force -Path $keyDirectory | Out-Null
    }

    if (-not (Test-Path -LiteralPath $PrivateKeyPath)) {
        $answer = Read-Host "No SSH key exists at '$PrivateKeyPath'. Create an Ed25519 key now? [Y/n]"
        if ($answer -and $answer -notmatch '^(?i)y(?:es)?$') {
            throw 'A local SSH identity is required.'
        }

        Write-Step 'Creating a local Ed25519 identity'
        Write-Host 'ssh-keygen will now ask for an optional passphrase. Press Enter twice for no passphrase.'
        & ssh-keygen -t ed25519 -f $PrivateKeyPath
        if ($LASTEXITCODE -ne 0) {
            throw "ssh-keygen failed with exit code $LASTEXITCODE."
        }
    }

    if (-not (Test-Path -LiteralPath $publicKeyPath)) {
        Write-Step 'Rebuilding the missing public key'
        $publicKey = & ssh-keygen -y -f $PrivateKeyPath
        if ($LASTEXITCODE -ne 0) {
            throw "Could not read the private key at '$PrivateKeyPath'."
        }
        Set-Content -LiteralPath $publicKeyPath -Value $publicKey -Encoding ascii
    }

    $key = (Get-Content -Raw -LiteralPath $publicKeyPath).Trim()
    if ($key -notmatch '^ssh-(ed25519|rsa|ecdsa-|dss)\s+\S+') {
        throw "'$publicKeyPath' does not contain a supported OpenSSH public key."
    }

    return [pscustomobject]@{
        Private = $PrivateKeyPath
        Public  = $publicKeyPath
        Key     = $key
    }
}

function New-SshArguments([string]$PrivateKeyPath) {
    $arguments = @(
        '-p', $Port.ToString(),
        '-i', $PrivateKeyPath,
        '-o', 'IdentitiesOnly=yes'
    )

    if ($ProxyJump) {
        $arguments += @('-J', $ProxyJump)
    }

    return $arguments
}

function Invoke-Ssh([string[]]$Arguments, [string]$RemoteCommand) {
    & ssh @Arguments $Destination $RemoteCommand
    if ($LASTEXITCODE -ne 0) {
        throw "SSH failed with exit code $LASTEXITCODE."
    }
}

function Get-TargetOS([string[]]$SshArguments) {
    Write-Step 'Detecting the remote operating system (this may ask for the password once)'
    $probe = & ssh @SshArguments $Destination 'echo __SSH_KEY_INSTALLER_OS__%OS%__$env:OS' 2>&1
    if ($LASTEXITCODE -ne 0) {
        $probe | Write-Host
        throw "Could not detect the remote operating system (SSH exit code $LASTEXITCODE)."
    }
    if (($probe -join "`n") -match 'Windows_NT') {
        return 'Windows'
    }
    return 'Linux'
}

function Install-LinuxKey([string[]]$SshArguments, [string]$PublicKey) {
    $keyBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($PublicKey))
    $remoteScript = @"
set -eu
umask 077
key=`$(printf '%s' '$keyBase64' | base64 -d)
mkdir -p "`$HOME/.ssh"
touch "`$HOME/.ssh/authorized_keys"
chmod 700 "`$HOME/.ssh"
chmod 600 "`$HOME/.ssh/authorized_keys"
grep -qxF "`$key" "`$HOME/.ssh/authorized_keys" || printf '%s\n' "`$key" >> "`$HOME/.ssh/authorized_keys"
printf '%s\n' 'SSH_KEY_INSTALLER_OK=Linux'
"@
    # Encoding the complete script avoids Windows-to-POSIX command-line quoting differences.
    $scriptBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteScript))
    Invoke-Ssh $SshArguments "echo $scriptBase64|base64 -d|sh"
}

function Install-WindowsKey([string[]]$SshArguments, [string]$PublicKey) {
    $escapedKey = $PublicKey.Replace("'", "''")
    $remoteScript = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
`$key = '$escapedKey'

function Add-SshKey([string]`$Path) {
    `$parent = Split-Path -Parent `$Path
    New-Item -ItemType Directory -Force -Path `$parent | Out-Null
    if (-not (Test-Path -LiteralPath `$Path)) {
        New-Item -ItemType File -Force -Path `$Path | Out-Null
    }
    `$lines = @(Get-Content -LiteralPath `$Path -ErrorAction SilentlyContinue)
    if (`$lines -notcontains `$key) {
        Add-Content -LiteralPath `$Path -Value `$key -Encoding ascii
    }
}

`$userAuth = Join-Path `$env:USERPROFILE '.ssh\authorized_keys'
Add-SshKey `$userAuth
& icacls.exe (Split-Path -Parent `$userAuth) /inheritance:r /grant:r "`${env:USERNAME}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
& icacls.exe `$userAuth /inheritance:r /grant:r "`${env:USERNAME}:F" '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null

`$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (`$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    `$adminAuth = Join-Path `$env:ProgramData 'ssh\administrators_authorized_keys'
    Add-SshKey `$adminAuth
    & icacls.exe `$adminAuth /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
}

Write-Output 'SSH_KEY_INSTALLER_OK=Windows'
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remoteScript))
    Invoke-Ssh $SshArguments "powershell.exe -NoLogo -NonInteractive -NoProfile -EncodedCommand $encoded"
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    throw 'OpenSSH client (ssh) was not found. Install the Windows OpenSSH Client optional feature first.'
}
if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
    throw 'ssh-keygen was not found. Install the Windows OpenSSH Client optional feature first.'
}

if (-not $Destination) {
    $Destination = Read-Host 'SSH destination (for example root@192.168.1.1 or a Host alias)'
}
if (-not $Destination -or $Destination -match '\s') {
    throw 'Destination must be a non-empty SSH destination without spaces.'
}

if (-not $TargetOS) {
    $choice = Read-Host 'Remote OS: [L]inux, [W]indows, or [A]uto-detect? [L]'
    switch -Regex ($choice) {
        '^(?i)w' { $TargetOS = 'Windows' }
        '^(?i)a' { $TargetOS = 'Auto' }
        default  { $TargetOS = 'Linux' }
    }
}

$IdentityFile = Resolve-IdentityPath $IdentityFile
$identity = Ensure-LocalIdentity $IdentityFile
$sshArguments = New-SshArguments $identity.Private

if ($TargetOS -eq 'Auto') {
    $TargetOS = Get-TargetOS $sshArguments
    Write-Host "Detected remote OS: $TargetOS"
}

$fingerprint = (& ssh-keygen -lf $identity.Public 2>$null) -join ' '
Write-Host "`nLocal key: $($identity.Public)"
Write-Host "Fingerprint: $fingerprint"
Write-Host "Target: $Destination ($TargetOS)"

Write-Step "Installing the public key on $TargetOS"
if ($TargetOS -eq 'Windows') {
    Install-WindowsKey $sshArguments $identity.Key
} else {
    Install-LinuxKey $sshArguments $identity.Key
}

Write-Step 'Verifying key-only login'
$verifyArguments = $sshArguments + @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10')
Invoke-Ssh $verifyArguments 'echo SSH_KEY_LOGIN_OK'

Write-Host "`nDone. Key login is working:" -ForegroundColor Green
Write-Host "ssh $Destination"
