$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repositoryRoot 'install-ssh-key.ps1'
$shScriptPath = Join-Path $repositoryRoot 'install-ssh-key.sh'
$readmePath = Join-Path $repositoryRoot 'README.md'
$pagePath = Join-Path $repositoryRoot 'docs\index.html'

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count) {
    throw "PowerShell parse errors:`n$($parseErrors -join "`n")"
}

$script = Get-Content -Raw -LiteralPath $scriptPath
$shScript = Get-Content -Raw -LiteralPath $shScriptPath
$readme = Get-Content -Raw -LiteralPath $readmePath
$page = Get-Content -Raw -LiteralPath $pagePath
$installCommand = 'irm https://guajun.github.io/ssh-key-installer/install.ps1 | iex'
$posixInstallCommand = 'curl -fsSL https://guajun.github.io/ssh-key-installer/install.sh | sh'

if (-not $readme.Contains($installCommand)) {
    throw 'README does not contain the canonical install command.'
}
if (-not $page.Contains($installCommand)) {
    throw 'GitHub Pages does not contain the canonical install command.'
}
if (-not $readme.Contains($posixInstallCommand)) {
    throw 'README does not contain the canonical POSIX install command.'
}
if (-not $page.Contains($posixInstallCommand)) {
    throw 'GitHub Pages does not contain the canonical POSIX install command.'
}
if ($shScript -match "`r") {
    throw 'install-ssh-key.sh must use LF line endings so curl | sh works.'
}
if ($script -match 'IdentityFile\s+\S+\.pub') {
    throw 'The script must never pass a public key path as IdentityFile.'
}
foreach ($marker in @('Find-LocalIdentity', 'Read-IdentityPath', '.ssh\id_rsa', 'SSH_KEY_INSTALLER_OK=Linux', 'SSH_KEY_INSTALLER_OK=Windows', '/etc/dropbear/authorized_keys', 'BatchMode=yes')) {
    if (-not $script.Contains($marker)) {
        throw "Expected behavior marker is missing: $marker"
    }
}
foreach ($marker in @('SSH_KEY_INSTALLER_OK=Linux', 'SSH_KEY_INSTALLER_OK=Windows', '/etc/dropbear/authorized_keys', 'IdentitiesOnly=yes', 'BatchMode=yes', 'FromBase64String', 'administrators_authorized_keys')) {
    if (-not $shScript.Contains($marker)) {
        throw "Expected install-ssh-key.sh marker is missing: $marker"
    }
}
foreach ($marker in @('OpenSSH ignores a key that is glued', 'never join two keys')) {
    if (-not $script.Contains($marker) -and -not $shScript.Contains($marker)) {
        throw "Expected trailing-newline repair marker is missing: $marker"
    }
}
if (-not $script.Contains("[A]uto-detect? [A]'")) {
    throw 'Interactive target OS selection must default to Auto-detect.'
}
if (-not $script.Contains("default  { `$TargetOS = 'Auto' }")) {
    throw 'Empty target OS input must select Auto.'
}

Write-Output 'REPOSITORY_TESTS_OK'
