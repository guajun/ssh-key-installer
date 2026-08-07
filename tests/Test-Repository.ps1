$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repositoryRoot 'install-ssh-key.ps1'
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
$readme = Get-Content -Raw -LiteralPath $readmePath
$page = Get-Content -Raw -LiteralPath $pagePath
$installCommand = 'irm https://guajun.github.io/ssh-key-installer/install.ps1 | iex'

if (-not $readme.Contains($installCommand)) {
    throw 'README does not contain the canonical install command.'
}
if (-not $page.Contains($installCommand)) {
    throw 'GitHub Pages does not contain the canonical install command.'
}
if ($script -match 'IdentityFile\s+\S+\.pub') {
    throw 'The script must never pass a public key path as IdentityFile.'
}
foreach ($marker in @('Find-LocalIdentity', '.ssh\id_rsa', 'SSH_KEY_INSTALLER_OK=Linux', 'SSH_KEY_INSTALLER_OK=Windows', '/etc/dropbear/authorized_keys', 'BatchMode=yes')) {
    if (-not $script.Contains($marker)) {
        throw "Expected behavior marker is missing: $marker"
    }
}

Write-Output 'REPOSITORY_TESTS_OK'
