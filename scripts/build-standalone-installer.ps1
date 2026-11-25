#Requires -Version 7
<#
.SYNOPSIS
    Builds the TokenSaver MSI and the standalone TokenSaver MCP installer (.exe), and writes
    SHA-256 checksums for both into build/dist/.

.DESCRIPTION
    1. Builds src/Installers/TokenSaver.Setup (WiX) with a numeric MSI version.
    2. Compiles installer/TokenSaverMcp.iss (Inno Setup 6), which bundles that MSI.
    Outputs (build/dist/):
      TokenSaver-Setup-<numeric>.msi
      TokenSaverMCP-Setup-<display>.exe
      SHA256SUMS.txt

    Version: -Version when given (a leading "v" is stripped), otherwise nbgv's NuGetPackageVersion.

.PARAMETER Version
    Display version, e.g. 1.0.49-alpha. The MSI version is its numeric part (1.0.49).

.PARAMETER Configuration
    Build configuration. Default Release.
#>
[CmdletBinding()]
param(
    [string] $Version = "",
    [string] $Configuration = "Release"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$wixProj  = Join-Path $repoRoot "src\Installers\TokenSaver.Setup\TokenSaver.Setup.wixproj"
$issFile  = Join-Path $repoRoot "installer\TokenSaverMcp.iss"
$distDir  = Join-Path $repoRoot "build\dist"

function Invoke-Native([string] $File, [string[]] $Arguments) {
    Write-Host ">> $File $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$File exited with code $LASTEXITCODE" }
}

function Resolve-DisplayVersion {
    if ($Version -ne "") { return $Version -replace '^v', '' }
    if (-not (Get-Command nbgv -ErrorAction SilentlyContinue)) {
        throw "No -Version given and nbgv is not installed. Run: dotnet tool install --global nbgv, or pass -Version."
    }
    $out = & nbgv get-version -v NuGetPackageVersion 2>&1
    if ($LASTEXITCODE -ne 0) { throw "nbgv get-version failed (exit $LASTEXITCODE): $out" }
    return "$out".Trim()
}

$display = Resolve-DisplayVersion
if ($display -notmatch '^(\d+)\.(\d+)(?:\.(\d+))?') {
    throw "Version '$display' does not start with Major.Minor[.Patch]."
}
$patch   = if ($Matches[3]) { $Matches[3] } else { "0" }
$numeric = "$($Matches[1]).$($Matches[2]).$patch"        # MSI product version: three parts
$fourPart = "$numeric.0"                                 # Inno VersionInfoVersion: four parts
Write-Host "TokenSaver MCP installer $display (MSI $numeric), $Configuration" -ForegroundColor Cyan

New-Item -ItemType Directory -Force $distDir | Out-Null

# 1. MSI. The wixproj writes build/dist/TokenSaver-Setup-<MyAppVersion>.msi.
# Rebuild, not build: a stale WiX obj/ folder makes an incremental build skip the MSI (MSB3030).
Invoke-Native dotnet @("build", $wixProj, "-c", $Configuration, "-t:Rebuild", "-p:MyAppVersion=$numeric")
$msi = Join-Path $distDir "TokenSaver-Setup-$numeric.msi"
if (-not (Test-Path $msi)) { throw "Expected MSI not found: $msi" }

# 2. Standalone exe, which bundles that MSI.
$iscc = @(
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "ISCC.exe not found. Install Inno Setup 6 (choco install innosetup)." }

Invoke-Native $iscc @(
    "/Q",
    "/DMyAppVersion=$display",
    "/DMyAppNumericVersion=$fourPart",
    "/DTokenSaverMsi=$msi",
    $issFile
)
$exe = Join-Path $distDir "TokenSaverMCP-Setup-$display.exe"
if (-not (Test-Path $exe)) { throw "Expected installer not found: $exe" }

# 3. Checksums for both assets.
$sums = foreach ($asset in @($exe, $msi) | Sort-Object { Split-Path $_ -Leaf }) {
    "$((Get-FileHash -Path $asset -Algorithm SHA256).Hash.ToLowerInvariant())  $(Split-Path $asset -Leaf)"
}
$sumsPath = Join-Path $distDir "SHA256SUMS.txt"
$sums | Set-Content -Path $sumsPath -Encoding ascii

Write-Host ""
Write-Host "Assets:" -ForegroundColor Green
$sums | ForEach-Object { Write-Host "  $_" }
